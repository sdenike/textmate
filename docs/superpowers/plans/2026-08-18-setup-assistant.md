# Setup Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `FirstLaunchBundleInstaller`'s single-purpose modal with a three-step Setup Assistant (welcome, appearance, bundles) that is also re-runnable from `Help → Setup Assistant…`.

**Architecture:** Objective-C++ owns the window, the modal session, and every side effect; SwiftUI owns presentation and local view state only. They meet at a deliberately narrow, pure-Objective-C bridging header. Testable logic lives in a `library.static` target linked by both the app and its test binary, following the `PreferencesMigration` precedent.

**Tech Stack:** Objective-C++, SwiftUI (Swift 6.0), XcodeGen, the home-grown CxxTest-style runner produced by `bin/gen_test`.

**Spec:** `docs/superpowers/specs/2026-08-18-setup-assistant-design.md`

## Global Constraints

These apply to every task. They are not suggestions and several of them fail silently when violated.

- **arm64 only.** Never add an x86_64 fallback.
- **Deployment target is macOS 26.0.** Never write `@available(macOS 26, *)` or an `NSVisualEffectView` fallback — every branch would be dead code.
- **Swift declarations crossing to Objective-C++ must be `public`, not merely `@objc`.** An `internal @objc` class compiles, lands in the `.swiftmodule`, and is *absent* from the generated `TextMate-Swift.h`. The failure appears at the Objective-C++ call site as `use of undeclared identifier`, which points at the wrong file.
- **The bridging header is parsed as C/Objective-C, never Objective-C++, and is compiled without `GCC_PREFIX_HEADER = prelude.mm`.** It may contain no C++ whatsoever, and may not import any header under `Xcode/include/` — those rely on the prelude for their AppKit imports. It imports `<Cocoa/Cocoa.h>` and self-contained headers beside it, and nothing else.
- **`bin/gen_test` wraps every test file in `namespace <filename> { … }`.** Objective-C forbids `@interface` and `@implementation` inside a namespace, so **a test file cannot declare an Objective-C class**. There is no escape hatch. Prefer free functions in the code under test — this is why `PreferencesMigration` is written as free functions.
- **Never use `OAK_ASSERT_EQ` on an Objective-C object pointer.** Use `OAK_ASSERT(a == b)`. `OAK_ASSERT_EQ` falls back to a generic `to_s` that range-fors over the pointer; when the assertion fails it throws `NSInvalidArgumentException`, the runner catches only `std::exception`, and the binary aborts with SIGABRT instead of naming the failing test.
- **Build with `bin/build`, never bare `xcodebuild`.** A leaked `GEM_HOME`/`GEM_PATH` from chruby/rbenv/rvm breaks the Ruby script phases with `Symbol not found: _rb_cArray (LoadError)`, which reads like a broken build and is not one. `bin/build` guards against it.
- **`project.yml` changes require `xcodegen generate --spec project.yml`.** The `.xcodeproj` is generated and committed.
- **Docs travel in the same commit as the change.** `STREAM.md` gets a newest-first entry with timestamp, what, why, and the "if interrupted here" next step.
- **No AI attribution or session trailers in commit messages.**

---

### Task 1: Swift compiles in the app target

Retires the largest unknown first: this is the first target in the repository to carry both `.swift` and `.mm` sources through a full build. Nothing else in the plan is worth starting until this is proven in a committed state rather than a throwaway spike.

**Files:**
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.h`
- Create: `Applications/TextMate/src/TextMate-Bridging-Header.h`
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift`
- Modify: `project.yml` (TextMate target `sources` and `settings.base`)

**Interfaces:**
- Consumes: nothing.
- Produces: `TMSetupAssistantStep` (Swift enum, `public`), and the compiled fact that `#import "TextMate-Swift.h"` resolves from Objective-C++ in this target.

- [ ] **Step 1: Create the pure-Objective-C types header**

This file is imported by the bridging header, so it must be self-contained and contain no C++.

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.h
//
// Pure Objective-C. This header is imported by TextMate-Bridging-Header.h,
// which ClangImporter compiles as C/Objective-C without the prelude prefix
// header -- so it must import its own dependencies and must never contain
// C++, nor import anything under Xcode/include/.

#import <Cocoa/Cocoa.h>

// Keys into TMThemeChoice.colors. Nine roles is enough to draw a convincing
// code sample and no more than the appearance step actually renders.
extern NSString* const TMThemeColorBackground;
extern NSString* const TMThemeColorForeground;
extern NSString* const TMThemeColorSelection;
extern NSString* const TMThemeColorCaret;
extern NSString* const TMThemeColorComment;
extern NSString* const TMThemeColorString;
extern NSString* const TMThemeColorKeyword;
extern NSString* const TMThemeColorNumber;
extern NSString* const TMThemeColorFunction;

@interface TMThemeChoice : NSObject
@property (nonatomic, copy, readonly) NSString* name;
@property (nonatomic, copy, readonly) NSString* identifier;
@property (nonatomic, copy, readonly) NSString* appearance;   // @"light", @"dark", @"unspecified"
@property (nonatomic, copy, readonly) NSDictionary<NSString*, NSColor*>* colors;
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier appearance:(NSString*)appearance colors:(NSDictionary<NSString*, NSColor*>*)colors;
@end

@interface TMBundleChoice : NSObject
@property (nonatomic, copy, readonly) NSString* name;
@property (nonatomic, copy, readonly) NSString* identifier;
@property (nonatomic, copy, readonly) NSString* category;
@property (nonatomic, readonly)       BOOL installed;
@property (nonatomic, readonly)       BOOL recommended;
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier category:(NSString*)category installed:(BOOL)installed recommended:(BOOL)recommended;
@end

// Pure rules, kept here rather than in the window controller so the test
// binary can reach them. The window controller does the C++ extraction and
// calls these; the extraction itself is verified by hand.

// Maps a bundle item's semanticClass field onto the appearance buckets the
// assistant offers. Returns @"light", @"dark" or @"unspecified".
extern NSString* TMThemeAppearanceForSemanticClass (NSString* semanticClass);

// Merges newly-declined bundle identifiers into an existing never-suggest
// list. MUST merge rather than replace: DocumentWindowController reads this
// list for its on-demand per-extension prompt.
extern NSArray<NSString*>* TMMergeNeverSuggestIdentifiers (NSArray<NSString*>* existing, NSArray<NSString*>* adding);

