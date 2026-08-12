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
