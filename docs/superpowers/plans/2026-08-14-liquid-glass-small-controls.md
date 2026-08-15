# Liquid Glass Increment 2 — Small Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `OakKeyEquivalentView` — the key-equivalent recorder in the Bundle Item Chooser — draw its background with `NSGlassEffectView` instead of a hand-drawn border and fill, and prove the result with offscreen renders in both appearances.

**Architecture:** The control currently paints everything itself in `drawRect:`: a one-pixel border, an inset background fill, and its centred display string. Because a view's own `drawRect:` paints *beneath* its subviews, glass cannot simply be slipped in behind that drawing — it would cover the text. So the text moves into the glass view's `contentView` as an `NSTextField`, `drawRect:` is deleted outright, and the existing clear button stays a sibling above the glass. Verification is a new offscreen-render test that forces `NSApp.appearance` and captures the view to a bitmap, which was measured to reproduce live glass rendering faithfully.

**Tech Stack:** Objective-C++, AppKit (macOS 26.5 SDK), the `OakAppKit_test` runner added in the foundation increment.

**Spec:** `docs/superpowers/specs/2026-08-14-liquid-glass-design.md`

## Global Constraints

- **Deployment target is macOS 26.0.** Never write `@available(macOS 26, *)` guards or `NSVisualEffectView` fallbacks — every branch would be dead code.
- **arm64 only.** Do not add x86_64 fallbacks.
- **Build with `bin/build`, never bare `xcodebuild`.** It sanitises leaked `GEM_HOME`/`GEM_PATH` from Ruby version managers, which otherwise break the Ruby build phases with a misleading `Symbol not found: _rb_cArray`.
- **Never run `bin/deploy-local`.** The maintainer runs the signed Homebrew build; deploy-local installs an ad-hoc build that cannot self-update.
- **Never use `OAK_ASSERT_EQ` on an Objective-C object pointer.** There is no `to_s` overload for `NSView*` and friends, so it resolves to the generic `to_s(_T const&)`, which range-fors over the pointer. A *failing* assertion then throws `NSInvalidArgumentException`, which the generated runner does not catch, and the binary aborts with SIGABRT instead of naming the test. Use `OAK_ASSERT(a == b)` or `OAK_ASSERT([a isEqual:b])`. `OAK_ASSERT_EQ` remains correct for numbers, `BOOL` and `std::string`.
- **Tests live at `Frameworks/OakAppKit/tests/t_*.mm`** and contain top-level `void test_*()` functions. `bin/gen_test` wraps each file in `namespace <filename> { … }`.
- **Do not add a `CHANGELOG.md` entry and do not cut a release in this plan.** Pushing `CHANGELOG.md` to master triggers the release workflow, and this increment ships only after the maintainer has reviewed the renders. Releasing is Task 6, gated on that review.

## Verified SDK behaviour this plan depends on

Measured against real AppKit on 2026-08-14, not inferred. Recorded in full in the spec's
"Verified behaviour of `NSGlassEffectView`" section.

- Setting `contentView` installs the fill constraints internally. **Do not add your own
  glass↔content constraints.**
- `contentView.superview` is a private `ContentHolderView`, **not** the glass view.
- A glass view with no `contentView` has a `fittingSize` of `0 × 0`, so a bare glass backdrop
  needs explicit constraints. Here the glass is pinned to the control's bounds, which supplies them.
- `glassView.subviews` always contains 2 internal views, even when bare. Never index into it.
- A view's own `drawRect:` paints beneath its subviews. This is why the text must move.

## File Structure

| File | Responsibility |
|---|---|
| `Frameworks/OakAppKit/src/OakKeyEquivalentView.mm` | The control. Gains a glass background and a display text field; loses `drawRect:`. |
| `Frameworks/OakAppKit/tests/t_key_equivalent_view.mm` | New. Structural tests for the migrated control. |
| `Frameworks/OakAppKit/tests/t_glass_snapshot.mm` | New. Renders the control offscreen in both appearances, asserts glass actually rendered, and writes PNGs when `OAK_SNAPSHOT_DIR` is set. |

`OakKeyEquivalentView.h` does not change — the migration is entirely internal, and
`BundleItemChooser.mm:643` keeps working untouched.