@protocol TMSetupAssistantHost <NSObject>
- (NSArray<TMThemeChoice*>*)availableThemes;
- (NSArray<TMBundleChoice*>*)availableBundles;
- (NSString*)currentAppearance;                                  // @"light", @"dark", or nil for automatic
- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance;
- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance;
- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest;
- (void)finishWithSkip:(BOOL)skipped;
@end
```

- [ ] **Step 2: Create the bridging header**

```objc
// Applications/TextMate/src/TextMate-Bridging-Header.h
//
// The ONLY Objective-C surface Swift can see. Keep it this small.
//
// ClangImporter compiles this as C/Objective-C, never Objective-C++, and
// without GCC_PREFIX_HEADER. Adding an Xcode/include/<framework> header here
// fails with "unknown type name 'NSNotificationName'" and similar, because
// those headers take their AppKit imports from the prelude. Adding anything
// with C++ in it fails with "function definition declared 'typedef'".

#import <Cocoa/Cocoa.h>
#import "SetupAssistant/SetupAssistantTypes.h"
```

- [ ] **Step 3: Create the first Swift file**

Every type crossing to Objective-C++ is `public`. `TMSetupAssistantStep` is the step enum the later tasks build on.

```swift
// Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift
import SwiftUI

public enum TMSetupAssistantStep: Int, CaseIterable {
	case welcome = 0
	case appearance = 1
	case bundles = 2

	var title: String {
		switch self {
			case .welcome:    return "Welcome to TextMate"
			case .appearance: return "Appearance"
			case .bundles:    return "Bundles"
		}
	}
}
```

- [ ] **Step 4: Register the Swift file and bridging header in project.yml**

In the `TextMate:` target, add the Swift source immediately after `main.mm`:

```yaml
      - path: "Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift"
```

and in that target's `settings.base`, immediately after the `INFOPLIST_FILE` line:

```yaml
        SWIFT_OBJC_BRIDGING_HEADER: "Applications/TextMate/src/TextMate-Bridging-Header.h"
```

- [ ] **Step 5: Regenerate the project**

Run: `xcodegen generate --spec project.yml`
Expected: `Created project at /Users/shelby/Development/textmate/TextMate.xcodeproj`

- [ ] **Step 6: Build and confirm Swift compiled**

Run: `bin/build`
Expected: `** BUILD SUCCEEDED **`

Then confirm the Swift module was really produced, rather than the file being silently ignored:

Run: `ls ~/build/textmate-revived/xcode/Release/TextMate.swiftmodule/`
Expected: `arm64-apple-macos.swiftmodule` present.

This check matters. A `.swift` file absent from the target's sources still leaves a green build; the only proof it compiled is the module.

- [ ] **Step 7: Commit**

```bash
git add project.yml TextMate.xcodeproj Applications/TextMate/src/SetupAssistant Applications/TextMate/src/TextMate-Bridging-Header.h STREAM.md
git commit -m "feat(setup): the first Swift file in this repository

Phase 6's islands need Swift, and no target here had ever contained a .swift
file. This lands the smallest possible one -- a step enum and the bridging
header -- so the toolchain question is settled in a committed state rather
than a spike that gets reverted.

The bridging header is deliberately two imports long. ClangImporter compiles
it as C/Objective-C without the prelude prefix header, so it can hold neither
C++ nor any header from Xcode/include/, both of which fail in ways that name
the wrong file."
```

---

### Task 2: SetupAssistantCore library, and the first test that runs

`TextMate_test` compiles only the generated runner; anything it exercises must come from a library it links. `PreferencesMigration` is the precedent — `library.static`, one `.mm`, linked by both `TextMate` and `TextMate_test`.

**Files:**
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.mm`
- Create: `Applications/TextMate/tests/t_setup_assistant.mm`
- Modify: `project.yml` (new `SetupAssistantCore` target; `TextMate` and `TextMate_test` dependencies)

**Interfaces:**
- Consumes: `TMThemeChoice`, `TMBundleChoice` from Task 1.
- Produces: the `SetupAssistantCore` static library, linked by `TextMate` and `TextMate_test`; `t_setup_assistant.mm` as the file later tasks add tests to.

- [ ] **Step 1: Write the failing test**

Note the constraints being obeyed: no `@interface` anywhere (the file is inside an implicit namespace), and `OAK_ASSERT` rather than `OAK_ASSERT_EQ` for object comparisons.

```objc
// Applications/TextMate/tests/t_setup_assistant.mm
#import "../src/SetupAssistant/SetupAssistantTypes.h"

// This file is wrapped in `namespace t_setup_assistant { … }` by bin/gen_test,
// so it cannot declare an Objective-C class. Everything under test is either a
// free function or a class method taking its inputs explicitly.

void test_theme_choice_carries_its_values ()
{
	NSDictionary* colors = @{ TMThemeColorBackground: NSColor.blackColor, TMThemeColorForeground: NSColor.whiteColor };
	TMThemeChoice* choice = [TMThemeChoice choiceWithName:@"Twilight" identifier:@"766026CB-703D-4610-B070-8DE07D967C5F" appearance:@"dark" colors:colors];

	// to_s(NSString*) lives in Frameworks/ns, which TextMate_test does not link.
	// Compare with isEqualToString:, exactly as t_preferences_migration.mm does.
	OAK_ASSERT([choice.name isEqualToString:@"Twilight"]);
	OAK_ASSERT([choice.appearance isEqualToString:@"dark"]);
	OAK_ASSERT_EQ(choice.colors.count, 2);
	OAK_ASSERT(choice.colors[TMThemeColorBackground] == NSColor.blackColor);
}

void test_bundle_choice_carries_its_values ()
{
	TMBundleChoice* choice = [TMBundleChoice choiceWithName:@"Ruby" identifier:@"E4B4E2FF-C8EE-44B2-A6E0-A5B2E1F0C1D2" category:@"Languages" installed:NO recommended:YES];

	OAK_ASSERT([choice.name isEqualToString:@"Ruby"]);
	OAK_ASSERT([choice.category isEqualToString:@"Languages"]);
	OAK_ASSERT_EQ(choice.installed, false);
	OAK_ASSERT_EQ(choice.recommended, true);
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/build TextMate/test`
Expected: FAIL at link with `Undefined symbols … _OBJC_CLASS_$_TMThemeChoice`. The header exists but nothing implements it and nothing links it.

- [ ] **Step 3: Implement the types**

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.mm
#import "SetupAssistantTypes.h"

