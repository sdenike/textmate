// Frameworks/Preferences/src/SettingsSupportBridge.h
#import <Foundation/Foundation.h>

// The text shown for "Last check:". Extracted from SoftwareUpdatePreferences's
// -lastCheckDescription so the precedence can be tested: checking beats an
// error, an error beats a date, and "Never" is the floor.
extern NSString* TMSettingsLastCheckDescription (BOOL isChecking, NSString* errorString, NSString* relativeDate);
