# STREAM

Running work log, newest first. Timestamp · what · why · if-interrupted-here.

---

## 2026-08-12 — Task 4 (benchmark harness and baseline) complete

**What:** Added `bin/bench/measure.sh` (measures one `.app`: on-disk size, `lipo`
archs, rpath/loader_path dylib count on the main executable, and — only if
Gatekeeper accepts the bundle — launch-to-responsive time and RSS via a
bounded `osascript` Apple Event poll) and `bin/bench/baseline.sh` (downloads
`v2.0.23` from `textmate/textmate` and `v2.1.4-undead` from
`textmatelives/textmate`, extracts whichever of `.tbz`/`.zip`/`.dmg` was
published, measures both). Ran it and recorded the result in
`docs/benchmarks/2026-08-12-baseline.md`: official 38496 KB / x86_64+arm64 /
0 rpath dylibs / 699ms / 130MB RSS; undead 27928 KB / arm64 / 0 rpath dylibs
/ 661ms / 141MB RSS. Both releases turned out to be Developer ID-signed and
notarized, so both were actually launched (per `spctl --assess`) rather than
static-only — full assessment output is in the task-4 report under
`.superpowers/sdd/2026-08-12-phase-0-baseline-and-hygiene/`.

Corrected several bugs found by actually running the draft scripts, not just
reading them: (1) `osascript` blocks indefinitely rather than failing fast
when Automation/TCC permission is unavailable non-interactively — added a
per-call watchdog (kill the actual `osascript` pid after a few seconds),
written to stay `set -e`-safe (`wait $pid || rc=$?`, not a bare `wait`
that would abort the script before its exit code is captured); (2) `ps -o
rss= -p ''` on an empty pid prints uninitialized memory as its error text,
which isn't valid UTF-8 and crashed Python's `text=True` decode — guarded
so an unfound process reports `n/a` instead of crashing; (3) macOS's own
default `$TMPDIR` ends in a trailing slash, so `baseline.sh`'s original
`"${TMPDIR:-/tmp}/tmr-baseline"` produced a doubled slash that `pgrep -f`
(matching that path as a literal substring) could never match against the
kernel-normalized single-slash path in a real process's command line —
every default-environment run would have silently lost RSS; fixed by
stripping the trailing slash before joining; (4) a single timed launch
right after fresh extraction measures Gatekeeper's first-run verification
plus a cold page cache, not steady state — added a discarded warm-up
launch+quit before the timed one so the required "second launch onward"
methodology is actually true of the recorded numbers, not just asserted in
prose. Also found and documented, without silently fixing or hiding it: the
rpath-dylib-count metric reads 0 for both builds because neither shipped
bundle contains any `.framework`/`.dylib` at all — this repo's ~45
`Frameworks/` modules are already fully statically linked into each
executable, so Phase 7's "measurable improvement on rpath dylib count"
claim doesn't have a nonzero baseline to move against as currently scoped.

**Why:** the project's entire "faster and smaller" claim is unverifiable
without an honest, reproducible baseline that Phase 3 and Phase 7 get
judged against — a script that silently degrades (crashes, hangs, or
measures the wrong thing without saying so) would make later phases compare
against noise instead of fact. Fixing bugs found by execution rather than
inspection, and reporting the ones that reshape what a later phase can
claim (the rpath-dylib finding) rather than smoothing them over, is the
actual point of this task.

### If interrupted here

Task 4 committed, nothing left in progress. Both downloaded `.app` bundles
and all extraction happened under the session scratch directory only —
nothing was installed to `/Applications`, no Gatekeeper bypass was used, and
both launched apps were quit and confirmed not running before the commit.
Next: Task 5 (2021-tree compile check) per
`docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md` — note
this baseline was taken against *released* binaries specifically because
Task 5 had not yet determined whether the 2021 source tree still compiles
under current clang.

---

## 2026-08-12 — Task 3 (upstream fork remotes verified) complete

