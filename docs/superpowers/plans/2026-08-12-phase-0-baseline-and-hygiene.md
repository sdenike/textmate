# TextMate Revived — Phase 0: Baseline, Safety Net, and Hygiene

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the secret-leak controls, upstream remotes, performance baseline, and GitHub project scaffolding that every later phase depends on — without changing a single line of application code.

**Architecture:** Phase 0 touches only repository infrastructure. Secret hygiene lands first and is proven with a planted dummy credential, because the controls must exist before any signing work does. The performance baseline is measured against *released binaries* rather than a local build, since the 2021 tree predates clang 2100 and may not compile.

**Tech Stack:** git, `gh` CLI, gitleaks 8.30.1, hyperfine, GitHub Actions, macOS 26.6.1 / Xcode 26.6.

## Global Constraints

- Repository is `sdenike/textmate`, **public**, GPLv3. Anything committed is world-readable.
- No credentials, keys, certificates, or provisioning profiles in any commit, ever.
- CI runs only on public repositories; every job carries a `github.repository` guard.
- No application source code changes in this phase. Infrastructure only.
- Do not amend or rewrite commit `346b52b1` or any ancestor — it is upstream history, and rewriting it destroys the merge-base with `textmatelives/main` and `schriftgestalt:master`.
- Every commit message uses conventional-commit prefixes (`chore:`, `ci:`, `docs:`, `test:`).
- `STREAM.md` gets a newest-first entry in the same commit as the change it describes.

## Verified Preconditions

These were checked on 2026-08-12 and do not need re-verification:

| Fact | Value |
|---|---|
| `sdenike/textmate` visibility | `public` |
| `secret_scanning` | already `enabled` |
| `secret_scanning_push_protection` | already `enabled` |
| `dependabot_security_updates` | `disabled` — enabled in Task 1 |
| Existing milestones | 0 |
| gitleaks in Homebrew | 8.30.1 |
| Official TextMate baseline release | `v2.0.23`, 2021-10-12 |
| textmatelives baseline release | `v2.1.4-undead`, 11.4 MB `.tbz` |

## File Structure

| File | Responsibility |
|---|---|
| `.gitignore` (modify) | Single source of ignore truth; credential patterns are the load-bearing part |
| `.githooks/pre-commit` (create) | Local gitleaks gate; blocks the commit before it exists |
| `.github/workflows/gitleaks.yml` (create) | CI gate; catches what bypassed the local hook |
| `.github/workflows/build.yml` (modify) | Add repository guard so forks and private clones never run CI |
| `bin/bench/measure.sh` (create) | Measures one `.app` bundle; single responsibility |
| `bin/bench/baseline.sh` (create) | Downloads reference releases and drives `measure.sh` |
| `docs/benchmarks/2026-08-12-baseline.md` (create) | Recorded numbers Phase 3 and Phase 7 are judged against |

---

### Task 1: Secret hygiene controls

**Files:**
- Modify: `.gitignore`
- Create: `.githooks/pre-commit`
- Create: `.github/workflows/gitleaks.yml`
- Test: planted dummy credential (manual, destroyed after)

**Interfaces:**
- Consumes: nothing.
- Produces: a repository where `git commit` fails on a staged secret, and a CI job named `gitleaks` that fails a pull request containing one.

- [ ] **Step 1: Write the failing test — plant a dummy credential**

This is the test. It must fail (i.e. the commit must be allowed) before the controls exist, proving the test is real.

**Do not use a published example credential as the canary.** Well-known documentation keys such as AWS's `AKIAIOSFODNN7EXAMPLE` are allowlisted by gitleaks' default config precisely because they are fake — the hook would correctly ignore one, and we would misread that as a broken control. Generate a real, throwaway SSH private key instead: it matches gitleaks' `private-key` rule unambiguously, it has never been used for anything, and it is destroyed at the end of this task.

```bash
cd /Users/shelby/Development/textmate
ssh-keygen -t ed25519 -N '' -C 'gitleaks-canary-DELETE-ME' -f /tmp/canary_key
cp /tmp/canary_key ./canary.pem
git add -f canary.pem
git status --porcelain canary.pem   # expect: A  canary.pem
```

