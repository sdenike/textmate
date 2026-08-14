# ninja build parity baseline — 2026-08-12

Date: 2026-08-12
Decides: nothing (recording only). Gates Task 7 (Xcode build must reproduce this) and,
transitively, Task 8 (deleting the rave/ninja build — the only irreversible task in Phase 2).

This document is not an assertion that the build is correct. It is a record of what
`./bin/build` actually produces and what its test targets actually do on this machine,
today, so that a later "the Xcode build reaches parity" claim can be checked against real
numbers instead of taken on faith.

## Method

```
./bin/build TextMate
find "$HOME/build/textmate-revived/release" -type f \
  \( -perm -u+x -o -name '*.a' -o -name '*.dylib' \) | sed "s|.*/release/||" | sort
```

Build output directory: `$HOME/build/textmate-revived/release` (already baked into the
checked-out `build.ninja`'s `-b` flag from a prior `./configure` run this session; `bin/build`
would have called `./configure` itself had `build.ninja` been absent).

**Test-target discovery matches CI exactly** (`.github/workflows/build-and-test.yml:60-63`),
not the simplified form in this task's own brief. The brief's inline snippet
(`sed 's|/default.rave||'`) keeps the `Frameworks/` prefix, producing names like
`Frameworks/authorization/test`; ninja rejects that (`unknown target`, suggesting the
unrelated `Frameworks/authorization/tests` — a unit_ninja fuzzy match, not a real target).
`bin/rave`'s actual phony output is `target[:identifier] + '/test'`, and
`target[:identifier]` is the bare name from the `target "${dirname}"` directive
(`authorization`, not `Frameworks/authorization`) — confirmed both by reading
`bin/rave:773,1464` and by grepping the generated `build.ninja` for
`^build authorization/test`. CI's `dirname | basename` pipeline already produces the correct
bare name; used that instead:

```bash
grep -lE '^[[:space:]]*tests[[:space:]]' Frameworks/*/default.rave \
  | xargs -n1 dirname | xargs -n1 basename | sort
```

