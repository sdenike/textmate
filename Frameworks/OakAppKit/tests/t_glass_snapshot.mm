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
