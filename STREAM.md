# STREAM

Running work log, newest first. Timestamp · what · why · if-interrupted-here.

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
