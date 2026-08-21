# Settings: SoftwareUpdate Pane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SoftwareUpdatePreferences`'s hand-built AppKit contents with a SwiftUI `Form`, hosted inside the unchanged AppKit Settings shell, establishing the pattern the remaining panes will follow.

**Architecture:** The `Preferences` static library gains Swift and a narrow pure-Objective-C bridging shim. The pane stays a `PreferencesPane` subclass — that contract is ObjC++ and cannot move — but its `loadView` installs an `NSHostingView` instead of an `NSGridView`. Derived display state moves into a testable model, and a `Preferences_test` target is created to exercise it.

**Tech Stack:** Objective-C++, SwiftUI (Swift 6.0), XcodeGen, the `bin/gen_test` CxxTest-style runner.

**Spec:** `docs/superpowers/specs/2026-08-20-settings-swiftui-panes-design.md`

## Global Constraints

- **arm64 only.** Deployment target **macOS 26.0**. Never write `@available(macOS 26, *)` or `NSVisualEffectView` fallbacks — every branch is dead code.
- **Swift declarations crossing to Objective-C++ must be `public`**, not merely `@objc`. An `internal @objc` class compiles, reaches the `.swiftmodule`, and is silently absent from the generated `-Swift.h`; the failure appears at the ObjC++ call site as `use of undeclared identifier`.
- **A bridging header is parsed as C/Objective-C, never Objective-C++, and compiled without `GCC_PREFIX_HEADER`.** No C++ in it, and nothing under `Xcode/include/` — those headers take their AppKit imports from the prelude.
- **`bin/gen_test` wraps each test file in `namespace <filename> { … }`**, and Objective-C forbids `@interface`/`@implementation` inside a namespace. A test file cannot declare an Objective-C class.
- **`OAK_ASSERT` is a single-argument macro** (`bin/gen_test:110`); the preprocessor splits on commas without tracking `[]` or `{}`, so an argument containing `@[ a, b ]` needs a second paren pair: `OAK_ASSERT((expr))`.
- **Never `OAK_ASSERT_EQ` on an Objective-C object pointer** — it resolves to a generic `to_s` that iterates the pointer and aborts the runner with SIGABRT. Use `OAK_ASSERT([a isEqualToString:@"…"])`.
- **`to_s(NSString*)` lives in `Frameworks/ns`** — only usable if the test target links it.
- Build with **`bin/build`**, never bare `xcodebuild`. `project.yml` changes require `xcodegen generate --spec project.yml`; the `.xcodeproj` is generated and committed.
- **No AI attribution or session trailers in commits.** `STREAM.md` gets a newest-first entry in the same commit as the change it describes.

---

### Task 1: Swift compiles in the `Preferences` static library

The app target's Swift support was proven by spike; **no framework target in this repository has ever contained Swift.** This task proves a `library.static` target can, and does nothing else, so a failure here is unambiguous.

**Files:**
- Create: `Frameworks/Preferences/src/Preferences-Bridging-Header.h`
- Create: `Frameworks/Preferences/src/SettingsSupport.swift`
- Modify: `project.yml` — the `Preferences` target

**Interfaces:**
- Consumes: nothing.
- Produces: `SettingsChannel` (Swift enum, `public`), and the compiled fact that the `Preferences` library builds with Swift.

- [ ] **Step 1: Create the bridging shim**

It re-declares the externs it needs. **Re-declaring an `extern` is not duplicating a literal** — the declaration carries no value, the definitions stay in `Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm:12-19`, and the linker resolves them. A misspelled name is a link error, not a silently wrong key.

