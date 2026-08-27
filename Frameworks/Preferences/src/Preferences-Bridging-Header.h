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
#import "SettingsBundlesBridge.h"
#import "SettingsFieldsBridge.h"
#import "SettingsVariablesBridge.h"
#import "TerminalSupportBridge.h"

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

// The Terminal pane's rmate section. kUserDefaultsMateInstallPathKey and
// kUserDefaultsMateInstallVersionKey are deliberately NOT re-declared here --
// the shell-support half of the pane is pushed from TerminalPreferences.mm as
// finished state (SettingsPaneMateInstall, in TerminalPane.swift) rather than
// read from defaults directly, because installing needs a filesystem check, an
// abbreviated-path display rule and format_string::expand, none of which
// SwiftUI can do on its own.
extern NSString* const kUserDefaultsDisableRMateServerKey; // @"rmateServerDisabled"
extern NSString* const kUserDefaultsRMateServerListenKey;  // @"rmateServerListen"
extern NSString* const kUserDefaultsRMateServerPortKey;    // @"rmateServerPort"
extern NSString* const kRMateServerListenLocalhost;        // @"localhost"
extern NSString* const kRMateServerListenRemote;           // @"remote"

// The Bundles pane's two negated checkboxes. kUserDefaultsDisableBundleUpdatesKey
// is DEFINED in Frameworks/BundlesManager/src/BundlesManager.mm -- BundlesManager.h
// cannot be imported here, it sits behind Xcode/include/ and pulls in
// bundles/item.h, so this is a bare re-declaration of the same extern symbol,
// the same indirection used above for the SoftwareUpdate keys.
// kUserDefaultsDisableBundleSuggestionsKey is DEFINED in
// SettingsBundlesBridge.mm, imported above.
extern NSString* const kUserDefaultsDisableBundleUpdatesKey; // @"disableBundleUpdates"

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
