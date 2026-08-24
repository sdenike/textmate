#import "../src/SettingsVariablesBridge.h"

// Wrapped in namespace t_settings_variables by bin/gen_test, so no Objective-C
// class may be declared here. Everything under test is a free function.
//
// OAK_ASSERT rather than OAK_ASSERT_EQ on every object comparison: there is no
// to_s overload for NSString*/NSDictionary*, so OAK_ASSERT_EQ falls through to
// the generic to_s(_T const&), which range-fors over the pointer and aborts the
// whole runner with SIGABRT when the assertion fails.

static NSArray* variables (NSUInteger count)
{
	NSMutableArray* res = [NSMutableArray array];
	for(NSUInteger i = 0; i < count; ++i)
		[res addObject:@{ @"enabled": @YES, @"name": [NSString stringWithFormat:@"NAME_%lu", (unsigned long)i], @"value": [NSString stringWithFormat:@"value %lu", (unsigned long)i] }];
	return res;
}

void test_new_entry_placeholders ()
{
	NSDictionary* entry = TMVariablesNewEntry();
	OAK_ASSERT([entry[TMVariableKeyName()]  isEqualToString:@"VARIABLE_NAME"]);
	OAK_ASSERT([entry[TMVariableKeyValue()] isEqualToString:@"variable value"]);
	OAK_ASSERT_EQ([entry[TMVariableKeyEnabled()] boolValue], true);
}

void test_key_names ()
{
	OAK_ASSERT([TMVariableKeyEnabled() isEqualToString:@"enabled"]);
	OAK_ASSERT([TMVariableKeyName()    isEqualToString:@"name"]);
	OAK_ASSERT([TMVariableKeyValue()   isEqualToString:@"value"]);
}

// + inserts AT the selection, not after it and not at the end.
void test_insertion_index ()
{
	OAK_ASSERT_EQ(TMVariablesInsertionIndex(2, 5), 2);
	OAK_ASSERT_EQ(TMVariablesInsertionIndex(0, 5), 0);
	// No selection: append.
	OAK_ASSERT_EQ(TMVariablesInsertionIndex(-1, 5), 5);
	OAK_ASSERT_EQ(TMVariablesInsertionIndex(-1, 0), 0);
	// Out of range is treated as no selection rather than trapping.
	OAK_ASSERT_EQ(TMVariablesInsertionIndex(9, 5), 5);
}

void test_insert_places_entry_at_index ()
{
	NSArray* res = TMVariablesInsert(variables(3), 1);
	OAK_ASSERT_EQ(res.count, 4);
	OAK_ASSERT([res[0][TMVariableKeyName()] isEqualToString:@"NAME_0"]);
	OAK_ASSERT([res[1][TMVariableKeyName()] isEqualToString:@"VARIABLE_NAME"]);
	OAK_ASSERT([res[2][TMVariableKeyName()] isEqualToString:@"NAME_1"]);

	// Appending at count is in range; past it is not, and returns the input.
	OAK_ASSERT_EQ(TMVariablesInsert(variables(3), 3).count, 4);
	OAK_ASSERT_EQ(TMVariablesInsert(variables(3), 4).count, 3);
	OAK_ASSERT_EQ(TMVariablesInsert(variables(3), -1).count, 3);
}

void test_remove ()
{
	NSArray* res = TMVariablesRemove(variables(3), 1);
	OAK_ASSERT_EQ(res.count, 2);
	OAK_ASSERT([res[0][TMVariableKeyName()] isEqualToString:@"NAME_0"]);
	OAK_ASSERT([res[1][TMVariableKeyName()] isEqualToString:@"NAME_2"]);

	OAK_ASSERT_EQ(TMVariablesRemove(variables(3), 3).count,  3);
	OAK_ASSERT_EQ(TMVariablesRemove(variables(3), -1).count, 3);
	OAK_ASSERT_EQ(TMVariablesRemove(@[], 0).count, 0);
}

