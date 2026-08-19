// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm
#import "SetupAssistantWindowController.h"
#import "SetupAssistantGating.h"

@interface SetupAssistantWindowController () <NSWindowDelegate>
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
		window.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
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
@end
