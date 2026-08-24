// Frameworks/Preferences/src/SettingsVariablesBridge.h
#import <Foundation/Foundation.h>

// The Variables pane's editing rules, as pure functions over the array of
// dictionaries stored under kUserDefaultsEnvironmentVariablesKey. The SwiftUI
// pane owns the array and the selection; every rule that decides WHAT the array
// becomes lives here, where Preferences_test can reach it -- Swift cannot be
// tested from bin/gen_test's runner at all.
//
// Nothing here touches NSUserDefaults. Reading and writing that key is three
// lines of Swift (SettingsSupport.swift), and keeping it out of these functions
// is what makes them testable without a defaults domain to set up and tear down.
//
// Explicitly _Nonnull/_Nullable throughout, same reason as SettingsFieldsBridge.h:
// unaudited, Swift imports every NSString*/NSArray* here as an Optional. The
// underscore spellings rather than the bare nullable/nonnull keywords, which do
// not parse when this header is compiled standalone as part of the Swift
// bridging header.
//
// extern "C": SettingsVariablesBridge.mm is Objective-C++, so without this the
// definitions get C++ name mangling while Swift's ClangImporter -- which parses
// this header as plain C -- looks up the plain C symbol. Both sides still
// compile clean and Preferences_test still passes, because its tests call these
// from Objective-C++ too and mangle identically; only the app's final link
// surfaces the mismatch. __cplusplus is undefined for the plain-C parse, so
// this is a no-op there.
#ifdef __cplusplus
extern "C" {
#endif

// The three keys inside each entry. Functions rather than NSString* const so
// Swift gets them through the same audited surface as everything else here.
extern NSString* _Nonnull TMVariableKeyEnabled(void); // @"enabled"
extern NSString* _Nonnull TMVariableKeyName(void);    // @"name"
extern NSString* _Nonnull TMVariableKeyValue(void);   // @"value"

// The entry the + button inserts: enabled, named VARIABLE_NAME, valued
// "variable value". Exact strings -- users recognise them.
extern NSDictionary<NSString*, id>* _Nonnull TMVariablesNewEntry(void);

// Where + inserts: at the selection when there is one, otherwise at the end.
// Pass -1 for no selection, matching NSTableView's selectedRow.
extern NSInteger TMVariablesInsertionIndex(NSInteger selectedRow, NSInteger count);

extern NSArray<NSDictionary<NSString*, id>*>* _Nonnull TMVariablesInsert(NSArray<NSDictionary<NSString*, id>*>* _Nonnull variables, NSInteger index);
extern NSArray<NSDictionary<NSString*, id>*>* _Nonnull TMVariablesRemove(NSArray<NSDictionary<NSString*, id>*>* _Nonnull variables, NSInteger row);

// The row to select after removing `row`, given the count AFTER the removal.
// Steps back one row unless the first was removed, then falls off the end to
// -1 (nothing to select) when the list is now empty or shorter than that.
extern NSInteger TMVariablesSelectionAfterRemove(NSInteger row, NSInteger count);

// Sets one key of one row and nothing else. Deliberately dumb: the SwiftUI
// pane calls it per keystroke, and a rule applied per keystroke is a rule
// applied to text the user has not committed and may still cancel.
extern NSArray<NSDictionary<NSString*, id>*>* _Nonnull TMVariablesSetValue(NSArray<NSDictionary<NSString*, id>*>* _Nonnull variables, NSInteger row, NSString* _Nonnull key, id _Nonnull value);

// Editing the name or value of a DISABLED variable silently re-enables it.
// Undocumented, surprising, and the shipped behaviour of the AppKit pane
// (VariablesPreferences.mm -tableView:setObjectValue:forTableColumn:row: as of
// 2026-08-24) -- kept deliberately, which is why it is a tested function rather
// than an inline `if` somewhere in a view.
//
// Applied on COMMIT, against the last committed array, rather than inside
// TMVariablesSetValue: NSTableView called -setObjectValue: when editing ENDED,
// so one keystroke into a disabled row followed by Escape left the row alone.
// Folding the rule into the per-keystroke setter re-enabled it on that first
// character and the next focus change persisted it -- a PATH override the user
// cancelled coming back on.
//
// Counts must match; they do not during an insert or a delete, and those flush
// the pending edits through here first and then write the structural change
// directly. Mismatched counts return `current` untouched rather than guessing
// which rows correspond.
extern NSArray<NSDictionary<NSString*, id>*>* _Nonnull TMVariablesEnableEdited(NSArray<NSDictionary<NSString*, id>*>* _Nonnull baseline, NSArray<NSDictionary<NSString*, id>*>* _Nonnull current);

// One row back to how it was last committed -- what Escape does. The whole
// entry, not just the text: the checkbox commits on the click, so the baseline
// already holds its current state.
extern NSArray<NSDictionary<NSString*, id>*>* _Nonnull TMVariablesRevert(NSArray<NSDictionary<NSString*, id>*>* _Nonnull current, NSArray<NSDictionary<NSString*, id>*>* _Nonnull baseline, NSInteger row);

#ifdef __cplusplus
}
#endif