---

### Task 1: Snapshot harness

Build the verification tool first, so the migration can be seen rather than assumed. It renders a
view offscreen with a forced appearance and measures whether glass rendered.

This is a real test, not just a screenshot script: it asserts that the glass region of the render
differs from the same view rendered without glass. That difference was measured at 0.44 mean
absolute RGB (on 0..1) inside the glass rect while the region outside it was bit-identical, so the
signal is enormous and the threshold below is not delicate.

**Files:**
- Create: `Frameworks/OakAppKit/tests/t_glass_snapshot.mm`

**Interfaces:**
- Consumes: `OakCreateGlassBackground` from the foundation increment.
- Produces: two helpers later tasks reuse —
  `NSBitmapImageRep* SnapshotView (NSView* view, NSString* appearanceName)` and
  `void WriteSnapshotIfRequested (NSBitmapImageRep* rep, NSString* name)`.

- [ ] **Step 1: Write the failing test**

Create `Frameworks/OakAppKit/tests/t_glass_snapshot.mm`:

```objc
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <oak/oak.h>

// Renders `view` offscreen with `appearanceName` forced on the application.
//
// NSApp.appearance is the only thing that works here: passing -AppleInterfaceStyle
// on the command line sets the value in NSArgumentDomain (a plain
// stringForKey: lookup does return it) but AppKit derives effectiveAppearance
// from the system setting and ignores it, so the render comes back in whatever
// mode the machine happens to be in. Verified 2026-08-14.
//
// cacheDisplayInRect: does capture live glass: rendering the same view with and
// without a glass subview differs by 0.44 mean absolute RGB inside the glass
// rect, matching what /usr/sbin/screencapture produces for the same window to
// within 0.015. The offscreen path needs no screen-recording permission and no
// visible window, so it is the one to use.
static NSBitmapImageRep* SnapshotView (NSView* view, NSString* appearanceName)
{
	// The generated runner does not create the application object, and setting a
	// property on a nil NSApp is a silent no-op -- the render would come back in
	// whatever appearance the machine is in, and the test would still pass.
	// sharedApplication is idempotent, so calling it here is safe wherever this
	// runs.
	[NSApplication sharedApplication];

	NSAppearance* savedAppearance = NSApp.appearance;
	NSApp.appearance = [NSAppearance appearanceNamed:appearanceName];

	NSSize size = view.fittingSize;
	if(size.width < 1)
		size.width = 200;
	if(size.height < 1)
		size.height = 22;

	NSRect frame = NSMakeRect(0, 0, size.width, size.height);
	NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;

	NSView* host = [[NSView alloc] initWithFrame:frame];
	window.contentView = host;
	OakAddAutoLayoutViewsToSuperview(@[ view ], host);
	[view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor].active   = YES;
	[view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor].active = YES;
	[view.topAnchor constraintEqualToAnchor:host.topAnchor].active           = YES;
	[view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor].active     = YES;

	// The window is never ordered front and no activation policy is set. Glass
	// still renders: the same comparison scores 0.4436 either way, so the
	// harness needs no visible window, no foreground app, and no screen-recording
	// permission. It works under CI.
	[host layoutSubtreeIfNeeded];
	for(NSInteger i = 0; i < 40; ++i)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];

	NSBitmapImageRep* rep = [host bitmapImageRepForCachingDisplayInRect:host.bounds];
	[host cacheDisplayInRect:host.bounds toBitmapImageRep:rep];

	// Restore it: NSApp.appearance is process-wide state and the runner's test
	// order is not guaranteed, so leaving it forced would silently change the
	// appearance any later test renders under.
	NSApp.appearance = savedAppearance;
	return rep;
}

// Writes `rep` as a PNG when OAK_SNAPSHOT_DIR is set, so the same binary that
// tests the control also produces the images the maintainer reviews:
//
//   OAK_SNAPSHOT_DIR=/tmp/shots ~/build/textmate-revived/xcode/Release/OakAppKit_test
//
// Does nothing when the variable is unset, which is the CI case.
static void WriteSnapshotIfRequested (NSBitmapImageRep* rep, NSString* name)
{
	char const* dir = getenv("OAK_SNAPSHOT_DIR");
	if(!dir)
		return;
	NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
	[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{ }] writeToFile:path atomically:YES];
	fprintf(stderr, "wrote %s\n", path.UTF8String);
}

// Mean absolute RGB difference across two same-sized reps, on a 0..1 scale.
static double MeanDifference (NSBitmapImageRep* a, NSBitmapImageRep* b)
{
	OAK_ASSERT_EQ(a.pixelsWide, b.pixelsWide);
	OAK_ASSERT_EQ(a.pixelsHigh, b.pixelsHigh);

	double sum = 0;
	NSInteger n = 0;
	for(NSInteger y = 0; y < a.pixelsHigh; ++y)
	{
		for(NSInteger x = 0; x < a.pixelsWide; ++x)
		{
			NSColor* ca = [a colorAtX:x y:y];
			NSColor* cb = [b colorAtX:x y:y];
			sum += fabs(ca.redComponent - cb.redComponent) + fabs(ca.greenComponent - cb.greenComponent) + fabs(ca.blueComponent - cb.blueComponent);
			n += 3;
		}
	}
	return n ? sum / n : 0;
}

void test_snapshot_captures_live_glass ()
{
	// Two identical hosts, one with a glass subview. If cacheDisplayInRect: did
	// not capture glass, these would render identically and every screenshot
	// this harness produces would be worthless.
	NSView* plain = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
	plain.translatesAutoresizingMaskIntoConstraints = NO;
	[plain.widthAnchor constraintEqualToConstant:200].active  = YES;
	[plain.heightAnchor constraintEqualToConstant:40].active  = YES;

	NSView* glassy = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 40)];
	glassy.translatesAutoresizingMaskIntoConstraints = NO;
	[glassy.widthAnchor constraintEqualToConstant:200].active  = YES;
	[glassy.heightAnchor constraintEqualToConstant:40].active  = YES;
	NSGlassEffectView* glass = OakCreateGlassBackground(NSGlassEffectViewStyleRegular);
	OakAddAutoLayoutViewsToSuperview(@[ glass ], glassy);
	[glass.leadingAnchor constraintEqualToAnchor:glassy.leadingAnchor].active   = YES;
	[glass.trailingAnchor constraintEqualToAnchor:glassy.trailingAnchor].active = YES;
	[glass.topAnchor constraintEqualToAnchor:glassy.topAnchor].active           = YES;
	[glass.bottomAnchor constraintEqualToAnchor:glassy.bottomAnchor].active     = YES;

	NSBitmapImageRep* without = SnapshotView(plain,  NSAppearanceNameDarkAqua);
	NSBitmapImageRep* with    = SnapshotView(glassy, NSAppearanceNameDarkAqua);

	// Measured at 0.44 for this exact comparison; 0.02 is a floor far below it
	// that still fails outright if glass stops rendering.
	OAK_ASSERT(MeanDifference(without, with) > 0.02);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/build OakAppKit/test`