Expected right now: the file stages cleanly with no hook to stop it. That is the failing state. Do **not** actually run `git commit` at this step — there is no hook yet, and the point is only to show the path is open.

- [ ] **Step 2: Clean up the canary before writing controls**

```bash
git restore --staged canary.pem && rm -f canary.pem
git status --porcelain   # expect: only STREAM.md and docs/ untracked
```

- [ ] **Step 3: Replace `.gitignore`**

The existing file is three lines. Replace its entire contents with:

```gitignore
# ---- Build output ----
build/
build.ninja
.ninja_deps
.ninja_log
DerivedData/
*.o
*.dSYM/

# ---- Machine-local build config ----
local.rave

# ---- Legacy upstream artifact ----
Frameworks/license/src/revoked_serials.cc

# ---- Xcode user state ----
*.xcuserstate
xcuserdata/
*.xcscmblueprint
*.xccheckout
.swiftpm/

# ---- macOS ----
.DS_Store

# =====================================================================
# SIGNING IDENTITIES AND KEYS — NEVER COMMIT
# This repository is PUBLIC. Anything committed here is world-readable
# and scraped by automated harvesters within minutes of the push.
# =====================================================================
*.p12
*.pfx
*.cer
*.crt
*.pem
*.key
*.keychain
*.keychain-db
*.p8
AuthKey_*.p8
*.mobileprovision
*.provisionprofile

# ---- Credentials and environment ----
.env
.env.*
.envrc
secrets/
*.secret
notarize.json
notarization-credentials.plist
```

Note: `.gitignore` only affects **untracked** files. Nothing currently tracked is removed by this change — verified, the repository has no credential-shaped tracked files today.

- [ ] **Step 4: Create the pre-commit hook**

Create `.githooks/pre-commit`:

```bash
#!/bin/sh
# Blocks commits containing secrets. This repository is PUBLIC.
# Bypassing this hook with --no-verify is never correct for a real commit.

if ! command -v gitleaks >/dev/null 2>&1; then
    echo "pre-commit: gitleaks not installed. Run: brew install gitleaks" >&2
    exit 1
fi

# gitleaks 8.19+ subcommand form. The older 'gitleaks protect --staged'
# is deprecated. Exit code 1 means leaks were found.
gitleaks git --pre-commit --staged --redact --verbose .
status=$?

if [ $status -eq 1 ]; then
    cat >&2 <<'EOF'

COMMIT BLOCKED: gitleaks detected a secret in your staged changes.

This repository is public. Do not bypass this check.
If the finding is a false positive, add a narrowly-scoped allowlist
entry to .gitleaks.toml rather than disabling the hook.
EOF
    exit 1
fi

exit $status
```

Make it executable and register the hooks directory. `core.hooksPath` is used rather than `.git/hooks/` so the hook is version-controlled and every clone gets it:

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

- [ ] **Step 5: Install gitleaks and run the test again**

```bash
brew install gitleaks
gitleaks version   # expect 8.30.1 or newer
cp /tmp/canary_key ./canary.pem
git add -f canary.pem
git commit -m "test: canary (MUST BE REVERTED)"
```

Expected: **FAILS**, exit status 1, printing "COMMIT BLOCKED: gitleaks detected a secret". This is the test now passing.

If it instead succeeds, stop and report — do not proceed. Run `git reset --soft HEAD~1` first to undo the commit, then remove the file as in Step 6.

- [ ] **Step 6: Destroy the canary**

```bash
git restore --staged canary.pem
rm -f canary.pem /tmp/canary_key /tmp/canary_key.pub
git status --porcelain | grep canary && echo "CANARY STILL PRESENT — STOP" || echo "canary gone"
git log --oneline -3
```

Expected: `canary gone`, and no commit titled "test: canary" in the log. Confirm both before continuing — a canary left behind is the exact failure this task exists to prevent.

