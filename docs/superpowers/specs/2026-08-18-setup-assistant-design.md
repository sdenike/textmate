# Setup Assistant — design

Date: 2026-08-18
Status: approved, not yet implemented
Phase: 6 (SwiftUI islands) — the first island

## Why

Two decisions that shape how TextMate looks and behaves are effectively undiscoverable, and one
first-launch flow already exists but only covers a third of what a new user needs.

Theme and appearance live in `View → Theme` and nowhere else (`AppController Menus.mm:98-111`).
There is no Settings pane for them. On 2026-08-18 this produced a support question that looked like
lost settings and was actually the untouched default: `universalThemeUUID` sitting at
`kMacClassicThemeUUID`, which `AppController Menus.mm:67-70` registers as the factory default. A
user with no way to find the theme menu has no way to tell a default from a fault.

Meanwhile `FirstLaunchBundleInstaller` already runs a modal at `applicationDidFinishLaunching:`
(`AppController.mm:592`) offering the default-tier bundles. It works. It is also the only thing a
new user is asked, which makes the first-run experience "pick some bundles, then figure out the
rest yourself."

This design replaces that single-purpose modal with a Setup Assistant covering appearance and
bundles, reachable again later from the Help menu.

## What it is

A three-step assistant, shown app-modal:

1. **Welcome** — what this fork is. No decisions. Its functional job is to make *Skip Setup*
   visible before anything else happens.
2. **Appearance** — appearance mode and theme, with a live mockup.
3. **Bundles** — the existing default-tier bundle list.

It is the first Swift and SwiftUI code in this repository.

## Scope

**In scope.** Appearance and theme selection; bundle selection; the Help menu entry point; the
gating that decides who sees it and when.

**Out of scope, deliberately.**

- **The `mate` command-line tool.** It already installs from Settings → Terminal
  (`TerminalPreferences.mm:265-288`). Putting a second path to the same privileged write in the
  assistant would mean extracting `install_mate()` from its file-static scope, duplicating the
  authentication flow, and proving that a system auth dialog behaves correctly over an app-modal
  window. Considered and cut: the discoverability gain did not justify a second route to a
  privileged filesystem write, and it keeps the first Swift island small.
- **File-type associations.** `LSSetDefaultRoleHandlerForContentType` appears nowhere in the tree.
  Building that feature for the first time inside the first Swift island would confuse two risks.
  It remains on the maintainer's list as separate work.
- **Preferences, About and the update sheet.** The other three Phase 6 islands. Each has a working
  AppKit implementation to reach parity with; this one does not, which is why it goes first.

## Architecture

### The constraint that decides the shape

Swift interop was proven in this tree on 2026-08-18 by a throwaway spike; the full contract is in
`CLAUDE.md`. Two findings govern this design:

- Swift declarations must be `public`, not merely `@objc`, or they are absent from the generated
  `TextMate-Swift.h` and ObjC++ fails at the call site with `use of undeclared identifier`.
- A bridging header is parsed as C/ObjC and never ObjC++, and is compiled without
  `GCC_PREFIX_HEADER = prelude.mm`. So it cannot include C++, and cannot include this tree's own
  framework headers either — they take their AppKit imports from the prelude.

Everything crossing the boundary is therefore plain Objective-C: `NSString`, `NSArray`, `NSColor`,
`BOOL`, and a small number of purpose-built data classes. No C++ type crosses. No framework header
is reachable from Swift.

### Division of responsibility

ObjC++ owns the window and every side effect. Swift owns presentation and local view state only.

- `SetupAssistantWindowController` (ObjC++) creates the `NSWindow`, hosts the SwiftUI content in an
  `NSHostingView`, runs the modal session, and implements `TMSetupAssistantHost`. It is a singleton,
  following the pattern `AboutWindowController` and `Preferences` already use
  (`AppController.mm:656,693`).
- `SetupAssistantView` (Swift, SwiftUI) renders the three steps and holds which step is current and
  what is currently checked or selected. It performs no installation, writes no defaults, and reads
  nothing from disk.

This keeps the bridging header narrow and stable, and leaves bundle installation — the one genuinely
risky operation — in the ObjC++ code that already performs it correctly today.

### Rejected alternatives

**Swift owns the window and the view model, ObjC++ reduced to services.** Rejected because it makes
the boundary *wider*, not narrower: every piece of data Swift needs must still be marshalled through
plain ObjC, and the modal session and responder chain end up driven from Swift, which is exactly
what the phase gate is sensitive to.

**Swift purely presentational, ObjC++ owns all state.** Rejected as the recommended design with its
ergonomics removed. SwiftUI's value is local state; routing every checkbox toggle across the
boundary buys nothing.

**Replace `FirstLaunchBundleInstaller` outright.** Rejected. It already knows which bundles are
default-tier and uninstalled, already installs them, and already maintains the never-suggest list.
Deleting working installation code to write new installation code is risk with no payoff. Its
*window* is retired; the class remains as the engine behind the bundles step.