Expected: FAIL to compile — `use of undeclared identifier 'OakAddAutoLayoutViewsToSuperview'` is *not* what you should see (it is declared in `OakUIConstructionFunctions.h`, already imported). If the build succeeds and the test passes on the first run, that is fine and expected: this task adds a harness whose assertion is about AppKit's behaviour, not about code being written here. Confirm it *runs* — the count in `OakAppKit_test: N tests passed` must go from 10 to 11.

If it fails with `MeanDifference` under threshold, stop: the offscreen capture path is not seeing glass on this machine and every later verification step in this plan is void. Report that rather than raising the threshold.

- [ ] **Step 3: Commit**

```bash
git add Frameworks/OakAppKit/tests/t_glass_snapshot.mm
git commit -m "test(OakAppKit): add an offscreen glass snapshot harness

Renders a view with NSApp.appearance forced and captures it with
cacheDisplayInRect:, which was measured to reproduce live glass to within 0.015
mean absolute RGB of what screencapture produces for the same window -- without
needing screen-recording permission or a visible window.

Passing -AppleInterfaceStyle on the command line does not work for this: the
value lands in NSArgumentDomain and reads back, but AppKit takes
effectiveAppearance from the system setting and ignores it."
```

---

### Task 2: Make the control translucent and glass-backed

