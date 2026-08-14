#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakKeyEquivalentView.h>
#import <oak/oak.h>

// Resolves a dynamic system colour for `appearanceName`.
//
// Setting NSApp.appearance is not enough: a dynamic NSColor resolves against
// NSAppearance.currentAppearance, which is separate thread-local state that
// NSApp.appearance does not touch. Measured 2026-08-14 -- reading
// windowBackgroundColor with only NSApp.appearance set returns pure white under
// BOTH appearances, while resolving it inside performAsCurrentDrawingAppearance:
// gives white for Aqua and 0.118 grey for DarkAqua. Get this wrong and the light
// and dark renders come back byte-identical while every test still passes.
//
// A plain NSView plus a layer colour is used rather than an NSView subclass that
// paints in drawRect:, because bin/gen_test wraps every test file in
// `namespace <filename> { … }` and Objective-C forbids @interface/@implementation
// inside a C++ namespace. No test file in this tree can declare a class.
static NSColor* ResolvedWindowBackground (NSString* appearanceName)
{
	__block NSColor* res = nil;
	[[NSAppearance appearanceNamed:appearanceName] performAsCurrentDrawingAppearance:^{
		res = [NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
	}];
	return res;
}

// Builds an offscreen window around `view` with `appearanceName` forced, runs the
// layout and a few runloop turns, and hands back the window so the caller can
// choose how to capture it.
//
// NSApp.appearance is the only thing that forces appearance here. Passing
// -AppleInterfaceStyle on the command line does put the value in NSArgumentDomain,
// and stringForKey: reads it back, but AppKit takes effectiveAppearance from the
// system setting and ignores it -- so a harness built on that renders light and
// dark identically while passing. The generated test runner also creates no
// NSApplication, and setting a property on a nil NSApp is a silent no-op, so
// sharedApplication has to be called here.
static NSWindow* PrepareWindow (NSView* view, NSString* appearanceName)
{
	[NSApplication sharedApplication];
	NSApp.appearance = [NSAppearance appearanceNamed:appearanceName];

	NSSize size = view.fittingSize;
	if(size.width < 1)
		size.width = 200;
	if(size.height < 1)
		size.height = 22;

	// Inset the view from the window edge. Without this the glass runs edge to
	// edge and its outline leaves the frame, which makes the one thing these
	// renders exist to show -- the corner radius -- nearly impossible to see.
	CGFloat const kPadding = 12;

	NSRect frame = NSMakeRect(0, 0, size.width + kPadding * 2, size.height + kPadding * 2);
	NSWindow* window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	window.releasedWhenClosed = NO;

	// Glass refracts what is behind it, so a host with no background renders it as
	// a flat pale shape in every appearance.
	NSView* host = [[NSView alloc] initWithFrame:frame];
	host.wantsLayer = YES;
	host.layer.backgroundColor = ResolvedWindowBackground(appearanceName).CGColor;
	window.contentView = host;

	OakAddAutoLayoutViewsToSuperview(@[ view ], host);
	[view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:kPadding].active    = YES;
	[view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-kPadding].active = YES;
	[view.topAnchor constraintEqualToAnchor:host.topAnchor constant:kPadding].active            = YES;
	[view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-kPadding].active     = YES;

	[host layoutSubtreeIfNeeded];
	for(NSInteger i = 0; i < 40; ++i)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	return window;
}

// Offscreen capture. Needs no visible window, no activation policy and no
// screen-recording permission, so this is the CI-safe path.
//
// IMPORTANT: it does NOT capture an NSGlassEffectView's contentView. The glass
// material itself is captured, but its hosted content is composited by the window
// server and never reaches the bitmap. Measured: a black label rendered as a plain
// subview covers 4.24% of the pixels; the identical label assigned to
// glass.contentView covers 0.00%, indistinguishable from empty glass; the same
// label as a sibling drawn over the glass covers 4.24% again. Use this to assert
// geometry and that the material rendered -- never to check what a glass surface
// contains.
static NSBitmapImageRep* SnapshotView (NSView* view, NSString* appearanceName)
{
	NSAppearance* savedAppearance = NSApp.appearance;
	NSWindow* window = PrepareWindow(view, appearanceName);
	NSView* host = window.contentView;

	NSBitmapImageRep* rep = [host bitmapImageRepForCachingDisplayInRect:host.bounds];
	[host cacheDisplayInRect:host.bounds toBitmapImageRep:rep];

	// NSApp.appearance is process-wide and test order is not guaranteed, so leaving
	// it forced would silently change what any later test renders under.
	NSApp.appearance = savedAppearance;
	return rep;
}

// Live capture, via a real onscreen window. This is the only way to see what a
// glass surface actually contains -- the same label that is invisible to
// SnapshotView covers 3.06% of the pixels here.
//
// The cost is that it needs the window ordered front, a regular activation policy
// and screen-recording permission for the running terminal, none of which hold
// under CI. So it is used only to produce images for review, never for assertions.
// Returns nil when the capture produced nothing.
static NSBitmapImageRep* CaptureLiveWindow (NSView* view, NSString* appearanceName, NSString* path)
{
	NSAppearance* savedAppearance = NSApp.appearance;
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

	NSWindow* window = PrepareWindow(view, appearanceName);
	[window makeKeyAndOrderFront:nil];
	for(NSInteger i = 0; i < 60; ++i)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];

	NSTask* task = [[NSTask alloc] init];
	task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
	task.arguments = @[ @"-x", @"-o", [NSString stringWithFormat:@"-l%ld", (long)window.windowNumber], path ];
	NSError* error = nil;
	[task launchAndReturnError:&error];
	[task waitUntilExit];
	[window orderOut:nil];
	NSApp.appearance = savedAppearance;

	NSData* data = [NSData dataWithContentsOfFile:path];
	return data ? [[NSBitmapImageRep alloc] initWithData:data] : nil;
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

// Fraction of opaque pixels dark enough to be text ink.
static double DarkFraction (NSBitmapImageRep* rep)
{
	NSInteger n = 0, hits = 0;
	for(NSInteger y = 0; y < rep.pixelsHigh; ++y)
	{
		for(NSInteger x = 0; x < rep.pixelsWide; ++x)
		{
			NSColor* c = [rep colorAtX:x y:y];
			double luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent;
			if(c.alphaComponent > 0.5 && luminance < 0.35)
				++hits;
			++n;
		}
	}
	return n ? (double)hits / n : 0;
}

static NSView* MakeSizedView (CGFloat width, CGFloat height)
{
	NSView* res = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	res.translatesAutoresizingMaskIntoConstraints = NO;
	[res.widthAnchor constraintEqualToConstant:width].active   = YES;
	[res.heightAnchor constraintEqualToConstant:height].active = YES;
	return res;
}

void test_window_background_resolves_per_appearance ()
{
	// Guards the trap this harness fell into: reading a dynamic colour with only
	// NSApp.appearance set returns the same value under both appearances, so the
	// backdrop bakes one of them and every render comes out identical.
	NSColor* light = ResolvedWindowBackground(NSAppearanceNameAqua);
	NSColor* dark  = ResolvedWindowBackground(NSAppearanceNameDarkAqua);
	OAK_ASSERT(fabs(light.redComponent - dark.redComponent) > 0.25);
}

void test_snapshot_captures_live_glass ()
{
	// Two identical hosts, one with a glass subview. If cacheDisplayInRect: did
	// not capture the glass material at all, these would render identically and
	// every image this harness produces would be worthless.
	NSView* plain = MakeSizedView(200, 40);

	NSView* glassy = MakeSizedView(200, 40);
	NSGlassEffectView* glass = OakCreateGlassBackground(NSGlassEffectViewStyleRegular);
	OakAddAutoLayoutViewsToSuperview(@[ glass ], glassy);
	[glass.leadingAnchor constraintEqualToAnchor:glassy.leadingAnchor].active   = YES;
	[glass.trailingAnchor constraintEqualToAnchor:glassy.trailingAnchor].active = YES;
	[glass.topAnchor constraintEqualToAnchor:glassy.topAnchor].active           = YES;
	[glass.bottomAnchor constraintEqualToAnchor:glassy.bottomAnchor].active     = YES;

	NSBitmapImageRep* without = SnapshotView(plain,  NSAppearanceNameDarkAqua);
	NSBitmapImageRep* with    = SnapshotView(glassy, NSAppearanceNameDarkAqua);

	// Measured at 0.44 for this comparison; 0.02 is a floor far below it that
	// still fails outright if the material stops rendering.
	OAK_ASSERT(MeanDifference(without, with) > 0.02);
}

void test_offscreen_capture_cannot_see_inside_glass ()
{
	// Locks in a limitation rather than a behaviour, so that the day AppKit starts
	// compositing contentView into cacheDisplayInRect: this fails and tells us the
	// live-window path is no longer needed. Until then it is the reason
	// CaptureLiveWindow exists.
	//
	// The same label is measured twice: as an ordinary subview, and as the glass's
	// contentView. Only the first leaves ink.
	NSTextField* visible = [NSTextField labelWithString:@"HELLO WORLD"];
	visible.textColor = NSColor.blackColor;
	visible.frame     = NSMakeRect(10, 10, 160, 20);
	NSView* plainHost = MakeSizedView(180, 40);
	[plainHost addSubview:visible];

	NSTextField* hidden = [NSTextField labelWithString:@"HELLO WORLD"];
	hidden.textColor = NSColor.blackColor;
	NSGlassEffectView* glass = OakCreateGlassBackground(NSGlassEffectViewStyleRegular);
	glass.contentView = hidden;
	NSView* glassHost = MakeSizedView(180, 40);
	OakAddAutoLayoutViewsToSuperview(@[ glass ], glassHost);
	[glass.centerXAnchor constraintEqualToAnchor:glassHost.centerXAnchor].active = YES;
	[glass.centerYAnchor constraintEqualToAnchor:glassHost.centerYAnchor].active = YES;
	[glass.widthAnchor constraintEqualToConstant:160].active                     = YES;
	[glass.heightAnchor constraintEqualToConstant:20].active                     = YES;

	double asSubview = DarkFraction(SnapshotView(plainHost, NSAppearanceNameAqua));
	double asContent = DarkFraction(SnapshotView(glassHost, NSAppearanceNameAqua));

	OAK_ASSERT(asSubview > 0.01);   // measured 0.0424
	OAK_ASSERT(asContent < 0.001);  // measured 0.0000
}

static OakKeyEquivalentView* MakeRecorder (NSString* eventString, CGFloat cornerRadius)
{
	OakKeyEquivalentView* view = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
	view.eventString = eventString;
	((NSGlassEffectView*)view.subviews.firstObject).cornerRadius = cornerRadius;
	[view.widthAnchor constraintEqualToConstant:180].active = YES;

	// The clear button's image lives in the OakAppKit framework bundle, which a
	// bare test-runner binary does not have, so NSButton falls back to drawing its
	// default "Button" title -- wide enough to cover the glyphs entirely. It is
	// irrelevant to what these renders exist to judge, so take it out; its real
	// appearance is checked in the running application instead. Iterate a copy:
	// mutating subviews while enumerating it is undefined.
	for(NSView* subview in [view.subviews copy])
	{
		if(![subview isKindOfClass:[NSGlassEffectView class]])
			[subview removeFromSuperview];
	}
	return view;
}

void test_key_equivalent_view_renders_in_both_appearances ()
{
	// Two radii are captured because the right one is a judgement the images have
	// to settle: OakGlassChromeMetrics().cornerRadius is 12, chosen for chrome
	// bars, while this control is a fixed 22pt tall, so 12 exceeds half its height
	// and rounds it to a pill. 8 is the SDK's own default.
	//
	// Geometry is asserted from the offscreen path, which works everywhere. The
	// images written for review come from a live window, because the offscreen
	// path cannot see the glyphs inside the glass -- see
	// test_offscreen_capture_cannot_see_inside_glass.
	char const* dir = getenv("OAK_SNAPSHOT_DIR");

	for(NSNumber* radius in @[ @8, @12 ])
	{
		for(NSString* appearance in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ])
		{
			NSString* name = [NSString stringWithFormat:@"key-equivalent-r%@-%@", radius,
				[appearance isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark"];

			// 180 x 22 plus PrepareWindow's 12pt padding on every side.
			NSBitmapImageRep* rep = SnapshotView(MakeRecorder(@"@s", radius.doubleValue), appearance);
			OAK_ASSERT_EQ(rep.pixelsWide, 204);
			OAK_ASSERT_EQ(rep.pixelsHigh, 46);

			if(dir)
			{
				NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
				NSBitmapImageRep* live = CaptureLiveWindow(MakeRecorder(@"@s", radius.doubleValue), appearance, path);
				if(live)
					fprintf(stderr, "wrote %s (%ldx%ld)\n", path.UTF8String, (long)live.pixelsWide, (long)live.pixelsHigh);
				else
					fprintf(stderr, "FAILED to capture %s -- screen recording permission?\n", path.UTF8String);
			}
		}
	}
}
