// Frameworks/Preferences/src/SettingsFieldsBridge.h
#import <Foundation/Foundation.h>

// The Projects pane's three text fields bind to settings_t, TextMate's C++
// settings layer, not NSUserDefaults -- PreferencesPane.mm already routes
// tmProperties through settings_t::set/raw_get for the AppKit panes, and this
// is the same bridge for SwiftUI. Functions rather than NSString* const: the
// keys are C++ std::string constants (Frameworks/settings/src/keys.h) and
// cannot initialise an Objective-C global at static-init time.
//
// Explicitly _Nonnull/_Nullable throughout: left unaudited, Swift imports
// every NSString* here -- return values included -- as String?, which then
// has to be force- or nil-coalesce-unwrapped at every call site even though
// none of these ever actually returns nil. _Nonnull/_Nullable (rather than
// NS_ASSUME_NONNULL_BEGIN/END) because the bare nullable/nonnull contextual
// keyword failed to parse when this header is compiled standalone as the
// Swift bridging header -- "unknown type name 'nullable'" -- while the
// underscore form works unconditionally.
// extern "C": SettingsFieldsBridge.mm is Objective-C++, so without this the
// definitions there get C++ name mangling while Swift's ClangImporter -- which
// parses this header as plain C -- looks up the plain C symbol. Both sides
// compiled clean and Preferences_test (which never calls these from Swift)
// still passed; only the app's final link surfaced it, as nine "Undefined
// symbols" against the mangled names sitting right there in the archive.
// __cplusplus is undefined for the plain-C parse, so this is a no-op there.
#ifdef __cplusplus
extern "C" {
#endif

extern NSString* _Nonnull TMSettingsExcludeKey(void);
extern NSString* _Nonnull TMSettingsIncludeKey(void);
extern NSString* _Nonnull TMSettingsBinaryKey(void);

// Never returns nil, even for a key that was never set -- callers bind it
// straight to a SwiftUI TextField, and nil there is a crash the first time
// someone opens the pane having never set a pattern.
extern NSString* _Nonnull TMSettingsGetString(NSString* _Nonnull key);
extern void TMSettingsSetString(NSString* _Nonnull key, NSString* _Nullable value);

// The tag <-> string mapping the AppKit pane got for free from
// OakStringListTransformer plus NSSelectedTagBinding, reimplemented as pure
// functions: SwiftUI's Picker has no equivalent value-transformer mechanism,
// and this keeps the fallback rule (unrecognised value -> first entry) in one
// tested place instead of a second copy living in Swift.
extern NSInteger TMFileBrowserPlacementTagForValue(NSString* _Nullable value); // "left"->0, else->1
extern NSString* _Nonnull TMFileBrowserPlacementValueForTag(NSInteger tag);    // 0->"left", else->"right"

extern NSInteger TMHTMLOutputPlacementTagForValue(NSString* _Nullable value); // "bottom"->0, "right"->1, else->2
extern NSString* _Nonnull TMHTMLOutputPlacementValueForTag(NSInteger tag);    // 0->"bottom", 1->"right", else->"window"

#ifdef __cplusplus
}
#endif