The migration proper. Four things change together and the control is broken if any one is missed,
so they are one task: `isOpaque` must stop claiming opacity, the glass must be installed as the
first subview, the display string must move into a text field, and `drawRect:` must go.

**Files:**
- Modify: `Frameworks/OakAppKit/src/OakKeyEquivalentView.mm`
- Test: `Frameworks/OakAppKit/tests/t_key_equivalent_view.mm` (create)

**Interfaces:**
- Consumes: `OakCreateGlassBackground` from the foundation increment.
- Produces: no API change. `OakKeyEquivalentView.h` is untouched and
  `BundleItemChooser.mm:643` keeps working as-is.

- [ ] **Step 1: Write the failing tests**

Create `Frameworks/OakAppKit/tests/t_key_equivalent_view.mm`:

```objc
#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <oak/oak.h>

static NSGlassEffectView* GlassOf (OakKeyEquivalentView* view)
{
	// The glass is installed in initWithFrame:, before the clear button can be
	// added, so it is always the control's first subview. (Do not confuse this
	// with the glass view's own subviews, of which there are always two
	// internal ones even when it is empty.)
	NSView* first = view.subviews.firstObject;
	OAK_ASSERT(first != nil);
	OAK_ASSERT([first isKindOfClass:[NSGlassEffectView class]]);
	return (NSGlassEffectView*)first;
}

static NSTextField* DisplayFieldOf (OakKeyEquivalentView* view)
{
	NSView* content = GlassOf(view).contentView;
	OAK_ASSERT(content != nil);
	OAK_ASSERT([content isKindOfClass:[NSTextField class]]);
	return (NSTextField*)content;
}

void test_key_equivalent_view_is_not_opaque ()
{
	// Glass samples what is behind it. A view that still claims to be opaque
	// tells AppKit not to draw that backdrop, and the effect has nothing to
	// work with.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT_EQ(view.isOpaque, NO);
}

void test_key_equivalent_view_has_a_glass_background ()
{
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	NSGlassEffectView* glass = GlassOf(view);
	OAK_ASSERT_EQ(glass.style, NSGlassEffectViewStyleRegular);
}

void test_key_equivalent_view_shows_its_event_string ()
{
	// Deliberately not asserting a literal "⌘S": the glyph mapping belongs to
	// ns::glyphs_for_event_string, and pinning its output here would make this
	// test fail for a reason that has nothing to do with the view. What matters
	// is that the field shows whatever the view considers its value -- which is
	// exactly what accessibilityAttributeValue: reports.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = @"@s";

	NSString* shown = DisplayFieldOf(view).stringValue;
	OAK_ASSERT(shown.length > 0);
	OAK_ASSERT([shown isEqualToString:[view accessibilityAttributeValue:NSAccessibilityValueAttribute]]);
}

void test_key_equivalent_view_dims_its_text_while_recording ()
{
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];

	// disableGlobalHotkeys defaults to YES, and setRecording: then calls
	// PushSymbolicHotKeyMode, which disables every system hotkey for as long as
	// the mode is pushed. A test must not leave that pushed, so turn it off
	// first and stop recording before returning.
	view.disableGlobalHotkeys = NO;

	OAK_ASSERT([DisplayFieldOf(view).textColor isEqual:NSColor.labelColor]);
	view.recording = YES;
	OAK_ASSERT([DisplayFieldOf(view).textColor isEqual:NSColor.secondaryLabelColor]);
	view.recording = NO;
	OAK_ASSERT([DisplayFieldOf(view).textColor isEqual:NSColor.labelColor]);
}

void test_key_equivalent_view_keeps_its_clear_button_above_the_glass ()
{
	// setEventString: sets showClearButton itself (OakKeyEquivalentView.mm:46),
	// so assigning a non-empty string is enough to add the button.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = @"@s";

	OAK_ASSERT(view.subviews.count >= 2);
	OAK_ASSERT([view.subviews.firstObject isKindOfClass:[NSGlassEffectView class]]);
	OAK_ASSERT(![view.subviews.lastObject isKindOfClass:[NSGlassEffectView class]]);
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/build OakAppKit/test`

