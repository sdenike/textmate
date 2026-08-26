// Frameworks/Preferences/src/Preferences-Bridging-Header.h
//
// The ONLY Objective-C surface Swift sees in this framework. Keep it small.
//
// ClangImporter compiles this as C/Objective-C without GCC_PREFIX_HEADER, so
// it imports Foundation itself and may contain no C++. It must NOT import
// anything under Xcode/include/ -- those headers rely on the prelude for
// their Foundation and AppKit types and fail here with "unknown type name".
//
// The keys below are DECLARED here and DEFINED in
// Frameworks/SoftwareUpdate/src/SoftwareUpdate.mm:12-19. Re-declaring an
// extern shares the symbol rather than copying the value, so a name typo is a
// link error rather than a wrong key that compiles and passes its tests.

// Cocoa, not just Foundation, for the encoding shim's NSPopUpButton below --
// a system umbrella header, which is fine here; a header out of
// Xcode/include/ is not.
#import <Cocoa/Cocoa.h>
#import "SettingsFieldsBridge.h"
#import "SettingsVariablesBridge.h"

extern NSString* const kUserDefaultsDisableSoftwareUpdateKey;   // @"SoftwareUpdateDisablePolling"
extern NSString* const kUserDefaultsAskBeforeUpdatingKey;       // @"SoftwareUpdateAskBeforeUpdating"
extern NSString* const kUserDefaultsSoftwareUpdateChannelKey;   // @"SoftwareUpdateChannel"
extern NSString* const kUserDefaultsLastSoftwareUpdateCheckKey; // @"SoftwareUpdateLastPoll"

extern NSString* const kSoftwareUpdateChannelRelease;           // @"release"
extern NSString* const kSoftwareUpdateChannelPrerelease;        // @"beta"
extern NSString* const kSoftwareUpdateChannelCanary;            // @"nightly"

// The keys below are DEFINED in Frameworks/Preferences/src/Keys.mm, this
// framework's own key file -- unlike the SoftwareUpdate keys above, no
// cross-framework indirection is needed.
extern NSString* const kUserDefaultsFoldersOnTopKey;                   // @"foldersOnTop"
extern NSString* const kUserDefaultsAllowExpandingLinksKey;            // @"allowExpandingLinks"
extern NSString* const kUserDefaultsFileBrowserSingleClickToOpenKey;   // @"fileBrowserSingleClickToOpen"
extern NSString* const kUserDefaultsAutoRevealFileKey;                 // @"autoRevealFile"
extern NSString* const kUserDefaultsFileBrowserPlacementKey;           // @"fileBrowserPlacement"
extern NSString* const kUserDefaultsDisableFileBrowserWindowResizeKey; // @"disableFileBrowserWindowResize"
extern NSString* const kUserDefaultsDisableTabBarCollapsingKey;        // @"disableTabBarCollapsing"
extern NSString* const kUserDefaultsDisableTabReorderingKey;           // @"disableTabReordering"
extern NSString* const kUserDefaultsDisableTabAutoCloseKey;            // @"disableTabAutoClose"
extern NSString* const kUserDefaultsHTMLOutputPlacementKey;            // @"htmlOutputPlacement"
extern NSString* const kUserDefaultsEnvironmentVariablesKey;           // @"environmentVariables"
extern NSString* const kUserDefaultsDisableSessionRestoreKey;            // @"disableSessionRestore"
extern NSString* const kUserDefaultsDisableNewDocumentAtStartupKey;      // @"disableNewDocumentAtStartup"
extern NSString* const kUserDefaultsDisableNewDocumentAtReactivationKey; // @"disableNewDocumentAtReactivation"

// The Files pane keeps OakEncodingPopUpButton rather than rebuilding it in
// SwiftUI: the control reads Charsets.plist and maintains the user's own
// subset of it in the availableEncodings default, with a "Customize List…"
// window behind it, none of which is worth reimplementing to gain a Picker.
// Three functions rather than the class itself, because
// OakAppKit/OakEncodingPopUpButton.h takes its NSPopUpButton from
// GCC_PREFIX_HEADER and does not parse standalone here -- this is the narrow
// pure-ObjC shim CLAUDE.md prescribes. Defined in FilesPreferences.mm, its
// only caller's neighbour, since OakAppKit is linked by Preferences and not by
// PreferencesSupport. Swift observes changes by KVO on "encoding"; the control
// has no target/action of its own (its menu items target the button).
#ifdef __cplusplus
extern "C" {
#endif
extern NSPopUpButton* _Nonnull TMCreateEncodingPopUpButton(void);
extern NSString* _Nullable TMEncodingPopUpButtonGetEncoding(NSPopUpButton* _Nonnull button);
extern void TMEncodingPopUpButtonSetEncoding(NSPopUpButton* _Nonnull button, NSString* _Nullable encoding);
#ifdef __cplusplus
}
#endif
