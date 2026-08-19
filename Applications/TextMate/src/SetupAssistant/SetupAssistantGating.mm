// Applications/TextMate/src/SetupAssistant/SetupAssistantGating.mm
#import "SetupAssistantGating.h"

NSString* const kUserDefaultsDidRunSetupAssistantKey = @"didRunSetupAssistant";

BOOL TMSetupAssistantShouldRunAtLaunch (NSUserDefaults* defaults)
{
	return ![defaults boolForKey:kUserDefaultsDidRunSetupAssistantKey];
}

void TMSetupAssistantMarkAsRun (NSUserDefaults* defaults)
{
	[defaults setBool:YES forKey:kUserDefaultsDidRunSetupAssistantKey];
}
