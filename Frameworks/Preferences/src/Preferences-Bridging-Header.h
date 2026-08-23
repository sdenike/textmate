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

#import <Foundation/Foundation.h>
#import "SettingsFieldsBridge.h"

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