Expected: FAIL. `test_key_equivalent_view_is_not_opaque` fails because `isOpaque` still returns
`YES`; the rest fail inside `GlassOf` because the control has no glass subview yet.

- [ ] **Step 3: Add the display field and glass to the class extension**

In `Frameworks/OakAppKit/src/OakKeyEquivalentView.mm`, extend the existing class extension at
lines 11–19 so it reads:

```objc
@interface OakKeyEquivalentView ()
{
	OakRolloverButton* _clearButton;
	NSGlassEffectView* _glassView;
	NSTextField* _displayField;
	id _eventMonitor;
	void* _hotkeyToken;
}
@property (nonatomic) NSString* displayString;
@property (nonatomic) BOOL showClearButton;
@end
```

- [ ] **Step 4: Build the glass background in the initialiser**

Replace `initWithFrame:` (lines 22–27) with:

```objc
- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		self.disableGlobalHotkeys = YES;

		_displayField                          = [NSTextField labelWithString:@""];
		_displayField.alignment                = NSTextAlignmentCenter;
		_displayField.font                     = OakControlFont();
		_displayField.textColor                = NSColor.labelColor;
		_displayField.cell.accessibilityElement = NO; // this class answers for itself; see accessibilityAttributeValue:

		_glassView              = OakCreateGlassBackground(NSGlassEffectViewStyleRegular);
		_glassView.cornerRadius = 8; // see the note in Task 5 -- provisional until the renders are reviewed
		_glassView.contentView  = _displayField;

		// Added first, so the clear button that setShowClearButton: appends
		// later is always above it.
		OakAddAutoLayoutViewsToSuperview(@[ _glassView ], self);
		[_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active   = YES;
		[_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
		[_glassView.topAnchor constraintEqualToAnchor:self.topAnchor].active           = YES;
		[_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active     = YES;
	}
	return self;
}
```

Do **not** add constraints between `_glassView` and `_displayField`. Assigning `contentView`
installs them internally; adding your own conflicts with them.

- [ ] **Step 5: Route the display string and recording state to the field**

Replace `setDisplayString:` (lines 66–72) with:

```objc
- (void)setDisplayString:(NSString*)aString
{
	if(_displayString == aString || [_displayString isEqualToString:aString])
		return;
	_displayString = aString;
	_displayField.stringValue = aString ?: @"";
}
```

Then, in `setRecording:`, immediately after the existing `self.displayString = …` assignment on
line 111, add:

```objc
	_displayField.textColor = _recording ? NSColor.secondaryLabelColor : NSColor.labelColor;
```

- [ ] **Step 6: Stop claiming opacity**

Replace `isOpaque` (lines 163–166) with:

```objc
- (BOOL)isOpaque
{
	return NO;
}
```

- [ ] **Step 7: Delete `drawRect:` and round the focus ring to match the glass**

Delete the whole of `drawRect:` (lines 201–228). Everything it drew is now either the glass
background or the display field.

Deleting it also removes two latent defects rather than preserving them: an
`if(@available(macos 10.14, *))` guard that is dead code against a macOS 26 deployment target, and
a mis-indented line inside it that made `backgroundColor = NSColor.controlColor` unconditional, so
the `NSColor.whiteColor` initialiser above it never took effect in any appearance.

Then replace `drawFocusRingMask` (lines 230–233) so the ring follows the glass outline instead of
a square:

```objc
- (void)drawFocusRingMask
{
	[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:_glassView.cornerRadius yRadius:_glassView.cornerRadius] fill];
}
```

Leave `focusRingMaskBounds` as it is — the bounds are still correct.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bin/build OakAppKit/test`
Expected: PASS — `OakAppKit_test: 16 tests passed` (10 from the foundation, 1 from Task 1, 5 here).

- [ ] **Step 9: Commit**

```bash
git add Frameworks/OakAppKit/src/OakKeyEquivalentView.mm Frameworks/OakAppKit/tests/t_key_equivalent_view.mm
git commit -m "feat(OakAppKit): put the key equivalent recorder on glass

