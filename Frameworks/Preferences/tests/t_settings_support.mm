// Frameworks/Preferences/tests/t_settings_support.mm
#import "../src/SettingsSupportBridge.h"

// Wrapped in namespace t_settings_support by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.

void test_checking_wins_over_everything ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(YES, @"some error", @"5 minutes ago") isEqualToString:@"Checking…"]);
	OAK_ASSERT([TMSettingsLastCheckDescription(YES, nil, nil) isEqualToString:@"Checking…"]);
}

void test_error_wins_over_date ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, @"Network unreachable", @"5 minutes ago") isEqualToString:@"Network unreachable"]);
}

void test_date_used_when_no_error ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, nil, @"5 minutes ago") isEqualToString:@"5 minutes ago"]);
}

void test_never_when_nothing_known ()
{
	OAK_ASSERT([TMSettingsLastCheckDescription(NO, nil, nil) isEqualToString:@"Never"]);
}