// Delete steps the selection back one row and clamps. Both ends matter: the
// first row must not step to -1 and land on nothing, and the last row must not
// keep a selection that no longer exists.
void test_selection_after_remove ()
{
	// Middle of five: 3 removed, four left, select 2.
	OAK_ASSERT_EQ(TMVariablesSelectionAfterRemove(3, 4), 2);
	// The FIRST row: stays at 0 rather than stepping to -1.
	OAK_ASSERT_EQ(TMVariablesSelectionAfterRemove(0, 2), 0);
	// The LAST row of three: steps back to 1, which is in range.
	OAK_ASSERT_EQ(TMVariablesSelectionAfterRemove(2, 2), 1);
	// The ONLY row: nothing left to select.
	OAK_ASSERT_EQ(TMVariablesSelectionAfterRemove(0, 0), -1);
	// Nothing was selected, so nothing is selected after.
	OAK_ASSERT_EQ(TMVariablesSelectionAfterRemove(-1, 3), -1);
}

void test_set_value_replaces_only_that_row ()
{
	NSArray* res = TMVariablesSetValue(variables(3), 1, TMVariableKeyValue(), @"edited");
	OAK_ASSERT_EQ(res.count, 3);
	OAK_ASSERT([res[1][TMVariableKeyValue()] isEqualToString:@"edited"]);
	OAK_ASSERT([res[1][TMVariableKeyName()]  isEqualToString:@"NAME_1"]);
	OAK_ASSERT([res[0][TMVariableKeyValue()] isEqualToString:@"value 0"]);
	OAK_ASSERT([res[2][TMVariableKeyValue()] isEqualToString:@"value 2"]);
}

// Per-keystroke setter: sets the key and nothing else. The re-enable rule used
// to live in here, which meant one character into a disabled row ticked it back
// on before the user had committed anything -- and Escape could not take it
// back. It is TMVariablesEnableEdited's job now.
void test_set_value_does_not_re_enable ()
{
	NSArray* disabled = @[ @{ @"enabled": @NO, @"name": @"OFF", @"value": @"off" } ];

	NSArray* byName = TMVariablesSetValue(disabled, 0, TMVariableKeyName(), @"ON");
	OAK_ASSERT_EQ([byName[0][TMVariableKeyEnabled()] boolValue], false);
	OAK_ASSERT([byName[0][TMVariableKeyName()] isEqualToString:@"ON"]);

	// The input is not mutated -- these functions return a new array, and the
	// pane keeps the old one until it assigns the result.
	OAK_ASSERT_EQ([disabled[0][TMVariableKeyEnabled()] boolValue], false);
}

void test_set_value_out_of_range_is_a_no_op ()
{
	OAK_ASSERT_EQ(TMVariablesSetValue(variables(2), 2, TMVariableKeyName(), @"x").count, 2);
	OAK_ASSERT([TMVariablesSetValue(variables(2), 2, TMVariableKeyName(), @"x")[1][TMVariableKeyName()] isEqualToString:@"NAME_1"]);
	OAK_ASSERT_EQ(TMVariablesSetValue(@[], 0, TMVariableKeyName(), @"x").count, 0);
}

// The surprising one, now applied on commit: a row whose name or value differs
// from what was last committed ticks back on.
void test_editing_a_disabled_variable_re_enables_it_on_commit ()
{
	NSArray* baseline = @[ @{ @"enabled": @NO, @"name": @"OFF", @"value": @"off" } ];

	NSArray* byName = TMVariablesEnableEdited(baseline, TMVariablesSetValue(baseline, 0, TMVariableKeyName(), @"ON"));
	OAK_ASSERT_EQ([byName[0][TMVariableKeyEnabled()] boolValue], true);
	OAK_ASSERT([byName[0][TMVariableKeyName()] isEqualToString:@"ON"]);

	NSArray* byValue = TMVariablesEnableEdited(baseline, TMVariablesSetValue(baseline, 0, TMVariableKeyValue(), @"on"));
	OAK_ASSERT_EQ([byValue[0][TMVariableKeyEnabled()] boolValue], true);

	OAK_ASSERT_EQ([baseline[0][TMVariableKeyEnabled()] boolValue], false);
}

