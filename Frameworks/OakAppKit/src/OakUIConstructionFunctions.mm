#import "OakUIConstructionFunctions.h"
#import "NSColor Additions.h"
#import "NSImage Additions.h"

NSFont* OakStatusBarFont ()
{
	return [NSFont messageFontOfSize:[NSUserDefaults.standardUserDefaults integerForKey:@"statusBarFontSize"] ?: 12];
}

NSFont* OakControlFont ()
{
	return [NSFont messageFontOfSize:0];
}

NSTextField* OakCreateLabel (NSString* label, NSFont* font, NSTextAlignment alignment, NSLineBreakMode lineBreakMode)
{
	// This was introduced in 10.12 but does not appear to use controlTextColor until 10.14, which is required for proper highlight when used in a table view
	if(@available(macos 10.14, *))
	{
		NSTextField* res = [NSTextField labelWithString:label];
		[[res cell] setLineBreakMode:lineBreakMode];
		res.alignment = alignment;
		if(font)
			res.font = font;
		return res;
	}

	NSTextField* res = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[[res cell] setWraps:NO];
	[[res cell] setLineBreakMode:lineBreakMode];
	res.alignment       = alignment;
	res.bezeled         = NO;
	res.bordered        = NO;
	res.drawsBackground = NO;
	res.editable        = NO;
	res.font            = font ?: OakControlFont();
	res.selectable      = NO;
	res.stringValue     = label;
	return res;
}

NSButton* OakCreateCheckBox (NSString* label)
{
	if(@available(macos 10.14, *))
	{
		NSButton* res = [NSButton checkboxWithTitle:(label ?: @"") target:nil action:nil];
		// When we have a row that only contains checkboxes (e.g. Find options), nothing restrains the height of that row
		[res setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
		return res;
	}

	NSButton* res = [[NSButton alloc] initWithFrame:NSZeroRect];
	[res setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
	res.buttonType = NSButtonTypeSwitch;
	res.font       = OakControlFont();
	res.title      = label;
	return res;
}

NSButton* OakCreateButton (NSString* label, NSBezelStyle bezel)
{
	NSButton* res = [NSButton buttonWithTitle:label target:nil action:nil];
	if(bezel != NSBezelStyleRounded)
		res.bezelStyle = bezel;
	return res;
}

NSPopUpButton* OakCreatePopUpButton (BOOL pullsDown, NSString* initialItemTitle, NSView* labelView)
{
	NSPopUpButton* res = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:pullsDown];
	if(initialItemTitle)
		[[res cell] setMenuItem:[[NSMenuItem alloc] initWithTitle:initialItemTitle action:NULL keyEquivalent:@""]];
	if(labelView)
		res.accessibilityTitleUIElement = labelView;
	return res;
}

NSPopUpButton* OakCreateActionPopUpButton (BOOL bordered)
{
	NSPopUpButton* res = [NSPopUpButton new];
	res.pullsDown = YES;
	res.bordered = bordered;

	NSMenuItem* item = [NSMenuItem new];
	item.title = @"";
	item.image = [NSImage imageNamed:NSImageNameActionTemplate];
	[item.image setSize:NSMakeSize(14, 14)];

	[[res cell] setUsesItemFromMenu:NO];
	[[res cell] setMenuItem:item];
	res.accessibilityLabel = @"Actions";

	return res;
}

NSComboBox* OakCreateComboBox (NSView* labelView)
{
	NSComboBox* res = [[NSComboBox alloc] initWithFrame:NSZeroRect];
	res.font = OakControlFont();
	res.accessibilityTitleUIElement = labelView;
	return res;
}

OakRolloverButton* OakCreateCloseButton (NSString* accessibilityLabel)
{
	OakRolloverButton* closeButton = [[OakRolloverButton alloc] initWithFrame:NSZeroRect];
	closeButton.regularImage  = [NSImage imageNamed:@"CloseTemplate"         inSameBundleAsClass:[OakRolloverButton class]];
	closeButton.pressedImage  = [NSImage imageNamed:@"ClosePressedTemplate"  inSameBundleAsClass:[OakRolloverButton class]];
	closeButton.rolloverImage = [NSImage imageNamed:@"CloseRolloverTemplate" inSameBundleAsClass:[OakRolloverButton class]];

	closeButton.accessibilityLabel = accessibilityLabel;
	return closeButton;
}

// =========================
// = OakBackgroundFillView =
// =========================

@implementation OakBackgroundFillView
{
	NSView* _visualEffectBackgroundView;
	id _activeBackgroundValue;
	id _inactiveBackgroundValue;
}

- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_style = OakBackgroundFillViewStyleNone;
		[self setWantsLayer:YES]; // required by the glass background updateBackgroundStyle installs
	}
	return self;
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow
{
	if(self.window)
	{
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidBecomeMainNotification object:self.window];
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignMainNotification object:self.window];
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidBecomeKeyNotification object:self.window];
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:self.window];
	}

	if(newWindow)
	{
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeMainOrKey:) name:NSWindowDidBecomeMainNotification object:newWindow];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeMainOrKey:) name:NSWindowDidResignMainNotification object:newWindow];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeMainOrKey:) name:NSWindowDidBecomeKeyNotification object:newWindow];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeMainOrKey:) name:NSWindowDidResignKeyNotification object:newWindow];
	}

	self.active = ([newWindow styleMask] & NSWindowStyleMaskFullScreen) || [newWindow isMainWindow] || [newWindow isKeyWindow];
}