NSString* const TMThemeColorBackground = @"background";
NSString* const TMThemeColorForeground = @"foreground";
NSString* const TMThemeColorSelection  = @"selection";
NSString* const TMThemeColorCaret      = @"caret";
NSString* const TMThemeColorComment    = @"comment";
NSString* const TMThemeColorString     = @"string";
NSString* const TMThemeColorKeyword    = @"keyword";
NSString* const TMThemeColorNumber     = @"number";
NSString* const TMThemeColorFunction   = @"function";

@implementation TMThemeChoice
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier appearance:(NSString*)appearance colors:(NSDictionary<NSString*, NSColor*>*)colors
{
	TMThemeChoice* res = [self new];
	res->_name       = [name copy];
	res->_identifier = [identifier copy];
	res->_appearance = [appearance copy];
	res->_colors     = [colors copy];
	return res;
}
@end

@implementation TMBundleChoice
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier category:(NSString*)category installed:(BOOL)installed recommended:(BOOL)recommended
{
	TMBundleChoice* res = [self new];
	res->_name        = [name copy];
	res->_identifier  = [identifier copy];
	res->_category    = [category copy];
	res->_installed   = installed;
	res->_recommended = recommended;
	return res;
}
@end

NSString* TMThemeAppearanceForSemanticClass (NSString* semanticClass)
{
	if([semanticClass containsString:@"theme.dark"])
		return @"dark";
	if([semanticClass containsString:@"theme.light"])
		return @"light";
	return @"unspecified";
}

NSArray<NSString*>* TMMergeNeverSuggestIdentifiers (NSArray<NSString*>* existing, NSArray<NSString*>* adding)
{
	NSMutableSet<NSString*>* set = [NSMutableSet setWithArray:existing ?: @[]];
	[set addObjectsFromArray:adding ?: @[]];
	return set.allObjects;
}
```

- [ ] **Step 3b: Add tests for the pure rules**

Append to `t_setup_assistant.mm`. These are the marshalling tests the spec asks
for: the parts that can live away from C++ and therefore away from the app target.

```objc
void test_semantic_class_maps_to_appearance ()
{
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.dark.twilight") isEqualToString:@"dark"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.light.mac_classic") isEqualToString:@"light"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.something") isEqualToString:@"unspecified"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"") isEqualToString:@"unspecified"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(nil) isEqualToString:@"unspecified"]);
}

// The regression this exists to prevent: replacing rather than merging
// resurrects every bundle suggestion the user has ever declined.
void test_never_suggest_merges_rather_than_replaces ()
{
	NSArray* merged = TMMergeNeverSuggestIdentifiers(@[ @"A", @"B" ], @[ @"B", @"C" ]);
	OAK_ASSERT_EQ(merged.count, 3);
	OAK_ASSERT([[NSSet setWithArray:merged] isEqualToSet:[NSSet setWithArray:@[ @"A", @"B", @"C" ]]]);
}

void test_never_suggest_tolerates_empty_input ()
{
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(nil, nil).count, 0);
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(@[ @"A" ], nil).count, 1);
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(nil, @[ @"A" ]).count, 1);
}
```

- [ ] **Step 4: Add the library target and link it**

In `project.yml`, immediately before the `TextMate_test:` target, add:

```yaml
  SetupAssistantCore:
    type: library.static
    platform: macOS
    sources:
      - path: "Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.mm"
    settings:
      base:
        GCC_PREFIX_HEADER: "$(SRCROOT)/Shared/PCH/prelude.mm"
```

Add to the `TextMate` target's `dependencies:` list:

```yaml
      - target: SetupAssistantCore
        link: true
```

Add to the `TextMate_test` target's `dependencies:` list, alongside the existing `- sdk: Foundation.framework`:

```yaml
      - target: SetupAssistantCore
      - sdk: AppKit.framework
```

`AppKit.framework` is required because `TMThemeChoice` carries `NSColor`. `TextMate_test` previously linked Foundation alone.

- [ ] **Step 5: Regenerate and run the test**

Run: `xcodegen generate --spec project.yml && bin/build TextMate/test`
Expected: `** BUILD SUCCEEDED **` and the runner reporting the new tests passing alongside the existing preferences-migration ones.

- [ ] **Step 6: Commit**

```bash
git add project.yml TextMate.xcodeproj Applications/TextMate/src/SetupAssistant Applications/TextMate/tests STREAM.md
git commit -m "feat(setup): data types crossing the Swift boundary, and a library to test them

TextMate_test compiles only the generated runner, so anything it exercises has
to come from a library both binaries link -- the shape PreferencesMigration
already uses. SetupAssistantCore is that library.

TMThemeChoice and TMBundleChoice are plain Objective-C mirrors rather than the
real BundleSpec and theme_ptr, because neither can cross a bridging header:
one lives behind Xcode/include/, the other is C++."
```

---

### Task 3: The gating predicate

Free functions, not a class — matching `PreferencesMigration` and sidestepping the rule that a test file cannot declare an Objective-C class.

**Files:**
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantGating.h`
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantGating.mm`
- Modify: `Applications/TextMate/tests/t_setup_assistant.mm`
- Modify: `project.yml` (`SetupAssistantCore` sources)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `TMSetupAssistantShouldRunAtLaunch(NSUserDefaults*)` → `BOOL`, `TMSetupAssistantMarkAsRun(NSUserDefaults*)` → `void`, and `kUserDefaultsDidRunSetupAssistantKey`.

- [ ] **Step 1: Write the failing tests**

Append to `Applications/TextMate/tests/t_setup_assistant.mm`, and add the new import at the top of the file:

```objc
#import "../src/SetupAssistant/SetupAssistantGating.h"
```

```objc
// Each test uses its own throwaway suite name and removes it before and after,
// so a prior interrupted run never leaks state and the developer's real
// preferences are never touched. Tests in this target run in parallel by
// default; per-test domains are what makes that safe.

static NSUserDefaults* fresh_defaults (NSString* suite)
{
	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
	return [[NSUserDefaults alloc] initWithSuiteName:suite];
}

void test_assistant_runs_when_key_absent ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Absent";
	NSUserDefaults* defaults = fresh_defaults(suite);

	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), true);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

void test_assistant_does_not_run_once_marked ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Marked";
	NSUserDefaults* defaults = fresh_defaults(suite);

	TMSetupAssistantMarkAsRun(defaults);
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), false);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

void test_marking_is_idempotent ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Twice";
	NSUserDefaults* defaults = fresh_defaults(suite);

	TMSetupAssistantMarkAsRun(defaults);
	TMSetupAssistantMarkAsRun(defaults);
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), false);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