- [ ] **Step 7: Create the CI gate**

Create `.github/workflows/gitleaks.yml`:

```yaml
name: gitleaks

on:
  pull_request:
  push:
    branches: [master]

permissions:
  contents: read

jobs:
  scan:
    # CI runs only on the canonical public repository. Forks and private
    # clones must never run Actions. Update this string when the repo is
    # renamed in Phase 4 — missing it silently disables all CI.
    if: github.repository == 'sdenike/textmate'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install gitleaks
        run: |
          curl -sSL -o gitleaks.tar.gz \
            https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
          tar -xzf gitleaks.tar.gz gitleaks
          sudo install gitleaks /usr/local/bin/gitleaks
      - name: Scan full history
        run: gitleaks git --redact --verbose .
```

Runs on `ubuntu-latest` deliberately: this job needs no macOS toolchain, and macOS runner minutes bill at a multiple of Linux.

- [ ] **Step 8: Enable Dependabot security updates**

Secret scanning and push protection are already enabled (verified). Dependabot is not:

```bash
gh api -X PATCH repos/sdenike/textmate \
  -f 'security_and_analysis[dependabot_security_updates][status]=enabled'

gh api repos/sdenike/textmate --jq '.security_and_analysis'
```

Expected: `secret_scanning`, `secret_scanning_push_protection`, and `dependabot_security_updates` all `enabled`.

- [ ] **Step 9: Commit**

```bash
git add .gitignore .githooks/pre-commit .github/workflows/gitleaks.yml STREAM.md
git commit -m "chore: add secret-leak controls (gitignore, pre-commit hook, CI scan)"
```

---

### Task 2: Repository guard on the existing build workflow

**Files:**
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: the guard idiom established in Task 1's `gitleaks.yml`.
- Produces: no workflow in this repository runs outside `sdenike/textmate`.

- [ ] **Step 1: Read the current workflow**

```bash
cat .github/workflows/build.yml
```

Expected: a push-triggered job on `macOS-latest` that brew-installs boost/capnp/sparsehash/multimarkdown/ninja/ragel then runs `./configure && ninja TextMate`.

- [ ] **Step 2: Add the guard to every job**

Insert as the first key of each `jobs.<name>` block, immediately after `runs-on`:

```yaml
    if: github.repository == 'sdenike/textmate'
```

Leave the rest of the workflow untouched. It will likely fail to build on modern toolchains — that is Task 5's finding to record, not this task's problem to fix.

- [ ] **Step 3: Verify the YAML parses**

```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/build.yml')); \
print([ (k, v.get('if')) for k,v in d['jobs'].items() ])"
```

Expected: every job prints a non-`None` `if` value.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build.yml STREAM.md
git commit -m "ci: restrict workflows to the canonical public repository"
```

---

### Task 3: Add upstream fork remotes

**Files:**
- No files. Git configuration only.

**Interfaces:**
- Produces: remotes `textmatelives`, `gs1469`, `tectiv3` fetched locally, so Phases 1-3 can merge and cherry-pick without network round-trips.

- [ ] **Step 1: Add the three remotes**

```bash
git remote add upstream      https://github.com/textmate/textmate.git
git remote add textmatelives https://github.com/textmatelives/textmate.git
git remote add gs1469        https://github.com/schriftgestalt/textmate.git
git remote add tectiv3       https://github.com/tectiv3/textmate.git
git fetch --all --prune
```

- [ ] **Step 2: Verify the merge-base is shared**

This is the assumption the entire plan rests on. If any of these fail, stop and report — a fork without shared history cannot be merged, only ported by hand.

```bash
git merge-base --is-ancestor $(git rev-parse HEAD) textmatelives/main && echo "textmatelives: OK"
git merge-base HEAD gs1469/master   >/dev/null && echo "gs1469: shared base OK"
git merge-base HEAD tectiv3/develop >/dev/null && echo "tectiv3: shared base OK"
```

Expected: three `OK` lines.

- [ ] **Step 3: Record the divergence numbers**

```bash
echo "textmatelives: $(git rev-list --count HEAD..textmatelives/main) ahead"
echo "gs1469:        $(git rev-list --count HEAD..gs1469/master) ahead"
echo "tectiv3:       $(git rev-list --count HEAD..tectiv3/develop) ahead"
```

Expected, approximately: 130 / 77 / 100. Materially different numbers mean a fork moved since 2026-08-12 — record the new values in `STREAM.md`.

- [ ] **Step 4: Commit the STREAM entry**

```bash
git add STREAM.md
git commit -m "docs: record upstream fork remotes and divergence"
```

---

### Task 4: Benchmark harness and baseline

**Files:**
- Create: `bin/bench/measure.sh`
- Create: `bin/bench/baseline.sh`
- Create: `docs/benchmarks/2026-08-12-baseline.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `bin/bench/measure.sh <path-to-.app>` printing one Markdown table row; `docs/benchmarks/2026-08-12-baseline.md` holding the numbers Phase 3 and Phase 7 are judged against.

