# STREAM

Running work log, newest first. Timestamp · what · why · if-interrupted-here.

---

## 2026-08-21 — RESUME HERE: Software Update pane ported; a crash caught by the whole-branch review

Branch `phase-6/swiftui-preferences`, 13 commits, **unpushed and unmerged**. Build green, 4 tests
passing and now actually running in CI. All four plan tasks complete, each reviewed, plus a final
whole-branch pass and its fix wave (`4c1ea1ab`).

### The finding that justified the whole-branch review

Eight task-level reviews passed. The final pass found that the app **SIGTRAPs on every automatic
update check while the pane is open** — the default configuration.

`SoftwareUpdate.mm:313`'s `NSBackgroundActivityScheduler` block runs off-main, synchronously reaches
`:368 self.checking = YES`, fires KVO into the pane, and calls a `@MainActor` Swift method. Under
Swift 6 on macOS 26 the `@objc` thunk traps before its body runs. Both ends were measured, not
argued: the scheduler block reports `isMainThread = 0`, and an off-main `@MainActor` thunk exits 133.

**The old AppKit pane had the same off-main KVO**, feeding a Cocoa binding that misbehaved quietly.
Swift 6's isolation checking converts that latent thread bug into a hard crash. The port did not
introduce the defect; it made it impossible to ignore.

`Ruling: this ledger recorded @MainActor soundness as "verified against SoftwareUpdate.mm:326,344,368,417"
after Task 3. That was WRONG and I passed it on as settled. All four of those sites are main-dispatched
or on the button path — but :368 has a second caller at :313 that is not. Checking the call sites you
are handed is not the same as checking all callers.`

### Also fixed: the branch's own tests never ran

`Preferences_test` was absent from the hand-maintained `TESTS` list in
`.github/workflows/build-and-test.yml`, whose own comment says new targets must be added by hand.
The plan created the target and never wired it, so four passing tests guarded nothing.

### What shipped

The AppKit pane is gone. `SoftwareUpdatePreferences.loadView` now installs an `NSHostingView`; the
shell — window, toolbar, pane switching, persistence — is untouched. Behavioural parity with the
deleted pane was verified against git history: the negated `SoftwareUpdateDisablePolling` checkbox,
both separate disabled-bindings, Check-Now-while-checking, and all four "Last check" states.
`fittingSize` measured 490×252 and stable across every change, against controls (`EmptyView` 10×10,
empty `Form` 40×40).

### If interrupted here

Branch is complete and unmerged; it needs the maintainer's manual QA, none of which has been done.
The highest-value check is the defaults diff — `SoftwareUpdateDisablePolling` is stored **inverted**,
and a lost negation would silently disable updates for everyone while the checkbox still looked
right. Five panes remain (Projects, Variables, Files, Terminal, Bundles); the spec holds the order
and the reasoning.

---

## 2026-08-21 — Final fix wave: the pane's own KVO could kill the app on the hourly update check

Whole-branch review found one crash and one gap; both fixed here along with three smaller items, in
one commit.

**The crash.** `SoftwareUpdatePreferences.mm`'s `-pushUpdateStatus` called
`-updateWithLastCheckDescription:isChecking:`, which is `@MainActor` on the Swift side, from a chain
that is fully synchronous and starts off-main: `SoftwareUpdate.mm`'s `NSBackgroundActivityScheduler`
block runs on an XPC activity queue, calls `-checkForTestBuild:`, whose `self.checking = YES` fires
KVO straight into `-observeValueForKeyPath:`. With automatic checks on -- the default -- opening
Settings on this pane and waiting for the hourly check would take the app down. Reproduced the
mechanism standalone before touching anything: an `@objc @MainActor` method compiled at
`-swift-version 6` for `arm64-apple-macos26.0`, invoked through its ObjC thunk from a background
queue, exits **133 (SIGTRAP) with the body never running**; the same binary with a conditional
main-queue hop runs the body on the main thread and exits 0.

`-pushUpdateStatus` now reads the two values on the calling thread and **hops only when not already
on main**, rather than dispatching unconditionally. That is a correctness requirement, not a latency
preference: `-loadView` seeds the status synchronously and `SettingsPaneFactory` measures
`fittingSize` off the view it builds immediately after, so an unconditional `dispatch_async` would
defer the seed past the measurement and size the "Last check" row for empty text -- precisely what
seeding-before-the-factory exists to prevent. The Swift side's isolation was left alone;
`SettingsPaneUpdateStatus` drives SwiftUI and belongs on the main actor. Its comment claiming the
KVO chain is always main-thread was the false premise behind the bug and has been corrected in
place. **This is a pre-existing threading defect, not one the port introduced** -- the AppKit pane
fed the same off-main KVO into a Cocoa binding, which misbehaved quietly instead of trapping. The
port converted silent misbehaviour into a hard crash.

**The gap.** `.github/workflows/build-and-test.yml` carries a hand-maintained `TESTS` list and
`Preferences_test` was not in it, so this branch's four tests guarded nothing (`release.yml` gates
on the same job). Added, alphabetically between `plist_test` and `regexp_test`, and deliberately
**not** added to the `--no-parallel` case beside it: those eight are frameworks whose runners call
Cocoa APIs asserting `NSThread.isMainThread`, and this suite exercises only
`TMSettingsLastCheckDescription`, a pure C function over `BOOL` and `NSString*`. Confirmed by
running the binary bare five times plus once with `-v`: 4/4 every time.

Three smaller items. `#import "Keys.h"` is gone from `SoftwareUpdatePreferences.mm` -- every key the
file uses is declared in `SoftwareUpdate/SoftwareUpdate.h`, and `Keys.h` declares none of them.
`import SwiftUI` moved from mid-file to the top of `SettingsSupport.swift`. And the pane's
`-removeObserver:forKeyPath:` is now flag-guarded on both sides: unlike the notification-centre
`-removeObserver:` next to it, an unbalanced call throws, and the pair is balanced today only
because `OakTransitionViewController` happens to drop the old subview on animation completion.

`fittingSize` re-measured with the same standalone harness: **490x252, unchanged**. `bin/build` and
`bin/build Preferences/test` both succeed, no new diagnostics on either changed source.

**If interrupted here:** the branch is complete and green. Nothing is half-done. The one thing not
covered by a test is the crash fix itself -- it was verified by standalone repro and by inspection,
not by a test in this tree, because reproducing it needs a live `NSBackgroundActivityScheduler`.

---

## 2026-08-21 — Task 4 done: the shared pane style, extracted rather than designed ahead

Executed `.superpowers/sdd/2026-08-21-settings-softwareupdate-pane/task-4-brief.md` verbatim. Added
`Frameworks/Preferences/src/SettingsFormStyle.swift`, a `public struct SettingsPane<Content: View>:
View` that wraps `content` in `Form { … }.formStyle(.grouped).scrollDisabled(true)` -- transcribed
from the brief exactly, including its `.scrollDisabled(true)`, which is load-bearing rather than
cosmetic: the shell sizes each pane from `fittingSize` (`PreferencesPane.mm:36`, then
`OakTransitionViewController`), and a pane that scrolls internally would report a small fitting size
and clip, the same failure mode `CLAUDE.md` records for the Terminal pane. `public`, not merely
`@objc`, because `SettingsPane` is generic (`@objc` cannot express a generic type at all) and is
consumed only from Swift -- `SoftwareUpdatePaneView`, same module -- so ObjC visibility was never in
play; the constraint that forces `public` elsewhere in this file (`SettingsPaneFactory`,
`SettingsPaneUpdateStatus`) is about crossing to Objective-C++, and this type never does.

`SoftwareUpdatePaneView.body` in `SettingsSupport.swift` now wraps its two `Section`s in
`SettingsPane { … }` instead of `Form { … }.formStyle(.grouped)` directly -- the only change to that
file. Added the new file to `Preferences`'s `sources:` in `project.yml` (alphabetically before
`SettingsSupport.swift`) and ran `xcodegen generate --spec project.yml`; the resulting
`TextMate.xcodeproj` diff is exactly the new file's two entries plus the documented order-only swap
of two `PBXCopyFilesBuildPhase` "Embed Dependencies" objects, nothing else.

**Measured `fittingSize` before and after, not just after.** Rebuilt the same kind of throwaway
harness Task 3 used (a stub `.m` defining the bridging header's extern constants, linked against the
real, unmodified `SettingsSupport.swift` compiled standalone via `swiftc`) to get a real "before"
number rather than trusting the figure recorded in the brief: 490x252, matching Task 3's own
measurement and its control baselines (10x10 `EmptyView`, 40x40 empty grouped `Form`). Recompiled the
same harness against the edited `SettingsSupport.swift` plus the new `SettingsFormStyle.swift` --
**after is also 490x252, unchanged**. `.scrollDisabled(true)` did not move it because the pane's two
`Section`s already fit inside 252pt without scrolling; the modifier is there for later, taller panes,
per the brief's own note, not because this one needed it.

`bin/build` -> `** BUILD SUCCEEDED **`; touched both changed files and grepped the full log for their
names next to "warning" -- none. `bin/build Preferences/test` -> `** BUILD SUCCEEDED **`;
`Preferences_test -v --no-parallel` -> `4 tests passed`.

### If interrupted here

Task 4 is committed -- this was the last task in
`docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md`. Every later pane in
`docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`'s ordering should now wrap its
content in `SettingsPane { … }` rather than reaching for `Form` directly.

---

## 2026-08-21 — Task 3 fix round 1/5: "Last check" and "Check Now" go live

Coordinator finding: Task 3 shipped with `lastCheckDescription: ""` and `isChecking: false`
hardcoded into `SettingsPaneFactory.softwareUpdateView`, so the pane's "Last check" field was
permanently blank and "Check Now" never greyed out while a check ran -- a real regression against
the AppKit pane it replaced, not the deferred nicety the brief's Step 2/3 split implied. Flagged in
the Task 3 report rather than invented at the time, since the brief's own factory signature took
only `checkNow:`; this round supplies the wiring the brief promised ("Step 3") but never wrote.

Added `SettingsPaneUpdateStatus` to `SettingsSupport.swift` -- an `@objc(SettingsPaneUpdateStatus)
@MainActor public final class … : NSObject, ObservableObject` with `@Published` `lastCheckDescription`/
`isChecking` and one bridge method, `update(lastCheckDescription:isChecking:)`. The factory now
takes it as a second parameter and `SoftwareUpdatePaneView` observes it (`@ObservedObject`)
instead of taking plain values. `SoftwareUpdatePreferences.mm` creates one in `loadView`, seeds it
synchronously before calling the factory (so `fittingSize` measures real text, not `""`), and pushes
into it from a single KVO observation of **its own** `lastCheckDescription` -- reusing
`+keyPathsForValuesAffectingLastCheckDescription`, already declared over
`softwareUpdateController.checking`, `.errorString` and `relativeStringForLastCheck`, so one
`addObserver:forKeyPath:@"lastCheckDescription"` (registered in `viewWillAppear`, removed in
`viewDidDisappear`, matching the existing timer/notification lifecycle in the same two methods)
catches all three without three separate observers. `NSKeyValueObservingOptionInitial` re-syncs on
every appear, covering a check that ran while the pane was hidden and thus unobserved.

Confirmed the KVO source is always main-thread before relying on `@MainActor` for the pushed-into
object: `SoftwareUpdate.mm`'s `self.checking = YES` runs synchronously on the thread that called
`checkForUpdate:` (the SwiftUI button action, main thread); the async completion's `self.checking =
NO` and `self.errorString = …` are both inside `dispatch_async(dispatch_get_main_queue(), …)`. No
loosened isolation needed.

Re-measured `fittingSize` the same way as Task 3 (standalone harness compiling the real
`SettingsSupport.swift` against a stub defining the bridging header's extern constants, since
linking the real `Preferences.a` standalone remains impractical) -- **unchanged at 490x252**, both
for `"Never"`/not-checking and for a longer string (`"5 minutes ago"`) with `isChecking: true`, so
neither real last-check text nor the checking state grows the pane.

`bin/build` -> `** BUILD SUCCEEDED **`, no warnings from either changed file (checked by touching
both and grepping the full log). `bin/build Preferences/test` -> `** BUILD SUCCEEDED **`,
`Preferences_test -v` -> `4 tests passed`. `SoftwareUpdate.mm` untouched this round -- the nightly
channel change from Task 3 stands as committed.

### If interrupted here

This fix round is committed. Round 1/5 per the coordinator's numbering; no further findings
outstanding as of this entry. Next is whatever the coordinator's round 2 raises, or if none, the
next pane in `docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`'s ordering.

---

## 2026-08-21 — Task 3 done: the Software Update pane in SwiftUI, first pane ported

Executed `.superpowers/sdd/2026-08-21-settings-softwareupdate-pane/task-3-brief.md`. Appended
`SoftwareUpdateModel`, `SoftwareUpdatePaneView` and `@objc public final class SettingsPaneFactory`
to `Frameworks/Preferences/src/SettingsSupport.swift`, then rewrote
`SoftwareUpdatePreferences.mm`'s `loadView` to install `[SettingsPaneFactory
softwareUpdateViewWithCheckNow:]`'s `NSHostingView` instead of building an `NSGridView`. The watch
checkbox stays inverted (`pollingDisabled` backs `watchForUpdates` negated) and the channel now
persists through `SettingsChannel` rather than a runtime-registered `NSSelectedTagBinding`
transformer -- `OakSoftwareUpdateChannelTransformer`'s registration in `init` came out too, since
`loadView`'s rewrite deleted its only binding and it would otherwise sit there naming a stale
2-of-3 channel list.

Deleted the pre-10.15 branch of `relativeStringForDate:` and the `@available(macos 11.0, *)` icon
guard, both dead at a macOS 26 deployment target. `-lastCheckDescription` now calls
`TMSettingsLastCheckDescription`, so Task 2's tested function has a real caller -- though nothing
in the new pane displays its result yet: per the brief, `SettingsPaneFactory`'s factory takes only
`checkNow:` and hardcodes `lastCheckDescription: ""`/`isChecking: false` into the view. The "Last
check" field will render blank and "Check Now" won't visibly grey out while checking until a later
task threads live values through; flagging this rather than silently wiring it myself, since the
brief's own interface line pins the factory to `checkNow:` only.

**Measured `fittingSize` rather than trusting it.** Linking the real `Preferences` static lib
standalone was impractical (it pulls the whole app's transitive dependency graph through the other
panes in the same target), so verification compiled the actual, unmodified `SettingsSupport.swift`
in a throwaway harness against a stub `.m` defining the same extern constants, called
`SettingsPaneFactory.softwareUpdateView`, and printed `.fittingSize`. Got 490x252, against control
baselines of 10x10 for a bare `EmptyView` and 40x40 for an empty grouped `Form` -- confirms the
number reflects real content, not a default. This is the failure mode `CLAUDE.md` records for the
Terminal pane; it did not reproduce here.

`Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm:392`'s `includePrereleases` now triggers for any
non-release channel rather than prerelease only, so Nightly actually differs from Normal releases
in the picker. Also moves test builds (forced onto canary at `:359`) from stable-only to including
prereleases -- a recorded consequence, not a surprise.

`bin/build` -> `** BUILD SUCCEEDED **`; no warnings from either changed file (checked by touching
them and grepping the full log). `bin/build Preferences/test` -> `** BUILD SUCCEEDED **`,
`Preferences_test -v` -> `4 tests passed`. The extern link check the brief warned about (this task
is the first to force `Preferences-Bridging-Header.h`'s symbols to link) surfaced nothing -- clean
link both times.

### If interrupted here

Task 3 is committed. Everything the maintainer needs to check interactively is Step 6 of
`docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md` -- rendering, the disabled
states, the defaults diff (checkbox negation is the likeliest thing to have inverted silently),
channel storage values, and Nightly's "Check Now". Next pane in the series picks up wherever
`docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`'s ordering says to go after
Software Update.

---

## 2026-08-21 — Task 2 done: `Preferences_test`, the framework's first test target

Executed `.superpowers/sdd/2026-08-21-settings-softwareupdate-pane/task-2-brief.md` verbatim.
`Frameworks/Preferences` had no test target, no `tests/` directory, and nothing anywhere
exercising it -- confirmed before writing anything. TDD order: wrote
`Frameworks/Preferences/tests/t_settings_support.mm` first, ran `bin/build Preferences/test`, and
got the expected first failure (`xcodebuild: error: The project 'TextMate.xcodeproj' does not
contain a target named 'Preferences_test'.`) before the target existed. Then added
`Frameworks/Preferences/src/SettingsSupportBridge.{h,mm}` -- `TMSettingsLastCheckDescription`,
pulled out of `SoftwareUpdatePreferences.mm:37`'s precedence (checking beats an error, an error
beats a date, "Never" is the floor) so it can be tested as a free function, since `bin/gen_test`
wraps every test file in a namespace and Objective-C forbids declaring a class inside one.

Wired `project.yml`: a `PreferencesSupport` static library (just the one new `.mm`, none of
`Preferences`'s AppKit/`settings_t`/BundlesManager baggage) and a `Preferences_test` tool target
linking only that. The `Preferences` target had **no `dependencies:` key at all** before this --
it resolved everything through `HEADER_SEARCH_PATHS` -- so the brief's instruction to add
`PreferencesSupport` there meant adding the key itself, not appending to a list. Confirmed by
reading the target block first. Ran `xcodegen generate --spec project.yml`; the diff is purely
additive (225 lines, 0 deletions in `project.pbxproj`) -- the "Embed Dependencies" phase-order
swap noted as expected elsewhere didn't happen this time.

`bin/build Preferences/test` -> `** BUILD SUCCEEDED **`; running the binary directly (as the brief
directs, since the wrapper's `exec`'d output isn't visible through this session's non-tty capture)
gives `Preferences_test: 4 tests passed`, exit 0. Full `bin/build` (whole app) also still succeeds
with `PreferencesSupport` linked in.

### If interrupted here

Task 2 is committed. Start Task 3 next, per
`docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md` -- it rewires
`SoftwareUpdatePreferences.mm`'s `-lastCheckDescription` to call `TMSettingsLastCheckDescription`
so the tested function is the one that actually runs, and consumes Task 1's `SettingsChannel`.
Neither happens yet: this task only extracted and tested the logic, per its own scope.

---

## 2026-08-21 — Task 1 done: Swift compiles in the Preferences static library

Executed `.superpowers/sdd/2026-08-21-settings-softwareupdate-pane/task-1-brief.md` verbatim. Added
`Frameworks/Preferences/src/Preferences-Bridging-Header.h` (re-declares the four defaults keys and
three channel constants defined in `SoftwareUpdate.mm:12-19`) and
`Frameworks/Preferences/src/SettingsSupport.swift` (`SettingsChannel`, a public enum for the three
channels, Nightly included per the ruling below). Wired `project.yml`'s `Preferences` target: the
`.swift` file went into `sources:`, and `SWIFT_OBJC_BRIDGING_HEADER` went into `settings.base` right
after `GCC_PREFIX_HEADER`. No `dependencies:` key was added -- the target still resolves everything
through `HEADER_SEARCH_PATHS`, unchanged.

**Proves what it needed to prove.** No framework target in this repo had ever contained Swift before
this. `bin/build` succeeded, and forcing a rebuild of just the `Preferences` target shows
`SwiftCompile ... SettingsSupport.swift ... (in target 'Preferences' ...)` in the log, so the file is
confirmed compiled, not just silently absent from `sources` behind a green build. The module landed
at `~/build/textmate-revived/xcode/Release/Preferences.swiftmodule/` (also present, redundantly,
under `obj/TextMate.build/Release/Preferences.build/Objects-normal/arm64/`) -- later tasks building
on this target should expect that path.

**Extern-linking not yet exercised.** Nothing in Task 1 calls `SettingsChannel.storedValue` or
`.title` from outside the enum itself, so a misspelled extern in the bridging header would not yet
surface as a link error -- nothing forces the linker to resolve those symbols yet. That check only
becomes real once a later task references `SettingsChannel` from outside this file.

### If interrupted here

Task 1 is committed. Start Task 2 next, per
`docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md`. Task 1's build is proven above;
no need to re-verify unless `project.yml` or the two new files under `Frameworks/Preferences/src`
change again.

---

## 2026-08-21 — RESUME HERE: Nightly IS offered; the entry below this one is superseded

**Reverses the ruling in the previous entry.** That entry says nightly stays out of the picker. It
does not. The maintainer was shown the evidence, reaffirmed the instruction, and Nightly is offered.
Read this entry, not that one, on the channel question.

### What was added, and why it is more than a picker entry

Adding "Nightly builds" alone would have shipped a control that lies.
`Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm:392` sets `includePrereleases` only for the
prerelease channel, so an untouched `nightly` resolves to exactly the same updates as `release`. The
plan therefore also changes that line to `![updateChannel isEqualToString:kSoftwareUpdateChannelRelease]`
— any channel other than stable opts into prerelease tags.

`Ruling: implement the maintainer's instruction fully rather than partially. A picker entry whose
label says "Nightly builds" and whose behaviour is "Normal releases" is worse than not offering it,
and worse than the extra line of change. Cost if wrong: nightly and prerelease behave identically,
which is already true and now documented.`

### Two consequences recorded so they are not discovered later

- **Nightly and Prereleases deliver identical updates today.** The feed is git tags
  (`AppController.mm:507`) with two tiers, stable and prerelease. There is nothing more bleeding-edge
  to fetch. The entry is forward-looking and becomes distinct only if a nightly tag stream starts.
- **Test builds change behaviour.** `SoftwareUpdate.mm:359` forces canary when `testBuild` is set,
  so those builds move from stable-only to including prereleases. Almost certainly what a test build
  wanted, but it is a real change, not a no-op.

### If interrupted here

Plan at `docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md`, four tasks, **no
implementation yet**. Branch `phase-6/swiftui-preferences`, unpushed. Start at Task 1; do not
re-plan. Execution mode was not chosen. The risk Task 3 exists to catch: `PreferencesPane.mm:36`
sizes a pane from `fittingSize` and `OakTransitionViewController` pins to it — a `0×0` there is what
made the Terminal pane look like a dead click for months.

---

## 2026-08-21 — RESUME HERE: SoftwareUpdate pane plan written, ready to execute

Plan at `docs/superpowers/plans/2026-08-21-settings-softwareupdate-pane.md` — four tasks. Branch
`phase-6/swiftui-preferences`, unpushed, **no implementation yet**.

### Reading the source changed two decisions

The maintainer's instruction was to read rather than guess, and doing so overturned things a survey
summary had settled.

**The pane is not three controls.** It is five, with cascading enablement — the channel picker and
the ask-before-downloading checkbox are *both* disabled when updates are off, via two separate
`NSEnabledBinding`s — plus a computed `lastCheckDescription` combining checking, error and date
states, and about forty lines of pre-10.15 date formatting behind a `#if` that cannot run on a
macOS 26 deployment target.

**And Nightly should not be added to the picker, though it had already been asked for.**
`SoftwareUpdate.mm:392` sets `includePrereleases` only for the prerelease channel, so `nightly`
delivers exactly what `release` does. The feed is git tags (`AppController.mm:507`) and has no third
tier to expose. It survives only because `SoftwareUpdate.mm:359` forces it for test builds.

`Ruling: nightly stays out of the picker, reversing the maintainer's earlier instruction after
showing them the evidence. Adding it would ship a control labelled "Nightly builds" that silently
means "Normal releases". Cost if wrong: a channel that power users cannot select from the UI,
though they can still set it with `defaults write`.`

### The mechanism that removes a failure class

The bridging shim **re-declares** the extern keys rather than retyping their values. A re-declared
extern shares the symbol — the definitions stay in `SoftwareUpdate.mm` — so a misspelled name is a
link error, not a key that compiles, links and silently reads nothing. That is precisely what the
`didPromptForDefaultBundles` casing bug was earlier in this work.

### Three errors caught in the plan's own self-review

A type promised in an Interfaces block that no task defined (`SettingsPaneHost`); a step that said
"replace `loadView`" without showing the code, at exactly the Swift/ObjC++ seam where this repo's
constraints bite hardest; and a wrong Files list. All fixed before the plan was committed.

### If interrupted here

Read the plan and start at Task 1. Do not re-plan. The risk it exists to catch: `PreferencesPane.mm:36`
sizes a pane from `fittingSize` and `OakTransitionViewController` pins to it — a `0×0` there is what
made the Terminal pane look like a dead click for months. Execution mode not chosen yet.

---

## 2026-08-20 — RESUME HERE: Settings plan blocked on a product decision, not on code

The Settings panes spec is written and has now been corrected twice — once at self-review, once
while planning. **No implementation plan exists**, and writing it is blocked on one question only
the maintainer can answer.

### The blocker: a third update channel the popup cannot represent

`SoftwareUpdate.mm:17-19` defines three channels — `release`, `beta`, `nightly`. The pane's popup is
backed by an `OakStringListTransformer` registered over only the first two
(`SoftwareUpdatePreferences.mm:27`), so a user whose `SoftwareUpdateChannel` is `nightly` opens the
pane to a tag lookup that matches nothing. What happens next is whatever the binding happens to do,
and touching any other control in the pane may silently rewrite their channel to `release`.

That is pre-existing, and a rewrite has to choose deliberately rather than reproduce an accident.
Three defensible answers — add Nightly to the picker, show it read-only only when already active, or
match the current two-item picker and define what a nightly user sees — and they are different
products, so the plan's code cannot be written until one is chosen.

### Three spec errors found while planning

- **`OakSoftwareUpdateChannelTransformer` is not a class.** It is registered at runtime by
  `OakStringListTransformer createTransformerWithName:andObjectsArray:`. The spec had named it as
  something to unit-test.
- **Prerelease is `@"beta"`, not `"prerelease"`** — and the third channel above was missed entirely.
- **The first pane's keys are not in `Keys.h`.** They live in `Frameworks/SoftwareUpdate`, whose
  header is under `Xcode/include/` and can never be imported by a bridging header. The spec's
  "make `Keys.h` bridgeable" plan is correct for later panes and irrelevant to this one.

`Ruling: the general mechanism becomes a small pure-ObjC shim that RE-DECLARES the extern keys it
needs. Re-declaring an extern is not duplicating a literal — the declaration carries no value, the
definition stays in its own .mm, and the linker resolves it. A misspelled name is a link error
rather than a silently wrong key, which is exactly what the retyped literal behind this session's
didPromptForDefaultBundles casing bug was not.`

### Worth noting about process

This spec has had errors corrected at self-review and again at planning, both times because it
described code that had been surveyed rather than read. The next pane's design should start from
reading its source.

### If interrupted here

Branch `phase-6/swiftui-preferences`, unpushed, tree clean. Spec at
`docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`. Ask the maintainer the nightly
question, then invoke `superpowers:writing-plans`. PR #20 (update-alert wording) is open and green
against master, unmerged.

---

## 2026-08-20 — Settings panes designed as islands; About dropped with reasons

Spec at `docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`. Branch
`phase-6/swiftui-preferences`, nothing implemented yet.

### About was evaluated and dropped

It is not an AppKit window — a 292-line controller around a `WKWebView` rendering HTML that
`assemble_resources.sh` generates from Markdown, with version and copyright injected at runtime as
JavaScript globals. Porting it means writing a Markdown renderer for a 269 KB Changes page of 202
releases, plus selection, scrolling and link handling, to replace what a browser does for free —
and the gate is visual parity, so success looks identical to doing nothing. Recorded in `HANDOFF.md`
with the reasoning, not just the verdict.

### Settings: the shell stays, the panes become islands

2,544 lines across 18 files, and the cost is in the panes. Four of six bind through
`NSUserDefaultsController` and value transformers; one loads from a xib. The 234-line shell works,
so it keeps the window, toolbar, key equivalents, transitions and persistence, and each pane's
`loadView` installs an `NSHostingView` instead of hand-built AppKit.

Maintainer's decisions: modern `Form` styling rather than visual parity, since the goal is a uniform
modern look; and all panes held on one branch so Settings never ships half-modern.

`Ruling: SoftwareUpdate goes first, not Files. Files looked obvious at 145 lines until reading it —
its checkboxes go to NSUserDefaults but file types, encoding and line endings go through
settings_t, a C++ layer that cannot cross a bridging header, and it uses a custom encoding control
backed by Charsets.plist. That is the two hardest pieces of the whole effort sitting on the pane
whose job is to prove the easy case. SoftwareUpdate is three controls and plain defaults.`

### The one-line change that removes a whole failure class

`Keys.h` is pure Objective-C and contains no C++, so it is one `#import <Foundation/Foundation.h>`
away from being usable through a bridging header. That lets Swift use the real `extern NSString*
const` key constants via `@AppStorage` instead of retyped literals — the exact failure that produced
this session's `didPromptForDefaultBundles` casing bug, where a test passed while proving nothing.
Six panes of retyped keys would be six chances to repeat it.

### If interrupted here

Spec is written and committed; **no implementation plan exists yet**. Next step is
`superpowers:writing-plans`, not code. Two risks the spec names and nothing has retired: this would
be the second Swift-bearing target ever in this repo (the first was the app target, proven by
spike), and `OakTransitionViewController` pins panes to `fittingSize` — a 0×0 there is what made the
Terminal pane look like a dead click for months.

---

## 2026-08-19 — v3.0.0-revived.26 cut; the maintainer confirmed the two modal paths

CHANGELOG's `## Unreleased` heading became `## 2026-08-19 (v3.0.0-revived.26)`. **Merging PR #19
now publishes a real release** — that is the whole point of this commit, and it was the maintainer's
explicit instruction rather than a side effect.

### The last two unverifiable checks passed

Closing the assistant with the red title-bar button ends the modal session and leaves the app
responsive, and ⌘Q quits while the assistant is open. Both were confirmed by the maintainer at a
keyboard, because neither is reachable from this environment.

They matter because they are separate code paths from the ones normal use exercises: Done and Skip
leave through `finishWithSkip:`, while the red button leaves through `windowWillClose:` — which only
fires because the controller declares `<NSWindowDelegate>` and assigns itself as the window's
delegate. Three distinct defects in this branch could each have left a modal session running with no
window on screen, unresponsive and force-quit only. All three are now confirmed dead against a
running app rather than reasoned about.

### The release also carries a fix nobody was looking for

`seedShippedDefaults` never restored `origin` for a bundle already in the persisted state, and
`BundleSpec` never serialised it — so on any used profile, 0 of 41 default-tier bundles resolved as
shipped. The visible symptom was "Revert to Default" being greyed out for every bundle TextMate
ships, which is how it is described in the release notes. Found only because the maintainer reported
an empty bundles step and asked why.

### If interrupted here

PR #19 is open against `master` with the version cut. Merging fires `release.yml` for real:
build, test, sign, notarize, staple, tag `v3.0.0-revived.26`, publish, and update the Homebrew cask.
Wait for CI green on the PR before merging.

---

## 2026-08-19 — Welcome step's photo moved from the step's own view to the content region

**What:** The bottom-anchored crop below was correct but fixed the wrong layer: `WelcomeStepView`
sat inside the content `VStack` alongside a `Spacer()`, so the two competed for the remaining
height, and that `VStack`'s own `.padding(24)` inset the result again — an image living inside
`WelcomeStepView` could never reach the bottom or side edges of the content region no matter how
it was cropped. Moved the image load and crop into a new `WelcomeBackground: View` and attached it
as `SetupAssistantView`'s content-region `.background { }`, applied *after* `.padding(24)` so it
covers the padded frame rather than sitting inset within it, and shown only when
`model.step == .welcome`. `WelcomeStepView` now holds only the copy text with its `.thinMaterial`
scrim — no image, no background of its own. `bin/build` succeeded; `TextMate_test` 14/14.

**Why:** The target is the About window's full-bleed photo — edge to edge above the button row,
stem running off the bottom. That requires the image to be a sibling of the Spacer, not a child
competing with it, and to sit outside the padding, not inside it.

**If interrupted here:** nothing left to do; the diff is confined to
`SetupAssistantView.swift` (the `.background` on the content `VStack`, the new `WelcomeBackground`
struct, and the slimmed `WelcomeStepView`). Rendering itself is still unverified — this only
confirms the structure now permits full bleed, not that a screenshot shows it.

---

## 2026-08-19 — Welcome step's background crop now anchors to the stem, not the centre

**What:** `WelcomeStepView`'s `.background` was cropping `tml_image.png` centre-anchored (the
default for `.aspectRatio(contentMode: .fill)`), which shows the flower head and cuts the stem off
mid-way, leaving empty space above the Skip/Continue divider. Wrapped the image in a
`GeometryReader` and added `.frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)`
before `.clipped()`, so the scaled-up image is positioned with its bottom edge at the step's bottom
edge and the excess is cropped off the top instead — the stem now runs to the bottom of the step,
matching how it exits the bottom edge on the About window. Confirmed against the installed SDK's
`SwiftUICore.swiftinterface` (`frame(width:height:alignment:)`, `_FrameLayout`) that alignment
positions the (here, oversized) content within the explicit frame rather than the reverse, so
`.bottom` keeps the content's bottom edge and crops from the top. `bin/build` succeeded;
`TextMate_test` 14/14. Nothing else in the file changed.

**Why:** The maintainer asked for the stem to reach the bottom of the step, matching the About
window's crop, instead of the centre-anchored default leaving it stranded mid-image.

**If interrupted here:** nothing left to do; the diff is self-contained to `WelcomeStepView`'s
`.background`. Rendering itself is unverified (headless/visual check was out of scope here) — if a
follow-up screenshot shows the crop still wrong, re-check `Image(nsImage:)`'s intrinsic size versus
`geo.size` at the actual window width before assuming the alignment direction is the problem.

---

## 2026-08-19 — The textmatelives background image is back, at the maintainer's request, in the About window and behind Setup Assistant's Welcome step

**What:** Recovered `Applications/TextMate/about/css/tml_image.png` (579,466 bytes) from git blob
`bb196fc9`, the exact bytes `ac04adfa` deleted on 2026-08-14, via `git cat-file -p`. Restored the
`background-image: url("tml_image.png")` rule in `about/css/stylesheet.css` that commit removed,
and rewrote the comment above it — it used to explain the removal; now it records the removal *and*
the restoration, with both commit references, rather than leaving a stale note beside the image it
described as gone. `Xcode/scripts/assemble_resources.sh` already ships it: its About-section copy is
`cp -p "$app/about/css/"*`, an unfiltered glob, not an extension allowlist, so no script change was
needed — confirmed by inspection and then by listing the built bundle's `About/css/`. Added a
background to `WelcomeStepView` in `SetupAssistantView.swift` (Setup Assistant's first step only,
not `AppearanceStepView`, `BundlesStepView`, or the shared window chrome around all three): a bundle
URL lookup (`Bundle.main.url(forResource:withExtension:subdirectory:)`, subdirectory `About/css`,
verified against the installed `NSBundle.h`) rather than an asset-catalog copy, `.thinMaterial`
behind the copy text as a scrim, and a nil-image fallback that renders the step exactly as before —
Swift here can't reach `NSImage(named:)`'s app-bundle resolution the ObjC side gets for free. `bin/build`
succeeded; `TextMate_test` 14/14. Built bundle confirmed to contain both `stylesheet.css` and
`tml_image.png` under `Contents/Resources/About/css/`.

