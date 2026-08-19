#import "../src/SetupAssistant/SetupAssistantTypes.h"
#import "../src/SetupAssistant/SetupAssistantGating.h"

// This file is wrapped in `namespace t_setup_assistant { … }` by bin/gen_test,
// so it cannot declare an Objective-C class. Everything under test is either a
// free function or a class method taking its inputs explicitly.

void test_theme_choice_carries_its_values ()
{
	NSDictionary* colors = @{ TMThemeColorBackground: NSColor.blackColor, TMThemeColorForeground: NSColor.whiteColor };
	TMThemeChoice* choice = [TMThemeChoice choiceWithName:@"Twilight" identifier:@"766026CB-703D-4610-B070-8DE07D967C5F" appearance:@"dark" colors:colors];

	// to_s(NSString*) lives in Frameworks/ns, which TextMate_test does not link.
	// Compare with isEqualToString:, exactly as t_preferences_migration.mm does.
	OAK_ASSERT([choice.name isEqualToString:@"Twilight"]);
	OAK_ASSERT([choice.appearance isEqualToString:@"dark"]);
	OAK_ASSERT_EQ(choice.colors.count, 2);
	OAK_ASSERT(choice.colors[TMThemeColorBackground] == NSColor.blackColor);
}

void test_bundle_choice_carries_its_values ()
{
	TMBundleChoice* choice = [TMBundleChoice choiceWithName:@"Ruby" identifier:@"E4B4E2FF-C8EE-44B2-A6E0-A5B2E1F0C1D2" category:@"Languages" installed:NO recommended:YES];

	OAK_ASSERT([choice.name isEqualToString:@"Ruby"]);
	OAK_ASSERT([choice.category isEqualToString:@"Languages"]);
	OAK_ASSERT_EQ(choice.installed, false);
	OAK_ASSERT_EQ(choice.recommended, true);
}

void test_semantic_class_maps_to_appearance ()
{
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.dark.twilight") isEqualToString:@"dark"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.light.mac_classic") isEqualToString:@"light"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"theme.something") isEqualToString:@"unspecified"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(@"") isEqualToString:@"unspecified"]);
	OAK_ASSERT([TMThemeAppearanceForSemanticClass(nil) isEqualToString:@"unspecified"]);
}

// The regression this exists to prevent: replacing rather than merging
// resurrects every bundle suggestion the user has ever declined.
void test_never_suggest_merges_rather_than_replaces ()
{
	NSArray* merged = TMMergeNeverSuggestIdentifiers(@[ @"A", @"B" ], @[ @"B", @"C" ]);
	OAK_ASSERT_EQ(merged.count, 3);
	OAK_ASSERT(([[NSSet setWithArray:merged] isEqualToSet:[NSSet setWithArray:@[ @"A", @"B", @"C" ]]]));
}

void test_never_suggest_tolerates_empty_input ()
{
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(nil, nil).count, 0);
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(@[ @"A" ], nil).count, 1);
	OAK_ASSERT_EQ(TMMergeNeverSuggestIdentifiers(nil, @[ @"A" ]).count, 1);
}

// Each test uses its own throwaway suite name and removes it before and after,
// so a prior interrupted run never leaks state and the developer's real
// preferences are never touched. Tests in this target run in parallel by
// default; per-test domains are what makes that safe.

static NSUserDefaults* fresh_defaults (NSString* suite)
{
	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
	return [[NSUserDefaults alloc] initWithSuiteName:suite];
}

void test_assistant_runs_when_key_absent ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Absent";
	NSUserDefaults* defaults = fresh_defaults(suite);

	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), true);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

void test_assistant_does_not_run_once_marked ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Marked";
	NSUserDefaults* defaults = fresh_defaults(suite);

	TMSetupAssistantMarkAsRun(defaults);
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), false);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

void test_marking_is_idempotent ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Twice";
	NSUserDefaults* defaults = fresh_defaults(suite);

	TMSetupAssistantMarkAsRun(defaults);
	TMSetupAssistantMarkAsRun(defaults);
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), false);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}

// The old bundle-prompt key must not suppress the assistant. Every existing
// user has it set, and they are exactly the audience the appearance step is
// aimed at.
void test_legacy_bundle_prompt_key_does_not_suppress_the_assistant ()
{
	NSString* suite = @"com.macromates.TextMate.SetupAssistantTest.Legacy";
	NSUserDefaults* defaults = fresh_defaults(suite);

	[defaults setBool:YES forKey:@"didPromptForDefaultBundles"];
	OAK_ASSERT_EQ(TMSetupAssistantShouldRunAtLaunch(defaults), true);

	[NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
}
