// Frameworks/Preferences/src/SettingsVariablesBridge.mm
#import "SettingsVariablesBridge.h"

static NSString* const kVariableKeyEnabled = @"enabled";
static NSString* const kVariableKeyName    = @"name";
static NSString* const kVariableKeyValue   = @"value";

NSString* TMVariableKeyEnabled (void) { return kVariableKeyEnabled; }
NSString* TMVariableKeyName    (void) { return kVariableKeyName;    }
NSString* TMVariableKeyValue   (void) { return kVariableKeyValue;   }

NSDictionary<NSString*, id>* TMVariablesNewEntry (void)
{
	return @{
		kVariableKeyEnabled: @YES,
		kVariableKeyName:    @"VARIABLE_NAME",
		kVariableKeyValue:   @"variable value",
	};
}

NSInteger TMVariablesInsertionIndex (NSInteger selectedRow, NSInteger count)
{
	return selectedRow >= 0 && selectedRow <= count ? selectedRow : count;
}

NSArray<NSDictionary<NSString*, id>*>* TMVariablesInsert (NSArray<NSDictionary<NSString*, id>*>* variables, NSInteger index)
{
	if(index < 0 || index > variables.count)
		return variables;
	NSMutableArray* res = [variables mutableCopy];
	[res insertObject:TMVariablesNewEntry() atIndex:index];
	return res;
}

NSArray<NSDictionary<NSString*, id>*>* TMVariablesRemove (NSArray<NSDictionary<NSString*, id>*>* variables, NSInteger row)
{
	if(row < 0 || row >= variables.count)
		return variables;
	NSMutableArray* res = [variables mutableCopy];
	[res removeObjectAtIndex:row];
	return res;
}

NSInteger TMVariablesSelectionAfterRemove (NSInteger row, NSInteger count)
{
	if(row < 0)
		return -1;
	if(row > 0)
		--row;
	return row < count ? row : -1;
}

NSArray<NSDictionary<NSString*, id>*>* TMVariablesSetValue (NSArray<NSDictionary<NSString*, id>*>* variables, NSInteger row, NSString* key, id value)
{
	if(row < 0 || row >= variables.count)
		return variables;

	NSMutableDictionary* newValue = [NSMutableDictionary dictionaryWithDictionary:variables[row]];
	newValue[key] = value;

	NSMutableArray* res = [variables mutableCopy];
	res[row] = newValue;
	return res;
}

// nil == nil, which -isEqual: does not give you: a row missing a key entirely
// would otherwise read as edited on every commit and tick itself back on.
static BOOL equal_values (id lhs, id rhs)
{
	return lhs == rhs || [lhs isEqual:rhs];
}

NSArray<NSDictionary<NSString*, id>*>* TMVariablesEnableEdited (NSArray<NSDictionary<NSString*, id>*>* baseline, NSArray<NSDictionary<NSString*, id>*>* current)
{
	if(baseline.count != current.count)
		return current;

	NSMutableArray* res = nil;
	for(NSUInteger i = 0; i < current.count; ++i)
	{
		NSDictionary* was = baseline[i];
		NSDictionary* now = current[i];
		if([now[kVariableKeyEnabled] boolValue])
			continue;
		if(equal_values(was[kVariableKeyName], now[kVariableKeyName]) && equal_values(was[kVariableKeyValue], now[kVariableKeyValue]))
			continue;

		NSMutableDictionary* entry = [now mutableCopy];
		entry[kVariableKeyEnabled] = @YES;
		res = res ?: [current mutableCopy];
		res[i] = entry;
	}
	return res ?: current;
}

NSArray<NSDictionary<NSString*, id>*>* TMVariablesRevert (NSArray<NSDictionary<NSString*, id>*>* current, NSArray<NSDictionary<NSString*, id>*>* baseline, NSInteger row)
{
	if(row < 0 || row >= current.count || row >= baseline.count)
		return current;

	NSMutableArray* res = [current mutableCopy];
	res[row] = baseline[row];
	return res;
}
