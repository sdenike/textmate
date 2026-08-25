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
extern NSString* _Nonnull TMSettingsEncodingKey(void);
extern NSString* _Nonnull TMSettingsLineEndingsKey(void);
extern NSString* _Nonnull TMSettingsFileTypeKey(void);

// Never returns nil, even for a key that was never set -- callers bind it
// straight to a SwiftUI TextField, and nil there is a crash the first time
// someone opens the pane having never set a pattern.
extern NSString* _Nonnull TMSettingsGetString(NSString* _Nonnull key);
// A no-op when that value is already stored -- see the comment on the
// definition. Call it on commit, never per keystroke.
extern void TMSettingsSetString(NSString* _Nonnull key, NSString* _Nullable value);

// The tag <-> string mapping the AppKit pane got for free from
// OakStringListTransformer plus NSSelectedTagBinding, reimplemented as pure
// functions: SwiftUI's Picker has no equivalent value-transformer mechanism,
// and this keeps the fallback rule (unrecognised value -> first entry) in one
// tested place instead of a second copy living in Swift.
extern NSInteger TMFileBrowserPlacementTagForValue(NSString* _Nullable value); // "right"->1, else->0
extern NSString* _Nonnull TMFileBrowserPlacementValueForTag(NSInteger tag);    // 0->"left", else->"right"

extern NSInteger TMHTMLOutputPlacementTagForValue(NSString* _Nullable value); // "bottom"->0, "right"->1, else->2
extern NSString* _Nonnull TMHTMLOutputPlacementValueForTag(NSInteger tag);    // 0->"bottom", 1->"right", else->"window"

// The values are the BACKSLASH-escaped two- and four-character forms, not real
// control characters: settings_t writes them into Global.tmProperties quoted
// and hands them back the same way, and only settings_for_path's expansion
// turns them into a real newline for OakDocument. The AppKit pane's
// OakLineEndingsSettingsTransformer was built from @[ @"\\n", @"\\r",
// @"\\r\\n" ] for the same reason; the round trip is asserted in
// t_settings_fields.mm rather than reasoned about.
extern NSInteger TMLineEndingsTagForValue(NSString* _Nullable value); // "\\r"->1, "\\r\\n"->2, else->0
extern NSString* _Nonnull TMLineEndingsValueForTag(NSInteger tag);    // 0->"\\n", 1->"\\r", 2->"\\r\\n"

// Scoped variants. kSettingsFileTypeKey holds a DIFFERENT value per scope
// selector -- "attr.untitled" for a new document, "attr.file.unknown-type" for
// one whose type could not be determined -- and the Files pane edits both from
// one pane. settings_t has always supported this (raw_get's section argument,
// set's fileType argument); the unscoped pair above passes "", the global
// section.
extern NSString* _Nonnull TMSettingsGetScopedString(NSString* _Nonnull key, NSString* _Nonnull scope);
// value may be nil, and nil is NOT "" here: it stores NULL_STR, which reads
// back as "" and is how the unknown-document popup's "Prompt for type" entry
// (a menu item with a nil representedObject in the AppKit pane) is expressed.
extern void TMSettingsSetScopedString(NSString* _Nonnull key, NSString* _Nullable value, NSString* _Nonnull scope);

#ifdef __cplusplus
}
#endif

// One grammar as the Files pane's two file-type popups need it. Objective-C,
// not Swift, because bin/gen_test cannot reach Swift and TMFileTypeItemsSorted
// below is the tested half of the menu-building the AppKit pane did inline.
// scope is nil exactly when the grammar has no kFieldGrammarScope (NULL_STR).
@interface TMFileTypeItem : NSObject
@property (nonatomic, readonly) NSString* _Nonnull name;
@property (nonatomic, readonly) NSString* _Nullable scope;
@property (nonatomic, readonly) BOOL hidden;
- (instancetype _Nonnull)initWithName:(NSString* _Nonnull)name scope:(NSString* _Nullable)scope hidden:(BOOL)hidden;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Drops hidden grammars and scope-less ones, and orders what is left by name
// through text::less_t -- the three rules the AppKit pane spread across a
// std::multimap and two `continue`s. FilesPreferences.mm supplies the
// candidates straight from bundles::query; this framework must not link
// bundles.
extern NSArray<TMFileTypeItem*>* _Nonnull TMFileTypeItemsSorted(NSArray<TMFileTypeItem*>* _Nonnull candidates);

#ifdef __cplusplus
}
#endif
