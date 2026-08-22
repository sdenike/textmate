#import "../src/SettingsFieldsBridge.h"
#import <settings/settings.h>
#import <test/jail.h>

// Wrapped in namespace t_settings_fields by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.

void test_file_browser_placement_tag_for_value ()
{
	OAK_ASSERT_EQ(TMFileBrowserPlacementTagForValue(@"left"),  0);
	OAK_ASSERT_EQ(TMFileBrowserPlacementTagForValue(@"right"), 1);
	// Unrecognised or missing values fall back to the first entry, same rule
	// as SettingsChannel.from(storedValue:) on the Swift side.
	OAK_ASSERT_EQ(TMFileBrowserPlacementTagForValue(@"bogus"), 0);
	OAK_ASSERT_EQ(TMFileBrowserPlacementTagForValue(nil),      0);
}

void test_file_browser_placement_value_for_tag ()
{
	OAK_ASSERT([TMFileBrowserPlacementValueForTag(0) isEqualToString:@"left"]);
	OAK_ASSERT([TMFileBrowserPlacementValueForTag(1) isEqualToString:@"right"]);
	OAK_ASSERT([TMFileBrowserPlacementValueForTag(9) isEqualToString:@"left"]);
}

void test_html_output_placement_tag_for_value ()
{
	OAK_ASSERT_EQ(TMHTMLOutputPlacementTagForValue(@"bottom"), 0);
	OAK_ASSERT_EQ(TMHTMLOutputPlacementTagForValue(@"right"),  1);
	OAK_ASSERT_EQ(TMHTMLOutputPlacementTagForValue(@"window"), 2);
	OAK_ASSERT_EQ(TMHTMLOutputPlacementTagForValue(@"bogus"),  0);
	OAK_ASSERT_EQ(TMHTMLOutputPlacementTagForValue(nil),       0);
}

void test_html_output_placement_value_for_tag ()
{
	OAK_ASSERT([TMHTMLOutputPlacementValueForTag(0) isEqualToString:@"bottom"]);
	OAK_ASSERT([TMHTMLOutputPlacementValueForTag(1) isEqualToString:@"right"]);
	OAK_ASSERT([TMHTMLOutputPlacementValueForTag(2) isEqualToString:@"window"]);
	OAK_ASSERT([TMHTMLOutputPlacementValueForTag(9) isEqualToString:@"bottom"]);
}

void test_settings_key_names ()
{
	OAK_ASSERT([TMSettingsExcludeKey() isEqualToString:@"exclude"]);
	OAK_ASSERT([TMSettingsIncludeKey() isEqualToString:@"include"]);
	OAK_ASSERT([TMSettingsBinaryKey()  isEqualToString:@"binary"]);
}

void test_settings_string_round_trip ()
{
	test::jail_t jail;
	settings_t::set_default_settings_path(jail.path("default"));
	settings_t::set_global_settings_path(jail.path("global"));

	// Never nil for a key that has not been set -- a SwiftUI TextField bound
	// straight to this would crash on first launch otherwise.
	OAK_ASSERT([TMSettingsGetString(TMSettingsExcludeKey()) isEqualToString:@""]);

	TMSettingsSetString(TMSettingsExcludeKey(), @"*.o");
	OAK_ASSERT([TMSettingsGetString(TMSettingsExcludeKey()) isEqualToString:@"*.o"]);

	TMSettingsSetString(TMSettingsIncludeKey(), @"*.md");
	OAK_ASSERT([TMSettingsGetString(TMSettingsIncludeKey()) isEqualToString:@"*.md"]);

	TMSettingsSetString(TMSettingsBinaryKey(), @"*.png");
	OAK_ASSERT([TMSettingsGetString(TMSettingsBinaryKey()) isEqualToString:@"*.png"]);

	// Round trip again with a different value confirms this is a real
	// write/read through settings_t, not a value cached at the first call.
	TMSettingsSetString(TMSettingsExcludeKey(), @"*.o *.pyc");
	OAK_ASSERT([TMSettingsGetString(TMSettingsExcludeKey()) isEqualToString:@"*.o *.pyc"]);
}
