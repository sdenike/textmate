# Liquid Glass Increment 4 — Chrome Bars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the four always-visible chrome bars — the editor status bar, the HTML output status bar, and the file browser's header and actions bar — off `NSVisualEffectView` and onto `NSGlassEffectView`, so the surfaces the maintainer looks at every second read as macOS 26.

**Architecture:** All four *subclass* `NSVisualEffectView` and add their controls directly to themselves, so there is no contained effect view to swap. Each becomes a plain `NSView` hosting one `NSGlassEffectView` pinned to its bounds, whose `contentView` is a holder view carrying every existing control unchanged. This is the shape increment 2 arrived at independently, for the same reason: the SDK guarantees placement only for `contentView`.

**Tech Stack:** Objective-C++, AppKit (macOS 26.5 SDK), the `OakAppKit_test` runner and the live-window snapshot harness built in increment 2.

**Spec:** `docs/superpowers/specs/2026-08-14-liquid-glass-design.md`

## Global Constraints

- **Deployment target is macOS 26.0.** Never write `@available(macOS 26, *)` guards or `NSVisualEffectView` fallbacks — every branch would be dead code.
- **arm64 only.** No x86_64 fallbacks.
- **Build with `bin/build`, never bare `xcodebuild`.** It sanitises leaked `GEM_HOME`/`GEM_PATH`, which otherwise break the Ruby build phases with a misleading `Symbol not found: _rb_cArray`.
- **`bin/build` never prints a pass count.** It execs the runner without `-v` and the runner is silent on success. Counts come from `~/build/textmate-revived/xcode/Release/<name>_test -v --no-parallel`. Silence is not evidence that tests did not run.
- **Never run `bin/deploy-local`.**
- **Never use `OAK_ASSERT_EQ` on an Objective-C object pointer** — it resolves to a generic `to_s` that range-fors the pointer, and a *failing* assertion then aborts with SIGABRT instead of naming the test. Use `OAK_ASSERT(a == b)` / `OAK_ASSERT([a isEqual:b])`.
- **A test file cannot declare an Objective-C class.** `bin/gen_test` wraps each file in `namespace <filename> { … }` and ObjC forbids `@interface`/`@implementation` inside a C++ namespace.
- **A `to_s` overload in one test file is invisible to its siblings** — each is in its own namespace. Symptom: `no viable 'begin' function`.
- **Do not touch `CHANGELOG.md`** until the release task. Pushing it to master triggers the release workflow.

## Facts established by survey — do not re-derive

| Class | Header | Currently |
|---|---|---|
| `OTVStatusBar` | `OTVStatusBar.h:6` | `: NSVisualEffectView`, Titlebar / WithinWindow / FollowsWindowActiveState |
| `HOStatusBar` | `HOStatusBar.h:6` | same, plus `wantsLayer = YES` |
| `OFBHeaderView` | `OFBHeaderView.h:3` | `: NSVisualEffectView`, Titlebar / WithinWindow / `wantsLayer` |
| `OFBActionsView` | `OFBActionsView.h:1` | same four as `HOStatusBar` |

- None of the four overrides `drawRect:`, defines `isOpaque`, or declares an `intrinsicContentSize`. All four lay out with Auto Layout via `OakAddAutoLayoutViewsToSuperview(views, self)`.
- **No consumer depends on the `NSVisualEffectView` superclass.** A grep for `.material` / `.blendingMode` / `.state` / `.maskImage` on `statusBar`, `headerView` and `actionsView` across `Frameworks/` and `Applications/` returns nothing.
- **`NSVisualEffectMaterialTitlebar` does not silently become Liquid Glass on macOS 26.** Verified by screenshotting the running app built against the macOS 26 SDK; the status bar renders flat and opaque.
- **`OFBHeaderView` and `OFBActionsView` are not adjacent** — `FileBrowserView.mm:63-65` puts the header at the top and the actions bar at the bottom with the whole file list between them. No container, no `spacing`.
- **The file list scrolls underneath the header.** `FileBrowserView.mm:68` adds `_headerView.fittingSize.height` to the scroll view's top content inset, and `:59` raises the header above it. **The header's `fittingSize` is load-bearing.**

From increment 2, all measured against real AppKit:

- Assigning a view to `contentView` makes AppKit pin it to fill the glass. **Do not add your own glass↔content constraints.** The content's intrinsic size then propagates up and can override the host's — this is what silently shrank `OakKeyEquivalentView` from 22 points to 16.
- `contentView.superview` is a private `ContentHolderView`, not the glass view.
- `glassView.subviews` always contains 2 internal views. Never index into it.
- `cacheDisplayInRect:` captures the glass material but **not** its `contentView`. Assertions run offscreen; review images come from `CaptureLiveWindow`.

## File Structure

| File | Change |
|---|---|
| `Frameworks/OakAppKit/src/OakUIConstructionFunctions.{h,mm}` | New `OakWrapInGlass(NSView* bar, NSGlassEffectViewStyle style)` — the shared restructure, written once instead of four times |
| `Frameworks/OakTextView/src/OTVStatusBar.{h,mm}` | Superclass → `NSView`; adopt the helper |
| `Frameworks/HTMLOutput/src/browser/HOStatusBar.{h,mm}` | Same |
| `Frameworks/FileBrowser/src/OFB/OFBHeaderView.{h,mm}` | Same |
| `Frameworks/FileBrowser/src/OFB/OFBActionsView.{h,mm}` | Same |
| `Frameworks/OakAppKit/tests/t_glass_wrap.mm` | New — tests for the helper |
| `Frameworks/OakAppKit/tests/t_glass_snapshot.mm` | Extend — render a representative bar |

---

### Task 1: `OakWrapInGlass`

Four identical restructures written four times is four chances to differ. Write it once.

**Files:**
- Modify: `Frameworks/OakAppKit/src/OakUIConstructionFunctions.{h,mm}`
- Create: `Frameworks/OakAppKit/tests/t_glass_wrap.mm`

**Interfaces:**
- Consumes: `OakCreateGlassBackground`, `OakAddAutoLayoutViewsToSuperview`.
- Produces: `NSView* OakWrapInGlass (NSView* bar, NSGlassEffectViewStyle style);` — returns the holder that callers should add their controls to.

- [ ] **Step 1: Write the failing tests**

Create `Frameworks/OakAppKit/tests/t_glass_wrap.mm`:

```objc
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <oak/oak.h>

void test_wrap_in_glass_returns_a_holder_inside_the_glass ()
{
	NSView* bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
	NSView* holder = OakWrapInGlass(bar, NSGlassEffectViewStyleRegular);

	OAK_ASSERT(holder != nil);
	OAK_ASSERT(bar.subviews.count == 1);
	OAK_ASSERT([bar.subviews.firstObject isKindOfClass:[NSGlassEffectView class]]);

	NSGlassEffectView* glass = (NSGlassEffectView*)bar.subviews.firstObject;
	OAK_ASSERT(glass.contentView == holder);
}

void test_wrap_in_glass_does_not_constrain_the_holder ()
{
	// Assigning contentView makes AppKit pin the holder to fill the glass.
	// Adding our own constraints on top conflicts with those, so the helper
	// must not install any between the glass and the holder.
	NSView* bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
	NSView* holder = OakWrapInGlass(bar, NSGlassEffectViewStyleRegular);
	OAK_ASSERT_EQ(holder.constraints.count, 0);
}

void test_wrap_in_glass_keeps_the_bar_sized_by_its_content ()
{
	// The hazard from increment 2: content inside glass propagates its size up
	// through the glass to the host. A bar whose holder wants 300x24 must end up
	// 300x24, not collapsed and not stretched.
	NSView* bar = [[NSView alloc] initWithFrame:NSZeroRect];
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	NSView* holder = OakWrapInGlass(bar, NSGlassEffectViewStyleRegular);

	NSView* content = [[NSView alloc] initWithFrame:NSZeroRect];
	content.translatesAutoresizingMaskIntoConstraints = NO;
	[content.widthAnchor constraintEqualToConstant:300].active  = YES;
	[content.heightAnchor constraintEqualToConstant:24].active  = YES;
	OakAddAutoLayoutViewsToSuperview(@[ content ], holder);
	[content.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor].active   = YES;
	[content.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor].active = YES;
	[content.topAnchor constraintEqualToAnchor:holder.topAnchor].active           = YES;
	[content.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor].active     = YES;

	OAK_ASSERT_EQ(bar.fittingSize.width, 300);
	OAK_ASSERT_EQ(bar.fittingSize.height, 24);
}
```

- [ ] **Step 2: Run to verify they fail**

```sh
bin/build OakAppKit/test
```

Expected: FAIL to compile — `use of undeclared identifier 'OakWrapInGlass'`.

- [ ] **Step 3: Declare it**

