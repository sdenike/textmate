#import "AboutWindowController.h"
#import "TextMate-Swift.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

static NSString* const kUserDefaultsReleaseNotesDigestKey = @"releaseNotesDigest";

static NSData* Digest (NSData* someData)
{
	unsigned char md[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(someData.bytes, (CC_LONG)someData.length, md);
	return [NSData dataWithBytes:md length:sizeof(md)];
}

// bin/gen_about_data builds this at compile time from CHANGELOG.md (see its
// own header comment). URLForResource:withExtension: does NOT search
// subdirectories on its own -- confirmed against the real API -- so the
// subdirectory: argument here is load-bearing, not decorative.
static NSURL* ChangelogPlistURL ()
{
	return [NSBundle.mainBundle URLForResource:@"Changelog" withExtension:@"plist" subdirectory:@"About"];
}

@interface AboutWindowController () <NSWindowDelegate, NSToolbarDelegate>
@property (nonatomic, readonly) NSArray<NSString*>* segmentLabels;
@property (nonatomic) NSToolbar* toolbar;
@property (nonatomic) NSSegmentedControl* segmentedControl;
@property (nonatomic) AboutHostingController* aboutHostingController;
@property (nonatomic) NSString* selectedPage;
@end

@implementation AboutWindowController
+ (instancetype)sharedInstance
{
	static AboutWindowController* sharedInstance = [self new];
	return sharedInstance;
}

+ (void)showChangesIfUpdated
{
	NSURL* url = ChangelogPlistURL();
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		if(NSData* releaseNotes = [NSData dataWithContentsOfURL:url])
		{
			NSData* lastDigest    = [NSUserDefaults.standardUserDefaults dataForKey:kUserDefaultsReleaseNotesDigestKey];
			NSData* currentDigest = Digest(releaseNotes);
			dispatch_async(dispatch_get_main_queue(), ^{
				if(lastDigest && ![lastDigest isEqualToData:currentDigest])
					[AboutWindowController.sharedInstance showChangesWindow:self];
				[NSUserDefaults.standardUserDefaults setObject:currentDigest forKey:kUserDefaultsReleaseNotesDigestKey];
			});
		}
	});
}

