# STREAM

Running work log, newest first. Timestamp · what · why · if-interrupted-here.

---

## 2026-08-13 — Phase 4 Task 2: identity rename built, deployed, and verified end-to-end

**What:** Built (`./bin/build TextMate`, `BUILD SUCCEEDED`) and ran all 25 baseline test targets
individually against `docs/benchmarks/2026-08-12-ninja-parity.md`: **25/25 match exactly** --
22 pass, `scm` fails the same documented `2 of 84` (hg/svn absent locally), `buffer` fails the
same documented `3 of 26` (misspellings, no headless `NSSpellChecker` dictionary), `file` fails
the same documented `1 of 11` (iconv TRANSLIT), `cf` crashes the same documented SIGBUS/exit 138.
`command` and `editor` reproduced the doc's own noted batching artifact (looked hung when run
back-to-back with others) and passed cleanly in seconds re-run individually, exactly as the doc
already recorded.

`bin/deploy-local`'s guard verified doing its job: with the old `com.macromates.TextMate` app
still at `/Applications/TextMate.app`, deploy-local refused with "REFUSING TO REPLACE" (identifier
mismatch). Moved the old app aside -- **not deleted** -- to
`/Applications/TextMate (macromates 3.0.0-revived.10 backup).app`, then re-ran deploy-local, which
installed cleanly. Installed app verified: `CFBundleIdentifier = com.shelbydenike.TextMate`,
`CFBundleName = TextMate`, code signature valid.

**Migration verified against real data, precisely** (Python `plistlib`, comparing the exact
top-level-key set `MigratePreferencesDomain` iterates over -- not `defaults read`'s recursive
line count, which over-counts nested array/dict contents): the real
`~/Library/Preferences/com.macromates.TextMate.plist` has **37 top-level keys** (36 real settings
+ a `MigratedFromMacromates` marker already written there from Task 1's earlier same-domain
no-op run, before this rename). Launched the newly installed app (`open`, not osascript/polling),
and `~/Library/Preferences/com.shelbydenike.TextMate.plist` now has the **identical 37 keys**,
identical values, zero missing, zero extra, zero mismatched. **All 36 real settings carried over,
exactly matching the plan's stated expectation.**

**`mate` verified with hard evidence, not just exit code:** `mate /tmp/.../verify.txt` exited 0
against the already-running app (same PID throughout, no relaunch), and `lsof -p <pid>` confirmed
that exact process held an open file descriptor on that exact file -- proof `mate.mm:59`'s
`URLForApplicationWithBundleIdentifier:@"com.shelbydenike.TextMate"` found and used the real,
running, renamed app.

**Bundles verified three ways, none requiring GUI automation:** (1) source reading --
`AppController.mm:518` calls `loadBundlesIndex` synchronously at launch, which unconditionally
calls `createBundlesIndex:` and populates `bundles::set_index(...)` in memory regardless of
whether the on-disk cache exists yet -- the new `~/Library/Caches/com.shelbydenike.TextMate/`
being empty shortly after launch is expected (the on-disk `BundlesIndex.binary` write is a
separate, debounced/on-quit path via `saveBundlesIndex:`, not a signal of whether bundles loaded);
(2) `~/Library/Application Support/TextMate/Managed/Bundles/` -- the literal-string path, correctly
unaffected by the identifier change -- still has all 54 bundles; (3) `lsof` on the running process
shows an open handle on `~/Library/Application Support/TextMate/Global.tmProperties`, confirming
the app is actively reading from that (unaffected) support directory at runtime. No crashes or
errors for the process in the unified log over the full session.

**Confirmed untouched, as required:** `grep -c "com.macromates" Applications/TextMate/Info.plist`
= **38** (all UTI declarations survive; only the `CFBundleIdentifier` line, no longer matching,
dropped out of the count -- was 39 before this change). `OakDocument.mm`'s xattr names
(`com.macromates.bookmarks`, `.folded`, `.crc32`, `.selectionRange`, `.visibleIndex`,
`.backup.*`) are byte-for-byte unchanged -- never touched.

**Deliberately not done:** did not bump `CHANGELOG.md`/`APP_VERSION` or run a second
build-and-redeploy cycle to re-stamp the version string. The plan's global constraint ("after each
task: build, bump version, update changelog, deploy, verify") would normally call for this, but
`bin/deploy-local`'s replace-in-place path for a *same-identifier* redeploy unconditionally shells
out to `osascript -e 'tell application id ... to quit'` before removing the old copy -- exactly
the class of Apple-Events call this task was explicitly warned hangs on an unacknowledged
Automation permission prompt in this environment, and neither the deployed identifier, the
migration, `mate`, nor bundle loading depend on which version string is baked in. Left for a
deliberate follow-up, ideally the first time with a human present to clear the one-time
Automation permission dialog. `/Applications/TextMate.app` currently reports
`3.0.0-revived.10` with `com.shelbydenike.TextMate` -- correct identifier, stale-but-harmless
version string.

**Why:** This is the load-bearing verification for the whole task -- the plan's own risk table
calls settings-reverting-silently and `mate`-can't-find-the-app the two most user-visible ways
this rename could fail invisibly. Both are now checked against real data on a real machine, not
assumed from reading code.

### If interrupted here

Task 2's core work (identifier rename, cache paths, `mate`/`gtm` lookups, build, 25/25 tests,
deploy, migration, bundles) is done, committed (`eedef5cf`), and verified end-to-end. Two things
remain open, both already flagged, neither blocking the rest of Phase 4: (1) Dialog/Dialog2
(`PlugIns/dialog*`) still say `com.macromates.plugin.*` -- blocked on the git-submodule/upstream
question recorded in the previous entry, needs a human decision (fork + repoint `.gitmodules`, or
vendor the two plugins into the tree); (2) the version-bump-and-redeploy convention was skipped
for the reason above -- safe to do manually whenever a human is present to clear the Automation
prompt once. The old `com.macromates.TextMate` app is preserved at
`/Applications/TextMate (macromates 3.0.0-revived.10 backup).app` (not deleted) until the rename
is trusted. Next: Task 3 (the privileged helper) or Task 4 (attribution/credits), per the plan.


## 2026-08-13 — Phase 4 Task 2: bundle identifiers changed to com.shelbydenike.* (Dialog/Dialog2 blocked on a submodule)

**What:** Changed `CFBundleIdentifier` in `Applications/TextMate/Info.plist:12` and
`Applications/QuickLookGenerator/Info.plist:12` from `com.macromates.${TARGET_NAME}` to
`com.shelbydenike.${TARGET_NAME}`. Updated the dependents that must stay in sync with it: the
`~/Library/Caches/com.macromates.TextMate/` cache directory hardcoded in
`Applications/gtm/src/gtm.cc:104`, `Applications/QuickLookGenerator/src/generate.mm:38`,
`Frameworks/BundlesManager/src/BundlesManager.mm:950,957`, `bin/gen_credits.rb:202`, and
`bin/build:16,30`; the app-bundle lookup in `Applications/mate/src/mate.mm:59`
(`URLForApplicationWithBundleIdentifier:`); and QuickLookGenerator's explicit prefs suite in
`Applications/QuickLookGenerator/src/generate.mm:209` (`initWithSuiteName:`). Left the 38 UTI
declarations and `txmt://` scheme in the same `Info.plist` untouched (only line 12 changed) and
left every internal-chrome identifier alone (dispatch queues, log subsystems, error domain,
pasteboard type, Touch Bar identifiers in both `OakTextView.mm` and
`DocumentWindowController.mm`, Mach port names, `runner.mm`'s fallback-only cache-path string,
the SCM svn driver's `com.macromates.TextMate.scm` lookup -- confirmed inert, since `scm` is
`type: library.static` in `project.yml` and no bundle in this app ever declares that identifier,
so it always falls through to `CFBundleGetMainBundle()` -- and Task 1's
`PreferencesMigration.mm` source domain, which must stay pinned to the old identifier forever by
design).

**Blocked, not done:** `PlugIns/dialog/Info.plist:16` and `PlugIns/dialog-1.x/Info.plist:16`
(Dialog / Dialog2 plug-in identifiers) are **git submodules** pointing at
`https://github.com/textmate/dialog.git` and `https://github.com/textmate/dialog-1.x.git` --
upstream's own repos, never forked under this project; `git log` on both paths shows every past
change here is a pointer-bump to a commit upstream published, never an independent commit.
`project.yml`'s `INFOPLIST_FILE` reads each submodule's plist directly at build time, so there is
no build-setting indirection that can rename the identifier without editing that tracked file.
Committing the edit only inside the local submodule checkout would produce a commit that exists
on this machine alone -- `.gitmodules` still resolves to upstream, so a fresh clone or CI's `git
submodule update` would fail to fetch it. That is a certain, silent break for the next checkout,
not a hypothetical one. A real fix means either forking both repos under project control and
repointing `.gitmodules`, or vendoring them into the tree and dropping the submodule -- a
repo-topology decision the plan does not make and this task should not make unilaterally.
Reverted both edits; both files are back to `com.macromates.plugin.${TARGET_NAME}`, tree clean.
It is a 1-line change in each once someone decides where that commit should live.

**Why:** `Applications/TextMate/Info.plist:12` is the app's real identity; everything else
touched here is code that has to keep agreeing with it. Leaving any of it on the old identifier
while the app itself moved would silently break QuickLook previews, `bin/gen_credits.rb`,
`mate`, or bundle-index caching, each in a different, hard-to-notice way.

### If interrupted here

Committed. Next: `bin/build`, run all 25 baseline test targets against
`docs/benchmarks/2026-08-12-ninja-parity.md`, verify Task 1's migration actually fires against
the real `~/Library/Preferences/com.macromates.TextMate.plist` (back up first), verify `mate`
finds the renamed app, then handle `bin/deploy-local`'s expected identifier-mismatch refusal by
moving the old `/Applications/TextMate.app` aside (never deleting it) before installing the new
one. Do not touch `PlugIns/dialog*` again without first resolving the submodule question above.


## 2026-08-13 — Phase 4 Task 1: preferences migration (pre-rename release)

**What:** Added `Applications/TextMate/src/PreferencesMigration.{h,mm}`:
`MigratePreferencesDomain(source, destination)` copies every key persisted under `source` into
`destination` that `destination` doesn't already have (per-key, never clobbers), then writes a
`MigratedFromMacromates` marker into `destination` so later calls no-op immediately. Source is
only ever read, never deleted. `MigrateLegacyPreferencesIfNeeded()` calls it with
`source = "com.macromates.TextMate"` (hardcoded) and `destination = NSBundle.mainBundle.bundleIdentifier`
(read at runtime, not hardcoded) — so today, before Task 2 changes `CFBundleIdentifier`, source
and destination resolve to the literal same domain and the call is a true, verified no-op; once
Task 2 lands, destination will resolve to `com.shelbydenike.TextMate` and the same code performs
the real migration, with no changes needed to this file. Wired as the very first statement in
`main()` (`Applications/TextMate/src/main.mm`), before `oak::application_t::set_support(...)` —
earlier than the plan's suggested neighbourhood, deliberately, so no code path anywhere (app
init, AppController, RegisterDefaults) can read a default before migration runs.

New `Applications/TextMate/tests/t_preferences_migration.mm`, 5 tests, all against throwaway
`*.PreferencesMigrationTest.*` domains (never the real `com.macromates.TextMate` domain):
copies-into-empty-destination, never-clobbers-but-still-fills-gaps, marker-makes-second-run-a-true-noop,
absent-source-is-clean-noop, and source-equals-destination-is-a-safe-noop (today's actual shipping
state). Build wiring: new `PreferencesMigration` library.static target and `TextMate_test` tool
target in `project.yml` (mirrors the existing `<framework>_test` pattern one level up, since this
is the first test target for something under `Applications/` rather than `Frameworks/`);
`Xcode/scripts/gen_test.sh` gained an `Applications/$name` fallback alongside its existing
`Frameworks/$name` / `vendor/$name` search, needed for `gen_test.sh TextMate` to find
`Applications/TextMate/tests/`. `TextMate.xcodeproj` regenerated via `xcodegen generate`.

**Why:** `NSUserDefaults.standardUserDefaults` is keyed on `CFBundleIdentifier`. Task 2 will change
it from `com.macromates.TextMate` to `com.shelbydenike.TextMate`; without this migration, every
setting a user has would silently revert to defaults the moment that ships. This lands first, in
its own release, so the code has actually run against a real old domain on a real machine before
anything depends on it — verification (backup real plist, run, compare, restore) is next.

### If interrupted here

Code committed and unit-tested (5/5 pass, `./bin/build TextMate/test`). Full `TextMate` app also
builds clean with the new dependency. Not yet done: (1) verify against the real
`~/Library/Preferences/com.macromates.TextMate.plist` (back up first, restore after — do not
leave it modified), (2) re-run all 25 baseline test targets against
`docs/benchmarks/2026-08-12-ninja-parity.md` to confirm no regression. Task 2 (the actual
`CFBundleIdentifier` rename) must not start until both are done and reported.


## 2026-08-13 — Phase 3 merged; Phase 4 planned around a data-loss trap

**What:** PR #5 merged to master (`851bec7c`) with a real merge commit. Phase 4 planned at
`docs/superpowers/plans/2026-08-13-phase-4-identity.md`.

**The recon finding that shapes the whole phase:** `com.macromates.*` in this tree is not one
thing. It is three, with completely different migration semantics:

1. **Identity — change these.** Bundle identifiers (app, QuickLookGenerator, Dialog, Dialog2),
   six hardcoded cache paths under `~/Library/Caches/com.macromates.TextMate/`, app-bundle
   lookups in `mate.mm:59` and `gtm.cc:104`, and the privileged helper's five launchd
   identifiers (`constants.h:4-8`).
2. **Data format — must NOT change.** Extended attributes written onto *the user's own
   documents* (`com.macromates.bookmarks`, `.folded`, `.crc32`, `.selectionRange`,
   `.visibleIndex`, `.backup.*`), the 38 `com.macromates.textmate.*` UTIs that every installed
   bundle's `info.plist` references, and the `txmt://` URL scheme that external tools and links
   across the internet use.
3. **Internal chrome — leave alone.** Dispatch queue and log-subsystem names, error domain,
   pasteboard type, Touch Bar identifiers, Mach port names. Renaming is churn with risk and no
   benefit.

**A naive `sed com.macromates → com.shelbydenike` would silently orphan every bookmark and code
fold on every file the user has ever opened**, and break document-type associations with every
installed bundle. The xattrs and the identifier live in the same tree and look identical to a
grep; only their semantics differ.

**What survives untouched:** `~/Library/Application Support/TextMate` is the literal string
`TextMate`, not derived from the identifier (`main.mm:51`, `AppController.mm:505`,
`tm_query.cc:32`, `generate.mm:30`). Bundles, themes, and gems need no migration — the single
biggest piece of user state is safe.

**What does need migrating:** `NSUserDefaults.standardUserDefaults` is implicitly keyed on the
bundle identifier, so every setting reverts to defaults the moment it changes. Task 1 writes that
migration and ships it in a release BEFORE the rename, so it has actually run against the old
domain on a real machine before it is needed.

**Why:** Phase 4 changes identity to `com.shelbydenike.*` without orphaning user state.

### If interrupted here

Phase 3 merged. `/Applications/TextMate.app` is v3.0.0-revived.9, zero build dependencies.
Branch `phase-4/identity` created off master with the plan committed. Next: Task 1 (preferences
migration — written and released BEFORE the identifier changes, never in the same build).


## 2026-08-13 — Phase 3 Task 4: `CrashReporter` deleted, `crash` kept (Phase 3 complete)

**What:** Investigated both frameworks before touching either. `Frameworks/CrashReporter`
(342 lines, `CrashReporter.mm`/`.h`) is a static library linked into the `TextMate` app target
(`project.yml`), but `CrashReporter.sharedInstance`, `applicationDidFinishLaunching:`, and
`postNewCrashReportsToURLString:` have zero callers anywhere in the tree outside the framework's
own definition — confirmed by repo-wide grep. So it was already fully dead before this task:
never instantiated, never wired to the app delegate. Its only two jobs were (1) scanning
`~/Library/Logs/DiagnosticReports` — which macOS populates on its own regardless of this
framework — and (2) POSTing gzipped reports to a URL string that would have to be supplied by a
caller that doesn't exist; `REST_API`/`api.textmate.org` was removed in PR #9 with nothing put
in its place, so even a wired-up call site would have nowhere to send reports. No signal
handlers anywhere in it either — it's an uploader, not a crash-catching mechanism.

`Frameworks/crash` (62 lines, `info.cc`/`.h`) is different: `crash_reporter_info_t` is a
thread-local RAII breadcrumb stack that publishes a description string into
`__crashreporter_info__`, a symbol macOS's own crash reporter reads via a linker `.desc`
directive — pure annotation, no signal handling, no change to whether/how the app crashes.
**Correction to the plan's recon:** the plan's "measured facts" counted 4 external includers
(all `.cc`); actual count is **12 files, 15 call sites** — the plan's grep only covered `.cc`
files and missed `.mm` consumers: `Applications/TextMate/src/{main,OakMainMenu,
TMPlugInController}.mm`, `Frameworks/OakTextView/src/{OakTextView,GutterView}.mm`,
`Frameworks/OakAppKit/src/{OakAppKit,OakPasteboard}.mm`,
`Frameworks/DocumentWindow/src/DocumentWindowController.mm`, plus the 4 `.cc` files the plan
named (`io/src/exec.cc`, `layout/src/{ct,layout}.cc`, `selection/src/selection.cc`). This
doesn't change the decision — it strengthens it: `crash` is woven through menu key handling,
text-view selectors, drag & drop, document switching, and plug-in loading, not a narrow corner,
so deleting it for zero behavioural gain would be real, unjustified churn across 12 files.
tectiv3's own removal (`025f2ef8`) also left `crash` alone and only deleted `CrashReporter`.

**Decision: delete `CrashReporter`, keep `crash` unchanged.** `git rm -r Frameworks/CrashReporter
Xcode/include/CrashReporter` (4 files: the `.h`/`.mm` pair, the `bin/symbolicate` dsym-lookup
script, and the header-staging symlink). `project.yml`: removed the `CrashReporter` target
block, its `- target: CrashReporter` / `link: true` dependency on the `TextMate` app target, and
the now-dangling `Xcode/include/CrashReporter` entry from that target's `HEADER_SEARCH_PATHS`.
Also removed `kUserDefaultsDisableCrashReportingKey` and `kUserDefaultsCrashReportsContactInfoKey`
from `Frameworks/Preferences/src/Keys.h`/`.mm` (plus their one registration-defaults dictionary
entry) — both existed solely to configure the now-deleted uploader and had no other reader,
confirmed by repo-wide grep before removal; same "delete what the removal orphans" precedent as
Task 3 dropping `libcurl.tbd` once `network` was gone.

