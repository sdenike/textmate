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
//
// Put the glass views you want merged inside the returned container's
// `contentView`, not as direct subviews of the container itself -- the SDK
// documents the container as acting only on `contentView`'s descendants: "The
// glass effect container view does the following: 1. Elevates the z-order of
// descendants of `contentView` to position them above the `contentView`. 2.
// Merges descendants together if the views are sufficiently similar and
// within the proximity specified in spacing. 3. Processes similar glass
// effect views as a batch to improve performance."
//
// `spacing` is the proximity, in points, within which glass descendants of
// `contentView` merge. Per the SDK: "The default value, zero, is sufficient
// for batch processing eligible glass effect views, while avoiding distortion
// and merging effects for other views in close proximity." That means a
// spacing-0 container does NOT merge separate glass views just because they
// sit near each other -- a caller wanting two adjacent glass surfaces (e.g.
// the file browser's header and actions bars) to merge and hide their seam
// must pass a non-zero spacing.
NSGlassEffectContainerView* OakCreateGlassContainer (CGFloat spacing = 0);

// `style` is NSGlassEffectViewStyleRegular for chrome sitting over content, or
// NSGlassEffectViewStyleClear for transient overlays that should read through.
// `tint` may be nil for the system default; when non-nil it must be a dynamic
// colour that resolves for both light and dark appearance.
//
// Put content in the returned view's `contentView`. Adding subviews directly
// does not composite correctly. `cornerRadius` from OakGlassChromeMetrics()
// is applied automatically -- callers do not need to set it themselves.
NSGlassEffectView* OakCreateGlassBackground (NSGlassEffectViewStyle style, NSColor* tint = nil);

// Shared chrome geometry, so surfaces do not each invent their own. These are
// starting values chosen to match macOS 26 system chrome; if screenshot review
// during a later increment shows they are wrong, change them here once.
//
// `cornerRadius` is applied by OakCreateGlassBackground to the view it
// returns. `contentInsets` has no counterpart property on NSGlassEffectView --
// it is advisory data for callers building their own layout constraints
// around `contentView`; nothing applies it automatically.
struct OakGlassMetrics
{
	CGFloat cornerRadius;
	NSEdgeInsets contentInsets;
};

OakGlassMetrics OakGlassChromeMetrics ();

// Restructures `bar` to draw its background with glass, and returns the view its
// controls should be added to.
//
// NSGlassEffectView hosts content through contentView and guarantees placement
// only for that view -- the SDK header is explicit that "arbitrary subviews
// aren't guaranteed specific behavior with regard to z-order in relation to the
// content view or glass effect". So a bar cannot simply gain a glass subview and
// keep adding controls to itself; the controls move into a holder that becomes
// the glass's contentView.
//
// Add controls to the RETURNED view, never to `bar` itself.
NSView* OakWrapInGlass (NSView* bar, NSGlassEffectViewStyle style);

OakBackgroundFillView* OakCreateVerticalLine (OakBackgroundFillViewStyle style);
void OakSetupKeyViewLoop (NSArray<NSView*>* views);
void OakAddAutoLayoutViewsToSuperview (NSArray<NSView*>* views, NSView* superview);