```objc
// Frameworks/Preferences/src/Preferences-Bridging-Header.h
//
// The ONLY Objective-C surface Swift sees in this framework. Keep it small.
//
// ClangImporter compiles this as C/Objective-C without GCC_PREFIX_HEADER, so
// it imports Foundation itself and may contain no C++. It must NOT import
// anything under Xcode/include/ -- those headers rely on the prelude for
// their Foundation and AppKit types and fail here with "unknown type name".
//
// The keys below are DECLARED here and DEFINED in
// Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm:12-19. Re-declaring an
// extern shares the symbol rather than copying the value, so a name typo is a
// link error rather than a wrong key that compiles and passes its tests.

#import <Foundation/Foundation.h>

extern NSString* const kUserDefaultsDisableSoftwareUpdateKey;   // @"SoftwareUpdateDisablePolling"
extern NSString* const kUserDefaultsAskBeforeUpdatingKey;       // @"SoftwareUpdateAskBeforeUpdating"
extern NSString* const kUserDefaultsSoftwareUpdateChannelKey;   // @"SoftwareUpdateChannel"
extern NSString* const kUserDefaultsLastSoftwareUpdateCheckKey; // @"SoftwareUpdateLastPoll"

extern NSString* const kSoftwareUpdateChannelRelease;           // @"release"
extern NSString* const kSoftwareUpdateChannelPrerelease;        // @"beta"
```

- [ ] **Step 2: Create the first Swift file**

`SettingsChannel` models the two user-selectable channels. **`kSoftwareUpdateChannelCanary` (`@"nightly"`) is deliberately absent** — `SoftwareUpdate.mm:392` sets `includePrereleases` only for `kSoftwareUpdateChannelPrerelease`, so `nightly` behaves identically to `release`, and the feed (git tags) has no third tier to offer. It survives only because `SoftwareUpdate.mm:359` forces it for test builds.

```swift
// Frameworks/Preferences/src/SettingsSupport.swift
import Foundation

// The two channels a user can choose. "nightly" (kSoftwareUpdateChannelCanary)
// is intentionally not here: SoftwareUpdate.mm:392 sets includePrereleases only
// for the prerelease channel, so nightly resolves to exactly the same updates as
// release. It exists for test builds (SoftwareUpdate.mm:359), not as a tier.
public enum SettingsChannel: String, CaseIterable, Identifiable {
	case release
	case prerelease

	public var id: String { rawValue }

	// The stored defaults value. Not the case name: prerelease persists as "beta".
	public var storedValue: String {
		switch self {
			case .release:    return kSoftwareUpdateChannelRelease
			case .prerelease: return kSoftwareUpdateChannelPrerelease
		}
	}

	public var title: String {
		switch self {
			case .release:    return "Normal releases"
			case .prerelease: return "Prereleases"
		}
	}

	// Anything unrecognised -- including "nightly" -- reads as release, which is
	// what those channels actually deliver.
	public static func from(storedValue: String?) -> SettingsChannel {
		allCases.first { $0.storedValue == storedValue } ?? .release
	}
}
```

- [ ] **Step 3: Wire the target**

In `project.yml`'s `Preferences` target, add to `sources:`:

```yaml
      - path: "Frameworks/Preferences/src/SettingsSupport.swift"
```

and to `settings.base`, after the existing `GCC_PREFIX_HEADER` line:

```yaml
        SWIFT_OBJC_BRIDGING_HEADER: "Frameworks/Preferences/src/Preferences-Bridging-Header.h"
```

- [ ] **Step 4: Build**

Run: `xcodegen generate --spec project.yml && bin/build`
Expected: `** BUILD SUCCEEDED **`

Then prove Swift actually compiled rather than being silently ignored — a `.swift` file missing from `sources` still yields a green build:

Run: `ls ~/build/textmate-revived/xcode/Release/Preferences.swiftmodule/ 2>/dev/null || find ~/build/textmate-revived/xcode -name 'Preferences*.swiftmodule' -maxdepth 3`
Expected: a `.swiftmodule` for the Preferences module exists. **Report the exact path found** — a static library's module may land somewhere different from the app target's, and later tasks need to know.

- [ ] **Step 5: Commit**

```bash
git add project.yml TextMate.xcodeproj Frameworks/Preferences/src STREAM.md
git commit -m "feat(settings): Swift in the Preferences library

No framework target here has ever contained Swift -- only the app target,
proven by spike. This lands the smallest possible file in a library.static so
that fact is established on its own, before a pane depends on it.

The bridging shim re-declares the four defaults keys and two channel constants
it needs rather than retyping their values. Re-declaring an extern shares the
symbol; the definitions stay in SoftwareUpdate.mm. A name typo is a link error
instead of a key that compiles, links and silently reads nothing."
```

---

### Task 2: `Preferences_test`, and the pane's derived state made testable

