// Frameworks/Preferences/tests/t_settings_bundles.mm
#import "../src/SettingsBundlesBridge.h"

// Wrapped in namespace t_settings_bundles by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.
//
// OAK_ASSERT rather than OAK_ASSERT_EQ on every TMBundleRow*/NSString*
// comparison: there is no to_s overload for either, so OAK_ASSERT_EQ falls
// through to the generic to_s(_T const&), which range-fors over the pointer
// and aborts the whole runner with SIGABRT when the assertion fails instead
// of reporting which one did.

static TMBundleRow* row (NSString* name, NSString* category, BOOL isMandatory, BOOL isInstalled, BOOL isEditedShipped, NSString* downloadURLString, NSString* path)
{
	return [[TMBundleRow alloc] initWithIdentifier:name
	                                           name:name
	                                       category:category
	                               webLinkURLString:nil
	                                        updated:nil
	                                    textSummary:@""
	                                   installState:TMBundleInstallStateOff
	                         installedToggleEnabled:YES
	                                    isMandatory:isMandatory
	                                    isInstalled:isInstalled
	                              autoUpdateEnabled:NO
	                                            ref:nil
	                              downloadURLString:downloadURLString
	                                           path:path
	                                isEditedShipped:isEditedShipped];
}

// ================
// = Filtering
// ================

void test_filter_matches_substring_case_and_diacritic_insensitively ()
{
	NSArray<TMBundleRow*>* rows = @[
		row(@"Ruby", @"Languages", NO, NO, NO, nil, nil),
		row(@"Über", @"Languages", NO, NO, NO, nil, nil),
		row(@"HTML", @"Markup", NO, NO, NO, nil, nil),
	];

	OAK_ASSERT_EQ(TMBundlesFilterRows(rows, @"rub", nil).count, 1);
	OAK_ASSERT([TMBundlesFilterRows(rows, @"rub", nil)[0].name isEqualToString:@"Ruby"]);
	// "uber" (no diacritic, different case) must still find "Über".
	OAK_ASSERT_EQ(TMBundlesFilterRows(rows, @"uber", nil).count, 1);
	OAK_ASSERT([TMBundlesFilterRows(rows, @"uber", nil)[0].name isEqualToString:@"Über"]);
}

void test_empty_search_text_matches_everything ()
{
	NSArray<TMBundleRow*>* rows = @[ row(@"Ruby", @"Languages", NO, NO, NO, nil, nil), row(@"HTML", @"Markup", NO, NO, NO, nil, nil) ];
	OAK_ASSERT_EQ(TMBundlesFilterRows(rows, @"", nil).count, 2);
}

void test_nil_category_matches_every_category ()
{
	NSArray<TMBundleRow*>* rows = @[ row(@"Ruby", @"Languages", NO, NO, NO, nil, nil), row(@"HTML", @"Markup", NO, NO, NO, nil, nil) ];
	OAK_ASSERT_EQ(TMBundlesFilterRows(rows, @"", nil).count, 2);
}

void test_category_filters_to_exact_match_only ()
{
	NSArray<TMBundleRow*>* rows = @[ row(@"Ruby", @"Languages", NO, NO, NO, nil, nil), row(@"HTML", @"Markup", NO, NO, NO, nil, nil) ];
	NSArray<TMBundleRow*>* res = TMBundlesFilterRows(rows, @"", @"Languages");
	OAK_ASSERT_EQ(res.count, 1);
	OAK_ASSERT([res[0].name isEqualToString:@"Ruby"]);
}

// A bundle with no category (nil) must not match an active category filter --
// it is not "in" any category, including one it happens to be compared against.
void test_category_filter_excludes_rows_with_no_category ()
{
	NSArray<TMBundleRow*>* rows = @[ row(@"Orphan", nil, NO, NO, NO, nil, nil) ];
	OAK_ASSERT_EQ(TMBundlesFilterRows(rows, @"", @"Languages").count, 0);
}

// Both predicates are AND-ed: a name match in the wrong category is excluded.
void test_search_and_category_combine_with_and ()
{
	NSArray<TMBundleRow*>* rows = @[
		row(@"Ruby", @"Languages", NO, NO, NO, nil, nil),
		row(@"Ruby on Rails", @"Web", NO, NO, NO, nil, nil),
	];
	NSArray<TMBundleRow*>* res = TMBundlesFilterRows(rows, @"ruby", @"Web");
	OAK_ASSERT_EQ(res.count, 1);
	OAK_ASSERT([res[0].name isEqualToString:@"Ruby on Rails"]);
}

// ================
// = Menu enablement
// ================

// Mandatory bundles disable everything except the two rules that do not key
// off mandatory at all (Copy URL, Reveal in Finder) -- matching
// -populateMenu:forBundle: literally: revertEnabled only reads isEditedShipped,
// with no separate !mandatory check, because bundleIsEditedShippedDefault:
// already returns NO for a mandatory bundle at the call site.
void test_mandatory_bundle_disables_edit_actions ()
{
	TMBundleRow* r = row(@"Bundle Support", @"Support", YES, YES, NO, @"https://example.com", @"/path");
	TMBundleMenuEnablement e = TMBundleMenuEnablementForRow(r);
	OAK_ASSERT(!e.autoUpdateEnabled);
	OAK_ASSERT(!e.changeRefEnabled);
	OAK_ASSERT(!e.editEnabled);
	OAK_ASSERT(!e.uninstallEnabled);
	OAK_ASSERT(!e.removeEnabled);
	OAK_ASSERT(!e.revertEnabled);
	OAK_ASSERT(e.copyURLEnabled);
	OAK_ASSERT(e.revealEnabled);
}

void test_uninstall_requires_non_mandatory_and_installed ()
{
	OAK_ASSERT(TMBundleMenuEnablementForRow(row(@"A", nil, NO, YES, NO, nil, nil)).uninstallEnabled);
	OAK_ASSERT(!TMBundleMenuEnablementForRow(row(@"A", nil, NO, NO, NO, nil, nil)).uninstallEnabled);
	OAK_ASSERT(!TMBundleMenuEnablementForRow(row(@"A", nil, YES, YES, NO, nil, nil)).uninstallEnabled);
}

void test_revert_tracks_isEditedShipped_only ()
{
	OAK_ASSERT(TMBundleMenuEnablementForRow(row(@"A", nil, NO, NO, YES, nil, nil)).revertEnabled);
	OAK_ASSERT(!TMBundleMenuEnablementForRow(row(@"A", nil, NO, NO, NO, nil, nil)).revertEnabled);
}

void test_copy_url_and_reveal_track_presence_of_the_string ()
{
	TMBundleMenuEnablement withBoth = TMBundleMenuEnablementForRow(row(@"A", nil, NO, NO, NO, @"https://example.com", @"/path"));
	OAK_ASSERT(withBoth.copyURLEnabled);
	OAK_ASSERT(withBoth.revealEnabled);

	TMBundleMenuEnablement withNeither = TMBundleMenuEnablementForRow(row(@"A", nil, NO, NO, NO, nil, nil));
	OAK_ASSERT(!withNeither.copyURLEnabled);
	OAK_ASSERT(!withNeither.revealEnabled);
}

void test_disable_bundle_suggestions_key_name ()
{
	OAK_ASSERT([kUserDefaultsDisableBundleSuggestionsKey isEqualToString:@"disableBundleSuggestions"]);
}
