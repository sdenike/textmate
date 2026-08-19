#import "../src/SetupAssistant/SetupAssistantTypes.h"

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
