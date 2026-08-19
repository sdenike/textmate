// Applications/TextMate/src/SetupAssistant/SetupAssistantWindowController.mm
#import "SetupAssistantWindowController.h"
#import "SetupAssistantGating.h"
#import "SetupAssistantTypes.h"
#import "TextMate-Swift.h"
#import <bundles/bundles.h>
#import <theme/theme.h>
#import <ns/ns.h>

@interface SetupAssistantWindowController () <NSWindowDelegate, TMSetupAssistantHost>
@end

// Nine roles, matching the keys declared in SetupAssistantTypes.h. Background
// and foreground come from theme_t's own accessors (theme.h:77-78) rather
// than through styles_for_scope: those two are the theme's root colors with
// no scope-selector merge involved, so they cannot pick up a stray per-scope
// override the way a wildcard-scoped lookup could. Caret and selection have
// no such root accessor -- styles_t is the only place they live -- so those
// two go through styles_for_scope(scope::wildcard), same as the per-token
// lookups below.
static NSDictionary<NSString*, NSColor*>* colors_for_theme (theme_ptr const& theme)
{
	auto color = [&theme](char const* scopeString){
		auto const& styles = theme->styles_for_scope(scope::scope_t(scopeString));
		return [NSColor colorWithCGColor:styles.foreground()];
	};

	auto const& base = theme->styles_for_scope(scope::wildcard);
	return @{
		TMThemeColorBackground: [NSColor colorWithCGColor:theme->background()],
		TMThemeColorForeground: [NSColor colorWithCGColor:theme->foreground()],
		TMThemeColorSelection:  [NSColor colorWithCGColor:base.selection()],
		TMThemeColorCaret:      [NSColor colorWithCGColor:base.caret()],
		TMThemeColorComment:    color("comment"),
		TMThemeColorString:     color("string.quoted.double"),
		TMThemeColorKeyword:    color("keyword.control"),
		TMThemeColorNumber:     color("constant.numeric"),
		TMThemeColorFunction:   color("entity.name.function"),
	};
}

@implementation SetupAssistantWindowController
+ (instancetype)sharedInstance
{
	static SetupAssistantWindowController* instance = [self new];
	return instance;
}

- (instancetype)init
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 460) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
	window.title = @"Setup Assistant";
	[window center];

	if(self = [super initWithWindow:window])
	{
		window.contentView = [SetupAssistantHostingController viewFor:self];
		// NSWindowController does not become its window's delegate on its own.
		// Without this, -windowWillClose: below never fires, -stopModal never
		// runs, and the title-bar close button leaves the app in a modal
		// session with no window -- unresponsive, with no way out but a
		// force-quit.
		window.delegate = self;
	}
	return self;
}

- (void)runModal
{
	// The Help menu item stays enabled while the assistant is open (nothing in
	// validateMenuItem: special-cases it), so this can be re-entered. Calling
	// runModalForWindow: a second time on the same window would start a nested
	// modal session; closing the window then fires windowWillClose: only once,
	// so stopModal unwinds just the inner session and the outer one is left
	// blocked forever with the window already ordered out -- an unresponsive
	// app with no window on screen. isVisible reflects AppKit's own bookkeeping
	// for exactly the span this class puts the window on screen (set only as a
	// side effect of runModalForWindow: below, cleared by the unconditional
	// orderOut: that follows it), so re-entering here can only ever observe
	// "currently in a session" or "not" -- there is no separate flag to leave
	// stuck on if a session ends abnormally.
	if(self.window.isVisible)
	{
		[self.window makeKeyAndOrderFront:self];
		return;
	}

	[self.window center];
	[NSApp runModalForWindow:self.window];
	[self.window orderOut:self];
	TMSetupAssistantMarkAsRun(NSUserDefaults.standardUserDefaults);
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	// Closing the window with the title-bar button must end the modal session,
	// or the app is left running a session with no window and stops responding
	// to everything.
	[NSApp stopModal];
}

- (NSArray<TMThemeChoice*>*)availableThemes
{
	NSMutableArray<TMThemeChoice*>* res = [NSMutableArray array];
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeTheme))
	{
		theme_ptr theme = parse_theme(item);
		if(!theme)
			continue;

		// The themes menu classifies by the same field (AppController
		// Menus.mm:152-156), so the assistant and View -> Theme agree on
		// which themes are light and which are dark.
		NSString* appearance = TMThemeAppearanceForSemanticClass(to_ns(item->value_for_field(bundles::kFieldSemanticClass)));
		[res addObject:[TMThemeChoice choiceWithName:to_ns(item->name()) identifier:to_ns(to_s(item->uuid())) appearance:appearance colors:colors_for_theme(theme)]];
	}
	[res sortUsingComparator:^NSComparisonResult(TMThemeChoice* a, TMThemeChoice* b){
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return res;
}

- (NSArray<TMBundleChoice*>*)availableBundles                                 { return @[]; }

- (NSString*)currentAppearance
{
	return [NSUserDefaults.standardUserDefaults stringForKey:@"themeAppearance"];
}

- (NSString*)currentThemeIdentifierForAppearance:(NSString*)appearance
{
	NSString* key = [appearance isEqualToString:@"dark"] ? @"darkModeThemeUUID" : @"universalThemeUUID";
	return [NSUserDefaults.standardUserDefaults stringForKey:key];
}

- (void)applyThemeIdentifier:(NSString*)identifier appearance:(NSString*)appearance
{
	// Same keys View -> Theme writes via takeUniversalThemeUUIDFrom: and
	// takeDarkThemeUUIDFrom: (AppController Menus.mm:103-111), so the two
	// routes cannot diverge.
	NSString* key = [appearance isEqualToString:@"dark"] ? @"darkModeThemeUUID" : @"universalThemeUUID";
	if(identifier)
		[NSUserDefaults.standardUserDefaults setObject:identifier forKey:key];
}

- (void)applyAppearance:(NSString*)appearance
{
	// Same key View -> Theme writes via takeThemeAppearanceFrom:
	// (AppController Menus.mm:98-101). Absent means automatic.
	if(appearance)
			[NSUserDefaults.standardUserDefaults setObject:appearance forKey:@"themeAppearance"];
	else	[NSUserDefaults.standardUserDefaults removeObjectForKey:@"themeAppearance"];
}

- (void)installBundleIdentifiers:(NSArray<NSString*>*)install neverSuggest:(NSArray<NSString*>*)neverSuggest { }

- (void)finishWithSkip:(BOOL)skipped
{
	[NSApp stopModal];
}
@end