// The old bundle-prompt key must not suppress the assistant. Every existing
// user has it set, and they are exactly the audience the appearance step is
// aimed at.
void test_legacy_bundle_prompt_key_does_not_suppress_the_assistant ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Legacy";
	NSUserDefaults* defaults = fresh_defaults(suite);

	[defaults setBool:YES forKey:@"didPromptForDefaultBundles"];
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), true);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/build TextMate/test`
Expected: FAIL to compile with `'../src/SetupAssistant/SetupAssistantGating.h' file not found`.

- [ ] **Step 3: Write the header**

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantGating.h
#import <Foundation/Foundation.h>

// Written once the assistant has been completed or skipped. It is a NEW key
// rather than a reuse of kUserDefaultsDidPromptForDefaultBundlesKey, and that
// is deliberate: every existing user already has the old key set, so reusing
// it would hide the assistant from precisely the people the appearance step
// exists for.
extern NSString* const kUserDefaultsDidRunSetupAssistantKey;

// Whether the assistant should be shown during applicationDidFinishLaunching:.
// The Help menu entry point does NOT consult this -- it always shows.
BOOL TMSetupAssistantShouldRunAtLaunch (NSUserDefaults* defaults);

// Records that the assistant has run. Called on completion AND on skip: a
// dismissed assistant must not reappear on the next launch.
void TMSetupAssistantMarkAsRun (NSUserDefaults* defaults);
```

- [ ] **Step 4: Write the implementation**

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantGating.mm
#import "SetupAssistantGating.h"

NSString* const kUserDefaultsDidRunSetupAssistantKey = @"didRunSetupAssistant";

BOOL TMSetupAssistantShouldRunAtLaunch (NSUserDefaults* defaults)
{
	return ![defaults boolForKey:kUserDefaultsDidRunSetupAssistantKey];
}

void TMSetupAssistantMarkAsRun (NSUserDefaults* defaults)
{
	[defaults setBool:YES forKey:kUserDefaultsDidRunSetupAssistantKey];
}
```

- [ ] **Step 5: Add the source to the library**

In `project.yml`, add to `SetupAssistantCore`'s `sources:`:

```yaml
      - path: "Applications/TextMate/src/SetupAssistant/SetupAssistantGating.mm"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodegen generate --spec project.yml && bin/build TextMate/test`
Expected: `** BUILD SUCCEEDED **`, all six tests passing.

- [ ] **Step 7: Commit**

```bash
git add project.yml TextMate.xcodeproj Applications/TextMate/src/SetupAssistant Applications/TextMate/tests STREAM.md
git commit -m "feat(setup): gate the assistant on its own defaults key

A new key rather than a reuse of kUserDefaultsDidPromptForDefaultBundlesKey.
Every existing user already has the old key set, so reusing it would hide the
assistant from exactly the people its appearance step exists for -- the ones
who cannot currently find View -> Theme.

Free functions rather than a class method, matching PreferencesMigration: a
test file is wrapped in a namespace by bin/gen_test and Objective-C forbids
declaring a class inside one."
```

---

### Task 4: The window, and the Help menu entry point

Deliverable: `Help → Setup Assistant…` opens an empty modal window that closes cleanly. No content yet — this proves the window lifecycle, the modal session, and the menu wiring in isolation from SwiftUI.

**Files:**
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.h`
- Create: `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm`
- Modify: `Applications/TextMate/src/AppController.mm` (Help menu at `:408-412`, plus a new action)
- Modify: `project.yml` (TextMate target sources)

**Interfaces:**
- Consumes: `TMSetupAssistantShouldRunAtLaunch` (Task 3), `TMSetupAssistantHost` (Task 1).
- Produces: `+[SetupAssistantWindowController sharedInstance]`, `-[SetupAssistantWindowController runModal]`, and `-[AppController showSetupAssistant:]`.

- [ ] **Step 1: Write the window controller header**

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.h
#import <Cocoa/Cocoa.h>

@interface SetupAssistantWindowController : NSWindowController
+ (instancetype)sharedInstance;

// Runs the assistant app-modally and returns when it is finished or skipped.
// Both paths mark the assistant as run.
- (void)runModal;
@end
```

- [ ] **Step 2: Write the window controller with an empty content view**

```objc
// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm
#import "SetupAssistantWindowController.h"
#import "SetupAssistantGating.h"

@interface SetupAssistantWindowController ()
@end

@implementation SetupAssistantWindowController
+ (instancetype)sharedInstance
{
	static SetupAssistantWindowController* instance = [self new];
	return instance;
}

- (instancetype)init
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 460) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
	window.title = @"Setup Assistant";
	[window center];

	if(self = [super initWithWindow:window])
	{
		window.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
	}
	return self;
}

- (void)runModal
{
	[self.window center];
	[NSApp runModalForWindow:self.window];
	[self.window orderOut:self];
	TMSetupAssistantMarkAsRun(NSUserDefaults.standardUserDefaults);
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	// Closing the window with the title-bar button must end the modal session,
	// or the app is left running a session with no window and stops responding
	// to everything.
	[NSApp stopModal];
}
@end
```

- [ ] **Step 3: Add the menu item and the action**

In `Applications/TextMate/src/AppController.mm`, change the Help menu at `:408-412` to:

```objc
{ @"Help",
    .systemMenu = MBMenuTypeHelp, .submenu = {
        { @"TextMate Help", @selector(showHelp:), @"?" },
        { /* -------- */ },
        { @"Setup Assistant…", @selector(showSetupAssistant:) },
    }
},
```

Add the import near the other local imports at the top of the file:

```objc
#import "SetupAssistant/SetupAssistantWindowController.h"
```

Add the action beside `orderFrontAboutPanel:` (`:656`), following the same shape:

```objc
- (IBAction)showSetupAssistant:(id)sender
{
	[SetupAssistantWindowController.sharedInstance runModal];
}
```

- [ ] **Step 4: Register the sources**

In `project.yml`, add to the `TextMate` target's `sources:`:

```yaml
      - path: "Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm"
```

- [ ] **Step 5: Build**

Run: `xcodegen generate --spec project.yml && bin/build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Verify manually — this step cannot be automated**

GUI gestures cannot be synthesised in the agent sandbox. Ask the maintainer to run `bin/deploy-local`, launch TextMate, and confirm:

1. `Help → Setup Assistant…` exists and is enabled.
2. Choosing it opens a centred empty window.
3. The window is modal — clicking a document window behind it does nothing.
4. Closing it with the title-bar close button returns the app to normal, and the app still responds to menus and typing.

Point 4 is the one that fails if `windowWillClose:` is wrong, and its symptom is a completely unresponsive app.