Append to `Frameworks/OakAppKit/src/OakUIConstructionFunctions.h`, after the glass constructors:

```objc
// Restructures `bar` to draw its background with glass, and returns the view its
// controls should be added to.
//
// NSGlassEffectView hosts content through contentView and guarantees placement
// only for that view -- the SDK header is explicit that "arbitrary subviews
// aren't guaranteed specific behavior with regard to z-order in relation to the
// content view or glass effect". So a bar cannot simply gain a glass subview and
// keep adding controls to itself; the controls move into a holder that becomes
// the glass's contentView.
//
// Add controls to the RETURNED view, never to `bar` itself.
NSView* OakWrapInGlass (NSView* bar, NSGlassEffectViewStyle style);
```

- [ ] **Step 4: Implement it**

Append to `Frameworks/OakAppKit/src/OakUIConstructionFunctions.mm`:

```objc
NSView* OakWrapInGlass (NSView* bar, NSGlassEffectViewStyle style)
{
	NSGlassEffectView* glass = OakCreateGlassBackground(style);

	NSView* holder = [[NSView alloc] initWithFrame:NSZeroRect];
	holder.translatesAutoresizingMaskIntoConstraints = NO;
	glass.contentView = holder;

	OakAddAutoLayoutViewsToSuperview(@[ glass ], bar);
	[glass.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active   = YES;
	[glass.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	[glass.topAnchor constraintEqualToAnchor:bar.topAnchor].active           = YES;
	[glass.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor].active     = YES;

	return holder;
}
```

Do **not** add constraints between `glass` and `holder`. Assigning `contentView` installs them.

- [ ] **Step 5: Run to verify they pass**

```sh
bin/build OakAppKit/test
~/build/textmate-revived/xcode/Release/OakAppKit_test -v --no-parallel
```

Expected: `OakAppKit_test: 24 tests passed` (21 before, 3 added here).

- [ ] **Step 6: Commit**

```bash
git add Frameworks/OakAppKit/src/OakUIConstructionFunctions.h Frameworks/OakAppKit/src/OakUIConstructionFunctions.mm Frameworks/OakAppKit/tests/t_glass_wrap.mm
git commit -m "feat(OakAppKit): add OakWrapInGlass

Four chrome bars each subclass NSVisualEffectView and add their controls to
themselves. NSGlassEffectView guarantees placement only for contentView, so each
needs the same restructure -- glass pinned to the bar, controls in a holder that
becomes the glass's contentView. Written once here rather than four times."
```

---

### Task 2: `OTVStatusBar` — the probe

The editor status bar is on every editor window, which makes it both the most valuable target and the right one to prove the shape on before touching the other three.

**Files:**
- Modify: `Frameworks/OakTextView/src/OTVStatusBar.h` (superclass), `Frameworks/OakTextView/src/OTVStatusBar.mm`

**Interfaces:**
- Consumes: `OakWrapInGlass` from Task 1.
- Produces: nothing new. `OakDocumentView.mm:89` and `:151` construct it and are untouched.

- [ ] **Step 1: Change the superclass**

`Frameworks/OakTextView/src/OTVStatusBar.h:6` — change `NSVisualEffectView` to `NSView`.

Check the file's imports: if it imports `<Cocoa/Cocoa.h>` or `<AppKit/AppKit.h>` nothing more is needed. It must be able to see `NSGlassEffectViewStyle` only if the header mentions it — it should not.

- [ ] **Step 2: Replace the effect configuration with the wrap**

In `Frameworks/OakTextView/src/OTVStatusBar.mm`, delete the three lines at `:76-78`:

```objc
	self.material     = NSVisualEffectMaterialTitlebar;
	self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
	self.state        = NSVisualEffectStateFollowsWindowActiveState;
```

Then change `:135` from adding the controls to `self`:

```objc
	OakAddAutoLayoutViewsToSuperview([views allValues], self);
```

to adding them to the holder. Introduce the holder just before it:

```objc
	// Controls go inside the glass, not on the bar -- NSGlassEffectView
	// guarantees placement only for its contentView.
	NSView* contentHolder = OakWrapInGlass(self, NSGlassEffectViewStyleRegular);
	OakAddAutoLayoutViewsToSuperview([views allValues], contentHolder);
```

**The constraint block that follows (`:147-156`) must now be installed on `contentHolder`, not on `self`.** Every `[self addConstraints:…]` in that block becomes `[contentHolder addConstraints:…]`. If any constraint in it references `self` as a layout item rather than a container, report it rather than guessing — that would mean a control is pinned to the bar across the glass boundary, which will not work.