There is **no test target for `Preferences`** — verified: none in `project.yml`, no `Frameworks/Preferences/tests/` directory, nothing anywhere exercising this framework. This creates one and moves the pane's display logic somewhere it can be checked.

**Files:**
- Create: `Frameworks/Preferences/src/SettingsSupportBridge.h`
- Create: `Frameworks/Preferences/src/SettingsSupportBridge.mm`
- Create: `Frameworks/Preferences/tests/t_settings_support.mm`
- Modify: `project.yml` — new `PreferencesSupport` and `Preferences_test` targets

**Interfaces:**
- Consumes: `SettingsChannel` (Task 1).
- Produces: `TMSettingsLastCheckDescription(BOOL, NSString*, NSString*)` → `NSString*`, and `Preferences_test` as the target later tests are added to.

- [ ] **Step 1: Write the failing test**

The precedence being pinned is from `SoftwareUpdatePreferences.mm:37`:
`isChecking ? @"Checking…" : (errorString ?: _relativeStringForLastCheck ?: @"Never")`

```objc
// Frameworks/Preferences/tests/t_settings_support.mm
#import "../src/SettingsSupportBridge.h"

// Wrapped in namespace t_settings_support by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.

void test_checking_wins_over_everything ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(YES, @"some error", @"5 minutes ago") isEqualToString:@"Checking…"]);
	OAK_ASSERT([TMSettingsLastCheckDescription(YES, nil, nil) isEqualToString:@"Checking…"]);
}

void test_error_wins_over_date ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, @"Network unreachable", @"5 minutes ago") isEqualToString:@"Network unreachable"]);
}

void test_date_used_when_no_error ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, nil, @"5 minutes ago") isEqualToString:@"5 minutes ago"]);
}

void test_never_when_nothing_known ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, nil, nil) isEqualToString:@"Never"]);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/build Preferences/test`
Expected: FAIL — the target does not exist yet, so `xcodebuild` reports an unknown target. That is the expected first failure; the next step creates it.

- [ ] **Step 3: Write the header and implementation**

```objc
// Frameworks/Preferences/src/SettingsSupportBridge.h
#import <Foundation/Foundation.h>

// The text shown for "Last check:". Extracted from SoftwareUpdatePreferences's
// -lastCheckDescription so the precedence can be tested: checking beats an
// error, an error beats a date, and "Never" is the floor.
extern NSString* TMSettingsLastCheckDescription (BOOL isChecking, NSString* errorString, NSString* relativeDate);
```

```objc
// Frameworks/Preferences/src/SettingsSupportBridge.mm
#import "SettingsSupportBridge.h"

NSString* TMSettingsLastCheckDescription (BOOL isChecking, NSString* errorString, NSString* relativeDate)
{
	if(isChecking)
		return @"Checking…";
	return errorString ?: relativeDate ?: @"Never";
}
```

- [ ] **Step 4: Create the test target**

In `project.yml`, immediately after the `Preferences` target, add:

```yaml
  Preferences_test:
    type: tool
    platform: macOS
    sources:
      - path: "$(DERIVED_FILE_DIR)/_TPreferences.mm"
        optional: true
        buildPhase: sources
    preBuildScripts:
      - script: "\"$SRCROOT/Xcode/scripts/gen_test.sh\" Preferences"
        name: "Generate CxxTest runner (Preferences)"
        basedOnDependencyAnalysis: false
        outputFiles:
          - "$(DERIVED_FILE_DIR)/_TPreferences.mm"
    settings:
      base:
        GCC_PREFIX_HEADER: "$(SRCROOT)/Shared/PCH/prelude.mm"
    dependencies:
      - target: PreferencesSupport
      - sdk: Foundation.framework
```

and add the small library the test links — the full `Preferences` library pulls AppKit, `settings_t` and a dozen frameworks that a test tool has no reason to carry:

```yaml
  PreferencesSupport:
    type: library.static
    platform: macOS
    sources:
      - path: "Frameworks/Preferences/src/SettingsSupportBridge.mm"
    settings:
      base:
        GCC_PREFIX_HEADER: "$(SRCROOT)/Shared/PCH/prelude.mm"
```

Add `PreferencesSupport` to the `Preferences` target's `dependencies:` so the app gets one definition:

```yaml
    dependencies:
      - target: PreferencesSupport
        link: true
```