- (void)windowDidChangeMainOrKey:(NSNotification*)aNotification
{
	self.active = ([self.window styleMask] & NSWindowStyleMaskFullScreen) || [self.window isMainWindow] || [self.window isKeyWindow];
}

- (void)setActive:(BOOL)flag
{
	if(_active == flag)
		return;
	_active = flag;
	self.needsDisplay = YES;
}

- (void)setActiveBackgroundValue:(id)value
{
	if(value == _activeBackgroundValue || [value isEqual:_activeBackgroundValue])
		return;
	_activeBackgroundValue = value;
	if(_active)
		self.needsDisplay = YES;
}

- (void)setInactiveBackgroundValue:(id)value
{
	if(value == _inactiveBackgroundValue || [value isEqual:_inactiveBackgroundValue])
		return;
	_inactiveBackgroundValue = value;
	if(!_active)
		self.needsDisplay = YES;
}

- (void)setActiveBackgroundColor:(NSColor*)aColor             { self.activeBackgroundValue = aColor;    }
- (void)setActiveBackgroundGradient:(NSGradient*)aGradient    { self.activeBackgroundValue = aGradient; }
- (void)setInactiveBackgroundColor:(NSColor*)aColor           { self.inactiveBackgroundValue = aColor;    }
- (void)setInactiveBackgroundGradient:(NSGradient*)aGradient  { self.inactiveBackgroundValue = aGradient; }

- (NSColor*)activeBackgroundColor          { return [_activeBackgroundValue isKindOfClass:[NSColor class]]      ? _activeBackgroundValue   : nil; }
- (NSGradient*)activeBackgroundGradient    { return [_activeBackgroundValue isKindOfClass:[NSGradient class]]   ? _activeBackgroundValue   : nil; }
- (NSColor*)inactiveBackgroundColor        { return [_inactiveBackgroundValue isKindOfClass:[NSColor class]]    ? _inactiveBackgroundValue : nil; }
- (NSGradient*)inactiveBackgroundGradient  { return [_inactiveBackgroundValue isKindOfClass:[NSGradient class]] ? _inactiveBackgroundValue : nil; }