The control drew its own one-pixel border and inset fill, and drew its display
string in the same drawRect:. A view's own drawRect: paints beneath its
subviews, so glass could not simply go behind that text -- it would have covered
it. The string moves into the glass view's contentView as an NSTextField and
drawRect: goes away entirely.

isOpaque had to stop returning YES: it tells AppKit not to draw the backdrop,
which is exactly what the glass effect samples.

Deleting drawRect: also drops an @available(macos 10.14) guard that was dead
against a macOS 26 deployment target, and a mis-indented line that made the
background unconditionally controlColor -- the whiteColor initialiser above it
had never taken effect."
```

---

### Task 3: Render the migrated control in both appearances

**Files:**
- Modify: `Frameworks/OakAppKit/tests/t_glass_snapshot.mm`

**Interfaces:**
- Consumes: `SnapshotView` and `WriteSnapshotIfRequested` from Task 1; the migrated control from Task 2.
- Produces: four PNGs when `OAK_SNAPSHOT_DIR` is set.

- [ ] **Step 1: Write the failing test**

Add to `Frameworks/OakAppKit/tests/t_glass_snapshot.mm`, and add
`#import <OakAppKit/OakKeyEquivalentView.h>` to its imports:

```objc
static OakKeyEquivalentView* MakeRecorder (NSString* eventString, CGFloat cornerRadius)
{
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = eventString;
	((NSGlassEffectView*)view.subviews.firstObject).cornerRadius = cornerRadius;
	[view.widthAnchor constraintEqualToConstant:180].active = YES;
	return view;
}

void test_key_equivalent_view_renders_in_both_appearances ()
{
	// Two radii are captured because the right one is a judgement the renders
	// have to settle: OakGlassChromeMetrics().cornerRadius is 12, chosen for
	// chrome bars, and this control is a fixed 22pt tall, so 12 exceeds half its
	// height and rounds it to a pill. 8 is the SDK's own default.
	for(NSNumber* radius in @[ @8, @12 ])
	{
		for(NSString* appearance in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ])
		{
			NSBitmapImageRep* rep = SnapshotView(MakeRecorder(@"@s", radius.doubleValue), appearance);
			OAK_ASSERT(rep.pixelsWide > 0);
			OAK_ASSERT(rep.pixelsHigh > 0);
			WriteSnapshotIfRequested(rep, [NSString stringWithFormat:@"key-equivalent-r%@-%@", radius,
				[appearance isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark"]);
		}
	}
}
```

- [ ] **Step 2: Run it**

Run: `bin/build OakAppKit/test`
Expected: PASS — `OakAppKit_test: 17 tests passed`.

- [ ] **Step 3: Produce the renders**

```bash
rm -rf /tmp/oak-shots && mkdir -p /tmp/oak-shots
OAK_SNAPSHOT_DIR=/tmp/oak-shots ~/build/textmate-revived/xcode/Release/OakAppKit_test
ls -l /tmp/oak-shots
```

Expected: four files — `key-equivalent-r8-light.png`, `key-equivalent-r8-dark.png`,
`key-equivalent-r12-light.png`, `key-equivalent-r12-dark.png`.

- [ ] **Step 4: Commit**

```bash
git add Frameworks/OakAppKit/tests/t_glass_snapshot.mm
git commit -m "test(OakAppKit): render the key equivalent recorder for review"
```

---

### Task 4: Confirm nothing else regressed

**Files:** none modified.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: evidence the tree is releasable.

- [ ] **Step 1: Build the application**

