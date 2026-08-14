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
	// setEventString: sets showClearButton itself (OakKeyEquivalentView.mm:46),
	// so assigning a non-empty string is enough to add the button.
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = @"@s";

	OAK_ASSERT(view.subviews.count >= 2);
	OAK_ASSERT([view.subviews.firstObject isKindOfClass:[NSGlassEffectView class]]);
	OAK_ASSERT(![view.subviews.lastObject isKindOfClass:[NSGlassEffectView class]]);
}
