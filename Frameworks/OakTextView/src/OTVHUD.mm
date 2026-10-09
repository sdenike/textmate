#import "OTVHUD.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface OTVHUD ()
{
	NSTextField* _textField;
	NSUInteger _requestID;
}
@property (nonatomic, weak) NSView* lastView;
@end

@implementation OTVHUD
- (instancetype)initWithView:(NSView*)aView
{
	CGFloat const kWidth  = 100;
	CGFloat const kHeight = 30;

	NSRect aRect = [aView.window convertRectToScreen:[aView convertRect:[aView visibleRect] toView:nil]];
	aRect = NSInsetRect(aRect, 10, 10);
	aRect = NSMakeRect(NSMaxX(aRect) - kWidth, NSMaxY(aRect) - kHeight, kWidth, kHeight);

	NSWindow* window = [[NSWindow alloc] initWithContentRect:aRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	if(!window)
		return nil;

	if(self = [super initWithWindow:window])
	{
		_lastView = aView;

		window.ignoresMouseEvents = YES;
		window.backgroundColor    = [NSColor clearColor];
		window.opaque             = NO;
		window.level              = NSPopUpMenuWindowLevel;

		// A transient overlay that should read through to the text beneath it, so
		// Clear glass rather than Regular. The label is the glass's content, centred
		// in a holder: AppKit pins contentView to fill the glass, and a label drawn
		// to fill would sit at the top rather than the middle.
		NSView* contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)];
		window.contentView = contentView;

		NSGlassEffectView* glass = OakCreateGlassBackground(NSGlassEffectViewStyleClear);
		glass.translatesAutoresizingMaskIntoConstraints = YES;
		glass.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		glass.frame            = contentView.bounds;
		glass.cornerRadius     = kHeight / 2;

		_textField = OakCreateLabel(@"", [NSFont systemFontOfSize:20]);
		self.stringValue = @"88888";

		NSView* holder = [[NSView alloc] initWithFrame:NSZeroRect];
		OakAddAutoLayoutViewsToSuperview(@[ _textField ], holder);
		[_textField.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor].active   = YES;
		[_textField.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor].active = YES;
		[_textField.centerYAnchor constraintEqualToAnchor:holder.centerYAnchor].active   = YES;
		glass.contentView = holder;

		[contentView addSubview:glass];
	}
	return self;
}

- (void)setStringValue:(NSString*)someText
{
	NSMutableParagraphStyle* pStyle = [NSMutableParagraphStyle new];
	[pStyle setAlignment:NSTextAlignmentCenter];

	_textField.objectValue = [[NSMutableAttributedString alloc] initWithString:someText attributes:@{
		NSParagraphStyleAttributeName:  pStyle,
		NSForegroundColorAttributeName: NSColor.labelColor
	}];
}

- (void)fadeOut:(id)sender
{
	NSUInteger requestID = _requestID;

	[NSAnimationContext beginGrouping];
	[NSAnimationContext currentContext].completionHandler = ^{
		if(requestID == _requestID)
			[self close];
	};
	[self.window.animator setAlphaValue:0];
	[NSAnimationContext endGrouping];
}

- (void)showWindow:(id)sender
{
	++_requestID;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fadeOut:) object:nil];

	[NSAnimationContext beginGrouping];
	[NSAnimationContext currentContext].duration = 0;
	[self.window.animator setAlphaValue:1];
	[NSAnimationContext endGrouping];

	[super showWindow:sender];

	[self performSelector:@selector(fadeOut:) withObject:nil afterDelay:1];
}

+ (OTVHUD*)showHudForView:(NSView*)aView withText:(NSString*)someText
{
	static __weak OTVHUD* LastHUD;

	OTVHUD* res = LastHUD;
	if(!res || res.lastView != aView)
		LastHUD = res = [[OTVHUD alloc] initWithView:aView];

	res.stringValue = someText;
	[res showWindow:self];
	return res;
}
@end
