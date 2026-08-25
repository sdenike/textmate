#import "../src/SettingsFieldsBridge.h"
#import <settings/settings.h>
#import <test/jail.h>
#import <sys/stat.h>
#import <sys/time.h>

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
	// Everything that touches settings_t lives in this one test on purpose:
	// the default/global paths are process-global statics, and the runner runs
	// tests in parallel unless asked not to, so a second test setting them up
	// races this one (observed: 1 of 11 failing, sporadically, either side).
	test::jail_t jail;
	std::string const globalPath = jail.path("global");
	settings_t::set_default_settings_path(jail.path("default"));
	settings_t::set_global_settings_path(globalPath);

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

	// settings_t::set truncates and rewrites the whole file, so "did it write?"
	// is answered by whether the file was replaced. Backdating to a fixed
	// timestamp makes that exact rather than a race against mtime resolution.
	struct timeval const backdated[2] = { { 1000000, 0 }, { 1000000, 0 } };
	OAK_ASSERT_EQ(utimes(globalPath.c_str(), backdated), 0);

	// Re-committing the value that is already stored must NOT rewrite. The
	// Projects pane commits on Return, on the caret leaving the field and on
	// the settings window closing, so one edit reaches here several times, and
	// every needless truncate-and-rewrite is a window in which a crash leaves
	// the user's global settings file empty.
	TMSettingsSetString(TMSettingsExcludeKey(), @"*.o *.pyc");
	struct stat sb;
	OAK_ASSERT_EQ(stat(globalPath.c_str(), &sb), 0);
	OAK_ASSERT(sb.st_mtimespec.tv_sec == 1000000);

	// A real change still writes.
	TMSettingsSetString(TMSettingsExcludeKey(), @"*.pyc");
	OAK_ASSERT_EQ(stat(globalPath.c_str(), &sb), 0);
	OAK_ASSERT(sb.st_mtimespec.tv_sec != 1000000);
	OAK_ASSERT([TMSettingsGetString(TMSettingsExcludeKey()) isEqualToString:@"*.pyc"]);

	// The escaped line-endings forms survive settings_t verbatim: they are
	// written into Global.tmProperties quoted and must come back as the same
	// two and four characters, or the Files pane's popup selects nothing.
	TMSettingsSetString(TMSettingsLineEndingsKey(), TMLineEndingsValueForTag(2));
	OAK_ASSERT([TMSettingsGetString(TMSettingsLineEndingsKey()) isEqualToString:@"\\r\\n"]);
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(TMSettingsGetString(TMSettingsLineEndingsKey())), 2);

	// One key, three scopes, three independent values -- the Files pane edits
	// the untitled and unknown-type ones side by side, and a scope leaking
	// into the global section would retype every file the user opens.
	OAK_ASSERT([TMSettingsGetScopedString(TMSettingsFileTypeKey(), @"attr.untitled") isEqualToString:@""]);

	TMSettingsSetScopedString(TMSettingsFileTypeKey(), @"text.plain", @"attr.untitled");
	TMSettingsSetScopedString(TMSettingsFileTypeKey(), @"source.ruby", @"attr.file.unknown-type");
	OAK_ASSERT([TMSettingsGetScopedString(TMSettingsFileTypeKey(), @"attr.untitled") isEqualToString:@"text.plain"]);
	OAK_ASSERT([TMSettingsGetScopedString(TMSettingsFileTypeKey(), @"attr.file.unknown-type") isEqualToString:@"source.ruby"]);
	OAK_ASSERT([TMSettingsGetString(TMSettingsFileTypeKey()) isEqualToString:@""]);

	// nil is the "Prompt for type" entry: stored as NULL_STR, read back as "".
	TMSettingsSetScopedString(TMSettingsFileTypeKey(), nil, @"attr.file.unknown-type");
	OAK_ASSERT([TMSettingsGetScopedString(TMSettingsFileTypeKey(), @"attr.file.unknown-type") isEqualToString:@""]);
	OAK_ASSERT([TMSettingsGetScopedString(TMSettingsFileTypeKey(), @"attr.untitled") isEqualToString:@"text.plain"]);

	// And the same no-redundant-write rule as the unscoped setter, compared
	// within the scope rather than against the global section.
	OAK_ASSERT_EQ(utimes(globalPath.c_str(), backdated), 0);
	TMSettingsSetScopedString(TMSettingsFileTypeKey(), @"text.plain", @"attr.untitled");
	OAK_ASSERT_EQ(stat(globalPath.c_str(), &sb), 0);
	OAK_ASSERT(sb.st_mtimespec.tv_sec == 1000000);

	TMSettingsSetScopedString(TMSettingsFileTypeKey(), @"source.c", @"attr.untitled");
	OAK_ASSERT_EQ(stat(globalPath.c_str(), &sb), 0);
	OAK_ASSERT(sb.st_mtimespec.tv_sec != 1000000);
}

void test_line_endings_tag_for_value ()
{
	// The escaped forms, not real control characters -- see the header.
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(@"\\n"),   0);
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(@"\\r"),   1);
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(@"\\r\\n"), 2);
	// A real newline is NOT the stored form, and must not be mistaken for one.
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(@"\n"),    0);
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(@"bogus"), 0);
	OAK_ASSERT_EQ(TMLineEndingsTagForValue(nil),      0);
}

void test_line_endings_value_for_tag ()
{
	OAK_ASSERT([TMLineEndingsValueForTag(0) isEqualToString:@"\\n"]);
	OAK_ASSERT([TMLineEndingsValueForTag(1) isEqualToString:@"\\r"]);
	OAK_ASSERT([TMLineEndingsValueForTag(2) isEqualToString:@"\\r\\n"]);
	OAK_ASSERT([TMLineEndingsValueForTag(9) isEqualToString:@"\\n"]);
}

void test_file_type_items_sorted ()
{
	NSArray<TMFileTypeItem*>* candidates = @[
		[[TMFileTypeItem alloc] initWithName:@"Ruby"       scope:@"source.ruby"  hidden:NO ],
		[[TMFileTypeItem alloc] initWithName:@"Hidden"     scope:@"source.hide"  hidden:YES],
		[[TMFileTypeItem alloc] initWithName:@"C"          scope:@"source.c"     hidden:NO ],
		// No kFieldGrammarScope: stringWithCxxString: hands NULL_STR back as
		// nil, and a menu entry that selects nothing is worse than no entry.
		[[TMFileTypeItem alloc] initWithName:@"Scopeless"  scope:nil             hidden:NO ],
		[[TMFileTypeItem alloc] initWithName:@"apache"     scope:@"source.conf"  hidden:NO ],
	];

	NSArray<TMFileTypeItem*>* items = TMFileTypeItemsSorted(candidates);
	OAK_ASSERT_EQ(items.count, 3);
	// text::less_t, so "apache" sorts with the capitals rather than after them.
	OAK_ASSERT([items[0].name isEqualToString:@"apache"]);
	OAK_ASSERT([items[1].name isEqualToString:@"C"]);
	OAK_ASSERT([items[2].name isEqualToString:@"Ruby"]);
	OAK_ASSERT([items[2].scope isEqualToString:@"source.ruby"]);

	OAK_ASSERT_EQ(TMFileTypeItemsSorted(@[ ]).count, 0);
}