- (id)init
{
	NSRect visibleRect = [[NSScreen mainScreen] visibleFrame];
	NSRect rect = NSMakeRect(0, 0, std::min<CGFloat>(700, NSWidth(visibleRect)), std::min<CGFloat>(800, NSHeight(visibleRect)));

	NSWindow* win = [[NSPanel alloc] initWithContentRect:rect styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
	if((self = [super initWithWindow:win]))
	{
		_segmentLabels    = @[ @"About", @"Changes", @"Legal" ];
		_segmentedControl = [NSSegmentedControl segmentedControlWithLabels:_segmentLabels trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(takeSelectedSegmentFrom:)];

		self.toolbar = [[NSToolbar alloc] initWithIdentifier:@"About TextMate"];
		[self.toolbar setAllowsUserCustomization:NO];
		[self.toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
		[self.toolbar setDelegate:self];
		[win setToolbar:self.toolbar];

		[win setFrameAutosaveName:@"BundlesReleaseNotes"];
		[win setDelegate:self];
		[win setAutorecalculatesKeyViewLoop:YES];
		[win setHidesOnDeactivate:NO];
		[win setTitleVisibility:NSWindowTitleHidden];

		self.aboutHostingController = [AboutHostingController new];

		NSView* contentView = self.aboutHostingController.view;
		[contentView.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
		[contentView.heightAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;

		[win setContentView:contentView];
	}
	return self;
}

- (void)showAboutWindow:(id)sender
{
	self.selectedPage = @"About";
	[self showWindow:self];
	[self centerOnFrontmostDocumentWindow];
}

- (void)centerOnFrontmostDocumentWindow
{
	// Centre on the frontmost document window when there is one, so the panel
	// lands where the user is looking rather than on whichever screen happens to
	// be "main". Falls back to the active screen.
	//
	// Panels are skipped: the About window is itself an NSPanel, and so are the
	// other auxiliary windows, none of which are a sensible thing to centre on.
	NSRect target = NSScreen.mainScreen.visibleFrame;
	for(NSWindow* window in NSApp.orderedWindows)
	{
		if(window == self.window || !window.isVisible || [window isKindOfClass:[NSPanel class]])
			continue;
		target = window.frame;
		break;
	}

	NSRect frame = self.window.frame;
	frame.origin.x = round(NSMidX(target) - NSWidth(frame)  / 2);
	frame.origin.y = round(NSMidY(target) - NSHeight(frame) / 2);

	// Keep it on screen: a document window can be partly offscreen, or larger
	// than the screen the panel would land on.
	NSScreen* screen = self.window.screen ?: NSScreen.mainScreen;
	NSRect limit = screen.visibleFrame;
	frame.origin.x = std::min(std::max(NSMinX(frame), NSMinX(limit)), NSMaxX(limit) - NSWidth(frame));
	frame.origin.y = std::min(std::max(NSMinY(frame), NSMinY(limit)), NSMaxY(limit) - NSHeight(frame));

	[self.window setFrameOrigin:frame.origin];
}

- (void)showChangesWindow:(id)sender
{
	self.selectedPage = @"Changes";
	[self showWindow:self];

	if(NSData* releaseNotes = [NSData dataWithContentsOfURL:ChangelogPlistURL()])
		[NSUserDefaults.standardUserDefaults setObject:Digest(releaseNotes) forKey:kUserDefaultsReleaseNotesDigestKey];
}

- (void)takeSelectedSegmentFrom:(id)sender
{
	if(sender == _segmentedControl)
		self.selectedPage = _segmentLabels[_segmentedControl.selectedSegment];
	else if([sender respondsToSelector:@selector(representedObject)])
		self.selectedPage = [sender representedObject];
}

- (void)setSelectedPage:(NSString*)pageName
{
	if(_selectedPage == pageName || [_selectedPage isEqualToString:pageName])
		return;
	_selectedPage = pageName;

	[self.aboutHostingController showPage:pageName];
	_segmentedControl.selectedSegment = [_segmentLabels indexOfObject:pageName];
}

- (void)selectPageAtRelativeOffset:(NSInteger)offset
{
	NSUInteger index = [_segmentLabels indexOfObject:self.selectedPage];
	if(index != NSNotFound)
		self.selectedPage = _segmentLabels[(index + _segmentLabels.count + offset) % _segmentLabels.count];
}

- (IBAction)selectNextTab:(id)sender     { [self selectPageAtRelativeOffset:+1]; }
- (IBAction)selectPreviousTab:(id)sender { [self selectPageAtRelativeOffset:-1]; }

// ====================
// = Toolbar Delegate =
// ====================

- (NSToolbarItem*)toolbar:(NSToolbar*)aToolbar itemForItemIdentifier:(NSString*)anIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem* res = [[NSToolbarItem alloc] initWithItemIdentifier:anIdentifier];
	if(![anIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier])
		res.view = _segmentedControl;
	return res;
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)aToolbar
{
	return [self toolbarDefaultItemIdentifiers:aToolbar];
}

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)aToolbar
{
	return @[ NSToolbarFlexibleSpaceItemIdentifier, @"TMSegmentedControlIdentifier", NSToolbarFlexibleSpaceItemIdentifier ];
}

- (void)updateShowTabMenu:(NSMenu*)aMenu
{
	if(![[self window] isKeyWindow])
	{
		[aMenu addItemWithTitle:@"No Tabs" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	for(NSUInteger i = 0; i < _segmentLabels.count; ++i)
	{
		NSString* label = _segmentLabels[i];
		NSMenuItem* item = [aMenu addItemWithTitle:label action:@selector(takeSelectedSegmentFrom:) keyEquivalent:i < 9 ? [NSString stringWithFormat:@"%c", '1' + (char)i] : @""];
		[item setRepresentedObject:label];
		[item setTarget:self];
		[item setState:i == _segmentedControl.selectedSegment ? NSControlStateValueOn : NSControlStateValueOff];
	}
}

@end