**What:** Added four remotes (`upstream` → textmate/textmate, `textmatelives`, `gs1469` →
schriftgestalt/textmate, `tectiv3`) and ran `git fetch --all --prune`, pulling full
histories for all three forks plus canonical upstream. Confirmed the branch names the
plan assumes actually exist: `textmatelives/main` (not `master`, though that also
exists), `gs1469/master`, `tectiv3/develop`. Verified shared history with all three forks
using the symmetric form, `git merge-base HEAD <remote>/<branch> >/dev/null` — all three
printed their `OK` line. The brief's original textmatelives check used the asymmetric
`git merge-base --is-ancestor $(git rev-parse HEAD) textmatelives/main`, which asks
whether our HEAD is contained in their history — true only while HEAD sat on pristine
`346b52b1`, structurally unable to pass once our branch carries its own commits (it now
has 6, from Tasks 1-2). Caught this, stopped rather than substitute a passing command,
reported it; the plan's Step 2 was corrected to the symmetric form and re-run verbatim
to confirm. Divergence, measured with `git rev-list --count`: textmatelives 130 ahead,
gs1469 74 ahead, tectiv3 231 ahead.

The tectiv3 number is the significant finding: the plan's ~100 recon estimate came from
`gh pr view --json commits` on PR #1467, and GitHub's API caps how many commits it
returns for a PR's commit list — 231 is the true, authoritative branch divergence.
Two consequences: PR #1467 is actually the **largest** of the three forks by commit
count, not the middle one as recon assumed; and PR metadata must not be trusted for
magnitude going forward — `git rev-list --count` (or an equivalent local git measurement)
is the authority, not the GitHub API's commit list.

**Why:** Phases 1-3 merge and cherry-pick from these three forks; verifying they share
real history with us is the assumption the entire plan rests on, so confirming it (not
just adding the remotes) was the actual deliverable. Getting the divergence magnitude
right matters directly for Phase 1-3 effort estimates, especially now that tectiv3 —
previously assumed mid-sized — is known to be the largest port.

### If interrupted here

Task 3 committed, nothing left in progress. All four remotes stay fetched locally
(no need to re-fetch large histories). No merge, rebase, cherry-pick, or checkout was
performed against any of them — this task only added and verified remotes, per
constraints. Next: Phase 0 Task 4 (benchmark harness and baseline) per
`docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md`.

---

## 2026-08-12 — Task 2 (CI repository guard on build.yml) complete

**What:** Added `if: github.repository == 'sdenike/textmate'` as the first key of the `build` job
in `.github/workflows/build.yml`, immediately before `runs-on`, matching the guard idiom Task 1
established in `gitleaks.yml`. `build.yml` has exactly one job, so it's the only one that needed
it. No other change — the workflow still brew-installs boost/capnp/sparsehash/multimarkdown/
ninja/ragel and runs `./configure && ninja TextMate` on `macOS-latest`, unmodified. Verified the
YAML parses and the job's `if` is non-`None` with the exact `python3 -c "import yaml..."` command
from the task brief, run inside a throwaway venv (system Homebrew python3 has no `yaml` module
and is externally managed; used a scratch venv rather than `pip install --break-system-packages`).

**Why:** CI must never run Actions on forks or private clones of this public repo. `build.yml`
predates that control; this closes the gap the same way `gitleaks.yml` already does. Deliberately
did not fix, modernize, or otherwise touch the 2021-era build steps — attempting that build and
recording what breaks is Task 5's job, not this one's.

### If interrupted here

Task 2 committed, nothing left in progress. Next: Phase 0 Task 3 per
`docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md`.

---

## 2026-08-12 — Task 1 fix round 3/5: suppress the one pre-existing finding by fingerprint