**Why:** The maintainer knows the provenance — textmatelives' artwork, not this fork's — and asked
for it back anyway; `ac04adfa`'s own removal rationale doesn't apply once that's an informed choice
rather than an inherited default. Same image, two spots: the About window already had the CSS
machinery for it, and the Setup Assistant's Welcome step is the other "first impression" surface in
the app, so reusing the recovered file there costs nothing further to ship (579 KB once, not twice)
and gives the wizard's opening screen the same visual identity as the About window.

**If interrupted here:** nothing left to do for this change; it's a complete, self-contained diff.
If picking this up cold, `git log -1` on this entry's commit shows the whole thing — CSS rule,
comment rewrite, and the new `WelcomeStepView` body — in one place.

---

## 2026-08-19 — Shipped-tier origin is now restored on reload, not only on first sight

**What:** One-line-plus-comment fix in `+[BundleRegistry seedShippedDefaults]`
(`Frameworks/BundlesManager/src/BundleRegistry.mm`): the existing-spec branch now sets
`existing.origin = TMBundleOriginShipped` inside the branch it already guards with
`if(existing.origin != TMBundleOriginMandatory)`, mirroring the self-heal `seedMandatory` has always
done for its own origin. Nothing else changed. `bin/build` succeeds; `BundlesManager_test` 10/10,
`TextMate_test` 14/14 (both `--no-parallel`).

**Why:** `origin` is derived, never persisted — `BundleSpec`'s `plistRepresentation` and
`initWithPlistRepresentation:` don't mention it, so every reloaded spec arrives as
`TMBundleOriginUser`. `seedShippedDefaults` only tagged brand-new UUIDs, so on any profile that had
run the app once, **0 of the 41 default-tier bundles were Shipped**. That emptied the Setup
Assistant's bundles step and disabled Preferences → Bundles' "Revert to Default" menu item, which
gates on `bundleIsEditedShippedDefault:` → `origin == TMBundleOriginShipped`.

**Why not persist `origin` instead** (the deeper-looking fix): it is derived from three catalogues —
`MandatoryBundles.h`, `DefaultBundles.plist`, `AvailableBundles.plist` — that change between
releases, and all three seeds already re-derive it on every reload. Persisting adds a second source
of truth that goes stale the moment a bundle is promoted out of or dropped from a catalogue, and it
buys nothing on migration: existing state has no `origin` key, so the first launch would still have
to compute the value from the seeds and write it back. The header's `// set at load, not persisted`
is the intended design; the bug was one seed forgetting to honour it.

**Re-tagging is safe, and unconditional-within-the-guard is correct.** At the point
`seedShippedDefaults` runs, an existing spec can only hold `Mandatory` (just set by `seedMandatory`,
and load-bearing — `removeSpecForUUID:`/`updateSpec:` refuse to touch those) or `User` (the
post-load default for everything else). `Available` is impossible, that seed runs after. `User` here
carries no information worth preserving: being listed in `DefaultBundles.plist` *is* what makes a
bundle shipped-tier, and a user who repointed a shipped default is modelled as url/ref divergence by
`bundleIsEditedShippedDefault:`, not as a different origin.

**Evidence, against this machine's real state:** compiled `BundleRegistry.mm` + `BundleSpec.mm` twice
into a throwaway CLI — once from `HEAD`, once patched — with `-Dsave=harnessSaveDisabled` so `-save`
is renamed out of existence and nothing can write to `Bundles.plist`. Both ran `-init` → `-reload`
against the real `~/Library/Application Support/TextMate/Bundles.plist` (153 specs) and the real
`DefaultBundles.plist` (41 entries, all 41 already in the state file, none overlapping the 4
mandatory UUIDs or the 108 available ones). Before: `Shipped=0 User=41`. After: `Shipped=41 User=0`.
`Bundles.plist` byte-identical afterwards.

**If interrupted here:** done and committed. The Setup Assistant bundles step should now populate on
this profile; worth confirming in the running app.

---

## 2026-08-19 — Bundles step now lists installed bundles too; found a second bug blocking it in practice

**What:** Closed the divergence between the design spec and `BundlesStepView`: the step sourced from
`FirstLaunchBundleInstaller.candidateSpecs`, which excludes installed bundles, so an established
profile saw nothing. Added `+[FirstLaunchBundleInstaller allShippedSpecs]` — every `origin ==
TMBundleOriginShipped` spec, sorted by category then name — and rewrote `candidateSpecs` as a filter
over it (sort comparator now lives in exactly one place). `SetupAssistantWindowController.mm`'s
`-availableBundles` now sources from `allShippedSpecs`; `recommended` comes from membership in
`candidateSpecs` (which is precisely "not installed, not previously declined"), so installed bundles
show checked+disabled and previously-declined ones show unchecked but still selectable.
`-installBundleIdentifiers:neverSuggest:` now resolves against `allShippedSpecs` too, not
`candidateSpecs`, so a reconsidered, previously-declined bundle still resolves to a spec to install —
with an explicit `installedSHA` skip inline as a second, redundant guard alongside `finish()`'s own
`!$0.installed` filter on the Swift side, which is the one that actually keeps installed bundles out
of both the install and never-suggest lists. Updated `SetupAssistantView.swift`'s stale comment above
that filter, the empty-state copy (now only reachable if zero shipped-tier specs exist at all), and
the disclosure line (now mentions installed bundles explicitly). `bin/build` succeeds;
`bin/build TextMate/test` → 14/14 (`TextMate_test -v`: `14 tests passed`).

**Why:** the maintainer ran the assistant and saw an empty Bundles step; the spec always said
installed entries should show, checked and disabled, not disappear.

**Found during verification, escalated rather than patched — outside this task's file list:**
`BundleRegistry.seedShippedDefaults` (`Frameworks/BundlesManager/src/BundleRegistry.mm:144-179`) only
sets `origin = TMBundleOriginShipped` for a UUID it has never seen before in `_specs`. For a UUID
already present in the loaded state file — true of every default-tier bundle after its first install
— origin is left at whatever it was on load, and `BundleSpec.mm`'s `plistRepresentation` /
`initWithPlistRepresentation:` never mention `origin` at all, so a freshly-loaded spec always starts
at the default, `TMBundleOriginUser`, and nothing re-promotes it. `seedMandatory` doesn't have this
problem — it unconditionally re-asserts `existing.origin = TMBundleOriginMandatory` on every reload —
but `seedShippedDefaults` has no equivalent self-heal. Read `BundleRegistry.mm` in full, then
confirmed this is live on this exact machine two ways: (1) spot-checked 5 of the 41
`DefaultBundles.plist` UUIDs directly against `~/Library/Application Support/TextMate/Bundles.plist`
— all 5 present, all 5 already carry a real `installedSHA`; (2) replayed `-reload`'s exact sequence
(load state file → `seedMandatory` → `seedShippedDefaults` → `seedAvailableBundles`) in a throwaway
Python script against this machine's real `Bundles.plist` + `DefaultBundles.plist` +
`AvailableBundles.plist` — result: **0** of 153 specs end up `origin == Shipped` (the 41 default-tier
ones sit at `User`; they don't overlap `AvailableBundles.plist`'s UUIDs, so they're not even
reclassified to `Available` — just stuck). This task's fix is still correct and necessary — a truly
fresh profile's first-ever launch hits no existing entries, so `seedShippedDefaults` tags all 41
correctly and `allShippedSpecs` returns them immediately, no further change needed here — but on this
machine, and on any already-used profile, the Bundles step will keep showing its (new) empty-state
message until `seedShippedDefaults` also self-heals `origin`, the way `seedMandatory` already does.
That fix belongs in `BundleRegistry.mm`, not touched here. `BundlesManager.mm:1012` computes the
*Preferences → Bundles* "recommended" badge off the same `origin == Shipped` check, so that pane is
very likely silently affected by the same bug, independent of the Setup Assistant.

**If interrupted here:** the 3-file fix (`FirstLaunchBundleInstaller.{h,mm}`,
`SetupAssistantWindowController.mm`, `SetupAssistantView.swift`) is complete, built, tested, and
committed. The real blocker to the maintainer actually seeing bundles listed is
`BundleRegistry.seedShippedDefaults` not re-asserting `origin` for already-tracked specs. That needs
its own task: whether *every* previously-tracked default-tier bundle deserves unconditional
re-tagging the way mandatory bundles get it, or whether that would clobber some legitimate
reclassification path, hasn't been traced.

---

## 2026-08-19 — Setup Assistant complete; the final review caught what eight task reviews could not

All eight tasks of `docs/superpowers/plans/2026-08-18-setup-assistant.md` are implemented and
reviewed, plus a final whole-branch pass and its fix wave (`2d03ce34`). Build succeeds, 14 tests
pass, working tree clean on `phase-6/swiftui-onboarding`.

### The two defects worth remembering

Every task passed its own review, several after fix rounds. The feature still shipped two defects
into the final review, and both lived in the *seam* between tasks that were each individually
correct:

**Picking "Dark" wrote a light theme into `darkModeThemeUUID`.** `selectedThemeIdentifier` was
computed once in `init` and never recomputed when the appearance picker changed, so `finish()` wrote
a stale identifier into the slot the *new* appearance named. On a fresh profile that put Mac Classic
in the dark slot: ask for dark, get black-on-white. The picker was set up in one task and consumed
in another, and neither review could see both ends.

**Every run after the first showed first-run state.** The window controller is a process-lifetime
singleton that built its `contentView` — and therefore its SwiftUI model — once in `-init`.
Reopening from Help landed on the Bundles step with a Done button and no Welcome, re-offered
installed bundles, and silently reverted a theme set from `View → Theme` in between. Each task only
ever considered the first run.

`Ruling: this is the argument for a whole-branch review that per-task review cannot make. Both
defects were invisible by construction to a reviewer holding one diff. Neither the compiler nor the
test suite could see either.`

### A false premise in the design, corrected rather than built around

The spec justified running the assistant from `applicationDidFinishLaunching:` on the grounds that
it precedes session restore, so bundles install before documents open. **That is untrue.**
`+[DocumentWindowController restoreSession]` runs synchronously in
`applicationWillFinishLaunching:`, which fires first. Existing users see documents before the
assistant.

`Ruling: correct the documentation, not the launch ordering. The behaviour is identical to what
promptIfNeeded did for years, so nothing regressed; moving earlier means a modal inside
applicationWillFinishLaunching: or reordering session restore, both far riskier than this plan
designed or reviewed. The spec's manual-check item asserting the old ordering would otherwise have
been marked failed against correct behaviour.`

### If interrupted here

The branch is complete and unmerged. It needs the maintainer's manual QA — nothing in it has been
exercised by a human. The highest-value checks: close the assistant and confirm the app still
responds; open it twice and confirm it re-focuses; pick Dark, click Done, and confirm
`defaults read com.shelbydenike.TextMate darkModeThemeUUID` is not the Mac Classic light theme.
Merging will NOT publish a release — verified by reading `release.yml`: its version regex resolves
past `## Unreleased` to the already-tagged `3.0.0-revived.25` and the tag-exists check gates every
publish step off.

---

## 2026-08-19 — Final review fix wave on the Setup Assistant branch

**What:** Seven findings from the whole-branch review, one commit, two files.

The two critical ones. `SetupAssistantModel` held a single `selectedThemeIdentifier`, read once in
`init` for whichever slot the *starting* appearance named, and `finish()` then wrote it into the slot
the *ending* appearance named — so a fresh profile (automatic, editing light, Mac Classic selected)
that picked Dark wrote Mac Classic into `darkModeThemeUUID`, and dark mode resolved to a light theme.
It is now `selectedThemeIdentifiers: [String: String]`, one entry per slot, both seeded from the host
in `init`, with a computed `selectedThemeBinding` that addresses `editingAppearance`. The list, the
preview and the write therefore always name the same slot. That binding ignores a nil write: a `List`
whose contents change under it can report the vanished selection as no selection, which would clear
the slot's real theme.

Second: `SetupAssistantWindowController` is a `sharedInstance`, and it built `contentView` — and with
it the model, its `step`, and the `lazy allThemes`/`allBundles` caches — once in `-init`. Every run
after the first therefore opened on the Bundles step with a Done button and no Welcome (losing Skip's
discoverability), re-offered bundles installed during run one, and reverted a theme picked from
`View → Theme` in between. `-runModal` now rebuilds the view *after* the `isVisible` reentrancy guard,
so the re-focus path stays a pure no-op and only a genuine session gets fresh state. The discarded
model is unreferenced, which also leaves its strong reference back to the controller holding nothing
up.

**Automatic mode could not set the dark theme** — `editingAppearance` collapsed `"auto"` to `"light"`,
while the spec says both keys are editable in automatic because both are used. Fixed with the smallest
honest UI: a second segmented picker (Light Theme / Dark Theme) that appears *only* when appearance is
automatic and chooses which slot the existing single list edits, plus `finish()` writing both slots in
that mode and one otherwise. Rejected as larger: two side-by-side theme lists, or a per-slot sub-step.
Nothing changes for light or dark users, where the mode already names one slot.

Four smaller ones. The window never cleared `preventsApplicationTerminationWhenModal` (defaults YES),
so ⌘Q was inert during an app-modal wizard shown over already-restored documents; the retired
`FirstLaunchBundleInstaller` window cleared it explicitly and now this one does too. Skip Setup gained
`.keyboardShortcut(.cancelAction)`, because the spec and the assistant's own copy both promise ESC
dismisses it and nothing wired ESC to anything. The bundles step gained an empty state — essentially
every existing profile has all shipped-tier bundles installed, so the list is empty, and it sat under
"Recommended ones are already selected". And its caption now discloses that unchecking is permanent:
`installBundleIdentifiers:neverSuggest:` writes to the never-suggest list, which also silences
`DocumentWindowController`'s on-demand per-extension prompt.

**Why:** last pass before the branch is done; these were the findings that a user would actually hit,
in severity order.

**If interrupted here:** nothing outstanding on the code. `bin/build` succeeds and
`bin/build TextMate/test` passes 14/14. Rendering was not verified — the appearance step's new
automatic-mode picker and the bundles empty state have never been looked at in a running app.

---

## 2026-08-19 — Task 8 landed: the Setup Assistant now runs at first launch

**What:** Executed `.superpowers/sdd/2026-08-18-setup-assistant/task-8-brief.md`, the last task.
`AppController.mm`'s `applicationDidFinishLaunching:` no longer calls `[FirstLaunchBundleInstaller
promptIfNeeded]`; it now calls `[SetupAssistantWindowController.sharedInstance runModal]`, guarded
by `TMSetupAssistantShouldRunAtLaunch(NSUserDefaults.standardUserDefaults)`. Added the
`SetupAssistant/SetupAssistantGating.h` import beside the window-controller one and dropped the now-
unused `FirstLaunchBundleInstaller.h` import — nothing else in the file referenced that class.
`FirstLaunchBundleInstaller.mm`/`.h` lost `+promptIfNeeded`, `sActiveInstaller`,
`-initWithCandidates:`, `-buildContentView`, `-show`, `-dismiss`, the `FLBITableView` subclass, the
table view data source/delegate methods, and `-skip:`/`-installSelected:`/
`-observeValueForKeyPath:...` — the entire window/NIB-free-construction layer. `+candidateSpecs`
survives untouched, along with the three imports it needs (`BundlesManager.h`, `BundleRegistry.h`,
`BundleSpec.h`); `SetupAssistantWindowController.mm`'s `-availableBundles` and
`-installBundleIdentifiers:neverSuggest:` both still call it and needed no change. Verified before
deleting anything: `grep -rn promptIfNeeded --include=*.mm --include=*.h .` had exactly three hits
(the header declaration, the `.mm` definition, the one `AppController.mm` call site) — no other
caller existed to update. Confirmed after: every symbol `candidateSpecs`'s body touches
(`TMBundleOriginShipped`, `installedSHA`, `uuid`, `name`, `category`,
`kUserDefaultsBundlesToNeverSuggestKey`, `BundleRegistry.sharedInstance.allSpecs`) still resolves
through the kept imports. Rewrote the header's stale class comment, which had described the deleted
modal ("Enter activates Install Selected; ESC activates Skip...") — left as-is it would have
actively misdescribed the class.

**One change outside the brief, called for explicitly:** `SetupAssistantView.swift`'s `finish()`
switched both `.map { $0.identifier! }` calls to `.compactMap { $0.identifier }`. Same result under
today's invariant (`BundleSpec.mm:21` refuses to construct a spec with a nil `uuid`, and
`NSUUID.UUIDString` is non-nullable) — but `compactMap` drops a future nil instead of crashing on
it, and a first-launch wizard is the worst place to force-unwrap something a later change to
`TMBundleChoice`'s producers could break. Updated the comment above it, which had explained the old
force-unwrap and would otherwise now describe code that no longer exists.

**CHANGELOG.md gets `## Unreleased`, not a dated version heading.** Read
`.github/workflows/release.yml` first: it fires on any push to `master` that touches
`CHANGELOG.md`, extracts the version from the *first* `^## .* (v.*)$` line, and releases it if the
version contains `-revived` and no matching tag exists yet. Inventing the next version number now
would auto-publish the moment this branch merges — before the maintainer's own manual QA pass. Dug
into `git log -S'## Unreleased' -- CHANGELOG.md` and found the repo already has exactly this
pattern: commit `761a219a` added a bare `## Unreleased` heading for a feature landing, and a later,
separate `release:` commit (`c0631a40`) renamed it to a dated `(v3.0.0-revived.23)` heading plus a
one-line summary. Followed that convention exactly rather than inventing a new one. Confirmed safe
by running the workflow's own extraction regex against the edited file: it still resolves to
`3.0.0-revived.25`, the already-tagged top entry, because `## Unreleased` has no `(v...)` suffix to
match.

**HANDOFF.md:** Phase 6 items table's onboarding row is now `**done**`; the "Onboarding is designed
and approved... Nothing is implemented yet" paragraph is rewritten to "Onboarding is done" naming
what shipped and the two things that are genuinely still outstanding (both human-only, both outside
this environment): the maintainer's manual walk of the five first-launch scenarios the spec names,
and a green CI run on the pushed branch. Current-state table's `Phase 6` and `Unreleased` rows
updated to match.

**CLAUDE.md** gains a `### Setup Assistant (Phase 6)` subsection under Architecture: the gating-key
rename rationale (a new `didRunSetupAssistant` default rather than reusing the legacy prompt key, so
existing users see the assistant once too), that `TextMate-Bridging-Header.h` reaches only
`SetupAssistantTypes.h` and why that header has to stay pure-ObjC, and why `SetupAssistantCore` is
split into its own `library.static` — `TextMate_test` compiles only `bin/gen_test`'s generated
runner, so anything its tests exercise has to come from a library both `TextMate` and
`TextMate_test` link, the same shape `PreferencesMigration` already used.

**Build:** `bin/build` → `** BUILD SUCCEEDED **`. `bin/build TextMate/test` → `** BUILD SUCCEEDED
**`; `TextMate_test -v` run directly → `TextMate_test: 14 tests passed`, unchanged count — the brief
specified no new tests for this task.

### If interrupted here

All eight tasks of `docs/superpowers/specs/2026-08-18-setup-assistant-design.md` are implemented and
committed on `phase-6/swiftui-onboarding`. `FirstLaunchBundleInstaller` no longer has a window at
all; the Setup Assistant is the only path to installing default bundles now, both at first launch
and from `Help → Setup Assistant…`. What's left is explicitly human-only and could not be done from
here: the maintainer's manual walk of the brief's Step 4 checklist (fresh-profile launch order, ESC-
skip persistence, Help reopening with live state rather than a blank wizard, a chosen theme actually
applying, checked/unchecked bundles persisting correctly), and pushing the branch to confirm CI is
green (Step 7) before treating the phase item as done. Until both happen, do not turn `##
Unreleased` into a dated version heading — that is the deliberate act that ships this.

## 2026-08-18 — Task 7 landed: the bundles step, and the brief's own snippet failed to compile

**What:** Executed `.superpowers/sdd/2026-08-18-setup-assistant/task-7-brief.md`.
`FirstLaunchBundleInstaller.h` now declares `+ (NSArray<BundleSpec*>*)candidateSpecs` (forward
`@class BundleSpec`); the `.mm` was already implementing it with no prior declaration, so the
implementation itself is untouched. `SetupAssistantWindowController.mm` gives real bodies to
`-availableBundles` (maps `candidateSpecs` into `TMBundleChoice`) and
`-installBundleIdentifiers:neverSuggest:` (merges into the never-suggest default via
`TMMergeNeverSuggestIdentifiers`, then calls `BundlesManager.sharedInstance
installSpecs:completionHandler:` for the checked set). `SetupAssistantView.swift`'s bundles case is
now `BundlesStepView` — a list of toggles, recommended entries pre-checked — replacing
`Text("Bundles")`. `project.yml` needed no change: the `TextMate` target already links
`BundlesManager` and already lists `Xcode/include/BundlesManager` in its header search path
(confirmed by reading `project.yml:1860,1876-1877`, not assumed).

**The brief's own `finish()` snippet does not compile, for a reason specific to this bridging
setup.** `TMBundleChoice.identifier` has unspecified nullability in `SetupAssistantTypes.h`, so
Swift imports it as `String!`. `.map { $0.identifier }`, exactly as the brief wrote it, doesn't
preserve that IUO — SE-0054 decays a closure's inferred return type to plain `String?`, so both
`install` and `never` came out as `[String?]`, and `host.installBundleIdentifiers(_:neverSuggest:)`
wants `[String]`. Fixed with a force-unwrap (`$0.identifier!`) and a comment explaining why it's
safe: every `TMBundleChoice` here comes from `-availableBundles`, which always passes a real,
non-nil `spec.uuid.UUIDString` into the factory method. Considered annotating
`SetupAssistantTypes.h` with `NS_ASSUME_NONNULL_BEGIN/END` instead, which would fix the root cause
for every consumer including `TMThemeChoice` — rejected for this task because that file isn't in
the brief's Files list and a nullability-wide change risks a ripple beyond what Task 7 asked for;
the Swift-side fix stays confined to the one file the brief already named.

**Two questions the brief asked me to answer rather than guess at:**

1. **Async install continuing after the assistant's window closes is not a problem.** `finish()`
   calls `installBundleIdentifiers(...)` and then `host.finish(withSkip: false)` in the same turn,
   so the window orders out before `installSpecs:completionHandler:`'s background work can possibly
   finish. But `BundlesManager.sharedInstance` is a process-lifetime singleton
   (`BundlesManager.mm:58-61`), not owned by the assistant's window or its modal session — install
   and its completion handler keep running on their own queue exactly as they would for any other
   caller. The real cost, and it's out of scope per the brief ("do NOT add a progress UI"): the user
   gets no visual cue anything is still happening, where the old `FirstLaunchBundleInstaller` window
   stayed on screen with a progress bar until the install finished. A user who quits immediately
   after clicking Done could interrupt a bundle mid-install — a class of risk the old flow avoided
   by blocking on that progress bar, not something this task's scope covers.
2. **Installed bundles cannot reach the list at all, so "greyed out" is defensive code, not a live
   path today.** `candidateSpecs` filters `spec.installedSHA == nil` before anything reaches
   `-availableBundles`, so every `TMBundleChoice` built from it has `installed == NO` by
   construction. `BundlesStepView`'s `.disabled(bundle.installed)` and the pre-check logic's
   `!$0.installed` guards are therefore currently unreachable in the true branch — kept anyway
   because `TMBundleChoice` is a general-purpose view-model type and the brief's own Step 2/Step 3
   code computes and consumes `installed` explicitly; diverging (e.g. a second query that also
   surfaces installed bundles) would be exactly the "second version of that query" the top-level
   task said not to write. Verified empirically, not assumed: parsed the real `~/Library/Application
   Support/TextMate/Bundles.plist` on this machine against the shipped-tier catalogue `Bundle
   Support.tmbundle/Support/DefaultBundles.plist` (41 entries). On this dev machine all 41 are
   already installed, so `candidateSpecs` currently enumerates **0** here; for a fresh user (empty
   `Bundles.plist`, no never-suggest entries) the same cross-reference gives **41** candidates
   (Languages 28, Other 5, SCM 5, Build 3), none overlapping the 4 mandatory-tier bundles.

**Build:** `bin/build` → `** BUILD SUCCEEDED **` (after the force-unwrap fix; zero warnings on any
SetupAssistant or FirstLaunchBundleInstaller file — the one Swift deprecation warning in the log is
pre-existing, in `ThemePreview`'s untouched `+`-based `Text` concatenation from Task 6, just shifted
line number by this task's insertions). `bin/build TextMate/test` → `** BUILD SUCCEEDED **`;
`TextMate_test -v` run directly → `TextMate_test: 14 tests passed`, unchanged count —
`TextMate_test` doesn't link `BundlesManager` at all (`project.yml:2062-2066`, and the existing
`t_setup_assistant.mm` comment says so directly), so this task's bundle-selection logic has no
reachable unit-test surface there; the brief specified no new tests.

### If interrupted here

Task 7 is committed. `FirstLaunchBundleInstaller`'s window itself is still alive and still callable
(`+promptIfNeeded`) — Task 8 is what retires it. All three SwiftUI steps (welcome, appearance,
bundles) now have real content; nobody has put the assistant on screen in this environment, so a
human still needs to run the brief's Step 5 checklist: the list matches the old modal's offering,
recommended entries are pre-checked, Finish installs the checked set, unchecked bundles land in the
never-suggest default and don't re-prompt on a matching file open, and Skip installs nothing and
marks nothing as never-suggest.

## 2026-08-18 — Task 6, fix round 2/5: the currently-active theme is exempt from the hidden skip

**What:** Implemented the fix round 1 proposed rather than shipped. `-availableThemes`
(`SetupAssistantWindowController.mm`) now reads `universalThemeUUID` and `darkModeThemeUUID` once
before its enumeration loop and only applies the `hidden_from_user()` skip when an item's identifier
matches neither -- mirroring `validateThemeMenuItem:`'s own unfiltered resolution of the current
theme (`AppController Menus.mm:135-136`) rather than inventing a new mechanism. A theme that is
hidden from `View -> Theme` but currently configured in either slot now stays selectable and shows
as selected; every other hidden theme is still excluded exactly as round 1 left it.

**Confirmed, not assumed:** the exemption reads both defaults keys unconditionally in the single
pass that builds the whole list (no "which side" parameter exists on `-availableThemes` at all), so
it can't be lost by switching the Light/Dark segmented control -- that only filters an
already-complete, already-exempted list downstream in Swift. And `&&` short-circuits on
`hidden_from_user()` first, so a non-hidden item never even reaches the UUID comparisons -- the
common case (no hidden theme active) produces byte-identical output to round 1, unchanged.

**Build:** `bin/build` → `** BUILD SUCCEEDED **`. `bin/build TextMate/test` → `** BUILD SUCCEEDED **`;
`TextMate_test -v` run directly → `TextMate_test: 14 tests passed`.

### If interrupted here

Fix rounds 1/5 and 2/5 for Task 6 are both committed. Up to 3 more review rounds may follow before
Task 7 starts.

## 2026-08-18 — Task 6, fix round 1/5: hidden themes were leaking into the assistant's picker

**What:** Review caught that `-availableThemes` (`SetupAssistantWindowController.mm`) had no
`hidden_from_user()` check, while `View -> Theme`'s own enumeration
(`AppController Menus.mm:153-155`) skips hidden items before ever building a menu entry. Concrete
instance: `Themes.tmbundle/Themes/macOS System Theme.tmTheme` sets `hideFromUser`, so it's absent
from the menu but was appearing in the assistant. Added the same skip, with a comment pointing at
`AppController Menus.mm:154` as the source of the rule, so the two stay in sync if the menu's rule
ever changes.

**Traced, not fixed: what happens if the user's actual configured theme is a hidden one.**
`-currentThemeIdentifierForAppearance:` reads `NSUserDefaults` directly, unfiltered, so it still
returns the hidden theme's real UUID. But `allThemes` (`host.availableThemes()`) no longer contains
it post-fix, so `selectedTheme` resolves to `nil` (generic black preview, not the real theme's
colours) and the SwiftUI `List`'s selection binding matches no row (blank selection) — no crash, no
data loss on an untouched Done click (the same identifier writes back unchanged), but a user could
mistake the blank selection for a lost setting and pick a visible theme to "fix" it, silently
overwriting a working hidden-theme configuration. Proposed but did not implement the smallest fix:
exempt whichever theme is currently active in either slot from the hidden check, mirroring
`validateThemeMenuItem:` (`AppController Menus.mm:117-128`), which already looks up the active
theme's name via `bundles::lookup` unfiltered by `hidden_from_user()` for its menu-item label.
Left for the coordinator to schedule.

