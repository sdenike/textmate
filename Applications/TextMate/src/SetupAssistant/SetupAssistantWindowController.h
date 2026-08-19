// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.h
#import <Cocoa/Cocoa.h>

@interface SetupAssistantWindowController : NSWindowController
+ (instancetype)sharedInstance;

// Runs the assistant app-modally and returns when it is finished or skipped.
// Both paths mark the assistant as run.
- (void)runModal;
@end