**Why released binaries rather than a local build:** the 2021 tree predates clang 2100 and may not compile (Task 5 determines this). More importantly, the honest comparison for "is TextMate Revived faster and smaller" is against *what a user runs today*, which is a shipped release — not a debug build from a five-year-old tree.

- [ ] **Step 1: Write `bin/bench/measure.sh`**

```bash
#!/bin/bash
# Measures one .app bundle. Usage: measure.sh <label> </path/to/App.app>
# Emits a single Markdown table row on stdout.
set -euo pipefail

LABEL="$1"
APP="$2"
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"

SIZE_KB=$(du -sk "$APP" | cut -f1)
ARCHS=$(lipo -archs "$BIN" 2>/dev/null | tr ' ' '+')
DYLIBS=$(otool -L "$BIN" | tail -n +2 | grep -c '@rpath\|@loader_path' || true)

# Time to responsive: the app answers an Apple Event only once its main
# run loop is up, which is a real "ready to use" signal rather than a
# proxy for it.
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 2

START=$(python3 -c 'import time; print(time.time())')
open -a "$APP"
until osascript -e "tell application id \"$BUNDLE_ID\" to count windows" >/dev/null 2>&1; do
    sleep 0.05
done
END=$(python3 -c 'import time; print(time.time())')
LAUNCH_MS=$(python3 -c "print(round(($END - $START) * 1000))")

RSS_MB=$(python3 -c "
import subprocess
pid = subprocess.run(['pgrep','-n','-f','$APP'],capture_output=True,text=True).stdout.strip()
out = subprocess.run(['ps','-o','rss=','-p',pid],capture_output=True,text=True).stdout.strip()
print(round(int(out)/1024)) if out else print('n/a')
")

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true

printf '| %s | %s | %s | %s | %s | %s |\n' \
    "$LABEL" "$SIZE_KB" "$ARCHS" "$DYLIBS" "$LAUNCH_MS" "$RSS_MB"
```

- [ ] **Step 2: Write `bin/bench/baseline.sh`**

```bash
#!/bin/bash
# Downloads the reference releases and measures each one.
set -euo pipefail

REPO=$(git rev-parse --show-toplevel)
WORK="${TMPDIR:-/tmp}/tmr-baseline"
mkdir -p "$WORK"
cd "$WORK"

echo "| build | size KB | archs | rpath dylibs | launch ms | RSS MB |"
echo "|---|---|---|---|---|---|"

gh release download v2.0.23 --repo textmate/textmate --dir "$WORK/official" --clobber
gh release download v2.1.4-undead --repo textmatelives/textmate --dir "$WORK/undead" --clobber

for d in official undead; do
    archive=$(find "$WORK/$d" -name '*.tbz' -o -name '*.zip' | head -1)
    mkdir -p "$WORK/$d/x" && tar -xf "$archive" -C "$WORK/$d/x" 2>/dev/null || \
        unzip -oq "$archive" -d "$WORK/$d/x"
    app=$(find "$WORK/$d/x" -maxdepth 2 -name '*.app' | head -1)
    "$REPO/bin/bench/measure.sh" "$d" "$app"
done
```

