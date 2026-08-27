// Frameworks/Preferences/tests/t_terminal_support.mm
#import "../src/TerminalSupportBridge.h"

// Wrapped in namespace t_terminal_support by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.
//
// OAK_ASSERT rather than OAK_ASSERT_EQ on TMInstallPathItem*/NSString*
// comparisons: there is no to_s overload for either, so OAK_ASSERT_EQ falls
// through to the generic to_s(_T const&), which range-fors over the pointer
// and aborts the whole runner with SIGABRT when the assertion fails instead of
// reporting which one did.

void test_no_current_path_is_the_two_standard_entries_then_separator_then_other ()
{
	NSArray<TMInstallPathItem*>* items = TMTerminalInstallPathItems(nil);
	OAK_ASSERT_EQ(items.count, 4);
	OAK_ASSERT([items[0].title isEqualToString:@"/usr/local/bin/mate"]);
	OAK_ASSERT(!items[0].isSeparator && !items[0].isOther);
	OAK_ASSERT([items[1].title isEqualToString:@"~/bin/mate"]);
	OAK_ASSERT(!items[1].isSeparator && !items[1].isOther);
	OAK_ASSERT(items[2].isSeparator);
	OAK_ASSERT([items[3].title isEqualToString:@"Other…"]);
	OAK_ASSERT(items[3].isOther);
}

// A current path that IS one of the two standard ones must not duplicate --
// selecting "/usr/local/bin/mate" from the popup and asking again must not
// grow a second entry for the same path.
void test_current_path_matching_a_standard_entry_is_not_duplicated ()
{
	OAK_ASSERT_EQ(TMTerminalInstallPathItems(@"/usr/local/bin/mate").count, 4);
	OAK_ASSERT_EQ(TMTerminalInstallPathItems(@"~/bin/mate").count, 4);
}

// A genuinely custom path sorts first, ahead of both standard entries.
void test_custom_current_path_sorts_first ()
{
	NSArray<TMInstallPathItem*>* items = TMTerminalInstallPathItems(@"~/Applications/mate");
	OAK_ASSERT_EQ(items.count, 5);
	OAK_ASSERT([items[0].title isEqualToString:@"~/Applications/mate"]);
	OAK_ASSERT(!items[0].isSeparator && !items[0].isOther);
	OAK_ASSERT([items[1].title isEqualToString:@"/usr/local/bin/mate"]);
	OAK_ASSERT([items[2].title isEqualToString:@"~/bin/mate"]);
	OAK_ASSERT(items[3].isSeparator);
	OAK_ASSERT(items[4].isOther);
}

// The capture is \S+, not [\d.]+ -- a suffixed fork version like
// "3.0.0-revived.26" must come back whole, not truncated at the hyphen (the
// truncation is what let a fork mate collide with upstream's own 2.13.3).
void test_suffixed_version_survives_whole ()
{
	NSString* version = TMParseMateVersion(@"mate 3.0.0-revived.26 (Aug 27 2026)");
	OAK_ASSERT(version != nil);
	OAK_ASSERT([version isEqualToString:@"3.0.0-revived.26"]);
}

void test_bare_upstream_style_version_still_parses ()
{
	NSString* version = TMParseMateVersion(@"mate 2.13.3 (Oct 12 2021)");
	OAK_ASSERT(version != nil);
	OAK_ASSERT([version isEqualToString:@"2.13.3"]);
}

// io::exec hands back NULL_STR (or any other unrelated output) when it
// couldn't run the binary at all -- neither starts with "mate ", and both
// must come back nil rather than some bogus capture.
void test_output_not_starting_with_mate_is_nil ()
{
	OAK_ASSERT(TMParseMateVersion(@"") == nil);
	OAK_ASSERT(TMParseMateVersion(@"command not found") == nil);
}
