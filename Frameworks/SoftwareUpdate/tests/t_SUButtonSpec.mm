#import "../src/SUButtonSpec.h"

// Wrapped in namespace t_SUButtonSpec by bin/gen_test, so no Objective-C
// class may be declared here. OAK_ASSERT rather than OAK_ASSERT_EQ on
// SUButtonSpec*/NSString* comparisons: there is no to_s overload for either,
// and a failed OAK_ASSERT_EQ there would abort the whole runner instead of
// reporting which assertion failed (see t_terminal_support.mm for the same
// rule).

void test_update_available_manual_check_is_download_and_cancel ()
{
	NSArray<SUButtonSpec*>* buttons = SUButtonsForVersionCheck(NSOrderedAscending, NO, NO, @"3.0.0-revived.9");
	OAK_ASSERT_EQ(buttons.count, 2);
	OAK_ASSERT([buttons[0].title isEqualToString:@"Download"]);
	OAK_ASSERT(buttons[0].enabled && buttons[0].isDefault && !buttons[0].isCancel);
	OAK_ASSERT([buttons[1].title isEqualToString:@"Cancel"]);
	OAK_ASSERT(buttons[1].enabled && !buttons[1].isDefault && buttons[1].isCancel);
}

// A background check titles the second button "Later" instead of "Cancel",
// but it still gets "\e" -- the old code set keyEquivalent on
// self.buttons.lastObject unconditionally, not only when the title was
// literally "Cancel".
void test_update_available_background_check_is_download_and_later_but_still_a_cancel_key ()
{
	NSArray<SUButtonSpec*>* buttons = SUButtonsForVersionCheck(NSOrderedAscending, YES, NO, @"3.0.0-revived.9");
	OAK_ASSERT_EQ(buttons.count, 2);
	OAK_ASSERT([buttons[1].title isEqualToString:@"Later"]);
	OAK_ASSERT(buttons[1].isCancel);
}

void test_up_to_date_without_redownload_is_a_single_ok ()
{
	NSArray<SUButtonSpec*>* buttons = SUButtonsForVersionCheck(NSOrderedSame, NO, NO, @"3.0.0-revived.9");
	OAK_ASSERT_EQ(buttons.count, 1);
	OAK_ASSERT([buttons[0].title isEqualToString:@"OK"]);
	OAK_ASSERT(buttons[0].isDefault && !buttons[0].isCancel);
}

// Redownload is an extra button, not a cancel -- Escape must still close the
// window via the panel's own handling, not this button.
void test_up_to_date_with_redownload_adds_a_non_cancel_second_button ()
{
	NSArray<SUButtonSpec*>* buttons = SUButtonsForVersionCheck(NSOrderedSame, NO, YES, @"3.0.0-revived.9");
	OAK_ASSERT_EQ(buttons.count, 2);
	OAK_ASSERT([buttons[0].title isEqualToString:@"OK"]);
	OAK_ASSERT([buttons[1].title isEqualToString:@"Redownload"]);
	OAK_ASSERT(!buttons[1].isCancel && !buttons[1].isDefault);
}

// A background check never reaches NSOrderedSame/NSOrderedDescending --
// presentUIForBackgroundCheck: returns early before building any UI -- so
// allowRedownload is the only flag that varies here; backgroundCheck is
// irrelevant to this branch and is not threaded through it.
void test_prerelease_offers_ok_and_downgrade_naming_the_remote_version ()
{
	NSArray<SUButtonSpec*>* buttons = SUButtonsForVersionCheck(NSOrderedDescending, NO, NO, @"3.0.0-revived.4");
	OAK_ASSERT_EQ(buttons.count, 2);
	OAK_ASSERT([buttons[0].title isEqualToString:@"OK"]);
	OAK_ASSERT(buttons[0].isDefault);
	OAK_ASSERT([buttons[1].title isEqualToString:@"Downgrade to 3.0.0-revived.4"]);
	OAK_ASSERT(!buttons[1].isCancel && !buttons[1].isDefault);
}
