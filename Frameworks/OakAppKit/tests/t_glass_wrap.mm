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
	// The hazard from the previous increment: content inside glass propagates
	// its size up through the glass to the host. A bar whose holder wants
	// 300x24 must end up 300x24 -- not collapsed, not stretched.
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