**Build:** `bin/build` → `** BUILD SUCCEEDED **`. `bin/build TextMate/test` → `** BUILD SUCCEEDED **`;
`TextMate_test -v` run directly (same harness quirk as Task 6's own entry below) →
`TextMate_test: 14 tests passed`.

### If interrupted here

Fix round 1/5 for Task 6 is committed. 4 more review rounds may follow before Task 7 starts. The
hidden-current-theme exemption above is proposed, not implemented — needs a coordinator decision,
not just a green build, before touching it.

## 2026-08-18 — Task 6 landed: the appearance step, and two more brief gaps caught by reading real headers

**What:** Executed `.superpowers/sdd/2026-08-18-setup-assistant/task-6-brief.md`. Step 2 of
`SetupAssistantView.swift` is now `AppearanceStepView` — a segmented Light/Dark/Automatic picker
plus a theme list plus a mockup preview drawn from real theme colours — replacing the
`Text("Appearance")` placeholder. `SetupAssistantWindowController.mm` gives real bodies to
`-availableThemes`, `-currentAppearance`, `-currentThemeIdentifierForAppearance:` and
`-applyThemeIdentifier:appearance:`; `-availableBundles` and `-installBundleIdentifiers:neverSuggest:`
stay stubs, Task 7's job. `project.yml` needed no change — the TextMate target's
`HEADER_SEARCH_PATHS` already lists `theme`, `bundles`, `scope` and `ns` (confirmed by reading it,
per the brief's own instruction to verify rather than assume).

**The task instructions were right that the brief's colour-extraction snippet was unverified, and
right to say so up front — but the specific mismatch they named wasn't the real one.** They warned
`scope::wildcard` might be a `context_t` where `styles_for_scope` wants a `scope_t`. Reading
`scope.h` directly: `wildcard` is declared `extern scope_t wildcard`, so `theme->styles_for_scope
(scope::wildcard)` typechecks fine — no error there. The real wrinkle is semantic, found by reading
`theme.cc`'s matcher: a wildcard-context match short-circuits `does_match` to true for *every*
scope-selector rule in the theme simultaneously (scope.cc:274), not just the unscoped root entry, so
merging in rank order can blend in whatever per-scope override a theme happens to define for caret
or selection. `theme_t` has no root-level accessor for those two — only `foreground()`/`background()`
(theme.h:77-78) — so there's no way to get them without going through `styles_for_scope` at all.
Used `theme->foreground()`/`theme->background()` directly for the background/foreground swatch
colours (matching the task instructions' explicit steer, verified against `theme.cc:350-360`, where
`background(fileType)` is itself implemented as `styles_for_scope(fileType).background()` — sugar,
not a different code path), and kept `styles_for_scope(scope::wildcard)` only for caret/selection,
where there is no alternative. In practice this rarely matters: real themes almost never override
caret/selection per scope, so wildcard and the true root value coincide for every theme on this
machine. Neither value is actually drawn by the mockup anyway — `ThemePreview`'s body never
references `TMThemeColorCaret` or `TMThemeColorSelection` — so this was verified by reading, not by
a visible consequence.

**The brief's own `finish()` never sent the picker's tri-state choice anywhere, which would have
made "Automatic" a dead option.** Step 2 asked for an `-applyAppearance:` method "called from
`-finishWithSkip:` when not skipped" — but `-finishWithSkip:` only ever receives a `BOOL`, and the
Swift model's `appearance` (light/dark/auto) never crosses to the ObjC side in the brief's Step 4
`finish()`, which calls `applyThemeIdentifier(_:appearance:)` with `editingAppearance` — a value
that's *always* "light" or "dark", collapsing "auto" the same way "light" does, by design (it picks
which slot's theme list to edit, not the overall mode). Confirmed by reading `OakTextView.mm:826`
and `QuickLookPreviewProvider.mm:175` that `themeAppearance` is a real, load-bearing default (absent
= follow system dark/light; present = force it), so silently never writing it would make "Automatic"
indistinguishable from "Light" forever. Fixed by adding `-applyAppearance:` to the
`TMSetupAssistantHost` protocol itself (`SetupAssistantTypes.h` — the one file the brief's own Files
list omitted, because the brief didn't anticipate needing it) and calling it from Swift's `finish()`
directly, translating `"auto"` to `nil`. That header is already the Swift/ObjC boundary — the
bridging header imports it verbatim — so this is the same mechanism every other host method already
uses, not a new one. `-finishWithSkip:` itself is untouched.

**Theme count on this machine, by static inspection (not live enumeration — the task rules out
launching the app here):** 22 `.tmTheme` files, same 22 names, in both the embedded
`themes.tmbundle` under `Applications/TextMate/support/Bundles` and the separately-installed copy
under `~/Library/Application Support/TextMate/Managed/Bundles/`. Whether `bundles::query` dedupes
across those two locations at runtime is exactly the kind of thing a human needs to check by
actually opening the assistant.

**Build:** `bin/build` → `** BUILD SUCCEEDED **`, zero warnings on any SetupAssistant file (checked
by grep against the full log, not just the tail). `bin/build TextMate/test` built clean but its
`exec`-replaced binary's output didn't reach the captured log in this harness — ran
`~/build/textmate-revived/xcode/Release/TextMate_test -v` directly instead (sanctioned by CLAUDE.md
as the alternative to the name-filterless runner): `TextMate_test: 14 tests passed`, unchanged count,
no new tests — the brief specified none for this task.

**Not yet done, deliberately:** bundles step is still `Text("Bundles")` (Task 7). Nobody has put the
window on screen — same constraint as Task 5, this environment cannot launch the app or synthesise
clicks. A human still needs to confirm the five behaviours the brief's Step 6 lists: the theme list
matches `View → Theme`'s offerings, selecting a theme redraws the preview with no delay, the preview
colours are actually right for the theme, finishing preselects that theme on reopen, and switching to
Dark and picking a theme writes only the dark slot. Check `defaults read
com.apple.universalaccess reduceTransparency` before drawing any conclusion from a screenshot.

### If interrupted here

Tasks 1-6 are complete. Task 7 (bundles step: wire `availableBundles` and
`installBundleIdentifiers:neverSuggest:`) is the only remaining SwiftUI step; Task 8 (wiring the
assistant into launch) comes after. The assistant is still reachable only from the Help menu, so
none of this affects normal startup yet.

## 2026-08-18 — Task 5 landed: the SwiftUI shell, and a brief that was wrong on the load-bearing line

**What:** Executed `.superpowers/sdd/2026-08-18-setup-assistant/task-5-brief.md`. `SetupAssistantView.swift`
now holds the three-step shell: `SetupAssistantModel` (`@MainActor`, owns only which step is
showing), `SetupAssistantView`, `WelcomeStepView`, and the Objective-C++ entry point
`SetupAssistantHostingController.view(for:)`, exposed to ObjC as `+viewFor:`.
`SetupAssistantWindowController.mm` installs the resulting `NSHostingView` as the window's
`contentView` and implements `TMSetupAssistantHost` with the six data stubs the brief specifies
(empty arrays / nil) plus `-finishWithSkip:`, which calls `[NSApp stopModal]`.

**The brief's Step 2 code sample was wrong, and the task instructions that assigned this work said
so up front.** It showed replacing the class extension with `<TMSetupAssistantHost>` alone, which
would have dropped `<NSWindowDelegate>`. That conformance is what lets `-init` assign
`window.delegate = self` and what makes `-windowWillClose:` — which calls `[NSApp stopModal]` — ever
get invoked. Losing it is the same failure the previous entry's "Route one" describes, reopened: an
app-modal session with no window on screen and no way out but a force-quit. It would not have shown
up as a build error either — `window.delegate = self` still compiles against a narrower protocol
list as long as nothing else in the file demanded `NSWindowDelegate`, so the break is silent until
someone closes the window at runtime. Committed extension is
`@interface SetupAssistantWindowController () <NSWindowDelegate, TMSetupAssistantHost>` — both
protocols, confirmed present before building and again before committing.

**Two further gaps, neither named in the brief, both compiler-caught rather than silent.**
`SetupAssistantWindowController.mm` had never imported `SetupAssistantTypes.h` — Task 4 needed
none of `TMThemeChoice`/`TMBundleChoice`/`TMSetupAssistantHost`, and the generated
`TextMate-Swift.h` only forward-declares them (`@protocol TMSetupAssistantHost;`, no definition),
which is enough for a bare pointer but not for declaring conformance or a method returning
`NSArray<TMThemeChoice*>*`. Fixed with a direct import, ordered before `TextMate-Swift.h`.
Separately, Swift 6 strict concurrency rejected the hosting bridge outright:
`view(for:)` called `SetupAssistantModel.init(host:)`, which is `@MainActor`, from a nonisolated
static context — `error: call to main actor-isolated initializer 'init(host:)' in a synchronous
nonisolated context`. Marked `view(for:)` itself `@MainActor`; every real caller (window
construction, from the Help menu action) is already on the main thread, so the isolation the
function declares matches the isolation its caller is already running under. Nothing about who
owns the model or the step state changed.

**Build:** `bin/build` → `** BUILD SUCCEEDED **`, clean of SetupAssistant-related warnings.
`bin/build TextMate/test` → `TextMate_test: 14 tests passed`, unchanged from Task 4 — this task
added no new tests, per the brief.

**Not yet done, deliberately:** all six data-returning/data-applying `TMSetupAssistantHost` methods
are stubs; the appearance and bundles steps are placeholder `Text` views (Tasks 6 and 7). Nobody has
put the window on screen — the task that assigned this work ruled that out for this environment, so
verification here is build and test only. A human still needs to `bin/deploy-local` and click
through: Back/Continue/Skip navigate three steps, Back is absent on step one, the last step's button
reads "Done", Return activates the default button, and closing with the title-bar button leaves the
app responsive.

### If interrupted here

Tasks 1-5 are complete. Task 6 (appearance step: wire `availableThemes`, `currentAppearance`,
`applyThemeIdentifier:appearance:`) and Task 7 (bundles step) remain, plus the manual click-through
above. Nothing is wired into launch yet — the assistant is reachable only from the Help menu until
Task 8, so none of this can affect normal startup in the meantime.

---

## 2026-08-18 — two independent routes to a hung app, both closed before anyone clicked

Task 4 of the Setup Assistant plan landed the window and the `Help → Setup Assistant…` item
(`a0d16a0c`), then a reentrancy guard (`399cd307`). Both changes exist because of the same failure:
an app-modal session with no window on screen, unresponsive, recoverable only by force-quit.

**Route one — no window delegate.** The plan's code relied on `-windowWillClose:` calling
`[NSApp stopModal]`, but nothing made the controller the window's delegate, so it would never fire.
Caught in the pre-flight scan before implementation. Fixing it required
`@interface SetupAssistantWindowController () <NSWindowDelegate>` as well, since assigning `self` to
`window.delegate` does not compile without it.

**Route two — no reentrancy guard.** `AppController.mm:770`'s `validateMenuItem:` does not disable
`showSetupAssistant:` during a modal session, so choosing the menu item again while the assistant is
open starts a *nested* `runModalForWindow:` on the same singleton window. The single
`windowWillClose:` unwinds only the innermost session; the outer one blocks forever. Found by task
review, not by the compiler and not by the test suite — neither can see it.

`Ruling: fixed rather than parked, because the maintainer was about to be handed a build and asked
to exercise that exact menu item. Reopening a new window is the first thing anyone does while poking
at one. Cost if wrong: a few inert lines in the single-open case.`

### Still open at time of writing

The guard tests `self.window.isVisible`, which is only correct if `-runModalForWindow:` itself makes
the window visible. **That is unverified.** The macOS 26 SDK's `NSApplication.h` carries no doc
comment for the method, and the in-repo comment at `SoftwareUpdate.mm:606` does *not* support it —
it concerns the window's level after the session ends, not ordering front. A guard resting on an
unproven assumption is close to no guard, so a scoped re-review is establishing the answer with a
standalone test program. If `isVisible` proves unreliable the guard becomes an explicit `BOOL` set
around the session, which depends on nothing.

### If interrupted here

Tasks 1-3 are complete and reviewed. Task 4 is in fix round 1 of 5 awaiting that re-review. Task 5
(the SwiftUI shell) is briefed and unstarted. Nothing is wired into launch yet — the assistant is
reachable only from the Help menu until Task 8, so a hang cannot affect normal startup.

---

## 2026-08-18 — Task 4 landed: an empty assistant window, reachable from Help

**What:** Executed `.superpowers/sdd/2026-08-18-setup-assistant/task-4-brief.md`. Added
`SetupAssistantWindowController.{h,mm}` (an `NSWindowController` subclass with an empty content
view — SwiftUI content is Task 5), a `Help → Setup Assistant…` menu item with a separator before it
(`AppController.mm:408-414`, using the project's real separator literal `{ /* -------- */ }`,
confirmed against existing uses in the Bundles and Window menus before writing it), and
`-[AppController showSetupAssistant:]` beside `orderFrontAboutPanel:`. `project.yml` gained the one
new source path; `xcodegen generate` picked it up along with the known harmless swap of the two
"Embed Dependencies" phase orderings.

**Deviation from the brief, required by the task instructions:** the brief's `-init` never sets
`window.delegate`, so its own `-windowWillClose:` would never fire and `-stopModal` would never run
— a modal session with no window and an unresponsive app, recoverable only by force-quit. Added
`window.delegate = self;` after the `contentView` assignment. That assignment does not type-check
against a bare `NSWindowController` subclass (`assigning to 'id<NSWindowDelegate>' from incompatible
type`), so the class extension also gained `<NSWindowDelegate>` conformance — required for the fix
to compile, not scope creep. The `TMSetupAssistantHost` class extension stays empty as briefed;
that conformance is Task 5's.

Build: `bin/build` → `** BUILD SUCCEEDED **`. `bin/build TextMate/test` → exit 0, 14/14 tests still
passing (confirmed verbosely via the binary directly: `TextMate_test -v` → `14 tests passed`; no
tests were added this task). Verification stops there — opening the window, confirming it's modal,
and confirming the close button restores responsiveness all need a human at a keyboard, per the
brief's own Step 6.

### If interrupted here

Task 4 is committed and built clean. Task 5 (the actual SwiftUI content view, replacing the empty
`NSView`) is next and is the point where the modules-off Swift interop this repo has never exercised
actually gets proven under a real window rather than in isolation. Read the "No target in this tree
has ever contained a Swift file" note in `CLAUDE.md` before starting it.

---

## 2026-08-18 — a test that could not fail, and the plan line that caused it

`b22a2479` corrects `test_legacy_bundle_prompt_key_does_not_suppress_the_assistant`. It wrote
`@"didPromptForDefaultBundles"`; the real constant is
`kUserDefaultsDidPromptForDefaultBundlesKey = @"DidPromptForDefaultBundles"` — capital D —
at `Frameworks/BundlesManager/src/BundlesManager.mm:28`. `NSUserDefaults` keys are case-sensitive,
so the test had been setting a key that does not exist.

**The failure mode is what makes this worth writing down: the test passed either way.** It would
have gone on passing if someone later made `TMSetupAssistantShouldRunAtLaunch` consult the real
legacy key — which is the single regression it exists to prevent, and one that would hide the Setup
Assistant from every existing user, because they all have that key set. Shipped behaviour was never
wrong; the guard was.

The wrong literal came from the implementation plan itself (line 473), so it was transcribed
faithfully. The plan is corrected in the same commit so it cannot be re-transcribed by anyone
re-running it. The test now carries a comment naming the real constant's home and noting that the
casing is load-bearing.

`Ruling: the literal stays a literal rather than importing BundlesManager.h for the symbol.
TextMate_test does not link that framework, and pulling a large dependency into the test target to
avoid one string is the worse trade. The comment is what keeps it honest.`

### If interrupted here

Task 3 of `docs/superpowers/plans/2026-08-18-setup-assistant.md` is in fix round 1 of 5, awaiting a
scoped re-review of `b22a2479`. Tasks 1-2 are complete and reviewed clean. Task 4 (the window and
the Help menu item) is briefed and unstarted — it is the first task whose verification needs a human
at a keyboard, because GUI gestures cannot be synthesised in the agent sandbox.

---

## 2026-08-18 — Task 3 landed: the gating predicate

**What:** Executed Task 3 of `.superpowers/sdd/2026-08-18-setup-assistant/task-3-brief.md`. Appended
four tests to `Applications/TextMate/tests/t_setup_assistant.mm` (`test_assistant_runs_when_key_absent`,
`test_assistant_does_not_run_once_marked`, `test_marking_is_idempotent`,
`test_legacy_bundle_prompt_key_does_not_suppress_the_assistant`) plus the
`SetupAssistantGating.h` import, and confirmed the build fails as expected: `fatal error:
'.../SetupAssistant/SetupAssistantGating.h' file not found`. Then created
`Applications/TextMate/src/SetupAssistant/SetupAssistantGating.h` and `.mm` (free functions
`TMSetupAssistantShouldRunAtLaunch`/`TMSetupAssistantMarkAsRun` plus
`kUserDefaultsDidRunSetupAssistantKey`), added the `.mm` to `SetupAssistantCore`'s `sources:` in
`project.yml`, regenerated `TextMate.xcodeproj`, and got `** BUILD SUCCEEDED **` with
`TextMate_test -v` reporting `14 tests passed` (9 in this file: the prior 5 + these 4, plus 5
existing preferences-migration tests). `bin/build` (the full app) also succeeds.

**Why:** The predicate gates the assistant on its own new `didRunSetupAssistant` key rather than
the legacy `didPromptForDefaultBundles` key, deliberately: every existing user already has the old
key set, so reusing it would hide the assistant from exactly the audience its appearance step is
for. Free functions, not a class, because a test file is wrapped in a namespace by `bin/gen_test`
and Objective-C forbids declaring a class inside one — the same shape `PreferencesMigration`
already uses.

Confirms no surprises this task: no `OAK_ASSERT` top-level-comma trap this time (none of the four
new assertions contain a bare `@[...]`/`@{...}` literal), and `bin/build TextMate/test`'s silent
exit-0-on-success (it execs the runner without `-v`, so success prints nothing) is documented
behavior, not a regression — verified by running the built binary directly with `-v`.

### If interrupted here

Task 3 is fully done, verified, and committed. Task 4 is next — see
`.superpowers/sdd/2026-08-18-setup-assistant/` for its brief once written.

---

## 2026-08-18 — Task 2 landed: SetupAssistantCore library, and the first test that runs

**What:** Executed Task 2 of `docs/superpowers/plans/2026-08-18-setup-assistant.md`. Wrote
`Applications/TextMate/tests/t_setup_assistant.mm` first (two tests exercising `TMThemeChoice` /
`TMBundleChoice`) and confirmed it fails at link with `Undefined symbols … _OBJC_CLASS_$_TMThemeChoice`
(plus `NSColor`, `TMBundleChoice`, and the two color-constant symbols, since `TextMate_test` did not
yet link AppKit or anything implementing the header). Then created
`Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.mm` implementing the two classes and
the two pure rule functions (`TMThemeAppearanceForSemanticClass`, `TMMergeNeverSuggestIdentifiers`),
appended the three pure-rule tests, added the `SetupAssistantCore` `library.static` target to
`project.yml` (linked by both `TextMate` and `TextMate_test`, plus `AppKit.framework` on the test
target for `NSColor`), regenerated `TextMate.xcodeproj`, and got `** BUILD SUCCEEDED **` with all
10 tests passing (`TextMate_test -v` → `10 tests passed`: 5 new + the 5 existing
preferences-migration ones).

**Why:** `TextMate_test` compiles only the generated runner, so anything it exercises has to come
from a library both binaries link — the shape `PreferencesMigration` already established.
`SetupAssistantCore` is that library for the Setup Assistant's boundary types.

One thing worth recording for later tasks transcribing brief code verbatim: the brief's
`test_never_suggest_merges_rather_than_replaces` body, as written, does not compile.
`OAK_ASSERT` is a plain preprocessor macro (`bin/gen_test:110`), and the preprocessor's macro
argument splitting only tracks `()`, not `[]` — so the un-parenthesized top-level commas inside
`@[ @"A", @"B", @"C" ]` inside the assertion read as extra macro arguments
(`error: too many arguments provided to function-like macro invocation`). Fixed by wrapping the
whole assertion expression in one extra parenthesis pair (`OAK_ASSERT((...))`); no semantic change.
Full detail in `.superpowers/sdd/2026-08-18-setup-assistant/task-2-report.md`.

### If interrupted here

Task 2 is fully done, verified, and about to be committed. Task 3 is next: append
`SetupAssistantGating.mm` to `SetupAssistantCore`'s sources and more tests to `t_setup_assistant.mm`
(append-only, per the pre-flight scan in `.superpowers/sdd/2026-08-18-setup-assistant/progress.md`).
Read that file's Task 3 self-consistency note first, and re-check any brief code block containing
an `@[ ... ]` literal inside an `OAK_ASSERT(...)` for the same unparenthesized-macro-argument trap
before assuming it compiles as transcribed.

---

## 2026-08-18 — Task 1 landed: the first committed Swift file

**What:** Executed Task 1 of `docs/superpowers/plans/2026-08-18-setup-assistant.md`. Created
`Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.h` (pure-ObjC boundary types --
`TMThemeChoice`, `TMBundleChoice`, the `TMSetupAssistantHost` protocol, and the two pure C
functions later tasks unit-test), `Applications/TextMate/src/TextMate-Bridging-Header.h` (two
imports, nothing else), and `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift`
(`TMSetupAssistantStep`, a plain `public` step enum) -- all transcribed verbatim from
`.superpowers/sdd/2026-08-18-setup-assistant/task-1-brief.md` and diffed byte-for-byte against its
code blocks before saving. Registered the Swift source and `SWIFT_OBJC_BRIDGING_HEADER` on the
`TextMate` target in `project.yml`, regenerated `TextMate.xcodeproj`, built clean with `bin/build`
(`** BUILD SUCCEEDED **`, zero `error:` lines), and confirmed
`~/build/textmate-revived/xcode/Release/TextMate.swiftmodule/arm64-apple-macos.swiftmodule` exists
-- the only real proof the file compiled rather than being silently absent from `sources`.

**Why:** This is the toolchain question settled *in a committed state*. The prior spike (see the
".25 published, and Swift proved to work in this tree" entry below) proved the same shape then
reverted it; Task 1 is that proof for real, on the branch, so nothing after it depends on a spike
that no longer exists.

One thing worth recording: the generated `TextMate-Swift.h` is 376 lines with zero `@interface` /
`@protocol` in it -- `TMSetupAssistantStep` does not appear there. That is expected, not a defect:
the spike already found `internal @objc` invisible to ObjC++, and a plain (non-`@objc`) enum is
invisible the same way, by design, since nothing in Task 1 needs it seen from Objective-C++. It is
consumed from Swift directly, starting at Task 5.

### If interrupted here

Task 1 is fully done, verified, and about to be committed. Task 2 is next: add the
`SetupAssistantCore` `library.static` target to `project.yml`, linked by both `TextMate` and
`TextMate_test`, holding the `.mm` that implements the types this task only declared plus
`t_setup_assistant.mm`, the first test file. Read `docs/superpowers/plans/2026-08-18-setup-assistant.md`'s
Task 2 section and `.superpowers/sdd/2026-08-18-setup-assistant/progress.md` first -- the latter
records two rulings from plan self-review that still apply.

---

## 2026-08-18 — RESUME HERE: Setup Assistant plan written, ready to execute

Plan at `docs/superpowers/plans/2026-08-18-setup-assistant.md` — eight tasks. Branch
`phase-6/swiftui-onboarding`, tree clean, **still no implementation**. Next action is executing
Task 1, not writing more documents.

### Ordering is by risk, not by feature

Task 1 lands the first `.swift` file in the repository and does nothing else. Task 4 proves the
window and modal session with an *empty* content view before SwiftUI is involved. Both exist because
this app has never done either thing, and a modal session whose window closes without calling
`stopModal` leaves the entire app unresponsive — far easier to diagnose alone than tangled into a
first SwiftUI integration.

### Planning found a real gap in the spec

`TextMate_test` compiles only the generated runner and links only what it declares, so the design's
promised tests for gating and marshalling were unreachable from where the design had put that code.
`PreferencesMigration` is the precedent: `library.static`, linked by both `TextMate` and
`TextMate_test`. `SetupAssistantCore` now follows it and holds exactly what is testable without C++
— boundary types, gating predicate, semantic-class mapping, never-suggest merge. The spec's Files
table was corrected to match rather than left contradicting the plan.

`Ruling: two errors were caught in plan self-review, both of which would have cost a build cycle
each. The tests asserted with to_s(NSString*), which is declared in Frameworks/ns and is not linked
by TextMate_test — the existing t_preferences_migration.mm uses isEqualToString: and that is now
copied. And bundles::kFieldSemanticClass was verified at item.h:26 rather than left as an
instruction to go look it up. Verifying two API names cost one command; discovering them at compile
time costs a full build each.`

### The one test worth naming

`TMMergeNeverSuggestIdentifiers` is now a tested function rather than inline code. Replacing instead
of merging that list resurrects every bundle suggestion the user has ever declined, and
`DocumentWindowController.mm:1231,1273-1274` is what reads it. Silent, user-visible, and easy to
write wrong.

### If interrupted here

Read the plan and start at Task 1. Do not re-plan. The two risks nothing has retired: this is the
first target to carry both `.swift` and `.mm` through a clean CI build, and SwiftUI initialising
inside a modal session before session restore is new ground for this app. Execution mode was not
chosen yet — subagent-driven or inline.

---

## 2026-08-18 — Setup Assistant designed and approved

Spec committed at `docs/superpowers/specs/2026-08-18-setup-assistant-design.md`. Branch
`phase-6/swiftui-onboarding`, tree clean, **no implementation written yet**. Next step is the
implementation plan, then TDD against it.

### What the design decided, and the one thing that changed the premise

Onboarding was described in HANDOFF as having "no existing implementation." That is true of
onboarding as a concept and false in a way that matters: `FirstLaunchBundleInstaller` already runs a
modal at `AppController.mm:592` offering default-tier bundles. So this is not new UI beside an empty
space — it replaces a single-purpose modal and absorbs its job. The class stays as the engine; only
its window is retired. `DocumentWindowController.mm:1231,1273-1274` reads
`kUserDefaultsBundlesToNeverSuggestKey` for the on-demand per-extension prompt, so the bundles step
has to keep writing it.

Three steps: welcome, appearance, bundles. Appearance is the step that earns the feature — theme
lives in `View → Theme` and nowhere else, which is exactly why an untouched `kMacClassicThemeUUID`
default read as lost settings earlier this month.

**The `mate` CLI step was cut by the maintainer.** It already installs from Settings → Terminal
(`TerminalPreferences.mm:265-288`). Keeping it would have meant extracting `install_mate()` from
file-static scope, duplicating an authentication flow, and proving a system auth dialog behaves over
an app-modal window. Cutting it removed the riskiest part of the island and the only change to
existing privileged code.

`Ruling: the bridge shape is dictated by the spike's measurements, not by taste. A bridging header
is parsed as C/ObjC and compiled without the prelude PCH, so neither C++ nor this tree's own
framework headers can cross it. ObjC++ therefore owns the window and every side effect; Swift owns
presentation and local view state only. Any design that put Swift in charge would have widened the
boundary, not narrowed it.`

### Two checks during spec self-review that were worth doing

- Claimed "twenty-two themes on a stock profile" when what was measured was **this** machine, which
  has 54 bundles installed. Corrected to state the measurement and its date rather than imply a
  floor.
- Verified rather than assumed that `gen_test.sh` globs `Applications/TextMate/tests/`. It does —
  `:29-31` falls back `Frameworks/<name>` → `vendor/<name>` → `Applications/<name>`. Had it not, the
  planned `t_setup_assistant.mm` would never have compiled and the suite would have reported green
  without running it.

### If interrupted here

The spec is approved but **no plan document exists yet**. Read the spec, then invoke
`superpowers:writing-plans`. Do not start writing Swift before the plan exists. The two risks the
spec names and neither the spec nor anything else has retired: this is the first target to carry
both `.swift` and `.mm` through a clean CI build, and SwiftUI initialising inside a modal session
before session restore is something this app has never done.

---

## 2026-08-18 — .25 published, and Swift proved to work in this tree

**PR #18 merged** as `a8bc6398`, branch deleted locally and on origin. That fired `release.yml` and
published **v3.0.0-revived.25**. Now on `phase-6/swiftui-onboarding`, tree clean, nothing in flight.

### Phase 6's one open question is answered: Swift compiles here

Settled by a throwaway spike on the `TextMate` app target — added a `.swift` file, called it from
`main.mm`, built, reverted. `CLANG_ENABLE_MODULES = NO` was the suspected blocker and **is not one**:
the Swift compiler's ClangImporter uses modules internally whatever that target-level Clang setting
says. `SWIFT_VERSION = 6.0` was already in `Base.xcconfig`, no other setting needed adding, and no
Swift runtime is embedded because it is ABI-stable in macOS 26.

The full contract now lives in `CLAUDE.md`. The two findings that would each have cost an afternoon:

- **`internal @objc` is invisible to ObjC++.** It compiles, reaches the `.swiftmodule`, and is simply
  absent from the generated `TextMate-Swift.h` — a 383-line header with zero `@interface` in it. The
  error surfaces as `use of undeclared identifier` at the *call site*, pointing at the wrong file
  entirely. Declarations must be `public`, not merely `@objc`.
- **A bridging header cannot see ObjC++, and cannot see this tree's ObjC either.** It is parsed as
  C/ObjC, so C++ is a syntax error rather than an unsupported feature; and it is compiled without
  `GCC_PREFIX_HEADER = prelude.mm`, so framework headers relying on the prelude for their AppKit
  imports fail on `NSImage`, `NSButton`, `BOOL`. The bridge has to be a narrow, self-contained,
  pure-ObjC shim. Verified working alongside `import SwiftUI`.

`Ruling: spiked the toolchain question before designing the onboarding island rather than after.
Cost was two incremental builds and a revert. The other order would have surfaced the
bridging-header constraint midway through an island already written against the app's real headers
— a rewrite rather than a fix.`

### If interrupted here

The onboarding island itself is next and **has not been designed yet** — brainstorm before writing
it. The proven-safe shape: ObjC++ owns the window and drives Swift through `TextMate-Swift.h`, while
Swift calls back out through a pure-ObjC protocol in a self-contained bridging header. Also confirm
the .25 release finished: `gh run view 32181270935 --repo sdenike/textmate`.

---

## 2026-08-18 — clean stop, PR #18 open, phase plan written down

**Nothing is in flight.** Working tree clean, `phase-6/quicklook-extension` pushed at `a9196f06`,
[PR #18](https://github.com/sdenike/textmate/pull/18) open against `master` with 8 commits.

**If interrupted here / on resuming:** read `HANDOFF.md`'s **Next** section — the whole remaining
phase plan now lives there rather than in a session that gets discarded. Then ask the maintainer
whether to merge PR #18 before touching anything else.

### Why merging PR #18 is not a docs decision

`release.yml` fires on a `CHANGELOG.md` push to `master`, and the `.25` entry is already in the
diff. Merging it signs, notarizes, staples, tags and publishes a release. The maintainer has not
authorised that. Do not merge it unprompted.

### What this session actually produced

Everything technical landed in the two blocks below — Quick Look via an app extension, the bounded
`path::passwd_entry()` loop, and the third recurrence of the resource glob bug now guarded by
`bin/verify_resources.sh`. This entry adds only the plan.

`Ruling: the remaining-phase plan was reported to the maintainer in chat and existed nowhere else.
Written into HANDOFF.md's Next section with the spec's own text quoted for each phase, so a fresh
session resumes without re-reading the design doc or the transcript. Cost if wrong: a stale plan
section, which is cheap to correct — against a whole session spent re-deriving it, which is not.`

### The one open technical question in Phase 6

`Xcode/Base.xcconfig` sets `CLANG_ENABLE_MODULES = NO`, and **no target in the tree has ever
contained a Swift file**. Whether Swift compiles here at all is untested. Onboarding is the right
place to find out — it is the only SwiftUI island with no existing AppKit implementation to reach
parity with, so a failure there costs nothing but the experiment.

### Memory written this session

`~/.claude/projects/-Users-shelby-Development-textmate/memory/` had three files and **no
`MEMORY.md` index**, so none of them were loading. Index created, plus two standing corrections that
existed only in conversation: no `Claude-Session` trailers or AI attribution in commits, and no
signing credentials (Team ID, Apple ID) in the public repo.

---

## 2026-08-18 — .25 ready on a branch, verified by the maintainer

Branch `phase-6/quicklook-extension`, 7 commits, **pushed but NOT merged**. Merging publishes
v3.0.0-revived.25 (`release.yml` fires on a `CHANGELOG.md` push to `master`).

### Verified working by the maintainer

- **Quick Look previews** render syntax highlighted (Space on a `.rb` in Finder).
- **Bundle Editor** works — its 8 xibs had never shipped.
- **Terminal settings pane** shows its own contents rather than the previous pane's.

### What was actually wrong — two independent bugs, both shipping for months

**QuickLook.** `.appex` requires EXACT UTIs where `.qlgenerator` matched by conformance, so
inheriting the old three-entry list meant macOS never invoked the extension at all. And
`path::passwd_entry()` (`Frameworks/io/src/path.cc`) had an unbounded retry loop around a modal
alert; sandboxed, `access(pw_dir, R_OK)` fails on a valid home and the alert cannot display, so it
spun at 100% CPU forever. **That would hang any non-interactive caller** — `mate`, `tm_query`, the
test runners — not just this extension.

**Resources.** `assemble_resources.sh` globbed only `*.png`, `*.pdf`, `*.tiff`, so since Phase 2
every other framework resource was dropped: 12 uncompiled xibs (Terminal prefs, all 8 Bundle Editor,
encoding customisation, tab-size picker, pasteboard selector), `Charsets.plist`, `svn_status.xslt`,
`bindings.plist`, 36 `.icns`, HTMLOutput js and error page. 164 -> 216 files in `Contents/Resources`.
`TMFileReference`'s icons needed `Resources/DocumentTypes/`, recovered from its deleted
`default.rave` at `d07cc0c8^`.

`Ruling: this was the THIRD time this glob was wrong and the first not about images. Each time a
user found it, never the build. bin/verify_resources.sh now does a full set-difference at build time
and fails when a framework resource does not ship. A threshold check is useless here; only set
comparison works.`

Also corrected `CLAUDE.md`'s own collision check — it used `xargs -n1 basename`, which splits on
spaces and false-positives on names like "Bookmark Hover Add Template.pdf". Now NUL-delimited.

### Diagnostic lessons that cost real time here

- **`log show` returns NOTHING in the agent sandbox.** Reading its silence as "the extension never
  ran" misdirected two full rounds. Verify the tool works before trusting a negative.
- **A sandboxed extension's container is created at registration, not first run**, so its existence
  proves nothing about execution. Write a marker file inside it instead.
- **`sample <pid>` on the live process is what actually found the hang** — 1,859 of 2,156 samples in
  `path::passwd_entry()`.
- Two previous agents wasted effort trying to synthesise GUI input with `cliclick`/System Events.
  It does not work here. Ask the maintainer.

### The white-theme question — resolved, not a bug

`universalThemeUUID` matches `kMacClassicThemeUUID`, which `AppController Menus.mm:68` registers as
the **default**; `themeAppearance = light`; `darkModeThemeUUID` unset. That is an unchanged default
configuration, not lost settings. Theme lives in **View -> Theme** (a menu, not a Settings pane),
which also carries Auto/Light/Dark. Picking a theme while in Auto/Dark sets `darkModeThemeUUID`,
which is the same key the Quick Look extension reads.

### Open

- **Quick Look preview theme** — uses `universalThemeUUID`, so a light editor theme looks wrong on
  Quick Look's dark chrome, and `darkModeThemeUUID` is consulted in dark mode even when unset. Wants
  its own preference. Recorded as a known gap in `2dda56c3`.
- `BundleEditor/templates/*.plist` (8 files) — the old `.rave` shipped them, no current code
  references them, deliberately left unshipped rather than copied blindly.

### If interrupted here

1. Merge the branch when ready — that publishes .25.
2. Then Phase 6 remainder: onboarding is the cheapest first SwiftUI island, and proves the
   `CLANG_ENABLE_MODULES = NO` interaction before committing to the larger ones.
3. Phase 8 (shared modules) and 9 (optional LSP) after.

## 2026-08-18 — QuickLook works; a Phase 2 resource regression found

Branch `phase-6/quicklook-extension`. **Release deliberately held** — the maintainer asked to polish
before shipping, and that call surfaced a much larger bug than the one being polished.

### QuickLook works, verified by the maintainer

Space-bar on a `.rb` file renders syntax highlighted. Instrumented build reached
`STYLED: producing UTTypeRTF` rather than either plain-text fallback. Two real defects fixed:

- **`.appex` requires EXACT UTIs.** `.qlgenerator` matched by *conformance*, so its three-entry list
  (`public.source-code`, `public.plain-text`, `public.text`) covered everything beneath. An
  extension gets no such treatment — `sample.rb` is `public.ruby-script` and matched none of them,
  so macOS never invoked us. Now declares ~165 exact UTIs enumerated from `lsregister`.
- **`path::passwd_entry()` looped forever.** It retries `getpwuid` around a modal alert until
  `access(pw_dir, R_OK)` succeeds — unbounded, because it assumes a human is answering. Sandboxed,
  `access()` fails on a perfectly good `/Users/<name>` and the alert cannot display, so it spun at
  100% CPU. **That would hang any non-interactive caller** — `mate`, `tm_query`, the test runners.
  Now bounded, and the home root is granted read-only so the check passes.

### THE BIGGER FIND — resources have been missing since Phase 2

The maintainer reported the Settings **Terminal** pane showing the previous pane's contents. Root
cause: `TerminalPreferences.xib` — the only xib in the Preferences framework, every other pane being
built in code — **was never compiled or copied**. No nib means an empty view, `fittingSize` of
`0 x 0`, and `OakTransitionViewController` pins the incoming pane to zero size while the outgoing one
stays visible. Title and toolbar update, so it looks like a click that did not register.

Auditing outward found the same root cause everywhere: `assemble_resources.sh` globs only
`*.png`, `*.pdf`, `*.tiff`, so **every other resource type in every framework has been dropped since
Phase 2**:

| Missing | Referenced by |
|---|---|
| 11 more xibs — Bundle Editor (8), `CustomizeEncodings`, `Pasteboard Selector`, `TabSizeSetting` | never compiled at all |
| `Charsets.plist` | `OakEncodingPopUpButton.mm` |
| `svn_status.xslt` | `scm/src/drivers/svn.cc` |
| `bindings.plist` + 36 `.icns` | `TMFileReference.mm` |
| `HTMLOutputWKWebView.js`, `error_not_found.html` | `HOBrowserView.mm` |

`Ruling: this is the THIRD time this glob has been wrong -- CLAUDE.md already records it matching
only gfx/*.png, then missing 40 PDFs. A fix alone is not enough; the widening must come with a
build-time set-difference check that fails when a framework resource does not ship. A threshold
check ("at least N files") is explicitly useless here and the docs already say so.`

### Not regressions from this branch

`path::passwd_entry()`'s new bound is inert for the app: it is unsandboxed, `access()` succeeds
first time, and the Preferences code never calls `path::home()` at all. The Preferences sources are
untouched since the Phase 1 merge.

### Open, not addressed

- **QuickLook theme.** The preview uses `universalThemeUUID` — a light theme against Quick Look's
  dark chrome looks wrong — and consults `darkModeThemeUUID` in dark mode even when unset. Wants a
  dedicated preview-theme preference. Recorded as a known gap in `2dda56c3`.
- **The maintainer's editor theme showed white.** `themeAppearance = light` with
  `darkModeThemeUUID` unset while the system is dark. Nothing on this branch writes those keys, but
  the prefs file carries a `com.apple.macl` xattr proving the sandboxed extension read that domain,
  so a side effect cannot be ruled out. Unresolved.

### If interrupted here

1. Finish the resource fix + its verification check, then re-test Settings panes and the Bundle Editor.
2. Only then merge (publishes v3.0.0-revived.25).
3. Theme picker for QuickLook previews after that.

## 2026-08-17 — QuickLook extension built, needs one human check

Branch `phase-6/quicklook-extension` at `2785d96b`. **Not merged.** Merging publishes
v3.0.0-revived.25.

### What landed

The dead `TextMateQL.qlgenerator` is gone; `Contents/PlugIns/QuickLookExtension.appex` replaces it.
Principal class conforms to `QLPreviewingController` and implements
`providePreviewForFileRequest:completionHandler:`, ported from `GeneratePreviewForURL`'s body with
the four helpers unchanged. Sandboxed (`app-sandbox` + `files.user-selected.read-only`), matching
Apple's own template and Safari's shipped `.appex`.

Registration confirmed: `pluginkit -m -p com.apple.quicklook.preview` lists
`com.shelbydenike.TextMate.QuickLookExtension(3.0.0-revived.24)`.

### Two corrections about the tooling — worth knowing before testing anything QuickLook

**`qlmanage -m plugins` cannot see app extensions at all.** I set that as the verification gate and
it was the wrong gate. Safari's own `.appex` is equally absent from it; that command's man page
predates app-extension QuickLook by 14 years. **Use `pluginkit -m -p com.apple.quicklook.preview`.**

**`qlmanage -p` crashes on any `.appex`** — `NSInvalidArgumentException` in
`EXConcreteExtension makeExtensionContextAndXPCConnectionForRequest:`. Reproduced identically
against Apple's own `com.apple.osanalytics.IPSExtension`, so it is a broken system tool, not our
code. There is **no CLI route to prove a preview renders**; Finder's Space-bar preview is the test.

The original "QuickLook is broken" diagnosis still stands: `.qlgenerator` is the legacy type
`qlmanage -m plugins` *does* enumerate, and it listed every Apple generator while omitting ours.

### THE OPEN QUESTION — one Finder keypress answers it

`initialize()` reads grammars and themes from `~/Library/Application Support/TextMate/` and
`~/Library/Caches/`. **A sandboxed extension may not reach them**, and the pre-existing
`fileType == NULL_STR` / `!output` fallback degrades to plain text rather than failing loudly. So:

| Space-bar a `.rb` in Finder | Meaning |
|---|---|
| syntax-highlighted, themed | fully working |
| plain unstyled text | renders, but the sandbox is blocking grammars/themes |
| nothing, or a generic icon | not rendering |

The middle case is silent and plausible. If it happens, the fix is an entitlement or embedding a
minimal grammar set — but it has to be observed first.

### If interrupted here

1. Get that Finder check done, then merge (publishes .25).
2. Phase 6 remainder after that: onboarding as the first SwiftUI island is the cheapest way to prove
   the `CLANG_ENABLE_MODULES = NO` interaction before committing to the larger islands.
3. Scope bar and back/forward need **no work** — already done since 2014 and 2018.
4. Do not adopt `NSRulerView` for the gutter; do not port #1469/#1467.

## 2026-08-17 — .24 shipped; Phase 6 found to be incomplete

### v3.0.0-revived.24 is out and verified

PR #17 merged (`643ad295`), release published and checked end to end — not merely trusted from the
workflow's exit code:

```
sha256   eaaad58219f0f4b2d3427624017c4b40ff8c095ef789879b45c895fbe8da7099
cask     same sha256                                    -> brew upgrade works
signing  Developer ID Application: Shelby Denike (485WH9DHS4)
spctl    accepted, source=Notarized Developer ID
stapler  The validate action worked!
bundle   26,076 KB   (undead: 27,928)
```

Also: `/Applications/TextMate.app` currently holds the **ad-hoc** test build, because
`bin/deploy-local` was run during tab testing and it *moves* rather than copies. Check for Updates
will correctly refuse there. `brew upgrade --cask textmate-revived` restores a signed install.

Replied to schriftgestalt on PR #15 crediting the drag-rearrange fix, and asked for his view on
title-bar tabs rather than treating that objection as settled.

### PHASE 6 WAS CLOSED EARLY — it is not complete

Closing it was based on `NSVisualEffectView` being gone from the tree. That is the **glass
criterion, not the phase**. The spec's Phase 6 paragraph is far wider, and this was found only by
reading it back when the maintainer asked what was next.

Sized afterwards; full survey at `$CLAUDE_JOB_DIR/tmp/phase6-scope.md`. **Three entries in the first
version of this table were wrong** and are corrected here.

| Spec item | Status | Size |
|---|---|---|
| Tahoe tab bar | done | — |
| `NSGlassEffectView` on chrome | done | — |
| Scope bar | **already done — `OakScopeBarView`, 2014, five live callers** | none |
| Back/forward navigation | **already done — `goBack:`/`goForward:`, 2018, menu-wired** | none |
| **QuickLook extension** | **BROKEN IN SHIPPED BUILDS, not merely deprecated** | medium |
| SwiftUI island: onboarding | not done, and no existing implementation to match | small-medium |
| SwiftUI islands: Preferences, About, update sheet | not done — ~1,945 lines of working AppKit to reach parity with | large |
| `NSSplitViewController` sidebar | not started — earlier "partial" was a false positive | large, defer |
| `NSRulerView` gutter | not done | large, **do not do** |

**QuickLook is dead, not dying.** `qlmanage -m plugins` does not list `TextMateQL` even after a
forced `qlmanage -r`, though the bundle is on disk. Every callback `generate.mm` uses carries
`API_DEPRECATED(..., macos(10.0, 12.0))` in the current SDK. **Users have no preview today.**

**Corrections to the earlier table:** scope bar and back/forward were never missing — both predate
this fork by a decade and match the spec's wording by coincidence. The sidebar's "1 file" was
`BundleEditor.mm` (2021, upstream), the Bundle Editor's *own* internal split, nothing to do with the
file browser.

**#1469/#1467 will not port.** #1469 is `+19,490/−5,877` across 550 files and adds whole new
applications — the Liquid Glass spec already ruled it out as not lifting out as a single piece.
#1467's `OakSwiftUI` was built against a tree that had deleted `SoftwareUpdate` and `CrashReporter`,
so its views do not correspond to anything here. Write from scratch.

**Swift is pre-wired but unproven.** `Xcode/Base.xcconfig:59-61` already sets `SWIFT_VERSION = 6.0`,
commented as being there for exactly these islands. The landmine is `CLANG_ENABLE_MODULES = NO` at
`:43-57`, marked "REQUIRED off, do not remove" after an xdiff/Darwin module collision — Swift↔ObjC++
interop normally wants modules on. **Prove that interaction before committing to any SwiftUI work.**

`Ruling: a phase closed against one of its criteria is not a phase closed. Phases 0-5 and 7 stand;
Phase 6 is reopened as a remainder. Read the spec paragraph before declaring any future phase done,
not the criterion you happened to be working on.`

### Note on Phase 8's sequencing

Phase 8 extracts `RevivedUpdater`/`RevivedGlass`/`RevivedSettings` into a SwiftPM package for other
apps, and its own spec says to *"extract only what a second app demonstrably needs"*. No second app
consumes them yet, so that requirement is currently unknowable — designing the API now means
guessing at every caller but one. The Phase 6 remainder is concrete by comparison.

## 2026-08-17 — tab drag reworked; PR #17 merged

### PR #17 is open and CANNOT merge yet

`phase-7/performance` is pushed; PR #17 is open against `master`. **CI's test job failed** —
`scm_test` hung and the job hit its 30-minute limit:

```
Terminate orphan process: pid (24129) (scm_test)
```

`master`'s own CI was green before this branch, so it is either new or flaky. A rerun was started;
its result is the gate. Locally `scm_test` exits 0 but prints a hint referencing `ninja scm/coerce`
— **stale, ninja was removed in Phase 2** — and wants `subversion`, which it skips without.
Worth cleaning that message up regardless.

**Merging PR #17 publishes v3.0.0-revived.24**, because `release.yml` fires on a push to `master`
touching `CHANGELOG.md`. Do not merge casually.

### TEAR-OFF WAS BEING SWALLOWED BY OTHER APPS — fixed

Maintainer: *"When I try to drag a tab off the main window it simply pasted a path into this terminal
and did not make a new window with that tab."*

Not a bug in the new code — a **fundamental conflict with long-standing upstream behaviour**.
`OakTabItem` writes `kUTTypeFileURL` to the pasteboard alongside the internal type, and
`sourceOperationMaskForDraggingContext:` returned `Copy|Generic` for
`NSDraggingContextOutsideApplication`. So Terminal, Finder or any app that accepts files takes the
drop and pastes the path — which sets a non-None operation, and tear-off is guarded on
`operation == NSDragOperationNone`.

**The two cannot both work for one gesture**, and whichever app happened to sit behind the window
decided which you got. Predates this fork (`503d493f` only moved the file).

`Ruling: maintainer chose tear-off. sourceOperationMaskForDraggingContext: now returns
NSDragOperationNone for NSDraggingContextOutsideApplication. The file URL stays on the pasteboard --
in-application destinations go through the WithinApplication context and are unaffected, so dropping
a tab into OakTextView to insert its path, and onto the file browser, both still work. What is lost
is dragging a tab into another application to hand it the file.`

### Tear-off FEEL fixed after live testing (`7af7b720`)

Maintainer tested `f01d67d0` and reported: *"it does work but not very smooth, no indication that its
going to create a new window from the tab. And it loses focus so its not obvious what is happening."*
Three distinct causes:

**Snap-back was the "not smooth".** `NSDraggingSession.animatesToStartingPositionsOnCancelOrFail`
defaults to **YES** (verified in `NSDraggingSession.h` — note: *not* `NSDragging.h`, which only
forward-declares the class). Tear-off ends with `NSDragOperationNone`, so AppKit rubber-banded the
tab image back to the drag's origin and only then showed the new window. Now set to `NO` while past
the threshold, toggled on transitions only.

**No affordance was my own omission.** The first implementer flagged that it had skipped the
drag-image change and I accepted that in favour of "threshold correctness". Wrong call — a threshold
you cannot see is indistinguishable from a bug. The drag image now swaps to a synthetic
window-shaped image past 60 pt, via
`enumerateDraggingItemsWithOptions:forView:classes:searchOptions:usingBlock:` plus
`setDraggingFrame:contents:` (header: *"Any changes made to the properties of the draggingItem are
reflected in the drag"*). Both images are built **once** in `didDragTabView:` and the enumerate call
fires only on the threshold transition — `movedToPoint:` runs continuously and rebuilding per-move
would add the very stutter being removed.

**Focus had a precise cause, not the one I guessed.** `closeTabsAtIndexes:` was already the last
call; the problem is that its `activate:YES` re-selects a remaining tab in the *source* window via
`openAndSelectDocument:activate:YES` -> `makeTextViewFirstResponder:`, handing focus back, with
nothing after it to correct that. Fixed with an explicit `[controller.window makeKeyAndOrderFront:self]`
as the true final line.

`Note: that agent ran bin/deploy-local, which MOVES the build. /Applications/TextMate.app is now
the ad-hoc v3.0.0-revived.24 test build and ~/build/.../Release/TextMate.app no longer exists.
Consequence: Check for Updates will refuse, correctly, because an ad-hoc build has no team
identifier. brew upgrade --cask textmate-revived restores a signed install.`

### Tab drag: reviewer feedback fixed (`f01d67d0`)

schriftgestalt on PR #15: *"having the tabs to drag off like that makes it very difficult to
drag-rearrange tabs. Let the tab move horizontally and start the drag off only if the mouse is some
distance from the tabbar (like Safari is doing it)."*

**The key structural fact:** reorder and tear-off are phases of **one** `NSDraggingSession` started
at `OakTabBarView.mm:1002`. Tear-off is not a separate gesture — it is the fallback taken only when
nothing accepted the drop (`operation == NSDragOperationNone`), evaluated once at release. There was
no live distance signal anywhere in the file.

Fixed by replacing the window-frame test with distance from the **tab bar's own rect**, threshold
60 pt, measured to the rect not its centre so horizontal travel along the bar contributes nothing.
`draggingSession:movedToPoint:` records the state continuously, so dragging out and back cancels it.

**Unverified by drag.** This sandbox cannot synthesise a sustained mouse-down/move/up. Four gestures
need a human: sideways reorder, short drag below the bar, long drag to tear off, drop onto a second
window's bar.

`Ruling: a previous agent claimed to have verified tab behaviour in the running app, but had
launched /Applications/TextMate.app -- an older installed release, not its own build. Always confirm
CFBundleShortVersionString and binary mtime before believing any GUI verification claim.`

### Already working, do not rebuild it

**Dragging a single tab onto another window's tab bar and releasing already merges it** —
`performDragOperation:` (`OakTabBarView.mm:1093`) to `performDropOfTabItem:fromTabBar:index:toTabBar:index:`
(`DocumentWindowController.mm:1849`). `registerForDraggedTypes:` is per-instance and unscoped, so
AppKit already routes cross-window drags.

### Window-onto-tabbar merge landed (`9e9162fc`) — UNVERIFIED, test this first

Drag a whole window over another window's tab bar, hold 1.0 s, its tabs merge in.

**Hooked via `windowDidMove:`**, an `NSWindowDelegate` method `DocumentWindowController` already
conforms to — not `NSNotificationCenter`. `performWindowDragWithEvent:` hands the drag to the window
server and returns immediately (its own SDK header says so), so there is no completion callback;
`windowDidMove:` fires continuously during that drag because it is the same underlying mechanism as
ordinary titlebar dragging.

**The safety gate that makes this non-destructive:** armed only when
`NSEvent.pressedMouseButtons & 1` — session restore, cascade and zoom all fire `windowDidMove:` too,
and without that gate restoring a session could silently consolidate windows.

Feedback is a `controlAccentColor` border on the target bar (`OakTabBarView.mergeTargetHighlighted`);
there is no live `NSDraggingSession` to reuse the existing drop feedback, because a window is moving
rather than a tab. Merge reuses `insertDocuments:atIndex:selecting:andClosing:` — the same primitive
single-tab cross-window drop uses — inserting **before** closing the source window, with
`andClosing:nil` so nothing is discarded.

**The unsaved-document risk resolves, by design rather than luck.** `windowShouldClose:`
(`DocumentWindowController.mm:740`) does prompt for any document where `isDocumentEdited == YES` —
but `mergeIntoWindow:` calls **`[self.window close]`, not `performClose:`**, and AppKit's `close`
does not invoke `windowShouldClose:`. So no prompt fires for a document that has already moved.
Ownership has transferred before the close: the target controller retains the `OakDocument`s, so
`windowWillClose:` setting `self.documents = nil` on the source is harmless. Unsaved state lives in
the document, not the window, and moves with it.

This is the same `[delegate.window close]` pattern `mergeAllWindows:` has always used, so it is
consistent with existing behaviour rather than a new assumption. **Still worth exercising once with
a genuinely dirty buffer** — the reasoning is sound but unobserved.

### Open design question, not blocking

schriftgestalt also objected to tabs in the title bar at all: *"There is not one properer mac app
that is doing this."* The maintainer has since used it and kept it. Worth a considered decision
rather than leaving it implicitly settled.

### If interrupted here

1. **Get CI green**, then decide whether to merge PR #17 (which releases .24).
2. Finish or discard the window-merge gesture.
3. Get a human to exercise the four tab-drag gestures above.
4. Phase 8 (shared modules) and Phase 9 (optional LSP) remain.

## 2026-08-16 — Phase 7 closed, released as .24, everything in sync

Phase 7 is done and merged. `HANDOFF.md` is the polished snapshot; this file keeps the evidence.

### Two audits the maintainer asked for, both answered

**The Legal page: all four credits stay.** Onigmo (BSD-2), kvdb (MIT), xdiff (LGPLv2.1) and
Dialog/Dialog2 (repo GPLv3) are each present, compiled into the app target, linked, **and actively
called** — `regexp.cc:35` `onig_new()`, `Favorites.mm:15`, `gutter_diff.cc:192` `xdl_diff()`, and the
two embedded `.tmplugin`s. Each licence carries an attribution clause. The reverse sweep found
nothing shipped-but-uncredited; the only uncredited LICENSE in the tree is `bin/CxxTest`, which no
target compiles and no header path references (our runner is a home-grown reimplementation), so it
needs no credit.

**The `mate` CLI needs no separate optimisation.** `mate`, `tm_query` and `CommitWindowTool` all
inherit the project-wide flags with **zero overrides** — same `-Os`, thin LTO, dead-stripping,
arm64-only, hardened runtime as the app. And `mate` is a thin client: it posts a file-open request to
the running app over a Unix domain socket (`/tmp/textmate-{uid}.sock`, `Applications/mate/src/mate.mm`)
and does no real work itself, so its own speed is not a lever. It reaches `PATH` via the Terminal
preferences pane (`TerminalPreferences.mm:134`), offering `/usr/local/bin` or `~/bin`.

### Test baseline — know which failures are expected

- `buffer_test` **23/26**: three pre-existing spellchecking failures at `t_buffer.mm:117,136,151`.
- `settings_test` **passes in parallel, fails 1/9 under `--no-parallel`** — the documented flake;
  `t_track_paths.cc` needs real wall-clock time to pass between filesystem operations.
- scope, bundles, document, regexp, io, text, plist: all pass.

Anything else is a regression.

### If interrupted here

1. Phase 8 (shared modules) and Phase 9 (optional LSP) are what remain.
2. Before more micro-optimising: **the whole file is parsed at open, not the visible region**
   (`set_grammar` dirties the entire buffer, `buffer.cc:202`; batching stops at EOF, never at the
   viewport). That is the next real lever and a bigger change than anything in Phase 7.
3. The machine drifts badly — identical builds varied 28% across three rounds today. Any further
   perf work needs a quiet machine or it cannot be measured.

---

## 2026-08-16 — Phase 7, the levers are not where the spec said

Branch **`phase-7/performance`** (4 commits, unpushed). `master` is back at `origin/master`; two
Phase 7 commits had landed on it directly by mistake and were moved off. No PR yet.

### The two findings that reframe Phase 7

**1. The build is compiled for size, not speed.** `Xcode/Base.xcconfig` sets
`GCC_OPTIMIZATION_LEVEL = s`. `-Os` is precisely the flag that tells clang to suppress the inlining
and unrolling that make hot loops fast, and TextMate's hot loops are `oak::basic_tree_t`, the layout
engine and Onigmo's scanner — what a user feels when typing and scrolling.

Meanwhile the design doc named LTO and dead-stripping as Phase 7's levers. Both were **already on**
before Phase 7 began (`LLVM_LTO = YES_THIN`, `DEAD_CODE_STRIPPING = YES`). The one flag that
actually trades speed for size pointed at size, and nobody had looked.

`Not yet tested. -Os -> -O2 must be measured, not assumed -- assuming is what produced the
wrong-sign benchmark recorded in the entry below.`

**2. Bundle size is dominated by resources, not by binaries.**

```
55 document .icns   10040 KB   36%      <- largest single category, ~177 KB each
main TextMate        6040 KB   22%
Assets.car           2836 KB   10%
About/Contributions  1536 KB    6%      <- removed today
QuickLook+Bundles    4464 KB   16%
everything else      2788 KB   10%
```

Dead-strip and LTO act on `MacOS/` (7072 KB). `Resources/` is 15460 KB — more than twice that.

**Sequencing that follows from these two:** the size gate had only 224 KB of slack against `undead`
(27704 vs 27928). `-Os -> -O2` typically costs 10-20% of code size, which on a 6 MB binary would
blow that gate outright. Shrink first, then spend. Removing Contributions bought 1536 KB of room.

### Done today

| Commit | What |
|---|---|
| `3b59b4eb` | Removed the About window's Contributions page, `bin/gen_credits.rb`, its CSS and JS; added a contributors link to `About.md` |
| `ad635a95` | Dropped stale Contributions references from `bin/build`, `README.md`, CI workflow |
| `6915872e` | Corrected the fork's bundle id in `measure.sh` and the Phase 0 baseline |

**Why Contributions went, beyond the 1536 KB:** `bin/gen_credits.rb` called `api.github.com`
*during the build*, making builds non-hermetic and differently broken offline; the About window
fetched an avatar per contributor over the network when displayed; the page listed every commit in
the repo, so it grew without bound (26,887 lines). Its removal also deletes the DBM-cache failure
mode CLAUDE.md documented at length. Contributors are still credited — `About.md` now links
`/graphs/contributors` and `/commits/master`, which matters because that page was the only place in
the shipped app the ~26 upstream contributors were named at all (`Legal.md` names *framework*
authors, a different set).

### Two traps found, both worth not re-walking

**`xctrace --launch <path>` resolves through Launch Services by bundle id, not by the path given.**
Three Instruments runs aimed at the build tree profiled `/Applications/TextMate.app` instead,
confirmed from each trace's own `<process path=...>`. The launch profile is therefore **still
unmeasured**. To fix: copy the build to a scratch path with a distinct `CFBundleIdentifier` so
Launch Services can resolve it uniquely, then `--launch` that copy.

**The fork's bundle id is `com.shelbydenike.TextMate`, not `com.macromates.TextMate`.** Two
documents still said otherwise. This inverts which collision to guard against: there is now no
collision with `official`/`undead` at all, and the one that does bite is a `bin/deploy-local` copy
in `/Applications` sharing the id with the build under measurement. `measure.sh` itself needed no
change — it matches on executable name, not id — so the recorded launch numbers stand.

### Two GUI benchmarks cannot run concurrently

I dispatched the launch profiler and the large-file-open harness at the same time; both drive the
same app, and the profiler correctly stopped when it found the other one's `measure-open.sh` mid-run
rather than killing a process it had not started. Sequence GUI measurements one at a time.

### THE REAL FINDING — a 1 MB file takes 19-118 seconds to open

Large-file open, the gate metric left unmeasured through six phases, was finally measured. Opening
a **1 MB** C file pegs the CPU at 100% for **19-118 seconds**. A comment-only 1 MB control file
takes the same ~90 s, so it is not symbol count. This — not launch time, not bundle size — is what
"slow and clunky" means.

A 1 ms `sample` of the stalled process puts **1,774 of 2,475 main-thread samples (72%)** here:

```
ng::buffer_t::initiate_repair -> update_scopes -> did_parse
  -> ng::symbols_t::did_parse          symbols.cc:111
    -> bundles::value_for_setting      wrappers.cc:188
      -> query -> search -> scope::types::path_t::does_match
```

**Root cause, in one function.** `value_for_setting` already memoizes, with correct invalidation via
`bundles_did_change`. Both defects are in keying and bounding:

- the cache key was `setting + "\037" + to_s(scope)` — **built on every call, including hits**.
  `to_s` walks the whole node chain and allocates; `scope::scope_t::to_s_helper` appears ~1,900
  times in the sampled stacks. Meanwhile `scope_t::hash()` (`scope.cc:178`) is
  `return node ? node->_hash : 0` — an O(1) read of a field computed once at construction.
- `if(cache.map.size() > 1000) cache.map.clear()` — **discards the entire cache**, so a large file
  fills it, wipes it, refills it, degenerating to no caching exactly when caching matters.

### THE FIX WAS TRIED AND IT IS 13x WORSE — do not retry it

Attempted: `std::unordered_map` keyed on `(setting, context_t)` using `scope_t::hash()`, no string
built at all, bound raised 1000 -> 50000. **Measured, twice, by two operators, on the 1 MB file:**

```
before (unfixed)   15597 / 15559 / 15405 ms      median 15559 ms   (also 16505/16314/17061 earlier)
after  (fixed)     timeout:200s x 3              never completed a single timed run
```

Baseline provenance was verified rather than assumed: `nm` shows **0** `key_hash` symbols in
`/private/tmp/tm-before` and **5** in `tm-after`, so the two binaries genuinely differ by this
change and nothing else.

**Why it failed — `scope_t::hash()` is not safe to bucket on.** `scope.cc:16`:

```cpp
_hash(std::hash<std::string>()(atoms) ^ (parent ? parent->_hash : 0))
```

XOR is self-cancelling, and scope paths repeat atoms whenever constructs nest — `meta.block.c`
inside `meta.block.c` is ordinary C. Each repeated pair cancels to zero, so large families of
distinct scopes collapse onto one hash value. Harmless as a change-detector, which is presumably
why it survived; fatal as an `unordered_map` key, because entries pile into shared buckets and every
lookup degenerates to a linear walk resolved by `operator==`. Raising the bound to 50000 made those
walks fifty times longer.

**The expensive string key was load-bearing.** `std::hash` over the serialized scope distributes
properly; the cached `_hash` does not.

`Ruling: reverted. Change preserved as stash@{0} and as
$CLAUDE_JOB_DIR/tmp/cachefix.patch, for reference only -- do not reapply as-is. The 72% hot-path
diagnosis stands (measured three independent ways); only this remedy is disproven.`

### THEN THE RIGHT EXPERIMENT RAN — bound alone, 2.7x faster

**I had misread my own profile.** Of the 1774 samples in `value_for_setting`, **1770 are below it**
in `query`/`search`/`does_match` — the *miss* path. Only a handful are in `to_s` and the map lookup.
The `to_s_helper` frames I seized on were deep in the recursive stack, not the leaf cost. The string
key was never the bottleneck; **the cache missing was**. The failed experiment changed key *and*
bound together, and the bad hash swamped whatever the bound bought.

Changing **only** the bound, string key untouched (`wrappers.cc`, 1000 -> 50000):

```
before (bound 1000)   15597 / 15559 / 15405     median 15559 ms
after  (bound 50000)  15961 /  5820 /  5802     median  5820 ms
```

**Read the shape, not the median.** With the old bound all three runs are identical ~15.5 s — the
cache filled, wiped, and every open started cold. With the bound raised, run 1 is unchanged (~16 s,
populating the cache) and runs 2-3 drop to 5.8 s. The cache now survives between opens instead of
destroying itself. That is the thrash hypothesis confirmed directly.

Honest scope of the win: the **first** file opened in a session is unchanged at ~16 s; every file
after it is **2.7x faster**. Provenance verified — the bound-only build has 0 `key_hash` symbols.

**5.8 s for a 1 MB file is still bad.** Root cause now established by instrumentation, below.

### ROOT CAUSE OF THE REMAINING COST — instrumented, not inferred

Temporary counters were added to `value_for_setting` (calls, misses, clears, per-setting breakdown),
built, and run against two 1 MB files. **The instrumentation has been removed; the tree is back at
the committed 50000 bound.**

| setting | synthetic 1 MB | real 1 MB C++ (28,510 lines of this repo) |
|---|---|---|
| `showInSymbolList` | 47,684 calls / **38,374 misses** | 114,606 calls / **61,346 misses** |
| `softWrap` | 150,371 calls / 52 misses | 280,369 calls / 74 misses |
| `foldingStartMarker` | 109 calls / 50 misses | 218 calls / 73 misses |
| totals | 200,000 calls / 40,132 misses / 0 clears | 400,000 calls / 64,882 misses / **1 clear** |

**The arithmetic.** 53 bundle settings items declare `showInSymbolList`, with 53 distinct scope
selectors, and `cache_search` evaluates every one of them per miss. So a real 1 MB file costs
**61,346 x 53 = ~3.25 million scope-selector evaluations**, on the main thread.

**Why so many distinct scopes:** nesting *extends the scope path*, so deeply nested code produces
unboundedly many distinct scope strings — roughly two new scopes per line of real C++. Caching
cannot fix this; the misses are genuinely new lookups. Note the real file **cleared even the 50000
bound once**, so real source is worse than the synthetic test file, not better.

**Ruled out by the same data — do not re-investigate:**

- `folds.cc` — 218 calls, not per-line. An earlier survey and my own per-line theory were both wrong.
- `softWrap` — 280,369 calls but only 74 misses, so essentially all cache hits. Matches the sample
  showing almost no time in `to_s`.
- `item_t::does_match` (`item.cc`) — lean, a multimap range scan, no allocations.
- `scope_t::operator==` against `scope::wildcard` — short-circuits in O(1) when the wildcard node is
  null, so the guard before the matcher is not the cost.

The cost is genuinely `scope::selector_t::does_match`, which the sample independently confirms
(8,237 of 11,344 main-thread samples in `composite_t::does_match` and below).

**Concrete fix design for next session — a root-atom pre-filter.** Selector roots across the 53:
`source.*` 33, `meta.*` 9, `entity.*` 6, `text.*` 2, `support.*` 1, `constant.*` 1, wildcard 1.
**35 of 53 are rooted at `source.*`/`text.*`**, so a single atom comparison against the query
scope's root can reject about two thirds of candidates before running the recursive matcher. The 18
non-language-rooted selectors must stay in every bucket, so expect ~2.5-3x on the dominant cost, not
more. Bigger win, bigger risk: stop computing the symbol list synchronously during the initial parse
at all.

### DEFERRAL SURVEY — what is and is not on the critical path

Full survey at `$CLAUDE_JOB_DIR/tmp/deferral-survey.md`. Headlines:

**Parsing is already off the main thread; the expensive part is not.** `initiate_repair`
(`parsing.cc:55`) dispatches grammar parsing to a global queue, but the completion is bounced back
via `CFRunLoopPerformBlock` to the **main** run loop every ~10-20 lines, and that completion is what
runs `did_parse` -> `symbols_t::did_parse` -> the settings lookups. So millions of selector matches
land on the main thread in thousands of slices, for the whole file.

**The symbol list is genuinely deferrable.** Every consumer that can block is user-initiated
(Jump to Symbol, the status-bar popup, QuickLook), and they already call `wait_for_repair()`
themselves before reading. The only consumer firing automatically at open is `updateSymbol`
(`OakTextView.mm:3587`), a cheap non-blocking `upper_bound` read. So `symbols_t::did_parse` computes
the full cost for every buffer whether or not anything ever asks. **Not yet implemented** — it is a
visible behaviour change (the status-bar symbol would be empty until first requested), so it needs
the maintainer's call.

**The whole file is parsed at open, not the visible region** — `set_grammar` marks the entire buffer
dirty (`buffer.cc:202`) and batching stops at EOF, never at the viewport.

**Launch re-parses restored documents.** A `sample` of launch: 241 samples in `initiate_repair`,
164 in `update_scopes`, against 97 for all of `applicationWillFinishLaunching:` and 84 for
`restoreSession`. So launch cost is dominated by re-parsing whatever was open at quit, not by
bundle or plugin loading. Undetermined: whether background tabs load eagerly too.

**Checked and NOT worth pursuing:** the unconditional `createBundlesIndex:` after `cache.load()`
(`BundlesManager.mm:969`) looks like a wasteful rebuild but the cache makes the walk cheap and the
profile agrees it is minor; `layout_t`'s glyph layout is already correctly viewport-bounded
(`layout.cc:410-420`) — only the row-splitting pass is whole-buffer.

**Rust/Swift would not help.** The cost is ~3.25M selector evaluations; a rewrite runs the same
number with modestly better codegen, while adding a second toolchain to a build Phase 2 deliberately
unified, and Swift/C++ interop still handles the templated `oak::basic_tree_t` / scope node graphs
poorly. Algorithm beats language here.

### THE FAST-REJECT LANDED — 2.3x on a cold open (`72fa771f`)

The one lever that reduces the work rather than moving it. `path_t` precomputes its literal
(wildcard-free) first scope component at parse time; `does_match` scans the ancestor chain for it
before running the recursive matcher.

```
cold 1 MB open   85.6 s -> 37.1 s     2.3x, consistent across two runs
differential     6,500,000+ comparisons, 0 disagreements
scope 14/14   bundles 5/5   buffer 23/26 (same pre-existing spellchecking failures)
```

*(The absolute seconds are far above the 5-14 s measured earlier — the machine was heavily loaded by
then. The ratio is same-session against the same file, so it is the trustworthy figure.)*

**My design for this was unsound and the implementer caught it.** I specified comparing the query
scope's **root** atom. But `test_rank`, already in the suite, matches selector `source.php` against a
scope rooted at `text.html.php` with `source.php` as a *non-root ancestor* — PHP embedded in HTML.
An unanchored path's first component may match below the root, and every embedded-language grammar
depends on it. A root-equality reject would have silently broken PHP-in-HTML, JS-in-HTML,
Ruby-in-ERB. Hence the ancestor-chain scan: O(depth) rather than O(1), still much cheaper than the
full matcher because it skips the rank and backtrack bookkeeping every caller pays for.

`has_dotted_prefix` is `strncmp` plus a boundary check for `\0` or `.`, so `source.c` matches
`source.c.foo` but **not** `source.c++` — components compare whole. Getting that wrong would reject
valid matches.

**Falls back to the full matcher** (always correct, never rejects) for: any `*` in the first
component, and `group_t` parenthesised sub-selectors entirely, including any negation wrapping a
group. Negation is handled by gating only the un-negated `path_t` and letting the caller apply the
negation; comma alternatives are gated per composite.

**The reopen median is flat and that is expected** — reopening the same file in one session hits the
settings cache almost entirely after the first open, so that metric barely exercises `does_match`.
Both numbers are recorded rather than only the flattering one.

### `-Os` -> `-O2` MEASURED AND REVERTED — inconclusive, and `-Os` is Apple's own default

The last untested lever from the original Phase 7 plan. Built at `-O2`, measured cold 1 MB opens
against `-Os`, alternating sides so machine drift hit both equally:

```
        -Os        -O2       delta
r1    37045      35676       O2 -1369
r2    38890      42299       O2 +3409
r3    47400      35454       O2 -11946
median 38890     35676
spread 10355      6845
```

**The within-build spread is as large as the between-build difference.** `-Os` varied by 10.4 s
against *itself* across three rounds (37.0 -> 38.9 -> 47.4, drifting monotonically upward as the
session wore on), which is bigger than any effect being measured. Two of three rounds favour `-O2`
and its median is 8.3% better, but that cannot be distinguished from drift at this sample size.

Cost side is certain: binary 6184752 -> 6733360 bytes (+8.9%), bundle 26012 -> 26920 KB (+908 KB).
The size gate would still have passed — 1008 KB under `undead` — so the gate was not the blocker.

`Ruling: reverted. A certain 908 KB for an unmeasurable speed change is a bad trade, and -Os is
Xcode's own default for Release builds -- it is Apple's deliberate choice, not an oversight
inherited from upstream, which removes the main argument for switching. Worth one more attempt on a
quiet machine; the numbers above are the baseline to beat.`

### APPLE SILICON AUDIT — clean apart from three vendored binaries

Asked whether everything is optimised for Apple Silicon. Surveyed, and the answer is mostly yes:

| | |
|---|---|
| Compiled architectures | arm64 only; no universal slice in anything we build |
| x86 intrinsics, `__SSE*`, `__x86_64__` paths | **none anywhere in the tree** |
| rpath dylibs | 0 — fully static |
| NEON / Accelerate / SIMD | none used, and none needed: the hot loops chase pointers through scope node chains and AA-tree nodes, which do not vectorise |
| Vendored universal binaries | **were** shipping 144 KB of dead Intel — fixed, `fa72745c` |

`find_app` 134880->52960, `plist.bundle` 89536->56768, `keychain.bundle` 85648->52880. Enforced in
`bin/fetch_embedded_bundles.sh` rather than only in the checked-in copies, because a pin bump would
otherwise silently reintroduce them.

**The one real gap is still `GCC_OPTIMIZATION_LEVEL = s`** in `Xcode/Base.xcconfig` — the build is
compiled for size, and `-Os` is precisely the setting that suppresses the inlining and unrolling
that make hot loops fast. It has been the known outstanding lever since early in Phase 7 and is
**still untested**. Size headroom is comfortable for it: 26,164 KB against `undead`'s 27,928, so a
10-20% code-growth from `-O2` cannot breach the size gate. That headroom is why the Contributions
removal was sequenced first.

### CRASH ON QUIT — the off-thread cache warming was reverted

`938179fa` (warm `value_for_setting`'s cache from the parser's background queue) **crashed the app on
quit** and has been reverted. It bought 8%; it cost a SIGSEGV. Bad trade, and my defect.

```
Thread 0 (main):    exit -> __cxa_finalize_ranges -> cache_t::~cache_t()      wrappers.cc:190
Thread 4 (crashed): initiate_repair block -> value_for_setting -> map::find   parsing.cc:79 -> wrappers.cc:211
EXC_BAD_ACCESS (SIGSEGV) at 0x19bc5
```

Quitting runs `exit()`, which runs static destructors on the main thread and destroys
`value_for_setting`'s function-local `static cache_t`. A parse block still in flight on
`com.apple.root.default-qos` then calls into that cache and reads freed memory.

**The mutex is no defence — the mutex is a member of the object being destroyed.**

**The general rule this violated:** `value_for_setting` had only ever been called from the main
thread (via the `CFRunLoopPerformBlock` completion), so it could never race static destruction.
Moving those calls to a background queue turned a single-threaded invariant into a cross-thread one,
and nothing in the type system or the tests flagged it. **Before calling any function with
function-local statics from a new thread, check what happens to those statics at `exit()`.**

A targeted fix exists — give the static a deliberately leaked heap allocation
(`static cache_t& cache = *new cache_t();`) so it is never destroyed, the standard idiom for exactly
this. It was **not** applied, because `query()`/`cache_search()` reach further statics in
`query.cc` (`AllItems`, `cache()`) with the same exposure, so fixing one site would likely just move
the crash. Doing this properly means auditing every static on the bundles query path, and it is not
worth it for 8%.

### DEFERRING THE SYMBOL LIST DOES NOT HELP — tried twice, do not try a third time

The maintainer's proposal — draw the window first, fill the symbol list in behind — was implemented
twice, correctly, and **measured no improvement either time**. The implementation was discarded.

**Attempt 1, fixed delay.** `symbols_t` disabled during load, accumulating parsed ranges, flushed by
a `dispatch_after` a few hundred ms after load. Result: `5820 -> 5981 ms`, flat. Instrumentation
showed why: the flush fired with only **~80 of ~4000+ chunks** pending, so 98% of the file still
computed inline. A fixed delay cannot work against a parse that runs 5-10 seconds.

**Attempt 2, debounce plus sliced catch-up.** Flush re-armed on every chunk and fired only after
250 ms of no parsing, so the whole initial parse was deferred; catch-up processed in bounded slices
(300 scopes) re-dispatched to the main queue so the freeze could not simply move to the end.
Lifetime via `weak_ptr<symbols_t>` + `enable_shared_from_this`. Correctness verified: 6 slices,
`_symbols` growing monotonically, `symbols()` returning the complete list.

```
time-to-responsive   before median 471 ms   after median 466 ms   (10 runs/side)
open (quiescence)    before median 5200 ms  after median 5473 ms  (flat within noise)
```

**Why it cannot help: the parser already yields.** `initiate_repair` (`parsing.cc`) bounces its
completion through `CFRunLoopPerformBlock` every ~10-20 lines, so the main thread was already
answering Apple Events in ~470 ms *before any change*. There is no monolithic freeze to break up —
the work was already arriving in small slices. Deferral reschedules work that was never blocking.

`Ruling: the remaining cost is the total amount of work, not its scheduling. Stop trying to move it;
make it smaller. The one lever left is the root-atom pre-filter.`

**Also learned: `measure-open.sh`'s metric cannot show a deferral win at all**, because it waits for
CPU quiescence, which includes deferred work by definition. `bin/bench/measure-responsive.sh` was
added for this — it measures how long the main thread stays too busy to answer a bounded Apple
Event, requiring three consecutive fast replies so a lull between chunks cannot fake success.
**It contains a bash 3.2 workaround**: macOS's stock `/bin/bash` is 3.2 and its parser fails on
`case` inside `$( ... | while ... )` with ``syntax error near `;;'`` — fine under Homebrew bash 5.x,
broken exactly where the harness runs. The `case` lives in a named function for that reason.

### A MEASUREMENT TRAP THAT INVALIDATED TWO NUMBERS

**TextMate restores previously-open documents at launch.** An ad-hoc timing loop that does
`open -a`, sleeps, then waits for CPU quiescence measures *session restore*, not the open — and if
the file is already restored, it returns immediately. That produced a nonsensical **-929 ms** and
retroactively invalidated two real-file timings taken the same way (118 s and 199 s). Both are
struck. `bin/bench/measure.sh` and `measure-open.sh` close windows between runs and do not have this
problem; **use them, and do not hand-roll an open-and-wait loop.**

Consequence: raising the bound 50000 -> 500000 was tried and **reverted**, because its only evidence
was one of those unsound measurements. The trustworthy numbers today remain the harness ones on the
synthetic file: 15,559 -> 5,820 ms.

Tests, for the record: `bundles_test` 5/5, `scope_test` 13/13, `buffer_test` 23/26 — the three
failures are pre-existing spellchecking ones, reproduced with the change stashed out.

**Three more instances of the same pattern** were found and are NOT yet fixed:

| Site | Defect |
|---|---|
| `layout.cc:812` | `scope::to_s(_buffer.scope(0).left)` in the **per-frame draw path** |
| `folds.cc:367` | scope stringification in fold detection |
| `settings.cc:147-151` | another self-clearing cache — threshold **64** |

### Verified since

- `bin/build` succeeds with both the Contributions removal and the cache fix applied.
- Bundle is **26,164 KB**, down from 27,704 — the full 1,540 KB, and now **1,764 KB under
  `undead`** rather than 224 KB over. Artwork set-difference check prints nothing.
- `73a3299a` records why the first post-removal measurement showed the bundle getting *larger*:
  `assemble_resources.sh` copies but never deletes, so an incremental build keeps resources you
  removed. Delete `Resources/About` before trusting any local size figure.

### If interrupted here

1. **The cache fix is measured, rejected and reverted** — see above. Nothing outstanding on it.
2. **`layout.cc:812` is the best remaining candidate.** `_theme->background(scope::to_s(_buffer.scope(0).left))`
   inside `layout_t::draw()`, reached from `OakTextView.mm:432,765,1266` — a scope-chain walk plus a
   string allocation **on every frame**, for a colour that almost never changes. Cache it against the
   previous scope and recompute only on change; remember to invalidate on theme switch.
   Note `folds.cc:367` is a fallback that only runs when no folding pattern matched, and
   `settings.cc:147` is **not** the same defect — its `clear()` fires only on an explicit
   `sections(NULL_STR)` flush, not per lookup. A survey called it a defect; reading it says otherwise.
3. **Then the `-Os` -> `-O2` experiment** (`Xcode/Base.xcconfig`), both builds measured back to back.
4. Small dead-code sweep: 3 dead `@available` guards (`fs_cache.mm:66,217`,
   `OakDocumentView.mm:336`) and 4 uncompiled utilities (`gtm.cc`, `indent.cc`, `pretty_plist.cc`,
   `NewApplication/`). Housekeeping only — none of it ships, so none of it is a speed or size win.
5. Do not push or open a PR without the maintainer saying so.

---

## 2026-08-16 — Phase 6 shipped as .23; Phase 7 baselined and already ahead

**Read this first on resume.** Everything below is merged to master and released.

### State

| | |
|---|---|
| Released | **v3.0.0-revived.23**, verified: cask SHA256 matched, Developer ID signed, notarized, stapled |
| Phases done | 0-6 complete. **Phase 6 is closed** — `NSVisualEffectView` appears nowhere in `Frameworks/` or `Applications/` |
| Phase in progress | **7 — performance.** Baselined, not yet optimised |
| Phases left | 7, 8 (shared modules), 9 (optional LSP) |
| Working tree | clean, on `master` |

### Phase 7 baseline — measured today, same machine, same session

```
| build       | size KB | archs | rpath dylibs | launch ms      | RSS MB |
| undead      |   27928 | arm64 |            0 | 1141/1160/1110 |    146 |
| revived.23  |   27820 | arm64 |            0 |  813/ 819/ 824 |    136 |
```

**We are ~320 ms (28%) faster than `undead` on launch, 10 MB lighter in RSS, and 108 KB smaller.**
Phase 7's stated gate — "measured improvement over the `undead` baseline on launch time, installed
size, and large-file open" — is already met on two of three. Large-file open not yet measured.

### The trap that nearly produced the opposite conclusion

Comparing revived.23's ~818 ms against the **Phase 0 baseline document's** figure of 661 ms for
`undead` shows a 24% *regression*, and that is what I first reported. It is wrong.

`undead` measured **661 ms** at Phase 0 and measures **~1137 ms** on this machine today. Nothing
about `undead` changed — it is the same notarized binary. The ~475 ms is macOS drift across the
months between the two measurements, and it dwarfs anything this fork has changed.

`Ruling: every number in docs/benchmarks/2026-08-12-baseline.md is now unusable as a comparison
point. Phase 7 measures both sides in the same session, on the same machine, or it measures nothing.
A cross-session comparison here produced a confident 24% regression that was actually a 28%
improvement -- the sign was wrong, not just the magnitude.`

### Two false starts worth not repeating

- **`measure.sh` printed a skip warning and a number in the same run** (`1178 ms`). Its three
  bundle-id guards are nested, so that should be impossible — a warning at any level leaves
  `LAUNCH_MS` as the "not measured" string. Cause not established. The number was contention from my
  own earlier `open -n` launches; clean re-runs gave a tight 813/819/824. **Treat any `measure.sh`
  run that prints a warning as void, whatever number follows it.**
- **`undead` timed out three times, then measured fine on retry** with no change. I wrongly
  attributed it to an Automation/TCC denial; `osascript` reaches `com.macromates.TextMate` normally
  when the app is actually running, and both `open -a` and the readiness poll work in isolation. The
  `-1728` I saw was "no such running app" because I had already killed it. Cause of the original
  timeout unexplained — possibly first-launch Gatekeeper scanning of a freshly extracted bundle.
  Kill every TextMate process and re-run before believing a timeout.

### Where the bytes actually are

```
Contents/Resources      15460 KB   ← 56% of the bundle
Contents/MacOS           7072 KB
Contents/Library         2332 KB
Contents/SharedSupport   2132 KB
```

The spec's named size levers — dead-strip and LTO tuning — act on `MacOS`, the smaller half.
`Resources` is more than double it and has not been broken down yet. Do that before tuning link
flags.

### Maintainer decisions this session

- **The gate is "be fast", not a specific wording.** Asked whether to keep the spec's `undead`
  comparison or re-base it: *"The original code was slow and clunky, we need to be fast! So whatever
  we can do to be faster is what we are aiming for, wording is just wording."* Optimise for real
  speed; do not lawyer the spec's phrasing.
- Automation permission was offered if needed for benchmarking. It turned out not to be needed.
- **Georg Seifert (@schriftgestalt), author of upstream PR #1469, has been asked to open a PR with
  just the UI work.** The maintainer replied to him directly and will say when it arrives. Nothing to
  do until then.
- **Session links are no longer added to commits or PR bodies.** Stripped from PRs #12-14. The 53
  already in `master`'s commit messages are deliberately left alone — removing them rewrites
  published history, breaks tags `.4`-`.23`, and invalidates clones. Needs an explicit decision.

### Next steps for Phase 7

1. Measure **large-file open** (the third gate metric) — the harness has a method for it; the Phase 0
   doc says it uses a generated 100 MB file, recorded separately.
2. Break down the 15,460 KB of `Resources` before touching link flags.
3. Profile the ~818 ms launch in Instruments to find where the time actually goes, rather than
   assuming it is the subsystems the spec guessed at.
4. Then propose targets, against evidence.
5. Phase 7's own test requirement, per the design doc: benchmark assertions with thresholds that fail
   CI on regression.

---

## 2026-08-16 — Phase 6 adoption complete: `NSVisualEffectView` is gone from the tree

**`6c7a46cb`** moves the last six surfaces onto glass — both choosers' footer bars, the Bundles
preferences footer, the tooltip, the choice menu, and `OakBackgroundFillView`'s header style. The
completion check is a grep, and it comes back empty:

```sh
grep -rn 'NSVisualEffectView\|NSVisualEffectMaterial\|NSVisualEffectBlending' \
     --include='*.h' --include='*.mm' --include='*.cc' Frameworks Applications
```

Also removes the `@available(macos 10.14, *)` guards these sites carried, dead against a macOS 26
deployment target.

### Two defects in my brief, both caught by measurement

**The instructions were mutually exclusive.** `OakCreateGlassBackground` sets
`translatesAutoresizingMaskIntoConstraints = NO`, and my brief then told the implementer to keep
sizing two of the sites with `autoresizingMask`. Those cannot both hold. It built a throwaway Cocoa
binary and showed the frame stays `{0, 0, 0, 0}` through a superview resize with the flag off and no
constraints. Applying the brief literally would have shipped two invisible, zero-sized glass views.
Fixed by re-enabling the flag at those two frame-driven sites, with a comment saying why.

**`footerView`'s contract was the real problem, not its type.** The implementer found that five other
files — `FileChooser.mm`, `SymbolChooser.mm`, `BundleItemChooser.mm`, `Favorites.mm` and
`OakPasteboardChooser.mm` — add controls **directly as subviews of the footer view**, which is
exactly what `NSGlassEffectView` does not guarantee. Swapping the type alone would have left five
call sites relying on undefined z-order.

`Ruling: change what footerView returns rather than its five consumers. It now returns the holder,
with the glass behind it, and its declared type becomes NSView* rather than NSGlassEffectView*. Every
consumer keeps working untouched, and NSView* is the honest type -- a caller only ever needed
something to add subviews to. Cost if wrong: nothing gained a glass surface it should not have; the
alternative was editing five files to route through a holder each.`

### Increment 6 dropped deliberately — no glass behind the tab bar

The tab bar now sits in the window's titlebar row, where macOS already draws its own material.
Putting an `NSGlassEffectView` behind it would stack a second material inside a surface that has one
— the same reasoning that removed `OFBFinderTagsChooser` from increment 2. It would read as muddier,
not more modern. The spec's increment 6 is closed as **not wanted**, rather than pending.

### `Regular` everywhere, including the overlays

The spec anticipated `NSGlassEffectViewStyleClear` for tooltips and menus. All six use `Regular`
instead. `Clear` is for surfaces meant to read *through* to what is beneath; every one of these
carries text or controls that must stay legible. `Clear` remains a one-word change per site if the
maintainer wants a more transparent look.

**If interrupted here:** the branch is `phase-6/liquid-glass-finish`, feature-complete and not yet
merged. Run the full suite against the parity document, then ship as v3.0.0-revived.23. After that
Phase 6 is closed and Phase 7 (performance) begins. Georg Seifert is expected to open a PR with just
the UI work from #1469; the maintainer has asked him for it and will say when it arrives.

---

## 2026-08-15 — Tab tear-off: mostly already built, only the trigger was missing

**`2da8ac7e`.** Dragging a tab out of the window now gives it a window of its own. Maintainer
request, and the survey that preceded it saved most of the work.

**`takeTabsToTearOffFrom:` (`DocumentWindowController.mm:1733`) already did the whole job** — creates
the new `DocumentWindowController`, assigns the documents, opens and shows the window, closes the
source tabs — and was already wired to two triggers: the `moveDocumentToNewWindow:` menu action
(`:887`) and double-clicking a tab (`:1825`). The only gap was that
`draggingSession:endedAtPoint:operation:` (`OakTabBarView.mm:1019`) reset `draggedTabIndex` and
ignored everything else.

**The condition needs both halves:**

```objc
if(operation != NSDragOperationNone || draggedIndex == -1) return;
if(NSPointInRect(screenPoint, self.window.frame))          return;
```

`NSDragOperationNone` alone also covers a drop on some spot *inside* the window that refused it, and
dropping a tab back onto its own window should do nothing. Either check on its own tears off when it
should not.

The delegate method is `@optional`, so a tab bar whose delegate does not implement it keeps the old
behaviour of cancelling the drag. It carries the screen point so a future change can place the new
window where the tab was dropped; nothing uses that yet.

**A design question answered by the existing code rather than by me.** Before building this I flagged
that "a window is a project, not a document" in TextMate, and asked whether a torn-off window should
inherit the project. `takeTabsToTearOffFrom:` had already decided: it does `[DocumentWindowController
new]` and assigns only the documents, so the new window has no file browser — though it does keep
`defaultProjectPath` when the document lives inside the current project. Following existing behaviour
rather than inventing a second answer.

Tearing off the last tab is a no-op, the same guard `moveDocumentToNewWindow:` uses — otherwise it
would empty this window and open a near-identical one.

`OakAppKit_test: 25 tests passed`, application builds. **The drag gesture itself is unverified** —
UI scripting is denied in this environment, so no synthetic drag can be delivered. The maintainer
confirmed the window-drag fix by hand; this needs the same.

**If interrupted here:** the branch is feature-complete. Ship as v3.0.0-revived.22.

---

## 2026-08-15 — Window drag restored; two ivars with the same name; Legal page audited

**`0c48bae8` restores window dragging.** With the tab bar in the titlebar row there was no bare
titlebar left to grab and the window could not be moved at all.

**The trap: two different ivars named `_backgroundView` in `OakTabBarView.mm`.**

| Line | Class | What it is |
|---|---|---|
| `:259` | `OakBox` | belongs to **`OakTabView`** — each tab's own fill |
| `:718` | `OakTabView` | belongs to **`OakTabBarView`** — the empty area, created `tabItem:nil` |

A survey reported "OakBox" because it matched line 259 first, and the brief I wrote from it was
wrong. The empty region right of the last tab is a **phantom `OakTabView`** — that is how
double-clicking blank space opens a new tab (`doubleAction = newTab:`). It inherits
`OakTabView.mouseDown:` (`:563`), which records the location and returns **without calling super**,
so the click was swallowed. Adding `mouseDown:` to `OakTabBarView`, as the brief specified, would
have fired only on a roughly 1pt sliver the background view does not cover. The implementer applied
nothing and escalated — eighth time that judgement has been right.

**The fix hooks `mouseDragged:`, not `mouseDown:`, and that is load-bearing.** Starting the window
drag on mouse-down consumes the event and `mouseUp:` never arrives — and `mouseUp:` is where the
double-click that opens a new tab is detected. Reusing the existing 2.5pt drag threshold keeps both
behaviours: a click still opens a tab, a drag now moves the window. Guarded on `!_tabItem`, which is
how the file already distinguishes the phantom elsewhere (`closeButtonAlphaValue`).

Build succeeds, `OakAppKit_test: 25 tests passed`. **Not verified:** the drag itself — this
environment denies UI scripting (`osascript` returns `-1728`) and Screen Recording, so no synthetic
click can be delivered. The maintainer confirmed the About-window centring works; the drag needs the
same treatment.

### Legal page audited at the maintainer's request — nothing to remove

Every entry still ships, so every credit is still required:

| Component | Present | Used by | Licence obligation |
|---|---|---|---|
| Onigmo | `vendor/Onigmo` | linked by 28 targets | BSD, attribution |
| kvdb | `vendor/kvdb` | `DocumentWindowController.mm`, `Favorites.mm` | MIT, notice retained |
| xdiff | `vendor/xdiff` | linked by 12 targets | **LGPL-2.1** — attribution *and* source availability |
| Dialog / Dialog2 | `PlugIns/dialog*` | 27 references, both `PROVENANCE.md` present | MacroMates notice preserved; covered by our GPLv3 |

The page is already clean of the Phase 3 purge — zero mentions of boost, sparsehash, capnp or ragel.

One caveat worth knowing rather than discovering later: the Dialog entry states that upstream "did
not distribute either under a separate license, so they are covered by this repository's own license
(GPLv3)." That is a reasonable reading, but it is a conclusion this project reached, not something
upstream asserted.

**If interrupted here:** the branch is complete — titlebar tabs, drag fix, About centring, always-on
close button. Ship as v3.0.0-revived.22. The maintainer has already replied to Georg Seifert, so no
outreach is pending.

---

## 2026-08-15 — About window centres on the frontmost document window

**`9f1f6986`.** The About panel now centres on the frontmost document window, or on the active screen
when none is open, instead of landing wherever it was last left. Maintainer request.

Two separate causes, not one:

- `AboutWindowController.mm:57` computed an **x** origin from `NSMaxY` of both terms —
  `rect.origin.x = NSMaxY(visibleRect) - NSMaxY(rect)`. A longstanding typo.
- `:71` sets `setFrameAutosaveName:@"BundlesReleaseNotes"`, and the restored frame overrode the
  computed placement anyway, so the initial calculation only ever applied on a machine that had never
  opened the window.

The autosave is **kept** — it remembers a size the user chose — but the origin is recomputed on every
show. Panels are skipped when picking the reference window, since the About panel is itself an
`NSPanel`, and the result is clamped to the screen so a partly-offscreen document window cannot drag
the panel off with it.

**Still outstanding: the window-drag fix.** `OakTabBarView` has no `performWindowDragWithEvent:` in
the tree yet — the implementer had not filed it when this entry was written. The window cannot be
dragged by the titlebar row until it lands. The intended shape, and the reason
`mouseDownCanMoveWindow` must stay `NO`, is recorded in the entry two below.

**If interrupted here:** check whether `OakTabBarView.mm` contains `performWindowDragWithEvent:`; if
not, that fix still needs applying. Then build, run `OakAppKit_test` (expect 25), and ship the branch
as v3.0.0-revived.22.

---

## 2026-08-15 — PR #1469's author corrected us, and he was right

**`1f0ff406` retracts a false claim this project published about someone else's work.**

The Liquid Glass spec said PR #1469 (`textmate/textmate`) "reintroduces 11 `.rave` files — the build
system Phase 2 deleted." Georg Seifert (@schriftgestalt), its author, replied on commit `7cf1ff90`:

> removing the .rave build system was the first thing I did. My fork build with Xcode all the way.

Checked against the GitHub API rather than taken on either side's word:

| | |
|---|---|
| `.rave` files in the #1469 diff | **63**, every one status `removed` |
| Xcode project | PR **adds** `Applications/TextMate/TextMate.xcodeproj/project.pbxproj` |
| Upstream `textmate/textmate` master | still ships `.rave` — which is why they appear in the diff at all |

He is right and the spec was wrong. **The mistake was reading a list of filenames without reading
each entry's `status`.** A deleted file appears in a PR's file list exactly as an added one does. That
is the same failure mode as the artwork audit earlier today — counting what exists without checking
which ones ship — and it is worth naming twice, because both times the check *looked* like evidence.

He reached Xcode independently, and before this fork did.

**He has offered to open a PR containing only the UI work**, which is exactly Phase 6's scope. That
is the maintainer's call to accept; it is not something to answer on their behalf, so it is recorded
here and left open.

### Session links removed from public places

At the maintainer's instruction, `Claude-Session:` trailers and bare session URLs are no longer added
to commit messages or PR bodies. Stripped from the bodies of PRs #12, #13 and #14 and verified zero
remaining.

**Not removed: the 53 commit messages on `master` that already carry them.** Doing so means rewriting
published history — every SHA changes, the `v3.0.0-revived.4` … `.21` tags break, and any existing
clone is invalidated. That is a deliberate, destructive operation and needs an explicit decision, not
a side effect of a formatting request.

---

## 2026-08-15 — Last two .rave files deleted; credential audit; two bugs from maintainer testing

**`56e021cb` deletes `PlugIns/dialog/default.rave` and `PlugIns/dialog-1.x/default.rave`** — the last
two tracked survivors of the build system Phase 2 replaced. The maintainer asked whether any had crept
back; they had never left. Nothing reads them: every other `default.rave` mention in the tree is a
comment in `Xcode/scripts/*.sh` citing the old file as the source a build setting was derived from,
which is worth keeping. Both plug-ins build from `project.yml` (`tm_dialog`, `Dialog`, `Dialog2`), so
this removes dead files rather than a build path. Full `bin/build` passes after deletion.

Build entry points confirmed while checking: no `./configure`, no `bin/rave`, no `build.ninja`.
`bin/build` wrapping `xcodebuild` is the only path.

### Credential audit — clean, and the one hit is not a leak

Scanned the current tree **and the full history**, not just what is checked out:

| | |
|---|---|
| Apple ID `denike@gmail.com` | not present; `git log -S` finds it in no commit, ever |
| The app-specific password exposed in chat | not present; never in history |
| `.p12` / `.pem` / `.key` / `.cer` / `.mobileprovision` | none tracked |
| Workflows | reference `secrets.NAME` only — values live in GitHub Secrets |
| gitleaks pre-commit | active, `.githooks/pre-commit` via `core.hooksPath` |

**Team ID `485WH9DHS4` does appear** in `STREAM.md` and `docs/RELEASING.md`, and that is correct
rather than an oversight. A Team ID is public by design — it is embedded in every signed binary and
anyone who downloads the app can read it with `codesign -dv --verbose=2`, which is exactly how
Gatekeeper validates and how `OakDownloadManager` refuses an update signed by a different team.
Verified by reading it back out of the installed app. Nothing to redact.

### Two bugs the maintainer found testing the titlebar-tabs build

1. **The window cannot be dragged.** The tab bar now covers the titlebar row, and
   `OakTabBarView.mouseDownCanMoveWindow` returns `NO` (`:735-738`) with no `mouseDown:` anywhere on
   the bar — so a click in the empty area right of the tabs hits `_backgroundView` (`:1371`), travels
   up the responder chain, and is dropped. Fix is a `mouseDown:` on **`OakTabBarView`** calling
   `performWindowDragWithEvent:`. `mouseDownCanMoveWindow` **stays `NO`**: returning `YES` would let
   AppKit move the window on a click anywhere in the bar, including on a tab, and the view would
   never see the `mouseDown` at all. Tabs are `OakTabView` subviews that consume their own clicks and
   `+` is an `NSButton`, so an event reaching the bar came from empty space.
2. **The About window lands wherever it was left.** Two separate causes.
   `AboutWindowController.mm:57` computes an **x** origin from `NSMaxY` of both terms — a longstanding
   typo — and `:71` sets `setFrameAutosaveName:@"BundlesReleaseNotes"`, whose restored frame overrode
   the computed placement anyway. It now centres on the frontmost non-panel window, falling back to
   the active screen, clamped to stay on-screen. The autosave is kept, because it remembers a size
   the user chose.

**GitHub check:** no open PRs or issues on `sdenike/textmate`, `hidden-revived` or `homebrew-tap`. All
ten textmate PRs are the maintainer's own and merged; #10 never existed (GitHub shares numbering
between issues and PRs). The notifications API is not readable with the current token
(`Resource not accessible by personal access token`), so an alert the maintainer saw cannot be
confirmed from here — most likely the `github-actions[bot]` cask-bump commit on the tap.

**If interrupted here:** both fixes were dispatched to an implementer and had not reported. Resume by
checking whether `OakTabBarView.mm` has a `mouseDown:` and `AboutWindowController.mm` has
`centerOnFrontmostDocumentWindow`, then ship the branch as v3.0.0-revived.22. Full screen is still
unverified for the titlebar tabs, and cannot be verified in this environment.

---

## 2026-08-15 — Tabs moved into the titlebar row; and a probe that measured its own input

**Branch:** `phase-6/titlebar-tabs`, off master at `570c8be9`. `4b978fd6` moves the tab bar into the
window's titlebar row beside the traffic lights, iTerm2-style, reclaiming a row of chrome. Not
merged; the implementer's final verification had not been filed when this was written.

### The mechanism was already there

`DocumentWindowController.mm:208-212` already used `NSTitlebarAccessoryViewController` — the same
AppKit mechanism iTerm2 uses (`iTermTitlebarAccessoryNanny.swift:51-63`). Tabs landed in their own
strip only because `layoutAttribute` defaults to `NSLayoutAttributeBottom`.

Measured against real AppKit, by reading back frames from probe windows:

| Configuration | Accessory | Traffic lights | Result |
|---|---|---|---|
| `Bottom` (as shipped) | y 364–400 | y 409–423 | separate rows |
| `+ titleVisibility Hidden` | y 364–400 | y 409–423 | still separate |
| `+ titlebarAppearsTransparent` | y 364–400 | y 409–423 | still separate |
| `+ FullSizeContentView` | y 332–368 | y 377–391 | still separate |
| **`Right`** | **y 400–432** | **y 409–423** | **same row** |

`NSLayoutAttributeRight` is the entire mechanism. `titlebarAppearsTransparent` and
`FullSizeContentView` are **not** needed and were measured not to help.

### I asserted a measured fact that was my own input read back

The brief told the implementer that under `Right` the accessory "spans the full window width
starting at x = 0". **It does not.** My probe constructed its view with
`initWithFrame:NSMakeRect(0, 0, winWidth, 28)` — already full width — so the `w=800` I recorded was
the frame I had just set, not AppKit stretching anything.

The implementer built it as specified, found the tab bar rendering at **zero width**, confirmed it
three independent ways including an `NSLog` in the running application, and escalated rather than
inventing a fix. Correct call; it was the seventh time in this project that stopping on a
contradiction turned out to be right.

Re-measured, with a view deliberately **not** pre-sized:

- A `Right` accessory does **not** stretch its view.
- An Auto Layout **width constraint on the container has no effect** — still `w = 0`. A `Right`
  accessory sizes from the view's **frame**.
- **`autoresizingMask = NSViewWidthSizable` has no effect either.** Frame-size it once and it is
  correct; resize the window 800 → 1200 and the container stays 800 wide and right-aligns at x = 400.

So the container is frame-sized and maintained by hand in `windowDidResize:`. Verified in both
directions — 800 → 1200 and 1400 → 700 — with the tab bar starting at x = 77 and clearing the zoom
button each time. **That is the part a future reader will try to "clean up" into a constraint; the
commit message says why it cannot be.**

Other measured values: traffic lights end at **x = 69** (close 9–23, miniaturize 32–46, zoom 55–69),
so the inset is 69 + 8 = 77, matching iTerm2's 6–9pt of padding. The inset is derived at runtime from
the zoom button's frame rather than hardcoded, so it collapses to 0 in full screen where the buttons
are hidden.

**Unverified and not claimed:** full screen, and any screenshot of the real app — Screen Recording is
declined for this session's process, and synthetic modifier keys are dropped, so ⌃⌘F is unreachable.
The inset logic is written to be self-correcting there, which is not the same as tested.

**If interrupted here:** confirm the implementer's report landed and the six visual checks were
answered, then the tab-bar collapse at ≤1 document (`DocumentWindowController.mm:389`, `:1576`) needs
a look, then ship as v3.0.0-revived.22.

---

## 2026-08-15 — Increment 4 complete; and 40 more images have never shipped

**`0bce7964` — all four chrome bars are on glass.** `HOStatusBar`, `OFBHeaderView` and
`OFBActionsView` joined `OTVStatusBar`. `OakAppKit_test: 25 tests passed`, application builds. The
file browser's actions bar visibly gains the glass view's rounded corner, which is the first place
in this phase the material reads at all — the editor status bar sits over a flat text view, so glass
there is indistinguishable from the old flat bar.

`HOStatusBar` needed one thing beyond the brief's survey: its `setIndeterminateProgress:` adds
subviews dynamically, and those calls needed retargeting to the holder alongside the static ones.

### `5bcba5cc` — the .18 image fix was half a fix, and the other half was mine to miss

The implementer stopped on three blank buttons in the file browser and root-caused it as
pre-existing. Auditing it properly found far worse: **79 image files exist under `Frameworks/`, and
40 of them were never copied into the app.**

| Missing | Effect |
|---|---|
| `Folding Top/Bottom/Collapsed (+Hover)`, `FoldingDots` | no code-folding arrows in the gutter |
| `Bookmark`, `InsertBookmark`, `RemoveBookmark` | no gutter bookmarks |
| `diff.added/modified`, `error`, `warning`, `note`, `search` | no gutter marks |
| `Projects`, `Software Update`, `Terminal`, `Variables` | empty Preferences toolbar |
| `Search`, `Favorites`, `SCM` | the three blank file-browser buttons |

v3.0.0-revived.18 fixed "40 missing images" by globbing directories named `gfx` for `*.png`. Two
things that glob could never catch, and I checked neither before declaring it done:

- Four frameworks keep artwork outside `gfx/` — FileBrowser, DocumentWindow and OakTextView under
  `resources/`, Preferences under `icons/`.
- **The entire gutter icon set is PDF**, so `*.png` was structurally incapable of matching it.

The glob now covers `gfx/`, `resources/` and `icons/`, matching png, pdf and tiff. Audited before
and after: **40 missing → 0 missing**, confirmed in the running application.

`Ruling: the lesson is not "widen the glob". It is that the .18 verification counted only what it
had already decided to look for -- it asserted "≥40 PNGs in Resources" rather than comparing the set
that exists against the set that ships. A completeness check has to be a set difference, not a
threshold. The fix now carries that audit command in its comment, plus the basename-collision check
that flattening depends on.`

**If interrupted here:** increment 4's code is complete on `phase-6/liquid-glass-chrome-bars`.
Remaining: the full suite against the parity doc, then ship as v3.0.0-revived.21 (the CHANGELOG
currently has an "Unreleased" section to fold in). Then titlebar tabs, whose full recipe is measured
and recorded in the entry below.

Two Task 3 checks were not verified live and are not claimed as verified: scrolling the file list
under the header, and the HTML output status bar. The sandbox drops synthetic modifier keys, so
neither could be exercised. The height-neutrality test covers the first mechanically.

---

## 2026-08-15 — Tab close button always visible; iTerm2's titlebar tabs use the mechanism we already have

**`fb8d25f2` — the tab close button no longer hides until hover.** Maintainer request. The mechanism
was a KVO binding: `closeButtonAlphaValue` returned 1 only when `_mouseInside || _modified ||
_voiceOverEnabled`. It now returns 1 whenever there is a tab item, and
`keyPathsForValuesAffectingCloseButtonAlphaValue` narrows to `tabItem` accordingly. The modified
state still changes the button's *image* via `updateCloseButtonImage`; that was never driven from
the alpha.

**It costs no horizontal room, contrary to the initial survey's warning.** The button is created and
constrained whatever its alpha — it sits in the `H:|-(3@53)-[close]-(>=3@53)-[title]-(>=6@53)-|`
chain and already contributed to each tab's `fittingSize` — so only opacity changed, and opacity does
not participate in Auto Layout. Confirmed by screenshotting three open tabs with nothing hovered:
widths unchanged.

### Titlebar tabs — researched, and it corrects something said earlier in this session

The maintainer asked about moving tabs into the titlebar row the way iTerm2 and Obsidian do, to
reclaim a row of chrome. Mid-conversation I claimed this would mean replacing TextMate's mechanism
with `NSWindowStyleMaskFullSizeContentView` plus a hidden title. **That was wrong.**

| | Mechanism |
|---|---|
| iTerm2 | `NSTitlebarAccessoryViewController` — `sources/Hacks/iTermTitlebarAccessoryNanny.swift:51-63` |
| TextMate today | `NSTitlebarAccessoryViewController` — `DocumentWindowController.mm:208-212` |

**The same AppKit mechanism, already in place.** Both even set `fullScreenMinHeight` on it. The
difference is configuration:

- iTerm2 sets `_tabBarControl.insets` from `leftInsetForWindowButtons`
  (`iTermRootTerminalView.m:1145`) — 2.5, 9 or 6 points depending on tab style — to clear the traffic
  lights. That inset only makes sense if the accessory shares a row with those buttons, which is
  precisely the visual difference.
- Tab position is a preference, `kPreferenceKeyTabPosition`, over
  `PSMTab_TopTab/BottomTab/LeftTab/RightTab`.
- Full screen hides the bar entirely unless `kPreferenceKeyShowFullscreenTabBar` is set.

**Not verified, and not to be assumed:** the exact configuration that puts their accessory in the
traffic-light row rather than below the title. The inset code is strong circumstantial evidence, not
proof. **Pin that down before writing the plan** — guessing is how you get a window that looks right
until someone enters full screen or uses a notched display.

Also relevant when that increment is written: TextMate hides the accessory entirely when the window
holds one document or fewer (`DocumentWindowController.mm:389`, `:1576`, gated on
`kUserDefaultsDisableTabBarCollapsingKey`). Titlebar tabs have to keep working with that collapse.

**If interrupted here:** increment 4 Task 3 — `HOStatusBar`, `OFBHeaderView`, `OFBActionsView` — is
still outstanding and is the next thing in the current plan. Titlebar tabs are a separate,
unplanned increment.

---

## 2026-08-15 — Editor status bar on glass; and Reduce Transparency invalidates a claim I made

**Task 2 landed:** `cf0aa263` moves `OTVStatusBar` off `NSVisualEffectView` onto a plain `NSView`
hosting `OakWrapInGlass`. `OakAppKit_test: 24 tests passed`, application builds, and a window-only
screenshot confirms every control is present and correctly placed — line/column, the grammar popup,
tab size, the bundle-item and symbol controls, the macro dot — at unchanged height.

**The finding that matters more: this machine has Reduce Transparency enabled.**
`com.apple.universalaccess reduceTransparency = 1`, and
`NSWorkspace.accessibilityDisplayShouldReduceTransparency` returns `YES`. macOS flattens every
vibrancy and glass material at the compositor when that is on.

**This retracts a claim committed in `a6a5b169`.** That commit put in the spec that
`NSVisualEffectMaterialTitlebar` "does not silently become Liquid Glass on macOS 26", citing a
screenshot of the flat status bar as proof. The screenshot proved nothing — the bar was flat because
*everything* is flat on this machine. Whether that material maps to glass on macOS 26 is still
unverified and cannot be settled here. Retracted in the spec, and `CLAUDE.md` now carries the check
to run before trusting any screenshot taken on this machine.

What survives: glass still renders as a distinct rounded surface with the setting on — the increment
2 renders show it, and the measured 0.44 mean-RGB difference between glass and no-glass held there.
So screenshots from here confirm **geometry, layout and control placement**, and cannot confirm
**translucency**. Every visual sign-off in this phase so far falls in the first category.

Two Task 2 checks are genuinely unverified for environmental reasons, both documented rather than
papered over: controls were not click-tested (the screen was locked, and macOS does not deliver
synthetic input while locked), and glassiness was not confirmed (Reduce Transparency). Neither
implicates the diff — no target/action wiring was touched — but neither is proven.

---

## 2026-08-15 — Increment 4 planned and started: the chrome bars

**Branch:** `phase-6/liquid-glass-chrome-bars`, off master at `43858aee`. Plan committed as
`b80a42b8`. Not merged.

Plan: `docs/superpowers/plans/2026-08-15-liquid-glass-chrome-bars.md`. Ledger:
`.superpowers/sdd/2026-08-15-liquid-glass-chrome-bars/`.

**The structural decision worth knowing.** All four bars need the identical restructure — plain
`NSView`, hosting a glass view pinned to its bounds, whose `contentView` is a holder carrying the
existing controls. Rather than write that out four times, Task 1 factors it into one helper,
`OakWrapInGlass(bar, style)`, which returns the holder to add controls to. Four hand-written copies
would be four chances to diverge, on four surfaces that are on screen constantly.

**Sequencing:** `OTVStatusBar` alone first as the probe — it is on every editor window, so it is both
the highest-value target and the right place to prove the shape. `HOStatusBar`, `OFBHeaderView` and
`OFBActionsView` are batched behind it once that shape holds. Renders and the full suite last.

**Two hazards the plan guards explicitly**, both of the same family as the six-point shrink that
increment 2 hit:

- `OakWrapInGlass` must be **size-neutral**. Task 1's third test pins a 300 × 24 holder and asserts
  the bar's `fittingSize` comes back 300 × 24. The brief tells the implementer to stop and report the
  observed value rather than adjust the expectation, because a surprise there is a finding.
- The file browser's list scrolls **underneath** its header, and `FileBrowserView.mm:68` derives the
  list's top content inset from `_headerView.fittingSize.height`. A height change of even one point
  shifts the file list. Task 3 carries a dedicated height-neutrality test.

**`HOStatusBar` needs care** where the others do not: it rebuilds its constraints dynamically in
`updateConstraints` (`:90-127`), so its holder must be reachable from that method — an instance
variable, not a local.

**Task 1 has landed.** `5e97d957` adds `OakWrapInGlass` and
`Frameworks/OakAppKit/tests/t_glass_wrap.mm` — 78 insertions across three files. Count verified by
running the binary directly rather than taken from the implementer's report:
`OakAppKit_test: 24 tests passed`, up from 21.

The size-neutrality test passed first time, so wrapping a bar in glass does **not** reproduce
increment 2's shrink — a 300 × 24 holder yields a 300 × 24 bar. That was the single biggest risk in
this increment and it is now pinned by a test rather than assumed.

**If interrupted here:** resume at Task 2, `OTVStatusBar` — superclass to `NSView`, delete the
`material`/`blendingMode`/`state` lines at `OTVStatusBar.mm:76-78`, call `OakWrapInGlass`, and move
both the control-adding at `:135` **and the constraint block at `:147-156`** onto the returned
holder. That constraint move is the step most likely to go wrong; if any constraint there references
`self` as a layout item rather than as a container, that is a finding to report, not to guess at.
Then Task 3 (the other three, batched), Task 4 (render + full suite), Task 5 (ship as
v3.0.0-revived.21).

---

## 2026-08-15 — v3.0.0-revived.20 verified live; increment 4 surveyed and the spec corrected

**The release is out and checked end to end**, not just reported green: cask SHA256
`1d9c8f08…5343` matches the published asset byte-for-byte, signed by Developer ID
`485WH9DHS4`, notarized, stapled, `spctl` accepts it as `Notarized Developer ID`.

**Increment 4 (chrome bars) is surveyed, and three spec claims were wrong.** All corrected in
`a6a5b169`; the details are in the spec, the consequences are here.

1. **There is no contained effect view to swap.** `OTVStatusBar`, `HOStatusBar`, `OFBHeaderView`
   and `OFBActionsView` each **subclass `NSVisualEffectView`** and add their controls directly to
   themselves. The SDK guarantees placement only for `contentView`, so each needs restructuring
   around a glass `contentView` — the same holder shape increment 2 arrived at independently. A grep
   for `.material` / `.blendingMode` / `.state` / `.maskImage` on these across `Frameworks/` and
   `Applications/` returns nothing, so changing the superclass to `NSView` breaks no consumer.
2. **The spec's only concrete `spacing` claim was false.** It named the file browser's header and
   actions bar as the pair needing a non-zero container spacing; `FileBrowserView.mm:63-65` puts them
   at opposite ends with the entire file list between them. They can never be in proximity. No
   surface identified so far needs a non-zero `spacing`.
3. **The file list scrolls underneath the header.** `FileBrowserView.mm:68` adds the header's height
   to the scroll view's top content inset and `:59` raises the header above it. The header is
   therefore a real glass-over-content surface, and **its `fittingSize` is load-bearing** — change it
   and the list's inset moves with it. This is the same class of hazard that silently shrank
   `OakKeyEquivalentView` by six points in increment 2, so it gets an explicit test.

**The premise was checked before committing to the work:** the running app, built against the macOS
26 SDK, was screenshotted. `NSVisualEffectMaterialTitlebar` renders flat and opaque — it does **not**
silently become Liquid Glass. Increment 4 is real work with a real visible result.

**If interrupted here:** increment 2 is shipped and merged (PR #13, master at `4cb82ff7`); nothing
is in flight. Increment 4 is surveyed but **not yet planned** — no plan file, no branch, no ledger.
Write the plan from the corrected spec, then execute `OTVStatusBar` alone first as the probe (it is
on every editor window), render it with the live-window harness, and only batch `HOStatusBar`,
`OFBHeaderView` and `OFBActionsView` once that shape is proven. Increment 3 (overlays) was
deliberately deferred behind 4 because its stated purpose was cheap learning, and increment 2
already delivered that.

---

## 2026-08-14 — Liquid Glass increment 2 shipped as v3.0.0-revived.20

**Increment 2 is complete and released.** `OakKeyEquivalentView` — the key-equivalent recorder in
the Bundle Item Chooser — is the first surface in the fork to call a glass constructor. Corner
radius settled at **8**, a deliberate local override of `OakGlassChromeMetrics().cornerRadius` (12):
the control is a fixed 22 points tall, so anything from 11 up clamps to a full capsule, and a small
recessed input reading as a capsule would be the only one in that chooser. Documented at the call
site.

**Verification, all of it re-run at the end rather than trusted from earlier in the increment:**

| Check | Result |
|---|---|
| Full suite, 28 targets | 23 clean; 4 failures all matching the parity doc exactly; `command_test` hit its known hang and was killed by a 15-minute timeout |
| `OakAppKit_test` | 21 tests passed (was 10 before the increment) |
| Application build | `** BUILD SUCCEEDED **` |
| Launch smoke test | window opened, process stayed up, no crash |
| Clear-button artwork | all six `Close*Template` PNGs present in `TextMate.app/Contents/Resources/` |

That last row is the check the harness structurally cannot do. `NSImage Additions.mm:9` resolves
artwork with `[NSBundle bundleForClass:]`, which lands on the app bundle in the real app (OakAppKit
is statically linked) but on the bare test binary under the runner — which is exactly why renders
from the harness showed `NSButton`'s default "Button" title where the clear button should be. The
artwork is fine; only the test binary cannot see it.

**Next: increment 4, not increment 3.** The spec ordered overlays before chrome bars so glass could
be learned cheaply on a tooltip. That learning has already happened, and on a control that exercised
more edge cases than a tooltip would have — content-size propagation through `contentView`, the
capture limitation, appearance resolution. The maintainer wants a change they can see, and increment
4 (`OTVStatusBar`, `HOStatusBar`, `OFBHeaderView`, `OFBActionsView`) is the first one that is on
screen at all times. Increment 3's overlays fold in afterwards.

---

## 2026-08-14 — Phase 6 increment 2 planned; spec corrected against the SDK and the code

**Branch:** `phase-6/liquid-glass-small-controls`, off master at `56d193b7`. Not merged.

**What changed.** `docs/superpowers/plans/2026-08-14-liquid-glass-small-controls.md` is new — the
plan for increment 2 — and the design spec gained two corrections, both from checking rather than
assuming.

**`OFBFinderTagsChooser` is out of increment 2.** The spec listed it as a small control. Reading it
showed `FileBrowserViewController.mm:572` assigns it to an `NSMenuItem`'s `view`, so it is a
menu-item view, not a control in a window. It has no background of its own *because* the menu draws
one behind it; adding an `NSGlassEffectView` would put a second material inside a surface that
already has one. Increment 2 keeps one target, `OakKeyEquivalentView`, which exercises every hard
part at once — it paints both its background and its text in `drawRect:`, masks a focus ring by
hand, reads the effective appearance, and hosts a sibling subview.

**The spec gained a measured table of `NSGlassEffectView`'s Auto Layout behaviour.** The SDK header
documents the contract but not how the view behaves under constraints, which is the only thing an
adoption site needs. Measured against real AppKit, not inferred. The two that would otherwise cost
an afternoon each: `contentView.superview` is a private `ContentHolderView` rather than the glass
view, and a glass view with no `contentView` has a `fittingSize` of `0 × 0`, so a glass backdrop
without content silently collapses. Also: setting `contentView` installs the fill constraints
itself, so adding your own conflicts with them; `glassView.subviews` is always 2 even when empty;
the default `cornerRadius` is 8, not 0.

**Verification method for increments 2–6 is settled, and the obvious approach was wrong.**
Passing `-AppleInterfaceStyle Dark` on the command line does *not* force appearance — the value
lands in `NSArgumentDomain` and `stringForKey:` returns it, but AppKit takes `effectiveAppearance`
from the system setting and ignores it, so both "appearances" would have rendered identically while
the test passed. `NSApp.appearance` is the only mechanism that works, and the generated test runner
creates no `NSApplication`, so the harness must call `sharedApplication` itself or the assignment is
a silent no-op on nil.

What does work: glass renders into an offscreen `cacheDisplayInRect:`. Rendering the same view with
and without a glass subview differs by **0.4436** mean absolute RGB while the region outside the
glass rect is bit-identical, and live `screencapture` of the same window agrees to within 0.015 —
with no visible window, no activation policy, and no screen-recording permission. So the screenshots
are a real test, they run headless, and they run under CI.

**The renders caught a silent regression the test suite could not.** `70d21a88` fixes it and
`1e0f80df` adds the render test that found it.

The migration had shrunk the control from 22 points tall to **16**, and every test still passed.
Handing the display field to the glass as its `contentView` makes AppKit pin the field to fill the
glass, so the field's own 16-point intrinsic height propagated up through the glass and beat the
control's declared 22. It surfaced only because two renders came back byte-identical: at 16 points,
corner radii of 8 and 12 both exceed half the height and clamp to the same pill. The brief's stop
condition — *if any two renders are byte-identical, stop* — was written to catch a broken appearance
override. It caught a layout bug instead.

Five variants were measured against real AppKit before choosing the fix. The height is now pinned at
**priority 999, not required**, which reproduces the original semantics: 22 is the control's natural
height and a host that sets its own still wins (verified — a host forcing 30 gets 30, with the text
still centred). A required constraint would have conflicted with any such host. A holder view
between the glass and the field absorbs the stretching so the glyphs stay centred rather than being
pulled to the full height.

**Task 2 landed earlier — the recorder is on glass.** `776ed70c` modifies
`Frameworks/OakAppKit/src/OakKeyEquivalentView.mm` and adds `t_key_equivalent_view.mm`, taking the
suite to `OakAppKit_test: 16 tests passed`. This is the first application code in the fork to call a
glass constructor. The control now installs an `NSGlassEffectView` as its first subview with the
display string hosted in that view's `contentView`; `drawRect:` is deleted outright, `isOpaque`
returns `NO` so glass has a backdrop to sample, and the focus ring follows the glass's corner radius
instead of a square. Corner radius is provisionally 8, pending the renders.

**A trap worth knowing, now in `CLAUDE.md`.**
`OAK_ASSERT_EQ(view.style, NSGlassEffectViewStyleRegular)` compiles in `t_glass.mm` and fails in a
new test file, because `bin/gen_test` wraps each test file in its own namespace and the `to_s`
overload for that enum lives in the first file. The generic `to_s(_T const&)` fallback then tries to
iterate the enum, and the error — `no viable 'begin' function` — reads as though the assertion is
wrong rather than misplaced. Use `OAK_ASSERT(a == b)`.

**Task 1 landed earlier.** `765eb320` adds the snapshot harness,
`Frameworks/OakAppKit/tests/t_glass_snapshot.mm` (129 lines, one file). It exposes `SnapshotView`,
`WriteSnapshotIfRequested` and `MeanDifference` for Task 3 to reuse, and its own test asserts that
glass actually rendered — a floor of 0.02 against a measured 0.44, so it fails outright if the
capture path ever stops seeing glass. Its implementer had not yet filed its report when this entry
was written, so the reported test count is unconfirmed here; it should read `11 tests passed`.

**If interrupted here:** the SDD ledger is
`.superpowers/sdd/2026-08-14-liquid-glass-small-controls/progress.md`, and it carries the rulings
behind both brief corrections. Briefs 1–3 are written beside it. Tasks 1 and 2 are complete and
committed; Task 1's review came back clean on both verdicts. Confirm state with:

```sh
~/build/textmate-revived/xcode/Release/OakAppKit_test -v --no-parallel   # expect 16, or 17 after Task 3
```

Note that `bin/build` itself never prints a pass count — it execs the runner without `-v` and the
runner is silent on success. Its silence is not evidence that tests did not run.

**The first batch of renders was unusable, and a second harness fix is in flight.** Looking at the
actual images rather than their checksums showed two defects, both in the harness rather than the
control:

1. The text read **"Button"**. `OakCreateCloseButton` loads its image from the OakAppKit framework
   bundle, which a bare test-runner binary does not have, so `NSButton` fell back to drawing its
   default title — wide enough to cover the key-equivalent glyphs completely. A harness artefact
   only; the image loads normally in the app.
2. **The glass had nothing behind it.** `SnapshotView` hosted the control in a plain `NSView` with
   no background, so the glass was refracting a void and came out a flat pale shape in both
   appearances. Glass only shows its character over real content.

The fix gives the host `windowBackgroundColor` — what the control actually sits on in the Bundle
Item Chooser, so the render is representative rather than merely diagnostic — and strips every
non-glass subview before snapshotting. **Checksums alone would never have caught either of these:**
all four digests were distinct and all four images were the right size. Someone has to look.

Remaining: finish the render fix, Task 4 (full suite against the parity doc, plus exercising the
control in the running app via ⌃⌘T — the clear button's real appearance is checked there, since the
harness cannot show it), Task 5 (**maintainer picks the corner radius from the renders — this is the
gate; nothing ships before it**), Task 6 (CHANGELOG, release, confirm the cask bump).

---

## 2026-08-14 — SESSION CLOSE: Phases 5, 5a and Phase 6's foundation shipped

**Read this first on resume.** Everything below is merged to master. Working tree clean.

### Where the project is

| | |
|---|---|
| Released | **v3.0.0-revived.19**, signed, notarized, on GitHub Releases and Homebrew |
| Install | `brew tap sdenike/tap && brew install --cask textmate-revived` |
| Phases done | 0, 1, 2, 3, 4, 5, 5a, and Phase 6's **foundation increment** |
| Phases left | 6 increments 2-6 (the visible glass work), 7 performance, 8 shared modules, 9 optional LSP |

### What shipped this session

**Phase 5 — signing and notarization.** The first signed, notarized release this fork has ever
produced. Getting there meant fixing five silent failures in a pipeline that had never once run:
workflows triggering on `main` when this repo uses `master`; a release guard matching `-undead` when
this fork ships `-revived`; `multimarkdown` missing from two separate workflows; the deleted
`network_test` still in the CI target list, aborting the step and suppressing ten later targets; and
notarization rejecting `PrivilegedTool` for a debug entitlement, because the Mach-O re-sign sweep
never globbed `Resources/`. The in-app updater now works end to end — verified by the maintainer
updating into .18 from inside the app.

**Phase 5a — central Homebrew tap.** `sdenike/homebrew-tap` serves every app on the account.
`hidden-revived` migrated onto it and `sdenike/homebrew-hidden-revived` was deleted. Both repos'
release workflows now bump their cask automatically; verified by cutting .17 and watching
`github-actions[bot]` commit the correct checksum unaided.

**Phase 6 foundation.** Three glass constructors in `OakUIConstructionFunctions`, plus the test
target `OakAppKit` never had. No callers yet, by design. See `CLAUDE.md`'s "Liquid Glass" section.

### Repo-wide defects found and fixed along the way

These were not the task and matter more than it:

1. **Tests silently did not run when changed** — all 28 targets. `gen_test`'s script phases declared
   `outputFiles:` and no `inputFiles:`, so the runner was never regenerated. Anyone doing TDD here
   would have watched a red test pass. Declaring `inputFiles:` would *not* have fixed it (Xcode does
   not glob them); `basedOnDependencyAnalysis: false` did, plus removing `Time.now` from
   `bin/gen_test` so a content comparison could keep builds incremental.
2. **40 framework images never shipped** — the tab overflow button rendered as the literal word
   "Button", per-tab close buttons were invisible, and all 20 Bundle Editor icons were missing.
   Fixed in .18.
3. **The README described a different fork**, told people to install two dependencies removed in
   .6, and the About window shipped that fork's artwork as a full-bleed background.

### Standing constraints that must not be forgotten

- **Never rename** the `com.macromates.*` xattrs in `OakDocument.mm`, the 38 UTIs, or the `txmt://`
  scheme — they are on-disk format in users' own files.
- `CFBundleName` stays `TextMate`; the version string identifies the build.
- **A `CHANGELOG.md` push to master triggers a release.** Do not touch it for changes that are not
  user-visible.
- `bin/deploy-local` installs an **ad-hoc** build that cannot self-update. The maintainer runs the
  signed Homebrew build; do not deploy-local over it.
- Never use `OAK_ASSERT_EQ` on a raw Objective-C object pointer (see `CLAUDE.md`).
- `command_test` is flaky; one run of it is not evidence in either direction.

### Largest outstanding debt

**The bundle catalogue.** `AvailableBundles.plist` has 108 entries, every one pointing at
`textmatelives`, and `DefaultBundles.plist` has 41 — the set a fresh install pulls automatically.
24 files across 13 of those bundles still carry `#!/usr/bin/env ruby18` shebangs. The mandatory four
are now forked under `sdenike` and a `ruby18` shim in our `bundle-support` fork makes those commands
run, but that shim is a stopgap: several also use `iconv`, `parsedate`, `Config::CONFIG`,
`TimeoutError` and `Object#type`, which no shim can rescue.

### If interrupted here

Nothing in flight. Next step is planning **Phase 6 increment 2** (small controls:
`OakKeyEquivalentView`, `OFBFinderTagsChooser`) against the foundation, with screenshots in both
appearances for the maintainer to review — that is where visible change starts.

## 2026-08-14 — Final review found the spec's own explanation was wrong; fixed (`0aa31d5c`)

The whole-branch review returned three Important findings, all in API shape, all fixed in one wave.
**10 tests passing**, full app builds.

**The spec was wrong about why the container exists.** It claimed a `NSGlassEffectContainerView`
alone stops adjacent glass surfaces seaming. The SDK header says the opposite:

> `spacing` — "The default value, zero, is sufficient for batch processing eligible glass effect
> views, while **avoiding distortion and merging effects** for other views in close proximity."
>
> `contentView` — "**Merges descendants together** if the views are sufficiently similar and within
> the proximity specified in `spacing`."

So a default container batches for performance and deliberately does **not** merge, and merging
applies to descendants of `contentView`, not direct subviews. Both now encoded:
`OakCreateGlassContainer(CGFloat spacing = 0)` takes the parameter, and both facts are in the
header comment and the corrected spec. Had this shipped as written, increment 4 would have wrapped
the file browser's header and actions bars in a container, seen no merging, and hunted the wrong
cause.

**Also fixed:** `OakGlassChromeMetrics().cornerRadius` was carried but never applied —
`OakCreateGlassBackground` now applies it, instead of twelve call sites each having to remember;
and `contentInsets` is documented as advisory data for callers' constraints, since
`NSGlassEffectView` has no such property. The tint test asserted only non-nil and used a *static*
colour while the header demands a dynamic one — now asserts the value with `isEqual:` against a
dynamic colour, since test code is exemplar code for adopters.

**My arithmetic error, caught by the implementer.** I told it to expect 11 tests; my own four items
add two to eight. It reported 10, flagged the contradiction, and refused to pad a phantom test to
match the number. That is the right instinct — a test invented to satisfy a stated count tests
nothing.

**If interrupted here.** All plan tasks and the final fix wave are complete; nothing merged, nothing
released, branch not pushed. Remaining before merge: push and let the PR's CI run — it has **never**
executed any of this, and the branch changes build behaviour for all 28 test targets and adds a
target CI has never built. The PR body must name the repo-wide build fix as a change distinct from
the Liquid Glass foundation. Rulings are in
`.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md`.

## 2026-08-14 — Liquid Glass foundation done: 5/5 tasks, 25/25 parity (Task 5)

Branch `phase-6/liquid-glass-foundation`, 13 commits `d805ce4a..a04e6dc4`. Full app build succeeds.
**25 of 25 baseline targets match** `docs/benchmarks/2026-08-12-ninja-parity.md`: `scm` 2/84,
`buffer` 3/26, `file` 1/11, `cf` exit 138, the other 21 pass. Plus `Onigmo` 2 and the new
`OakAppKit` 8.

**A regression I diagnosed and then had to un-diagnose.** `command_test` hung three times on this
branch while passing once on `master`, which looked like something I had broken. It was not. Running
the **same already-built binary** three times gave `exit 0 / 4 tests passed`, then two hangs — so
it is flaky, and my master A/B was a single sample that happened to land on the passing side. The
cause is the one CI already documents: `wait_for_command()` polls `NSApp`, nil in a test binary, so
the completion path fires or does not depending on timing. The parity document described this target
as merely slow; it now carries an addendum saying one run of it is not evidence in either direction.

**What this branch delivers beyond the plan**, and not by scope creep — these surfaced because it
was the first genuine TDD done in this repository:

1. **Tests silently did not run when changed** (28 targets). Adding or editing a test did nothing
   while the suite reported green.
2. **The generated runner then churned on every build**, forcing a recompile and relink of every
   test target. That was my own fix trading one defect for another; the reviewer caught it, and its
   proposed `cmp` guard was itself inert until `<%= Time.now %>` came out of `bin/gen_test`.
3. `CLAUDE.md` now documents three traps that cost real time today: the stale runner, `gen_test`'s
   implicit `namespace <filename>{…}` wrapping and its `to_s` shadowing, and why `OAK_ASSERT_EQ`
   must never be used on a raw Objective-C object pointer.

**If interrupted here.** All five tasks complete and reviewed; the final whole-branch review is in
flight. Nothing is merged and nothing is released — this increment is additive, ships no
user-visible change, and deliberately has **no `CHANGELOG.md` entry**, since a CHANGELOG push to
master triggers the release workflow. Every ruling made on the maintainer's behalf is in
`.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md`, which is also the resume point.
Next after merge: plan increment 2 (small controls) against a foundation that now exists.

## 2026-08-14 — An assertion that destroyed the information it existed to give (Task 3 fix round)

`test_glass_background_hosts_content_via_contentView` used `OAK_ASSERT_EQ(view.contentView, content)`
— two `NSView*`. There is no `to_s` overload for ObjC object pointers, so it silently resolved to
`bin/gen_test`'s generic `to_s(_T const&)`, which range-fors over the pointer. It compiled, emitting
only a `may not respond to 'countByEnumeratingWithState:objects:count:'` warning.

The failure mode is the point: **when that assertion failed**, `to_s` threw
`NSInvalidArgumentException`, the generated runner catches only `std::exception const&`, and the
whole binary aborted with SIGABRT (exit 134) rather than reporting which test failed. An assertion
macro that makes a failure *less* legible than no assertion at all. The reviewer did not merely spot
it — it built a repro and confirmed exit 134.

**That line was verbatim from the brief I wrote.** The implementer followed instructions exactly.
Fixed to `OAK_ASSERT(view.contentView == content)` (`219132ae`), which is how the sibling container
test already avoided the trap, and the warning — the visible tell — is now gone from the build log.
The same round added the missing `translatesAutoresizingMaskIntoConstraints` test for
`OakCreateGlassBackground`, which its sibling had and it did not. Re-review: both ADDRESSED, no new
breakage, and no other `OAK_ASSERT_EQ` on a raw ObjC pointer anywhere in the file. **8 tests passing.**

`CLAUDE.md` now carries the rule, since the reviewer confirmed this was the repo's first such usage
and the warning is easy to wave past.

**Parked with a ruling:** the reviewer is right that this test does not pin *our* constructor's
contract — it exercises `NSGlassEffectView.contentView`'s own setter/getter, which Apple guarantees,
and would pass for a bare `alloc/init`. Kept anyway: our constructor does not set `contentView`, so
there is no behaviour of ours to pin; the test documents the usage the doc comment prescribes, which
is exactly what twelve future call sites will get wrong.

**If interrupted here.** Tasks 1-4 complete. Task 5 (parity) was at 22 of 27 targets, all matching
baseline — `scm` 2/84, `buffer` 3/26, `cf` exit 138, rest passing — with `command`, `editor`,
`file`, `Onigmo`, `OakAppKit` outstanding. Resume from
`.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md`.

## 2026-08-14 — Liquid Glass foundation complete: all three constructors landed (Task 4 of 5)

`OakGlassChromeMetrics` added, commit `52057e6a`. **7 tests passing.** The foundation the whole
phase rests on now exists in `Frameworks/OakAppKit/src/OakUIConstructionFunctions`:

```objc
NSGlassEffectContainerView* OakCreateGlassContainer ();
NSGlassEffectView*          OakCreateGlassBackground (NSGlassEffectViewStyle style, NSColor* tint = nil);
struct OakGlassMetrics { CGFloat cornerRadius; NSEdgeInsets contentInsets; };
OakGlassMetrics             OakGlassChromeMetrics ();
```

All three are **deliberately uncalled** — increments 2-6 of the phase are their consumers. A reviewer
applying YAGNI would flag them; that is pre-adjudicated in the SDD ledger.

**Task 4 needed no `to_s` overload** — its `CGFloat`/`NSEdgeInsets` fields resolved against the
existing numeric overloads. Worth noting because Task 3 had to discover the namespace-shadowing trap
the hard way; carrying that discovery into Task 4's brief meant it did not repeat the search.

**If interrupted here.** Task 5 (parity verification across all 25 baseline targets plus `Onigmo`
and the new `OakAppKit`) is running; the combined Tasks 3+4 review is in flight. The four known-bad
targets must reproduce identically — `scm` 2/84, `buffer` 3/26, `file` 1/11, `cf` SIGBUS 138 — and
this is the first parity run whose results are trustworthy, since before today's fix a changed test
could silently not run. Resume from
`.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md`. Still **no `CHANGELOG.md`
entry**: additive increment, and a CHANGELOG push to master triggers a release.

## 2026-08-14 — Glass constructors 2 of 3 landed; two more build traps documented (Tasks 2-3)

**Task 2** — `OakCreateGlassContainer`, commit `3bf9695b`. **Task 3** — `OakCreateGlassBackground`,
commit `b8934940`. 6 tests passing, all verified registered in the generated runner.

**The stale-runner fix needed a second half.** Setting `basedOnDependencyAnalysis: false` stopped
changed tests being missed, but made an unconditional `mv` bump the runner's mtime every build,
forcing a recompile and relink of every test target every time. The reviewer caught that; its
suggested `cmp -s` guard was then **inert**, because `bin/gen_test:133` emitted `<%= Time.now %>`
into the runner's version string, so two consecutive generations always differed. Confirmed by
diffing them — the timestamp was the only delta. Dropped it (`0f17f727`); "generated just now"
carries no information in a test runner's `--version`. Both properties now verified together: a
no-op build leaves the mtime untouched, and appending a failing test still gives `1 of 3 tests
failed`, exit 1. Fixing either half alone breaks the other.

**A second gen_test trap, found by Task 3 and now in `CLAUDE.md`.** `bin/gen_test` wraps each test
file in `namespace <filename> { … }`. `OAK_ASSERT_EQ` stringifies both operands on failure, so
asserting on a type without `to_s()` will not compile — but defining an overload inside that
implicit namespace **hides the global `to_s` overloads**, breaking unrelated assertions in the same
file. Task 3 hit both in sequence: added `to_s(NSGlassEffectViewStyle)` following
`t_OakCompareVersionStrings.mm`'s precedent, which then broke Task 2's autoresize test until
`using ::to_s;` was added. Neither is scope creep — both are required to make the brief's own tests
compile.

**If interrupted here.** Task 4 (`OakGlassChromeMetrics`) is in flight; Task 5 (parity verification)
not started. Tasks 3 and 4 are to be reviewed together as one unit — same shape, same files. The SDD
ledger at `.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md` records every ruling and
is the resume point. Still **no `CHANGELOG.md` entry**: this increment is additive and a CHANGELOG
push to master triggers a release.

## 2026-08-14 — Every test target silently ignored new tests. Fixed. (Task 2 of 5)

**The important part of this entry is not the task.** While implementing Task 2, the implementer
reported that `bin/build OakAppKit/test` had reused a stale generated runner and reported success
without compiling its edited test. Reproduced directly: appended a test asserting `false`, rebuilt
without clearing anything, and got

```
** BUILD SUCCEEDED **
OakAppKit_test: 2 tests passed        <- the failing test was never compiled or run
```

**Cause.** Each `<name>_test` target's only source is the runner `gen_test.sh` generates into
`$(DERIVED_FILE_DIR)`; that runner is what pulls in `tests/t_*.{cc,mm}`. All **28** of those script
phases declared `outputFiles:` and none declared `inputFiles:`, so Xcode skipped regeneration
whenever the output existed and never learned a test file had changed. **Adding or editing any test
in this repository did nothing, while the suite reported green.** Anyone practising TDD here would
have watched their red test pass.

**Fix** (`f6f3ec51`): `basedOnDependencyAnalysis: false` on all 28 phases — the pattern this project
already uses for its four resource-assembly phases. Same probe afterwards:

```
OakAppKit_test: 1 of 3 tests failed
t_glass.mm:21: Assertion failed: false      <- build exits 1
```

Regression-checked `ns_test`, an untouched framework: 6 tests passed. Cost is a Ruby script globbing
one directory per test build.

**Scope of what this invalidates.** Framework *code* changes were always caught — those recompile
the library and relink the test binary. The blind spot was changes to test files themselves. Past
verification runs in this repo that only exercised existing tests against changed code remain
trustworthy; any past claim that a *newly added* test passed does not.

**Task 2 itself:** `OakCreateGlassContainer` added to `OakUIConstructionFunctions`, commit
`3bf9695b`, 2 tests passing.

**If interrupted here.** Tasks 1-2 complete, 3-5 not started. Resume from the SDD ledger at
`.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md`, which records every ruling. Still
**no `CHANGELOG.md` entry** for this increment: it is additive and a CHANGELOG push to master
triggers a release.

## 2026-08-14 — Phase 6 execution started: OakAppKit_test now exists (Task 1 of 5)

Branch `phase-6/liquid-glass-foundation`, executing
`docs/superpowers/plans/2026-08-14-liquid-glass-foundation.md` subagent-driven. Task 1 committed as
`4cd0e5a8`.

**What Task 1 did.** Added the `OakAppKit_test` target to `project.yml`, regenerated
`TextMate.xcodeproj`, added a placeholder `Frameworks/OakAppKit/tests/t_glass.mm`, and wired
`OakAppKit` into the `--no-parallel` lists in `bin/build` and CI plus CI's `TESTS=` string. The
framework had test files but no target, so `bin/build OakAppKit/test` failed outright and there was
no test cycle to do TDD against.

**`--no-parallel` is now eight frameworks, not seven** — `CLAUDE.md` updated. These tests construct
`NSView`s and Cocoa asserts `NSThread.isMainThread`. Note `gen_test.sh`'s own comment still names
seven, because `OakAppKit_test` postdates the ninja baseline it describes.

**A plan defect that implementation found.** The brief's dependency list omitted `Quartz.framework`
and `libsqlite3.tbd` and the target would not link. The list had been derived from OakAppKit's
`HEADER_SEARCH_PATHS` roots — which describes what *compiles*, not what *links*. `-ObjC` forces the
whole static archive to load, so every transitive SDK dependency of OakAppKit applies to anything
linking it. Ruling: accept the addition. This is precisely the kind of gap a fresh implementer
catches and a plan author does not.

**Verified rather than taken on trust:** `bin/build OakAppKit/test` → BUILD SUCCEEDED;
`OakAppKit_test -v` → `1 test passed`. The IDE's "file not found" and "OAK_ASSERT undeclared"
diagnostics on `t_glass.mm` are **false positives** — clangd lacks the target's
`HEADER_SEARCH_PATHS`; the header resolves through the symlink
`Xcode/include/OakAppKit/OakAppKit/OakUIConstructionFunctions.h`.

**If interrupted here.** Task 1 is committed and under review; Tasks 2–5 are not started. The SDD
ledger at `.superpowers/sdd/2026-08-14-liquid-glass-foundation/progress.md` is the resume point — it
records which tasks are complete and every ruling made. **Do not add a `CHANGELOG.md` entry for this
increment**: it is additive, ships nothing user-visible, and a CHANGELOG push to master triggers a
release.

## 2026-08-14 — Liquid Glass foundation plan written; v.18 shipped and self-updated

**v3.0.0-revived.18 published and installed via Check for Updates.** The maintainer ran the in-app
updater and it downloaded, verified, installed and relaunched — the **first time that path has ever
completed**. Verified afterwards: the running app is `3.0.0-revived.18` signed by
`Developer ID Application: Shelby Denike (485WH9DHS4)`, all **40 of 40** framework images are at the
Resources root including `CloseTemplate` and `TabOverflowThinTemplate`, and the tap cask
auto-bumped to `.18`. The full chain — sign, notarize, publish, bump cask, self-update — now works
end to end.

**Plan:** `docs/superpowers/plans/2026-08-14-liquid-glass-foundation.md`. Five tasks, 31 steps, no
placeholders.

**Task 1 is a prerequisite the spec did not anticipate.** `Frameworks/OakAppKit/tests/` contains
test files but **no `OakAppKit_test` target exists** — `bin/build OakAppKit/test` fails with "does
not contain a target named", and the two files there (`gui_dictionary.mm`, `gui_pop_out.mm`) use
the pre-migration `class X : public CxxTest::TestSuite` style that `gen_test.sh` does not glob. They
have never run. There was no test cycle to do TDD against, so the plan creates the target, which
leaves the framework testable afterwards rather than only for this work. It also adds `OakAppKit`
to the `--no-parallel` list in both `bin/build` and CI, since these tests construct `NSView`s and
Cocoa asserts `NSThread.isMainThread` — making it the eighth such framework.

**The plan deliberately covers the foundation only.** Increments 2-6 are unplanned. The spec's own
rationale is that increments 2-3 exist to *learn* how glass behaves against TextMate's layout —
whether `NSGlassEffectView` fights manual frame arithmetic, how `contentView` hosting interacts
with existing constraints, what tint each surface needs. Writing confident bite-sized steps for
those now would mean inventing the answers. Each adoption increment gets planned after the
foundation exists and its target file has been read.

**If interrupted here.** Nothing implemented yet — the plan is written and committed, awaiting the
maintainer's choice between subagent-driven and inline execution. The foundation increment is
additive and ships nothing user-visible, so it must **not** get a `CHANGELOG.md` entry: a
CHANGELOG push to master is what triggers a release.

## 2026-08-14 — v3.0.0-revived.18 was cancelled by a CI timeout; two causes, both fixed

**The release did not publish.** Its `verify/test` job was cancelled, so `release` was skipped and
`.17` remained latest. Two compounding causes:

1. **`timeout-minutes: 15` was too tight.** The job ran **15m21s** and was killed mid-step at the
   limit.
2. **Every release ran the test suite twice, concurrently.** A `CHANGELOG.md` push to master
   triggers `ci.yml` (push to master, no path filter) *and* `release.yml` (push + `paths:
   CHANGELOG.md`), and **both call the same reusable `build-and-test.yml`**. The evidence is
   direct: for commit `9c6de4c`, CI's test job finished in **9m09s** while the release run's
   identical job hit the timeout at **15m21s**. Same tests, same commit, same runner image — the
   difference is contention between the two concurrent runs.

**Fixes.** Timeouts raised 15 → 30 minutes for both `build` and `test`, since 15 was marginal even
uncontended. And `ci.yml` now carries `paths-ignore: [CHANGELOG.md]`: a CHANGELOG-only push *is* a
release, and `release.yml`'s verify job already runs the same suite, so CI duplicating it is pure
waste. `paths-ignore` skips only when **every** changed path matches, so a commit touching
CHANGELOG.md alongside code still gets CI — the case that matters is not weakened.

Worth noting what did *not* cause it: no `concurrency:` block exists in any workflow, so nothing
cancelled it by policy, and the cancellation was not manual.

**If interrupted here.** The .18 fix (40 missing framework images) is committed on master but
**unreleased** — no `v3.0.0-revived.18` tag exists, and `CHANGELOG.md` still has .18 at the top, so
re-running Release via `workflow_dispatch` will pick it up and publish correctly.

## 2026-08-14 — Phase 6 designed: Liquid Glass. Spec written, awaiting review

**Spec:** `docs/superpowers/specs/2026-08-14-liquid-glass-design.md`. Design settled through
brainstorming; **not yet approved, and no implementation plan written**.

**Decisions, each with evidence rather than preference:**

- **PR #1469 is out of scope.** +19,490/−5,877 across 550 files. It adds whole new applications
  (CompareMate, SyntaxMate, QuickLookExtensions) and reintroduces 11 `.rave` files — the build
  system Phase 2 deleted. There is no "UI part" that lifts out cleanly.
- **Native `NSWindow` tabbing is rejected**, after initially being the maintainer's preference.
  `DocumentWindowController` holds `NSArray<OakDocument*>` in **one** `NSWindow` with **one**
  `fileBrowser`, and `restoreSession` iterates `session["projects"]`, one entry per window. **A
  window in TextMate is a project, not a document.** Native tabbing means one project per tab —
  open five files from a folder and get five file browsers onto it. TextMate already decided this
  deliberately: `AppController.mm` sets `allowsAutomaticWindowTabbing = NO`.
- **The custom tab bar is kept and modernised**: glass background, and its close/overflow/new-tab
  controls are *already* standard `NSButton`/`OakRolloverButton`, so they need no change.

**The maintainer's suggestion to look at iTerm2 paid off three times**, and is why the spec is
better than it would have been:

1. iTerm2 uses a custom `PSMTabBarControl`; `allowsAutomaticWindowTabbing` appears nowhere in
   their tree. A mature app with well-regarded tabs made the same call, for the same structural
   reason — their windows hold many sessions.
2. **It corrected the foundation's API.** Their `iTermOpenQuicklyView.m` shows
   `NSGlassEffectView` hosts content through `.contentView`, not by adding subviews, and that they
   apply a dynamic light/dark `tintColor`. Getting that wrong would have been one mistake
   propagated to all 12 call sites.
3. **It corroborated the sequencing.** Their glass adoption covers the Open Quickly chooser, chat
   toolbar and a text-field container — overlays and choosers — with the tab bar untouched.
   Independently the same ordering the spec had chosen.

Their code carries an `@available(macOS 26, *)` guard with an `NSVisualEffectView` fallback. That
is dead code here: this fork's deployment target *is* macOS 26, so old paths get deleted rather
than branched around.

**Shape:** a three-constructor foundation in `OakUIConstructionFunctions` (already imported by 46
files, so widening an existing seam), then six increments ordered by blast radius — small controls
and overlays first, tab bar last — each shipping as its own release. Verification is screenshots in
both appearances, reviewed by the maintainer, since no UI test infrastructure exists and a visual
regression is invisible to the suite.

**If interrupted here.** The spec awaits maintainer review. On approval the next step is the
`writing-plans` skill to produce the implementation plan — no code until then. Release
v3.0.0-revived.18 (the 40 missing framework images) was still in its `verify/test` job when this
was written; once published it should be installed via **Check for Updates**, which now has a
matching Team Identifier on both sides and has never been exercised successfully.

## 2026-08-14 — All 40 framework image assets were missing from the app (v3.0.0-revived.18)

**Found by the maintainer noticing the literal word "Button" in the tab bar.** That is AppKit's
default `NSButton` title: an `NSButton` with neither image nor title draws it. The overflow button's
only visual is `regularImage = [NSImage imageNamed:@"TabOverflowThinTemplate" inSameBundleAsClass:]`,
which was returning nil.

**Cause.** Every PNG under `Frameworks/*/gfx/` — 40 files across OakTabBarView (14), BundleEditor
(20) and OakAppKit (6) — was in the repository but never copied into the built app. `project.yml`
contains no `gfx` reference at all. The Phase 2 XcodeGen migration dropped them, and they shipped
missing in v3.0.0-revived.16 and .17.

**Why it went unnoticed for two releases.** The failure is completely silent. `imageNamed:` returns
nil, the button draws a default title, the build succeeds, every test passes. Nothing anywhere
reports a missing asset. Also broken and unnoticed: the per-tab close button (`CloseTemplate` plus
five `TabCloseThin*` variants) and all 20 Bundle Editor item icons.

**Fix.** `assemble_resources.sh` now copies them flat into `Contents/Resources`. Flat matters: the
frameworks are statically linked (there is no `Contents/Frameworks`), so
`+[NSBundle bundleForClass:]` resolves to the app bundle itself and `imageNamed:` searches the
Resources root — a `gfx/` subdirectory would not be found. Verified all 40 basenames are unique
before flattening, so nothing silently overwrites.

**Caught an off-by-one in my own fix.** The first version copied 39 of 40. `Proxy.png` in
`BundleEditor/gfx/Bundle Item Icons/` is a **symlink** to `Settings.png`, and `find -type f`
excludes symlinks. Now `\( -type f -o -type l \)`; `cp` follows the link and writes a real file.
The acceptance check that missed it was "at least 40 PNGs in Resources" — which passed at 42 by
counting three unrelated PNGs in `About/` and `TextMate Help/` subdirectories. **Counting a
superset is not verification**; the correct check compares the exact expected set against the
Resources *root*, which is what the fix now uses.

**Not deployed with `bin/deploy-local` on purpose.** The maintainer is now running the signed
Homebrew build, and deploy-local would replace it with an ad-hoc build that cannot self-update
(see "Bundle delivery" in `CLAUDE.md`). Shipping this as .18 instead, which also exercises the
in-app updater for the first time on a properly signed pair.

**If interrupted here.** Phase 6 design is paused mid-way: scope (Liquid Glass only), depth
(replace custom views with standard controls), sequencing (low-risk first, tab bar last),
verification (screenshots reviewed by the maintainer), approach A (foundation first) and the
six-increment migration sequence are all agreed. **Next design section is the tab bar decision** —
whether to adopt native `NSWindow` tabbing.

## 2026-08-14 — Cask automation proven end to end (v3.0.0-revived.17)

**Phase 5a is closed.** `HOMEBREW_TAP_TOKEN` is set on both `sdenike/textmate` and
`sdenike/hidden-revived`, and the automation has now run for real.

Cutting v3.0.0-revived.17 was the only way to test it: the tag for `.16` already existed, so a
re-run stops at the tag check and never reaches the cask step. The release note is genuine rather
than filler — Homebrew availability is real user-facing news.

**Result — all three jobs green, and the bot did the work:**

```
verify/build [success]   verify/test [success]   release [success]
tap commit:  "textmate-revived 3.0.0-revived.17"   by github-actions[bot]
cask:        version "3.0.0-revived.17"
             sha256  "882833deafd39d365f0d3f28bbb7c7f40041ad1f5f5fc730fca70fdf23b3e3df"
```

**Verified rather than assumed.** Downloaded the published asset and compared: its sha256 is
`882833de…`, byte-identical to what the workflow wrote into the cask. A wrong checksum here would
fail every `brew install` while looking perfectly fine in the diff, so this is the check that
matters. `brew info --cask sdenike/tap/textmate-revived` now offers `3.0.0-revived.17`.

**hidden-revived cannot release yet.** It has only `HOMEBREW_TAP_TOKEN`; its workflow signs and
notarizes before reaching the cask step, so it needs five more secrets —
`MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_ID`,
`APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`. Same underlying credentials as TextMate's, different names
(`KEYCHAIN_PASSWORD` is new and arbitrary). It also versions differently: `MARKETING_VERSION` in
the Xcode project, triggered by pushing a `v*` tag, not by a changelog edit.

**If interrupted here.** Phases 0-5a are done. Next is **Phase 6 — Liquid Glass + PR #1469's UI
work**. Largest outstanding debt remains the bundle catalogue: 108 `AvailableBundles.plist` entries
pointing at `textmatelives`, 41 installed by default on first launch.

## 2026-08-14 — Phase 5a: central Homebrew tap, with automatic cask bumps

**What.** Created `sdenike/homebrew-tap` as one tap for every application on this account,
replacing the tap-per-app pattern. Seeded it with `textmate-revived` (new) and `hidden-revived`
(carried over unchanged from `sdenike/homebrew-hidden-revived`). Added a cask-bump step to
`release.yml`. Tracking issue: sdenike/textmate#10; the hidden-revived side is
sdenike/hidden-revived#3.

**Why central.** A tap per app means a new repository each time something ships, and users running
a separate `brew tap` for each. One tap: `brew tap sdenike/tap` once, and everything added later is
immediately installable.

**Verified against real Homebrew, not by inspection.** Tapped it locally and ran
`brew audit --cask` on both casks — clean, no warnings. `brew info` resolves
`textmate-revived 3.0.0-revived.16 (auto_updates)` with `Required: arm64 architecture, macOS >= 26`
and the `TextMate.app` artifact. The sha256 is the real one, computed from the published
`.tbz` (`4bee83a3…`).

Caught one thing that way: `depends_on macos: ">= :tahoe"` is the deprecated string-comparison
form and warned on every invocation, though it resolved identically. The bare symbol
`depends_on macos: :tahoe` already means "this version or newer". Also worth noting the local tap
does not refresh on `brew untap && brew tap` — that restores from cache, so verifying a pushed
change needs `git -C $(brew --repository)/Library/Taps/sdenike/homebrew-tap pull`.

**Automation shape.** The bump step commits **directly to the tap's default branch**, not via a
pull request. A PR per release would need merging every time, which is the manual step the
automation exists to remove; the tap's commit history serves as the record. The step is guarded:
it checks for `HOMEBREW_TAP_TOKEN` first and, if absent, emits a warning and succeeds, so a missing
token can never fail an otherwise-good release. It also verifies both substitutions landed before
committing, rather than trusting `sed`.

**Blocked on the maintainer for one thing.** `HOMEBREW_TAP_TOKEN` must be a PAT with
`contents: write` on `sdenike/homebrew-tap`, set as a secret on both `textmate` and
`hidden-revived`. A workflow's built-in `GITHUB_TOKEN` is scoped to its own repository and cannot
push to the tap.

**Phase 5a complete.** Both PRs merged on green CI — sdenike/textmate#11 (build 4m52s, test 7m5s,
scan) and sdenike/hidden-revived#4 (that repository runs no PR CI). Issues #10 and #3 both closed
by their merges. `sdenike/homebrew-hidden-revived` is deleted; before deleting it, its MIT `LICENSE`
was carried into the new tap and the cask confirmed byte-identical (same sha256) so nothing was
lost with the repository.

Final state: `brew tap sdenike/tap` serves `textmate-revived` and `hidden-revived`, both audit
clean, both resolving from `sdenike/homebrew-tap`.

**Mistake worth recording: `brew untap --force` uninstalls, it does not preserve.** This machine had
Hidden Bar installed *from the old tap*, so after deleting that repository `brew update` failed with
`fatal: repository … not found`. Plain `brew untap` refused ("Would untap … after uninstalling the
following casks"), so `--force` was used on the expectation that it would detach the tap and leave
the installed app alone. It did not — it removed `/Applications/Hidden Bar Revived.app`.

Recovered immediately with `brew install --cask sdenike/tap/hidden-revived`: same version 2.1.0,
now sourced from the new tap. **Settings survived** — the app is sandboxed, so its preferences live
in `~/Library/Containers/com.sdenike.hiddenbar/`, and an uninstall (unlike `--zap`) does not touch
container paths. Verified `com.sdenike.hiddenbar.plist` still present in the container afterwards.

The correct order, for next time: **reinstall from the new tap first, then untap the old one** — or
accept the uninstall/reinstall cycle knowingly rather than trusting `--force` to be non-destructive.

**Still outstanding, and only the maintainer can do it:** `HOMEBREW_TAP_TOKEN` — a PAT with
`contents: write` on `sdenike/homebrew-tap` — must be set as a secret on **both** `sdenike/textmate`
and `sdenike/hidden-revived`. Until then both bump steps warn and skip; releases themselves are
unaffected.

## 2026-08-14 — FIRST SIGNED, NOTARIZED RELEASE PUBLISHED (v3.0.0-revived.16)

**Shipped.** <https://github.com/sdenike/textmate/releases/tag/v3.0.0-revived.16> —
`TextMate-3.0.0-revived.16.tbz`, 11,812,507 bytes. All three jobs green: `verify/build`,
`verify/test`, `release`.

**Verified independently**, by downloading the published asset rather than trusting the workflow's
own assertions:

```
codesign --verify --deep --strict   valid on disk; satisfies its Designated Requirement
codesign -dv                        flags=0x10000(runtime)   <- hardened runtime
                                    Authority=Developer ID Application: Shelby Denike (485WH9DHS4)
                                    Authority=Developer ID Certification Authority
                                    Authority=Apple Root CA
spctl --assess --type execute       accepted, source=Notarized Developer ID
xcrun stapler validate              ticket stapled (so first launch works offline)
```

**What it took, from a pipeline that had never once run.** Five failures, each hiding the next:

1. `ci.yml`/`release.yml` triggered on `main`; this repository uses `master` — nothing ever ran.
2. `release.yml` guarded on `-undead` versions; this fork ships `-revived` — would have skipped.
3. `build-and-test.yml` never installed `multimarkdown`, which `bin/gen_html:67` requires.
4. Its `TESTS` list still named the `network_test` target deleted in `42e674ce`, aborting the step
   and silently suppressing ten later targets.
5. `release.yml` had no dependency-install step at all, so the signed build hit (3) again.
6. Notarization rejected `Contents/Resources/PrivilegedTool` for
   `com.apple.security.get-task-allow` — the Mach-O re-sign sweep never globbed `Resources/`, and
   the nested-bundle re-seal only handles bundles, so a bare executable fell between them.

**Phase 5's core objective is met**: Developer ID signing, notarization, and GitHub Releases
delivery all work end to end, and the in-app updater points at this repository, so an installed
v3.0.0-revived.16 can now actually receive updates.

**If interrupted here.** Master clean; the release is public. Remaining Phase 5 surface: nothing
blocking. Next phases — 5a (Homebrew tap, migrate `hidden-revived` onto it), 6 (Liquid Glass +
PR #1469 UI), 7 (performance), 8 (shared modules), 9 (optional LSP). The bundle catalogue remains
the largest known debt: **108 `AvailableBundles.plist` entries all pointing at `textmatelives`, 41
of them installed by default on first launch.**

## 2026-08-14 — Signing works end to end; notarization rejected PrivilegedTool

**Progress.** With build dependencies added, the release run got through building signed, locating
the app, re-signing embedded Mach-Os, re-sealing nested bundles, re-signing the outer app, and
`codesign --verify --deep --strict` plus the hardened-runtime assertion. It failed at **step 14,
Notarize via notarytool**:

```
"status": "Invalid", "statusSummary": "Archive contains critical validation errors"
path:    TextMate.app/Contents/Resources/PrivilegedTool
message: The executable requests the com.apple.security.get-task-allow entitlement.
```

**Cause.** `get-task-allow` is the debug entitlement; Apple rejects any notarized archive
containing it. Two sweeps were meant to cover this and neither reached the file:

- *Re-sign every embedded Mach-O* globbed only `*/Frameworks/*`, `*/MacOS/*`, `*/SharedSupport/*`
  and `*/PlugIns/*`. `Contents/Resources/` was not in the list.
- *Re-seal nested bundles* handles `.tmplugin`, `.framework`, `.qlgenerator`, `.appex` — but
  `PrivilegedTool` is a **bare Mach-O**, not a bundle.

So it kept its build-time signature. Only the *outer* app is re-signed with
`CS_GET_TASK_ALLOW=false`; that substitution never reached the nested executable. Note
`CS_GET_TASK_ALLOW` appears nowhere in `Base.xcconfig` or `project.yml` — it exists only as a
placeholder in `Applications/TextMate/Entitlements.plist` that `release.yml` seds. The entitlement
on `PrivilegedTool` is Xcode's own auto-injected debug entitlement, not something the project asks
for.

**Fix.** Added `-o -path "*/Resources/*"` to the Mach-O sweep. `PrivilegedTool` is `type: tool` in
`project.yml` with no entitlements of its own, so re-signing it without `--entitlements` strips the
debug entitlement and removes nothing legitimate. The existing `file -b | grep Mach-O` guard keeps
ordinary resource files untouched.

**Unrelated:** `claude doctor` reported `Last update attempt: failed (install_failed)`, but
`claude update` reports 2.1.232 is current — that failure was transient.

**If interrupted here.** Fix committed; next release run needs triggering via `workflow_dispatch`.
Still no tag and no release — `gh release list` is empty. Notarization is step 14 of 16, so the
remaining unproven steps are stapling, Gatekeeper verification, the `.tbz`, and publishing.

## 2026-08-14 — Release secrets work; release.yml had no dependency install step

**Secrets are in and correct.** All five set on `sdenike/textmate`. The release run past them:

```
verify / build  [success]
verify / test   [success]
release         [failure]  — step 7: Build signed TextMate.app
```

Step 6, **Import signing certificate into temporary keychain, now passes** — the `.p12`, its
password and the notarization credentials are all valid. That was the previous stopping point.

**The new failure.** `PhaseScriptExecution Assemble resources (TextMate)` again — the same
`multimarkdown` problem fixed earlier for `build-and-test.yml`. Cause: **`release.yml` has no
dependency install step whatsoever.** The `release` job deliberately builds its own app rather than
reusing `verify`'s artifact, so it needs the dependencies in its own right and never had them.
Added `brew install mercurial subversion multimarkdown` before the certificate import.

**`docs/RELEASING.md` was wrong about this too** — it listed "4. Install deps via Homebrew
(`:85-87`)" describing a step that did not exist. When rewriting that document earlier I corrected
its fork-specific details (branch, version suffix, URLs, the update mechanism) but took its
step-by-step description of the workflow on trust rather than checking it line by line. Corrected,
with a note about why the gap was invisible.

**Pattern worth naming:** every one of these — `main` vs `master`, `-undead` vs `-revived`, missing
`multimarkdown` in two separate workflows, the deleted `network_test`, this missing install step —
was latent for the same reason. A pipeline that cannot run cannot fail, so its rot is silent and
its documentation drifts unchallenged. Each fix has bought exactly one more step of progress, which
is the expected shape when unwinding an inherited pipeline that has never once executed.

**If interrupted here.** Fix committed; the next release run needs triggering via
`workflow_dispatch`. No tag or release exists yet — `git ls-remote --tags origin` and
`gh release list` are both still empty, and tagging is step 15, well downstream of the failure.

## 2026-08-14 — PR #9 merged on green CI; first Release run reaches the signing step

**Merged.** PR #9 is on master as `f20b6625` after three CI rounds, each exposing the next latent
failure — `multimarkdown` missing, then the deleted `network_test` still in the target list, then
green: build 2m50s, test 7m54s across 19 targets, scan 12s. First green CI run this repository has
ever had.

**The Release workflow then fired on master for the first time**, because merging pushed
`CHANGELOG.md` — precisely the trigger that was repaired. `v3.0.0-revived.16` passed the new
`-revived` guard. Result:

```
verify / build  [success]
verify / test   [success]
release         [failure]  — step 6: Import signing certificate into temporary keychain
```

That is the ideal outcome for a run with no credentials. The release job's own fresh build-and-test
gate passed, and it failed exactly where it must without secrets. **Empirically, the five secrets
are the only thing left between this repository and a signed, notarized release** — everything
upstream of signing is proven working, not assumed.

**Nothing was published.** `git ls-remote --tags origin` and `gh release list` are both empty:
tagging and release creation are steps 13-14, well downstream of the step-6 failure, so a
credential-less run cannot leave a bad tag behind. Re-running after adding secrets is therefore
safe and needs no cleanup.

**If interrupted here.** Master is clean at `f20b6625`, v3.0.0-revived.16 deployed locally. The next
action is the maintainer's: follow `docs/RELEASING.md`'s "First-time setup" to export the Developer
ID identity as a `.p12` and set `MAC_CERTIFICATE_P12`, `MAC_CERTIFICATE_PWD`, `APPLE_ID`,
`APPLE_ID_PWD` and `APPLE_TEAM_ID`, then re-run the Release workflow via `workflow_dispatch`.

## 2026-08-14 — First CI run in this repository's history; it failed, then was fixed

**What.** Fixing the workflow branch triggers made CI actually run on a pull request for the first
time ever. It failed both jobs immediately, which is exactly what it was supposed to do.

**The failure.** `** BUILD FAILED **` in the `Assemble resources (TextMate)` script phase, with one
decisive line:

```
Unable to find a markdown compiler
```

`bin/gen_html:67` declares `MARKDOWN_COMPILERS = %w[ multimarkdown ]` and searches for that binary
alone. `.github/workflows/build-and-test.yml` installed only `mercurial subversion` — the two
needed by `scm`'s tests — and never `multimarkdown`, which every About/Legal/Contributions page
goes through. Added to both the `build` and `test` jobs.

**Pre-existing, not a regression.** The workflow triggered on `branches: [main]` while this
repository's default branch is `master`, so it had never once run and the missing dependency could
not surface. This was the first time the build had been exercised on a clean machine rather than a
developer laptop that happens to have `multimarkdown` from an earlier Homebrew install. Diagnosing
it needed the jobs API (`/actions/runs/<id>/jobs`) to name the failing step — `gh run view
--log-failed` returned 51 KB of compiler warnings with the actual error nowhere near the end.

**Noted, not fixed:** `bin/gen_html` has `abort "Unable to find a markdown compiler" if
filter.nil?` twice, at lines 70 and 78. The second is dead — `filter` is already proven non-nil by
line 70. Harmless, out of scope here.

**Second failure, after multimarkdown fixed the first.** `build` then passed in 3m0s, but `test`
still failed at 5m0s with exit 65 and no `FAILED: <target>` line — meaning a *build* failure inside
the test job, not an assertion:

```
xcodebuild: error: The project 'TextMate.xcodeproj' does not contain a target named 'network_test'.
```

`build-and-test.yml`'s hardcoded `TESTS` list still named `network_test`. The framework was deleted
in `42e674ce`; the parity document already records the resulting 26 → 25 drop, and this same
staleness turned up earlier today when running the suite locally. Because the list is iterated in
order and xcodebuild aborts the step, every target after `io_test` never ran at all. Removed;
the list is now the 19 CI-included targets.

Both of these had the same root cause as each other: **a workflow pointed at a branch that does not
exist in this repository cannot fail, so its bugs accumulate silently.** Two of them had.

**If interrupted here.** PR #9 carries the update-feed fix, the workflow trigger fixes, the
rewritten `docs/RELEASING.md`, and two CI fixes (`multimarkdown`, `network_test`). **Do not merge
until CI is green.** No CHANGELOG entry for the CI work: nothing in the shipped application
changed.

## 2026-08-13 — Update feed pointed at another fork; Phase 5 surveyed (v3.0.0-revived.16)

**The bug.** `AppController.mm:497` set the software-update feed to
`https://github.com/textmatelives/textmate.git/info/refs?service=git-upload-pack`.
`OakUpdateAssetURLForVersion` derives the download URL from that same host and path, so the
updater checked a third party's tags and would have offered their release assets. Same class of
problem as the bundle pins, found by sweeping for `textmatelives` after fixing those.

It **failed safe** rather than dangerously: `OakDownloadManager` validates the extracted bundle's
Developer ID against the installed app's Team Identifier, so a foreign build would have been
rejected. But updates could never succeed, and version comparison ran against someone else's tags.
Now points at `sdenike/textmate`, with a comment saying it must track whatever repository we sign
releases in.

Also repointed the About window's feedback link and the Contributions page's commit/tree links,
which sent users to that other project. The `commits/main` link also had the wrong branch for this
repository.

**Phase 5 is much further along than the roadmap suggests.** Survey findings:

- `.github/workflows/release.yml` already does the whole chain: imports a Developer ID cert from
  secrets into a temporary keychain, builds signed, re-signs every embedded Mach-O with
  `--options runtime --timestamp`, re-seals nested bundles (`.tmplugin`, `.framework`,
  `.qlgenerator`, `.appex`), substitutes `CS_GET_TASK_ALLOW=false`, notarizes via `notarytool`,
  staples with a retry loop, and verifies with `spctl`.
- `SoftwareUpdate` already targets GitHub Releases and verifies Developer ID by Team Identifier.
- `ENABLE_HARDENED_RUNTIME = YES`; entitlements exist for the app and `mate`.
- A valid **Developer ID Application: Shelby Denike (485WH9DHS4)** identity is present locally.

**What actually blocks a release — configuration, not code:**

1. **No GitHub secrets are set.** `gh secret list --repo sdenike/textmate` returns empty with
   exit 0, so this is a real empty list, not a permissions failure. `release.yml` needs
   `MAC_CERTIFICATE_P12`, `MAC_CERTIFICATE_PWD`, and the notarization Apple ID / team ID /
   app-specific password.
2. **`release.yml` has never run** — `gh run list --workflow=release.yml` is empty.
3. `Base.xcconfig` sets `CODE_SIGN_IDENTITY = -` (ad-hoc) and no `DEVELOPMENT_TEAM`, which is
   correct for local builds but means only CI produces a signed app.

These are the maintainer's to supply — a `.p12` and notarization credentials cannot and should not
be uploaded on their behalf.

**Sizing the remaining bundle work properly.** The sweep also showed the bundle catalogue is far
larger than the earlier "13 bundles" framing: `AvailableBundles.plist` has **108 entries, every one
pointing at `textmatelives`**, and `DefaultBundles.plist` has **41** — the set a fresh install
pulls automatically. So a first launch still fetches 41 bundles from a third party. That is the
real scope of the deferred bundle phase, and it is much bigger than the 13 bundles with broken
shebangs.

**Then: the release pipeline could never have fired.** Two inherited textmatelives assumptions in
the workflows, both silent:

1. `release.yml` triggered on `branches: [main]`. This repository's default branch is `master`, so
   pushing `CHANGELOG.md` never started a release.
2. Its guard was "Skip if not an **-undead** release", matching `*-undead*`. This fork versions as
   `-revived`, so even a manual `workflow_dispatch` would have skipped with a notice.

The workflow was half-migrated already — `if: github.repository == 'sdenike/textmate'` and the
`textmate-revived` build path were updated, but the trigger and guard were not. Both fixed.

**And CI has never run on a single pull request here.** `ci.yml` triggered on `main` for both
`push` and `pull_request`, while `gitleaks.yml` correctly used `master`. That is why every PR in
this session showed exactly one check (`scan`) — `build-and-test` was never invoked. Fixed.

**The `.p12` question.** There is **no `.p12` anywhere** in the home directory. What exists are
`AuthKey_*.p8` App Store Connect API keys under `~/.appstoreconnect/private_keys/` — a different
credential, for API/notarytool authentication, not code signing. The signing identity lives in the
login keychain (`Developer ID Application: Shelby DeNike (485WH9DHS4)`); a `.p12` is how it gets
into CI and has to be exported once.

`sdenike/hidden-revived` uses the same scheme under different secret names
(`MACOS_CERTIFICATE`/`MACOS_CERTIFICATE_PASSWORD`/`APPLE_APP_PASSWORD` vs this repo's
`MAC_CERTIFICATE_P12`/`MAC_CERTIFICATE_PWD`/`APPLE_ID_PWD`) — and it has **no secrets set either**;
its one release run failed in 17 seconds. Verified via
`gh api repos/<r>/actions/secrets` returning `{"total_count":0}` with a 200, not a 403 — the
earlier `gh secret list` empty output could have been a scope problem, so it was re-checked
explicitly.

`docs/RELEASING.md` was still textmatelives' document: `-undead` versions, `main` branch,
`textmatelives/textmate` URLs, and a "How users get the update" section describing an
`api.github.com/releases/latest` poll the code does not do (it reads the git ref advertisement and
*derives* the asset URL). Rewritten, with a new **First-time setup** section covering the `.p12`
export, the app-specific password, the five `gh secret set` commands, deleting the exported `.p12`
afterwards, and dry-running via `workflow_dispatch`.

**If interrupted here.** Committed on `fix/update-feed-points-at-fork`, PR #9. Nothing blocks the
next step except the maintainer adding those five secrets — that is the only remaining gate on a
first signed, notarized release.

## 2026-08-13 — Own bundle forks created; ruby18 shim ships (v3.0.0-revived.15)

**What.** Forked the four mandatory bundles under `sdenike`, repointed `MandatoryBundles.h`,
pushed a `ruby18` compatibility shim into our own Bundle Support fork, and upstreamed the Source
macro fix so it is no longer wiped by pin bumps. The release depends on no third-party repository
any more.

| Pin | Now | SHA |
|---|---|---|
| Bundle Support | `sdenike/bundle-support.tmbundle` | `e828e72c` (shim added) |
| Text | `sdenike/text.tmbundle` | `34ab5891` (unchanged) |
| Source | `sdenike/source.tmbundle` | `36685fda` (shebang fixed) |
| Themes | `sdenike/themes.tmbundle` | `e6e91850` (unchanged) |

**Checked before trusting the move:** each fork's HEAD sat exactly at the previously pinned SHA,
so `git log <oldpin>..HEAD` shows only our own commit in each case. No upstream drift rode along
with the repoint.

**The monorepo idea does not work.** `sdenike/textmate-bundles` holding everything was the ask,
but `BundleFetcher` parses a URL into owner/repo only, fetches
`codeload.github.com/{owner}/{repo}/tar.gz/{ref}`, and validates `info.plist` at the tarball root.
One bundle per repository is baked in; a monorepo needs a fetcher rewrite. Hence four forks.

**The shim, and why `-EUTF-8`.** `Support/shared/bin/ruby18` sits beside the existing `ruby` shim
and routes to `${TM_RUBY:-/usr/bin/ruby}`. It rewrites any `-K` flag to `-EUTF-8`: Ruby 2.6 accepts
`-K` but warns it is 1.8 compatibility, while dropping it is actively wrong — with `LANG` unset,
which is normal for a bundle command, `default_external` falls back to US-ASCII and non-ASCII text
breaks. Tested against all five shebang forms found in the wild; all five now execute, and the
`-w -d` variant's `LoadError` chatter is `ruby -d`'s own output, reproduced by plain `ruby -d`.

**This is a stopgap and that is recorded in three places** — the shim's header, the Bundle Support
pin comment, and the changelog. The 13 affected bundles still need forking and porting: several
also use `iconv`, `parsedate`, `Config::CONFIG`, `TimeoutError` and `Object#type`, which raise
under 2.6 and which no shim can rescue. The shim gets them to the point of failing on their real
incompatibilities instead of on a missing interpreter.

**Bonus catch: the rave purge was being silently undone.** The first real re-fetch of Bundle
Support since Phase 2 reintroduced `src/default.rave` and `find_app.cc` as untracked files —
`d07cc0c8` deleted that directory from the repository, but `fetch_embedded_bundles.sh` only
scrubbed `.github/` and `CocoaDialog.app/`, so the tarball put it back. `src/` is now scrubbed
too. The prebuilt `find_app` binary ships in `Support/shared/bin`, so the sources have no runtime
use. Two `.rave` files still exist in the vendored Dialog plug-ins from Task 2b — pre-existing,
untouched here.

**Verification.** Build SUCCEEDED. Shim present in the built app; a real `ruby18 -wKU` shebang
executed through the built app's copy returns `ext=UTF-8` with non-ASCII intact. `src/` absent from
the built app.

**Merged.** PR #8 merged to master as `a1df7c19`, carrying v3.0.0-revived.14 and .15. Branch
deleted, master synced, tree clean. The PR's title and body were rewritten before merging — it had
been opened as a narrow shebang fix and grew into the fork migration, so the description no longer
matched its contents.

**Post-merge verification.** `BundlesManager/test` and `bundles/test` pass. The app relaunches and
rebuilds its bundle index (`Bundles.plist` and `BundlesIndex.binary` both rewritten at launch). The
shim is present in the installed app *and* in the `Managed/` copy, which is the one bundle commands
actually resolve against.

**If interrupted here.** Nothing in flight. Next: Phase 5 — Developer ID signing, notarization,
in-app updates from GitHub Releases.

## 2026-08-13 — BLOCKER found: no write access to the mandatory bundle repos. Deferring bundles.

**Decision (maintainer).** Leave the remaining 24 broken files alone for now and carry on with the
main build. Eventually stand up our **own** bundle repository with the updated bundles and repoint
the pins at it, rather than depending on `textmatelives`.

**Why the question came up.** The proposal was to comment the 13 affected bundles out of the
installer so nobody installs them until they are fixed. Measured, that trades badly: **25 broken
items out of ~700**, and 11 of the 13 ship grammars. Hiding them removes syntax highlighting for
Java, Python, Ruby, HTML, Markdown, Perl, Lua, YAML, Groovy and Cron to suppress 3.6% of their
items. Ruby alone is 2 broken of 201.

**And hiding is not the cheap option.** `AvailableBundles.plist` lives inside
`Bundle Support.tmbundle/Support/` — a sha-pinned, regenerated bundle — so editing the catalogue
needs exactly the same write access as fixing the bundles outright.

**The blocker.** Verified via the GitHub API: this account has `push=false`, `admin=false` on
`textmatelives/{bundle-support,text,source}.tmbundle` and belongs to no organizations. Those three
are pinned **mandatory** in `MandatoryBundles.h`. So the app's offline bootstrap depends on a third
party's repositories, no fix to them can be upstreamed, and the one-file `ruby18` shim that would
repair all 27 broken shebangs at once (a sibling of the existing `ruby` shim in
`bundle-support.tmbundle/Support/shared/bin/`) cannot be shipped either.

The Source pin's warning comment originally said to push the fix upstream. That was wrong and is
corrected — it now records the access constraint and says to re-apply by hand after any pin bump.

**The five shebang forms**, for whoever does the eventual fix: `ruby18` (12), `ruby18 -wKU` (9),
`ruby18 -w` (4), `ruby18 -w -d` (1), `ruby18  -wKU` (1, double space).

**Why this does not block Phase 5.** The breakage is inherited from upstream, lives in opt-in
bundles, and is identical for upstream TextMate users. The app's own embedded bundles are clean.

## 2026-08-13 — Bundle architecture mapped; do NOT extract the mandatory bundles

**Why this came up.** The question was whether to pull all bundles out of the main repository into
their own, letting users install what they want — and whether that would unblock working on the
main build and revisiting bundles later.

**The separation already exists.** The ~50 optional bundles are already independent upstream
repositories; `Managed/Bundles/` only caches extracted tarballs of them. The in-app chooser is
real: `Frameworks/Preferences/src/BundlesPreferences.mm`. Even the embedded bundles are generated
from separate repositories — `bin/fetch_embedded_bundles.sh` materializes them from the SHAs in
`MandatoryBundles.h`. The embedded copy is a first-launch offline bootstrap, not a source of truth.

**Do not extract the four mandatory bundles.** `MandatoryBundles.h:3-4` states it outright: users
cannot remove, disable or repoint Bundle Support, Text, Source or Themes. Bundle Support alone
provides `TM_SUPPORT_PATH`, which **34 of 54 installed bundles and 208 files** depend on. Without
them a fresh install has no grammars, no themes and no shared Ruby library.
`BundleRegistry.mm`'s `ensureMandatoryBundlesOnDisk()` logs and continues rather than crashing —
but that "graceful" path is an editor that cannot highlight anything.

**Avian: keep it, and pin it.** Initially flagged as the extraction candidate because it is the
fifth embedded bundle while only four are pinned, with no `.sha` marker and zero mentions in
`MandatoryBundles.h`. That was premature — it is a working feature bundle, not a demo.
`Import GZip`/`BZip2`/`PNG Image` are `callback.document.binary-import` filters with
`contentMatch` magic-byte patterns and `hideFromUser = 1`, so opening a compressed file
transparently decompresses it for viewing; `Show Images` and `Compress Selected Items` are
`callback.file-browser.action-menu` entries; `Encrypt on Save` is a save hook on
`attr.rev-path.crypt`. Dropping it regresses opening `.gz`/`.bz2`/`.png` to binary garbage. The
real anomaly is that it is hand-maintained while its four siblings are regenerated — the fix is to
pin it, not delete it. Deferred to the later bundle phase.

**Phase 5 is unblocked.** Bundles were scheduled before Phase 5 on the grounds that a signed,
notarized build would hand broken bundles to real users. The app's own bundles are now clean (zero
`ruby18` in installed v3.0.0-revived.14). The remaining 24 files are in *optional* bundles fetched
from upstream — equally broken for upstream TextMate users, i.e. inherited breakage in opt-in
content, not something this fork's release introduces. Bundle work can follow the main build.

**Source pin now carries a warning.** `MandatoryBundles.h` documents that the embedded
Source.tmbundle holds an un-upstreamed shebang fix and that bumping the pin silently discards it,
with the verification command to catch that.

**If interrupted here.** Nothing in flight beyond PR #8, still open.

## 2026-08-13 — ruby18 shebangs fixed in the shipped bundles (v3.0.0-revived.14)

**What.** Rewrote the five `#!/usr/bin/env ruby18` shebangs in
`Applications/TextMate/support/Bundles/` — four Avian commands and one Source macro. Built,
verified, released as v3.0.0-revived.14.

**The scope discovery that mattered.** The triage measured `~/Library/Application Support/TextMate/
Managed/Bundles/`, which is downloaded tarballs with no git. But
`Applications/TextMate/support/Bundles/` is **245 files tracked in this repository** — the five
bundles embedded in the app (Avian, Bundle Support, Source, Text, Themes). Those are fixable here
and now. `Avian.tmbundle` never appeared in the triage at all, because it ships inside the app and
is not installed into `Managed/`; it carried four of the five bad shebangs.

**Why `-EUTF-8` and not just dropping the flag.** Four of the five read
`#!/usr/bin/env ruby18 -wKU`. Ruby 2.6 accepts `-K` but warns it "is for 1.8 compatibility and may
cause odd behavior", so keeping it was not an option for a fork that bans 1.8. Dropping it was not
an option either — measured with `LANG` unset, which is the realistic case for a bundle command,
bare `-w` yields `Encoding.default_external = US-ASCII`, and any non-ASCII text the command
touches would break. `-w -EUTF-8` reproduces `-wKU`'s UTF-8 external *and* script encoding exactly,
with no warning. All three variants were measured against real files, not reasoned about.

**Verification.** Build SUCCEEDED; zero `ruby18` remains anywhere in the built app's
`SharedSupport/Bundles/`. All five changed files pass `plutil -lint`. Each script body was
extracted from its plist and passed `ruby -c` under 2.6.10 — parsing matters, since a working
shebang on 1.8-only syntax would just move the failure later. All five: Syntax OK.

**Still outstanding.** 24 files across 13 bundles in `Managed/Bundles/` have the same shebang and
cannot be durably fixed there — no git, and `BundlesManager`'s 3h poll re-fetches over any edit.
That needs forks of 12 upstream bundle repositories, which creates public repositories under the
maintainer's account, so it was not done unprompted. `Source.tmbundle` is the one overlap, already
fixed here.

**Deployed.** `bin/deploy-local` installed v3.0.0-revived.14 over .13; the installed app contains
no `ruby18` anywhere in `SharedSupport/Bundles/`.

**If interrupted here.** Committed on branch `fix/bundle-ruby18-shebangs`, built and deployed.
Remaining: merge the PR, then decide whether to fork the 12 upstream bundle repositories to fix
the other 24 shebangs.

## 2026-08-13 — Bundle Ruby-1.8 triage done; earlier claim in this log was wrong

**What.** Ran the triage that the previous entry deferred. Every verdict was checked by executing
the construct against the real system Ruby (2.6.10p210) rather than reasoning about it, which is
what caught the error below.

**Correction to the previous entry.** It named `$KCODE` and `require 'jcode'` as the real
breakage. **Both are absent from the installed bundles entirely** — as are `ftools`, `generator`
and `soap`. The original scan's 27 hits were 26 files carrying a `ruby18` shebang plus one
`RUBY_VERSION` branch; the alternation just made it look like the other markers had matched. The
same wrong claim went into `CLAUDE.md` and the Phase 4 PR body. `CLAUDE.md` is now corrected and
says so explicitly; the PR body is historical and was left alone.

**What is actually broken: a shebang, not a language feature.** 24 files across 13 bundles start
`#!/usr/bin/env ruby18`. No `ruby18` exists on `PATH`, and — the decisive check —
`bundle-support.tmbundle/Support/shared/bin/` ships a `ruby` shim but **no `ruby18` shim**, so the
`${TM_RUBY:-/usr/bin/ruby}` indirection does not rescue them. They name a different interpreter and
die at `env: ruby18: No such file or directory` before any Ruby parses.

Java 4 · Python 4 · YAML 3 · Active4D 2 · Lua 2 · Perl 2 · Gist 1 · Markdown 1 · Ruby 1 ·
Source 1 · Groovy 1 · HTML 1 · Cron 1.

The Python four are `Templates/*/info.plist` whose `<key>command</key>` *is* the `ruby18` script —
so "new file from template" fails, which is a first-run-visible path. Two hits are deliberately
**not** counted as breakage: `Ruby.tmbundle/Tests/rubylexer/regtest.rb` is a test fixture, and
`Bundle Development.tmbundle/Snippets/Ruby 1_8 Shebang.tmSnippet` stores the shebang under
`<key>content</key>` — it inserts one rather than running one. Worth revisiting, since a fork that
bans 1.8 shipping a shortcut for writing 1.8 shebangs is its own small absurdity.

**Library breakage, overlapping the above — do not sum the sets.** Confirmed fatal by execution:
`require 'iconv'` (3 files) and `require 'parsedate'` (1) both `cannot load such file`;
`Config::CONFIG` (1) and `TimeoutError` (3) both `NameError`; `Object#type` `NoMethodError` (~5).
Confirmed *harmless*, warning only: `Fixnum`/`Bignum` (11), `Hash#index` (18) — both still run.

**Honest limit on two numbers.** The `Object#type` (~5) and `String#each` (~19) counts come from
loose regexes that also match `Array#each`, `IO#each` and `String#index`, all of which are fine.
They are upper bounds needing per-file confirmation, not findings. Recorded that way in
`CLAUDE.md` rather than quoted as fact.

**If interrupted here.** Triage is committed on branch `docs/bundle-ruby-triage`; no bundle file
has been modified. Next piece is mechanical: fix the 24 shebangs, which is most of the problem.

## 2026-08-13 — KNOWN GAP logged: bundles are outside the Ruby 2.6 constraint

**Why this came up.** After the Phase 4 PR opened, the question was whether the plan needs to
cover updating the bundles too. It does. Logged as a known gap rather than planned in detail —
recorded here and in `CLAUDE.md`'s "Bundle delivery" section, **scheduled before Phase 5**.

**Why before Phase 5.** Phase 5 is Developer ID signing, notarization and public releases. That is
the point at which builds reach people who are not us. A signed, notarized app that pulls stock
Ruby 1.8 bundles ships the bug to real users; fixing it while distribution is still local is far
cheaper.

**What the audit found.**

- Only **three** bundles are forked: `MandatoryBundles.h` pins
  `textmatelives/{bundle-support,text,source}.tmbundle`. A fourth mandatory bundle,
  `themes.tmbundle` (`MandatoryBundles.h:53`), still points at **upstream `textmate/`**.
- Everything else — roughly 50 bundles — is fetched stock via
  `https://codeload.github.com/%@/%@/tar.gz/%@` (`BundleFetcher.mm:65`) from whatever
  `AvailableBundles.plist` names.
- **27 installed files** match Ruby 1.8 markers (`$KCODE`, `require 'jcode'`, 1.8 shebangs) across
  Ruby, YAML, Java, Perl, Lua, Gist, Markdown, HTML. Un-triaged on purpose: `$KCODE` and
  `require 'jcode'` genuinely raise under Ruby 2.6, but
  `Bundle Development.tmbundle/Snippets/Ruby 1_8 Shebang.tmSnippet` is a template *for inserting* a
  1.8 shebang — intentional content. The 27 is a search hit count, not a defect count.

**Correction to a stale doc claim.** `CLAUDE.md` said local dev wires bundles in via symlinks from
`~/src/github.com/textmatelives/bundles/`. Those repositories **do not exist on this machine**, so
`bin/reset_bundles.sh` is inoperative here — the 54 entries in `Managed/Bundles/` are real
directories downloaded via codeload, not symlinks. Corrected in `CLAUDE.md`.

**Shape of the eventual work** (triage first — it is the only piece whose cost is known, and it
sizes the other two): triage the 27 hits; fork and port whichever bundles genuinely break, and
decide `themes.tmbundle`'s fate; then repoint `AvailableBundles.plist` at forked repositories,
document an upstream re-merge path, and fix or delete `reset_bundles.sh`'s dead paths.

**If interrupted here.** Nothing is in flight. The gap is documented in `CLAUDE.md` and here; no
plan document has been written and no bundle has been touched.

## 2026-08-13 — Phase 4 Task 4 VERIFIED; `${YEAR}` copyright bug found and fixed

**What.** Built `c0c327c0` (Task 4) and `8bc1a8f9` (Task 3) and ran the full test suite against
them. Both verify clean. Found and fixed a separate, long-standing bug in the resource pipeline
while checking Task 4's own output.

**Verification result.** Build SUCCEEDED. App identity `com.shelbydenike.TextMate`,
`CFBundleName` `TextMate`, version `3.0.0-revived.13` (extracted from `CHANGELOG.md` by
`assemble_resources.sh`'s `app_version()`, so bumping the changelog heading *is* the version
bump — there is no separate `MARKETING_VERSION` to edit).

**25 of 25 baseline targets match `docs/benchmarks/2026-08-12-ninja-parity.md` exactly**, with
the four known-bad reproducing identically: `scm` 2/84 (no `hg`/`svn` on this machine), `buffer`
3/26 (misspellings), `file` 1/11 (iconv TRANSLIT), `cf` SIGBUS exit 138. `authorization` — the
only target that covers Task 3's actual code change — passes. `Onigmo_test` and `TextMate_test`
also pass. The prior handoff's "25 test targets" and the parity doc's 26-row table are
reconciled: `network_test` was deleted in `42e674ce` ("build!: delete the dead network
framework"), which the parity doc's own closing line already records.

**The `${YEAR}` bug.** The shipped `NSHumanReadableCopyright` read a literal
`© MacroMates Ltd., 2004-${YEAR}`. Cause: `assemble_resources.sh` dispatched each resource to a
transform by file extension, and `.strings` went straight to `utf16.sh` (transcode only) while
only `Info.plist` files went through `expand_plist.sh` (which is what passes
`-dYEAR="$(date +%Y)"`). Nothing ever substituted the variable. Fixed by adding an
`expand_utf16()` helper that expands and then transcodes, used at both `.strings` call sites.
This also fixed the same latent bug in both Dialog plug-ins, which now read `2005-2026` and
`2008-2026`. Pre-existing, not caused by Task 4 — the installed v.12 build has it too — but it
is a defect in exactly what Task 4 was auditing, so it was fixed here rather than deferred.

The fork's own notice renders `2026-2026` this year. Maintainer chose to keep the
`2026-${YEAR}` range: it self-corrects in January and needs no future code change.

**Also fixed.** `CLAUDE.md` claimed this repository is `textmatelives/textmate`. It is not —
`origin` is `git@github.com:sdenike/textmate.git`, and `textmatelives` is a separate remote this
fork merges *from*. That stale line is what sent Task 4's first pass at `Legal.md` to the wrong
URLs. Corrected, with a note that shipped docs must link to `sdenike/textmate`.

**Deployed and exit criteria met.** `bin/deploy-local` installed v3.0.0-revived.13 over .12.
All eight criteria in `docs/superpowers/plans/2026-08-13-phase-4-identity.md:106-113` check out
against the *installed* build, not the build tree:

- Identifiers: app `com.shelbydenike.TextMate`; `com.shelbydenike.plugin.Dialog` and `.Dialog2`;
  `com.shelbydenike.TextMateQL`; helper `com.shelbydenike.auth_server`, `.plist`, `.sock`.
- Settings carried over: 64 keys in the `com.shelbydenike.TextMate` domain.
- Bookmarks/folds: xattr names in `OakDocument.mm` still `com.macromates.*`, unchanged.
- Bundles load: `~/Library/Caches/com.shelbydenike.TextMate/BundlesIndex.binary` and
  `~/Library/Application Support/TextMate/Bundles.plist` were both rewritten at launch, 54
  bundles on disk, nothing bundle-related in the log. (`lsof` shows no open `.tmbundle` handles,
  which is expected — they are parsed into memory and closed, so that is not counter-evidence.)
- 38 `com.macromates.textmate.*` UTIs intact; `txmt` URL scheme registered.
- `mate` and `txmt://open?url=…` both opened a file in the running app, confirmed by `lsof`
  showing the process holding it — exit 0 alone would not have proved the document appeared.
- No crash reports; the process survived both open paths.

**Pushed, PR open.** Branch `phase-4/identity` pushed to `origin` (14 commits ahead of master).
PR: https://github.com/sdenike/textmate/pull/6

Note for future sessions: `gh pr create` fails on this machine with
`GraphQL: Resource not accessible by personal access token (createPullRequest)` — the `gh` token
lacks PR write scope. The GitHub MCP server authenticates separately and works; use it instead of
re-authenticating `gh`.

**If interrupted here.** The PR is open and unmerged. Remaining: merge it, then Phase 5
(Developer ID signing, notarization, in-app updates from GitHub Releases).

## 2026-08-13 — SESSION HANDOFF: Phase 4 nearly complete, Task 4 unverified

**Read this first on resume.** Everything below is committed; nothing is in the working tree.

### Exact state

- Branch `phase-4/identity`, **12 commits ahead of master**, working tree clean, **not pushed, no PR**.
- Installed: `/Applications/TextMate.app` — `com.shelbydenike.TextMate`, name `TextMate`,
  **v3.0.0-revived.12**. One app on the machine; no duplicates.
- Submodules: **4** (`Applications/TextMate/icons`, `bin/CxxTest`, `vendor/Onigmo/vendor`,
  `vendor/kvdb/vendor`). Dialog and Dialog2 were vendored, dropping 2.
- Phases 0, 1, 2, 3 are merged to master. Phase 4 is this branch.

### Phase 4 task status

| Task | State |
|---|---|
| 1 — preferences migration | **done**, verified against real data (37/37 keys), released as v3.0.0-revived.10 |
| 2 — bundle identifiers | **done**, migration fired for real, `mate` verified working, released as .11 |
| 2b — vendor Dialog plug-ins | **done**, provenance recorded, fresh-clone build verified, released as .12 |
| 3 — privileged helper | **done** (`8bc1a8f9`) — helper is LIVE (wired into the document open/save path for permission-restricted files), so kept not deleted; all five identifiers moved as one unit since they cross-reference at runtime |
| 4 — attribution and credits | **COMMITTED BUT UNVERIFIED** (`c0c327c0`) |

### The one thing that needs doing on resume

`c0c327c0` landed mid-task when the session was interrupted. It has **not been built** and the
**25 test targets have not been re-run against it**. Do that first.

What it contains: README's unaffiliated-fork + GPLv3 notice; `Legal.md` with boost and sparsehash
removed (both deleted in Phase 3) and the vendored Dialog plug-ins documented;
`NSHumanReadableCopyright` keeping MacroMates' notice and adding ours alongside — not instead of.
I also corrected its new `Legal.md` links, which pointed at `textmatelives/textmate` rather than
this repository.

Task 3 also has **no release of its own** — the identifier rename it performed has not been built,
deployed, or changelogged.

### Then, to close Phase 4

1. Build, run the 25 targets against `docs/benchmarks/2026-08-12-ninja-parity.md`.
2. Release v3.0.0-revived.13 covering Tasks 3 and 4; deploy; verify.
3. Check Phase 4 exit criteria in the plan — notably that bundles still load, `txmt://` still
   opens, and bookmarks/folds on existing files still work.
4. Push, open a PR, merge.

### Standing constraints that must not be forgotten

- **Never rename these** — they are on-disk format written into the user's own files, and share
  files with things that DO change: extended attributes in `OakDocument.mm`
  (`com.macromates.bookmarks`, `.folded`, `.crc32`, `.selectionRange`, `.visibleIndex`,
  `.backup.*`), the 38 `com.macromates.textmate.*` UTIs in `Applications/TextMate/Info.plist`,
  and the `txmt://` URL scheme.
- `CFBundleName` stays `TextMate` — the user asked the menu bar not read "TextMate Revived". The
  version string identifies the build.
- After each task: build, bump version, update changelog, deploy, verify.
- `bin/deploy-local` moves rather than copies, and refuses on identifier mismatch. That guard is
  correct behaviour, not a bug.
- Do NOT launch the app via `osascript` polling — it hangs on an Automation permission prompt.
- Build output goes to `~/build/textmate-revived/xcode`; never `/tmp`.
- A stale `com.macromates.auth_server` LaunchDaemon may exist from the pre-rename build. It was
  deliberately NOT removed — the official TextMate installs the same one, so on a machine with
  both it may not be ours to delete.

### Remaining phases

5 (Developer ID signing, notarization, in-app updates from GitHub Releases) · 5a (central
`sdenike/homebrew-tap`, migrate `hidden-revived` onto it) · 6 (Liquid Glass + PR #1469's UI work)
· 7 (performance) · 8 (shared modules) · 9 (optional LSP).

Of the three upstream forks, only textmatelives is merged. PR #1469's UI work lands in Phase 6;
tectiv3's remaining work is Phase 9.


## 2026-08-13 — Phase 4 Task 3: privileged helper renamed, not deleted

**What:** Investigated `Applications/PrivilegedTool` and `Frameworks/authorization` before
touching either (plan's file reference, `Applications/PrivilegedTool/src/constants.h`, was
off by one directory -- the actual `kAuth*` macros live in
`Frameworks/authorization/src/constants.h`; content matches the plan's description exactly,
just relocated). Traced real callers: `Frameworks/file/src/open.cc` and `save.cc`
(`kFileTestWritableByRoot` / `obtain_authorization`), `Frameworks/document/src/OakDocument.mm`
(the actual document save/open pipeline), and `Applications/mate/src/mate.mm` (the `mate` CLI's
`authorization` field) all wire into it live. This is the "open/save a file you don't own"
flow -- e.g. editing `/etc/hosts` -- reachable from both the GUI (an NSAlert offers to
authenticate) and the command line, not dead code like `CrashReporter` was in Phase 3.
`connect_to_auth_server` (`Frameworks/authorization/src/server.cc`) self-installs the tool via
`AuthorizationExecuteWithPrivileges` the first time it's needed, so there's no separate "does
the app install it" step to find -- first use *is* the install.

**Decision: keep it, rename all five identifiers.** Changed
`Frameworks/authorization/src/constants.h`'s `kAuthJobName`, `kAuthToolPath`, `kAuthSocketPath`,
`kAuthPlistPath`, `kAuthRightName` from `com.macromates.*` to `com.shelbydenike.*`. Confirmed by
grep this is the only file in either directory mentioning "macromates" -- the launchd plist and
authorization-right registration are both generated at runtime from these macros
(`Applications/PrivilegedTool/src/install.cc`), nothing else to update.

**Stale daemon: found one on this machine, left it alone, with evidence.**
`/Library/LaunchDaemons/com.macromates.auth_server.plist` and
`/Library/PrivilegedHelperTools/com.macromates.auth_server` exist here (`launchctl print
system/com.macromates.auth_server` confirms it's loaded, on-demand, not running). File
timestamps -- Oct 2021 and May 2024 -- predate this fork's existence entirely (versioning
starts at `3.0.0-revived` in 2026), so this is almost certainly an official MacroMates
TextMate install's own helper, not a prior build of this fork. Per the plan's explicit caution
("the official TextMate installs the same one... may not be ours to delete"), left it
untouched -- no `sudo`, no `launchctl unload`, no file removal. Recorded in CHANGELOG.md so a
user knows why it's still there and that this build no longer uses it.

**Authorization right:** renamed along with the rest (`com.shelbydenike.textmate.openfile`).
Deliberate, not incidental -- leaving it as `com.macromates.textmate.openfile` while renaming
the other four would mean this fork's binary silently reuses a right the user may have already
approved for the official app, without a fresh admin prompt tied to our own tool. Noted in
CHANGELOG.md that re-approval is expected on first use.

**Verification:** `./bin/build TextMate` -- `BUILD SUCCEEDED`. All 25 baseline test targets
individually (`./bin/build <name>/test`): 21 pass, `scm`/`buffer`/`file`/`cf` fail/crash for the
identical documented reasons in `docs/benchmarks/2026-08-12-ninja-parity.md`; `command` hit the
doc's own documented batching artifact when run 23rd of 25 in one loop, re-ran alone and it
passed in ~1.8s clean -- 25/25 match, no regression. Confirmed in the built app itself, not just
source: `strings TextMate.app/Contents/Resources/PrivilegedTool` shows all five
`com.shelbydenike.*` strings and zero `com.macromates` occurrences. Did not deploy to
`/Applications`, launch the app, or exercise the actual save-as-root flow -- doing so would
attempt the tool's self-install path (`AuthorizationExecuteWithPrivileges`, an admin prompt),
which the task forbids running.

**Why:** The helper is a real, live feature (permission-restricted file open/save), unlike
`CrashReporter`'s Phase 3 dead code -- evidence-based, not assumed. Identity must stay
consistent across all five values together since they cross-reference each other (job name in
the plist, socket path the daemon binds and the client connects to, right name both sides
check) -- renaming four and not the fifth would silently misbehave rather than fail loudly.

### If interrupted here

Task 3 committed. Task 4 (attribution/credits) next: README's fork disclaimer, Legal.md's
boost/sparsehash removal + Dialog/Dialog2 credit, `Contributions.md`'s stale
`com.macromates.TextMate` credits-cache path (a real bug found mid-task -- Task 2 renamed
`bin/gen_credits.rb`'s own dead `__END__` template but missed the live consumer,
`Applications/TextMate/about/Contributions.md`, which actually renders in the About window),
and the `NSHumanReadableCopyright` dual-copyright line, all already edited on disk pending
their own build/test verification and commit.

## 2026-08-13 — Phase 4 Task 2b: build, 25-target parity, and fresh-clone verification, all green

**What:** `./bin/build TextMate` -- `BUILD SUCCEEDED`. Ran all 25 baseline test targets
individually (`./bin/build <name>/test`, matching the doc's own per-target methodology) against
`docs/benchmarks/2026-08-12-ninja-parity.md`: **25/25 match exactly**. 21 pass; `scm` fails the
same documented `2 of 84` (hg/svn absent locally, identical message); `buffer` fails the same
documented `3 of 26` (identical three `t_buffer.mm` misspellings assertions, same lines); `file`
fails the same documented `1 of 11` (identical `t_save.cc:113` iconv TRANSLIT assertion); `cf`
crashes the same documented SIGBUS/exit 138, no summary printed. `command` reproduced the doc's
own noted batching artifact when run as target 23 of 25 in one long loop (looked hung, killed by
a `timeout 180` guard); re-ran it alone immediately after and it built and passed in about a
second with clean exit 0, exactly as the doc's own methodology predicts and as Task 2's build
already found for the same target. `editor` passed cleanly within the batch, no artifact this
run.

Verified `TMPlugInController.mm`'s plug-in loading is identifier-agnostic (see previous entry),
so no code change was needed there -- confirmed again post-build by checking the two identifiers
the running app's built bundle actually carries (below), which is what `loadPlugInAtPath:` reads
at runtime.

Both plug-ins confirmed in the built app: `TextMate.app/Contents/PlugIns/Dialog.tmplugin` and
`Dialog2.tmplugin` present, `CFBundleIdentifier` reads `com.shelbydenike.plugin.Dialog` and
`com.shelbydenike.plugin.Dialog2` respectively (`PlistBuddy`, not a grep of source).

**Fresh-clone proof, the check that actually matters here:** `git clone --recursive` of this
local repository (branch `phase-4/identity`, both new commits included) into a `mktemp -d` temp
directory. Confirmed before building: `git submodule status` inside the clone shows exactly the
4 real submodules (icons, CxxTest, Onigmo, kvdb) -- neither dialog path listed, nothing to fetch
from `github.com/textmate/dialog*` -- and both `PlugIns/dialog*/PROVENANCE.md` plus the renamed
`Info.plist` identifiers are present as ordinary files in the clone. `./bin/build TextMate` in
that clone: `BUILD SUCCEEDED`, both `.tmplugin` bundles present with the correct
`com.shelbydenike.plugin.*` identifiers -- proof a party who only has this git history, not this
machine's working tree, gets a working build. Temp clone then deleted (`rm -rf`).

**One deliberate wrinkle, handled:** `Xcode/Base.xcconfig` pins `SYMROOT`/`OBJROOT` to the fixed
absolute path `$(HOME)/build/textmate-revived/xcode` (Phase 2 Task 6, to keep build output out of
Spotlight) -- not relative to `$(SRCROOT)`, so the temp clone's build shared and briefly
overwrote the same output directory the main tree's own verified build lived in, rather than
writing somewhere self-contained under the temp directory. Source compilation itself was still
correctly isolated (each tree's own `$(SRCROOT)`-relative files), so this doesn't weaken the
fresh-clone proof, but to leave the shared build directory in a known-good state sourced from the
real working tree (not a now-deleted temp path) rather than /tmp, re-ran `./bin/build TextMate`
against the main tree once more after deleting the clone and re-verified both identifiers again
against that final rebuild -- shown above.

**Why:** This is the verification bar for Task 2b: proof, not assumption, that a party who never
had this machine's working tree -- a fresh clone or CI -- gets a repository that no longer
depends on the two unforked upstream submodules being reachable, builds clean, and ships both
plug-ins under the new identity.

### If interrupted here

Task 2b is complete: both plug-ins vendored (commit `0d1a7e6e`), both identifiers renamed
(commit `fce08a2c`), build verified, 25/25 test parity verified, fresh-clone build verified, temp
clone deleted, main tree's build directory restored and re-verified. `git status --porcelain`
clean except this STREAM.md entry, about to be committed. Nothing else queued for Task 2b. Next:
per the Phase 4 plan, Task 3 (the privileged helper) or Task 4 (attribution/credits).

## 2026-08-13 — Phase 4 Task 2b: Dialog/Dialog2 plug-in identifiers renamed

**What:** Changed `CFBundleIdentifier` in `PlugIns/dialog/Info.plist:16` and
`PlugIns/dialog-1.x/Info.plist:16` from `com.macromates.plugin.${TARGET_NAME}` to
`com.shelbydenike.plugin.${TARGET_NAME}` -- a 1-line change in each, now possible because the
previous commit vendored both out of their submodules. Confirmed no other file in the tree
references `com.macromates.plugin` (repo-wide grep, clean). Read
`Applications/TextMate/src/TMPlugInController.mm` in full: plug-in discovery
(`loadAllPlugIns:`) scans `NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
...)` plus the app's own `builtInPlugInsPath` for `*.tmplugin` bundles by file extension, not by
identifier; `loadPlugInAtPath:` then reads `CFBundleIdentifier` back out of each bundle's own
`Info.plist` at runtime (`[bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"]`) and uses it
only as (a) a dictionary key in `loadedPlugIns` to detect double-loads and (b) a lookup against
the user's `disabledPlugIns` defaults array, which defaults to `@[ @"io.emmet.EmmetTextmate" ]`
only -- nothing hardcodes `com.macromates.plugin.*` anywhere. Loading is identifier-agnostic by
construction; this rename cannot break it.

**Why:** Completes the rename Task 2 had to leave blocked -- both plug-ins now carry the same
`com.shelbydenike.*` identity as the rest of the app.

### If interrupted here

Committed. Next: `./bin/build`, the 25-target parity check against
`docs/benchmarks/2026-08-12-ninja-parity.md`, confirm both `.tmplugin` bundles land in the built
`TextMate.app` with the new identifier, then a fresh `git clone --recursive` into a temp
directory to prove a clean checkout builds without the two dropped submodules (delete the temp
clone afterward).

## 2026-08-13 — Phase 4 Task 2b: dialog submodules vendored, dropping the submodule registrations

**What:** Recorded provenance (upstream URL, exact commit SHA, author, date, subject) for both
`PlugIns/dialog` (`https://github.com/textmate/dialog.git` @ `fa2f59e3a`) and
`PlugIns/dialog-1.x` (`https://github.com/textmate/dialog-1.x.git` @ `43df3148e`), wrote it into
a new `PROVENANCE.md` in each directory, then de-submoduled both: `git rm --cached` the gitlink
(keeps working-tree files on disk), deleted each directory's `.git` gitlink file, removed both
stanzas from `.gitmodules`, removed both `submodule.PlugIns/dialog*` sections from `.git/config`,
deleted `.git/modules/PlugIns/dialog` and `.git/modules/PlugIns/dialog-1.x`, then `git add`ed the
now-ordinary tracked files. Verified: `git submodule status` shows 4 remaining (icons, CxxTest,
Onigmo, kvdb), neither dialog path listed; `git diff --cached --summary` shows exactly two
`delete mode 160000` (the old gitlinks) and 55 `create mode 100644` (identical file content,
confirmed no executable bits in the original submodules to lose). File contents byte-for-byte
unchanged from the recorded upstream commit -- no edits made besides adding `PROVENANCE.md`.
Checked `.gitignore` and `project.yml` for submodule-path assumptions: neither needs a change
(`.gitignore` never mentioned these paths; `project.yml`'s 31 `PlugIns/dialog*` references are
plain source-file paths that resolve identically whether the directory is a submodule checkout
or vendored files).

**Why:** Task 2 left `PlugIns/dialog*` on `com.macromates.plugin.*` because both were git
submodules pointing at upstream's own unforked repos -- editing `Info.plist` inside a submodule
checkout produces a commit only this machine has, and `.gitmodules` still resolves to upstream,
so a fresh clone or CI would silently fail to get the rename. The user chose vendoring over
forking upstream: small, dormant repos, and it also drops 2 of the 6 remaining submodules.

### If interrupted here

Vendoring is staged but not yet committed. Next: commit this as its own increment (`git status
--porcelain` first), then do the identifier rename (`com.macromates.plugin.${TARGET_NAME}` →
`com.shelbydenike.plugin.${TARGET_NAME}` in both `PlugIns/*/Info.plist:16`) as a second commit,
then verify `TMPlugInController.mm` doesn't hardcode the old identifier (initial read of
`loadPlugInAtPath:`/`loadAllPlugIns:` shows it discovers `.tmplugin` bundles by directory scan +
extension and reads `CFBundleIdentifier` dynamically from each bundle's own Info.plist -- used
only as a dictionary key and against the user's `disabledPlugIns` defaults array, which defaults
to `@[ @"io.emmet.EmmetTextmate" ]` -- so no hardcoded `com.macromates.plugin.*` match exists
anywhere in the tree; confirm this holds after rebuilding), then `./bin/build`, the 25-target
parity check, a fresh `git clone --recursive` build in a temp dir, and a check of the built
`TextMate.app`'s two `.tmplugin` bundles for identifier + presence.

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
