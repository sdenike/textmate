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

// The surprising one. Type in the name or value of an unchecked row and it
// ticks back on.
void test_editing_a_disabled_variable_re_enables_it ()
{
	NSArray* disabled = @[ @{ @"enabled": @NO, @"name": @"OFF", @"value": @"off" } ];

	NSArray* byName = TMVariablesSetValue(disabled, 0, TMVariableKeyName(), @"ON");
	OAK_ASSERT_EQ([byName[0][TMVariableKeyEnabled()] boolValue], true);
	OAK_ASSERT([byName[0][TMVariableKeyName()] isEqualToString:@"ON"]);

	NSArray* byValue = TMVariablesSetValue(disabled, 0, TMVariableKeyValue(), @"on");
	OAK_ASSERT_EQ([byValue[0][TMVariableKeyEnabled()] boolValue], true);

	// The input is not mutated -- these functions return a new array, and the
	// pane keeps the old one until it assigns the result.
	OAK_ASSERT_EQ([disabled[0][TMVariableKeyEnabled()] boolValue], false);
}

// ...but unticking the checkbox itself must stick, which is the whole point of
// the key check inside the rule.
void test_unticking_the_checkbox_is_not_undone ()
{
	NSArray* res = TMVariablesSetValue(variables(1), 0, TMVariableKeyEnabled(), @NO);
	OAK_ASSERT_EQ([res[0][TMVariableKeyEnabled()] boolValue], false);

	// And an already-enabled row edited by name stays enabled.
	NSArray* stillOn = TMVariablesSetValue(variables(1), 0, TMVariableKeyName(), @"RENAMED");
	OAK_ASSERT_EQ([stillOn[0][TMVariableKeyEnabled()] boolValue], true);
}

void test_set_value_out_of_range_is_a_no_op ()
{
	OAK_ASSERT_EQ(TMVariablesSetValue(variables(2), 2, TMVariableKeyName(), @"x").count, 2);
	OAK_ASSERT([TMVariablesSetValue(variables(2), 2, TMVariableKeyName(), @"x")[1][TMVariableKeyName()] isEqualToString:@"NAME_1"]);
	OAK_ASSERT_EQ(TMVariablesSetValue(@[], 0, TMVariableKeyName(), @"x").count, 0);
}
