// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm
#import "SetupAssistantWindowController.h"
#import "SetupAssistantGating.h"
#import "SetupAssistantTypes.h"
#import "TextMate-Swift.h"

@interface SetupAssistantWindowController () <NSWindowDelegate, TMSetupAssistantHost>
@end

@implementation SetupAssistantWindowController
+ (instancetype)sharedInstance
{
	static SetupAssistantWindowController* instance = [self new];
	return instance;
}

- (instancetype)init
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 460) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
	window.title = @"Setup Assistant";
	[window center];

	if(self = [super initWithWindow:window])
	{
		window.contentView = [SetupAssistantHostingController viewFor:self];
		// NSWindowController does not become its window's delegate on its own.
		// Without this, -windowWillClose: below never fires, -stopModal never
		// runs, and the title-bar close button leaves the app in a modal
		// session with no window -- unresponsive, with no way out but a
		// force-quit.
		window.delegate = self;
	}
	return self;
}

- (void)runModal
{
	// The Help menu item stays enabled while the assistant is open (nothing in
	// validateMenuItem: special-cases it), so this can be re-entered. Calling
	// runModalForWindow: a second time on the same window would start a nested
	// modal session; closing the window then fires windowWillClose: only once,
	// so stopModal unwinds just the inner session and the outer one is left
	// blocked forever with the window already ordered out -- an unresponsive
	// app with no window on screen. isVisible reflects AppKit's own bookkeeping
	// for exactly the span this class puts the window on screen (set only as a
	// side effect of runModalForWindow: below, cleared by the unconditional
	// orderOut: that follows it), so re-entering here can only ever observe
	// "currently in a session" or "not" -- there is no separate flag to leave
	// stuck on if a session ends abnormally.
	if(self.window.isVisible)
	{
		[self.window makeKeyAndOrderFront:self];
		return;
	}

	[self.window center];
	[NSApp runModalForWindow:self.window];
	[self.window orderOut:self];
	TMSetupAssistantMarkAsRun(NSUserDefaults.standardUserDefaults);
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	// Closing the window with the title-bar button must end the modal session,
	// or the app is left running a session with no window and stops responding
	// to everything.
	[NSApp stopModal];
}

- (NSArray<TMThemeChoice*>*)availableThemes                                   { return @[]; }
- (NSArray<TMBundleChoice*>*)availableBundles                                 { return @[]; }
- (NSString*)currentAppearance                                                { return nil; }
- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance        { return nil; }
- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance { }
- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest { }

- (void)finishWithSkip:(BOOL)skipped
{
	[NSApp stopModal];
}
@end
