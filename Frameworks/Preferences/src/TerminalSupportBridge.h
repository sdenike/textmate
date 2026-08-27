// Frameworks/Preferences/src/TerminalSupportBridge.h
#import <Foundation/Foundation.h>

// One row of the Terminal pane's "Location:" popup. isSeparator/isOther mirror
// the two synthetic rows SettingsFileBrowserLocationItem uses for the same
// purpose in the Projects pane: a Divider has no meaningful title, and "Other…"
// carries no path of its own -- selecting it means "show a save panel", not
// "install here".
@interface TMInstallPathItem : NSObject
@property (nonatomic, readonly) NSString* _Nonnull title;
@property (nonatomic, readonly) BOOL isSeparator;
@property (nonatomic, readonly) BOOL isOther;
- (instancetype _Nonnull)initWithTitle:(NSString* _Nonnull)title isSeparator:(BOOL)isSeparator isOther:(BOOL)isOther;
@end

// extern "C": TerminalSupportBridge.mm is Objective-C++, so without this the
// definition there gets a C++-mangled symbol while a plain-C caller looks up
// the unmangled one. _Nonnull/_Nullable rather than NS_ASSUME_NONNULL_BEGIN/END
// because the bare nullable/nonnull keyword fails to parse when this header is
// read standalone as the Swift bridging header.
#ifdef __cplusplus
extern "C" {
#endif

// Reproduces -updatePopUp:'s ordering exactly: any current path that is
// neither of the two standard ones sorts first, then the two standard paths,
// then a separator, then "Other…". currentPath is nil when nothing is
// installed and nothing has been picked yet, and is otherwise ALREADY
// abbreviated with ~ -- TerminalPreferences.mm does that before calling in, the
// same division of labour SettingsFieldsBridge.h uses (Foundation path
// manipulation stays with the caller; this is the pure ordering rule, which is
// what t_terminal_support.mm exercises).
extern NSArray<TMInstallPathItem*>* _Nonnull TMTerminalInstallPathItems(NSString* _Nullable currentPath);

#ifdef __cplusplus
}
#endif