`xcodegen generate --spec project.yml` regenerated `TextMate.xcodeproj`
(`grep -c CrashReporter project.pbxproj` → 0). `./bin/build` succeeds;
`CFBundleIdentifier`/`CFBundleName` unchanged (`com.macromates.TextMate`/`TextMate`).

**Verification against `docs/benchmarks/2026-08-12-ninja-parity.md`:** all 25 baseline test
targets rebuilt and rerun individually (`./bin/build <name>/test`) match the recorded result
exactly — 19 of 20 CI-included pass, `scm` fails identically (`2 of 84`, `hg`/`svn` absent); the
six CI-excluded targets reproduce the same pattern (`buffer` 3/26 misspellings, `cf` SIGBUS/exit
138, `layout`/`command`/`editor` pass, `file` 1/11 iconv TRANSLIT). `command_test` briefly showed
`exit=124` when run inside one 25-target batched loop — the exact same batching artifact
Task 3's baseline already documented for `command`/`editor`; re-run individually it passed in
under a second, no hang. Target count stays 25 — `CrashReporter` never had a test target.
Final repo-wide grep (`grep -rn "crash/\|CrashReporter" --include='*.cc' --include='*.h'
--include='*.mm' . | grep -v vendor/`) shows only the 12 legitimate `crash/info.h` includes plus
one self-referential comment in `Frameworks/crash/src/info.cc:4` — zero `CrashReporter` matches.

**Why:** Phase 3 dependency purge, and the last task of the phase. `CrashReporter` was dead
weight pointed at a dead endpoint — deleting it shrinks the tree with zero behavioural change
(nothing called it, so nothing now doesn't call it). `crash` earns its keep: it's cheap (62
lines, no external deps), installs no signal handler, and is genuinely used across the app to
annotate the crash reports macOS writes anyway.

### If interrupted here

Phase 3 (dependency purge) is functionally complete after this task — all four tasks done:
boost/sparsehash removed (v3.0.0-revived.6), ragel removed (v3.0.0-revived.7), `network` deleted
(v3.0.0-revived.8), `CrashReporter` deleted (this task, pending version bump to
v3.0.0-revived.9). At time of writing, the code commit for this task is about to land
(`build!:` prefix — deletes a linked framework), followed by a `release:` commit bumping
`CHANGELOG.md`, then `bin/deploy-local`. Branch `phase-3/dependency-purge`, unpushed, no PR.
Next: Phase 3 exit criteria review (all four checked in the plan's own terms: zero Homebrew
deps, `/opt/homebrew/include` gone from `HEADER_SEARCH_PATHS`, no stray `.rl`/`boost`/
`sparsehash` outside `vendor/`, updater untouched, 25/25 test parity, a versioned/changelogged/
deployed release) before starting Phase 4.

## 2026-08-13 — Phase 3 Task 3: `network` deleted (not migrated), libcurl dropped

**What:** The plan's premise ("replace `network` with `URLSession`") was wrong — recon proved
the migration already happened in the textmatelives merge. `Frameworks/SoftwareUpdate/src/`
already calls `NSURLSession` directly (`SoftwareUpdate.mm:373`, `OakDownloadManager.mm:78,336`)
and `Security.framework` for signature verification; `network`'s only consumer was its own
test (`Frameworks/network/tests/t_download.cc`, hits a live HTTP endpoint). Verified
independently before touching anything: repo-wide `grep` for `#include`/`#import` of any
`network/*.h` (`.cc`/`.h`/`.mm`/`.cpp`/`.m`, excluding `vendor/`) found zero hits outside
`Frameworks/network/` itself. So this was a deletion, not a migration.

`git rm -r Frameworks/network` (20 files: 9 `.cc`, 10 `.h`, 1 test). Also
`git rm -r Xcode/include/network` (10 files) — the per-header symlinks staging `network`'s
public headers for Xcode's header search paths, same convention every other framework under
`Xcode/include/` uses (confirmed by comparing to `OakFoundation`'s identical structure);
leaving them would have left dangling symlinks pointing at deleted files, not a partial
deletion worth keeping.

`project.yml`: removed the `network` and `network_test` target blocks, and removed
`network`'s `- target: network` / `link: true` from the `TextMate` app target's dependencies
(the "declares network as a dependency of SoftwareUpdate" in the task brief turned out to
mean the `TextMate` app target itself, which links `SoftwareUpdate` — `project.yml`'s actual
`SoftwareUpdate`/`SoftwareUpdate_test` target blocks never referenced `network` at all).
Also dropped both `sdk: libcurl.tbd` lines (`network_test`'s own, and `TextMate`'s): repo-wide
`grep` for `curl_easy_*`/`CURL*`/`libcurl` outside `vendor/` found hits only in
`network/src/download.cc` and `download_tbz.cc` — nothing else in the tree calls libcurl.
This build now links zero libcurl. (This was the system SDK's `libcurl.tbd`, not a Homebrew
package — `./configure` never checked for `curl` — so it isn't a Homebrew-dependency-count
change like Task 1/2, just one fewer linked library.)

`xcodegen generate --spec project.yml` regenerated `TextMate.xcodeproj`
(`grep -c network TextMate.xcodeproj/project.pbxproj` → 0). `./bin/build TextMate` succeeds,
output still under `~/build/textmate-revived/xcode`.

**Verification against `docs/benchmarks/2026-08-12-ninja-parity.md`:** all 25 remaining
baseline targets (26 minus `network_test`) rebuilt and rerun individually
(`./bin/build <name>/test`) match the recorded result exactly — 19/20 CI-included pass, `scm`
fails identically (`2 of 84`, `hg`/`svn` absent); the six CI-excluded targets reproduce the
same pattern (`buffer` 3/26 misspellings, `cf` SIGBUS/exit 138, `layout`/`command`/`editor`
pass, `file` 1/11 iconv TRANSLIT). `SoftwareUpdate_test` passes; `Frameworks/SoftwareUpdate`
was not touched. Parity doc updated with a dated section explaining the 26→25 count change so
it reads as an accounted-for deletion, not a lost test.

**Why:** Phase 3 dependency purge. Recon disproved the plan's migration premise before any
code was written, so the correct action was deletion, matching the fork's stated goal (keep
the updater, unlike tectiv3, who deleted `network` and the updater together) while still
removing dead code and its libcurl link.

### If interrupted here

Task 3 complete, uncommitted at time of writing this entry — commit lands in the same commit
as this entry (`build!:` prefix, breaking: deletes a framework). Branch
`phase-3/dependency-purge`, unpushed, no PR. Next: Task 4 (`crash`/`CrashReporter` — keep,
delete, or replace; no crash-reporting endpoint exists since `api.textmate.org` is gone, so an
enabled reporter posting nowhere is dead weight, but the local assertion helpers may still be
useful).

## 2026-08-13 — Phase 3 Task 2 complete: ragel removed

**What:** Commit `848dd1a8` (parser port + verification, see entry below). This wrap-up:
trimmed `ragel` from all three CI `brew install` lines (`build-and-test.yml` ×2, kept
`mercurial subversion` for `scm`'s tests; `release.yml`'s step installed only `ragel`, so
that step was deleted outright rather than left installing nothing). Updated `CLAUDE.md` and
`README.md` — neither lists `ragel` as a dependency anymore. `git ls-files '*.rl'` returns
nothing. Rebuilt (`./bin/build TextMate`, picks up `CHANGELOG.md`'s new top entry
automatically via `assemble_resources.sh`'s `app_version()`), deployed with
`bin/deploy-local` (replaced 3.0.0-revived.6 in `/Applications`), confirmed
`CFBundleIdentifier`/`CFBundleName` unchanged. Released v3.0.0-revived.7.

**Why:** Phase 3 targets zero Homebrew dependencies to build. Three of four are now gone
(boost, sparsehash, ragel).

### If interrupted here

`/Applications/TextMate.app` is v3.0.0-revived.7. Branch `phase-3/dependency-purge`,
unpushed, no PR. Next: Task 3 replaces `Frameworks/network` with `URLSession` — enumerate
what `SoftwareUpdate` actually uses (download, tbz extraction, signature verification,
keychain), implement on `URLSession`, port `network`'s tests before deleting the framework.
**Keep the updater** — tectiv3 deleted `network` and the updater together; this fork keeps
the updater (textmatelives' GitHub-Releases updater, a stated project goal for Phase 5). Then
Task 4 (`crash`/`CrashReporter` — keep, delete, or replace; note there's no crash-reporting
endpoint since `api.textmate.org` is gone, so an enabled reporter posting nowhere is dead
weight, but the local assertion helpers may still be useful).

## 2026-08-13 — Phase 3 Task 2: ragel removed, ASCII plist parser hand-written

**What:** `Frameworks/plist/src/ascii.rl` (191 lines) → `ascii.cc`. Chose option (b), porting
tectiv3's hand-written parser (`34e166b9`), not (a) committing generated output. Reasoning: the
actual ragel usage was two small sub-machines — a string tokenizer and a comment/whitespace
skipper — not a large grammar; the array/dict/int/bool/date logic around them was already
hand-written C++, untouched by ragel. A hand-written replacement stays reviewable; a committed
`.cc` from `ragel -o` is an opaque state table forever. Ported by hand rather than copying
tectiv3's file wholesale: their `ascii.cc` predates this fork's Task 1 (`boost::get` →
`plist::get`/`plist::convert`), so a literal copy would have reintroduced `boost::get` in
`parse_key`. Only `parse_ws` and `parse_string` changed; everything else in the file is
untouched.

`project.yml`'s `plist` target loses the `preBuildScripts` ragel phase and the
`$(DERIVED_FILE_DIR)/_Rplist_ascii.cc` optional source, gaining a plain `ascii.cc` entry.
`Xcode/scripts/gen_ragel.sh` deleted (only caller was that phase). `TextMate.xcodeproj`
regenerated via `xcodegen generate --spec project.yml`.

**Verification, in order of rigor:**
1. Generated the *actual* ragel output from the current `ascii.rl` (ragel still installed,
   pre-removal) and diffed a standalone extraction of its `parse_ws`/`parse_string` state
   machine against the hand-written port across 19 cases: quoting, `\\`/`\"` escapes, escapes
   TextMate relies on staying literal (`\d`, `\s\t` — regex fragments in grammars/themes must
   not be unescaped), unterminated strings/comments, bare words, comments. One real divergence
   found and fixed before porting: an unterminated `/* comment` at EOF left one trailing byte
   unconsumed in tectiv3's version; ragel consumes to EOF. Fixed with `p = pe` in the fallback
   branch; re-verified byte-for-byte identical on every case afterward.
2. `plist/test` (33 tests, the exact count `docs/benchmarks/2026-08-12-ninja-parity.md` and
   Task 1 both record) passes unchanged — this suite already covers exactly the escape/comment
   edge cases from step 1.
3. Real-world round-trip: built a standalone driver linking the actual `libplist.a`/`libtext.a`/
   etc., loading real XML bundle files via the unmodified `plist::load`, serializing to
   TextMate's ASCII plist text via the unmodified `to_s()`, then parsing that text back via
   `parse_ascii` and re-serializing. Ran across 10 real files — 3 themes (Twilight, macOS
   System Theme, Undead), 5 bundles' `info.plist`, the `Plain text.plist` grammar, and a
   `.tmPreferences` file with regex scope selectors — against both a build linking the new
   hand-written `parse_ascii` and one linking the actual ragel-generated object file recompiled
   from git HEAD's `ascii.rl`. Every file's re-parsed output was byte-identical between old and
   new parser.
4. All 26 test targets run individually and compared against
   `docs/benchmarks/2026-08-12-ninja-parity.md`: 21 pass with exact test counts matching Task
   1's own more recent tally (authorization 1, bundles 5, BundlesManager 10, document 9,
   encoding 6, FileBrowser 1, HTMLOutput 1, io 24, network 1, ns 6, parse 4, plist 33, regexp
   41, scope 13, selection 24, settings 9, SoftwareUpdate 20, text 34, theme 1, layout 9,
   command 4, editor 9); `scm` fails 2/84 (hg/svn not on this machine, documented), `buffer`
   fails 3/26 (headless `NSSpellChecker`, documented), `cf` crashes SIGBUS/exit 138
   (documented), `file` fails 1/11 (iconv TRANSLIT, documented). **26/26 match, zero deltas.**
   `./bin/build TextMate` succeeds; `CFBundleIdentifier`/`CFBundleName` unchanged.

**Why:** Phase 3 targets zero Homebrew dependencies to build. Three of four are now gone
(boost, sparsehash, ragel); only `multimarkdown`'s removal was already done pre-Phase-3.

### If interrupted here

Core parser change committed. Still pending for Task 2: `git ls-files '*.rl'` confirmed empty;
CI's three `brew install` lines still need `ragel` trimmed (`build-and-test.yml` ×2,
`release.yml` ×1 — the latter installed only ragel, so that whole step should be deleted, not
edited to install nothing); CLAUDE.md/README.md still describe ragel as a dependency; version
needs bumping to v3.0.0-revived.7 in `CHANGELOG.md`; then rebuild, `bin/deploy-local`, verify,
final `release:` commit. After that: Task 3 (replace `network` with `URLSession`, KEEPING the
updater) and Task 4 (`crash`/`CrashReporter`).

## 2026-08-13 — Phase 3 Task 1: boost and sparsehash removed

**What:** `boost::variant` → `std::variant` (153 call sites), `boost::crc_32_type` → zlib
`crc32()`, `dense_hash_map` → `std::unordered_map` (1 site). `/opt/homebrew/include` dropped from
`HEADER_SEARCH_PATHS`. CI's `brew install` trimmed to `ragel mercurial subversion` — boost,
google-sparsehash, and multimarkdown all removed (multimarkdown was already unused).
Commits `3bf1efe8`, `e767e4e0`, `2cf30c91`, `3c74199f`. Released v3.0.0-revived.6.

**The CRC equivalence proof mattered more than expected.** `boost::crc_32_type` and zlib's
`crc32()` both claim "CRC-32", but CRC variants differ in polynomial, initial value, reflection,
and final XOR — a mismatch would not surface as a compile error or necessarily as a test failure.
Verified byte-for-byte over empty/ASCII/single-byte/all-256-values/high-bytes-only/8KB-random
inputs, plus the published check vector `"123456789"` → `0xCBF43926`, which confirms both compute
the *standard* variant rather than merely agreeing with each other.

It is used for `com.macromates.crc32`, a **persisted xattr** gating code-fold-state restore on
reopen. A silently different checksum would have discarded fold state on every existing file, with
nothing failing to report it.

**Two incidental finds:** `any_t` becoming a real `plist` type rather than a boost alias made an
unqualified `equal()` in `delta.cc` ADL-ambiguous against the now-visible `plist::equal` — fixed by
qualifying. And `ascii.rl` (ragel source) used `boost::get`, missed by a `.cc/.h/.mm` grep and
caught by the build.

All 26 test targets match `docs/benchmarks/2026-08-12-ninja-parity.md` with zero deltas.

**Why:** Phase 3 targets zero Homebrew dependencies to build. Two of four are gone.

### If interrupted here

`/Applications/TextMate.app` is v3.0.0-revived.6. Branch `phase-3/dependency-purge`, unpushed, no
PR. Next: Task 2 removes `ragel` — one file (`Frameworks/plist/src/ascii.rl`, 191 lines), decide
between committing the generated output or porting tectiv3's hand-written parser (`34e166b9`).
Then Task 3 (replace `network` with URLSession, KEEPING the updater) and Task 4 (crash/CrashReporter).


## 2026-08-13 — Phase 3 Task 1 (4/4) complete: /opt/homebrew/include dropped, full verification

**What:** `Xcode/Base.xcconfig`'s `HEADER_SEARCH_PATHS` loses `/opt/homebrew/include` — the last
line item existed only to serve `boost` and `sparsehash`, both fully gone as of the previous
three commits. Re-verified with the path actually removed, not just reasoned about: full
`./bin/build TextMate` (0 errors, `BUILD SUCCEEDED`) plus all 26 test targets run individually
and compared against `docs/benchmarks/2026-08-12-ninja-parity.md`'s Xcode column —

19 of 20 CI-included targets pass (authorization 1, bundles 5, BundlesManager 10, document 9,
encoding 6, FileBrowser 1, HTMLOutput 1, io 24, network 1, ns 6, parse 4, plist 33, regexp 41,
scope 13, selection 24, settings 9, SoftwareUpdate 20, text 34, theme 1 — all exact test-count
matches); `scm` fails 2/84 for the same documented `hg`/`svn`-not-on-this-machine reason. Of the
6 CI-excluded targets: `buffer` fails 3/26 (misspellings, headless `NSSpellChecker`), `file` fails
1/11 (iconv TRANSLIT), `cf` crashes SIGBUS/exit 138 — all three identical to the baseline; layout
(9), command (4), editor (9) pass, matching this machine's own more-permissive local results the
baseline already recorded. **26/26 match, zero deltas.**

`grep -rn "boost/\|sparsehash\|dense_hash_map" --include='*.cc' --include='*.h' --include='*.mm' .
| grep -v vendor/` returns nothing. App bundle: `CFBundleIdentifier` still `com.macromates.TextMate`,
`CFBundleName` still `TextMate` (untouched, per constraint), ad-hoc codesign verifies clean,
Mach-O arm64 only, `otool -L` shows `/usr/lib/libz.1.dylib` correctly linked.

**Why:** Phase 3 Task 1 exit criteria.

### If interrupted here

Task 1 is done and verified end to end, committed as 4 commits on `phase-3/dependency-purge`
(variant → crc → dense_hash_map+prelude → header path). Not touched, deliberately out of Task 1's
scope: `.github/workflows/*.yml`'s `brew install boost google-sparsehash ...` lines (still
harmless no-ops; Task 2 removes `ragel`/`multimarkdown` from the same lines, so one consolidated
CI cleanup after Task 2 makes more sense than two partial edits) and `Applications/TextMate/about/
Legal.md`'s boost attribution (a packaging/distribution concern, not a build one). Next: Task 2
(remove ragel) per the same plan document — decide between committing generated `ascii.cc` vs.
porting tectiv3's hand-written parser (`34e166b9`), per the plan's own two-option framing.

## 2026-08-13 — Phase 3 Task 1 (3/4): dense_hash_map → unordered_map; prelude.cc finished

