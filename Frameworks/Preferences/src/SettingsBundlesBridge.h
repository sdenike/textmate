// Frameworks/Preferences/src/SettingsBundlesBridge.h
#import <Foundation/Foundation.h>

// The Bundles pane's model is the ObjC `Bundle` class (BundlesManager/Bundle.h),
// which cannot cross the bridging header: it lives behind Xcode/include/ and,
// like SetupAssistantTypes.h's TMBundleChoice, has to be mirrored into a plain
// value type instead. TMBundleRow carries exactly the fields the SwiftUI table
// and its per-row gear menu read; BundlesPreferences.mm rebuilds the array
// fresh from BundlesManager.sharedInstance.bundles on every change and never
// hands the real Bundle* to Swift. Every action a row can trigger crosses back
// the other way as a plain identifier string (bundle.identifier.UUIDString),
// which the ObjC++ side resolves back to a real Bundle* -- the same division
// TerminalSupportBridge draws around TMInstallPathItem.
//
// Explicitly _Nonnull/_Nullable throughout, same reason as every other bridge
// header here -- NOT NS_ASSUME_NONNULL_BEGIN/END: the bare nullable/nonnull
// contextual keyword does not parse when this header is compiled standalone
// as the Swift bridging header ("unknown type name 'nullable'"), so the
// underscore spellings are mandatory.

// Mirrors installedCellState's three states (BundlesPreferences.mm's
// Bundle(BundlesInstallPreferences) category) without pulling NSControlStateValue
// across the bridge. Off/On map to the checkbox; Mixed is "install or uninstall
// in flight" -- the SwiftUI pane shows a spinner rather than a mixed-state
// checkbox for that one, which is why it is its own case rather than a BOOL.
typedef NS_ENUM(NSInteger, TMBundleInstallState) {
	TMBundleInstallStateOff = 0,
	TMBundleInstallStateOn,
	TMBundleInstallStateMixed,
};

@interface TMBundleRow : NSObject
@property (nonatomic, readonly) NSString* _Nonnull            identifier; // bundle.identifier.UUIDString
@property (nonatomic, readonly) NSString* _Nonnull            name;
@property (nonatomic, readonly) NSString* _Nullable           category;
@property (nonatomic, readonly) NSString* _Nullable           webLinkURLString; // bundle.htmlURL, nil when the bundle has none
@property (nonatomic, readonly) NSDate*   _Nullable           updated;          // bundle.downloadLastUpdated
@property (nonatomic, readonly) NSString* _Nonnull            textSummary;
@property (nonatomic, readonly) TMBundleInstallState          installState;
// !(isMandatory && isInstalled) -- precomputed because it is what
// -tableView:willDisplayCell:forTableColumn:row: computed for the Installed
// column; a mandatory, already-installed bundle cannot be unchecked.
@property (nonatomic, readonly) BOOL                          installedToggleEnabled;
@property (nonatomic, readonly) BOOL                          isMandatory;
@property (nonatomic, readonly) BOOL                          isInstalled;
@property (nonatomic, readonly) BOOL                          autoUpdateEnabled;
@property (nonatomic, readonly) NSString* _Nullable           ref;               // for the Change Ref/Edit Bundle sheets
@property (nonatomic, readonly) NSString* _Nullable           downloadURLString; // for Copy URL and the Edit Bundle sheet
@property (nonatomic, readonly) NSString* _Nullable           path;              // for Reveal in Finder
@property (nonatomic, readonly) BOOL                          isEditedShipped;   // gates Revert to Default

- (instancetype _Nonnull)initWithIdentifier:(NSString* _Nonnull)identifier
                                        name:(NSString* _Nonnull)name
                                    category:(NSString* _Nullable)category
                            webLinkURLString:(NSString* _Nullable)webLinkURLString
                                     updated:(NSDate* _Nullable)updated
                                 textSummary:(NSString* _Nonnull)textSummary
                                installState:(TMBundleInstallState)installState
                      installedToggleEnabled:(BOOL)installedToggleEnabled
                                 isMandatory:(BOOL)isMandatory
                                 isInstalled:(BOOL)isInstalled
                           autoUpdateEnabled:(BOOL)autoUpdateEnabled
                                         ref:(NSString* _Nullable)ref
                           downloadURLString:(NSString* _Nullable)downloadURLString
                                        path:(NSString* _Nullable)path
                             isEditedShipped:(BOOL)isEditedShipped;
@end

// The per-row gear menu's eight enablement rules, straight out of
// -populateMenu:forBundle: (BundlesPreferences.mm, as of the AppKit pane).
// A plain C struct rather than eight separate functions so a call site cannot
// forget one, and testable in one shot from t_settings_bundles.mm.
typedef struct {
	BOOL autoUpdateEnabled; // !mandatory
	BOOL changeRefEnabled;  // !mandatory
	BOOL editEnabled;       // !mandatory
	BOOL uninstallEnabled;  // !mandatory && installed
	BOOL removeEnabled;     // !mandatory
	BOOL revertEnabled;     // isEditedShipped (already excludes mandatory/user-added)
	BOOL copyURLEnabled;    // downloadURLString != nil
	BOOL revealEnabled;     // path != nil
} TMBundleMenuEnablement;

// extern "C": SettingsBundlesBridge.mm is Objective-C++, so without this the
// definitions get C++-mangled symbols while Swift's ClangImporter -- which
// parses this header as plain C -- looks up the plain C ones. Preferences_test
// calls these from Objective-C++ too and mangles identically, so only the
// app's final link would catch a missing extern "C" here; do not drop it.
// __cplusplus is undefined for the plain-C parse, so this is a no-op there.
#ifdef __cplusplus
extern "C" {
#endif

// DEFINED here rather than re-declared from elsewhere: this used to be a
// second file-static copy in BundlesPreferences.mm (its own comment noted it
// mirrors DocumentWindowController.mm:43, the real consumer, which keeps its
// own independent static rather than sharing one). That AppKit-only copy is
// gone now that the checkbox binds through here instead; this is the same
// string, relocated rather than duplicated a third time.
extern NSString* _Nonnull const kUserDefaultsDisableBundleSuggestionsKey; // @"disableBundleSuggestions"

// name CONTAINS[cd] searchText, AND-ed with category IN {category} when
// category is non-nil -- filterStringDidChange:'s NSCompoundPredicate, ported
// field for field. `[cd]` is case- and diacritic-insensitive, which is what
// NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch reproduces on
// -rangeOfString:options:. An empty searchText matches everything, same as an
// absent predicate.
extern NSArray<TMBundleRow*>* _Nonnull TMBundlesFilterRows(NSArray<TMBundleRow*>* _Nonnull rows, NSString* _Nonnull searchText, NSString* _Nullable category);

extern TMBundleMenuEnablement TMBundleMenuEnablementForRow(TMBundleRow* _Nonnull row);

#ifdef __cplusplus
}
#endif