- [ ] **Step 3: Build and run the suite**

```sh
bin/build OakAppKit/test
~/build/textmate-revived/xcode/Release/OakAppKit_test -v --no-parallel
bin/build
```

Expected: 24 tests still passing, and `** BUILD SUCCEEDED **` for the app.

- [ ] **Step 4: Look at it in the running application**

```sh
open -n ~/build/textmate-revived/xcode/Release/TextMate.app
```

Open any file. The status bar runs along the bottom: line/column, language popup, tab size, bundle-item popup. Confirm every control is present, correctly positioned, and clickable, and that the bar has not changed height. Then quit.

**If any control is missing or misplaced, stop and report** — that means the constraint move in Step 2 was incomplete, and guessing at it will cost more than asking.

- [ ] **Step 5: Commit**

```bash
git add Frameworks/OakTextView/src/OTVStatusBar.h Frameworks/OakTextView/src/OTVStatusBar.mm
git commit -m "feat(OakTextView): put the editor status bar on glass"
```

---

### Task 3: The remaining three bars

Same restructure, three times. Batched deliberately: the shape is proven by Task 2, and each is a small mechanical edit of the same kind.

**Files:**
- Modify: `Frameworks/HTMLOutput/src/browser/HOStatusBar.{h,mm}`
- Modify: `Frameworks/FileBrowser/src/OFB/OFBHeaderView.{h,mm}`
- Modify: `Frameworks/FileBrowser/src/OFB/OFBActionsView.{h,mm}`

**Interfaces:**
- Consumes: `OakWrapInGlass`, and the pattern established by Task 2.
- Produces: nothing new. `HOBrowserView.mm:31`, `FileBrowserView.mm:19` and `:20` are untouched.

- [ ] **Step 1: Apply the Task 2 treatment to each**

For each of the three: superclass → `NSView`; delete the `material`/`blendingMode`/`state`/`wantsLayer` lines; insert `OakWrapInGlass(self, NSGlassEffectViewStyleRegular)`; add the controls to the returned holder; move that class's constraint installation onto the holder.

Their current effect-configuration and layout lines:

| Class | Effect config | Adds controls at | Constraints at |
|---|---|---|---|
| `HOStatusBar` | `:44-47` | `:83` | `:90-127` (`updateConstraints`) |
| `OFBHeaderView` | `:34-36` | `:58` | `:61-63` |
| `OFBActionsView` | `:21-24` | `:63` | `:66-68` |

`HOStatusBar` is the one to take care with: its constraints are rebuilt dynamically in `updateConstraints`, so the holder must be reachable from that method — store it in an instance variable rather than a local.

- [ ] **Step 2: Guard the file browser header's height**

The file list scrolls underneath the header: `FileBrowserView.mm:68` adds `_headerView.fittingSize.height` to the scroll view's top content inset. If the wrap changes that height, the list's content shifts.

Add to `Frameworks/OakAppKit/tests/t_glass_wrap.mm`:

```objc
void test_wrap_in_glass_preserves_fitting_height ()
{
	// FileBrowserView adds the header's fittingSize.height to the file list's
	// top content inset, so a bar that changes height when wrapped silently
	// shifts the list. Wrapping must be height-neutral.
	NSView* plain = [[NSView alloc] initWithFrame:NSZeroRect];
	plain.translatesAutoresizingMaskIntoConstraints = NO;
	NSView* plainContent = [[NSView alloc] initWithFrame:NSZeroRect];
	plainContent.translatesAutoresizingMaskIntoConstraints = NO;
	[plainContent.heightAnchor constraintEqualToConstant:24].active = YES;
	OakAddAutoLayoutViewsToSuperview(@[ plainContent ], plain);
	[plainContent.topAnchor constraintEqualToAnchor:plain.topAnchor].active       = YES;
	[plainContent.bottomAnchor constraintEqualToAnchor:plain.bottomAnchor].active = YES;

	NSView* wrapped = [[NSView alloc] initWithFrame:NSZeroRect];
	wrapped.translatesAutoresizingMaskIntoConstraints = NO;
	NSView* holder = OakWrapInGlass(wrapped, NSGlassEffectViewStyleRegular);
	NSView* wrappedContent = [[NSView alloc] initWithFrame:NSZeroRect];
	wrappedContent.translatesAutoresizingMaskIntoConstraints = NO;
	[wrappedContent.heightAnchor constraintEqualToConstant:24].active = YES;
	OakAddAutoLayoutViewsToSuperview(@[ wrappedContent ], holder);
	[wrappedContent.topAnchor constraintEqualToAnchor:holder.topAnchor].active       = YES;
	[wrappedContent.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor].active = YES;

	OAK_ASSERT_EQ(wrapped.fittingSize.height, plain.fittingSize.height);
}
```

