# TextMate Revived — Phase 2: Xcode Migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `rave`/ninja build with a native Xcode project that opens and builds with Cmd-B, builds from CLI with `xcodebuild`, keeps all 54 test binaries running, and unblocks Swift compilation for Phase 6.

**Architecture:** Generate the project with **XcodeGen** from a checked-in `project.yml`, itself derived from the existing `.rave` files by a converter we write. Both `project.yml` and the generated `.xcodeproj` are committed, so contributors need only Xcode; XcodeGen is required solely to regenerate. The ninja build stays working and authoritative until parity is proven, then is deleted in one commit.

**Tech Stack:** XcodeGen 2.46.0, Xcode 26.6, `xcodebuild`, Swift 6 language mode, C++23, CxxTest.

## Global Constraints

- Apple Silicon only. `ARCHS = arm64`, no `x86_64` anywhere.
- `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- Repository `sdenike/textmate` is PUBLIC and GPLv3. No credentials in any commit, ever.
- Every CI job carries `if: github.repository == 'sdenike/textmate'`.
- `CFBundleIdentifier` stays `com.macromates.TextMate` in this phase. The identifier change plus settings migration is Phase 4 and must not be pulled forward.
- Root `CHANGELOG.md` is the single source of truth for `APP_VERSION`, parsed from the first `## <date> (vX.Y.Z)` heading. Any build-system change must preserve that derivation.
- Signing stays ad-hoc (`-`) with `APPLE_DEVELOPER_ID` as the env override. Real Developer ID signing is Phase 5.
- `STREAM.md` gets a newest-first entry in the same commit as its change.
- Conventional-commit prefixes.
- **The ninja build must keep working until Task 8.** Every task before it is additive.

## Why not port PR #1469's project

Measured, not assumed. `gs1469/master`'s `project.pbxproj` is 6506 lines defining **7 targets**, at `MACOSX_DEPLOYMENT_TARGET` 10.11/12.4. It references the `license` and `updater` frameworks textmatelives deleted (25 references), expects `bl`, `CompareMate`, and `QuickLookExtensions` directories we do not have, and omits `NewApplication` and `QuickLookGenerator` which we do. It would need 50+ edits before it parsed against our tree, and would still need all 46 frameworks wired from scratch.

Generating from `.rave` is less work and produces a project that stays in sync with the source of truth.

## The build we must reproduce

Every rule in the current `build.ninja`, with its edge count and how Xcode covers it:

| rule | edges | Approach |
|---|---|---|
| CopyFile | 1536 | Native Copy Files build phase |
| CompileClang | 736 | Native compile sources |
| **ExportHeader** | **369** | **See "The header problem" — the load-bearing risk** |
| Link | 84 | Native |
| GenTest / RunTest | 54 / 54 | Script phase per test target invoking `bin/gen_test` + CxxTest |
| CompileMarkdown | 32 | Script phase invoking `bin/gen_html` (multimarkdown) |
| Codesign | 30 | Native code signing |
| CompileXib | 28 | Native |
| ExpandVariables | 26 | Native Info.plist variable substitution |
| RunExecutable / RunApplication | 18 / 12 | Script phases running build-time tools |
| PCH | 8 | Native `GCC_PREFIX_HEADER` |
| ConvertToUTF16 | 8 | Script phase |
| CompileRagel | 2 | Custom build rule — only two `.rl` files |
| CompileIcon | 2 | Script phase invoking `bin/build_app_icon.sh` |
| MakeBuildfile | 1 | Dropped; XcodeGen replaces it |

## The header problem

`ExportHeader` has 369 edges and no native Xcode equivalent. The rave build copies each framework's public headers into a single flat build-side include root, which is what makes `#include <buffer/buffer.h>` resolve from any other framework.

Three ways to reproduce it in Xcode, in order of preference:

1. **`HEADER_SEARCH_PATHS` pointed at the repo root.** Because every framework already lives at `Frameworks/<name>/src/…`, a single `-I$(SRCROOT)/Frameworks` plus a per-framework symlink or header map may resolve `<buffer/buffer.h>` directly. Cheapest if it works — verify in Task 3 before building anything on it.
2. **A generated headers directory.** One script phase that mirrors rave's export into `$(DERIVED_FILE_DIR)/include`, with that on the search path. Faithful, but reintroduces a copy step.
3. **Xcode header maps** (`USE_HEADERMAP`). Automatic but historically unpredictable across targets.

**Task 3 decides this by experiment, not by argument, and every later task depends on the answer.**

## File Structure