## Files

| File | Status | Role |
|---|---|---|
| `Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.{h,mm}` | new | Pure ObjC boundary types and the pure rules that operate on them. Compiled into `SetupAssistantCore`. |
| `Applications/TextMate/src/SetupAssistant/SetupAssistantGating.{h,mm}` | new | Free functions deciding whether the assistant runs. Compiled into `SetupAssistantCore`. |
| `Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.{h,mm}` | new | ObjC++ host: window, modal session, `TMSetupAssistantHost` implementation, and all C++ extraction. App target only. |
| `Applications/TextMate/src/SetupAssistant/SetupAssistantView.swift` | new | SwiftUI content, all types `public` |
| `Applications/TextMate/src/TextMate-Bridging-Header.h` | new | Pure ObjC. `#import <Cocoa/Cocoa.h>`, the host protocol, the data classes. Nothing else, ever. |
| `Applications/TextMate/src/AppController.mm` | edit | Help menu item at `:408`, `showSetupAssistant:` action, and the `:592` call site |
| `Applications/TextMate/src/FirstLaunchBundleInstaller.{h,mm}` | edit | Window retired; list-building and installation exposed for the assistant |
| `Applications/TextMate/tests/t_setup_assistant.mm` | new | Gating predicate and marshalling tests |
| `project.yml` | edit | `.swift` source path, `SWIFT_OBJC_BRIDGING_HEADER`, and the new `SetupAssistantCore` target |

### Why there is a separate library target

`TextMate_test` compiles only the generated runner and links only the libraries it declares, so
anything it exercises must live in a target both binaries link. `PreferencesMigration` is the
existing precedent: `type: library.static`, one `.mm`, listed as a dependency of both `TextMate`
and `TextMate_test`.

`SetupAssistantCore` follows it, and holds exactly the code that is testable without C++: the
boundary types, the gating predicate, the semantic-class-to-appearance mapping, and the
never-suggest merge. Everything requiring the C++ `theme` and `bundles` frameworks stays in
`SetupAssistantWindowController` in the app target and is verified by hand.

This split is what makes this document's own testing section achievable rather than aspirational.
It also forces the API shape predicted below — free functions and class methods taking their inputs
explicitly — for a second, independent reason: `TMThemeChoice` carries `NSColor`, so `TextMate_test`
gains `AppKit.framework` alongside the `Foundation.framework` it previously linked alone.

## The boundary contract

Declared in `TextMate-Bridging-Header.h`, in plain Objective-C only.

```objc
#import <Cocoa/Cocoa.h>

@interface TMBundleChoice : NSObject
@property (nonatomic, copy)   NSString* name;
@property (nonatomic, copy)   NSString* identifier;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, assign) BOOL recommended;
@end

@interface TMThemeChoice : NSObject
@property (nonatomic, copy) NSString* name;
@property (nonatomic, copy) NSString* identifier;
@property (nonatomic, copy) NSString* appearance;              // @"light", @"dark", @"unspecified"
@property (nonatomic, copy) NSDictionary<NSString*, NSColor*>* colors;
@end

@protocol TMSetupAssistantHost <NSObject>
- (NSArray<TMBundleChoice*>*)availableBundles;
- (NSArray<TMThemeChoice*>*)availableThemes;
- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance;
- (NSString*)currentAppearance;                                 // @"light", @"dark", nil = auto
- (void)installBundles:(NSArray<NSString*>*)identifiers neverSuggest:(NSArray<NSString*>*)skipped;
- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance;
- (void)finishWithSkip:(BOOL)skipped;
@end
```

The `colors` dictionary carries nine roles, extracted on the ObjC++ side where the C++ `theme`
framework is reachable: `background`, `foreground`, `selection`, `caret`, `comment`, `string`,
`keyword`, `constant.numeric`, `entity.name.function`.

Twenty-two themes were installed on the maintainer's profile when this was measured
(2026-08-18); that is one machine, not a guaranteed floor. All colors for all themes are marshalled
once when the assistant opens. Theme selection then updates the mockup from SwiftUI state alone, with no
round trip across the boundary. If the installed theme count ever grows by an order of magnitude,
revisit this; at twenty-two it is roughly two hundred `NSColor` objects and not worth deferring.

## The steps

### 1. Welcome

Static copy describing the fork. Continue, and a *Skip Setup* control that is visible without
scrolling or hovering. Skip is not a hidden affordance — an assistant that appears after an update
must be dismissible in one obvious action.

### 2. Appearance

Two controls and a preview.

Appearance mode writes `themeAppearance`: `light`, `dark`, or absent for automatic. Theme selection
writes `universalThemeUUID` for the light theme and `darkModeThemeUUID` for the dark one — the same
keys `takeUniversalThemeUUIDFrom:` and `takeDarkThemeUUIDFrom:` already write
(`AppController Menus.mm:103-111`). In automatic mode both are editable, because both are used.