- [ ] **Step 3: Make them executable and run**

```bash
chmod +x bin/bench/measure.sh bin/bench/baseline.sh
./bin/bench/baseline.sh | tee /tmp/baseline.md
```

Expected: two table rows. The `official` row should show `x86_64+arm64` — that is the Intel weight Phase 2 strips. `undead` should show `arm64` only and roughly 11.4 MB.

If `osascript` prompts for Automation permission, grant it — the measurement cannot proceed otherwise. Note in the results file that the numbers were taken with the app already permitted, so later runs are comparable.

- [ ] **Step 4: Record the baseline**

Create `docs/benchmarks/2026-08-12-baseline.md` containing the table from Step 3, plus:

```markdown
# Baseline — 2026-08-12

Measured on macOS 26.6.1, Xcode 26.6, Apple Silicon.

Method: `bin/bench/baseline.sh`. Launch time is measured to first successful
Apple Event reply, which requires the main run loop to be running — a real
"ready to use" signal rather than a proxy.

## Measurement limits, stated honestly

- Launch time includes Gatekeeper's first-run verification on the very first
  launch. All recorded numbers are from the *second* launch onward.
- Large-file open time is not automated. It is measured manually against a
  generated 100 MB file and recorded separately.
- RSS is sampled once after the window appears, not at steady state.

## Targets these numbers set

- Phase 3 must not regress size or launch versus `undead`.
- Phase 7 must show measurable improvement over `undead` on launch, size,
  and rpath dylib count. The dylib count is the direct proxy for the
  45-framework static-linking work.
```

- [ ] **Step 5: Commit**

```bash
git add bin/bench docs/benchmarks STREAM.md
git commit -m "test: add benchmark harness and record 2026-08-12 baseline"
```

---

### Task 5: Determine whether the inherited test suite can run

**Files:**
- Create: `docs/benchmarks/2026-08-12-build-attempt.md`

**Interfaces:**
- Produces: a recorded, honest answer to "do we have a working regression oracle right now, or only after Phase 1?" Every later phase's gate depends on this answer.

**Context:** the tree targets `APP_MIN_OS = 10.12` and was last touched in 2021, five clang major versions ago. Upstream PR #1463 exists specifically to work around a clang 15 crash; we are on clang 2100. A failed build here is an expected, informative outcome — not a task failure.

- [ ] **Step 1: Install the build dependencies**

```bash
brew install boost capnp google-sparsehash multimarkdown ninja ragel
git submodule update --init --recursive
```

- [ ] **Step 2: Attempt configure and build, capturing everything**

```bash
./configure 2>&1 | tee /tmp/configure.log
ninja TextMate 2>&1 | tee /tmp/build.log
echo "exit: ${PIPESTATUS[0]}"
```

- [ ] **Step 3: Branch on the outcome**

**If the build succeeded**, run the inherited suites and record the count:

```bash
ninja 2>&1 | tee /tmp/tests.log
grep -c "Running cxxtest tests" /tmp/tests.log || true
```

**If the build failed**, extract only the first distinct error — do not paste the whole log:

```bash
grep -m5 "error:" /tmp/build.log
```

- [ ] **Step 4: Record the finding**

Create `docs/benchmarks/2026-08-12-build-attempt.md` stating plainly: whether the 2021 tree builds on Xcode 26.6, the first errors if not, and therefore **which phase first gives us a green test oracle**.

If it does not build, record this consequence explicitly:

> The 86 inherited CxxTest suites cannot serve as the regression oracle until Phase 1. `textmatelives/main` has working CI (`build-and-test.yml`) and ships releases, so its tree builds and tests today. Phase 1's gate therefore becomes "textmatelives' suites pass on our merged tree", and Phase 0's role is reduced to hygiene, remotes, and the binary-level baseline.

- [ ] **Step 5: Commit**

```bash
git add docs/benchmarks/2026-08-12-build-attempt.md STREAM.md
git commit -m "docs: record 2021-tree build attempt on Xcode 26.6"
```