This finds **26** test-bearing frameworks, matching Task 1's independent `bin/rave2yaml
--inventory` count (`tests` directive, 26×) exactly.

Each of the 26 was then built/run **individually** (`./bin/build <name>/test`, one target per
invocation) rather than as one combined command. Reason: ninja's own progress line mislabels
every `RunTest` step — regardless of which framework's binary is actually executing, the
printed description always reads `Run tests for 'scope'…`. Root cause, read out of
`bin/rave:1444-1466`: rave emits one ninja `rule RunTest { … description = "Run tests for
'#{target[:name]}'…" }` stanza per framework, but ninja rules are looked up **by name**, and
all of them share the name `RunTest` — so only one stanza's `description` text survives in
the final `build.ninja`, and every edge that uses the `RunTest` rule prints that same fixed
string. The `command` itself (`$in $flags`) is bound per-edge correctly (confirmed: `scm`'s
and `buffer`'s failure output below correctly names their own source files, so the right
binary runs) — only the human-readable progress text is wrong. This is a real, pre-existing
cosmetic bug worth flagging on its own, and it is why this baseline does not trust the
brief's literal batched-log approach for per-target attribution. Not fixed — out of scope for
a diagnostic task.

## Artifact baseline

Build succeeded. Confirmed twice: zero `FAILED:` lines in the build log, and a second,
fully-idempotent `./bin/build TextMate` run afterward exited 0 (it re-signed 39 already-built
outputs — codesign is not restat-cached in this build — but performed no failing step).

**Total artifacts (executables, `.a`, `.dylib`) under the release directory: 41.** Zero `.a`
and zero `.dylib` — consistent with Task 4's baseline finding that this tree's ~45
`Frameworks/` modules are already fully statically linked; nothing here ships as a loadable
dylib.

Full list, paths relative to `$HOME/build/textmate-revived/release`:

```
Applications/mate/mate
Applications/PrivilegedTool/PrivilegedTool
Applications/QuickLookGenerator/TextMateQL.qlgenerator/Contents/MacOS/TextMateQL
Applications/TextMate/TextMate.app/Contents/Library/QuickLook/TextMateQL.qlgenerator/Contents/MacOS/TextMateQL
Applications/TextMate/TextMate.app/Contents/MacOS/CommitWindowTool
Applications/TextMate/TextMate.app/Contents/MacOS/mate
Applications/TextMate/TextMate.app/Contents/MacOS/TextMate
Applications/TextMate/TextMate.app/Contents/MacOS/tm_query
Applications/TextMate/TextMate.app/Contents/PlugIns/Dialog.tmplugin/Contents/MacOS/Dialog
Applications/TextMate/TextMate.app/Contents/PlugIns/Dialog.tmplugin/Contents/Resources/tm_dialog
Applications/TextMate/TextMate.app/Contents/PlugIns/Dialog2.tmplugin/Contents/MacOS/Dialog2
Applications/TextMate/TextMate.app/Contents/PlugIns/Dialog2.tmplugin/Contents/Resources/tm_dialog2
Applications/TextMate/TextMate.app/Contents/Resources/PrivilegedTool
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/backfill_descriptions.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/build_filetype_index.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/checknest.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/find_app
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/html_man.sh
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/man2html
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/Markdown.pl
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/mate
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/play
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/ruby
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/SmartyPants.pl
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/bin/tm_dialog
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/lib/markdown_to_help.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/lib/osx/keychain.bundle
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/lib/osx/plist.bundle
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/lib/textmate.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Bundle Support.tmbundle/Support/shared/private/track_usage.rb
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Source.tmbundle/Commands/Unwrap Braces.tmCommand
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Source.tmbundle/Commands/Wrap in Braces.tmCommand
Applications/TextMate/TextMate.app/Contents/SharedSupport/Bundles/Source.tmbundle/Support/bin/reindent.rb
Applications/tm_query/tm_query
Frameworks/CommitWindow/CommitWindowTool
PlugIns/dialog-1.x/Dialog.tmplugin/Contents/MacOS/Dialog
PlugIns/dialog-1.x/Dialog.tmplugin/Contents/Resources/tm_dialog
PlugIns/dialog-1.x/tm_dialog
PlugIns/dialog/Dialog2.tmplugin/Contents/MacOS/Dialog2
PlugIns/dialog/Dialog2.tmplugin/Contents/Resources/tm_dialog2
PlugIns/dialog/tm_dialog2
```

(Captured before any test target was built, so it contains no `_Test/*` test-harness
binaries — those are build scaffolding, not product artifacts, and are excluded by design,
not by the `find` filter.)

## Test baseline

All 26 discovered test targets were attempted. **None were skipped and none were left
incomplete** — total wall-clock for all 26 individual invocations was **5 minutes 22
seconds** (19:38:14–19:43:36), well inside the 25-minute time-box.

### CI-included targets (20) — CI requires these to pass

| Target | Result |
|---|---|
| authorization/test | PASS |
| bundles/test | PASS |
| BundlesManager/test | PASS |
| document/test | PASS |
| encoding/test | PASS |
| FileBrowser/test | PASS |
| HTMLOutput/test | PASS |
| io/test | PASS |
| network/test | PASS |
| ns/test | PASS |
| parse/test | PASS |
| plist/test | PASS |
| regexp/test | PASS |
| **scm/test** | **FAIL** |
| scope/test | PASS |
| selection/test | PASS |
| settings/test | PASS |
| SoftwareUpdate/test | PASS |
| text/test | PASS |
| theme/test | PASS |

**19 of 20 pass. `scm/test` fails outside the six CI-documented excludes — a genuine local
finding, not a code defect:**

```
scm: 2 of 84 tests failed:
Frameworks/scm/tests/t_hg.cc:13: Unable to test mercurial driver (hg executable not found).
Frameworks/scm/tests/t_svn.cc:13: Unable to test subversion driver (svn executable not found).
```

Confirmed: `hg` and `svn` are both absent from `PATH` on this machine. CI's own workflow
(`build-and-test.yml:40`) explicitly `brew install`s `mercurial subversion` before testing;
this local dev machine was never provisioned with either. Not fixed (diagnostic task,
environment-only gap) — noted here so Task 7 knows to provision both, or to expect this same
failure, before comparing against this baseline.

### CI-excluded targets (6) — headless-hostile per `build-and-test.yml:49-59`

Attempted anyway, per this task's instruction to record what happens rather than what should
happen. Not required for parity, but any surprise here is still worth knowing.

| Target | CI's stated reason | Local result | Detail |
|---|---|---|---|
| buffer/test | spellcheck needs `NSSpellChecker` dictionary (no headless support) | FAIL | `3 of 26 tests failed` — all three in `t_buffer.mm`'s `misspellings()` assertions. Matches CI's reason exactly. |
| cf/test | (grouped with layout: trap/segfault) | **CRASH** | Exit 138 = SIGBUS. No test summary printed — it died before reporting. Consistent with CI's "trap/segfault" characterization. |
| layout/test | pure C++ data-structure tests trap/segfault **under parallel runner** | PASS | Passed cleanly run standalone. CI's stated cause is specific to parallel scheduling, which a single isolated invocation doesn't exercise — not a contradiction of CI's reason, but also not reproduced here. |
| command/test | `wait_for_command()` polls NSApp; with `NSApp` nil the completion path never fires and the test **hangs to job timeout** | PASS | Completed in ~1 second. No hang observed. |
| editor/test | same NSApp/runloop cause as command | PASS | Completed in ~2 seconds. No hang observed. |
| file/test | `iconv //TRANSLIT` differs between macOS 14.5 (CI) and 26 (local) | FAIL | `1 of 11 tests failed` — `t_save.cc` transliteration assertion. Matches CI's reason exactly. |

**Three of the six (layout, command, editor) did not fail locally**, against a documented CI
reason that is specifically about CI's headless runner environment (no logged-in GUI session,
so `NSApp` truly never initializes; parallel scheduling contention). This machine is a normal
interactive, logged-in session, so the precondition for those three failures doesn't hold
here. This is not evidence the CI exclusion list is wrong — it is evidence that "passes on
this developer machine" and "passes on CI's headless runner" are different claims. Task 7/8
should keep treating the six-name list in `build-and-test.yml` as authoritative for CI, not
substitute this machine's results for it.