| File | Responsibility |
|---|---|
| `bin/rave2yaml` (create) | Parses `.rave` files, emits `project.yml`. Mechanical translation only. |
| `project.yml` (create) | XcodeGen spec — the checked-in source of truth for the project |
| `TextMate.xcodeproj` (generated, committed) | So contributors need only Xcode |
| `Xcode/*.xcconfig` (create) | Shared build settings: arch, deployment target, C++23, warnings |
| `Xcode/scripts/*.sh` (create) | One script per non-native rule (gen_test, markdown, ragel, icon, utf16) |
| `.github/workflows/ci.yml` (modify) | Switch from ninja to `xcodebuild` |

---

### Task 1: Inventory the rave build into machine-readable form

**Files:**
- Create: `bin/rave2yaml`
- Create: `docs/benchmarks/2026-08-12-rave-inventory.md`

**Interfaces:**
- Produces: `bin/rave2yaml --inventory` printing every target with its kind, sources globs, `require` deps, `tests` globs, `frameworks`, and `libraries`. Later tasks consume this.

- [ ] **Step 1: Write the failing test**

Create `tests/rave2yaml_test.sh`:

```bash
#!/bin/bash
# Every .rave-declared target must appear in the inventory, and dependency
# names must resolve to known targets. A parser that silently drops targets
# is worse than one that crashes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

declared=$(grep -lE '^[[:space:]]*(sources|executable)[[:space:]]' \
    Frameworks/*/default.rave Applications/*/default.rave | wc -l | tr -d ' ')
found=$(./bin/rave2yaml --inventory | grep -c '^target ')

[ "$declared" = "$found" ] || {
    echo "FAIL: $declared targets declared in .rave, $found found by parser"; exit 1; }

# every `require` name must resolve
./bin/rave2yaml --inventory > /tmp/inv.txt
names=$(awk '/^target /{print $2}' /tmp/inv.txt | sort -u)
for dep in $(awk '/^  requires /{$1=""; print}' /tmp/inv.txt | tr ' ' '\n' | sort -u); do
    grep -qx "$dep" <<<"$names" || { echo "FAIL: unresolved dependency: $dep"; exit 1; }
done
echo "PASS: $found targets, all dependencies resolve"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/rave2yaml_test.sh`
Expected: FAIL — `./bin/rave2yaml: No such file or directory`

- [ ] **Step 3: Write `bin/rave2yaml`**

A Ruby or Python script (Ruby matches the existing `bin/` tooling). It must:
- Walk `Frameworks/*/default.rave` and `Applications/*/default.rave`
- Parse the directives observed in this tree: `sources`, `tests`, `require`, `frameworks`, `libraries`, `executable`, `resources`, `entitlements`
- Expand `sources`/`tests` globs relative to the `.rave` file's directory
- Emit `--inventory` (human-readable) now; `project.yml` comes in Task 4
- **Fail loudly on any directive it does not recognise.** Silently ignoring an unknown directive is how a converted build ends up subtly wrong.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/rave2yaml_test.sh`
Expected: PASS, with a target count matching the `.rave` files (expect ~56: 46 frameworks + 10 apps).

- [ ] **Step 5: Record the inventory**

Write `docs/benchmarks/2026-08-12-rave-inventory.md` with the full target list, their dependency edges, and which have tests. This is the checklist Task 7 verifies parity against.

- [ ] **Step 6: Commit**

```bash
git add bin/rave2yaml tests/rave2yaml_test.sh docs/benchmarks/2026-08-12-rave-inventory.md STREAM.md
git commit -m "build: add rave2yaml inventory pass"
```

---

### Task 2: Baseline the ninja build's real outputs

**Files:**
- Create: `docs/benchmarks/2026-08-12-ninja-parity.md`

**Interfaces:**
- Produces: the authoritative list of artifacts and test results the Xcode build must match. Without this, "parity" is an opinion.

- [ ] **Step 1: Capture the artifact list**

```bash
./bin/build TextMate
find "$HOME/build/textmate-revived/release" -type f \
  \( -perm -u+x -o -name '*.a' -o -name '*.dylib' \) | sed "s|.*/release/||" | sort > /tmp/ninja-artifacts.txt