Run: `bin/build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run the baseline test suite**

Run the targets listed in `docs/benchmarks/2026-08-12-ninja-parity.md` and compare against it. The
four known-bad must reproduce identically and no others may fail: `scm` fails 2 of 84 (no `hg`/`svn`
on this machine), `buffer` fails 3 of 26 (misspellings), `file` fails 1 of 11 (iconv TRANSLIT), `cf`
crashes with SIGBUS exit 138. `command_test` is separately known to be flaky — the same binary has
given pass, hang, hang across three consecutive runs — so treat a hang there as noise, not as a
regression, and say so if it happens.

Expected: identical to the parity document, plus `OakAppKit_test` at 17.

- [ ] **Step 3: Exercise the control in the running application**

The renders show the control in isolation; this checks it in its actual home. Launch the built app
directly — **not** via `bin/deploy-local`:

```bash
open -n ~/build/textmate-revived/xcode/Release/TextMate.app
```

Then press ⌃⌘T to open the Bundle Item Chooser and switch its scope to key equivalents. Confirm
the recorder field appears, accepts a keystroke, shows the glyphs, and that its clear button still
appears and clears the value.

If anything about that interaction is wrong, that is a Task 2 defect, not a rendering question.

---

### Task 5: Hand the renders to the maintainer

**Files:** none modified.

- [ ] **Step 1: Present the four PNGs**

Send `key-equivalent-r8-{light,dark}.png` and `key-equivalent-r12-{light,dark}.png` and state
plainly what is being asked: whether glass suits this control at all, and which corner radius to
keep.

Say which way the code currently sits (radius 8, set explicitly in `initWithFrame:`) and that
`OakGlassChromeMetrics().cornerRadius` is 12, chosen for chrome bars rather than for a 22-point
control.

- [ ] **Step 2: Apply the decision**

- Radius 8 chosen → delete the now-redundant `_glassView.cornerRadius = 8;` line only if
  `OakCreateGlassBackground` is also changed to stop overriding the SDK default, which it should
  not be — chrome bars still want 12. Keep the explicit line and replace its provisional comment
  with the decision.
- Radius 12 chosen → delete the explicit line and let `OakCreateGlassBackground` supply it.
- Glass rejected for this control → stop. Revert Task 2, keep Tasks 1 and 3's harness (it is
  needed by every later increment regardless), and record the rejection in the spec.

- [ ] **Step 3: Commit any change from Step 2**

```bash
git add Frameworks/OakAppKit/src/OakKeyEquivalentView.mm
git commit -m "fix(OakAppKit): settle the key equivalent recorder's corner radius"
```

---

### Task 6: Ship it

**Gated on Task 5.** Do not start this task until the maintainer has approved the renders.

**Files:**
- Modify: `CHANGELOG.md`, `STREAM.md`
- Modify: `docs/benchmarks/2026-08-12-ninja-parity.md` (test count)

- [ ] **Step 1: Update the parity document**

`OakAppKit_test`'s expected count moves from 10 to 17.

- [ ] **Step 2: Add the STREAM.md entry**

Newest-first: what changed, that `OFBFinderTagsChooser` was dropped from this increment and why,
that the snapshot harness is now the verification route for increments 3–6, and that the next step
is planning increment 3 (overlays: `OTVHUD`, `OakToolTip`, `OakChoiceMenu`).

- [ ] **Step 3: Add the CHANGELOG entry and release**

Add a `v3.0.0-revived.20` entry describing the user-visible change: the key equivalent recorder in
the Bundle Item Chooser now uses the macOS 26 glass material instead of a hand-drawn border.

```bash
git add CHANGELOG.md STREAM.md docs/benchmarks/2026-08-12-ninja-parity.md
git commit -m "release: v3.0.0-revived.20 -- key equivalent recorder on glass"
git push
```

Pushing `CHANGELOG.md` to master is what triggers the release workflow. Watch it through verify →
sign → notarize → staple → publish, then confirm `github-actions[bot]` committed the bumped cask to
`sdenike/homebrew-tap` and that its `sha256` matches the published asset. A wrong checksum looks
correct in the diff and fails every `brew install`.

---

## What this plan deliberately does not cover

**`OFBFinderTagsChooser`, which the spec originally listed as the second target of this increment.**
Reading it settled the question: `FileBrowserViewController.mm:572` assigns it to an `NSMenuItem`'s
`view`, so it is a menu-item view, not a control in a window. It has no background of its own
because the menu draws one behind it, and adding an `NSGlassEffectView` would put a second material
inside a surface that already has one. The spec was corrected rather than the code.

**Increments 3 through 6** — overlays, chrome bars, choosers and window chrome, and the tab bar.
Each gets planned after its target files have been read, in the same way this one was, and each
inherits the snapshot harness Task 1 builds.