## Time-box

Brief's Step 2 allowed up to 25 minutes for the full test run. Actual: **5m 22s**, all 26
targets attempted to completion (pass, fail, or crash — none left mid-run or unattempted).

## Parity requirement

**Before Task 8 deletes the rave/ninja build, the Xcode build must reproduce:**

1. All 41 artifacts listed above (or their Xcode-equivalent product-output paths), building
   without error, from `xcodebuild`.
2. The same 20/6 test-target pass/fail split recorded here — 19 of the 20 CI-included targets
   passing, `scm/test` failing for the identical documented reason (or passing, if `hg`/`svn`
   are provisioned) — and, for the six CI-excluded targets, results consistent with CI's own
   documented exclusions rather than this local machine's more permissive results for
   layout/command/editor.

Until both hold, "the Xcode build reaches parity" is an opinion, not a fact this repository
can check.

---

## Xcode build parity — 2026-08-13 (Task 7)

Measured against the two requirements above, from a real `TextMate.xcodeproj` (86 targets,
committed this same task) built with `xcodebuild`, not assumed from the project generator's
intent. Build output: `$HOME/build/textmate-revived/xcode` (`SYMROOT`/`OBJROOT` fixed there
since Task 6; never `/tmp`).

### Method

```
xcodebuild -project TextMate.xcodeproj -scheme TextMate -configuration Release build
```

real ad-hoc codesigning, same as Task 6 — not `CODE_SIGNING_ALLOWED=NO`, which only the
per-target test builds below use. Artifacts enumerated with the same `find … -perm -u+x`
shape this document's ninja baseline used, run against the Xcode output tree instead. Each of
the 26 test targets was then built and run **individually**
(`xcodebuild … -target <name>_test -configuration Release build CODE_SIGNING_ALLOWED=NO`,
then the produced binary executed directly with `-v`), for the same reason this document's
ninja baseline gives for doing it that way: unambiguous per-target attribution. Total
wall-clock for all 26: **2m 13s** (14:47:13–14:49:26), faster than ninja's 5m22s because most
targets' own framework dependencies were already built by the preceding full-scheme build —
only each test target's own generated CxxTest runner needed compiling.