- [ ] **Step 3: Build and run**

```sh
bin/build OakAppKit/test
~/build/textmate-revived/xcode/Release/OakAppKit_test -v --no-parallel
bin/build
```

Expected: `OakAppKit_test: 25 tests passed`, and the app builds.

- [ ] **Step 4: Look at all three in the running application**

Launch the app. Check each surface:

- **File browser header and actions bar** — open a project folder (⌘O on a directory, or use an existing project window). The header carries the folder popup and its two buttons; the actions bar along the bottom carries five buttons and a popup. Scroll the file list and confirm rows pass *underneath* the header rather than being clipped at it.
- **HTML output status bar** — run any bundle command that produces HTML output (⌘R in a document with a Run command, or Bundles → … → anything producing output). Its status bar carries two buttons, a text field and two progress indicators.

Confirm no control is missing, no bar changed height, and the file list's top inset still clears the header.

- [ ] **Step 5: Commit**

```bash
git add Frameworks/HTMLOutput/src/browser/HOStatusBar.h Frameworks/HTMLOutput/src/browser/HOStatusBar.mm Frameworks/FileBrowser/src/OFB/OFBHeaderView.h Frameworks/FileBrowser/src/OFB/OFBHeaderView.mm Frameworks/FileBrowser/src/OFB/OFBActionsView.h Frameworks/FileBrowser/src/OFB/OFBActionsView.mm Frameworks/OakAppKit/tests/t_glass_wrap.mm
git commit -m "feat: put the remaining chrome bars on glass"
```

---

### Task 4: Verify and render

**Files:**
- Modify: `Frameworks/OakAppKit/tests/t_glass_snapshot.mm`

- [ ] **Step 1: Render a representative bar**

Add a render to `t_glass_snapshot.mm` following the existing
`test_key_equivalent_view_renders_in_both_appearances` pattern — a plain `NSView` wrapped with
`OakWrapInGlass`, holding a label and a button so the glass has real content, captured in both
appearances via `CaptureLiveWindow` when `OAK_SNAPSHOT_DIR` is set.

Do not try to render `OTVStatusBar` itself: it lives in `OakTextView`, which `OakAppKit_test` does
not link.

- [ ] **Step 2: Full suite against the parity document**

Run every target in `docs/benchmarks/2026-08-12-ninja-parity.md` and compare. The four known-bad must
reproduce identically and no others may fail: `scm` 2 of 84, `buffer` 3 of 26, `file` 1 of 11, `cf`
SIGBUS 138. `command_test` is separately known to hang intermittently — treat a hang there as noise
and say so.

- [ ] **Step 3: Capture the before/after**

The maintainer has a "before" screenshot of the flat status bar. Produce the matching "after" from
the running app, at the same window size, so the change is judged as a pair rather than described.

---

### Task 5: Ship

**Gated on Task 4 and on the maintainer seeing the screenshots.**

- [ ] **Step 1** — update `OakAppKit_test`'s count in the parity document.
- [ ] **Step 2** — STREAM.md entry: what changed, that the four bars are now glass, and that increment 3 (overlays) and 5-6 (choosers, window chrome, tab bar) remain.
- [ ] **Step 3** — `CHANGELOG.md` entry for v3.0.0-revived.21, commit, push, watch the release through to the cask bump, and verify the published asset's SHA256 against the cask.

---

## What this plan deliberately does not cover

**Increment 3 (overlays: `OTVHUD`, `OakToolTip`, `OakChoiceMenu`)** is deferred behind this one. The
spec ordered it earlier so glass could be learned cheaply on a transient surface; increment 2
delivered that learning on a control that exercised more edge cases than a tooltip would have.

**Increments 5 and 6** — choosers and window chrome, then the tab bar. The survey found the remaining
`NSVisualEffectView` sites they cover: `OakChooser.mm:287`, `OakPasteboardChooser.mm:336`,
`BundlesPreferences.mm:376` (all three a `footerView`), plus `OakToolTip.mm:54`,
`OakChoiceMenu.mm:56` and `OakBackgroundFillView.mm:225` which belong to increment 3.
