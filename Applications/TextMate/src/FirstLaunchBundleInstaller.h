#import <Cocoa/Cocoa.h>

@class BundleSpec;

// Modal window that lists every uninstalled default-tier bundle with a
// pre-checked checkbox and lets the user install the selected set in one
// shot. Fires once per user (gated by kUserDefaultsDidPromptForDefaultBundlesKey).
//
// Enter activates Install Selected; ESC activates Skip. Skip records the
// unchecked bundles in kUserDefaultsBundlesToNeverSuggestKey so the on-demand
// per-extension prompt also leaves them alone later.

@interface FirstLaunchBundleInstaller : NSWindowController
+ (void)promptIfNeeded;

// Shipped-origin bundles that are neither installed nor marked never-suggest,
// sorted by category then name. Exposed for the Setup Assistant, which
// replaces this class's window while keeping its selection logic.
+ (NSArray<BundleSpec*>*)candidateSpecs;
@end
