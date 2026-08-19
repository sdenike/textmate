// Applications/TextMate/src/SetupAssistant/SetupAssistantGating.h
#import <Foundation/Foundation.h>

// Written once the assistant has been completed or skipped. It is a NEW key
// rather than a reuse of kUserDefaultsDidPromptForDefaultBundlesKey, and that
// is deliberate: every existing user already has the old key set, so reusing
// it would hide the assistant from precisely the people the appearance step
// exists for.
extern NSString* const kUserDefaultsDidRunSetupAssistantKey;

// Whether the assistant should be shown during applicationDidFinishLaunching:.
// The Help menu entry point does NOT consult this -- it always shows.
BOOL TMSetupAssistantShouldRunAtLaunch (NSUserDefaults* defaults);

// Records that the assistant has run. Called on completion AND on skip: a
// dismissed assistant must not reappear on the next launch.
void TMSetupAssistantMarkAsRun (NSUserDefaults* defaults);