- [ ] **Step 7: Commit**

```bash
git add project.yml TextMate.xcodeproj Applications/TextMate/src "Applications/TextMate/src/AppController.mm" STREAM.md
git commit -m "feat(setup): an empty assistant window, reachable from Help

The window lifecycle and the modal session are worth proving on their own,
before SwiftUI is added on top: a modal session whose window closes without
stopping the session leaves the whole app unresponsive, and that is far easier
to diagnose here than tangled up with a first SwiftUI integration.

The menu bar is built in code through MenuBuilder rather than a xib, so the
item is three lines at AppController.mm:408 and an action following the same
shape orderFrontAboutPanel: already uses."
```

---

### Task 5: The SwiftUI shell — three steps, Back, Continue, Skip

**Files:**
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift`
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm`

**Interfaces:**
- Consumes: `TMSetupAssistantStep` (Task 1), `TMSetupAssistantHost` (Task 1), the window from Task 4.
- Produces: `SetupAssistantHostingController` — a `public` Swift class exposing `+[SetupAssistantHostingController viewForHost:]` to Objective-C++, returning an `NSView` the window controller installs as its `contentView`.

- [ ] **Step 1: Write the SwiftUI shell**

Replace the contents of `SetupAssistantView.swift`:

```swift
// Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift
import SwiftUI

public enum TMSetupAssistantStep: Int, CaseIterable {
	case welcome = 0
	case appearance = 1
	case bundles = 2

	var title: String {
		switch self {
			case .welcome:    return "Welcome to TextMate"
			case .appearance: return "Appearance"
			case .bundles:    return "Bundles"
		}
	}
}

@MainActor
final class SetupAssistantModel: ObservableObject {
	@Published var step: TMSetupAssistantStep = .welcome

	let host: any TMSetupAssistantHost

	init(host: any TMSetupAssistantHost) {
		self.host = host
	}

	var isFirstStep: Bool { step == .welcome }
	var isLastStep: Bool  { step == .bundles }

	func back() {
		guard let previous = TMSetupAssistantStep(rawValue: step.rawValue - 1) else { return }
		step = previous
	}

	func advance() {
		guard let next = TMSetupAssistantStep(rawValue: step.rawValue + 1) else { return }
		step = next
	}

	func finish() { host.finish(withSkip: false) }
	func skip()   { host.finish(withSkip: true) }
}

struct SetupAssistantView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 16) {
				Text(model.step.title).font(.largeTitle.bold())

				switch model.step {
					case .welcome:    WelcomeStepView()
					case .appearance: Text("Appearance")     // Task 6
					case .bundles:    Text("Bundles")        // Task 7
				}

				Spacer()
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(24)

			Divider()

			HStack {
				Button("Skip Setup") { model.skip() }
				Spacer()
				if !model.isFirstStep {
					Button("Back") { model.back() }
				}
				Button(model.isLastStep ? "Done" : "Continue") {
					model.isLastStep ? model.finish() : model.advance()
				}
				.keyboardShortcut(.defaultAction)
			}
			.padding(16)
		}
		.frame(minWidth: 640, minHeight: 460)
	}
}

struct WelcomeStepView: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("TextMate Revived is a fork of TextMate for macOS 26 on Apple Silicon.")
			Text("This assistant sets up how the editor looks and which bundles you have. You can run it again at any time from the Help menu.")
				.foregroundStyle(.secondary)
		}
	}
}

// The Objective-C++ entry point. `public` is load-bearing: an internal @objc
// declaration compiles, reaches the .swiftmodule, and is silently absent from
// the generated TextMate-Swift.h.
@objc(SetupAssistantHostingController)
public final class SetupAssistantHostingController: NSObject {
	@objc public static func view(for host: any TMSetupAssistantHost) -> NSView {
		return NSHostingView(rootView: SetupAssistantView(model: SetupAssistantModel(host: host)))
	}
}
```

- [ ] **Step 2: Install the SwiftUI view as the window's content**

In `SetupAssistantWindowController.mm`, add the generated-header import at the top:

```objc
#import "TextMate-Swift.h"
```

Declare conformance in the class extension:

```objc
@interface SetupAssistantWindowController () <TMSetupAssistantHost>
@end
```

Replace the `contentView` assignment in `init` with:

```objc
		window.contentView = [SetupAssistantHostingController viewFor:self];
```

Add stub implementations of the protocol — the real ones arrive in Tasks 6 and 7:

```objc
- (NSArray<TMThemeChoice*>*)availableThemes                                   { return @[]; }
- (NSArray<TMBundleChoice*>*)availableBundles                                 { return @[]; }
- (NSString*)currentAppearance                                                { return nil; }
- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance        { return nil; }
- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance { }
- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest { }

- (void)finishWithSkip:(BOOL)skipped
{
	[NSApp stopModal];
}
```

- [ ] **Step 3: Build**

Run: `bin/build`
Expected: `** BUILD SUCCEEDED **`

If it fails with `use of undeclared identifier 'SetupAssistantHostingController'`, the Swift class or its method is not `public` — that is the failure mode named in Global Constraints, and the error points at the Objective-C++ file rather than the Swift one.

- [ ] **Step 4: Verify manually**

Ask the maintainer to `bin/deploy-local` and confirm via `Help → Setup Assistant…`:

1. Three steps advance with Continue and return with Back.
2. Back is absent on the first step.
3. The last step's button reads "Done".
4. Return activates the default button; "Skip Setup" closes the window.
5. Closing the window with the close button still leaves the app responsive.

- [ ] **Step 5: Commit**

```bash
git add Applications/TextMate/src/SetupAssistant STREAM.md
git commit -m "feat(setup): the assistant's SwiftUI shell

Three steps with Back, Continue and Skip, hosted in the window from the
previous commit. Step content is stubbed; this commit is about the navigation
and the Objective-C++ to Swift seam being right before either matters.

Swift holds only which step is showing. Every action leaves through the
TMSetupAssistantHost protocol into Objective-C++, which is where anything with
a side effect belongs."
```

---

### Task 6: The appearance step

**Files:**
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm`
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift`
- Modify: `project.yml` (TextMate target `HEADER_SEARCH_PATHS` already lists `theme` and `bundles`; verify)

**Interfaces:**
- Consumes: `TMThemeChoice` (Task 1), the host protocol (Task 1).
- Produces: real implementations of `-availableThemes`, `-currentAppearance`, `-currentThemeIdentifierForAppearance:` and `-applyThemeIdentifier:appearance:`.

- [ ] **Step 1: Implement theme enumeration and colour extraction**