**Note:** the `Preferences` target currently has **no `dependencies:` key at all** — it resolves everything through `HEADER_SEARCH_PATHS`. Add the key.

- [ ] **Step 5: Run the tests**

Run: `xcodegen generate --spec project.yml && bin/build Preferences/test`
Expected: `** BUILD SUCCEEDED **`, then run the binary directly and report the count:

Run: `~/build/textmate-revived/xcode/Release/Preferences_test -v`
Expected: `4 tests passed`

- [ ] **Step 6: Commit**

```bash
git add project.yml TextMate.xcodeproj Frameworks/Preferences STREAM.md
git commit -m "test(settings): a test target for Preferences, and the first thing in it

Nothing under Frameworks/Preferences has ever been tested -- no target, no
tests directory, no test anywhere touching it. This adds the target and pins
the one piece of the SoftwareUpdate pane that is pure logic: the precedence
behind 'Last check', where checking beats an error, an error beats a date, and
Never is the floor.

The test links a small PreferencesSupport library rather than the Preferences
library itself, which would drag AppKit, settings_t and a dozen frameworks
into a test tool that needs none of them."
```

---

### Task 3: The pane in SwiftUI, hosted and correctly sized

**Files:**
- Modify: `Frameworks/Preferences/src/SoftwareUpdatePreferences.mm`
- Modify: `Frameworks/Preferences/src/SettingsSupport.swift`
- Modify: `project.yml` if a new `.swift` file is added

**Interfaces:**
- Consumes: `SettingsChannel`, `TMSettingsLastCheckDescription`, the bridging shim's key constants.
- Produces: `SettingsPaneFactory.softwareUpdateView(checkNow:)` — an `@objc public` Swift factory returning an `NSView` for `loadView` to install.

- [ ] **Step 1: Build the SwiftUI pane**

Behaviour to preserve exactly, read from the current `loadView` (`SoftwareUpdatePreferences.mm:113-155`):

- "Watch for:" checkbox binds `kUserDefaultsDisableSoftwareUpdateKey` **negated**.
- The channel popup and "Ask before downloading updates" are both **disabled when updates are disabled** — two separate `NSEnabledBinding`s with `NSNegateBooleanTransformerName`.
- "Check Now" is **disabled while checking**.
- "Last check:" shows `lastCheckDescription`.

```swift
// Append to Frameworks/Preferences/src/SettingsSupport.swift
import SwiftUI

@MainActor
final class SoftwareUpdateModel: ObservableObject {
	// Stored inverted in defaults: the key disables polling, the checkbox enables
	// it. The old code expressed this as NSNegateBooleanTransformerName inside a
	// binding, where it was invisible unless you read the options dictionary.
	@AppStorage(kUserDefaultsDisableSoftwareUpdateKey) private var pollingDisabled: Bool = false
	@AppStorage(kUserDefaultsAskBeforeUpdatingKey)     var askBeforeDownloading: Bool = false
	@AppStorage(kUserDefaultsSoftwareUpdateChannelKey) private var channelRaw: String = kSoftwareUpdateChannelRelease

	var watchForUpdates: Bool {
		get { !pollingDisabled }
		set { pollingDisabled = !newValue }
	}

	var channel: SettingsChannel {
		get { SettingsChannel.from(storedValue: channelRaw) }
		set { channelRaw = newValue.storedValue }
	}
}

struct SoftwareUpdatePaneView: View {
	@ObservedObject var model: SoftwareUpdateModel
	let lastCheckDescription: String
	let isChecking: Bool
	let checkNow: () -> Void

	var body: some View {
		Form {
			Section {
				Toggle("Watch for updates", isOn: Binding(get: { model.watchForUpdates },
				                                          set: { model.watchForUpdates = $0 }))
				Picker("Channel", selection: Binding(get: { model.channel },
				                                     set: { model.channel = $0 })) {
					ForEach(SettingsChannel.allCases) { channel in
						Text(channel.title).tag(channel)
					}
				}
				.disabled(!model.watchForUpdates)

				Toggle("Ask before downloading updates", isOn: $model.askBeforeDownloading)
					.disabled(!model.watchForUpdates)
			}

			Section {
				LabeledContent("Last check", value: lastCheckDescription)
				Button("Check Now", action: checkNow)
					.disabled(isChecking)
			}
		}
		.formStyle(.grouped)
	}
}
```

