#import <Cocoa/Cocoa.h>

@class BundleSpec;

// Formerly a modal window, shown once per user, that listed every
// uninstalled default-tier bundle with a pre-checked checkbox and let the
// user install the selected set in one shot. The window and its NIB-free
// construction code are gone: SetupAssistantWindowController now covers that
// flow, both at first launch and from Help > Setup Assistant..., and reuses
// this class only for its selection logic below.

@interface FirstLaunchBundleInstaller : NSWindowController

// Shipped-origin bundles that are neither installed nor marked never-suggest,
// sorted by category then name. Exposed for the Setup Assistant, which
// replaces this class's window while keeping its selection logic.
+ (NSArray<BundleSpec*>*)candidateSpecs;
@end