**What:** `theme_t`'s per-scope style cache (`Frameworks/theme/src/theme.h`) was the only
`google::dense_hash_map` in the tree — `std::unordered_map<scope::scope_t, styles_t>` replaces
it, and the `_cache.set_empty_key(scope::scope_t{})` call in `theme.cc`'s constructor is deleted
outright (`unordered_map` has no empty-key concept; nothing else used it). `scope::scope_t`
already had a `std::hash` specialization (`Frameworks/scope/src/scope.h:116`), so no new hasher
was needed. Checked iteration-order dependence per the task's instruction: `_cache` is only ever
touched via `find()`/`insert()` (confirmed by grep) — never iterated — so it's a pure
key→value memoization cache and the swap changes nothing observable.

`Shared/PCH/prelude.cc` now drops all three original includes (`boost/crc.hpp`,
`boost/variant.hpp`, `sparsehash/dense_hash_map`) and adds `<unordered_map>` — safe here and not
earlier, since by this commit nothing in the tree references any of the three anymore (variant:
commit 1; crc: commit 2; dense_hash_map: this commit) and this commit's own `theme.h` change is
the first thing that actually needs `<unordered_map>`.

**Why:** Phase 3 Task 1.

### If interrupted here

`Xcode/Base.xcconfig` still has `/opt/homebrew/include` on `HEADER_SEARCH_PATHS` — one more
commit removes it, once the full-tree build + all 26 test targets are re-verified against it
gone. Next: full `./bin/build`, then each of the 26 test targets individually
(`./bin/build <name>/test`), compared against `docs/benchmarks/2026-08-12-ninja-parity.md`.

## 2026-08-13 — Phase 3 Task 1 (2/4): boost::crc_32_type → zlib crc32()

**What:** The two call sites (`io::bytes_t::crc32()` in `Frameworks/file/src/bytes.cc`, and four
inline uses in `Frameworks/document/src/OakDocument.mm` — folded-region xattr, in-flight search
double-check, and a disk re-read checksum) now call zlib's `crc32()` directly
(`#include <zlib.h>`, no prelude change — only these two files need it). Streaming accumulation
(`boost::crc_32_type::process_bytes()` called repeatedly, `.checksum()` read once at the end)
becomes `crc = ::crc32(crc, bytes, len)` chained across calls, seeded via `::crc32(0, nullptr, 0)`
— the documented zlib idiom, and algebraically just 0. `Xcode/Base.xcconfig`'s `OTHER_LDFLAGS`
gains `-lz`, applied to every target (mirroring the existing `-fobjc-link-runtime` precedent and
its own comment's reasoning: harmless/inert on `library.static` targets, cheaper than hunting down
every final target whose dependency closure reaches these two translation units).

**Byte-for-byte equivalence proof (required before deleting the boost code, done — verifiable at
`/tmp/crc_probe/probe.cc`, not part of the repo):** a standalone program linking both
`boost::crc_32_type` and zlib's `crc32()` against the same inputs — empty string, ASCII text, a
single byte, all 256 possible byte values, the 0x80-0xFF high-byte-only range, an 8KB
pseudo-random buffer, and the published CRC-32 check vector `"123456789"` → `0xCBF43926`.
**All seven matched exactly**, including the standard check vector, confirming both compute the
same well-known CRC-32 variant rather than merely agreeing with each other by chance.

**What the CRC is actually used for (checked, not assumed):** two real uses. (1)
`com.macromates.crc32` is written as a **persisted extended attribute** alongside
`com.macromates.folded` on saved files, and read back on next open to decide whether saved fold
state still applies to the file's current content (`OakDocument.mm` around line 848) — this is
exactly the "persisted and keyed on checksum" risk the task called out, since a file saved by an
older (boost-based) build could be reopened by this one. The equivalence proof directly
de-risks it: a boost-computed xattr and a zlib-computed fresh checksum agree, so fold-state
restoration keeps working across the migration. (2) `OakDocumentMatch.checksum` /
`performReplacements:checksum:` is an in-memory-only same-run guard (computed during a search,
consumed moments later during "Replace All", never serialized) — no cross-version risk regardless
of which algorithm computes it, since both sides of that comparison always run under the same
build.

**Why:** Phase 3 Task 1.

### If interrupted here

`file` and `document` frameworks not yet individually rebuilt in isolation after this commit
(will be, along with everything else, in the full-tree verification once `dense_hash_map` and
the prelude/header-path cleanup land too — next two commits). `google::dense_hash_map` (1 file)
still untouched; `Shared/PCH/prelude.cc` still includes `boost/crc.hpp` (now unused) on purpose —
cleaned up in the dense_hash_map commit, once nothing needs any of the three original includes.

## 2026-08-13 — Phase 3 Task 1 (1/4): boost::variant → std::variant

**What:** `plist::any_t` and `parser::node_t` (regexp) were `typedef`s for
`boost::make_recursive_variant<...>::type` / `boost::variant<RW(t)...>`. Replaced both with a
hand-rolled struct wrapping `std::variant`, matching tectiv3's `2c49eead` design: `any_t`/`node_t`
hold a `.data` member, plus drop-in `plist::get<T>(any_t&/const&/*/const*)` overloads standing in
for `boost::get`. `boost::apply_visitor(v, x)` → `std::visit(v, x.data)` everywhere;
`boost::static_visitor<R>` base classes dropped (unneeded with `std::visit`). ~100 call sites
across plist/regexp and ~20 consumer frameworks (BundleEditor, BundlesManager, OakFilterList,
OakTextView, ns, layout, parse, selection, command, editor, bundles, buffer, theme, document,
plist tests) updated by the same mechanical rule.