- [ ] **Step 2: Add the Objective-C-visible factory**

A SwiftUI `View` is a struct and invisible to Objective-C++. It needs an `@objc public` factory — the same shape `SetupAssistantHostingController` uses in the app target. **`public` is load-bearing**: an `internal @objc` class compiles, reaches the `.swiftmodule`, and is silently absent from the generated header.

```swift
// Append to Frameworks/Preferences/src/SettingsSupport.swift
@objc(SettingsPaneFactory)
public final class SettingsPaneFactory: NSObject {
	// `public`, not merely @objc: an internal @objc class is absent from the
	// generated Preferences-Swift.h and fails at the ObjC++ call site with
	// "use of undeclared identifier", pointing at the wrong file entirely.
	@MainActor
	@objc public static func softwareUpdateView(checkNow: @escaping () -> Void) -> NSView {
		let model = SoftwareUpdateModel()
		let view = NSHostingView(rootView: SoftwareUpdatePaneView(model: model,
		                                                          lastCheckDescription: "",
		                                                          isChecking: false,
		                                                          checkNow: checkNow))
		// PreferencesPane.mm:36 sizes a pane from its fittingSize, and
		// OakTransitionViewController pins to it. A 0x0 here is what made the
		// Terminal pane look like a dead click for months.
		view.frame = NSRect(origin: .zero, size: view.fittingSize)
		return view
	}
}
```

**`lastCheckDescription` and `isChecking` are passed as plain values here and do not yet update.** Wiring them to the live `SoftwareUpdate` singleton is Step 3 — get the view on screen first, since a wrong `fittingSize` is easier to diagnose without observers in play.

- [ ] **Step 3: Replace `loadView`, and delete what cannot run**

In `SoftwareUpdatePreferences.mm`, import the generated header and replace the whole of `loadView` (currently `:113-155`):

```objc
#import "Preferences-Swift.h"

- (void)loadView
{
	SoftwareUpdate* controller = self.softwareUpdateController;
	self.view = [SettingsPaneFactory softwareUpdateViewWithCheckNow:^{
		[controller checkForUpdate:nil];
	}];
}
```

Then delete what the deployment target makes unreachable:

- The pre-10.15 branch of `relativeStringForDate:` (`:53-92`) — roughly forty lines. The target is macOS 26, so `NSRelativeDateTimeFormatter` is always available and the `#if defined(MAC_OS_X_VERSION_10_15)` fallback can never execute.
- The `@available(macos 11.0, *)` icon guard at `:22-24`, for the same reason.

Keep `viewWillAppear`/`viewDidDisappear`'s observer and 60-second timer, and keep `lastCheckDescription` — but have it return `TMSettingsLastCheckDescription(self.softwareUpdateController.isChecking, self.softwareUpdateController.errorString, _relativeStringForLastCheck)` so the function under test is the one that actually runs.

**Report the measured `fittingSize`.** If it is `0×0` or absurd, stop and report rather than working around it — that is the failure this task exists to catch.

- [ ] **Step 4: Build and test**

Run: `bin/build && bin/build Preferences/test`
Expected: `** BUILD SUCCEEDED **` for both; `Preferences_test -v` still reports `4 tests passed`.

- [ ] **Step 5: Verify manually — this cannot be automated**

GUI behaviour cannot be exercised in the agent sandbox. Ask the maintainer to `bin/deploy-local` or run the built app and confirm:

1. Settings → Software Update renders, with content, correctly sized — not collapsed, not clipped.
2. Unchecking "Watch for updates" disables both the channel picker and "Ask before downloading updates".
3. **The defaults diff.** `defaults export com.shelbydenike.TextMate /tmp/before.plist`, toggle every control, export to `/tmp/after.plist`, `diff` them. `SoftwareUpdateDisablePolling` must be **`true` when the checkbox is unchecked** — that is the negation, and it is the single most likely thing to invert silently.
4. Selecting "Prereleases" writes `SoftwareUpdateChannel = beta` — not `prerelease`.
5. ⌘1–⌘6 still switch panes; tabbing through the pane is sane.
6. "Check Now" runs a check and greys out while checking.