The preview is a **mockup, not a live editor**: a short fixed code sample drawn in SwiftUI using the
marshalled colors. A real preview would require the C++ `theme` and `layout` frameworks, which
cannot cross the bridge. The mockup updates instantly on selection because the colors are already
in Swift.

### 3. Bundles

The default-tier bundle list from `FirstLaunchBundleInstaller`, recommended entries pre-checked,
already-installed entries shown as installed and not selectable.

On finish, checked bundles install and unchecked ones are recorded in
`kUserDefaultsBundlesToNeverSuggestKey` — the same behaviour the current modal has, and load-bearing
because `DocumentWindowController.mm:1231,1273-1274` reads that list for the on-demand
per-extension bundle prompt. That prompt must keep working unchanged after the first-launch modal
is gone.

## Entry points and gating

One controller, two entry points, one code path.

**First launch.** Called from `applicationDidFinishLaunching:` at `AppController.mm:592`, the site
that calls `promptIfNeeded` today, and therefore before session restore. Running before restore is
deliberate: bundles determine syntax highlighting, and installing them after documents are open
forces a re-parse.

**`Help → Setup Assistant…`.** Added to the Help menu at `AppController.mm:408-412`, which is built
in code through MenuBuilder rather than in a xib. The action follows the established pattern:

```objc
- (IBAction)showSetupAssistant:(id)sender
{
    [SetupAssistantWindowController.sharedInstance showWindow:self];
}
```

This entry point ignores the gate entirely.

**The gate** is a new `kUserDefaultsDidRunSetupAssistantKey`. Because it is new, every existing user
sees the assistant once after updating — which is intended, since existing users are precisely the
people affected by the theme discoverability problem. Both Skip and completing the last step set it.

A version-numbered gate was considered, so a future release could re-run the assistant after adding
a step. Rejected as speculative: the Help entry already covers "show me that again."

**`kUserDefaultsDidPromptForDefaultBundlesKey` is left alone.** It continues to mean what it has
always meant.

### Consequence worth stating plainly

Because the assistant reachable from Help must work when nothing is fresh, it is not a first-run
wizard that happens to be re-runnable. It is a Setup Assistant that happens to run at first launch.
Every step reflects current state on every run: installed bundles show as installed, the current
theme is preselected, and nothing is written that the user did not confirm on this run.

## Verification

The design spec's Phase 6 gate reads *"visual parity pass, no regressions in the responder chain or
key equivalents."* The parity half is vacuous for this island — there is no predecessor to be at
parity with. It is replaced by the following.

### Automated — `Applications/TextMate/tests/t_setup_assistant.mm`

- the gating predicate: set and unset, and that the Help entry point bypasses it
- marshalling: a known set of bundles and themes produces the expected `TMBundleChoice` and
  `TMThemeChoice` values, including that every theme yields all nine color roles

`gen_test.sh:29-31` falls back from `Frameworks/<name>` to `vendor/<name>` to
`Applications/<name>`, so a file at `Applications/TextMate/tests/` is globbed into the runner —
verified, because a runner that silently skipped it would report green without running anything.

Both must be exposed as class methods taking their inputs explicitly, because `bin/gen_test` wraps
every test file in `namespace <filename> { … }` and Objective-C forbids declaring a class inside a
namespace. **No mock host object can exist in the test file.** This constrains the API and is
designed for rather than discovered.

If these tests touch AppKit on a background thread, `TextMate_test` may need adding to the
`--no-parallel` list in `bin/build` and CI, alongside the eight targets already there.

### Manual — requires the maintainer

GUI gestures cannot be synthesised in the agent sandbox; two previous agents lost time trying.

- a fresh profile shows the assistant before any document window restores
- ESC skips, and the assistant does not reappear on the next launch
- `Help → Setup Assistant…` reopens it with current state reflected, not a blank wizard
- a theme chosen in the assistant is actually applied to an open document
- bundles checked in the assistant are installed; bundles left unchecked do not re-prompt

## Risks

**The first Swift file in the project.** The toolchain question is settled, but this is still the
first target to carry both `.swift` and `.mm` sources through a full clean build and CI. A clean CI
build is part of the definition of done, not an afterthought.

**Retiring a working modal.** `FirstLaunchBundleInstaller`'s window goes away while its installation
logic stays. The risk is in the seam, not the logic, and the never-suggest list is the specific
thing to watch: `DocumentWindowController` depends on it.

**Modal before session restore.** Running a modal window this early in
`applicationDidFinishLaunching:` is what the current bundle installer already does, so the pattern
is proven — but the assistant is a larger window with SwiftUI content, and SwiftUI's first
initialisation happening inside a modal session before restore is not something this app has done
before.
