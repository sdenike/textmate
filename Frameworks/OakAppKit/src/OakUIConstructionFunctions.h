#import "OakRolloverButton.h"
typedef NS_ENUM(NSUInteger, OakBackgroundFillViewStyle) {
	OakBackgroundFillViewStyleNone = 0,
	OakBackgroundFillViewStyleHeader,
};

@interface OakBackgroundFillView : NSView
@property (nonatomic) OakBackgroundFillViewStyle style;
@property (nonatomic) NSColor* activeBackgroundColor;
@property (nonatomic) NSColor* inactiveBackgroundColor;
@property (nonatomic) NSGradient* activeBackgroundGradient;
@property (nonatomic) NSGradient* inactiveBackgroundGradient;
@property (nonatomic) BOOL active;
@end

NSFont* OakStatusBarFont ();
NSFont* OakControlFont ();

NSTextField* OakCreateLabel (NSString* label = @"", NSFont* font = nil, NSTextAlignment alignment = NSTextAlignmentLeft, NSLineBreakMode lineBreakMode = NSLineBreakByTruncatingMiddle);
NSButton* OakCreateCheckBox (NSString* label);
NSButton* OakCreateButton (NSString* label, NSBezelStyle bezel = NSBezelStyleRounded);
NSPopUpButton* OakCreatePopUpButton (BOOL pullsDown = NO, NSString* initialItemTitle = nil, NSView* labelView = nil);
NSPopUpButton* OakCreateActionPopUpButton (BOOL bordered = NO);
NSComboBox* OakCreateComboBox (NSView* labelView = nil);
OakRolloverButton* OakCreateCloseButton (NSString* accessibilityLabel = @"Close document");
NSView* OakCreateNSBoxSeparator ();

// Liquid Glass (macOS 26). Adjacent glass surfaces must share a container or
// they each sample the backdrop independently and the seam shows.
NSGlassEffectContainerView* OakCreateGlassContainer ();

// `style` is NSGlassEffectViewStyleRegular for chrome sitting over content, or
// NSGlassEffectViewStyleClear for transient overlays that should read through.
// `tint` may be nil for the system default; when non-nil it must be a dynamic
// colour that resolves for both light and dark appearance.
//
// Put content in the returned view's `contentView`. Adding subviews directly
// does not composite correctly.
NSGlassEffectView* OakCreateGlassBackground (NSGlassEffectViewStyle style, NSColor* tint = nil);

// Shared chrome geometry, so surfaces do not each invent their own. These are
// starting values chosen to match macOS 26 system chrome; if screenshot review
// during a later increment shows they are wrong, change them here once.
struct OakGlassMetrics
{
	CGFloat cornerRadius;
	NSEdgeInsets contentInsets;
};

OakGlassMetrics OakGlassChromeMetrics ();

OakBackgroundFillView* OakCreateVerticalLine (OakBackgroundFillViewStyle style);
void OakSetupKeyViewLoop (NSArray<NSView*>* views);
void OakAddAutoLayoutViewsToSuperview (NSArray<NSView*>* views, NSView* superview);