- [ ] **Step 6: Commit**

```bash
git add Frameworks/Preferences/src project.yml TextMate.xcodeproj STREAM.md
git commit -m "feat(settings): the Software Update pane in SwiftUI

First pane ported. The AppKit shell is untouched -- window, toolbar, key
equivalents, transitions and persistence all still come from Preferences.mm;
only loadView changed, from an NSGridView to an NSHostingView.

Two behaviours that were invisible in the old code are now explicit. The watch
checkbox is stored inverted -- the key disables polling -- which previously
lived as NSNegateBooleanTransformerName inside a binding options dictionary.
And the channel persists as \"beta\", not \"prerelease\", which the enum now
states rather than leaving to a runtime-registered string-list transformer.

Also drops roughly forty lines of pre-10.15 relative-date formatting and an
@available(macos 11) icon guard. The deployment target is macOS 26; neither
branch could ever run."
```

---

### Task 4: Extract the shared style layer

Now that one real pane exists, the styling worth sharing can be extracted from it rather than guessed at in advance.

**Files:**
- Create: `Frameworks/Preferences/src/SettingsFormStyle.swift`
- Modify: `Frameworks/Preferences/src/SettingsSupport.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `SoftwareUpdatePaneView` (Task 3).
- Produces: `SettingsPane<Content>` — the wrapper every later pane uses instead of `Form` directly.

- [ ] **Step 1: Extract what the pane established**

```swift
// Frameworks/Preferences/src/SettingsFormStyle.swift
import SwiftUI

// Every Settings pane wraps its content in this rather than using Form directly,
// so "uniform and modern" is decided once. A pane declares WHAT it configures;
// none of them decides how it looks. Six panes each making their own layout
// choices is exactly how a window ends up looking inconsistent.
public struct SettingsPane<Content: View>: View {
	private let content: Content

	public init(@ViewBuilder content: () -> Content) {
		self.content = content()
	}

	public var body: some View {
		Form {
			content
		}
		.formStyle(.grouped)
		.scrollDisabled(true)
	}
}
```

`.scrollDisabled(true)` matters: the shell sizes the pane from `fittingSize`, so a pane that scrolls internally would report a small fitting size and clip. **If Task 3 measured a sane `fittingSize` without this, keep it anyway and say so** — panes later in the sequence are taller and will need it.

- [ ] **Step 2: Adopt it in the pane**

Replace `Form { … }.formStyle(.grouped)` in `SoftwareUpdatePaneView` with `SettingsPane { … }`.

- [ ] **Step 3: Build and confirm nothing moved**

Run: `bin/build && bin/build Preferences/test`
Expected: `** BUILD SUCCEEDED **`; `4 tests passed`. Report the pane's `fittingSize` again and confirm it is unchanged from Task 3.

- [ ] **Step 4: Commit**

```bash
git add Frameworks/Preferences/src project.yml TextMate.xcodeproj STREAM.md
git commit -m "refactor(settings): extract the shared pane style

Pulled out of the Software Update pane rather than designed ahead of it, so it
encodes what a real pane needed instead of what one might need.

scrollDisabled is load-bearing: the shell sizes each pane from fittingSize
(PreferencesPane.mm:36, then OakTransitionViewController), and a pane that
scrolls internally reports a small fitting size and clips."
```

---

## Notes for whoever executes this

**The risk that has already shipped here once.** `OakTransitionViewController` pins the pane to `fittingSize`, and `CLAUDE.md` records the Terminal pane appearing as a dead click for months because an empty view was pinned to `0×0` with the previous pane still visible underneath. Measure and report `fittingSize` at every step that touches layout. It fails silently and looks like a rendering glitch.

**`nightly` is deliberately not offered.** `SoftwareUpdate.mm:392` sets `includePrereleases` only for the prerelease channel, so `nightly` delivers exactly what `release` does; the feed is git tags and has no third tier. It survives because `SoftwareUpdate.mm:359` forces it for test builds. Do not "fix" its absence from the picker.

**Read the file before changing it.** This plan exists because a survey summary produced three wrong statements in the spec — a class that does not exist, a constant whose value was wrong, and keys located in the wrong framework. Every code block above was written against the real source.