---

### Task 6: GitHub project scaffolding

**Files:**
- No files. GitHub metadata only.

**Interfaces:**
- Produces: milestones `Phase 0` through `Phase 9` and the label set every later issue and pull request uses.

- [ ] **Step 1: Create the milestones**

```bash
for m in \
  "Phase 0 — Baseline & Hygiene" \
  "Phase 1 — Rebase onto textmatelives" \
  "Phase 2 — Xcode migration" \
  "Phase 3 — Dependency purge" \
  "Phase 4 — Identity" \
  "Phase 5 — Updates & distribution" \
  "Phase 5a — Central Homebrew tap" \
  "Phase 6 — UI & Liquid Glass" \
  "Phase 7 — Performance" \
  "Phase 8 — Shared modules" \
  "Phase 9 — Optional: LSP"
do
  gh api -X POST repos/sdenike/textmate/milestones -f title="$m" >/dev/null && echo "created: $m"
done
```

- [ ] **Step 2: Create the labels**

The repository currently has only GitHub's defaults.

```bash
gh label create "phase-0"  --repo sdenike/textmate --color 0E8A16 --description "Baseline & hygiene"      --force
gh label create "security" --repo sdenike/textmate --color B60205 --description "Secrets, signing, updater" --force
gh label create "build"    --repo sdenike/textmate --color 1D76DB --description "Build system & CI"        --force
gh label create "ported"   --repo sdenike/textmate --color 5319E7 --description "Carries upstream fork work" --force
gh label create "perf"     --repo sdenike/textmate --color FBCA04 --description "Startup, size, throughput"  --force
gh label create "ui"       --repo sdenike/textmate --color C2E0C6 --description "AppKit, SwiftUI, Liquid Glass" --force
```

- [ ] **Step 3: Verify**

```bash
gh api repos/sdenike/textmate/milestones --jq 'length'   # expect 11
gh label list --repo sdenike/textmate | wc -l            # expect defaults + 6
```

- [ ] **Step 4: Open the Phase 1 tracking issue**

```bash
gh issue create --repo sdenike/textmate \
  --title "Phase 1: Merge textmatelives/main (130 commits)" \
  --milestone "Phase 1 — Rebase onto textmatelives" \
  --label "ported,build" \
  --body "$(cat <<'EOF'
Merge `textmatelives/main` into `master`.

**Brings:** arm64-only, macOS 26 target, Cap'n Proto removed, `license`
framework removed, dead `api.textmate.org` calls removed, notarized CI,
working GitHub-Releases updater.

**Gate:** tests green, app launches, benchmarks re-measured against
`docs/benchmarks/2026-08-12-baseline.md`.

**Attribution:** the merge commit body must credit `textmatelives/textmate`
and list the merged commit range. GPLv3 obligation.

Spec: `docs/superpowers/specs/2026-08-12-textmate-revived-design.md`
EOF
)"
```

---

## Phase 0 Exit Criteria

All must hold before Phase 1 begins:

- [ ] A planted dummy credential is rejected by the pre-commit hook.
- [ ] `gitleaks` CI job exists and is guarded by `github.repository`.
- [ ] Secret scanning, push protection, and Dependabot all report `enabled`.
- [ ] Three fork remotes fetched; shared merge-base verified for each.
- [ ] `docs/benchmarks/2026-08-12-baseline.md` contains real measured numbers.
- [ ] `docs/benchmarks/2026-08-12-build-attempt.md` states which phase first provides a green test oracle.
- [ ] 11 milestones and 6 labels exist; the Phase 1 issue is open.
- [ ] No `canary.pem` anywhere in the working tree or history.

## Subsequent Phases

Phases 1-9 get their own plan documents, written when their inputs are real. Phase 2's exact file paths do not exist until Phase 1's merge lands, and writing them now would be invention rather than planning.

Next: `docs/superpowers/plans/YYYY-MM-DD-phase-1-rebase-textmatelives.md`, written after Phase 0's exit criteria are met.