- (NSSize)intrinsicContentSize
{
	return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (void)setStyle:(OakBackgroundFillViewStyle)aStyle
{
	if(_style == aStyle)
		return;

	_style = aStyle;
	[self updateBackgroundStyle];
	self.needsDisplay = YES;
}

- (void)updateBackgroundStyle
{
	if(_visualEffectBackgroundView)
	{
		[_visualEffectBackgroundView removeFromSuperview];
		_visualEffectBackgroundView = nil;
	}

	if(self.style == OakBackgroundFillViewStyleHeader)
	{
		NSGlassEffectView* effectView = OakCreateGlassBackground(NSGlassEffectViewStyleRegular);

		// OakCreateGlassBackground turns this off for its constraint-driven callers.
		// This site is frame-driven and sizes itself with autoresizingMask, which
		// does nothing while that flag is NO -- the view stays 0x0 and invisible.
		effectView.translatesAutoresizingMaskIntoConstraints = YES;

		// Autoresizing only corrects size on a later superview resize event; it does
		// not retroactively fix a mismatch that already exists when the subview is
		// added. self may already be at its real size here, so match it explicitly
		// the way initWithFrame:[self bounds] used to.
		effectView.frame = [self bounds];

		_visualEffectBackgroundView = effectView;
		[_visualEffectBackgroundView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
		[self addSubview:_visualEffectBackgroundView positioned:NSWindowBelow relativeTo:nil];
	}
}

- (void)drawRect:(NSRect)aRect
{
	if(_visualEffectBackgroundView != nil)
	{
		[super drawRect:aRect];
		return;
	}

	id value = _active || !_inactiveBackgroundValue ? _activeBackgroundValue : _inactiveBackgroundValue;
	if([value isKindOfClass:[NSGradient class]])
	{
		NSGradient* gradient = value;
		[gradient drawInRect:self.bounds angle:270];
	}
	else if([value isKindOfClass:[NSColor class]])
	{
		NSColor* color = value;
		[color set];
		NSRectFill(self.bounds);
	}
}
@end

OakBackgroundFillView* OakCreateVerticalLine (OakBackgroundFillViewStyle style)
{
	OakBackgroundFillView* view = [[OakBackgroundFillView alloc] initWithFrame:NSZeroRect];
	view.style = style;
	[view addConstraint:[NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:1]];
	view.translatesAutoresizingMaskIntoConstraints = NO;
	return view;
}

NSView* OakCreateNSBoxSeparator ()
{
	NSBox* box = [[NSBox alloc] initWithFrame:NSZeroRect];
	box.boxType = NSBoxSeparator;
	return box;
}

void OakSetupKeyViewLoop (NSArray<NSView*>* superviews)
{
	std::set<NSView*> seen;
	for(NSView* candidate in superviews)
		seen.insert(candidate);

	NSMutableArray<NSView*>* views = [NSMutableArray new];
	for(NSView* view in superviews)
	{
		[views addObject:view];
		NSView* subview = view;
		while((subview = subview.nextKeyView) && [subview isDescendantOf:view] && seen.insert(subview).second)
			[views addObject:subview];
	}

	for(NSUInteger i = 0; i < views.count; ++i)
		views[i].nextKeyView = views.count == 1 ? nil : views[(i+1) % views.count];
}

void OakAddAutoLayoutViewsToSuperview (NSArray<NSView*>* views, NSView* superview)
{
	for(NSView* view in views)
	{
		if([view isEqual:[NSNull null]])
			continue;
		[view setTranslatesAutoresizingMaskIntoConstraints:NO];
		[superview addSubview:view];
	}
}

NSGlassEffectContainerView* OakCreateGlassContainer (CGFloat spacing)
{
	NSGlassEffectContainerView* res = [[NSGlassEffectContainerView alloc] initWithFrame:NSZeroRect];
	res.translatesAutoresizingMaskIntoConstraints = NO;
	res.spacing = spacing;
	return res;
}

NSGlassEffectView* OakCreateGlassBackground (NSGlassEffectViewStyle style, NSColor* tint)
{
	NSGlassEffectView* res = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
	res.translatesAutoresizingMaskIntoConstraints = NO;
	res.style = style;
	res.cornerRadius = OakGlassChromeMetrics().cornerRadius;
	if(tint)
		res.tintColor = tint;
	return res;
}

OakGlassMetrics OakGlassChromeMetrics ()
{
	return { .cornerRadius = 12, .contentInsets = NSEdgeInsetsMake(8, 12, 8, 12) };
}

NSView* OakWrapInGlass (NSView* bar, NSGlassEffectViewStyle style)
{
	NSGlassEffectView* glass = OakCreateGlassBackground(style);

	NSView* holder = [[NSView alloc] initWithFrame:NSZeroRect];
	holder.translatesAutoresizingMaskIntoConstraints = NO;
	glass.contentView = holder;

	OakAddAutoLayoutViewsToSuperview(@[ glass ], bar);
	[glass.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor].active   = YES;
	[glass.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor].active = YES;
	[glass.topAnchor constraintEqualToAnchor:bar.topAnchor].active           = YES;
	[glass.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor].active     = YES;

	return holder;
}