// The whole point of moving the rule off the keystroke: a cancelled edit is
// indistinguishable from no edit by the time commit runs, so the row stays off.
void test_a_reverted_edit_does_not_re_enable ()
{
	NSArray* baseline = @[ @{ @"enabled": @NO, @"name": @"PATH", @"value": @"/bin" } ];
	NSArray* typed    = TMVariablesSetValue(baseline, 0, TMVariableKeyName(), @"PATHX");
	NSArray* escaped  = TMVariablesRevert(typed, baseline, 0);

	OAK_ASSERT_EQ([TMVariablesEnableEdited(baseline, escaped)[0][TMVariableKeyEnabled()] boolValue], false);
	OAK_ASSERT([escaped[0][TMVariableKeyName()] isEqualToString:@"PATH"]);
}

// Unticking the checkbox must stick, which is why the rule keys off name and
// value rather than "anything changed".
void test_unticking_the_checkbox_is_not_undone ()
{
	NSArray* baseline = variables(1);
	NSArray* off      = TMVariablesSetValue(baseline, 0, TMVariableKeyEnabled(), @NO);
	OAK_ASSERT_EQ([TMVariablesEnableEdited(baseline, off)[0][TMVariableKeyEnabled()] boolValue], false);

	// And an already-enabled row edited by name stays enabled.
	NSArray* renamed = TMVariablesSetValue(baseline, 0, TMVariableKeyName(), @"RENAMED");
	OAK_ASSERT_EQ([TMVariablesEnableEdited(baseline, renamed)[0][TMVariableKeyEnabled()] boolValue], true);
}

void test_enable_edited_leaves_untouched_rows_and_mismatched_counts_alone ()
{
	NSArray* baseline = @[ @{ @"enabled": @NO, @"name": @"A", @"value": @"a" },
	                       @{ @"enabled": @NO, @"name": @"B", @"value": @"b" } ];

	// Only the edited row ticks on.
	NSArray* res = TMVariablesEnableEdited(baseline, TMVariablesSetValue(baseline, 1, TMVariableKeyValue(), @"edited"));
	OAK_ASSERT_EQ([res[0][TMVariableKeyEnabled()] boolValue], false);
	OAK_ASSERT_EQ([res[1][TMVariableKeyEnabled()] boolValue], true);

	// Nothing edited at all: the identical array back, nothing ticked on.
	NSArray* same = TMVariablesEnableEdited(baseline, baseline);
	OAK_ASSERT_EQ([same[0][TMVariableKeyEnabled()] boolValue], false);
	OAK_ASSERT_EQ(same.count, 2);

	// An insert or a delete makes the rows uncomparable; the pane flushes
	// through here first and then writes the structural change directly, so
	// this returns `current` rather than guessing.
	NSArray* grown = TMVariablesInsert(baseline, 2);
	OAK_ASSERT_EQ(TMVariablesEnableEdited(baseline, grown).count, 3);
	OAK_ASSERT_EQ([TMVariablesEnableEdited(baseline, grown)[0][TMVariableKeyEnabled()] boolValue], false);

	// A row missing the keys entirely reads as unedited against itself rather
	// than as changed -- nil == nil, which -isEqual: does not give you.
	NSArray* empty = @[ @{ @"enabled": @NO } ];
	OAK_ASSERT_EQ([TMVariablesEnableEdited(empty, empty)[0][TMVariableKeyEnabled()] boolValue], false);
}

void test_revert_restores_one_row_and_clamps ()
{
	NSArray* baseline = variables(3);
	NSArray* edited   = TMVariablesSetValue(TMVariablesSetValue(baseline, 1, TMVariableKeyName(), @"X"), 2, TMVariableKeyName(), @"Y");

	NSArray* res = TMVariablesRevert(edited, baseline, 1);
	OAK_ASSERT([res[1][TMVariableKeyName()] isEqualToString:@"NAME_1"]);
	// The OTHER edited row is untouched: Escape cancels one cell's session.
	OAK_ASSERT([res[2][TMVariableKeyName()] isEqualToString:@"Y"]);

	OAK_ASSERT([TMVariablesRevert(edited, baseline, 3)[1][TMVariableKeyName()]  isEqualToString:@"X"]);
	OAK_ASSERT([TMVariablesRevert(edited, baseline, -1)[1][TMVariableKeyName()] isEqualToString:@"X"]);
	// A row that does not exist in the baseline -- a just-added row Escaped
	// before its first commit -- is left as it is rather than trapping.
	OAK_ASSERT_EQ(TMVariablesRevert(edited, @[], 1).count, 3);
}
