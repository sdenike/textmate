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
	// The glass hosts a holder view whose only child is the display field. The
	// holder exists so the field keeps its natural height and stays centred
	// rather than stretching to fill the glass, so reach through it -- the
	// glass's contentView is the holder, not the field.
	NSView* holder = GlassOf(view).contentView;
	OAK_ASSERT(holder != nil);

	NSView* field = holder.subviews.firstObject;
	OAK_ASSERT(field != nil);
	OAK_ASSERT([field isKindOfClass:[NSTextField class]]);
	return (NSTextField*)field;
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
	// Not OAK_ASSERT_EQ: NSGlassEffectViewStyle has no to_s overload visible in
	// this file (bin/gen_test wraps each test file in its own namespace, so
	// t_glass.mm's local overload for the same enum does not reach here), and
	// OAK_ASSERT_EQ's fallback to_s is the generic container one, which fails to
	// compile against a plain enum.
	OAK_ASSERT(glass.style == NSGlassEffectViewStyleRegular);
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
	// setEventString: sets showClearButton itself, so assigning a non-empty
	// string is enough to add the button.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = @"@s";

	OAK_ASSERT(view.subviews.count >= 2);
	OAK_ASSERT([view.subviews.firstObject isKindOfClass:[NSGlassEffectView class]]);
	OAK_ASSERT(![view.subviews.lastObject isKindOfClass:[NSGlassEffectView class]]);
}

void test_key_equivalent_view_keeps_its_declared_height ()
{
	// The glass hosts the display field through contentView, which pins the
	// field to fill it. Without the height constraint below, the field's own
	// 16pt intrinsic height propagates up through the glass and beats the
	// control's declared 22, silently shrinking the control.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = @"@s";

	NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 180, 60)];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	[host addSubview:view];
	[view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor].active   = YES;
	[view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor].active = YES;
	[view.centerYAnchor constraintEqualToAnchor:host.centerYAnchor].active   = YES;
	[host layoutSubtreeIfNeeded];

	OAK_ASSERT_EQ(NSHeight(view.frame), 22);
}

void test_key_equivalent_view_yields_its_height_to_a_host ()
{
	// The height is priority 999, not required, so a host that needs a
	// different size still wins -- which is how the control behaved before it
	// gained a glass background.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];

	NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 180, 60)];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	[host addSubview:view];
	[view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor].active   = YES;
	[view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor].active = YES;
	[view.centerYAnchor constraintEqualToAnchor:host.centerYAnchor].active   = YES;
	[view.heightAnchor constraintEqualToConstant:30].active                  = YES;
	[host layoutSubtreeIfNeeded];

	OAK_ASSERT_EQ(NSHeight(view.frame), 30);
}
