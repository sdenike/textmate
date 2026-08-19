// Applications/TextMate/src/SetupAssistant/SetupAssistantTypes.h
//
// Pure Objective-C. This header is imported by TextMate-Bridging-Header.h,
// which ClangImporter compiles as C/Objective-C without the prelude prefix
// header -- so it must import its own dependencies and must never contain
// C++, nor import anything under Xcode/include/.

#import <Cocoa/Cocoa.h>

// Keys into TMThemeChoice.colors. Nine roles is enough to draw a convincing
// code sample and no more than the appearance step actually renders.
extern NSString* const TMThemeColorBackground;
extern NSString* const TMThemeColorForeground;
extern NSString* const TMThemeColorSelection;
extern NSString* const TMThemeColorCaret;
extern NSString* const TMThemeColorComment;
extern NSString* const TMThemeColorString;
extern NSString* const TMThemeColorKeyword;
extern NSString* const TMThemeColorNumber;
extern NSString* const TMThemeColorFunction;

@interface TMThemeChoice : NSObject
@property (nonatomic, copy, readonly) NSString* name;
@property (nonatomic, copy, readonly) NSString* identifier;
@property (nonatomic, copy, readonly) NSString* appearance;   // @"light", @"dark", @"unspecified"
@property (nonatomic, copy, readonly) NSDictionary<NSString*, NSColor*>* colors;
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier appearance:(NSString*)appearance colors:(NSDictionary<NSString*, NSColor*>*)colors;
@end

@interface TMBundleChoice : NSObject
@property (nonatomic, copy, readonly) NSString* name;
@property (nonatomic, copy, readonly) NSString* identifier;
@property (nonatomic, copy, readonly) NSString* category;
@property (nonatomic, readonly)       BOOL installed;
@property (nonatomic, readonly)       BOOL recommended;
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier category:(NSString*)category installed:(BOOL)installed recommended:(BOOL)recommended;
@end

// Pure rules, kept here rather than in the window controller so the test
// binary can reach them. The window controller does the C++ extraction and
// calls these; the extraction itself is verified by hand.

// Maps a bundle item's semanticClass field onto the appearance buckets the
// assistant offers. Returns @"light", @"dark" or @"unspecified".
extern NSString* TMThemeAppearanceForSemanticClass (NSString* semanticClass);

// Merges newly-declined bundle identifiers into an existing never-suggest
// list. MUST merge rather than replace: DocumentWindowController reads this
// list for its on-demand per-extension prompt.
extern NSArray<NSString*>* TMMergeNeverSuggestIdentifiers (NSArray<NSString*>* existing, NSArray<NSString*>* adding);

@protocol TMSetupAssistantHost <NSObject>
- (NSArray<TMThemeChoice*>*)availableThemes;
- (NSArray<TMBundleChoice*>*)availableBundles;
- (NSString*)currentAppearance;                                  // @"light", @"dark", or nil for automatic
- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance;
- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance;
- (void)applyAppearance:(NSString*)appearance;                  // nil means automatic
- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest;
- (void)finishWithSkip:(BOOL)skipped;
@end