**What:** Round 2 verdicted all three items ADDRESSED. One item remained: the pre-existing
finding disclosed at the end of round 2 (2012 upstream commit `3c79f275`,
`Frameworks/OakTextView/src/OakDocumentView.mm:130`, rule `generic-api-key`, matching
`kSettingsThemeKey`'s theme UUID constant — a confirmed false positive). With `schedule`/
`workflow_dispatch` now the only full-history triggers (round 1), this was going to turn CI red
on the first scheduled run and stay red, training everyone to ignore it — defeating the control.

Verified the suppression mechanism before using it, against gitleaks 8.30.1 itself, not memory:
`gitleaks --help` confirms `-i/--gitleaks-ignore-path` (default `.`); gitleaks' own README
documents `.gitleaksignore` fingerprint suppression; read the actual Go source
(`detect/detect.go`) and confirmed `AddGitleaksIgnore` skips `#`-comment and blank lines, and
`AddFinding` builds a commit-scoped fingerprint as exactly `commit:file:rule-id:start-line` and
checks it verbatim against the ignore set — i.e. scope is precisely commit+file+rule+line, not
path- or rule-wide. Added `.gitleaksignore` at repo root with a `#`-comment block recording the
finding, why it's a false positive, and the upstream date, followed by the one fingerprint line.

**Proved it, twice.** (1) Re-ran the exact command the CI `schedule`/`workflow_dispatch` path
runs (`gitleaks detect --redact -v --exit-code=2 --report-format=sarif
--report-path=results.sarif --log-level=debug`, no `--log-opts`, so still full history — same
5684/5685-commit scope as before): debug log shows `found .gitleaksignore file` and `skipping
finding: fingerprint ...3c79f275...generic-api-key:130`, ending in `no leaks found`, exit **0**.
(2) Confirmed the suppression isn't overbroad: planted a fresh throwaway ed25519 key
(`ssh-keygen` → `canary.pem`) in a real throwaway commit (`--no-verify`, since this test targets
the full-history *CI* scan, not the pre-commit hook, and needed the secret to actually exist in
history — explained in the report), re-ran the identical command: caught it immediately, exit
**2**, a completely different fingerprint (`...canary.pem:private-key:1`). Suppression is scoped
exactly as intended — a new secret is still caught, the old false positive is not. Destroyed the
test commit completely: `git reset --soft HEAD~1`, unstaged and removed `canary.pem`, removed the
`/tmp` key files and the scratch `.sarif` reports, then `git reflog expire --expire=now
--expire-unreachable=now --all && git gc --prune=now` so the throwaway commit object no longer
exists anywhere locally (verified via `git cat-file -t <sha>` failing, and `git fsck --full`
clean) — this never touched a remote, nothing was ever pushed.

**Why:** A leak scanner that's red on a clean tree gets ignored, which is worse than not having
one — round 3 makes the control's steady state actually green, without weakening what it catches.

### If interrupted here

Fix round 3 committed. Deferred per instruction, logged for the final review only: the
`--diff-filter=tuxdb` omission in the round-2 comment's backticked quote, the dependabot.yml
comment's "every workflow"/Phase 3 claims, `GITLEAKS_ENABLE_COMMENTS` input-name verification,
and whether `pull-requests: read` is strictly required. Next: await review of fix round 3.

---

## 2026-08-12 — Task 1 fix round 2/5: dependabot.yml + verified comment accuracy

**What:** Scoped re-review: Finding 1 (round 1) verdicted ADDRESSED. Finding 2 verdicted NOT
ADDRESSED — `gitleaks/gitleaks-action@v3` made the pin *structurally* trackable, but no
`.github/dependabot.yml` existed anywhere in the repo, so no ecosystem was configured for
version updates and nothing would ever actually open a bump PR. Two more Important findings
came with it. Fixed all three:

**Item A:** Added `.github/dependabot.yml` — `github-actions` ecosystem only, `directory: "/"`,
weekly. Deliberately scoped to github-actions alone (repo's other deps are leaving in Phase 3;
configuring them now is churn). Confirmed the `package-ecosystem`/`directory`/`schedule.interval`
keys and the `"weekly"` enum value against GitHub's own configuration-options doc before writing
it, not from memory. This also now covers `actions/checkout@v4`, same problem, same fix.

**Item B:** The `GITLEAKS_VERSION` comment in `gitleaks.yml` stated as settled fact that
"Dependabot tracks the @v3 tag... that's the fix for the staleness," which was false until Item A
landed — and contradicted this file's own round-1 entry, which correctly said nothing would bump
it without a `dependabot.yml`. Rewrote the comment to name `.github/dependabot.yml` explicitly and
to distinguish it from `dependabot_security_updates` (CVE advisories only, a separate mechanism).
Landing both files in the same commit makes the comment true as written, and it now agrees with
this log.

**Item C:** The round-1 `schedule`/`workflow_dispatch` triggers were added on the unverified
premise that they restore full-history coverage — the report only characterized `push`/
`pull_request` behavior. Read `gitleaks-action`'s actual dispatch logic: for `schedule`/
`workflow_dispatch`, `src/index.js` (lines 176-181) calls `gitleaks.Scan()` with a `scanInfo` that
was never given a `baseRef`/`headRef`, and `src/gitleaks.js`'s `Scan()` only appends `--log-opts`
inside its `push`/`pull_request` branches — neither matches, so no `--log-opts` flag is added at
all. Rather than trust that by inference, built a scratch git repo with a secret in a non-HEAD
commit (removed from a later commit, so absent from the working tree) and ran the exact resulting
command (`gitleaks detect --redact -v --exit-code=2 --report-format=sarif
--report-path=results.sarif --log-level=debug`, no `--log-opts`): gitleaks's own debug log showed
it executing `git -C . log -p -U0 --full-history --all --diff-filter=tuxdb` internally, and it
found the buried secret (exit 2). Confirmed branch (a): the triggers already provide genuine
full-history coverage — no workflow-behavior change needed, only tightened the inline comment to
cite the exact lines and the empirical proof instead of asserting it.

**Why:** Round 2 of up to 5. All three items were about a claim in a comment or a commit message
being true, not just plausible — the review is explicitly checking whether documentation and
behavior actually match, which is the same failure mode as the original hooksPath finding.

### If interrupted here

Fix round 2 committed. Deferred (coordinator said do not fix this round, logged for the final
review): whether `GITLEAKS_ENABLE_COMMENTS` is the correct input name, and whether
`pull-requests: read` is strictly required. Next: await review of fix round 2.

---

## 2026-08-12 — Task 1 fix round 1/5: hooksPath opt-in + Dependabot-trackable gitleaks

**What:** Task review returned two Important findings against Task 1. (1) `core.hooksPath` is
local git config, never transmitted by `git clone` — a fresh clone got zero local protection,
leaving CI as the only real gate, not the defence-in-depth promised. Fixed with `bin/setup-hooks`
(registers `core.hooksPath`, checks for `gitleaks`, warns clearly if missing — tested both paths)
and a new "Development Setup" section in `CONTRIBUTING.md` telling contributors to run it before
their first commit, stating plainly that the CI `gitleaks` job is the backstop, not a substitute.
(2) `.github/workflows/gitleaks.yml` pinned gitleaks 8.30.1 via a raw curl URL Dependabot cannot
track. Read `gitleaks/gitleaks-action`'s README: confirmed free for a public repo on a personal
account (`sdenike` qualifies, quoted in the task report) — switched to `gitleaks/gitleaks-action@v3`.
Before committing to it, read its actual source (`src/index.js`, `src/gitleaks.js`) and found its
`push`/`pull_request` scans are incremental (new commits only), unlike the old full-history curl
scan — added `workflow_dispatch` + a daily `schedule` cron to keep periodic full-history coverage.
Also added `pull-requests: read` to `permissions:` (the action's PR path lists PR commits via the
API) and set `GITLEAKS_ENABLE_COMMENTS: "false"` rather than granting `pull-requests: write` for a
PR-comment feature we don't use.

**Why:** Round 1 of up to 5 task-review fix rounds. Both findings were about the controls actually
holding up under real conditions (fresh clones, CI ruleset staleness) rather than passing on paper.

### If interrupted here

Fix round 1 committed. Flagged but deliberately NOT fixed (outside the two findings' named scope,
reported instead): this repo has no `.github/dependabot.yml`, so no ecosystem — including
`github-actions` — is actually configured for Dependabot version updates; `dependabot_security_updates`
(enabled in the original Task 1) only fires on CVE advisories, not routine releases, so
`gitleaks-action@v3` is trackable in principle but nothing will bump it without that file. Needs a
decision on scope/schedule/auto-merge policy before adding it. Next: await review of fix round 1.

---

## 2026-08-12 — Task 1 (secret hygiene controls) complete

**What:** Replaced `.gitignore` (previously 3 lines) with a full build-output, Xcode-user-state,
signing-identity, and credential ignore list. Added `.githooks/pre-commit` (gitleaks-backed,
blocks any commit with a staged secret) and registered it via `git config core.hooksPath
.githooks`. Installed gitleaks 8.30.1 via Homebrew. Added `.github/workflows/gitleaks.yml`,
a CI gate guarded with `if: github.repository == 'sdenike/textmate'` that scans full history on
PRs and pushes to `master`. Enabled `dependabot_security_updates` on the GitHub repo via `gh api`
(`secret_scanning` and `secret_scanning_push_protection` were already enabled). Proved the control
works with a real, throwaway ed25519 key (`ssh-keygen` → `canary.pem`): staged cleanly with no
hook in place, then blocked with exit status 1 ("COMMIT BLOCKED: gitleaks detected a secret")
once the hook and gitleaks were installed. Canary destroyed immediately after — no `canary.pem`,
no `/tmp/canary_key*`, no "test: canary" commit anywhere.

**Why:** This repo is public; anything committed is world-readable within minutes. Phase 5 will
introduce signing certificates and provisioning profiles — the leak controls must exist and be
proven working before that code ever lands, not after.

### If interrupted here

Task 1 is fully committed, nothing left in progress. Next: Phase 0 Task 2 (CI repository guard)
per `docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md`.

---

## 2026-08-12 — Recon complete, plan not yet approved

**What:** Surveyed the forked codebase, enumerated upstream PRs, analyzed two existing
modernization forks, and verified Liquid Glass APIs against the installed SDK. No code changed.

**Why:** Goal is "TextMate Revived" — Apple Silicon only, native macOS, Liquid Glass UI,
Xcode-buildable, Homebrew tap, in-app updates from `sdenike/textmate` releases, reusable modules.
Before planning phases, needed to know what already exists so we don't rebuild it.

### Repo as forked

- Pristine upstream `master`, last commit `346b52b1` (2021-10-12). Zero commits of our own.
- ~92K lines C++/ObjC++. 45 frameworks, 11 app targets, 27 MB.
- Build: `./configure` → `bin/rave` (50KB Ruby) → `build.ninja` → `ninja`. Not Xcode.
- `APP_MIN_OS = "10.12"` (`default.rave:1`). Dual-arch `-target macos-arm64` +
  `-target macos-x86_64` (`local-orig.rave:19-23`) — Intel lives in build config, not in code.
- Bundle ID template `com.macromates.${TARGET_NAME}` (`Info.plist:12`); version `v2.0.22`.
- License: GPLv3 (`LICENSE`, `COPYING`), no exceptions. Fork must stay GPLv3.
- 86 CxxTest test files under `Frameworks/*/tests/`, run via `ninja <framework>`.
- 6 submodules: `bin/CxxTest`, `Applications/TextMate/icons`, `PlugIns/dialog-1.x`,
  `PlugIns/dialog`, `vendor/Onigmo/vendor`, `vendor/kvdb/vendor`.
- CI `.github/workflows/build.yml`: push-triggered, brew-installs boost/capnp/sparsehash/
  multimarkdown/ninja/ragel, then `./configure && ninja TextMate`. `.travis.yml` is dead
  (xcode7.2).

### The core is the asset

`buffer` (AA-tree storage), `layout`, `editor`, `selection`, `regexp` (vendored Onigmo 5.13.5),
`scope`, `parse` — ~25K lines of pure C++. This is why TextMate opens huge files instantly.
`OakTextView` (7.4K lines ObjC++) is a custom `NSView` driving that engine. Nothing in SwiftUI
replaces it. See `INTERNALS.md` for `oak::basic_tree_t`, `ng::buffer_t`, `ng::layout_t`.

### Deps identified for removal

Cap'n Proto (36 refs), boost (crc + variant only), sparsehash, ragel, multimarkdown,
custom `network` framework (1.3K lines hand-rolled HTTP → URLSession), `license` framework
(660 lines, dead), `updater` + `SoftwareUpdate` (2.2K lines, points at dead api.textmate.org,
76 refs). No Sparkle present (0 refs).

### Prior art — both forks are complementary, not redundant

| | `textmatelives/textmate` | `schriftgestalt` (PR #1469) |
|---|---|---|
| Divergence | **130 ahead / 0 behind**, 300 files | 77 commits, 550 files, +19412/−5842 |
| Target | macOS 26+, Apple Silicon only | macOS 12+ |
| Build | still rave/ninja | deleted `.rave`, added `.xcodeproj`, static-links libs |
| Updates | GitHub Releases + signature verify | updater disabled |
| Killed | Cap'n Proto, license, api.textmate.org | license, crash reporter, QuickLook plugin |
| UI | SF Symbols toolbar, onboarding sheet | Tahoe tab bar, `NSRulerView` gutter, sidebar, scope bar, back/forward nav, diff view |
| Ships | 11.4 MB `.tbz`, notarized, 5 releases (v2.1.4-undead, 2026-06-11) | tagged v2.5-9806 |

PR #1469 state: `MERGEABLE` / `CLEAN`, head = `schriftgestalt:master` @ `9ccc07bb`.
Both GPLv3, both branch from the same base → git-mergeable.

Upstream has **14 open PRs** (2013–2026). Full JSON dump:
`scratchpad/open_prs.json`. Two are the large refactors above; #1467 is a third
(CMake migration + LSP, 106K lines). Remainder: 2 macOS-compat, 1 bugfix, 5 features,
1 build cleanup, 2 docs, 1 grammar.

### SDK verification (Xcode 26.6, macOS 26.6.1, SDK MacOSX26.5)

Typechecked clean at `arm64-apple-macos26.0`:
- AppKit: `NSGlassEffectView`, `NSGlassEffectContainerView`, `NSGlassEffectViewStyle.clear`
  — all `API_AVAILABLE(macos(26.0))`
- SwiftUI: `GlassEffectContainer(spacing:)`, `.glassEffect(.regular.tint(_).interactive(), in:)`

**Liquid Glass is fully reachable from AppKit.** SwiftUI is not required to get it.

Sparkle (via Context7, `/websites/sparkle-project`): 2.3+ requires macOS 10.13+, EdDSA
mandatory; `generate_appcast` signs appcast + release notes; markdown release notes since
Sparkle 2.9 / macOS 12; `sparkle:minimumSystemVersion` gates updates by OS.

### Standing recommendations (NOT yet approved by user)

1. **Base:** reset onto `textmatelives/main`, then port PR #1469's Xcode + Tahoe UI commits on
   top. Do not restart from the 2021 fork.
2. **UI:** AppKit shell + C++ core, Swift 6 for new code, SwiftUI islands via `NSHostingView`
   for Preferences / About / onboarding / update sheet. Not a SwiftUI rewrite.
3. **Updater:** Sparkle 2 + EdDSA appcast published to GitHub Releases by CI.
4. **Naming:** full rename, coexists with real TextMate — cask token `textmate-revived`.

### Decided by user (2026-08-12)

- **Bundle ID prefix:** `com.macromates.${TARGET_NAME}` → `com.shelbydenike.${TARGET_NAME}`
  (`Applications/TextMate/Info.plist:12`). Matches the user's other projects. Yields
  `com.shelbydenike.TextMate`, `com.shelbydenike.SyntaxMate`,
  `com.shelbydenike.QuickLookGenerator`. Changing the prefix orphans existing prefs and
  Application Support paths — migration is a separate open question.

- **UI:** AppKit shell + SwiftUI islands via `NSHostingView`. Not a SwiftUI rewrite.
- **Updater:** port textmatelives' GitHub-Releases updater. Not Sparkle.
- **LSP/Copilot:** deferred to Phase 9, gated on explicit approval.
- **Homebrew:** one central tap `sdenike/homebrew-tap` (→ `brew tap sdenike/tap`) replacing the
  per-app `sdenike/homebrew-hidden-revived`. Migrate existing users via `tap_migrations.json`
  in the OLD tap; the old repo must NOT be deleted or existing installs are stranded.
- **Tests:** each phase ships new tests, not just keeps the 86 CxxTest suites green. Phase 5
  updater negative tests (tampered payload / wrong key / downgrade rejected) are the
  highest-value suite in the project.
- **GitHub history:** milestone per phase, issue per work item, branch per issue, PR with
  `Closes #N`, squash merge, outcomes commented on issues. Ported work credits source SHAs
  and authors (GPLv3 obligation).
- **CI:** only on public repos. Guard every job with
  `if: github.repository == 'sdenike/textmate-revived'`.
- **Secrets:** never committed. Verified `sdenike/textmate` is PUBLIC and currently has
  NO credential-shaped tracked files. Root `.gitignore` is only 3 lines (`build.ninja`,
  `local.rave`, `revoked_serials.cc`) — replaced in Phase 0 before any signing work exists.
  Defence in depth: gitignore + gitleaks pre-commit + gitleaks in CI + push protection.
  If a secret ever lands: rotate first, scrub history second.

- **Apple Developer account: active** (used for White Rabbit, Smilodon, Redpill). Phase 5
  unblocked.
- **Shared modules (Phase 8):** `sdenike/construct` → package `Construct`, products
  `ConstructUpdater`, `ConstructGlass`, `ConstructSettings`. **PUBLIC, MIT.** Must be public:
  TextMate Revived is GPLv3, and GPLv3 requires complete corresponding source, so a GPL binary
  linking a private module is undistributable. Must be clean-room: anything extracted from
  TextMate's tree stays GPLv3 and would pull White Rabbit / Smilodon / Redpill to GPLv3 too.
  Package declares the LOWEST consuming macOS version; Liquid Glass gated
  `@available(macOS 26, *)` with fallback so Hidden Revived can still adopt it.
- **Spec approved by user 2026-08-12.** Proceeding to implementation plan.

### Phase 0 plan written

`docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md` — 6 tasks: secret hygiene
controls, CI repository guard, fork remotes, benchmark harness + baseline, 2021-tree build
attempt, GitHub milestones/labels.

Verified while writing it: `sdenike/textmate` is PUBLIC; `secret_scanning` and
`secret_scanning_push_protection` are ALREADY enabled (so that task is verify, not enable);
`dependabot_security_updates` is disabled; 0 milestones exist; gitleaks 8.30.1 is in Homebrew;
official TextMate `v2.0.23` shipped 2021-10-12 (same day as our fork's last commit).

Corrected in the spec: `gitleaks protect --staged` is the deprecated 8.x form. Current is
`gitleaks git --pre-commit --staged .` (exit code 1 = leaks found).

Deliberate plan choice: performance baseline is measured against **released binaries**
(official v2.0.23 + textmatelives v2.1.4-undead), not a local build. The 2021 tree predates
clang 2100 and may not compile — upstream PR #1463 exists to work around a clang 15 crash.
Task 5 records that outcome and states which phase first provides a green test oracle. If the
tree does not build, textmatelives' working CI makes Phase 1 the first real gate.

Only Phase 0 is planned in detail. Phases 1-9 get their own plans when their inputs are real —
Phase 2's file paths do not exist until Phase 1's merge lands.

### If interrupted here

Nothing is committed. No application code touched. Untracked: `STREAM.md`,
`docs/superpowers/specs/`, `docs/superpowers/plans/`.

Next step: user chooses subagent-driven or inline execution of the Phase 0 plan. Start with
Task 1 (secret hygiene) — it gates everything else and its test is a planted dummy credential
that must be rejected by the pre-commit hook.

**Do not amend `346b52b1`.** It is upstream's commit; rewriting it destroys the merge-base with
`textmatelives/main` and `schriftgestalt:master`, which the whole plan depends on.
