#import "../src/PreferencesMigration.h"

// Exercises MigratePreferencesDomain() directly against throwaway domain
// names -- never the real com.macromates.TextMate / com.shelbydenike.TextMate
// domains, so running this suite can never touch a developer's actual
// TextMate preferences. Each test uses its own dedicated pair of domain
// names (tests run in parallel by default -- bin/build only forces
// --no-parallel for a fixed list of frameworks that doesn't include this
// one) and removes them both before and after, so a prior interrupted run
// or a concurrently running test never leaks state across tests.

static NSString* const kSource1 = @"com.macromates.TextMate.PreferencesMigrationTest.Source1";
static NSString* const kDest1   = @"com.macromates.TextMate.PreferencesMigrationTest.Dest1";

static NSString* const kSource2 = @"com.macromates.TextMate.PreferencesMigrationTest.Source2";
static NSString* const kDest2   = @"com.macromates.TextMate.PreferencesMigrationTest.Dest2";

static NSString* const kSource3 = @"com.macromates.TextMate.PreferencesMigrationTest.Source3";
static NSString* const kDest3   = @"com.macromates.TextMate.PreferencesMigrationTest.Dest3";

static NSString* const kSource4 = @"com.macromates.TextMate.PreferencesMigrationTest.Source4";
static NSString* const kDest4   = @"com.macromates.TextMate.PreferencesMigrationTest.Dest4";

static NSString* const kShared5 = @"com.macromates.TextMate.PreferencesMigrationTest.Shared5";

static void RemoveDomain (NSString* name)
{
	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:name];
}

// ---------------------------------------------------------------------------
// Populated source + empty destination → every key is copied.
// ---------------------------------------------------------------------------

void test_copies_all_keys_into_empty_destination ()
{
	RemoveDomain(kSource1);
	RemoveDomain(kDest1);

	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ @"theme": @"Dark", @"fontSize": @14 }) forName:kSource1];

	MigratePreferencesDomain(kSource1, kDest1);

	NSDictionary* dest = [NSUserDefaults.standardUserDefaults persistentDomainForName:kDest1];
	OAK_ASSERT(dest != nil);
	OAK_ASSERT([dest[@"theme"] isEqualToString:@"Dark"]);
	OAK_ASSERT_EQ([dest[@"fontSize"] integerValue], 14);
	OAK_ASSERT_EQ([dest[kUserDefaultsMigratedFromMacromatesKey] boolValue], YES);

	// Source is read, never deleted -- an install can still be rolled back.
	NSDictionary* source = [NSUserDefaults.standardUserDefaults persistentDomainForName:kSource1];
	OAK_ASSERT([source[@"theme"] isEqualToString:@"Dark"]);

	RemoveDomain(kSource1);
	RemoveDomain(kDest1);
}

// ---------------------------------------------------------------------------
// A key already present in the destination is left alone; a key the
// destination lacks still gets copied in the same pass.
// ---------------------------------------------------------------------------

void test_never_clobbers_existing_destination_value ()
{
	RemoveDomain(kSource2);
	RemoveDomain(kDest2);

	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ @"theme": @"Dark", @"fontSize": @14 }) forName:kSource2];
	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ @"theme": @"Light" }) forName:kDest2];

	MigratePreferencesDomain(kSource2, kDest2);

	NSDictionary* dest = [NSUserDefaults.standardUserDefaults persistentDomainForName:kDest2];
	OAK_ASSERT([dest[@"theme"] isEqualToString:@"Light"]);   // untouched -- user's newer value wins
	OAK_ASSERT_EQ([dest[@"fontSize"] integerValue], 14);     // still copied -- destination never had it
	OAK_ASSERT_EQ([dest[kUserDefaultsMigratedFromMacromatesKey] boolValue], YES);

	RemoveDomain(kSource2);
	RemoveDomain(kDest2);
}

// ---------------------------------------------------------------------------
// Once the marker is set, a second call touches nothing at all -- not even
// keys the destination is missing.
// ---------------------------------------------------------------------------

void test_marker_makes_second_run_a_noop ()
{
	RemoveDomain(kSource3);
	RemoveDomain(kDest3);

	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ @"theme": @"Dark" }) forName:kSource3];

	MigratePreferencesDomain(kSource3, kDest3);
	OAK_ASSERT_EQ([[NSUserDefaults.standardUserDefaults persistentDomainForName:kDest3][@"theme"] isEqualToString:@"Dark"], YES);

	// Simulate the user clearing the migrated value; marker stays set.
	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ kUserDefaultsMigratedFromMacromatesKey: @YES }) forName:kDest3];

	MigratePreferencesDomain(kSource3, kDest3);

	NSDictionary* dest = [NSUserDefaults.standardUserDefaults persistentDomainForName:kDest3];
	OAK_ASSERT(dest[@"theme"] == nil); // second run never re-copied it

	RemoveDomain(kSource3);
	RemoveDomain(kDest3);
}

// ---------------------------------------------------------------------------
// A source domain with nothing persisted (fresh install) is a normal no-op,
// not an error -- destination ends up with only the marker.
// ---------------------------------------------------------------------------

void test_absent_source_is_clean_noop ()
{
	RemoveDomain(kSource4);
	RemoveDomain(kDest4);

	MigratePreferencesDomain(kSource4, kDest4);

	NSDictionary* dest = [NSUserDefaults.standardUserDefaults persistentDomainForName:kDest4];
	OAK_ASSERT(dest != nil);
	OAK_ASSERT_EQ(dest.count, 1u);
	OAK_ASSERT_EQ([dest[kUserDefaultsMigratedFromMacromatesKey] boolValue], YES);
	OAK_ASSERT([NSUserDefaults.standardUserDefaults persistentDomainForName:kSource4] == nil);

	RemoveDomain(kDest4);
}

// ---------------------------------------------------------------------------
// source == destination is the state this ships in today, since
// CFBundleIdentifier has not changed yet. Must not corrupt or duplicate
// anything -- only the marker key is added.
// ---------------------------------------------------------------------------

void test_source_equals_destination_is_a_safe_noop ()
{
	RemoveDomain(kShared5);

	[NSUserDefaults.standardUserDefaults setPersistentDomain:(@{ @"theme": @"Dark", @"fontSize": @14 }) forName:kShared5];

	MigratePreferencesDomain(kShared5, kShared5);

	NSDictionary* merged = [NSUserDefaults.standardUserDefaults persistentDomainForName:kShared5];
	OAK_ASSERT_EQ(merged.count, 3u); // theme, fontSize, marker -- nothing duplicated or lost
	OAK_ASSERT([merged[@"theme"] isEqualToString:@"Dark"]);
	OAK_ASSERT_EQ([merged[@"fontSize"] integerValue], 14);
	OAK_ASSERT_EQ([merged[kUserDefaultsMigratedFromMacromatesKey] boolValue], YES);

	// Second call (marker now set) must also be inert.
	MigratePreferencesDomain(kShared5, kShared5);
	NSDictionary* again = [NSUserDefaults.standardUserDefaults persistentDomainForName:kShared5];
	OAK_ASSERT_EQ(again.count, 3u);
	OAK_ASSERT([again[@"theme"] isEqualToString:@"Dark"]);
	OAK_ASSERT_EQ([again[@"fontSize"] integerValue], 14);

	RemoveDomain(kShared5);
}
