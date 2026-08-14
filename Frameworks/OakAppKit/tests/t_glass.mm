#import <OakAppKit/OakUIConstructionFunctions.h>
#import <oak/oak.h>

// bin/gen_test wraps this file's body in its own namespace, so declaring to_s
// here would otherwise hide (not overload) the global to_s(bool) etc. that the
// pre-existing autoresize test below relies on. Pull those back in.
using ::to_s;

// OAK_ASSERT_EQ needs to stringify both sides on failure; NSGlassEffectViewStyle
// has no built-in to_s (see t_OakCompareVersionStrings.mm for the same pattern
// with NSComparisonResult).
std::string to_s (NSGlassEffectViewStyle style)
{
	switch(style)
	{
		case NSGlassEffectViewStyleRegular: return "NSGlassEffectViewStyleRegular";
		case NSGlassEffectViewStyleClear:   return "NSGlassEffectViewStyleClear";
	}
	return NULL_STR;
}

void test_glass_container_is_a_container ()
{
	NSGlassEffectContainerView* container = OakCreateGlassContainer();
	OAK_ASSERT(container != nil);
	OAK_ASSERT([container isKindOfClass:[NSGlassEffectContainerView class]]);
}

void test_glass_container_does_not_autoresize ()
{
	// Every caller lays these out with Auto Layout; a container that also
	// autoresizes fights its own constraints.
	NSGlassEffectContainerView* container = OakCreateGlassContainer();
	OAK_ASSERT_EQ(container.translatesAutoresizingMaskIntoConstraints, NO);
}

void test_glass_container_applies_spacing ()
{
	// spacing is what actually merges nearby glass views (see the header
	// comment); a caller passing a value must see it land on the view.
	NSGlassEffectContainerView* container = OakCreateGlassContainer(8);
	OAK_ASSERT_EQ(container.spacing, 8);
}

void test_glass_background_applies_style ()
{
	NSGlassEffectView* regular = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, nil);
	OAK_ASSERT(regular != nil);
	OAK_ASSERT_EQ(regular.style, NSGlassEffectViewStyleRegular);

	NSGlassEffectView* clear = OakCreateGlassBackground(NSGlassEffectViewStyleClear, nil);
	OAK_ASSERT_EQ(clear.style, NSGlassEffectViewStyleClear);
}

void test_glass_background_nil_tint_leaves_system_default ()
{
	NSGlassEffectView* view = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, nil);
	OAK_ASSERT(view.tintColor == nil);
}

void test_glass_background_applies_tint_when_given ()
{
	// Dynamic, not static: the header requires tint to be "a dynamic colour
	// that resolves for both light and dark appearance", and this fixture is
	// exemplar code for future callers, so it must actually be one.
	NSColor* tint = [NSColor colorWithName:nil dynamicProvider:^NSColor* (NSAppearance* appearance){
		NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
		return [match isEqualToString:NSAppearanceNameDarkAqua] ? [NSColor colorWithWhite:0.2 alpha:0.5] : [NSColor colorWithWhite:0.8 alpha:0.5];
	}];
	NSGlassEffectView* view = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, tint);
	OAK_ASSERT([view.tintColor isEqual:tint]);
}

void test_glass_background_hosts_content_via_contentView ()
{
	// The API contract callers get wrong: content goes in contentView, not as a
	// subview. Encoding it here means one place to be right instead of twelve.
	NSGlassEffectView* view = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, nil);
	NSView* content = [[NSView alloc] initWithFrame:NSZeroRect];
	view.contentView = content;
	// Not OAK_ASSERT_EQ: two NSView* resolve to gen_test's generic to_s
	// fallback, which range-fors over the pointer. It compiles (with a
	// warning), but a failing assertion would throw NSInvalidArgumentException,
	// which the runner's catch(std::exception const&) doesn't catch -- SIGABRT
	// instead of a reported failure. test_glass_container_is_a_container
	// already avoids the same trap the same way.
	OAK_ASSERT(view.contentView == content);
}

void test_glass_background_does_not_autoresize ()
{
	NSGlassEffectView* view = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, nil);
	OAK_ASSERT_EQ(view.translatesAutoresizingMaskIntoConstraints, NO);
}

void test_glass_background_applies_corner_radius ()
{
	// OakGlassChromeMetrics() is disconnected from NSGlassEffectView's real
	// cornerRadius property unless the constructor wires them together itself
	// -- otherwise every call site has to remember to do it.
	NSGlassEffectView* view = OakCreateGlassBackground(NSGlassEffectViewStyleRegular, nil);
	OAK_ASSERT_EQ(view.cornerRadius, OakGlassChromeMetrics().cornerRadius);
}

void test_glass_chrome_metrics_are_shared_constants ()
{
	OakGlassMetrics metrics = OakGlassChromeMetrics();
	OAK_ASSERT_EQ(metrics.cornerRadius, 12);
	OAK_ASSERT_EQ(metrics.contentInsets.top, 8);
	OAK_ASSERT_EQ(metrics.contentInsets.left, 12);
	OAK_ASSERT_EQ(metrics.contentInsets.bottom, 8);
	OAK_ASSERT_EQ(metrics.contentInsets.right, 12);
}
