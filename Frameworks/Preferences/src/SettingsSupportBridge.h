// Frameworks/Preferences/src/SettingsSupportBridge.h
#import <Foundation/Foundation.h>

// extern "C": SettingsSupportBridge.mm is Objective-C++, so without this the
// definition gets a C++-mangled symbol while any plain-C parse of this header
// -- including Swift's, via the bridging header -- expects an unmangled one.
// Nothing calls this from Swift today, so the mismatch was latent: the symbol
// resolved because every caller was also Objective-C++ and mangled the same
// way. `nm` showed __Z30TMSettingsLastCheckDescriptionbP8NSStringS0_.
//
// Found while adding SettingsFieldsBridge, whose functions ARE called from
// Swift and which failed to link for exactly this reason. Fixed here too
// rather than left for the next pane to trip over.
//
// __cplusplus is undefined for the plain-C parse, so this is a no-op there.
#ifdef __cplusplus
extern "C" {
#endif

// The text shown for "Last check:". Extracted from SoftwareUpdatePreferences's
// -lastCheckDescription so the precedence can be tested: checking beats an
// error, an error beats a date, and "Never" is the floor.
extern NSString* _Nonnull TMSettingsLastCheckDescription (BOOL isChecking, NSString* _Nullable errorString, NSString* _Nullable relativeDate);

#ifdef __cplusplus
}
#endif
