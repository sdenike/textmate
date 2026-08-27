// Frameworks/SoftwareUpdate/src/SUButtonSpec.h
//
// Pure title/enabled/role description of the update sheet's buttons, one
// state at a time -- independent of what clicking a button actually does.
// SoftwareUpdate.mm zips this shape together with the real action block once
// it knows what each button should do; this header exists so the shape
// itself -- which title, which is enabled, which carries the return/escape
// key equivalent, for each of presentUIForBackgroundCheck:'s three orderings
// -- can be exercised without any window or SwiftUI view, in
// tests/t_SUButtonSpec.mm.

#import <Foundation/Foundation.h>

@interface SUButtonSpec : NSObject
@property (nonatomic, readonly) NSString* title;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL isDefault; // gets the "\r" key equivalent
@property (nonatomic, readonly) BOOL isCancel;  // gets the "\e" key equivalent
+ (instancetype)specWithTitle:(NSString*)title enabled:(BOOL)enabled isDefault:(BOOL)isDefault isCancel:(BOOL)isCancel;
@end

// presentUIForBackgroundCheck:'s three ordering states, matching the old
// addButtonWithTitle: sequence exactly:
//
//   NSOrderedAscending  (update available) -- "Download" (default) and,
//     titled "Later" for a background check or "Cancel" for a manual one,
//     a SECOND button that gets "\e" regardless of which title it has --
//     the old code set self.buttons.lastObject.keyEquivalent unconditionally.
//   NSOrderedSame       (up to date)       -- "OK" (default), plus a
//     "Redownload" button when allowRedownload, neither one a cancel.
//   NSOrderedDescending (prerelease)       -- "OK" (default), plus
//     "Downgrade to <remoteVersion>", not a cancel either.
extern NSArray<SUButtonSpec*>* SUButtonsForVersionCheck (NSComparisonResult ordering, BOOL backgroundCheck, BOOL allowRedownload, NSString* remoteVersion);