### Artifact parity: 41/41, by identity

The two build systems lay out output differently (ninja nests inside `Applications/`,
`Frameworks/`, `PlugIns/`; Xcode's `CONFIGURATION_BUILD_DIR` is flat), so every one of ninja's
41 recorded paths was reduced to a **binary identity** (basename + kind) and checked for an
Xcode counterpart, not matched path-for-path. All 41 collapse onto exactly **10 distinct
executable-producing Xcode targets**, each confirmed present at every location ninja put it:

| Identity | ninja occurrences (of 41) | Xcode confirmation |
|---|---|---|
| `TextMate` (app) | 1: embedded in `TextMate.app/Contents/MacOS/` | ✓ same relative path in the built `TextMate.app` |
| `mate` (tool) | 3: standalone; embedded in `TextMate.app/Contents/MacOS/`; copied into `SharedSupport/…/shared/bin/` | ✓ all 3 |
| `tm_query` (tool) | 2: standalone; embedded in `TextMate.app/Contents/MacOS/` | ✓ both |
| `PrivilegedTool` (tool) | 2: standalone; embedded in `TextMate.app/Contents/Resources/` | ✓ both |
| `CommitWindowTool` (tool) | 2: standalone (`Frameworks/CommitWindow/`); embedded in `TextMate.app/Contents/MacOS/` | ✓ both — **the one real gap, see below** |
| `Dialog` (plugin executable) | 2: standalone `PlugIns/dialog-1.x/Dialog.tmplugin/…`; embedded in `TextMate.app/Contents/PlugIns/` | ✓ both |
| `tm_dialog` (tool) | 4: bare standalone; standalone bundle's `Resources/`; embedded bundle's `Resources/`; copied into `SharedSupport/…/shared/bin/` | ✓ all 4 |
| `Dialog2` (plugin executable) | 2: standalone; embedded | ✓ both |
| `tm_dialog2` (tool) | 3: bare standalone; standalone bundle's `Resources/`; embedded bundle's `Resources/` | ✓ all 3 |
| `TextMateQL` (qlgenerator executable) | 2: standalone `Applications/QuickLookGenerator/…`; embedded in `TextMate.app/Contents/Library/QuickLook/` | ✓ both |

That accounts for 1+3+2+2+2+2+4+2+3+2 = **23** of the 41. The remaining **18** are resource
copies inside `TextMate.app/Contents/SharedSupport/` — 20 total between `Bundle
Support.tmbundle` (17 scripts/loadable-bundles) and `Source.tmbundle` (`Unwrap Braces.tmCommand`,
`Wrap in Braces.tmCommand`, `reindent.rb`), minus 2 (`mate` and `tm_dialog`'s own `SharedSupport`
copies) already counted above as occurrences of those two tool identities. All 18 reconfirmed
present, byte-for-byte-named, via the same `find` sweep against the Xcode-built `TextMate.app`;
these are plain `assemble_resources.sh` copies (Task 6), not independent Xcode build targets, so
there was nothing new to verify about *how* they're built — only that the script still runs and
still copies all of them, which it does.

**23 + 18 = 41. Every ninja artifact has a confirmed Xcode counterpart.**

**One real gap found, and fixed, not explained away:** `CommitWindowTool` was initially
**missing** from `TextMate.app/Contents/MacOS/` — 29 executables under the Xcode-built app
instead of ninja's 30. Root cause: `Frameworks/CommitWindow/default.rave:5` has
`files @CommitWindowTool "MacOS"`, but that directive is declared on a plain *library*
(`CommitWindow`) that `TextMate` only `require`s — not on `TextMate`'s own `default.rave`. Real
rave (`bin/rave:1097`, `signature()`) folds every *required* target's own `files`/`copy` assets
into the requiring bundle, a propagation `bin/rave2yaml`'s hand-verified `EMBED` table (Task 6)
didn't cover; the table only captured directives declared directly on a bundle-producing
target. Fixed in `bin/rave2yaml` (commit `4f848f7b`): `CommitWindowTool` added to
`EMBED['TextMate']`. That also surfaced a second, previously-latent bug it depended on fixing
first — `CommitWindowTool` is the first tool-kind target with neither a `require` nor a
`frameworks`/`libraries` line, so `emit_tool_target`'s unconditional `dependencies:` YAML key
had nothing under it (`nil`, not `[]`, to a parser) and XcodeGen rejected the whole project.
Fixed by only emitting the key when there is at least one target or SDK to list. Verified:
`TextMate.app` rebuilt clean afterward has all 30.

**Xcode-only additional products, not a discrepancy:** 48 `.a` static libraries (46 Frameworks
+ `Onigmo` + `xdiff`) and matching `.dSYM` bundles sit in the same flat `Release/` directory.
Ninja has no equivalent for either — it links every object file directly into each final
binary rather than through an intermediate archive step (this document's own ninja baseline:
"zero `.a` and zero `.dylib`"), and doesn't split debug info into separate `.dSYM` bundles.
These are inherent to how Xcode's `type: library.static` and default debug-info settings work,
not artifacts a user or Task 8 needs to account for — nothing consumes them except the final
link, exactly like ninja's own intermediate `.o` files, which the original baseline also
excluded by design ("build scaffolding, not product artifacts").

### Test parity: 26/26 targets, same pattern as the ninja baseline

| Target | ninja (2026-08-12) | Xcode (2026-08-13) | Match |
|---|---|---|---|
| authorization | PASS | PASS (1 test) | ✓ |
| bundles | PASS | PASS (5 tests) | ✓ |
| BundlesManager | PASS | PASS (10 tests) | ✓ |
| document | PASS | PASS (9 tests) | ✓ |
| encoding | PASS | PASS (6 tests) | ✓ |
| FileBrowser | PASS | PASS (1 test) | ✓ |
| HTMLOutput | PASS | PASS (1 test) | ✓ |
| io | PASS | PASS (24 tests) | ✓ |
| network | PASS | PASS (1 test) | ✓ |
| ns | PASS | PASS (6 tests) | ✓ |
| parse | PASS | PASS (4 tests) | ✓ |
| plist | PASS | PASS (33 tests) | ✓ |
| regexp | PASS | PASS (41 tests) — **1 of 41 failed before the Onigmo fix below** | ✓ |
| **scm** | **FAIL** (2/84: `hg`/`svn` not on this machine) | **FAIL** (identical: 2/84, same `hg`/`svn` message) | ✓ |
| scope | PASS | PASS (13 tests) | ✓ |
| selection | PASS | PASS (24 tests) | ✓ |
| settings | PASS | PASS (9 tests) | ✓ |
| SoftwareUpdate | PASS | PASS (20 tests) | ✓ |
| text | PASS | PASS (34 tests) | ✓ |
| theme | PASS | PASS (1 test) | ✓ |
| buffer (CI-excluded) | FAIL (3/26, misspellings) | FAIL (identical: 3/26, same 3 assertions, same file/line) | ✓ |
| cf (CI-excluded) | CRASH (SIGBUS, exit 138) | CRASH (identical: exit 138, no summary printed) | ✓ |
| layout (CI-excluded) | PASS (local machine only) | PASS (9 tests) | ✓ |
| command (CI-excluded) | PASS (local machine only) | PASS (4 tests) | ✓ |
| editor (CI-excluded) | PASS (local machine only) | PASS (9 tests) | ✓ |
| file (CI-excluded) | FAIL (1/11, iconv TRANSLIT) | FAIL (identical: 1/11, same `t_save.cc` transliteration assertion) | ✓ |

**26 of 26 targets match the ninja baseline's result exactly** — same pass/fail/crash, same
counts, same failing assertions where applicable. 19 of the 20 CI-included targets pass, `scm`
fails for the identical documented environment reason (this machine still has neither `hg` nor
`svn`); the six CI-excluded targets reproduce this local machine's own more-permissive
layout/command/editor passes exactly as recorded, not CI's headless-only failures — consistent
with the baseline's own note that "passes on this developer machine" and "passes on CI's
headless runner" are different claims, and Task 7/8 should keep treating
`build-and-test.yml`'s six-name list as authoritative for CI either way.

### The regexp/Onigmo discrepancy: root-caused and fixed

Confirmed still present at the start of this task exactly as Task 5 described:
`regexp_test` failing 1 of 41 — `capitalize()` on `"æblegrød"` producing `"æBlegrød"` (the
*second* letter capitalized, not the first) instead of `"Æblegrød"`.

**Ruled out by direct measurement, not reasoning** (`xcodebuild -showBuildSettings` and the
real build log's response file, compared line-by-line against `build.ninja`'s own `flags =`
for the same Onigmo translation units):
- Source-file set: identical 24 files on both sides (Onigmo's brace-expansion glob resolved by
  hand and diffed against both `build.ninja` and `project.yml`'s `sources:`).
- `-funsigned-char`, `-std=c99`, `-Os`, `-flto=thin`/`LLVM_LTO=YES_THIN`, `-DNDEBUG`: present,
  byte-identical, on both sides' actual captured compiler invocations.
- `vendor/Onigmo/config.h`: the only copy on either build's header search path; the one extra
  Xcode-side `-I` path (`$(CONFIGURATION_BUILD_DIR)/include`) doesn't exist on disk, a no-op.
- `-fno-common`: tested in isolation (compiled all 24 files with and without it) — doesn't
  reproduce the bug either way.
- LTO itself: tested with `LLVM_LTO=NO` on a fully clean rebuild — bug persisted. Not LTO.
- PCH content/staleness: tested against a completely cleared `SharedPrecompiledHeaders` cache
  plus a from-scratch `Onigmo.build` — bug persisted. Not PCH.

**Root cause, isolated by linking the exact same freshly-built objects two different ways:**
Xcode's own compiled `.o` files for Onigmo, linked *directly* (no archive) against a minimal
`onig_new`/`onig_search` probe, behave correctly. The identical objects, consulted through
`libtool -static`'s `libOnigmo.a` instead, do not. `vendor/Onigmo/src/setup.c` is a bare
`__attribute__((constructor))` — `libtool`'s own build log literally says
`warning: 'setup.o' has no symbols` — whose only job is calling `onig_set_default_syntax()` to
turn Unicode-range `\w`/`\p{Upper}`/`\p{Lower}` matching on (Onigmo's built-in default has
`ONIG_OPTION_ASCII_RANGE` on, i.e. ASCII-only matching). `bin/rave` links every object file
directly onto each final executable's command line, so `setup.o` always rides along regardless
of whether anything references it. XcodeGen's `type: library.static` instead archives Onigmo
into a real `.a`, and Xcode's final link consults that archive with ordinary lazy,
reference-driven member selection — since nothing ever takes `setup.o`'s address, the linker
never pulls it from the archive, the constructor never runs, and `\w` silently falls back to
ASCII-only. Exactly the observed bug.

**Fixed** (`bin/rave2yaml`, commit `3cb54ea0`): `-force_load $(BUILT_PRODUCTS_DIR)/libOnigmo.a`
added to `OTHER_LDFLAGS` for every tool/bundle/app/test target whose dependency closure links
Onigmo — not just `regexp_test`; the same silent drop would otherwise have shipped inside
`TextMate.app` itself. No `.rave` file or `vendor/Onigmo` source touched.

**Verified both ways, not just on the side that was broken:** `regexp_test` now passes 41/41
under Xcode (confirmed twice — once in isolation, once as part of the full 26-target sweep
above). Ninja's own `regexp/test` was re-run *after* the fix and still passes 41/41 — the fix
touches only the Xcode project generator, so ninja's build is provably unaffected.

### Verdict

**Both parity requirements hold, measured, not assumed:**

1. All 41 ninja artifacts have a confirmed Xcode counterpart by identity. One real gap
   (`CommitWindowTool`) was found, root-caused, and fixed — not discovered and left
   unexplained.
2. All 26 test targets produce the identical pass/fail/crash pattern as the ninja baseline,
   including identical failure counts and assertions where either build fails. The one test
   that genuinely differed between the two builds (`regexp_test`) was root-caused to a real,
   fixed bug in the Xcode project generator, then re-verified passing on both builds.

**Parity is proven.** Task 8 may proceed on the strength of this measurement.

---

## network removed — 2026-08-13 (Phase 3 Task 3)

Phase 3 Task 3's plan assumed `network` needed migrating to `URLSession`. Recon proved that
premise wrong: `Frameworks/SoftwareUpdate` already called `NSURLSession` directly
(`SoftwareUpdate.mm:373`, `OakDownloadManager.mm:78,336`) and `Security.framework` for
signature verification; `network`'s only consumer was its own test
(`Frameworks/network/tests/t_download.cc`). Confirmed independently before deleting anything:
repo-wide `grep` for `#include`/`#import` of any `network/*.h` (`.cc`/`.h`/`.mm`/`.cpp`/`.m`,
excluding `vendor/`) found zero hits outside `Frameworks/network/` itself. `network` was
therefore deleted outright (`git rm -r Frameworks/network`), not migrated — along with its
`Xcode/include/network/` header-staging symlinks (the same per-header-symlink convention
every other framework under `Xcode/include/` uses; leaving them would have left dangling
symlinks pointing at deleted files) and its `network`/`network_test` targets in `project.yml`.

`project.yml` also dropped `libcurl.tbd`: `network/src/download.cc` and `download_tbz.cc`
were the only callers of `curl_easy_*`/`CURL*` anywhere in the tree outside `vendor/`, and the
only two `sdk: libcurl.tbd` lines in `project.yml` were `network_test`'s own dependencies
(deleted with it) and the `TextMate` app target's (removed — nothing else references it).
This build now links zero libcurl.

### Test-target count: 26 → 25, everything else re-verified

`network_test` is gone, dropping this document's ninja-baseline inventory from 26 to 25. All
25 remaining targets were rebuilt and rerun individually (`./bin/build <name>/test`, matching
this document's own per-target methodology) after `xcodegen generate --spec project.yml` and a
full `./bin/build TextMate`, and every one reproduces the result already recorded above,
exactly:

19 of the 20 CI-included targets pass; `scm` still fails the same documented way (`2 of 84`,
`hg`/`svn` absent from this machine). The six CI-excluded targets reproduce the same
pass/fail/crash pattern already recorded: `buffer` FAIL (3/26, misspellings), `cf` CRASH
(SIGBUS, exit 138), `layout`/`command`/`editor` PASS, `file` FAIL (1/11, iconv TRANSLIT).
`command` and `editor` briefly appeared to hang when run back-to-back with 23 other targets in
one long shell invocation that hit a 10-minute wall-clock cap; re-run individually with a
bounded `timeout` guard, both passed in seconds with no hang, matching this document's original
finding for both. `SoftwareUpdate_test` passes (`Frameworks/SoftwareUpdate` was not modified).

`Onigmo_test` also exists in `project.yml` and still passes, but is out of scope for this
comparison: it postdates this document's ninja-derived 26-target inventory (added during the
Xcode migration, no `vendor/Onigmo` equivalent ever existed under the rave/ninja build) and was
never part of the baseline being matched here. `OakAppKit_test` is in the same category — added
2026-08-14 for the Liquid Glass foundation, likewise never part of this baseline. It passes
(8 tests).

### Addendum 2026-08-14 — `command_test` is intermittent, not merely slow

The paragraph above says `command` and `editor` "passed in seconds with no hang" when re-run
individually. That undersells `command`. Measured on 2026-08-14 by running the **same already-built
binary** three times in a row, unchanged, with TextMate.app not running:

```
run 1: exit=0    command_test: 4 tests passed
run 2: exit=137  (hung, killed at the guard)
run 3: exit=137  (hung, killed at the guard)
```

It is **flaky, not deterministic** — consistent with CI's stated reason for excluding it
(`wait_for_command()` polls `NSApp`, which is nil in a test binary, so the completion path fires or
does not depending on timing). A single run of `command_test` is therefore not evidence either way:
one pass does not show health, and one hang does not show breakage. This was learned the hard way —
a single passing run on `master` against a single hanging run on a branch briefly looked like a
regression, and was not.

Always run it under a bounded guard, and treat a hang as "no result" rather than a failure.

**25 of 25 baseline targets match. The count drop from 26 to 25 is `network_test` being
deleted, not a lost or skipped test.**
