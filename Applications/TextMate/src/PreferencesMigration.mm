#import "PreferencesMigration.h"

NSString* const kUserDefaultsMigratedFromMacromatesKey = @"MigratedFromMacromates";
NSString* const kLegacyPreferencesDomain                = @"com.macromates.TextMate";

void MigratePreferencesDomain (NSString* sourceDomain, NSString* destinationDomain)
{
	if(!sourceDomain || !destinationDomain)
		return;

	NSUserDefaults* userDefaults = NSUserDefaults.standardUserDefaults;

	NSDictionary* destination = [userDefaults persistentDomainForName:destinationDomain] ?: @{ };
	if([destination[kUserDefaultsMigratedFromMacromatesKey] boolValue])
		return; // already migrated -- run exactly once

	NSDictionary* source = [userDefaults persistentDomainForName:sourceDomain] ?: @{ };

	NSMutableDictionary* merged = [destination mutableCopy];
	for(NSString* key in source)
	{
		if(!merged[key])
			merged[key] = source[key]; // never clobber an existing destination value
	}
	merged[kUserDefaultsMigratedFromMacromatesKey] = @YES;

	[userDefaults setPersistentDomain:merged forName:destinationDomain];
}

void MigrateLegacyPreferencesIfNeeded ()
{
	NSString* destinationDomain = NSBundle.mainBundle.bundleIdentifier;
	if(!destinationDomain)
		return;
	MigratePreferencesDomain(kLegacyPreferencesDomain, destinationDomain);
}