**Also found and fixed:** `Frameworks/plist/src/ascii.rl` (ragel source, not caught by an
initial `--include='*.cc,*.h,*.mm'` grep since it's `.rl`) had 5 more `boost::get` uses — this is
why the first build attempt failed with "use of undeclared identifier 'boost'" pointing at the
*generated* `_Rplist_ascii.cc`, not a hand-written file.

**A second, non-mechanical fix:** `plist.h` already declared a *different*, pre-existing
`template <typename T> T get(any_t const&)` — a value-converting getter (numeric/string
coercion via `convert_to_helper_t`), semantically unrelated to `boost::get`'s discriminating
accessor. Both can't be named `get` with the same parameter type. Renamed the converting one to
`plist::convert<T>` (matching tectiv3) and updated its ~19 call sites (schema.h, grammar.cc,
theme.cc, OakTheme.mm, t_simple.cc) — a blanket rename, not a selective one, since `convert<T>`
is provably behaviour-identical to the old `get<T>` in 100% of cases (same underlying code, just
renamed) whereas selectively keeping some as the new discriminating `get` would require proving
per-call-site that the parsed type always matches exactly.

**A third, ADL-driven fix in `delta.cc`:** once `any_t` became a real type in `namespace plist`
(previously it was only a `boost::variant` alias, so ADL only ever found `namespace boost`, which
is why `to_s` lived there under a "we place this in the boost namespace to support ADL" comment —
moved to `namespace plist` now that it's unnecessary), an unqualified call to a file-local
`static bool equal(any_t const&, any_t const&)` became genuinely ambiguous against the
newly-ADL-visible `plist::equal` of the identical signature (reproduced and confirmed with a
throwaway repro before touching the real file, since this class of bug doesn't show up as a
type error — it's an overload-resolution ambiguity). Fixed by qualifying that one call as
`plist::equal(...)`; verified both implementations perform the same deep structural comparison
so this is a disambiguation, not a behaviour change.

**Why:** Phase 3 Task 1 — zero Homebrew (`boost`) dependency to build.

### If interrupted here

`plist`, `regexp`, and `theme` frameworks' tests individually rebuilt and pass (33/41/1 tests,
matching the parity doc) as an early sanity check before the full-tree sweep. `boost::crc_32_type`
(2 files) and `google::dense_hash_map` (1 file) are NOT yet touched — `Shared/PCH/prelude.cc`
still includes all three original headers on purpose, so this commit alone doesn't yet compile
`file/src/bytes.cc` or `document/OakDocument.mm` or `theme/*` in isolation; the next commits
finish those and the full-tree build/test verification happens once all four land. Do not remove
`/opt/homebrew/include` from `Xcode/Base.xcconfig` yet — `boost/crc.hpp` and
`sparsehash/dense_hash_map` are still `#include`d there.

## 2026-08-13 — Phase 2 merged; Phase 3 planned (much smaller than scoped)

**What:** PR #4 merged to master with a REAL merge commit (`8f47182d`), not a squash — 39 commits
of history preserved, applying the lesson from Phase 1's squash that destroyed the textmatelives
merge base. Phase 3 planned at
`docs/superpowers/plans/2026-08-13-phase-3-dependency-purge.md`.

**Recon shrank Phase 3 considerably.** The spec assumed a broad dependency purge; measurement says
otherwise:

- `boost` is **2 lines** (`Shared/PCH/prelude.cc:2-3`), `sparsehash` is **1 line** (`:4`)
- `ragel` is **1 file** (`Frameworks/plist/src/ascii.rl`, 191 lines)
- `multimarkdown` has **zero references — already gone**
- `Frameworks/network` (1236 lines) has **zero includes from outside itself**; only
  `SoftwareUpdate` and `network_test` depend on the target
- `crash`/`CrashReporter` is 404 lines with 4 external includers

Only `/opt/homebrew/include` remains on `HEADER_SEARCH_PATHS`, serving boost and sparsehash.
Removing those two lines removes the header path with them.

**Harvest, don't re-derive.** tectiv3 (PR #1467) solved four of these in an 8-hour window AFTER
their CMake migration landed, so the removals are not tangled with CMake and are mechanical:
boost → `std::variant` + zlib `crc32()` (`2c49eead`), sparsehash → `std::unordered_map`
(`36acd469`), ragel → hand-written parser (`34e166b9`), multimarkdown → pre-generated HTML
(`4aa342a9`). Their tree is upstream-based and ours is textmatelives-based with 231 commits of
divergence, so cherry-picks may not apply — use the approach, port by hand where it conflicts.

**One place we must NOT follow tectiv3.** They deleted `Frameworks/network` and the software
updater *together* (`a85e40af`). We keep the updater — textmatelives' GitHub-Releases updater is
what Phase 5 builds on and is a stated project goal. For us `network` is a replacement job on
URLSession, not a deletion. Following them blindly would silently remove in-app updates.

**Why:** Phase 3's goal is zero Homebrew dependencies to build.

### If interrupted here

Phase 2 complete and merged. `/Applications/TextMate.app` is v3.0.0-revived.5, built by Xcode,
arm64. Branch `phase-3/dependency-purge` created off master with the plan committed. Next:
Task 1 (remove boost and sparsehash — 3 lines of includes, but scattered uses; the zlib CRC
replacement needs a byte-for-byte equivalence probe before the old code is deleted).


## 2026-08-13 — Task 8 verification: fixed a real regression from the previous commit's --no-parallel fix

**What:** Running all 26 test targets end to end (the actual parity-document
verification, not just spot checks) turned up a genuine regression from the
"force --no-parallel for every runner" fix two commits ago: `settings_test`
went from PASS (9 tests, matching the parity doc) to **1 of 9 failing**
under forced serial execution, consistently reproducible. Root cause:
`Frameworks/settings/tests/t_track_paths.cc`'s `test_track_file` depends on
real wall-clock time passing between filesystem operations
(`usleep(100000)` between writes and its change-tracker assertions) --
under serial execution with nothing else contending for the CPU, that
still wasn't enough elapsed time; under parallel (default), it reliably
was. Confirmed directly: bare invocation (parallel, default) → silent
pass; `--no-parallel` → same 1/9 failure every time, 3 runs. `settings` is
a `.cc`-only framework -- ninja never forced `--no-parallel` for it either,
only for the seven frameworks with `.mm` test sources (`gen_test.sh`'s own
comment names them: buffer, document, BundlesManager, FileBrowser, ns,
encoding, SoftwareUpdate). "Forcing it universally is always safe" was
wrong -- reverted to matching ninja exactly: `bin/build` and
`build-and-test.yml` now pass `--no-parallel` only for those seven,
everything else runs bare. Re-ran all 26 targets after the fix: **26/26
now match `docs/benchmarks/2026-08-12-ninja-parity.md`'s Xcode section
exactly** -- 19 PASS + `scm` FAIL (hg/svn) among the 20 CI-included, and
buffer FAIL/cf CRASH/layout+command+editor PASS/file FAIL among the six
CI-excluded, byte-identical failure messages where applicable (spot-checked
scm, buffer, cf, file logs against the parity doc's exact text).

Also ran a genuine clean-state verification, not just a same-checkout
rebuild: `git clone --recursive` this branch into `/tmp`, moved
`~/build/textmate-revived/xcode` aside so the shared, xcconfig-pinned
output directory couldn't mask staleness, and built from there --
`BUILD SUCCEEDED`, `lipo -archs` reports `arm64` only, `codesign --verify
--deep --strict` passes. The 22 `grep`-matched "error:"/"FAILED" hits in
that build's full log are all pre-existing `-Wdeprecated-declarations`
warnings whose message text happens to contain an Objective-C selector
fragment like `...error:` -- not real failures.

**Why:** A parity claim is only real once actually measured against all 26
targets, not assumed from 25 matching and one "probably fine." The two
prior commits' `--no-parallel` reasoning was plausible but untested against
the specific test it was about to break; running it surfaced that
immediately.

### If interrupted here

All of Task 8's required work and this verification fix are committed.
Remaining before reporting done: confirm `git ls-files '*.rave'` is empty
and `configure`/`bin/rave` are gone (already true, just needs a final
one-line check), confirm the Intel grep is still clean, and write the
final summary. Nothing pushed.

## 2026-08-13 — Task 8 verification: fixed a clean-clone build failure (pre-existing, Task 6/7)

**What:** Verifying item 1 of Task 8's own bar ("`xcodebuild` succeeds from a
clean clone state") turned up a real gap: `Xcode/generated/TextMate.entitlements`
(XcodeGen's output from `project.yml`'s `entitlements: properties:` block) was
`.gitignore`d, never committed, but the committed `TextMate.xcodeproj`'s
`TextMate` target points `CODE_SIGN_ENTITLEMENTS` straight at that path.
Reproduced directly: moved the directory aside, rebuilt — `BUILD FAILED`,
`ProcessProductPackaging ... TextMate.app.xcent` missing input file. Every
doc (this fork's own and this session's rewrites) says XcodeGen is optional
for a plain build, so a genuinely fresh clone that never runs `xcodegen
generate` could not build at all. Predates Task 8 (Task 6/7 committed the
`.xcodeproj` but not this file) but blocks Task 8's own verification bar, so
fixed here rather than escalated: un-ignored `Xcode/generated/` and committed
`TextMate.entitlements` (content is fully deterministic — 4 static booleans
from `project.yml`, reconfirmed by running `xcodegen generate` fresh and
diffing). Regenerating also reshuffled unrelated `Embed Dependencies` build
phase orderings inside `project.pbxproj` (XcodeGen's own non-determinism,
nothing to do with this fix) — reverted that file to the committed version
via `git checkout --` before staging, so only the entitlements file and the
`.gitignore` line changed. Rebuilt clean afterward: `BUILD SUCCEEDED`.

**Why:** A verification step is only real if it's actually run; running it
found a genuine defect blocking the exact claim Task 8 must confirm.
Two-focused-attempt rule from the builder brief didn't even need invoking —
root cause was clear from the first failing build log.

## 2026-08-13 — Task 8: rave/ninja build deleted; Xcode is the only build

**What:** The irreversible step. Deleted: `configure`, `bin/rave`, all 60
`.rave` files, and three now-unreferenced rave-only helpers found by
grepping the whole tree for real (non-comment) invocations —
`bin/rave2yaml` (its only consumers were comments and its own test;
nothing left to convert once `.rave` sources are gone), `bin/gen_build`
(its only reference to itself was itself; its one job was calling the
now-deleted `./configure`), and `tests/rave2yaml_test.sh` (tested
`bin/rave2yaml` against `.rave` files, both gone). Confirmed
`bin/gen_test`, `bin/gen_html`, `bin/gen_credits.rb`, `bin/build_app_icon.sh`
are genuinely invoked by `Xcode/scripts/*.sh` (grepped each) — untouched.
Also removed the stray untracked `local.rave` and `build.ninja` files this
machine had on disk (dead weight, nothing reads them anymore) and dropped
`.gitignore`'s `build.ninja`/`.ninja_deps`/`.ninja_log`/`local.rave` entries.

`bin/build` rewritten around `xcodebuild`: no args builds the `TextMate`
scheme; `<target>` builds any other Xcode target; `<framework>/test` builds
`<framework>_test` and runs the binary directly (`BUILT_PRODUCTS_DIR`
resolved via `-showBuildSettings`, same pattern Task 7's parity measurement
proved), passing `--no-parallel` for every runner (not just `.mm` ones —
ninja's `RunTest` rule forced it only for `.mm` runners whose Cocoa calls
assert `NSThread.isMainThread`, e.g. `TMFileReference`; forcing it
universally is always safe and avoids re-deriving `gen_test.sh`'s own
`.cc`/`.mm` classification a third place). Both environment guards
(leaked `GEM_HOME`/`GEM_PATH`, root-owned `githubcredits.db`) kept verbatim
— Xcode's script phases still shell out to system Ruby. Tested directly:
default build, `mate` (plain target), `scope/test` (pass) and `scm/test`
(genuine local fail, `hg`/`svn` absent, exit 1 propagated correctly) all
behave as expected.

`README.md`: Building section rewritten for `xcodebuild`/Xcode, the
"transition" notice removed, MacPorts instructions dropped (`Xcode/Base.xcconfig`
hardcodes `/opt/homebrew/include` — MacPorts was never wired into the Xcode
build, so continuing to advertise it would be newly false, not preserved
truth), dead `[ninja]`/`[NinjaBundle]`/`[MacPorts]` footnote links removed.
`CONTRIBUTING.md` checked and needs no change — it never described the
build system. `CLAUDE.md`'s Build system and Tests sections rewritten for
Xcode only; every remaining "ninja"/"rave" mention left in it is now
explicitly past-tense ("no longer works", "was deleted"), not an
instruction. `project.yml`'s stale `# generated by bin/rave2yaml ... do not
hand-edit` header corrected to say it's hand-maintained now that the
generator is gone.

Two files beyond the required list, found via a repo-wide `ninja` grep and
fixed because they are genuinely live (not historical) build/dev docs:
`.tm_properties` (removed `TM_NINJA_FILE`/`TM_NINJA_TARGET` — the optional
Ninja bundle integration they configured has no replacement, so self-hosted
⌘B-inside-TextMate building is gone, documented as such in README rather
than papered over) and `docs/RELEASING.md` (steps/line-citations updated
for the new `release.yml`; the old claim that `Applications/TextMate/default.rave`
stamps `CFBundleShortVersionString` from `CHANGELOG.md` was removed rather
than guessed at a replacement — grepping `project.yml` and the built
`project.pbxproj` for `APP_VERSION`/`CHANGELOG` found no wiring, which
looks like a pre-existing gap from Task 6/7, out of scope here to fix).

Left referencing ninja, deliberately not touched (out of scope, not "how
to build"): `Frameworks/scm/tests/t_hg.cc`/`t_svn.cc` test-failure messages
suggesting `ninja scm/coerce` to skip (a test-content edit, not build
docs); `Xcode/Base.xcconfig` and `Xcode/scripts/*.sh` historical
"matches/replaces what rave did" provenance comments; `project.yml`'s three
`cxx_tests` non-translation rationale comments; `CHANGELOG.md`,
`docs/benchmarks/*`, `docs/superpowers/*` (historical records);
`.github/dependabot.yml` (still-accurate phase-tracking rationale);
`Default.tmProperties`/bundle `.plist` data files/`bindings.plist`/
`DocumentWindowController.mm`/`bin/generate_available_bundles.rb` (all
about the unrelated `.ninja`-file-format grammar or the third-party Ninja
bundle by name, not this repo's own build).

**Why:** Task 8 items 2–6: delete the rave build now that Task 7 proved
parity; keep `bin/build` working; rewrite the build docs in the same
commit as the deletion so they never lie even transiently; clean
`.gitignore` of patterns that no longer apply.

### If interrupted here

The deletion, `bin/build`, `.gitignore`, `project.yml`'s header,
`.tm_properties`, and `docs/RELEASING.md` are committed together (the
docs had to land atomically with the deletion). `README.md` and `CLAUDE.md`
are in the same commit. Still to verify and report: a clean-state
`xcodebuild -scheme TextMate -configuration Release build`, all 26 test
targets against the parity doc, `git ls-files '*.rave'` empty,
`lipo -archs` on the freshly built app, and the Intel grep. Nothing pushed.

## 2026-08-13 — Task 8, step 1: CI workflows switched from ninja to xcodebuild

**What:** `.github/workflows/build-and-test.yml`: both jobs' `Configure`
step (`./configure`) and `ninja` invocation replaced with `xcodebuild
-project TextMate.xcodeproj -scheme TextMate -configuration Release build`;
`ninja` dropped from both `brew install` lines. The test job's dynamic
`.rave`-file discovery (`grep ... Frameworks/*/default.rave`) replaced with
a fixed, hand-maintained list of the 20 CI-included `<name>_test` Xcode
targets (the same 20 from the 26-target parity baseline) — dynamic
discovery has no source left to discover from once `.rave` files are gone.
Each target is now built with `xcodebuild -target <name>_test ...
CODE_SIGNING_ALLOWED=NO` and then its compiled binary is executed directly
(mirrors Task 7's proven per-target method exactly), since there is no
native `xcodebuild` action equivalent to ninja's build+run `RunTest` rule
for these CxxTest binaries. Verified locally against the real
`TextMate.xcodeproj` before writing this: `text_test` builds and runs exit
0 via this exact pattern. `.github/workflows/release.yml`: `ninja` dropped
from its `brew install` line; the `Pre-seed local.rave` + `Configure` +
`ninja TextMate` steps collapsed into one `xcodebuild ... CODE_SIGN_IDENTITY=
"$CS_IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" build` step; `Locate built
app` now points at the fixed, xcconfig-pinned `~/build/textmate-revived/xcode/
Release/TextMate.app` instead of a generic `$HOME/build` search. The
inside-out manual re-sign/re-seal/re-sign-outer-app steps that follow are
left structurally unchanged (still correct and still needed: `assemble_resources.sh`
copies some embedded binaries with plain `cp`, which Xcode's native
Embed-and-sign machinery never touches, unlike the real Xcode targets
Task 7 confirmed are auto re-signed on embed). `.github/workflows/ci.yml`
needed no change — it only delegates to `build-and-test.yml` and never
mentions ninja itself. `gitleaks.yml` untouched, as instructed.

**Why:** Task 8 item 1: switch CI to `xcodebuild` before deleting the files
CI used to depend on, so CI is never broken mid-migration. The
`github.repository == 'sdenike/textmate'` guard and the six headless-hostile
test exclusions (buffer, cf, layout, command, editor, file) are preserved
verbatim per the task brief. `hg`/`svn` installation for `scm`'s tests is
untouched.

### If interrupted here

CI conversion is committed and complete. Task 8's remaining, irreversible
step — deleting `configure`, `bin/rave`, all `.rave` files, and the
now-dead rave-only helpers (`bin/rave2yaml`, `bin/gen_build`,
`tests/rave2yaml_test.sh`), rewriting `bin/build` to drive `xcodebuild`,
and rewriting `README.md`/`CLAUDE.md` in the same commit — has not started
yet. `CONTRIBUTING.md` was checked and needs no change (it never described
the build system). Nothing pushed.

## 2026-08-13 — Task 7 complete: Xcode/ninja parity measured and proven

**What:** `docs/benchmarks/2026-08-12-ninja-parity.md` now has the full Xcode-side
measurement alongside Task 2's ninja baseline: artifact parity (41/41 ninja
artifacts confirmed under Xcode by identity, one real gap — `CommitWindowTool`
— found and fixed, not explained away), test parity (all 26 test targets,
identical pass/fail/crash pattern to the ninja baseline including failure
counts and assertions), and the `regexp`/Onigmo discrepancy write-up
(root-caused to `libtool -static`'s lazy archive linking dropping
`vendor/Onigmo/src/setup.c`'s symbol-less constructor, fixed with
`-force_load`, verified passing on both builds). The document states plainly:
**parity is proven.**

Four commits this session: `3cb54ea0` (the regexp/Onigmo fix), `4f848f7b` (the
CommitWindowTool + empty-`dependencies:` fix), `26213106` (committed
`TextMate.xcodeproj`, `.gitignore` updated), and this one (the parity doc).

**Why:** Task 7 gates Task 8, the irreversible deletion of `configure`,
`bin/rave`, and all 60 `.rave` files. The brief was explicit that an
unmeasured parity claim is worse than no claim — every number in the parity
doc traces back to a command actually run this session, not an assumption.

### If interrupted here

Task 7 is DONE. Phase 2 is 7 of 8. Task 8 (delete rave/ninja, switch CI to
`xcodebuild`, strip any remaining Intel references, rewrite `README.md`/
`CONTRIBUTING.md`/`bin/build`) is next and is the phase's only irreversible
step — it should not start without the user's explicit go-ahead given its
scope. Nothing pushed; no PR opened for Phase 2 yet.

## 2026-08-13 — Task 7: committed the generated TextMate.xcodeproj

**What:** `.gitignore`'s blanket `*.xcodeproj/` pattern removed (it predated
this task's decision to commit the generated project; the comment above it
already said as much was still pending). `TextMate.xcodeproj/project.pbxproj`
and `project.xcworkspace/contents.xcworkspacedata` now tracked --
`xcuserdata/`/`*.xcuserstate`/`*.xcscmblueprint`/`*.xccheckout`, already
present lower in `.gitignore`, still keep every per-user bit out regardless
of the outer directory being tracked. Grepped the committed `project.pbxproj`
for `/Users/shelby` first: zero matches -- every path XcodeGen emitted is
`$(SRCROOT)`-relative, nothing machine-local leaked in.

**Why:** Task 7's own checklist: "contributors need only Xcode, not
XcodeGen." `project.yml` stays the source of truth; regenerate with
`xcodegen generate --spec project.yml` after editing it.

### If interrupted here

Only the parity doc write-up (`docs/benchmarks/2026-08-12-ninja-parity.md`)
remains for Task 7. All measurements (41/41 artifacts by identity, 26/26 test
targets built and run, regexp discrepancy resolved and verified both ways)
are already done and committed in the three prior commits this session.

## 2026-08-13 — Task 7: artifact-parity sweep found and fixed a real missing artifact

**What:** Measuring the Xcode build's artifacts against Task 2's recorded 41
ninja artifacts (by identity, not path, per this task's instruction) found one
real gap: `TextMate.app/Contents/MacOS/CommitWindowTool` was absent -- 29
executables under the Xcode-built app instead of ninja's 30. `bin/rave2yaml`'s
`EMBED` table (Task 6) captured every `files`/`copy` directive declared
directly on a bundle-producing target's own `default.rave`, but missed the one
case where the directive lives on a plain library that a bundle target merely
`require`s: `Frameworks/CommitWindow/default.rave:5` has `files
@CommitWindowTool "MacOS"`, and rave's own `signature()` (bin/rave:1097)
folds every REQUIRED target's own assets into the requiring bundle -- not
just the bundle's own declared assets. Confirmed by reading bin/rave's
source, not inferred. Fixed by adding `CommitWindowTool` to `EMBED['TextMate']`
(keyed by the bundle that actually copies it in, matching every other EMBED
entry) and `EMBED_DESTINATION['CommitWindowTool']`.

That surfaced a second, previously-latent bug: `CommitWindowTool` is the
first-ever tool-kind target with neither a `require` nor a `frameworks`/
`libraries` line (confirmed against its own build.ninja Link edge, which
really links nothing but libc++), so `emit_tool_target`'s unconditional
`dependencies:` key had nothing under it -- valid to bin/rave2yaml, but `nil`
to a YAML parser, and XcodeGen rejected it ("Incorrect type, expected
Array<Any>"). Fixed by only emitting the `dependencies:` key when there is at
least one target or SDK to list.

`project.yml` regenerated (additive: one new `CommitWindowTool` target block,
one new embed dependency entry, one guarded `dependencies:` block).
`TextMate.app` rebuilt clean and now has all 30 executables under
`Contents/`, matching ninja's 30 exactly. Full `xcodebuild -scheme TextMate
-configuration Release build` still succeeds, zero real errors (`grep
error:` hits are all inside deprecation-warning text/selector names like
`...configuration:error:`, not actual failures).

**Why:** Task 7's artifact-parity requirement is explicit: "every ninja
artifact needs an Xcode counterpart... an unexplained missing artifact
blocks Task 8." This one was neither explained away nor missed.

### If interrupted here

Full artifact parity (41/41 by identity) and full test parity (26/26 targets
built and run, results matching the ninja baseline's pass/fail/crash pattern
target-for-target) are both MEASURED and confirmed as of this entry. Not yet
done: commit `TextMate.xcodeproj` itself (`.gitignore` already updated to stop
excluding it), and write up
`docs/benchmarks/2026-08-12-ninja-parity.md` with the Xcode-side results and
the CommitWindowTool/regexp findings.

---

## 2026-08-13 — Task 7: root-caused and fixed the regexp/Onigmo Xcode-vs-ninja discrepancy

**What:** `bin/rave2yaml` now emits `OTHER_LDFLAGS: "$(inherited) -force_load
$(BUILT_PRODUCTS_DIR)/libOnigmo.a"` on every tool/bundle/app/test target whose
dependency closure links Onigmo (`emit_onigmo_force_load`, called from
`emit_tool_target`, `emit_bundle_target`, `emit_app_target`, `emit_test_target`).
`project.yml` regenerated (28 additive lines, nothing else changed) and
`TextMate.xcodeproj` regenerated from it. `regexp_test` now passes 41/41 under
Xcode; re-ran ninja's `regexp/test` afterward and it still passes 41/41 too — the
fix touches only the Xcode project generator, no `.rave` file or vendor source.

**Root cause, found by measurement, not guesswork:** `vendor/Onigmo/src/setup.c`
is a bare `__attribute__((constructor))` that calls `onig_set_default_syntax()`
to turn Unicode-range `\w`/`\p{Upper}`/`\p{Lower}` matching ON (Onigmo's built-in
default has `ONIG_OPTION_ASCII_RANGE` on, i.e. ASCII-only). It exports zero
symbols — libtool's own build log says so: `warning: 'setup.o' has no symbols`.
bin/rave links every object file directly onto each final link command, so
setup.o always rides along. XcodeGen packages Onigmo as a real `libOnigmo.a` via
`libtool -static`, and Xcode's final link consults that archive with ordinary
lazy, reference-driven member selection — since nothing ever references
setup.o, the linker never pulls it from the archive, the constructor never
runs, and `\w` silently falls back to ASCII-only. That is exactly the observed
bug: `capitalize()` on "æblegrød" produced "æBlegrød" (capitalizing the second
letter, not the first) because `\w` no longer matched "æ" at all.

Isolated empirically with a minimal `onig_new`/`onig_search` probe linked
against real compiled objects from both builds, ruling out every flag-level
candidate the task named before finding this: source-file set (identical, 24
files), `-funsigned-char`/`-std=c99`/`-Os`/`-flto=thin`/`-DNDEBUG` (byte-identical
in the real captured command lines, confirmed via `-showBuildSettings` and the
build log's response file), `-fno-common` (tested in isolation, doesn't
reproduce it), LTO (tested with `LLVM_LTO=NO`, bug persisted — ruling LTO out
entirely), PCH content and a fully-cleared `SharedPrecompiledHeaders` cache (bug
persisted). What finally isolated it: linking Xcode's own freshly, doubly-clean
rebuilt object files directly (no archive) passed; linking the exact same
objects via `libtool -static`'s `libOnigmo.a` failed. That is the whole
difference — archive-mediated (lazy) linking vs. direct object linking.

**Why:** Task 7 requires either a resolved discrepancy or an honest unresolved
one with evidence — this is resolved, with the fix verified on both builds.

### If interrupted here

Fix is committed. Still open for Task 7: artifact-count comparison (41 ninja
artifacts vs. Xcode), the full 26-target test-parity table under Xcode, then
committing `TextMate.xcodeproj` itself (currently gitignored by `*.xcodeproj/`
in `.gitignore` — that pattern needs a `TextMate.xcodeproj` exception before it
can be added) and the final `docs/benchmarks/2026-08-12-ninja-parity.md` update
stating whether parity is proven.

## 2026-08-13 — Task 6 complete: TextMate.app builds from Xcode; duplicate binaries eliminated

**What:** `TextMate.app` now builds from `TextMate.xcodeproj` (`fb8c3e61`..`9346f20b`, five
incremental commits). 86 targets. All six embedded products land at their correct bundle paths:
PrivilegedTool, `mate`, `tm_query`, Dialog.tmplugin, Dialog2.tmplugin, TextMateQL.qlgenerator.
Bundle identity verified byte-for-byte against the ninja build — same `CFBundleName`,
`CFBundleShortVersionString`, `CFBundleIdentifier`. Released as **v3.0.0-revived.3**, the first
build the Xcode project produced rather than ninja.

Scope discoveries handled: the app embeds six other built products via `@target` references, and
two of them (`Dialog`, `Dialog2`) live under `PlugIns/`, which `bin/rave2yaml`'s walk scope had
deliberately excluded since Task 1. The walk was widened.

**Duplicate binaries — three distinct causes, all closed** (user reported two launchable copies
in Spotlight):

1. `xcodebuild` defaults `SYMROOT` to `<project>/build`, writing a fully launchable
   `TextMate.app` **inside the working copy** where Spotlight indexes it. `SYMROOT`, `OBJROOT`,
   and `SHARED_PRECOMPS_DIR` now point at `~/build/textmate-revived/xcode` (`b72c2d22`).
2. `bin/deploy-local` copied rather than moved, leaving a launchable app in the build tree. It
   now verifies the installed bundle's identifier matches what it built, **then** removes the
   build copy (`1901536f`). The verification runs before the removal on purpose — never delete
   the only copy on an unverified install.
3. Stale copies in `DerivedData` and both build trees, plus the root-owned `~/build/textmate`
   from an old sudo run (removed by the user), deleted.

Result: `mdfind` for launchable `TextMate.app` returns exactly one path, `/Applications`.

`.metadata_never_index` in `~/build` suppresses future indexing but does not retract existing
index entries, which is why deleting the stray copies was necessary rather than optional.

**Also:** `CFBundleName` reverted to `TextMate` at the user's request — the version string
(`3.0.0-revived.N`) is what identifies this as the Revived build, so the menu bar does not need
to carry it.

**Carried into Task 7, not resolved:**
- The `regexp` Unicode casing assertion still differs between the ninja and Xcode builds. Real,
  reproducible, and it blocks retiring ninja.
- `CS_GET_TASK_ALLOW` is fixed at project-generation time rather than read per-configuration at
  build time, after three entitlements build-graph failures. Release unaffected; Debug
  entitlements are a documented simplification.

**Why:** Task 6's gate was a bundle Xcode produces that is identical to ninja's. It is, and it is
installed and running.

### If interrupted here

Phase 2 is 6 of 8. `/Applications/TextMate.app` is v3.0.0-revived.3, built by Xcode. Next: Task 7
proves parity against Task 2's recorded baseline (41 artifacts, 26 test targets) and must resolve
the `regexp` discrepancy; Task 8 is the irreversible one that deletes `configure`, `bin/rave`, all
60 `.rave` files, and switches CI to `xcodebuild`. Nothing pushed; Phase 2 has no PR yet.


## 2026-08-13 — Phase 2 Task 6: TextMate.app builds and runs from Xcode

**What:** `xcodebuild -project TextMate.xcodeproj -scheme TextMate -configuration Release
build` now produces a working `TextMate.app`, with real (non-`CODE_SIGNING_ALLOWED=NO`)
ad-hoc codesigning, matching the ninja build's identity exactly: `CFBundleName` TextMate,
`CFBundleShortVersionString` 3.0.0-revived.2, `CFBundleIdentifier` com.macromates.TextMate
(PlistBuddy-verified against both builds). All six embedded products
(`PrivilegedTool`, `mate`, `tm_query`, `Dialog.tmplugin`, `Dialog2.tmplugin`,
`TextMateQL.qlgenerator`) are present at their correct bundle paths. `./bin/deploy-local`
succeeded against the Xcode-built app — identifier guard passed, installed to
`/Applications/TextMate.app`. `xcodebuild -alltargets ... CODE_SIGNING_ALLOWED=NO` still
succeeds for the full 86-target project (Task 5's 76 + mate/tm_query/PrivilegedTool/
tm_dialog/tm_dialog2/Dialog/Dialog2/TextMateQL/TextMate); `text_test -v` still `34 tests
passed`, exit 0.

**Scope discoveries confirmed and closed, in order:**

1. **PlugIns widened into rave2yaml's walk.** `all_targets_by_name`/`run_inventory` now
   glob `PlugIns/*/default.rave` too (60 targets, was 56). `run_header_farm` deliberately
   NOT widened — Dialog/Dialog2 never export headers to anything.
2. **`checked_target` accepts non-framework kinds, but only at the walk's own root.**
   `TOP_LEVEL_KINDS` (framework/tool/bundle/qlgenerator/app) applies only when
   `name == root` (threaded through `transitive_requires`/`transitive_header_deps`);
   anything reached via an ordinary `require` edge still must be `framework` — matches
   rave's real graph, where nothing ever requires a tool/bundle/app/qlgenerator target.
3. **`EMBED`/`EMBED_DESTINATION` tables** (hand-verified against each `files`/`copy` line,
   same VENDOR_EXTRA rationale: `files`/`copy` content isn't parsed generically) translate
   `files @X`/`copy @X` into native XcodeGen `dependencies: embed: true, copy:
   {destination, subpath}` Copy Files phases — a real Xcode build phase Xcode itself
   orders and re-signs on copy, not a raw `cp -R` racing the rest of the build.
   `add_to_closure` recurses through EMBED so requesting just `TextMate` transitively
   pulls in all eight embedded/nested targets and their own `require` closures.
4. **Four new kind emitters** in `bin/rave2yaml`: `emit_tool_target` (mate, tm_query,
   PrivilegedTool, tm_dialog, tm_dialog2 — generalizes the frameworks/libraries
   aggregation Task 5 flagged as `_test`-only), `emit_bundle_target` (Dialog, Dialog2,
   TextMateQL — `type: bundle` + `WRAPPER_EXTENSION`), `emit_app_target` (TextMate).
   `choose_prefix_header`/`emit_sources` generalized from a hardcoded `.cc`+`.mm` mix to
   any N-extension combination (TextMateQL is the first `.c`+`.mm` user).
5. **Four new `Xcode/scripts/*.sh`**: `expand_plist.sh`/`markdown.sh`/`utf16.sh` (one per
   non-native rule — ExpandVariables/CompileMarkdown/ConvertToUTF16 — mirroring
   `build.ninja`'s actual command lines), `assemble_resources.sh` (postBuildScripts
   orchestrator interpreting each bundle-like target's `files`/`copy` manifest by hand,
   verified line-by-line against its `default.rave`). CompileIcon reuses the pre-existing
   `bin/build_app_icon.sh` directly. `RunExecutable`/`RunApplication` deliberately NOT
   ported — dev-only `ninja <target>/run` conveniences superseded by Xcode's native Run
   scheme action; out of scope for a `build` action.

**Seven real, distinct build failures, each traced to its actual cause, not guessed:**

1. **Onigmo_test regression, caught before commit.** First kind-dispatch draft nested
   `emit_test_target` inside the `'framework'` branch only; a vendor target with tests
   (Onigmo) would have silently lost its `_test` block. Caught by diffing the regenerated
   project.yml against the prior commit before building, not by a failed build.
2. **`type: bundle` doesn't get XcodeGen's default "link static libs to executables"
   treatment `type: tool` does** — TextMateQL linked with every `-framework` flag present
   but every `-l<static-lib>` flag silently missing ("Undefined symbols" for
   `buffer_t`/`settings_for_path`/etc). Fixed with explicit `link: true` on every
   framework/vendor dependency `emit_bundle_target`/`emit_app_target` emit.
3. **Real codesigning (no `CODE_SIGNING_ALLOWED=NO`) refuses to sign a bundle target with
   no `INFOPLIST_FILE`** — invisible under the `CODE_SIGNING_ALLOWED=NO` per-target test
   builds used through the rest of this task; only a full, actually-signing `-scheme`
   build exercises it. Fixed by adding `INFOPLIST_FILE` (pointing at the real,
   unexpanded plist) to `emit_bundle_target` too, derived from `target.file`'s own
   directory rather than a second hand-built table.
4. **Entitlements: three consecutive build-graph failures**, in order — "Entitlements
   file ... was modified during the build" (generating it from the same late
   `postBuildScripts` phase as everything else — ProcessProductPackaging reads
   `CODE_SIGN_ENTITLEMENTS` far earlier than Resources); "Multiple commands produce ...
   Entitlements.plist" (moved to `preBuildScripts`, but under `$(DERIVED_FILE_DIR)` with
   the same filename Xcode stages internally); "Cycle inside TextMate" (renamed, still
   under `$(DERIVED_FILE_DIR)` — ANY `CODE_SIGN_ENTITLEMENTS` path there makes Xcode treat
   it as a node it's also responsible for producing). Resolved by abandoning build-time
   generation entirely: XcodeGen's native `entitlements: path:/properties:` key (verified
   against the installed 2.46.0's actual output, not assumed) writes the file at
   `xcodegen generate` time, so by the time `xcodebuild` runs it's just an ordinary
   pre-existing file. Trade-off recorded: `CS_GET_TASK_ALLOW` is fixed at generation time
   (hardcoded to Release's `false`) rather than reading `$CONFIGURATION` at build time —
   acceptable since Release is this task's verification target and Xcode's own local
   ad-hoc signing already adds `get-task-allow=1` unconditionally regardless (observed
   directly on `mate`, which has no entitlements wired at all).
5. **`Frameworks/network` case-collides with Apple's real `Network.framework` on APFS** —
   a NEW instance of the same class of risk header-strategy.md's Task 5 addendum already
   flagged, via a different mechanism: rave precompiles `Shared/PCH/prelude.*` ONCE,
   globally, with a fixed dependency-independent flag set, so its `#import <WebKit/
   WebKit.h>` always resolves against Apple's real framework; Xcode's
   `GCC_PRECOMPILE_PREFIX_HEADER` is inherently per-target, so TextMate — the first target
   whose closure both requires `network` and forces `prelude.mm` — precompiled its PCH
   with `$(SRCROOT)/Xcode/include/network` on the search path, and APFS treats that path's
   own `network/` subdirectory as equal to `Network/`, shadowing Apple's framework
   ("no template named 'map' in namespace 'std'"). Fixed narrowly: TextMate's own sources
   never `#include <network/...>` directly (grepped, zero matches) — `network` is only in
   its `require` for linking, unaffected by excluding it from `HEADER_SEARCH_PATHS`
   specifically (`APP_HEADER_SEARCH_EXCLUDE`) rather than restructuring the farm itself
   (a bigger, riskier change touching all 76 already-verified targets).
6. **`destination: wrapper` means the product ROOT, not `Contents/`** — misread from the
   ProjectSpec.md text on first pass; `TextMateQL`'s `subpath: 'Library/QuickLook'` alone
   landed at `TextMate.app/Library/QuickLook/`, a stray top-level entry codesign refuses
   to seal ("unsealed contents present in the bundle root"). Fixed by spelling out
   `Contents/` in the subpath explicitly.
7. **Leaked rbenv `GEM_HOME`/`GEM_PATH`** (the exact hazard CLAUDE.md documents for
   `bin/build`) broke `markdown.sh`'s `bin/gen_html` call via `gen_credits.rb`'s ERB
   template requiring `net/https` → `openssl` (system Ruby 2.6 dlopening a gem built for
   Ruby 3.3.6). `xcodebuild` inherits the invoking shell's environment; `bin/build`'s own
   `env -u GEM_HOME -u GEM_PATH -u RUBYLIB -u RUBYOPT -u BUNDLE_GEMFILE` sanitization
   doesn't run in this path, so it's mirrored directly in `markdown.sh` instead of
   depending on every future invoker remembering it.

**Deliberately out of scope, recorded honestly rather than silently skipped:**
`RunExecutable`/`RunApplication` (dev-only relaunch convenience, Xcode's Run scheme action
already replaces it); `mate`'s own `expand CS_ENTITLEMENTS` (only the app's entitlements
are load-bearing per the task brief's explicit rules; `mate` still builds and embeds fine
without its two extra automation/library-validation grants). Neither affects the
verification bar.

**Why:** Task 6 is the last major translation gap before Task 7's parity proof — the app
target is what actually ships, and it's the first target exercising nearly every
mechanism this migration built (embedding, non-native resource rules, real codesigning,
per-target PCH) at once, which is exactly why it surfaced seven real bugs six frameworks
combined never did.

### If interrupted here

Task 6 is functionally complete: `TextMate.app` builds clean from Xcode with real
codesigning, matches ninja's identity exactly, all six embedded products present,
`bin/deploy-local` succeeded (currently installed at `/Applications/TextMate.app`).
`TextMate.xcodeproj` and `build/`/`Xcode/generated/` are gitignored and regenerable
(`xcodegen generate --spec project.yml`), not committed. Not yet done: updating
`docs/superpowers/plans/2026-08-12-phase-2-xcode-migration.md`'s Task 6 checkboxes (left
for the coordinating agent), and `docs/benchmarks/2026-08-12-header-strategy.md` could use
a short addendum for the `network`/`Network.framework` per-target-PCH finding (a second,
distinct instance of the same case-insensitivity risk class, found by a different
mechanism than the first one). Task 7 (prove full parity against Task 2's ninja baseline,
then commit the generated `.xcodeproj`) is next — it inherits one open item from Task 5
(`regexp_test`'s Unicode `capitalize()` finding) and should re-check `text_test`'s 34/34
against ninja's own count as part of its systematic pass, not just the pilot spot-check
this task repeated.

---

## 2026-08-13 — Phase 2 Task 5 (2/2): build-recipe fixes found by actually building all 46+3, full project.yml

**What:** With `bin/rave2yaml` translating every gap (previous entry), generated
`project.yml` for all 46 frameworks + 3 vendor targets (`--emit-yaml <all 46 names> kvdb Onigmo
xdiff`) and ran `xcodebuild -alltargets -configuration Release build CODE_SIGNING_ALLOWED=NO` to
completion. First attempt failed immediately (vendor gap not yet closed at that point); after the
gaps landed, four more real, distinct build failures surfaced, fixed one at a time as instructed,
each traced to its actual cause rather than guessed at:

1. **`CLANG_ENABLE_MODULES` defaults YES** (XcodeGen's own `base.yml` preset) but rave never passes
   `-fmodules` anywhere. With modules on, `vendor/xdiff/src/xpatience.c` pulled in the `Darwin`
   module (via the prelude header's system includes), whose own `search.h` declares an unrelated
   `struct entry` (POSIX hsearch) colliding with xpatience.c's same-named local struct --
   "incompatible definitions in different translation units". Fixed with `CLANG_ENABLE_MODULES = NO`
   in Base.xcconfig, project-wide (any target could hit the same class of collision).
2. **Xcode's automatic public-header install collided with a real Apple framework.** A
   `library.static` target's directory `sources: path:` entry defaults every `.h` it contains to
   Headers-phase PUBLIC visibility, copied to `build/Release/include/<TargetName>/`. APFS is
   case-insensitive, so `Frameworks/network`'s copy at `.../include/network/` IS
   `.../include/Network/` too -- exactly where WebKit.h's own `#import <Network/Network.h>`
   resolves once that directory is on the search path, shadowing Apple's real Network.framework
   with our own `network/constants.h` (compiled with no PCH context: "no type named 'string' in
   namespace 'std'"). Chased this into a bigger, better fix (next item) rather than patching around
   it with `headerVisibility:`.
3. **Directory `sources: path:` over-includes vs. rave's exact glob -- the real fix for #2 too.**
   `Frameworks/FileBrowser/src/drivers` is a pre-existing symlink to `Frameworks/scm/src/drivers`
   (predates this migration). rave's own `sources src/*.mm src/OFB/*.mm` glob never traverses into
   it, so rave never compiles it, but XcodeGen's directory `path:` entries recurse through symlinked
   subdirectories too, silently duplicating scm's driver sources into FileBrowser (surfaced as a
   spurious PCH request for `drivers/api.cc`, a `.cc` file inside an all-`.mm` target). Fixed by
   switching EVERY framework's (and vendor target's) `sources:` from a directory reference to an
   explicit, resolved file list built from the exact same glob rave itself resolves -- whatever rave
   compiles is exactly and only what Xcode compiles now. This also fixes #2 for free: an explicit
   list of `.cc`/`.mm`/`.c`/`.m` files never includes a `.h`, so Xcode's Headers-phase copy has
   nothing to act on -- no `headerVisibility:` workaround needed at all (added then removed within
   this same task once the better fix was found).
4. **Mixed `.cc`+`.mm` targets (7: BundleEditor, OakDebug, command, document, io, plist, theme) need
   a PER-FILE prelude, which Xcode's one-per-target `GCC_PREFIX_HEADER` can't give directly.**
   Verified by direct clang invocation that neither prelude works for both languages at once (see
   header-strategy.md addendum). First fix attempt (automatic `GCC_PREFIX_HEADER=prelude.cc` +
   forced second `-include prelude.mm` via `compilerFlags:` on the `.mm` files) failed a real build
   (`theme`): clang only honours the precompiled form of the FIRST `-include`; Xcode's own automatic
   one lands second and falls back to a textual include of an internal cache path that isn't a real
   file. Fixed by leaving `GCC_PREFIX_HEADER` unset for mixed targets entirely and forcing BOTH
   `.cc` and `.mm` groups onto their own prelude via `compilerFlags:` -- verified end to end in a
   scratch XcodeGen project before reapplying. The Ragel-generated `.cc` (plist only) needed the
   same forced `-include`, PLUS `-iquote <dirname of the original .rl file>` (rave's own
   `CompileRagel` adds exactly this, bin/rave:643, because the generated file textually carries
   `ascii.rl`'s own `#include "ascii.h"` unchanged, which only resolves against the original
   directory, not $(DERIVED_FILE_DIR)) -- without it: "fatal error: 'ascii.h' file not found".

Two more, smaller: `Xcode/scripts/gen_test.sh` assumed every target's tests live under
`Frameworks/<name>/tests/`, wrong for the one vendor target with tests (Onigmo, at
`vendor/Onigmo/tests/`) -- fixed by checking which directory actually exists. Fixing that then
exposed a real `/bin/bash` 3.2.57 quirk (Apple's frozen, GPLv2-licensed-ceiling shipped bash):
expanding a zero-element array under `set -u` is an unbound-variable error there (fixed in bash
4.4+), reproduced directly; fixed with the standard `"${arr[@]+"${arr[@]}"}"` guard everywhere the
script touches the (now sometimes genuinely empty) test-file array. Added `Xcode/scripts/gen_ragel.sh`
(new file, mirrors `gen_test.sh`'s pattern) to invoke `ragel` as a preBuildScript.

**Also found and fixed in `bin/rave2yaml` itself:** a real cycle in the `.rave` require graph
(`plist` requires `io`, `io` requires `ns`, `ns` requires `plist`) fed the starting target back into
its own dependency closure, since the closure walk never special-cased "don't re-add the root".
Manifested as `plist` listing itself in its own `HEADER_SEARCH_PATHS` and `plist_test` linking
`- target: plist` twice. Fixed by threading a `root:` (defaults to the outer call's own name) through
`transitive_requires`/`transitive_header_deps`'s recursion, excluded unconditionally regardless of
how many cycles route back to it. Added `check_dupes`/`check_self_ref`-style invariant checks during
development (not committed as test files -- ad hoc verification, superseded by the full green build).

**Full verification:** `xcodebuild -alltargets -configuration Release build
CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` -- **BUILD SUCCEEDED**, exit 0. 49
`library.static` targets (46 frameworks + kvdb/Onigmo/xdiff) + 27 `_test` tool targets, all
produced (49 `.a` + 27 executables, zero missing). `text_test: 34 tests passed` (pilot, unchanged).
Ran all 27 test binaries directly (`--no-parallel` for the 7 with `.mm` tests, per CLAUDE.md): 22
clean passes; `buffer_test`/`file_test`/`cf_test` fail/crash exactly matching
`docs/benchmarks/2026-08-12-ninja-parity.md`'s already-recorded pre-existing baseline (not a Task 5
regression); `scm_test` fails needing `hg`/`svn`, also already documented as absent on this machine.
`regexp_test` (1 of 41: a `capitalize()` Unicode-casing assertion on "æblegrød") is a genuinely NEW
finding -- confirmed real and deterministic (3 reruns, identical), confirmed NOT caused by: source
file set (byte-identical object list vs. a scratch ninja build), compile flags for the relevant file
(diffed line-by-line, identical), `-flto=thin` (disabling it for this one target didn't change the
result), or locale env (`LANG`/`LC_ALL` identical, explicit override didn't change it). Root cause
sits somewhere inside Onigmo's Unicode property-matching at runtime, not isolated further --
flagged for Task 7's parity work rather than chased past a reasonable budget here, since Task 5's
gate is building, not full test-behaviour parity (`tests/rave2yaml_test.sh` still `PASS: 56 targets,
all dependencies resolve`).

**Why:** Task 5 exists to prove the pattern scales past one framework; every fix here would have
either silently miscompiled or hard-failed 7-46 more times if found later instead of once, here.

### If interrupted here

Phase 2 Task 5 is functionally complete: all 46 frameworks + 3 vendor targets build clean under
Xcode. `TextMate.xcodeproj` and `build/` are gitignored and regenerable (`xcodegen generate --spec
project.yml`, then `xcodebuild -alltargets ...`), not committed. Not yet done: updating
`docs/superpowers/plans/2026-08-12-phase-2-xcode-migration.md`'s Task 5 checkbox/status (left for
the coordinating agent), and the `regexp_test` Unicode finding needs a line in whatever tracks
Task 7's parity checklist. Task 6 (the TextMate app target itself) is next and explicitly out of
scope here -- deliberately not touched, per the task brief. One thing Task 6 should know going in:
`Applications/TextMate/default.rave` requires `kvdb` directly (confirmed already translatable, same
VENDOR_EXTRA mechanism) and the app target will be the first consumer of `frameworks`/`libraries`
declared on the framework/vendor targets themselves, which today only get surfaced for `_test`
tool targets (`linked_sdks`) -- the app target's own link step needs the same aggregation.

## 2026-08-13 — Phase 2 Task 5 (1/2): rave2yaml closes all 3 known gaps, decides header-farm fidelity

**What:** Scaled `bin/rave2yaml --emit-yaml` from the Task 4 pilot (`text` alone) to translating
any of the 46 frameworks + 3 vendor targets, closing the three gaps the task named plus one fidelity
question:

**1. `require_headers` (weak, header-only dependency).** Added `transitive_header_deps`, mirroring
`bin/rave`'s `required_targets(..., include_weak: true)` (bin/rave:786-806) exactly: follows BOTH
`require` and `require_headers` at every node the walk discovers (not just the start), so it's
always a superset of the hard-only closure. Used for `HEADER_SEARCH_PATHS` on both library and test
targets; the hard-only closure (`transitive_requires`) stays the one used for `dependencies:`/linked
frameworks, matching rave's executable()/test-link steps which never pass `include_weak`. Verified
against a hand-traced BFS for `TMFileReference` (`require_headers scm`, which itself pulls in scm's
own `require text cf io settings regexp xdiff` and regexp's `require Onigmo text cf`, all
transitively): 13 entries, matched exactly. `CommitWindowTool`'s `require_headers CommitWindow` is
NOT a true self-reference (the task's framing) -- it's a second, `tool`-kind target declared in the
same `Frameworks/CommitWindow/default.rave` file requiring the FIRST target's (a real framework)
headers for its own `#include <CommitWindow/CommitWindow.h>`. Confirmed a genuine no-op for
`--emit-yaml`'s framework-only graph: `CommitWindowTool` is never a `framework` kind (fails
`checked_target`'s kind check) and nothing else `require`s a `tool`, so it never appears as a node
in any closure.

**2. `cxx_tests` (dead metadata).** Removed from the fail-loud `UNTRANSLATED_DIRECTIVES` list;
`emit_cxx_tests_skip_comment` now prints a visible YAML comment (naming the file count and citing
`bin/rave:137`) immediately before any target that declares it (`ns`, `layout`, `OakAppKit`) instead
of either raising or silently dropping it, per the task's explicit instruction.

**3. Vendor targets (kvdb, Onigmo, xdiff), replacing the `04ac5128` fail-loud guard with real
translation.** Added `VENDOR_EXTRA`, a 3-entry table hand-built from each vendor `.rave` file's exact
`add FLAGS`/`add C_FLAGS` content (not parsed generically -- `add` is in `INERT_DIRECTIVES`, plumbing
this parser was never asked to record until now): Onigmo gets `-Ivendor/Onigmo -Ivendor/Onigmo/vendor`
+ 2 warning suppressions, xdiff gets `-Ivendor/xdiff/src` + 3 suppressions, kvdb gets nothing extra.
`checked_target` now only raises for a vendor target ABSENT from this table, preserving the guard's
spirit for anything not yet taught. New `emit_vendor_target` lists each vendor target's resolved
`sources` as explicit files (never a directory reference -- Onigmo's own `vendor/` subtree has 60+
files far outside its `sources` glob).

**Fidelity decision: narrowed the header farm to declared headers, not whole `src/`.** The Task 4
farm symlinked one directory per framework (`Xcode/include/<n>/<n>` -> `Frameworks/<n>/src`),
exposing every file, including private ones 8+ frameworks' `headers` directives deliberately don't
export (e.g. `settings` exports only `settings.h keys.h`, not its 4 real headers). That's the same
class of risk as the flat-`-I` trap Task 3 already rejected. Rewrote `run_header_farm` to symlink one
file per DECLARED header (resolved via the same `Dir.glob` the parser already uses for the `headers`
GLOB_DIRECTIVE), landing at the same path rave's own `ExportHeader` would use. 46 frameworks -> 186
header symlinks; regenerating also now covers `vendor/*/` (3 more: kvdb, Onigmo, xdiff), which the
Task 4 farm never walked at all. Added a migration guard: the OLD farm's `Xcode/include/<n>/<n>` was
itself a symlink, and naively `mkdir_p`-ing over an existing symlink-to-a-directory does nothing,
which would have made the new code's pruning step resolve THROUGH the old symlink and start
deleting real files under `Frameworks/<n>/src` -- caught by explicitly unlinking a symlink at that
path before creating a real directory there. Verified: `text` (whose `headers src/*.h` already names
every header) is unaffected (still 17/17); `regexp` now gets exactly its 7 declared headers, not the
5 private ones (`private.h`, `parser.h`, `parser_base.h`, `parse_glob.h`, `dependency_graph.h`) the
old farm also exposed. Full reasoning in `docs/benchmarks/2026-08-12-header-strategy.md`'s new
addendum.

Also found and fixed a real bug while regenerating: a genuine cycle in the `.rave` require graph
(covered in the next STREAM entry, since it was found while emitting the full 46+3 set, not this
narrower gap-closing pass).

`bash tests/rave2yaml_test.sh` updated and still passing (`PASS: 56 targets, all dependencies
resolve`): the old regression check asserted `--emit-yaml kvdb` RAISES (the gap this task closes);
replaced with an assertion that it now succeeds, emits explicit `vendor/kvdb/...` source paths, and
never references a nonexistent `Frameworks/kvdb/src`, plus a static (non-`eval`, no
arbitrary-code-execution risk) check that the unknown-vendor-target guard and its 3 `VENDOR_EXTRA`
entries are still present in the source.

**Why:** These are exactly the three gaps and the one fidelity question the task named as blocking
the full 46-framework graph; closing them here, individually, with dedicated verification per gap,
is what let the full build (next entry) find real build-recipe issues instead of tripping over
already-known translation gaps.

### If interrupted here

Committed. `bin/rave2yaml`, `Xcode/include/*` (regenerated farm), `tests/rave2yaml_test.sh`,
`docs/benchmarks/2026-08-12-header-strategy.md` all reflect this state. The full 46+3 `project.yml`
emission and the build-recipe fixes it surfaced are the next STREAM entry (same task, committed
separately since they touch a different, non-overlapping set of files: `Xcode/Base.xcconfig`,
`Xcode/scripts/*`, `project.yml`).

## 2026-08-13 — Xcode/scripts/gen_test.sh now collects .mm test sources (CRITICAL, pre-Task-5)

**What:** `gen_test.sh`'s test-source glob only matched `t_*.cc`, silently dropping every `.mm`
test file. Seven frameworks (`buffer`, `document`, `BundlesManager`, `FileBrowser`, `ns`,
`encoding`, `SoftwareUpdate`) have `.mm` tests -- their Xcode-generated runners would have compiled
and reported success while running zero of those tests. The `text` pilot didn't catch this because
`text` has no `.mm` tests. Fixed to glob both `t_*.cc` and `t_*.mm` under `nullglob` (so a
framework with only one extension doesn't leave a literal unmatched pattern in the list), then
merge-sort the combined array under `LC_ALL=C sort`. The plain `t_*.{cc,mm}` brace-expansion form
globs and sorts each extension separately before concatenating -- that disagrees with
`build.ninja`'s `GenTest` input order whenever a `.cc` and `.mm` file interleave alphabetically
(`buffer`'s own `t_buffer.mm` sorts before `t_indexed_map.cc`), so it was rejected in favor of an
explicit sort matching `bin/rave`'s `test_sources.sort.uniq`, which sorts the combined list by full
filename regardless of extension. Comment on line 7-8 corrected to name both extensions.

Verified by diffing the exact argv the script now passes to `bin/gen_test` against each framework's
`GenTest` edge input list extracted straight from `build.ninja`, for both `buffer` and `document`
(the latter has one `.cc` and one `.mm` test) -- byte-identical, same order, for both. `bash
tests/rave2yaml_test.sh` still `PASS: 56 targets, all dependencies resolve` (untouched, `.rave`
files not modified). `xcodebuild -target text ...` still `BUILD SUCCEEDED`; `text_test` still `34
tests passed`.

**Why:** Task 5 scales `gen_test.sh` to 46 frameworks; shipping this bug would have given seven of
them a silently-incomplete (but green) test runner -- the dangerous kind of failure, since nothing
in the build output flags it.

### If interrupted here

Committed (fix + this entry, one `fix:` commit). Nothing else outstanding for this gap. Task 5's
scale-up can proceed; no other `Xcode/scripts/*.sh` files were audited for the same class of bug --
worth a quick check if any other wrapper scripts glob framework sources by extension.

## 2026-08-13 — Phase 2: rave2yaml --emit-yaml now raises on vendor targets

**What:** `bin/rave2yaml --emit-yaml`'s `checked_target` now raises immediately when the
requested target (or anything in its transitive `require` closure) lives under `vendor/`
(`kvdb`, `Onigmo`, `xdiff`) -- naming the target and its `default.rave:line`, and explaining why:
vendor targets declare no `executable`, so they pass the `framework` kind check same as a real
framework, but diverge from the `Frameworks/<name>/src/` convention `--emit-yaml` assumes
(explicit `headers` paths, per-target `add FLAGS` include flags, brace-expansion source globs, no
`src/` convention). Before this, `--emit-yaml kvdb` silently printed a `library.static` target
whose `sources: Frameworks/kvdb/src` doesn't exist -- the exact silent-gap risk the task-4 report
flagged. `--inventory` is untouched (it doesn't call `checked_target`), so its vendor listing
(Task 7's parity checklist) stays complete. `cxx_tests`/`require_headers` fail-loud re-verified
still firing (`ns`, `OakDebug`, `TMFileReference`).

Added a regression test to `tests/rave2yaml_test.sh`: asserts `--emit-yaml kvdb` raises and that
the error names both "vendor target" and the `.rave` file. Verified the test actually catches the
regression -- ran it against the pre-fix tool (`git show HEAD:bin/rave2yaml` in a scratch copy)
and confirmed FAIL before restoring the fix. `bash tests/rave2yaml_test.sh` still reports `PASS:
56 targets, all dependencies resolve`; `xcodebuild -target text ...` (the Task 4 pilot) still
`BUILD SUCCEEDED` -- `text`'s closure never touches a vendor target, confirmed by diffing
`--emit-yaml text`'s output against the committed `project.yml` (byte-identical).

**Why:** Task 5 scales `--emit-yaml` to 46 frameworks; `DocumentWindow` and `Applications/TextMate`
both `require kvdb`, `regexp` requires `Onigmo` -- Task 5 would otherwise hit this cold and could
ship a quietly-broken `project.yml` instead of a clear stop.

### If interrupted here

Committed (code + test + this entry, one `build:` commit). Nothing else outstanding for this gap.
Vendor targets themselves are still NOT translated to Xcode -- deliberately out of scope here,
left for whichever task decides how `kvdb`/`Onigmo`/`xdiff` map into XcodeGen.

## 2026-08-13 — Merge-base repaired; dead build files and SyntaxMate removed

**What (merge base):** Phase 1 (#3) was squash-merged, which landed all 130 textmatelives commits'
content but left **no merge relationship in git topology** — `git merge-base --is-ancestor` said
NO, so a future sync from textmatelives would have re-conflicted on all 130 commits it no longer
knew we had. Fixed with `git merge -s ours textmatelives/main` (`ad8f2cd8`): changes no file, only
records the discarded ancestry. Verified the tree hash was byte-identical before and after, and
`--is-ancestor` now reports YES with 0 behind.

**Lesson:** whole-fork integrations get a real merge commit. Squash is for single units of work.
This matters again in Phase 3, which ports tectiv3's dependency purge the same way.

**What (cleanup, `87de6763`):**
- `.travis.yml` — targets xcode7.2, dead since 2016
- `local-orig.rave` — stale local build-config copy, referenced by nothing
- `Applications/SyntaxMate` — XPC service nothing in the tree requires; tectiv3 already deleted
  it and upstream PR #1462 exists to do the same. It carried a submodule
  (`SyntaxMate.tmBundle`), removed cleanly from `.gitmodules`.

Verified before deleting that nothing outside `Applications/SyntaxMate/` referenced it, then
reconfigured and rebuilt: `ninja TextMate` still succeeds and signs. Target count 57 to 56;
`tests/rave2yaml_test.sh` derives the count rather than hardcoding it, so it self-adjusted.

**Why:** The tree had been growing, not shrinking — two build systems now coexist by design until
Task 7 proves parity, but these three were dead regardless of which one wins, so there was no
reason to wait for Task 8.

### If interrupted here

Phase 2 Tasks 1-4 complete. `master` carries the merge-base fix and cleanup; `phase-2/xcode-migration`
has merged master and is 15 commits ahead. Next: Task 4 review, then the vendor-target gap
(`kvdb` passes the kind check without erroring — a silent gap) before Task 5 scales to 46 frameworks.


## 2026-08-13 — Phase 2 Task 4c: gen_test.sh, a second real xcconfig bug (NDEBUG), text_test green

**What:** `Xcode/scripts/gen_test.sh <name>` wraps `bin/gen_test`, writing the generated CxxTest
runner to `$DERIVED_FILE_DIR/_T<name>.cc` with the same atomic `$out~ && mv` write as
build.ninja's `GenTest` rule. `text_test`'s `preBuildScripts` entry (from `--emit-yaml`, previous
commit) calls it. Verified the trick this depends on -- an XcodeGen source with `optional: true`
and a `$(DERIVED_FILE_DIR)/...` path compiling even though the file doesn't exist until a
preBuildScript creates it at build time -- in a scratch `/tmp` project before relying on it here,
since it's not documented behavior, just an empirically-confirmed one.

Building `text_test` (Release) then failed at **link**, not compile: undefined `OakBadAssertion`,
`OakPrintBadAssertion`, `oak::to_s`. Traced it to `Frameworks/OakDebug/src/OakAssert.h`:
`ASSERT`/`ASSERT_EQ`/`ASSERT_NE`/etc. (used throughout `text/src`, e.g. `transcode.h`) are
`#ifdef NDEBUG`-gated to nothing; without `NDEBUG` they expand to real calls that only link if the
target also `require`s `OakDebug` -- which `text` correctly doesn't. Base.xcconfig's own comment
already said "rave release: ... `-DNDEBUG`" but the file never actually set it. Second real gap
found by actually building, not two unrelated bugs -- both were "the comment describes rave
correctly, the xcconfig line under it doesn't match the comment." Fixed with a config-scoped line,
`GCC_PREPROCESSOR_DEFINITIONS[config=Release] = $(inherited) NDEBUG`, since Debug/Release share one
xcconfig file and Debug should keep assertions live.

**Full clean verification, from scratch:** deleted `TextMate.xcodeproj` and `build/`, re-ran
`xcodegen generate --spec project.yml`, then `tests/xcode_parity_test.sh text` and
`tests/xcode_parity_test.sh text_test` (both PASS), then ran the built binary directly:
`text_test: 34 tests passed`, exit 0. Compared against `./bin/build text/test`'s own binary run
directly (ninja's `RunTest` progress line is mislabeled for every target, per the Task 2 entry
below, so the direct binary run is the trustworthy comparison): `text: 34 tests passed`, exit 0.
Same count, both green -- Xcode and ninja agree on this framework.

**Why:** Task 4's whole purpose is proving the pattern before Task 5 repeats it 45 times, so both
xcconfig bugs found here (bare `"..."` quoting, missing `-DNDEBUG`) are exactly the kind of thing
worth catching once on one framework instead of 45 times later.

### If interrupted here

Task 4 is functionally done: `text` and `text_test` both build clean under Xcode, tests run green
and match ninja exactly. Remaining before closing out the task: commit this increment
(`Xcode/scripts/gen_test.sh`, `tests/xcode_parity_test.sh`, the NDEBUG xcconfig fix, this entry),
write the task-4-report.md, verify `git status --porcelain` is clean of `TextMate.xcodeproj`/`build/`
(both gitignored) before that commit. Nothing else outstanding for Task 4 itself; Task 5 is next
(replicate across the other 45 frameworks) and Task 6 (app target) is explicitly out of scope here.

## 2026-08-13 — Phase 2 Task 4b: rave2yaml --emit-yaml, project.yml, and a real xcconfig bug

**What:** `bin/rave2yaml --emit-yaml <target>...` hand-prints (no `require 'yaml'`, see the entry
below) an XcodeGen `project.yml` for the named targets plus their transitive `require` closure:
`framework`-kind targets become `library.static`, and a target that declares `tests` also gets a
`<name>_test` `tool` target. Fail-loud like `--inventory`: unknown target, non-`framework` kind, or
an untranslated directive (`require_headers`, `cxx_tests`) all raise instead of being dropped.
`HEADER_SEARCH_PATHS` per target is generated from that target's own transitive closure (self +
deps for the test tool, deps-only for the library, matching how rave never grants a framework
`-I` to its own headers -- only to consumers); `frameworks`/`libraries` become `sdk:` dependencies
on the test tool only, since rave never needs them before final link either.

Ran `bin/rave2yaml --emit-yaml text > project.yml`, then `xcodegen generate --spec project.yml`,
then `xcodebuild -target text -configuration Release build CODE_SIGNING_ALLOWED=NO`.

**Real bug found and fixed, not a re-derivation:** the `text` target's first build failed --
`decode.cc:264: error: expected expression`, `NULL_STR` expanding to a bare unquoted `<U+FFFF>`
token. Read the actual compiler response file (not just `-showBuildSettings`, which still *showed*
quotes): `-DNULL_STR=<EF BF BF>` with **no quote bytes at all**. Bare `"..."` in an `.xcconfig`
value is grouping syntax xcconfig strips before the value reaches clang; Base.xcconfig's committed
line relied on the quotes surviving literally, and they don't. Fixed with the standard xcconfig
escape, `NULL_STR=\"￿\"`; re-checked the response file after the fix and it now reads
`-DNULL_STR="<EF BF BF>"`, matching rave byte-for-byte, quotes included. `text` builds clean
(2 pre-existing deprecation warnings, no errors) -- `libtext.a` produced.

Also added `*.xcodeproj/` to `.gitignore`: `project.yml` is the checked-in source of truth (same
relationship as the `.rave` files to `build.ninja`, already gitignored); the `.xcodeproj` XcodeGen
writes from it is regenerated on demand, never committed.

**Why:** Task 4 exists to prove the pattern before Task 5 repeats it 45 times, and this is exactly
the kind of bug that's cheap to fix once, on one framework, and expensive to rediscover 45 times if
it ships silently broken in Base.xcconfig.

### If interrupted here

`text` (library.static) builds clean under Xcode. Still needed: `Xcode/scripts/gen_test.sh`
(currently an empty dir), then generate+build `text_test`, run its binary, confirm exit 0, then
`tests/xcode_parity_test.sh` and a final STREAM entry. `project.yml` and the `Base.xcconfig` fix
are already committed-ready; `TextMate.xcodeproj` and `build/` are gitignored and untouched by any
commit.

## 2026-08-13 — Phase 2 Task 4a: header-farm symlinks generated by rave2yaml

**What:** `bin/rave2yaml --emit-header-farm` walks `Frameworks/*/` (the same set `--inventory`
walks) and writes a committed, relative symlink per framework: `Xcode/include/<name>/<name>` ->
`../../../Frameworks/<name>/src`. Ran it: 46 symlinks, one per framework (all 46 have a `src` dir).
Verified `Xcode/include/text/text/case.h` resolves through the link, a second run is a no-op
(idempotent), and the existing `tests/rave2yaml_test.sh` (`--inventory` regression check) still
passes untouched.

**Why:** This is the header strategy `docs/benchmarks/2026-08-12-header-strategy.md` decided:
per-framework include roots generated from the inventory so the farm can't drift as frameworks are
added or removed, rather than hand-maintained symlinks. Generating it now, decoupled from
`--emit-yaml`, means it survives on its own if the rest of Task 4 gets interrupted.

Also discovered while adding this: `require 'yaml'` crashes under this shell's actual environment
-- `GEM_HOME`/`GEM_PATH` are leaked from rbenv (`/Users/shelby/.gem/ruby/3.3.6`), so system Ruby
2.6's `require 'yaml'` dlopens a psych built for Ruby 3.3 and dies with `Symbol not found:
_rb_cFalseClass`. This is the same class of hazard CLAUDE.md documents for `bin/build`. Decided:
`--emit-yaml` (next) hand-prints YAML the way `--inventory` hand-prints its report, so `rave2yaml`
never gems-in `yaml`/`psych` at all.

### If interrupted here

Header farm is committed and regenerable. Still needed for Task 4: `--emit-yaml` in `bin/rave2yaml`
(project.yml emission for `text` + its transitive closure), `Xcode/scripts/gen_test.sh`, and the
actual `xcodegen generate` + `xcodebuild` verification. None of that depends on redoing this step.

## 2026-08-13 — Phase 2 Task 4 blockers solved in main loop after agent cutoff

**What:** The Task 4 implementer was cut off by a session limit after ~178k tokens having written
nothing durable (no `project.yml`, no `.xcodeproj`, `rave2yaml` still `--inventory`-only, clean
tree, no report). Rather than pay for another exploration round, settled its two blockers directly
and recorded them in `Xcode/Base.xcconfig` so they cannot be lost again.

**1. PCH.** `-include Shared/PCH/prelude.cc` works. clang does not care that the prefix file is a
`.cc` rather than a `.h`. Symptom when missing is `use of undeclared identifier 'std'`, which reads
like broken code and is not.

**2. `-funsigned-char` is load-bearing, and was nearly missed.** Extracted rave's real flag line
from `build.ninja` rather than assuming. Without it, `Frameworks/text/src/utf8.h` does not compile
at all: `constant expression evaluates to 128 which cannot be narrowed to type 'char'`, because its
UTF-8 lead-byte constants (128, 192, 224, 240) do not fit a signed char. Every framework including
`utf8.h` inherits that failure, so this single missing flag would have broken Task 5 across all 46
frameworks with an error pointing at the source rather than the build settings. Now
`GCC_CHAR_IS_UNSIGNED_CHAR = YES`.

**3. `NULL_STR` verified byte-for-byte.** rave passes `-D'NULL_STR="\uFFFF"'`. Compiled a probe
that prints the macro's bytes: 3 bytes `EF BF BF`, U+FFFF in UTF-8. The literal form now in the
xcconfig produces the identical macro.

Also mirrored rave's actual warning set and release optimisation (`-Os`, `-flto=thin`,
dead-strip) into the xcconfig, copied from `build.ninja` rather than chosen.

**Why:** These are the settings all 46 frameworks inherit. Each was found by reading what the build
actually does, and each would have failed later in a way that pointed at the wrong culprit.

### If interrupted here

Phase 2 Tasks 1, 2, 3 complete and reviewed. Task 4 (pilot framework under XcodeGen) still
outstanding — its compile recipe is now fully solved and recorded, so what remains is the
mechanical work: `rave2yaml` project.yml emission, the committed relative-symlink header farm at
`Xcode/include/<n>/<n>`, and the CxxTest script phase. Nothing pushed; Phase 2 has no PR yet.


## 2026-08-12 — Plan-number corrections and CLAUDE.md drift fix

**What:** Settles the STREAM entry owed by `d89cc1d6`, plus a real doc-vs-code drift the check surfaced.

Plan corrections (`d89cc1d6`):
- The plan claimed **54 test binaries**. Wrong — 54 is the `RunTest` *edge* count in `build.ninja`
  (27 targets x 2 configurations). Task 2 measured **26 discovered test targets**. Task 7's parity
  gate now names 26, so it is not judged against a fabricated number.
- Tech stack line said C++23; the tree compiles `-std=c++2a`. Aligned to C++20 per Task 3.
- Recorded that `scm/test` needs `hg` and `svn`, absent on this machine but installed by CI.

`CLAUDE.md` drift (this commit): it still listed **`capnp`** as a `./configure` dependency. Cap'n
Proto was removed by the Phase 1 textmatelives merge, so that line had been wrong since `ef1db3f2`.
This file is loaded into every agent session, so a wrong dependency list actively wastes time.
Also documented `bin/setup-hooks`, `bin/build`, and `bin/deploy-local`, including *why* `bin/build`
is preferred over bare `ninja` — the leaked `GEM_HOME` and root-owned credits-cache failures both
produce errors that point at the wrong culprit, and rediscovering them costs an hour each time.

**Why:** `README.md` and `CHANGELOG.md` were checked and genuinely need nothing: README still
describes the rave build, which remains accurate until Phase 2 Task 8 deletes it, and no
user-facing change has shipped since v3.0.0-revived.1.

### If interrupted here

Phase 2 Tasks 1, 2, 3 complete and reviewed on `phase-2/xcode-migration`. Task 4 (pilot framework
under XcodeGen) is next and is the first task that generates an actual `.xcodeproj`. Nothing is
pushed; Phase 2 has no PR open yet.


## 2026-08-12 — Phase 2 Task 2: ninja build parity baseline recorded

**What:** `./bin/build TextMate` succeeds (confirmed via zero `FAILED:` lines plus a clean
idempotent re-run, exit 0) and produces **41 artifacts** (executables only — zero `.a`,
zero `.dylib`, consistent with Task 4's static-linking finding). Discovered **26** test
targets (matches Task 1's `bin/rave2yaml --inventory` `tests`-directive count exactly) and
ran every one individually. Wrote `docs/benchmarks/2026-08-12-ninja-parity.md` with the full
artifact list, the 20 CI-included targets' pass/fail, and the six CI-excluded targets called
out separately, per the task's decided points.

**Three findings, none fixed (diagnostic task):**

1. **Genuine local failure outside the six CI excludes:** `scm/test` fails — `hg`/`svn` are
   both absent from `PATH` here, while CI's own workflow `brew install`s both before testing.
   Environment gap, not a code defect; 19 of the 20 CI-included targets pass.
2. **Ninja's `RunTest` progress line is mislabeled for every target** — always prints `Run
   tests for 'scope'…` regardless of which framework is actually running, because `bin/rave`
   emits one `RunTest` rule per framework but ninja rules are looked up by name and all share
   the name `RunTest`, so only one `description` string survives into `build.ninja`. The
   command itself runs the correct per-target binary (confirmed via each failure's own
   correctly-named source paths) — only the human-readable text is wrong. Worked around by
   invoking each of the 26 targets as its own `./bin/build <name>/test` call rather than
   trusting the brief's single combined command's log for per-target attribution.
3. **Half of the six CI-excluded targets don't actually fail locally:** `layout`, `command`,
   and `editor` all pass cleanly on this interactive, logged-in machine — CI's stated causes
   (parallel-runner contention; `NSApp` nil on a headless runner) are specific to CI's
   environment and don't hold here. `buffer` and `file` fail exactly as CI documents; `cf`
   crashes with SIGBUS (exit 138), consistent with CI's trap/segfault characterization.

Also caught and corrected the task brief's own inline test-discovery snippet: it keeps the
`Frameworks/` path prefix (`sed 's|/default.rave||'`), producing names ninja rejects.
`bin/rave`'s real phony targets are bare names (`target[:identifier]`, e.g. `authorization`,
not `Frameworks/authorization`) — used CI's actual `dirname | basename` pipeline instead,
per the brief's own pointer to `build-and-test.yml` as authoritative.

**Why:** Task 8 deletes the rave/ninja build permanently and is gated on Task 7 proving the
Xcode build matches this baseline. Without a recorded, honest baseline — including the
failures, not just the passes — that gate has nothing real to check against.

### If interrupted here

Task 2 committed, nothing left in progress. Next: Phase 2 Task 4 (pilot framework under
XcodeGen) per `docs/superpowers/plans/2026-08-12-phase-2-xcode-migration.md`.

---

## 2026-08-12 — Phase 2 Task 1 fix round 1/5: config-scope leak closed, PlugIns claim corrected

**What:** Review (SPEC OK, parser output confirmed byte-correct against the repo) raised
two Important findings against `bin/rave2yaml`, both fixed:

1. **Docs error:** `docs/benchmarks/2026-08-12-rave-inventory.md` and
   `task-1-report.md` (3 places) falsely claimed `PlugIns/dialog*/default.rave` was
   out of scope because it used unimplemented directives (`arch`/`notarize`/`define`).
   Re-read both files: they use only already-implemented directives
   (`target sources executable frameworks add prefix files`); only the nested
   `Bundle Support.tmbundle/src/default.rave` genuinely uses `arch`/`notarize`/`define`.
   Exclusion was always correct (walk scope never included `PlugIns/`), the *reason*
   given was wrong. Also fixed a swapped target-name pairing (`PlugIns/dialog` is
   `tm_dialog2`+`Dialog2`, not `tm_dialog`+`Dialog2`).
2. **Real bug:** `config { }` block content flowed through the same per-line dispatch
   as target-level content, with only a bare depth counter — nothing stopped a
   `sources`/`require`/`frameworks`/`libraries`/`executable`/`prefix` line inside a
   `config` block from silently merging into the target's unconditional fields as if
   config-independent. Never manifested (both real `config` blocks contain only inert
   `add PLIST_FLAGS`) — luck, not enforcement. Fixed: `config_stack` (replacing the old
   `depth` int) now tracks open config names, and a GLOB/LIST/SCALAR directive found
   while any config block is open raises `RaveError` with file, line, directive,
   config name(s), and target — rather than being recorded with no per-config
   representation. `INERT_DIRECTIVES` still permitted inside `config` (never surfaced,
   so can't misreport). Chose fail-loud over recording config scope, since the
   `--inventory` interface never asked for per-config fields (Task 1 decided point 2).

Full detail and checks in `task-1-report.md`'s "Fix round 1/5" section (gitignored,
`.superpowers/sdd/2026-08-12-phase-2-xcode-migration/`). `bash tests/rave2yaml_test.sh`
still reports `PASS: 57 targets, all dependencies resolve` — neither fix changes the
target count or dependency graph, since the real tree's one `config` usage was already
`add`-only.

**Why:** A checklist stating a false "verified by reading" claim is worse than making no
claim, since later tasks are measured against it. Silent config-scope merging is the same
failure class the brief called out as the one thing to get right — one level deeper than
an unrecognised directive: silent *misapplication* instead of silent *dropping*.

### If interrupted here

Fix round 1/5 committed on `phase-2/xcode-migration`, not yet merged. Two Minor findings
(`BLOCK_DIRECTIVES` unreferenced; `resolve`'s variable regex narrower than `bin/rave`'s)
were explicitly deferred to final review per the coordinator — do not fix until asked.
Next: await round 2/5 or final review outcome.

## 2026-08-12 — Phase 2 Task 3: header strategy decided by experiment

**What:** `ExportHeader` (369 edges, the largest Phase 2 risk) reproduced in Xcode via a
nesting-preserving symlink farm. Wrote `Xcode/Base.xcconfig` and
`docs/benchmarks/2026-08-12-header-strategy.md`.

**The finding that matters:** rave copies `Frameworks/<n>/src/x.h` to `_Include/<n>/<n>/x.h` and
grants `-I_Include/<dep>` **only for frameworks a target declares in `require`**. The double
nesting means a framework's headers are reachable only by targets that depend on it — the
`require` graph is compiler-enforced, not documentation. The obvious shortcut
(`-I$(SRCROOT)/Frameworks`) would compile and silently destroy that, with nothing failing to
warn us.

Verified both directions rather than assuming: with dependencies granted, compilation proceeds
past every cross-framework include; withholding one produces
`fatal error: 'regexp/find.h' file not found`. Chosen approach is 46 directory symlinks instead
of 369 file copies, with per-target include paths generated from each `require` list.

**Two plan assumptions the build contradicted:**

1. Plan said `c++23`; `build.ninja` compiles `-std=c++2a`. Raising the standard across ~92K
   lines is a behavioural change and gets its own commit with tests behind it, not a silent
   rider on a build migration. xcconfig uses `c++20`.
2. `build.ninja` still emits `-mmacosx-version-min=10.12`, inherited from upstream and untouched
   by the textmatelives merge — their macOS 26 governed release packaging, not the compile flag.
   Phase 2 is the first point the compiler is told the truth. Watch for `@available`-guarded
   code behaving differently once the deployment target really is 26.0; the test suite is the
   check.

**Why:** Every remaining Phase 2 task generates include paths, so getting this wrong would have
been invisible until the whole project was wired.

### If interrupted here

Tasks 1 and 3 done. Task 2 (ninja parity baseline) still outstanding — it is independent and was
skipped ahead of, not lost. Next: Task 2, then Task 4 (pilot framework under XcodeGen).


## 2026-08-12 — Phase 2 Task 1: `bin/rave2yaml --inventory` parses all 60 rave targets

**What:** Added `bin/rave2yaml`, a Ruby parser that walks `Frameworks/*/default.rave` +
`Applications/*/default.rave` (56 files) and `vendor/*/default.rave` (3 files, tagged
`vendor-target` and reported separately), and prints every target's kind, `sources`/
`tests` globs, `require` deps, frameworks, and libraries. Grammar was read out of
`bin/rave`'s `Parser` class, not guessed from samples. Finds **57** targets in
Frameworks/Applications (not 56 — `Frameworks/CommitWindow/default.rave` declares two:
`CommitWindow` and `CommitWindowTool`) plus 3 vendor targets. Full directive-grammar
table, per-target dependency list, and the `cxx_tests`-is-parsed-but-never-built finding
are in `docs/benchmarks/2026-08-12-rave-inventory.md`. Added `tests/rave2yaml_test.sh`
(passes: `PASS: 57 targets, all dependencies resolve`) — fixed its target-count heuristic
from file-based `grep -l` (undercounts CommitWindow's second target) to counting `target`
directive occurrences directly, and widened its dependency-resolution check to accept
`vendor-target` names too (`TextMate` requires `kvdb`, a vendor target). Both fixes are
justified in the doc, per task-1's decided point 4 (investigate before changing either).
Unrecognised directives are fatal (file:line:name) by design — verified against a scratch
`.rave` file, not the real tree. Task 1 report:
`.superpowers/sdd/2026-08-12-phase-2-xcode-migration/task-1-report.md`.

**Why:** Every later Phase 2 task consumes this inventory; a parser that silently drops a
target or misreads a dependency makes the generated Xcode project quietly wrong in ways
that surface later as link errors. `--inventory` only — `project.yml` emission is Task 4,
deliberately not touched here.

### If interrupted here

Task 1 committed on `phase-2/xcode-migration`. Not yet merged. Next: Phase 2 Task 2 per
`docs/superpowers/plans/2026-08-12-phase-2-xcode-migration.md`.

## 2026-08-12 — Phase 2 planned: Xcode migration via XcodeGen, not by porting PR #1469

**What:** Wrote `docs/superpowers/plans/2026-08-12-phase-2-xcode-migration.md` (8 tasks).

**Approach decided by measurement, not preference.** PR #1469's committed `project.pbxproj` is
6506 lines defining only **7 targets** at deployment target 10.11/12.4. It references the
`license` and `updater` frameworks textmatelives deleted (25 references), expects
`bl`/`CompareMate`/`QuickLookExtensions` we do not have, and omits `NewApplication` and
`QuickLookGenerator` we do. 50+ edits before it would parse, and all 46 frameworks still
unwired. Rejected.

Instead: generate the project with **XcodeGen** (2.46.0, already installed) from a checked-in
`project.yml`, itself derived from the `.rave` files by a converter we write. The `.rave`
directives are mechanically readable (`sources` globs, `require` dep lists, `tests` globs).
Both `project.yml` and the generated `.xcodeproj` get committed so contributors need only Xcode.

**The load-bearing risk is `ExportHeader`** — 369 edges, no native Xcode equivalent. rave
flattens every framework's public headers into one build-side include root, which is what makes
`#include <buffer/buffer.h>` resolve across 46 frameworks. Task 3 decides the replacement by
experiment (plain `-I` vs a symlink farm vs header maps) and records the evidence; every later
task depends on that answer.

Full rule inventory taken from the live `build.ninja` rather than guessed: CopyFile 1536,
CompileClang 736, ExportHeader 369, Link 84, GenTest/RunTest 54 each, CompileMarkdown 32,
Codesign 30, CompileXib 28, ExpandVariables 26, RunExecutable 18, RunApplication 12, PCH 8,
ConvertToUTF16 8, CompileRagel 2, CompileIcon 2. Ragel is two files, not a pervasive dependency.

**ninja stays authoritative until Task 7 proves parity.** Task 8 — deleting rave, switching CI,
stripping Intel — is the only irreversible task and is gated on that proof.

**Why:** Phase 2 unblocks Swift compilation, which Phase 6's SwiftUI islands and Liquid Glass
require; the rave build has no Swift support.

### If interrupted here

Plan committed on `phase-2/xcode-migration`. Phase 1 is merged to master (`ef1db3f2`); a working
build is installed at `/Applications/TextMate.app` as TextMate Revived 3.0.0-revived.1. Next:
Phase 2 Task 1 (`bin/rave2yaml` inventory pass).


## 2026-08-12 — Visible identity: "TextMate Revived 3.0.0-revived.1" shipped to /Applications

**What:** Pulled the *visible* half of Phase 4 forward so the installed build is identifiable
as ours. `CFBundleName` and `CFBundleDisplayName` are now "TextMate Revived"
(`Applications/TextMate/Info.plist:5-8`), and `CHANGELOG.md` gained a
`## 2026-08-12 (v3.0.0-revived.1)` entry, which is what the build parses `APP_VERSION` from.
Rebuilt and redeployed; About now reads TextMate Revived 3.0.0-revived.1.

**Deliberately NOT changed: `CFBundleIdentifier` stays `com.macromates.TextMate`.** Changing it
orphans existing preferences, bundles, and Application Support state. That needs the settings
migration Phase 4 owns, so the rename was split: cosmetic identity now, identifier plus
migration later. Splitting it this way is safe precisely because the identifier is what macOS
keys state on, not the display name.

**Spec correction:** the changelog pipeline is not what this repo documented before the merge.
textmatelives moved the version source from `Applications/TextMate/about/Changes.md` to the
repo-root `CHANGELOG.md` (`Applications/TextMate/default.rave:7-8`), parsed from the first
`## <date> (vX.Y.Z)` heading. The spec's "Changelog and About window" section is updated; the
rule is now one changelog, at the root, with a load-bearing heading format.

**Why:** The user could not tell our build apart from the textmatelives build it replaced —
both reported 2.1.4-undead.

### If interrupted here

`/Applications/TextMate.app` is TextMate Revived 3.0.0-revived.1, running, ad-hoc signed.
Committed on `phase-1/rebase-textmatelives`; PR #3 is open. Next: Phase 2 (Xcode migration).


## 2026-08-12 — Phase 1: merged textmatelives/main; first working build deployed

**What:** Merged `textmatelives/main` (130 commits) into a `phase-1/rebase-textmatelives`
branch off the freshly-merged Phase 0 master. Only **2 conflicts** across 300 changed files:

- `.gitignore` — kept our credential-coverage block, added their `.claude/` entry.
- `.github/workflows/build.yml` — they deleted it; accepted the deletion, since their
  `build-and-test.yml` / `ci.yml` / `release.yml` supersede it.

Their workflows arrived with **no repository guards** (`build-and-test.yml` 2 jobs,
`ci.yml`, `release.yml` — 0 guards between them). Added
`if: github.repository == 'sdenike/textmate'` to every job. An unguarded `release.yml`
on a fork is the worst case of the three.

Built and deployed. `bin/build` and `bin/deploy-local` added.

**Build blockers hit, both environmental rather than code:**

1. `configure`'s `/usr/local` hardcoding — **fixed by the merge**; textmatelives'
   `configure` now queries `brew --prefix`. This was Task 5's blocking finding, resolved
   for free exactly as Phase 1's issue predicted.
2. Leaked `GEM_HOME`/`GEM_PATH` from chruby made system Ruby 2.6 dlopen gems built for
   3.3.6: `Symbol not found: _rb_cArray (LoadError)`.
3. `~/Library/Caches/com.macromates.TextMate/githubcredits.db` was **root-owned** (Aug 11
   22:22), so `DBM.new` failed EACCES. Removable without sudo — unlink needs write on the
   directory, not the file. Second root-owned artifact from that date; something ran a
   build under sudo on Aug 11.

`bin/build` handles 2 and 3 automatically so nobody re-derives them.

**Result:** 340/340 targets, arm64-only, 27 MB, launches and is responsive.
Deployed to `/Applications/TextMate.app` via `bin/deploy-local`, which verified the
existing bundle's `CFBundleIdentifier` matched before replacing it.

**Known and expected:** the build is **ad-hoc signed**, not Developer ID / notarized —
this replaced a notarized textmatelives build with an unnotarized local one. Proper
signing is Phase 5. About still reads "TextMate 2.1.4-undead"; the rename is Phase 4.

**Why:** Phase 1's goal was a tree that builds and runs. It does.

### If interrupted here

Phase 1 merge is committed on `phase-1/rebase-textmatelives`, not yet pushed or PR'd.
A working build is installed at `/Applications/TextMate.app`. Next: push, open the PR
against master closing issue #1, then Phase 2 (Xcode migration).


## 2026-08-12 — Final whole-branch review fix wave (4 findings) complete

**What:** Fixed all four findings from Phase 0's final whole-branch review, in one commit. (1)
`.githooks/pre-commit`'s false-positive guidance pointed contributors at `.gitleaks.toml`, a file
that has never existed in this repo; rewrote it to name the actual mechanism, `.gitleaksignore`
(`commit:file:rule-id:start-line` fingerprints, added in `0090d044`), and to state why the
fingerprint scope is deliberate — the rest of the file stays live, so a real secret elsewhere still
trips. (2) `.github/dependabot.yml`'s comment claimed `actions/checkout@v4` is used "in every
workflow" (false: `build.yml:9` still pins `v2`, out of scope until Phase 2) and that boost, Cap'n
Proto, sparsehash, ragel, multimarkdown, and ninja "are being removed in Phase 3" (false: Cap'n
Proto already left in Phase 1 via the textmatelives merge, ninja leaves in Phase 2's Xcode
migration, and only boost/sparsehash/ragel/multimarkdown are actually Phase 3). Fixed both claims;
the actual ecosystem/directory/interval config is untouched, confirmed by parsing the YAML in a
scratch venv. (3) `docs/benchmarks/2026-08-12-baseline.md`'s "Targets these numbers set" section
still hedged rpath dylib count as a live Phase 7 metric "needing re-scoping" — stale since
`b1880890` already resolved Phase 7's gate to launch time/installed size/large-file open,
explicitly not dylib count. Replaced the hedge with that resolved gate; the measured numbers and
the "Measurement limits" section (where the rpath=0 finding itself lives) are untouched. (4)
`bin/bench/measure.sh`'s two `open -a "$APP"` calls each ran after only an
`osascript_bounded ... quit || true`, whose `|| true` could swallow a conflict that appeared after
the upfront `other_instance_pid` gate and fall through into `open -a` unguarded. Wrapped each call
in the same `other_instance_pid` if/else the upfront gate already uses, reusing its exact echo
message and `not measured (bundle id owned by another process)` assignments rather than inventing
a new pattern — built with a small Python script operating on exact original-file line indices so
the untouched `RSS_MB` Python-heredoc content couldn't be accidentally re-indented, then verified
with `bash -n` and a full `git diff` read-through.

**Why:** All four were documentation/tooling drift the whole-branch review caught: guidance
pointing at a file that doesn't exist, a comment asserting things checkably false against this same
branch's other files, a stale hedge contradicted by a later commit already on this branch, and a
benchmark harness with one residual unguarded window next to an otherwise-sound conflict check.
None touch application code — scope stayed inside hygiene/docs/harness per the review's
constraints — and no benchmark was re-run, so the recorded baseline numbers are unchanged.

### If interrupted here

Fix wave committed as a single commit on `phase-0/baseline-and-hygiene`, nothing left in progress.
Not pushed. Full detail in
`.superpowers/sdd/2026-08-12-phase-0-baseline-and-hygiene/final-fix-report.md`. Next:
`superpowers:finishing-a-development-branch` to integrate this branch into `master`, then Phase 1
(merge `textmatelives/main`, 130 commits) per `sdenike/textmate` issue #1.

---

## 2026-08-12 — Spec: changelog and About window pipeline

**What:** Added a "Changelog and About window" section to the design spec, per user request that
every build update the changelog and that it surface in About TextMate → Changes.

The pipeline already exists upstream and is reused, not rebuilt:
`Applications/TextMate/about/Changes.md` is read as `TEXTMATE_CHANGES`
(`Applications/TextMate/default.rave:7`), `APP_VERSION` is derived from it (`default.rave:20`),
and it renders in the About window's Changes pane. `bin/extract_changes` and
`bin/update_changes` are the existing helpers.

Decision: `about/Changes.md` is the **single source of truth**, and the repo-root `CHANGELOG.md`
is generated from it rather than hand-maintained in parallel. The build already derives
`APP_VERSION` from that file, so it cannot silently rot — breaking it breaks the build. Two
hand-maintained changelogs always diverge, and the one that rots would be the one users see in
About. GitHub release notes generate from the same entry, so the About pane, `CHANGELOG.md`, and
the Releases page cannot disagree.

Naming: the About window currently reads "TextMate version 2.1.4-undead" because the installed
build is textmatelives' fork. That string is `CFBundleName` plus the `Changes.md`-derived
version; Phase 4 changes both. Phase 5 makes "changelog updated" a hard release gate.

**Why:** The user will be testing builds and needs to see, in the app, what changed between them.

### If interrupted here

Phase 0 Tasks 1-6 are all complete, committed, and reviewed. Remaining: the final whole-branch
review, then `superpowers:finishing-a-development-branch` to integrate
`phase-0/baseline-and-hygiene` into `master`. After that, Phase 1 (merge `textmatelives/main`,
130 commits) — tracked at `sdenike/textmate` issue #1.

---

## 2026-08-12 — Task 6 (GitHub milestones, labels, Phase 1 issue) complete

**What:** Created all 11 Phase 0–9 milestones and all 6 custom labels
(`phase-0`, `security`, `build`, `ported`, `perf`, `ui`) on `sdenike/textmate`
per the Task 6 brief, then opened the Phase 1 tracking issue
(`https://github.com/sdenike/textmate/issues/1`, milestone "Phase 1 —
Rebase onto textmatelives", labels `ported`+`build`). Found the repo had
Issues disabled (`has_issues: false`) — undocumented in the brief or the
task's "existing state" notes — and enabled it via `gh api -X PATCH
.../repos/sdenike/textmate -f has_issues=true` since opening the tracking
issue was an explicit, unambiguous task requirement and the whole
milestone/label scaffold exists to support issues. Posted the issue body
with the CORRECTED Phase 1 gate per this task's course-correction:
"textmatelives' test suites pass on our merged tree" (not the inherited
CxxTest suites, which Task 5 proved cannot run — 614/853 targets blocked
by the `/usr/local` vs `/opt/homebrew` `configure` bug), referencing both
`docs/benchmarks/2026-08-12-build-attempt.md` and
`docs/benchmarks/2026-08-12-baseline.md`, noting upstream PR #1457 and
textmatelives' `fix/configure-homebrew-prefix` branch as an unverified
possible fix, keeping the GPLv3 attribution requirement, and stating the
130-commit divergence explicitly.

**Why:** Phase 0's exit criteria require the 11 milestones, 6 labels, and
open Phase 1 issue to exist before Phase 1 can begin, and the brief's
original Phase 1 gate ("tests green") was rendered false by Task 5's
finding that the inherited tree doesn't build — posting the stale gate
would have pointed Phase 1 at a test oracle that cannot run.

### If interrupted here

Task 6 fully complete: 11/11 milestones, 15/15 labels (9 default + 6 new),
issue #1 open with correct milestone/labels/body, all verified via `gh
api`/`gh issue view`. No repository files were created by this task other
than this STREAM.md entry — the only change to commit. Full detail in
`.superpowers/sdd/2026-08-12-phase-0-baseline-and-hygiene/task-6-report.md`.
Note: `docs/superpowers/specs/2026-08-12-textmate-revived-design.md` has an
unrelated uncommitted modification (27 insertions) present before this task
started — not touched here, left for whichever task owns it.

---

## 2026-08-12 — Task 4 fix round 1/5 (bundle ID isolation) complete

**What:** Fixed an Important review finding in `bin/bench/measure.sh`:
`official`, `undead`, and any real TextMate a developer has installed all
share the identical `CFBundleIdentifier` `com.macromates.TextMate`, but
every Apple Event the harness sends was addressed `tell application id
"$BUNDLE_ID"` — which macOS resolves to whichever process currently owns
that id system-wide, not necessarily the instance this script just
launched at `$APP`. Added `other_instance_pid()`, which finds any process
with the same executable name whose full command line does not start with
`"$APP"/`, and wired it in at two points: an upfront gate right after
`BUNDLE_ID` is computed (skips the entire launch/RSS section — reporting
`not measured (bundle id owned by another process)` — before even calling
`open -a`, since `open -a` itself could activate the wrong instance), and
inside `osascript_bounded` itself, the one chokepoint all five flagged
call sites already run through, as defense-in-depth against a conflicting
instance appearing mid-run. Verified with an isolated test against the
function extracted from the committed file — nothing running (no
conflict), the script's own launch queried against its own path (no
conflict), and the same running process queried against a *different*
build's path (conflict correctly detected) — using only scratch-directory
builds, never `/Applications`, and without re-running the full benchmark
or producing new baseline numbers, per instruction. Also added three
disclosure-only bullets to `docs/benchmarks/2026-08-12-baseline.md`'s
"Measurement limits" section for two deferred Minor findings
(`hdiutil attach` has no timeout; the warm-up launch's readiness loop has
no failure branch and can silently make the "second launch onward" claim
false for a row) plus the shared-bundle-id constraint itself.

**Why:** an id-addressed quit landing on a user's real, open TextMate
session would destroy their working state, and a readiness poll answering
off the wrong process would corrupt the very numbers Phase 3 and Phase 7
are judged against — silently, with no error, producing a plausible-looking
but meaningless numbers. This machine has exactly that real
`/Applications/TextMate.app` installed at the same bundle id, so the risk
was not theoretical. Fixed the shared chokepoint rather than each of the
five flagged call sites individually so no future call site can bypass the
guard by omission.

### If interrupted here

Fix round 1/5 committed, nothing left in progress. The recorded baseline
table in `docs/benchmarks/2026-08-12-baseline.md` is unchanged from the
prior round — this round touched the harness and the limits section only,
per instruction not to re-run benchmarks. `.superpowers/sdd/.../task-4-report.md`
has a "Fix round 1/5" section appended with full reasoning. If further
review rounds land (2/5 through 5/5 per the coordinator's message), resume
from there; no known issues remain open in this round.

---

## 2026-08-12 — Task 5 (2021-tree build attempt) complete: does not build, Phase 1 is the oracle

**What:** Attempted the inherited 2021 tree on today's toolchain (macOS 26.6.1, Xcode 26.6,
Apple clang 21.0.0/clang-2100.1.1.101) per the Phase 0 plan. `git submodule update --init
--recursive` succeeded cleanly. `./configure` on a truly clean checkout **fails** (exit 1):
`dependency missing: '/usr/local/include/boost/crc.hpp'`. Root cause: `configure` hardcodes
`/usr/local/{include,lib}` as the only search location for boost/capnp/sparsehash; Homebrew
on Apple Silicon installs to `/opt/homebrew`. All six declared dependencies are genuinely
installed (boost 1.90.0_1, capnp 1.5.0, google-sparsehash 2.0.4, multimarkdown 6.8.0, ninja
1.13.2, ragel 6.11) — `configure` just never looks where Homebrew actually put them. Found a
second bug while reproducing this: `configure` writes part of `local.rave` *before*
validating headers exist, so a failed run still leaves the file behind, and an unmodified
retry silently skips validation and reports success without ever confirming the dependency
paths are real — a false green light, reproduced twice with no hand edits.

Proceeding to `ninja TextMate` against that state: first attempt hit `error: unable to open
output file ...: 'Operation not permitted'` against the default build directory
(`~/build/textmate/release`), which turned out to contain a `root`-owned subtree timestamped
the day before this session — unrelated prior activity on this machine, not a toolchain
finding. Worked around by pointing `bin/rave` at a clean directory via `configure`'s own
pre-existing `$builddir` mechanism (no file edited, no flag added). Against a clean build
dir: ninja dispatched 239/853 targets before stopping (default `-k1`), 3 steps failed, 3
genuinely distinct errors surfaced (documented in full in
`docs/benchmarks/2026-08-12-build-attempt.md`): the `/usr/local` vs `/opt/homebrew` boost
miss confirmed at actual compile time (`Shared/PCH/prelude.cc:24: fatal error: 'boost/crc.hpp'
file not found`, blocking the shared PCH nearly everything else transitively depends on —
which is why only 239/853 targets were even attempted), and an unrelated Ruby `LoadError`
generating `Contributions.html` (system Ruby 2.6 loading a gem built for a different,
`chruby`-managed Ruby 3.3.6). Did not reach 5 distinct errors because the PCH miss blocks
almost everything downstream — no path to more without patching `local.rave`'s include
paths, which is out of scope. Both attempts finished in ~2 seconds, nowhere near the
20-minute time-box. No test suite was run; the build never succeeded.

**Why:** Task 5 exists to answer, honestly, whether Phase 0 hands later phases a working
regression oracle. It does not: the 86 inherited CxxTest suites cannot run until the tree
builds, and it doesn't. Per the plan's pre-agreed fallback, Phase 1's gate becomes
"textmatelives' suites pass on our merged tree" — their CI builds and they ship releases, so
their tree is the only one that currently produces a green oracle. A failed build here was
the expected, correctly time-boxed outcome, not a task failure; the value was in getting the
*real* errors (a stale Apple-Silicon path assumption, confirmed at compile time, not left as
an unverified pre-flight check) rather than a misleading filesystem-permission artifact from
unrelated prior activity on this machine.

### If interrupted here

Task 5 committed, nothing left in progress. `local.rave` and `build.ninja` exist in the
working tree as generated artifacts (both gitignored, neither staged/committed, confirmed via
`git status --porcelain`). Next: Task 6 (GitHub milestones, labels, Phase 1 issue) per
`docs/superpowers/plans/2026-08-12-phase-0-baseline-and-hygiene.md` — Phase 1's issue should
cite this task's finding directly: its gate is "textmatelives' suites pass on our merged
tree," not "the inherited CxxTest suites still pass," since the latter can't be evaluated
until the tree builds at all.

---

## 2026-08-12 — Spec corrected: Phase 7 premise disproved, plan bugs fixed

**What:** Two rounds of spec/plan corrections, covering commit `8ab88020` (which landed without
a STREAM entry — that omission is what this entry settles) and the follow-up spec edits.

Plan bugs, both found by implementers who stopped rather than improvised:
- The Task 3 merge-base check used `git merge-base --is-ancestor HEAD textmatelives/main`, which
  can never pass once our branch has local commits of its own. Corrected to the symmetric
  `git merge-base HEAD <ref>` for all three forks.
- Task 2's guard-placement wording was self-contradictory ("first key of the job block,
  immediately after `runs-on`"). Corrected to "immediately before `runs-on`", matching
  `.github/workflows/gitleaks.yml`.

Measurement corrections:
- True fork divergence is textmatelives **130**, gs1469 **74**, tectiv3 **231** — not the
  ~130/77/100 from recon. The tectiv3 figure was wrong because it came from
  `gh pr view --json commits`, and GitHub's API caps the commit list it returns for a PR.
  **PR #1467 is the largest of the three forks, not the middle one.** Trust
  `git rev-list --count` over PR metadata for anything sizing-related.
- **Phase 7's headline premise was false.** The spec claimed dyld-loading 45 framework bundles
  was a launch cost we would remove, and called it "the single largest expected startup win."
  Phase 0's baseline measured `otool -L` on both shipped builds: zero rpath dylibs, and neither
  `.app` contains a `Contents/Frameworks/` at all. The ~45 source-tree modules are already
  statically linked. That win was banked years ago. The architecture section and Phase 7 are
  both rewritten, and Phase 7's gate no longer uses dylib count as a metric.

Also added: a "Local deployment" spec section. `bin/deploy-local` installs to `/Applications`
replacing the prior build, but must read `CFBundleIdentifier` and refuse to delete a bundle that
is not ours. This is load-bearing, not theoretical — `/Applications/TextMate.app` on this machine
is `com.macromates.TextMate` v2.1.4-undead, a working install predating this session. A
path-based overwrite would destroy it.

**Why:** Phase 0 exists to disprove false premises before later phases are built on them. It
earned its keep here: Phase 7 would have been scoped around a win that does not exist.

### If interrupted here

Spec and plan are current. Phase 0 Tasks 1-4 complete and committed. Next: Task 5 (attempt the
2021-tree build on Xcode 26.6 and record which phase first provides a green test oracle), then
Task 6 (GitHub milestones, labels, Phase 1 issue).

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
