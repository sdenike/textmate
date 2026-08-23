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

// Skips the write when that value is already stored. settings_t::set is two
// full read_file parses plus a NON-ATOMIC truncate-and-rewrite of the user's
// Global.tmProperties (settings.cc:444), so a redundant call is a redundant
// window in which a crash leaves that file empty -- taking font, theme, soft
// wrap and every other global setting with it, not just this key. Its callers
// commit on end-editing and can legitimately fire more than once for a single
// edit (Return, then the caret leaving the field, then the window closing);
// this is what makes that overlap free.
void TMSettingsSetString (NSString* key, NSString* value)
{
	std::string const settingsKey = to_s(key);
	std::string const newValue    = to_s(value ?: @"");
	if(settings_t::raw_get(settingsKey) == newValue)
		return;
	settings_t::set(settingsKey, newValue);
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