wc -l /tmp/ninja-artifacts.txt
```

- [ ] **Step 2: Capture the test baseline**

```bash
TESTS=$(grep -lE '^[[:space:]]*tests[[:space:]]' Frameworks/*/default.rave \
        | sed 's|/default.rave||' | sed 's|$|/test|')
./bin/build $TESTS 2>&1 | tee /tmp/ninja-tests.log; echo "exit=$?"
```

Record how many test targets ran and which passed. If any fail on this machine, record which — CI already excludes `buffer`, `cf`, `layout`, `command`, `editor`, `file` as headless-hostile, and a local failure outside that set is a finding.

- [ ] **Step 3: Record both**

Write `docs/benchmarks/2026-08-12-ninja-parity.md` with the artifact count, the test target list, pass/fail per target, and the excluded-in-CI set. State explicitly that the Xcode build must reproduce this list before ninja is deleted.

- [ ] **Step 4: Commit**

```bash
git add docs/benchmarks/2026-08-12-ninja-parity.md STREAM.md
git commit -m "test: record ninja build parity baseline"
```

---

### Task 3: Decide the header strategy by experiment

**Files:**
- Create: `Xcode/Base.xcconfig`
- Create: `docs/benchmarks/2026-08-12-header-strategy.md`

**Interfaces:**
- Produces: the `HEADER_SEARCH_PATHS` value every later target inherits. **Every subsequent task depends on this. Do not guess it.**

- [ ] **Step 1: Establish what must resolve**

```bash
grep -rhoE '#include <[a-z_]+/[A-Za-z_.]+\.h>' Frameworks/*/src Applications/*/src 2>/dev/null \
  | sort -u | head -30
grep -rhoE '#include <[a-z_]+/[A-Za-z_.]+\.h>' Frameworks/*/src 2>/dev/null | wc -l
```

Expected: cross-framework includes of the form `<buffer/buffer.h>`, resolving to `Frameworks/buffer/src/buffer.h`.

- [ ] **Step 2: Test option 1 — plain search path**

Build one leaf framework by hand with only `-I` and no header copying:

```bash
SDK=$(xcrun --show-sdk-path --sdk macosx)
xcrun clang++ -std=c++23 -target arm64-apple-macos26.0 -isysroot "$SDK" \
  -I"$PWD/Frameworks" -c Frameworks/text/src/utf8.cc -o /tmp/utf8.o 2>&1 | head -20
echo "exit=$?"
```

`Frameworks/text/src/utf8.cc` includes `<text/…>`, which under `-I$PWD/Frameworks` would need to resolve as `Frameworks/text/…` — it will NOT, because the real header is at `Frameworks/text/src/…`. Expect failure. That failure is the point: it tells us the flat `-I` cannot work without a mapping.

- [ ] **Step 3: Test option 2 — generated header root**

```bash
rm -rf /tmp/hdrroot && mkdir -p /tmp/hdrroot
for d in Frameworks/*/; do n=$(basename "$d"); [ -d "$d/src" ] && ln -s "$PWD/$d/src" "/tmp/hdrroot/$n"; done
xcrun clang++ -std=c++23 -target arm64-apple-macos26.0 -isysroot "$SDK" \
  -I/tmp/hdrroot -c Frameworks/text/src/utf8.cc -o /tmp/utf8.o 2>&1 | head -20
echo "exit=$?"
```

Expected: PASS. A symlink farm mirrors rave's export without copying 369 files.

- [ ] **Step 4: Record the decision and write the xcconfig**

Write `docs/benchmarks/2026-08-12-header-strategy.md` stating which option worked, with the commands and their output. Then create `Xcode/Base.xcconfig` with the chosen `HEADER_SEARCH_PATHS`, plus:

```
ARCHS = arm64
ONLY_ACTIVE_ARCH = YES
MACOSX_DEPLOYMENT_TARGET = 26.0
CLANG_CXX_LANGUAGE_STANDARD = c++23
CLANG_ENABLE_OBJC_ARC = YES
SWIFT_VERSION = 6.0
GCC_WARN_ABOUT_RETURN_TYPE = YES
CLANG_WARN_DOCUMENTATION_COMMENTS = NO
```

- [ ] **Step 5: Commit**

```bash
git add Xcode/Base.xcconfig docs/benchmarks/2026-08-12-header-strategy.md STREAM.md
git commit -m "build: decide Xcode header search strategy by experiment"
```

---

### Task 4: Generate and build one leaf framework with its tests

**Files:**
- Modify: `bin/rave2yaml` (add `project.yml` emission)
- Create: `project.yml`
- Create: `Xcode/scripts/gen_test.sh`

**Interfaces:**
- Produces: a working XcodeGen spec for one framework plus its test target. This is the pattern Task 5 replicates 45 more times — get it right before scaling.

Use `text` as the pilot: it is a leaf (few or no `require` deps) and it has tests (`Frameworks/text/default.rave:4`).

- [ ] **Step 1: Write the failing test**

Create `tests/xcode_parity_test.sh`:

```bash
#!/bin/bash
# A target builds under Xcode AND its CxxTest binary runs green.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TARGET="${1:?usage: xcode_parity_test.sh <target>}"

xcodebuild -project TextMate.xcodeproj -target "$TARGET" \
    -configuration Release build CODE_SIGNING_ALLOWED=NO > /tmp/xcb.log 2>&1 || {
    echo "FAIL: xcodebuild failed for $TARGET"; tail -20 /tmp/xcb.log; exit 1; }

echo "PASS: $TARGET builds under Xcode"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/xcode_parity_test.sh text`
Expected: FAIL — no `TextMate.xcodeproj` exists yet.

- [ ] **Step 3: Emit `project.yml` for the pilot target only**

Extend `bin/rave2yaml` with a `--emit-yaml <target>...` mode producing an XcodeGen spec containing only the named targets and their transitive `require` closure. Each framework becomes a static library target; each `tests` glob becomes a companion command-line-tool target.

- [ ] **Step 4: Write the CxxTest script phase**

Create `Xcode/scripts/gen_test.sh` wrapping the existing `bin/gen_test` so the test target's sources are generated into `$DERIVED_FILE_DIR` before compiling. Mirror what `build.ninja`'s `GenTest` rule does — read it rather than inventing.

- [ ] **Step 5: Generate and build**

```bash
xcodegen generate --spec project.yml
bash tests/xcode_parity_test.sh text
```

Expected: PASS.

- [ ] **Step 6: Verify the test binary actually runs green**

```bash
xcodebuild -project TextMate.xcodeproj -target text_test -configuration Release build CODE_SIGNING_ALLOWED=NO
"$(xcodebuild -project TextMate.xcodeproj -target text_test -configuration Release -showBuildSettings \
   | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')/text_test"
echo "exit=$?"
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add bin/rave2yaml project.yml Xcode/scripts/gen_test.sh tests/xcode_parity_test.sh STREAM.md
git commit -m "build: generate and build the text framework under Xcode"
```

---

### Task 5: Scale to all 46 frameworks

**Files:**
- Modify: `bin/rave2yaml`, `project.yml`

- [ ] **Step 1: Emit all framework targets**

Run `bin/rave2yaml --emit-yaml --all-frameworks > project.yml`, regenerate, and build each target.

- [ ] **Step 2: Build them all and record failures**

```bash
xcodegen generate --spec project.yml
for t in $(./bin/rave2yaml --inventory | awk '/^target /{print $2}'); do
  xcodebuild -project TextMate.xcodeproj -target "$t" -configuration Release build \
    CODE_SIGNING_ALLOWED=NO >/dev/null 2>&1 && echo "ok   $t" || echo "FAIL $t"
done | tee /tmp/xcode-targets.log
grep -c '^FAIL' /tmp/xcode-targets.log
```

- [ ] **Step 3: Fix failures one framework at a time**

Do not batch-fix. Each failure is either a missing dependency edge, a missing build phase, or a header-resolution gap — and the three have different fixes. Record each cause in the commit message.

- [ ] **Step 4: Commit**

```bash
git add bin/rave2yaml project.yml STREAM.md
git commit -m "build: all frameworks build under Xcode"
```

---

### Task 6: The TextMate app target

**Files:**
- Modify: `bin/rave2yaml`, `project.yml`
- Create: `Xcode/scripts/{markdown,icon,utf16}.sh`

- [ ] **Step 1: Add the app target with its resources**

`Applications/TextMate/default.rave:1-37` declares the bundle: sources, resources, entitlements, Info.plist. Translate all of it. The Info.plist must keep `${APP_VERSION}` substitution sourced from `CHANGELOG.md` — verify the built app reports the same version as the ninja build.

- [ ] **Step 2: Port the non-native rules as script phases**

One script per rule, each mirroring what `build.ninja` does: `CompileMarkdown` (32 edges), `CompileIcon` (2), `ConvertToUTF16` (8), `CompileRagel` (2), plus `RunExecutable`/`RunApplication` (30 combined). Read each rule's command line out of `build.ninja` rather than reconstructing it.

- [ ] **Step 3: Build and verify identity**

```bash
xcodebuild -project TextMate.xcodeproj -scheme TextMate -configuration Release build
```

Then confirm the built app's `CFBundleName`, `CFBundleShortVersionString`, and `CFBundleIdentifier` match the ninja-built app exactly.

- [ ] **Step 4: Verify it launches and deploy**

```bash
./bin/deploy-local "<path to Xcode-built TextMate.app>"
```

`bin/deploy-local`'s identifier guard must pass — that is itself a check that the Xcode build produced the right bundle.

- [ ] **Step 5: Commit**

```bash
git add bin/rave2yaml project.yml Xcode/scripts STREAM.md
git commit -m "build: TextMate.app builds and runs from Xcode"
```

---

### Task 7: Prove parity, then commit the generated project

**Files:**
- Create: `TextMate.xcodeproj` (committed)
- Modify: `docs/benchmarks/2026-08-12-ninja-parity.md`

- [ ] **Step 1: Compare artifacts against Task 2's baseline**

Every executable and static library ninja produced must have an Xcode counterpart. Record any that do not, with a reason — an unexplained missing artifact blocks Task 8.

- [ ] **Step 2: Run every test target under Xcode**

All 54 must build; all must pass except the six CI excludes. Record the results in the parity doc.

- [ ] **Step 3: Commit the generated project**

Committing `TextMate.xcodeproj` means contributors need only Xcode. `project.yml` stays the source of truth; the `.xcodeproj` is regenerated with `xcodegen generate`.

```bash
git add TextMate.xcodeproj docs/benchmarks/2026-08-12-ninja-parity.md STREAM.md
git commit -m "build: commit generated Xcode project after parity verification"
```

---

### Task 8: Delete rave, switch CI, strip Intel

**Files:**
- Delete: `configure`, `bin/rave`, all 63 `*.rave` files, `.travis.yml`, `local-orig.rave`
- Modify: `.github/workflows/ci.yml`, `.github/workflows/build-and-test.yml`, `README.md`, `CONTRIBUTING.md`, `bin/build`

**Do this only after Task 7 proves parity.** This is the irreversible step.

- [ ] **Step 1: Switch CI to xcodebuild**

Replace the ninja invocations with `xcodebuild`, keeping the `github.repository` guard on every job and keeping the six headless-hostile test excludes.

- [ ] **Step 2: Delete the rave build**

```bash
git rm -r configure bin/rave local-orig.rave .travis.yml
git rm $(git ls-files '*.rave')
```

- [ ] **Step 3: Confirm no Intel remains**

```bash
grep -rn "x86_64\|i386" --include='*.yml' --include='*.xcconfig' --include='project.yml' . | grep -v vendor/ || echo "clean"
lipo -archs "<built TextMate.app>/Contents/MacOS/TextMate"
```

Expected: `clean`, and `arm64` only.

- [ ] **Step 4: Rewrite the build documentation**

`README.md` and `CONTRIBUTING.md` currently describe `./configure && ninja`. They become Xcode instructions **in this same commit** — this is the commit where those docs would otherwise start lying.

- [ ] **Step 5: Update `bin/build`**

Its Ruby-environment workaround is still needed if any script phase shells out to Ruby; its ninja invocation is not. Rewrite it to call `xcodebuild`, keeping the credits-cache guard if `gen_credits.rb` is still in the build.

- [ ] **Step 6: Commit**

```bash
git commit -m "build!: replace rave/ninja with the Xcode project"
```

---

## Phase 2 Exit Criteria

- [ ] `open TextMate.xcodeproj` → Cmd-B → app builds and runs.
- [ ] `xcodebuild -scheme TextMate -configuration Release build` succeeds from a clean clone.
- [ ] All 54 test targets build; all pass except the six documented CI excludes.
- [ ] Artifact parity with Task 2's ninja baseline, or every difference explained in the parity doc.
- [ ] `lipo -archs` reports `arm64` only.
- [ ] No `.rave` file, `configure`, `bin/rave`, or `.travis.yml` remains.
- [ ] CI green on `xcodebuild`, every job guarded.
- [ ] `README.md` and `CONTRIBUTING.md` describe the Xcode build.
- [ ] `bin/deploy-local` installs the Xcode-built app and its identifier guard passes.

## Risks

| Risk | Mitigation |
|---|---|
| Header resolution differs subtly from rave's flat export, causing wrong-header-wins bugs | Task 3 decides by experiment and records the evidence; Task 5 builds all 46 frameworks before anything depends on it |
| A script phase silently no-ops, dropping a resource | Task 7 compares artifact lists against a recorded baseline rather than eyeballing |
| `bin/rave2yaml` silently ignores an unrecognised directive | It is specified to fail loudly instead; Task 1's test asserts target-count parity |
| Deleting rave before parity | Task 8 is gated on Task 7 and is the only irreversible task |
| Build-time codegen tools (`RunExecutable`, 18 edges) are unidentified | Task 6 Step 2 reads their command lines out of `build.ninja` rather than reconstructing them |
