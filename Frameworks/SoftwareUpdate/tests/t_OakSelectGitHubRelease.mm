#import <SoftwareUpdate/SoftwareUpdate.h>

// Entries mirror the GitHub “list releases” schema (see the live capture from
// api.github.com/repos/textmatelives/textmate/releases): only tag_name,
// prerelease, and draft matter for selection.
static NSDictionary* release_entry (NSString* tag, BOOL prerelease = NO, BOOL draft = NO)
{
	return @{ @"tag_name": tag, @"prerelease": @(prerelease), @"draft": @(draft) };
}

void test_stable_only_list ()
{
	// Current live state: no prereleases published yet. The beta channel must
	// still resolve the newest stable.
	NSArray* releases = @[ release_entry(@"v2.1.1-undead"), release_entry(@"v2.1.0-undead") ];
	OAK_ASSERT_EQ(OakSelectGitHubRelease(releases, YES)[@"tag_name"], @"v2.1.1-undead");
	OAK_ASSERT_EQ(OakSelectGitHubRelease(releases, NO)[@"tag_name"],  @"v2.1.1-undead");
}

void test_mixed_list ()
{
	NSArray* betaLeads = @[
		release_entry(@"v2.1.2-undead-beta.1", YES),
		release_entry(@"v2.1.1-undead"),
	];
	OAK_ASSERT_EQ(OakSelectGitHubRelease(betaLeads, YES)[@"tag_name"], @"v2.1.2-undead-beta.1");
	OAK_ASSERT_EQ(OakSelectGitHubRelease(betaLeads, NO)[@"tag_name"],  @"v2.1.1-undead");

	// Stable catches up with the beta cycle: beta channel converges onto it.
	NSArray* stableLeads = @[
		release_entry(@"v2.1.2-undead"),
		release_entry(@"v2.1.2-undead-beta.2", YES),
		release_entry(@"v2.1.1-undead"),
	];
	OAK_ASSERT_EQ(OakSelectGitHubRelease(stableLeads, YES)[@"tag_name"], @"v2.1.2-undead");
	OAK_ASSERT_EQ(OakSelectGitHubRelease(stableLeads, NO)[@"tag_name"],  @"v2.1.2-undead");
}

void test_selection_by_version_not_position ()
{
	// GitHub orders by creation date: a hotfix published after a newer beta
	// appears first in the array but must not win.
	NSArray* releases = @[
		release_entry(@"v2.1.1-undead"),
		release_entry(@"v2.1.2-undead-beta.1", YES),
	];
	OAK_ASSERT_EQ(OakSelectGitHubRelease(releases, YES)[@"tag_name"], @"v2.1.2-undead-beta.1");
}

void test_skips_unusable_entries ()
{
	NSArray* releases = @[
		release_entry(@"v9.9.9-undead", NO, YES), // draft
		@"not a dictionary",
		@{ @"prerelease": @NO, @"draft": @NO },   // no tag_name
		release_entry(@"v2.1.1-undead"),
	];
	OAK_ASSERT_EQ(OakSelectGitHubRelease(releases, YES)[@"tag_name"], @"v2.1.1-undead");
}

void test_no_acceptable_entry ()
{
	OAK_ASSERT(OakSelectGitHubRelease(@[ ], YES) == nil);
	OAK_ASSERT(OakSelectGitHubRelease(nil, YES) == nil);
	OAK_ASSERT(OakSelectGitHubRelease(@[ release_entry(@"v2.1.2-undead-beta.1", YES) ], NO) == nil);
}
