// Frameworks/Preferences/src/SettingsFieldsBridge.mm
#import "SettingsFieldsBridge.h"
#import <settings/settings.h>
#import <ns/ns.h>
#import <text/ctype.h>
#import <OakFoundation/NSString Additions.h>

NSString* TMSettingsExcludeKey     (void) { return [NSString stringWithCxxString:kSettingsExcludeKey];     }
NSString* TMSettingsIncludeKey     (void) { return [NSString stringWithCxxString:kSettingsIncludeKey];     }
NSString* TMSettingsBinaryKey      (void) { return [NSString stringWithCxxString:kSettingsBinaryKey];      }
NSString* TMSettingsEncodingKey    (void) { return [NSString stringWithCxxString:kSettingsEncodingKey];    }
NSString* TMSettingsLineEndingsKey (void) { return [NSString stringWithCxxString:kSettingsLineEndingsKey]; }
NSString* TMSettingsFileTypeKey    (void) { return [NSString stringWithCxxString:kSettingsFileTypeKey];    }

NSString* TMSettingsGetString (NSString* key)
{
	return [NSString stringWithCxxString:settings_t::raw_get(to_s(key))] ?: @"";
}

NSString* TMSettingsGetScopedString (NSString* key, NSString* scope)
{
	return [NSString stringWithCxxString:settings_t::raw_get(to_s(key), to_s(scope))] ?: @"";
}

// Same skip-the-redundant-write rule as TMSettingsSetString, compared within
// the same scope: the popups commit on selection, and picking the entry that
// is already stored must not rewrite Global.tmProperties.
void TMSettingsSetScopedString (NSString* key, NSString* value, NSString* scope)
{
	std::string const settingsKey = to_s(key);
	std::string const section     = to_s(scope);
	std::string const newValue    = to_s(value); // nil -> NULL_STR, deliberately
	if(settings_t::raw_get(settingsKey, section) == newValue)
		return;
	settings_t::set(settingsKey, newValue, section);
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

NSInteger TMLineEndingsTagForValue (NSString* value)
{
	if([value isEqualToString:@"\\r"])
		return 1;
	if([value isEqualToString:@"\\r\\n"])
		return 2;
	return 0;
}

NSString* TMLineEndingsValueForTag (NSInteger tag)
{
	if(tag == 1)
		return @"\\r";
	if(tag == 2)
		return @"\\r\\n";
	return @"\\n";
}

@implementation TMFileTypeItem
- (instancetype)initWithName:(NSString*)name scope:(NSString*)scope hidden:(BOOL)hidden
{
	if(self = [super init])
	{
		_name   = name;
		_scope  = scope;
		_hidden = hidden;
	}
	return self;
}
@end

NSArray<TMFileTypeItem*>* TMFileTypeItemsSorted (NSArray<TMFileTypeItem*>* candidates)
{
	// std::multimap<…, text::less_t> for the ordering, exactly as the AppKit
	// pane had it: text::less_t is a natural, case-insensitive compare, and a
	// multimap keeps two grammars sharing a name in the order they arrived.
	std::multimap<std::string, TMFileTypeItem*, text::less_t> grammars;
	for(TMFileTypeItem* item in candidates)
	{
		if(!item.hidden && item.scope)
			grammars.emplace(to_s(item.name), item);
	}

	NSMutableArray<TMFileTypeItem*>* res = [NSMutableArray arrayWithCapacity:grammars.size()];
	for(auto const& pair : grammars)
		[res addObject:pair.second];
	return res;
}
