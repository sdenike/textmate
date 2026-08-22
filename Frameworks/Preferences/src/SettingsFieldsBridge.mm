// Frameworks/Preferences/src/SettingsFieldsBridge.mm
#import "SettingsFieldsBridge.h"
#import <settings/settings.h>
#import <ns/ns.h>
#import <OakFoundation/NSString Additions.h>

NSString* TMSettingsExcludeKey (void) { return [NSString stringWithCxxString:kSettingsExcludeKey]; }
NSString* TMSettingsIncludeKey (void) { return [NSString stringWithCxxString:kSettingsIncludeKey]; }
NSString* TMSettingsBinaryKey  (void) { return [NSString stringWithCxxString:kSettingsBinaryKey]; }

NSString* TMSettingsGetString (NSString* key)
{
	return [NSString stringWithCxxString:settings_t::raw_get(to_s(key))] ?: @"";
}

void TMSettingsSetString (NSString* key, NSString* value)
{
	settings_t::set(to_s(key), to_s(value ?: @""));
}

NSInteger TMFileBrowserPlacementTagForValue (NSString* value)
{
	return [value isEqualToString:@"right"] ? 1 : 0;
}

NSString* TMFileBrowserPlacementValueForTag (NSInteger tag)
{
	return tag == 1 ? @"right" : @"left";
}

NSInteger TMHTMLOutputPlacementTagForValue (NSString* value)
{
	if([value isEqualToString:@"right"])
		return 1;
	if([value isEqualToString:@"window"])
		return 2;
	return 0;
}

NSString* TMHTMLOutputPlacementValueForTag (NSInteger tag)
{
	if(tag == 1)
		return @"right";
	if(tag == 2)
		return @"window";
	return @"bottom";
}