The C++ APIs, verified against the real headers:
`bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeTheme)` enumerates theme items; `parse_theme(item)` yields a `theme_ptr`; `theme->styles_for_scope(scope)` yields a `styles_t` whose accessors return `CGColorRef`; `[NSColor colorWithCGColor:]` converts. The same sequence already runs in `QuickLookPreviewProvider.mm:107-134`.

Add to `SetupAssistantWindowController.mm`:

```objc
#import <bundles/bundles.h>
#import <theme/theme.h>
#import <ns/ns.h>

static NSDictionary<NSString*, NSColor*>* colors_for_theme (theme_ptr const& theme)
{
	auto color = [&theme](char const* scopeString){
		auto const& styles = theme->styles_for_scope(scope::scope_t(scopeString));
		return [NSColor colorWithCGColor:styles.foreground()];
	};

	auto const& base = theme->styles_for_scope(scope::wildcard);
	return @{
		TMThemeColorBackground: [NSColor colorWithCGColor:base.background()],
		TMThemeColorForeground: [NSColor colorWithCGColor:base.foreground()],
		TMThemeColorSelection:  [NSColor colorWithCGColor:base.selection()],
		TMThemeColorCaret:      [NSColor colorWithCGColor:base.caret()],
		TMThemeColorComment:    color("comment"),
		TMThemeColorString:     color("string.quoted.double"),
		TMThemeColorKeyword:    color("keyword.control"),
		TMThemeColorNumber:     color("constant.numeric"),
		TMThemeColorFunction:   color("entity.name.function"),
	};
}

- (NSArray<TMThemeChoice*>*)availableThemes
{
	NSMutableArray<TMThemeChoice*>* res = [NSMutableArray array];
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeTheme))
	{
		theme_ptr theme = parse_theme(item);
		if(!theme)
			continue;

		// bundles::kFieldSemanticClass is declared at Frameworks/bundles/src/item.h:26.
		// The themes menu classifies by the same field, so the assistant and
		// View -> Theme agree on which themes are light and which are dark.
		// The mapping itself lives in SetupAssistantCore and is unit-tested.
		NSString* appearance = TMThemeAppearanceForSemanticClass(to_ns(item->value_for_field(bundles::kFieldSemanticClass)));

		[res addObject:[TMThemeChoice choiceWithName:to_ns(item->name()) identifier:to_ns(to_s(item->uuid())) appearance:appearance colors:colors_for_theme(theme)]];
	}
	[res sortUsingComparator:^NSComparisonResult(TMThemeChoice* a, TMThemeChoice* b){
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return res;
}

- (NSString*)currentAppearance
{
	return [NSUserDefaults.standardUserDefaults stringForKey:@"themeAppearance"];
}

- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance
{
	NSString* key = [appearance isEqualToString:@"dark"] ? @"darkModeThemeUUID" : @"universalThemeUUID";
	return [NSUserDefaults.standardUserDefaults stringForKey:key];
}

- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance
{
	// Same keys View -> Theme writes via takeUniversalThemeUUIDFrom: and
	// takeDarkThemeUUIDFrom: (AppController Menus.mm:103-111), so the two
	// routes cannot diverge.
	NSString* key = [appearance isEqualToString:@"dark"] ? @"darkModeThemeUUID" : @"universalThemeUUID";
	if(identifier)
		[NSUserDefaults.standardUserDefaults setObject:identifier forKey:key];
}
```

`bundles::kFieldSemanticClass` is verified — `Frameworks/bundles/src/item.h:26`. Confirm `item->name()` and `item->uuid()` against the same header before building; they are used here as `to_ns(item->name())` and `to_ns(to_s(item->uuid()))`.

- [ ] **Step 2: Implement appearance writing**

Add to the same file, and call it from `-finishWithSkip:` when not skipped:

```objc
- (void)applyAppearance:(NSString*)appearance
{
	if(appearance)
			[NSUserDefaults.standardUserDefaults setObject:appearance forKey:@"themeAppearance"];
	else	[NSUserDefaults.standardUserDefaults removeObjectForKey:@"themeAppearance"];
}
```

Absent means automatic — that is what `takeThemeAppearanceFrom:` already encodes.

- [ ] **Step 3: Build the appearance step in SwiftUI**

Replace `case .appearance: Text("Appearance")` in `SetupAssistantView.swift` with `AppearanceStepView(model: model)`, and add:

```swift
struct AppearanceStepView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Picker("Appearance", selection: $model.appearance) {
				Text("Light").tag("light")
				Text("Dark").tag("dark")
				Text("Automatic").tag("auto")
			}
			.pickerStyle(.segmented)
			.frame(maxWidth: 320)

			HStack(alignment: .top, spacing: 16) {
				List(model.themes(for: model.editingAppearance), id: \.identifier, selection: $model.selectedThemeIdentifier) { theme in
					Text(theme.name).tag(theme.identifier)
				}
				.frame(width: 220)

				ThemePreview(theme: model.selectedTheme)
					.frame(maxWidth: .infinity, minHeight: 200)
			}
		}
	}
}

// A mockup, not a live editor. Rendering real text would need the C++ theme
// and layout frameworks, neither of which can cross the bridging header. The
// colours are real; the code is fake.
struct ThemePreview: View {
	let theme: TMThemeChoice?

	private func color(_ key: String, _ fallback: Color) -> Color {
		guard let value = theme?.colors[key] else { return fallback }
		return Color(nsColor: value)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			line([("# frobnicate the widget", TMThemeColorComment)])
			line([("def ", TMThemeColorKeyword), ("frobnicate", TMThemeColorFunction), ("(count)", TMThemeColorForeground)])
			line([("  raise ", TMThemeColorKeyword), ("\"too many\"", TMThemeColorString), (" if count > ", TMThemeColorForeground), ("42", TMThemeColorNumber)])
			line([("  count * ", TMThemeColorForeground), ("2", TMThemeColorNumber)])
			line([("end", TMThemeColorKeyword)])
		}
		.font(.system(.body, design: .monospaced))
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(color(TMThemeColorBackground, .black))
		.clipShape(RoundedRectangle(cornerRadius: 8))
	}

	private func line(_ runs: [(String, String)]) -> some View {
		runs.reduce(Text("")) { partial, run in
			partial + Text(run.0).foregroundColor(color(run.1, .white))
		}
	}
}
```

- [ ] **Step 4: Add the model state the view binds to**

Add to `SetupAssistantModel`:

```swift
	@Published var appearance: String = "auto"
	@Published var selectedThemeIdentifier: String?

	private lazy var allThemes: [TMThemeChoice] = host.availableThemes()

	// In automatic mode both keys are used, so the user edits the light theme
	// here; the dark one keeps whatever it already had.
	var editingAppearance: String { appearance == "dark" ? "dark" : "light" }

	func themes(for appearance: String) -> [TMThemeChoice] {
		allThemes.filter { $0.appearance == appearance || $0.appearance == "unspecified" }
	}

	var selectedTheme: TMThemeChoice? {
		allThemes.first { $0.identifier == selectedThemeIdentifier }
	}
```

and initialise the selection in `init`, after `self.host = host`:

```swift
		self.appearance = host.currentAppearance() ?? "auto"
		self.selectedThemeIdentifier = host.currentThemeIdentifier(forAppearance: editingAppearance)
```

Change `finish()` to apply before finishing:

```swift
	func finish() {
		if let identifier = selectedThemeIdentifier {
			host.applyThemeIdentifier(identifier, appearance: editingAppearance)
		}
		host.finish(withSkip: false)
	}
```

- [ ] **Step 5: Build**

Run: `bin/build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Verify manually**

Ask the maintainer to confirm:

1. The theme list is populated and matches what `View → Theme` offers.
2. Selecting a theme changes the preview immediately, with no perceptible delay.
3. The preview's colours actually correspond to the chosen theme.
4. Choosing a theme and finishing changes the editor's theme; reopening the assistant shows that theme preselected.
5. Switching to Dark and choosing a theme writes the dark slot without disturbing the light one.

Check `defaults read com.apple.universalaccess reduceTransparency` before drawing conclusions about anything translucent in a screenshot.

- [ ] **Step 7: Commit**

```bash
git add Applications/TextMate/src/SetupAssistant STREAM.md
git commit -m "feat(setup): the appearance step, with a live theme mockup

This is the step that earns the feature. Theme and appearance live in
View -> Theme and nowhere else, so an untouched kMacClassicThemeUUID default
is indistinguishable from lost settings -- which is exactly how it was
reported this month.

The preview is a mockup with real colours rather than a live editor: rendering
real text needs the C++ theme and layout frameworks, and neither can cross a
bridging header. All colours for all themes are marshalled once when the
assistant opens, so selection redraws from Swift state with no round trip.

Writes the same universalThemeUUID, darkModeThemeUUID and themeAppearance keys
the menu writes, so the two routes cannot diverge."
```

---

### Task 7: The bundles step

**Files:**
- Modify: `Applications/TextMate/src/FirstLaunchBundleInstaller.h` (expose `candidateSpecs`)
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm`
- Modify: `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift`

**Interfaces:**
- Consumes: `TMBundleChoice` (Task 1), the host protocol (Task 1).
- Produces: real `-availableBundles` and `-installBundleIdentifiers:neverSuggest:`.

- [ ] **Step 1: Expose the existing candidate list**

`+[FirstLaunchBundleInstaller candidateSpecs]` at `FirstLaunchBundleInstaller.mm:49-72` already computes exactly the right set — shipped-origin bundles that are not installed and not in the never-suggest list. Move its declaration into the header:

```objc
// Applications/TextMate/src/FirstLaunchBundleInstaller.h
@class BundleSpec;

@interface FirstLaunchBundleInstaller : NSWindowController
+ (void)promptIfNeeded;

// Shipped-origin bundles that are neither installed nor marked never-suggest,
// sorted by category then name. Exposed for the Setup Assistant, which
// replaces this class's window while keeping its selection logic.
+ (NSArray<BundleSpec*>*)candidateSpecs;
@end
```

Remove the `+ (NSArray<BundleSpec*>*)candidateSpecs` declaration from the class extension in the `.mm` if one exists there.

- [ ] **Step 2: Implement the host methods**

Add to `SetupAssistantWindowController.mm`:

```objc
#import "../FirstLaunchBundleInstaller.h"
#import <BundlesManager/BundlesManager.h>
#import <BundlesManager/BundleSpec.h>

- (NSArray<TMBundleChoice*>*)availableBundles
{
	NSMutableArray<TMBundleChoice*>* res = [NSMutableArray array];
	for(BundleSpec* spec in FirstLaunchBundleInstaller.candidateSpecs)
	{
		[res addObject:[TMBundleChoice choiceWithName:spec.name identifier:spec.uuid.UUIDString category:(spec.category ?: @"Other") installed:(spec.installedSHA != nil) recommended:YES]];
	}
	return res;
}

- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest
{
	if(neverSuggest.count)
	{
		// Merge rather than replace: DocumentWindowController reads this list
		// for its on-demand per-extension prompt, and clobbering it would
		// resurrect suggestions the user already declined. The merge itself
		// lives in SetupAssistantCore and is unit-tested for exactly that.
		NSArray* existing = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey];
		[NSUserDefaults.standardUserDefaults setObject:TMMergeNeverSuggestIdentifiers(existing, neverSuggest) forKey:kUserDefaultsBundlesToNeverSuggestKey];
	}

	if(!install.count)
		return;

	NSMutableArray<BundleSpec*>* specs = [NSMutableArray array];
	NSSet* wanted = [NSSet setWithArray:install];
	for(BundleSpec* spec in FirstLaunchBundleInstaller.candidateSpecs)
	{
		if([wanted containsObject:spec.uuid.UUIDString])
			[specs addObject:spec];
	}

	[BundlesManager.sharedInstance installSpecs:specs completionHandler:^(NSArray<BundleSpec*>* installed){ }];
}
```

- [ ] **Step 3: Build the bundles step in SwiftUI**

Replace `case .bundles: Text("Bundles")` with `BundlesStepView(model: model)`, and add:

```swift
struct BundlesStepView: View {
	@ObservedObject var model: SetupAssistantModel

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Bundles add language support, commands and snippets. Recommended ones are already selected.")
				.foregroundStyle(.secondary)

			List(model.bundles, id: \.identifier) { bundle in
				Toggle(isOn: model.binding(for: bundle)) {
					VStack(alignment: .leading, spacing: 2) {
						Text(bundle.name)
						Text(bundle.category).font(.caption).foregroundStyle(.secondary)
					}
				}
				.disabled(bundle.installed)
			}
		}
	}
}
```

Add to `SetupAssistantModel`:

```swift
	@Published var checkedBundleIdentifiers: Set<String> = []

	private lazy var allBundles: [TMBundleChoice] = host.availableBundles()
	var bundles: [TMBundleChoice] { allBundles }

	func binding(for bundle: TMBundleChoice) -> Binding<Bool> {
		Binding(
			get: { bundle.installed || self.checkedBundleIdentifiers.contains(bundle.identifier) },
			set: { isOn in
				if isOn { self.checkedBundleIdentifiers.insert(bundle.identifier) }
				else    { self.checkedBundleIdentifiers.remove(bundle.identifier) }
			}
		)
	}
```

Initialise the pre-checked set in `init`, after the theme lines:

```swift
		self.checkedBundleIdentifiers = Set(allBundles.filter { $0.recommended && !$0.installed }.map { $0.identifier })
```

Extend `finish()`:

```swift
	func finish() {
		if let identifier = selectedThemeIdentifier {
			host.applyThemeIdentifier(identifier, appearance: editingAppearance)
		}
		let offered = allBundles.filter { !$0.installed }
		let install = offered.filter { checkedBundleIdentifiers.contains($0.identifier) }.map { $0.identifier }
		let never   = offered.filter { !checkedBundleIdentifiers.contains($0.identifier) }.map { $0.identifier }
		host.installBundleIdentifiers(install, neverSuggest: never)
		host.finish(withSkip: false)
	}
```

- [ ] **Step 4: Build**

Run: `bin/build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify manually**

1. The list matches what the old first-launch modal offered.
2. Recommended entries are pre-checked; installed ones show checked and disabled.
3. Finishing installs the checked bundles.
4. Unchecked bundles do not prompt again when a matching file is opened — this is the `kUserDefaultsBundlesToNeverSuggestKey` path and the specific thing that breaks if the merge in Step 2 were a replace.
5. Skipping installs nothing and marks nothing as never-suggest.

- [ ] **Step 6: Commit**

```bash
git add Applications/TextMate/src STREAM.md
git commit -m "feat(setup): the bundles step, reusing the existing selection logic

+[FirstLaunchBundleInstaller candidateSpecs] already computes the right set --
shipped-origin, not installed, not marked never-suggest -- and
BundlesManager already installs them. Rewriting either to move the UI would be
risk with no payoff, so the class keeps its logic and only loses its window.

The never-suggest list is merged rather than replaced. DocumentWindowController
reads it for the on-demand per-extension prompt, and clobbering it would
resurrect suggestions the user had already declined."
```

---

### Task 8: Wire it into launch, retire the old modal

The last task, and the only one that changes what a user sees on a normal launch.

**Files:**
- Modify: `Applications/TextMate/src/AppController.mm:592`
- Modify: `Applications/TextMate/src/FirstLaunchBundleInstaller.mm` (remove the window)
- Modify: `CHANGELOG.md`, `HANDOFF.md`, `STREAM.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: everything from Tasks 3-7.
- Produces: the shipped behaviour.

- [ ] **Step 1: Replace the launch call site**

At `AppController.mm:592`, replace `[FirstLaunchBundleInstaller promptIfNeeded];` with:

```objc
	if(TMSetupAssistantShouldRunAtLaunch(NSUserDefaults.standardUserDefaults))
		[SetupAssistantWindowController.sharedInstance runModal];
```

and add the gating import beside the window-controller one:

```objc
#import "SetupAssistant/SetupAssistantGating.h"
```

- [ ] **Step 2: Retire the old modal window, keep the logic**

In `FirstLaunchBundleInstaller.mm`, delete `+promptIfNeeded` and the window/NIB-construction code it drives, keeping `+candidateSpecs` and anything it depends on. Remove `+promptIfNeeded` from the header.

Run: `grep -rn 'promptIfNeeded' --include=*.mm --include=*.h .`
Expected: no hits outside the file being edited. If there are others, they are call sites that must be updated in this same commit.

- [ ] **Step 3: Build and run the full suite**

Run: `bin/build && bin/build TextMate/test`
Expected: `** BUILD SUCCEEDED **` for both, all tests passing.

- [ ] **Step 4: Verify manually — the full first-launch path**

This is the list from the spec, and it is the definition of done. Ask the maintainer to confirm each:

1. A fresh profile shows the assistant *before* any document window restores.
2. ESC skips, and the assistant does not reappear on the next launch.
3. `Help → Setup Assistant…` reopens it with current state reflected, not a blank wizard.
4. A theme chosen in the assistant is actually applied to an open document.
5. Bundles checked are installed; bundles left unchecked do not re-prompt.

To test a fresh profile without destroying real settings, back up and remove the preferences domain:

```bash
defaults export com.shelbydenike.TextMate ~/Desktop/textmate-prefs-backup.plist
defaults delete com.shelbydenike.TextMate
# to restore afterwards:
defaults import com.shelbydenike.TextMate ~/Desktop/textmate-prefs-backup.plist
```

- [ ] **Step 5: Update the documentation**

`CHANGELOG.md` gets an entry under a new version heading. `HANDOFF.md`'s Phase 6 table changes the onboarding row from designed to done. `CLAUDE.md` gains a short Setup Assistant subsection recording that the bridging header must stay narrow and why `SetupAssistantCore` exists as a separate library target. `STREAM.md` gets its newest-first entry.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(setup): show the Setup Assistant at first launch

Replaces FirstLaunchBundleInstaller's modal at the same call site, so bundles
are still installed before any document restores and nothing re-parses. The
installer class keeps its selection logic and loses only its window.

Gated on a new key, so everyone updating sees it once -- deliberately. Existing
users are exactly the people affected by theme living in View -> Theme and
nowhere else."
```

- [ ] **Step 7: Confirm CI is green before considering the phase item done**

This is the first target in the repository carrying both `.swift` and `.mm` through a clean build, and a clean CI build is part of the definition of done rather than an afterthought — local builds are incremental and can hide a missing source or resource.

Run: `gh run list --repo sdenike/textmate --limit 3`
Expected: the branch's build and test jobs both `success`.

---

## Notes for whoever executes this

**The two risks the spec names and nothing has yet retired.** First, SwiftUI initialising inside a modal session before session restore is something this app has never done; if launch hangs or the window never appears, that is where to look, and Task 4 deliberately proves the modal session with an empty window before SwiftUI is involved. Second, this is the first target carrying both `.swift` and `.mm` — Task 1 exists to fail fast on that rather than at the end.

**Do not verify resource or bundle correctness with a threshold.** If a step ever needs to check that files shipped, compare the sets. `bin/verify_resources.sh` already does this at build time, and the glob it guards has been wrong three times.

**`assemble_resources.sh` copies but never deletes.** If a build seems to still contain something removed, delete the target directory and rebuild before concluding anything about size or presence.
