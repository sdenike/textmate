// Frameworks/Preferences/src/SettingsSupportBridge.mm
#import "SettingsSupportBridge.h"

NSString* TMSettingsLastCheckDescription (BOOL isChecking, NSString* errorString, NSString* relativeDate)
{
	if(isChecking)
		return @"Checking…";
	return errorString ?: relativeDate ?: @"Never";
}
