#import "BundlesPreferences.h"
#import "Preferences-Swift.h"
#import "SettingsBundlesBridge.h"
#import <BundlesManager/BundlesManager.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

// File-static mirror of a key declared file-static in
// DocumentWindowController.mm. kUserDefaultsDisableBundleSuggestionsKey used
// to sit here too; it is now defined in SettingsBundlesBridge.mm, the only
// place left that needs an extern-visible copy (the BundlesPane.swift
// checkbox binds through the bridging header). Keep this one in sync with
// DocumentWindowController.mm:44, same as before.
static NSString* const kUserDefaultsGrammarsToNeverSuggestKey = @"grammarsToNeverSuggest";

// Bundle.h does not declare -textSummary -- Bundle.mm implements it (backed by
// +keyPathsForValuesAffectingTextSummary) for KVC-only access from Cocoa
// bindings, which the AppKit pane read via `arrangedObjects.textSummary`.
// -pushState below calls it directly, so this is a declaration-only category
// telling the compiler the method exists rather than a change to Bundle
// itself -- BundlesManager stays untouched.
@interface Bundle (TextSummary)
- (NSString*)textSummary;
@end

@interface BundleInstallHelper : NSObject
@property (nonatomic) NSMutableSet* bundlesBeingInstalled;
@property (nonatomic) NSString* bundleInstallActivityText;
@property (nonatomic, getter = isBusy, readonly) BOOL busy;
@property (nonatomic, readonly) NSString* activityText;
@end

@implementation BundleInstallHelper
+ (instancetype)sharedInstance
{
	static BundleInstallHelper* sharedInstance = [self new];
	return sharedInstance;
}

+ (NSSet*)keyPathsForValuesAffectingBusy
{
	return [NSSet setWithObjects:@"bundlesBeingInstalled", nil];
}

+ (NSSet*)keyPathsForValuesAffectingActivityText
{
	return [NSSet setWithObjects:@"bundleInstallActivityText", nil];
}

- (instancetype)init
{
	if(self = [super init])
	{
		_bundlesBeingInstalled = [NSMutableSet set];
	}
	return self;
}

- (BOOL)isBusy
{
	return _bundlesBeingInstalled.count != 0;
}

- (NSString*)activityText
{
	if(_bundleInstallActivityText)
		return _bundleInstallActivityText;

	if(NSDate* date = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsLastBundleUpdateCheckKey])
	{
		NSString* dateString = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
#if defined(MAC_OS_X_VERSION_10_15) && (MAC_OS_X_VERSION_10_15 <= MAC_OS_X_VERSION_MAX_ALLOWED)
		if(@available(macos 10.15, *))
			dateString = -[date timeIntervalSinceNow] < 5 ? @"Just now" : [[[NSRelativeDateTimeFormatter alloc] init] localizedStringForDate:date relativeToDate:NSDate.now];
#endif
		return [NSString stringWithFormat:@"Bundle index last updated: %@", dateString];
	}

	return @"";
}

- (void)installBundle:(Bundle*)bundle
{
	if([_bundlesBeingInstalled containsObject:bundle])
		return;

	[self willChangeValueForKey:@"bundlesBeingInstalled"];
	[_bundlesBeingInstalled addObject:bundle];
	[self didChangeValueForKey:@"bundlesBeingInstalled"];

	self.bundleInstallActivityText = [NSString stringWithFormat:@"Installing ‘%@’ bundle…", bundle.name];

	[BundlesManager.sharedInstance installBundles:@[ bundle ] completionHandler:^(NSArray<Bundle*>* bundles){
		if(!bundle.installed)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Error installing ‘%@’ bundle.", bundle.name];
		else if(bundles.count == 1)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle.", bundle.name];
		else if(bundles.count == 2)
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle and one dependency.", bundle.name];
		else
			self.bundleInstallActivityText = [NSString stringWithFormat:@"Installed ‘%@’ bundle and %ld dependencies.", bundle.name, bundles.count-1];

		[self willChangeValueForKey:@"bundlesBeingInstalled"];
		[_bundlesBeingInstalled removeObject:bundle];
		[self didChangeValueForKey:@"bundlesBeingInstalled"];
	}];
}

- (void)uninstallBundle:(Bundle*)bundle
{
	[BundlesManager.sharedInstance uninstallBundle:bundle];
	self.bundleInstallActivityText = [NSString stringWithFormat:@"Uninstalled ‘%@’ bundle.", bundle.name];
}
@end

@interface Bundle (BundlesInstallPreferences)
@property (nonatomic) NSControlStateValue installedCellState;
@end

@implementation Bundle (BundlesInstallPreferences)
+ (NSSet*)keyPathsForValuesAffectingInstalledCellState
{
	return [NSSet setWithObjects:@"installed", @"bundleInstallHelper.bundlesBeingInstalled", nil];
}

- (BundleInstallHelper*)bundleInstallHelper
{
	return BundleInstallHelper.sharedInstance;
}

- (NSControlStateValue)installedCellState
{
	return [self.bundleInstallHelper.bundlesBeingInstalled containsObject:self] ? NSControlStateValueMixed : (self.isInstalled ? NSControlStateValueOn : NSControlStateValueOff);
}

- (void)setInstalledCellState:(NSControlStateValue)newValue
{
	if(self.installedCellState == NSControlStateValueOff && newValue != NSControlStateValueOff)
		[self.bundleInstallHelper installBundle:self];
	else if(self.installedCellState == NSControlStateValueOn && newValue != NSControlStateValueOn)
		[self.bundleInstallHelper uninstallBundle:self];
}
@end

@interface BundlesPreferences ()
{
	SettingsPaneBundles* _bundlesModel;
}
@end

@implementation BundlesPreferences
- (NSImage*)toolbarItemImage
{
	if(@available(macos 11.0, *))
		return [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension" accessibilityDescription:@"Bundles"];
	return [NSWorkspace.sharedWorkspace iconForFileType:@"tmbundle"];
}

- (id)init
{
	if(self = [self initWithNibName:nil bundle:nil])
	{
		self.identifier = @"Bundles";
		self.title      = @"Bundles";
	}
	return self;
}

- (void)dealloc
{
	[BundlesManager.sharedInstance removeObserver:self forKeyPath:@"bundles"];
	[BundleInstallHelper.sharedInstance removeObserver:self forKeyPath:@"bundlesBeingInstalled"];
}

// The AppKit pane got row refreshes for free from NSArrayController's content
// binding to "bundles" plus Cocoa bindings observing each Bundle's
// installedCellState. TMBundleRow is a plain value snapshot instead, so this
// KVO pair is what replaces both: BundlesManager's "bundles" fires for a
// catalogue reload (add/remove/edit/revert, and the 3h background poll while
// the pane is open), and BundleInstallHelper's "bundlesBeingInstalled" is the
// declared dependency of installedCellState itself
// (+keyPathsForValuesAffectingInstalledCellState above) -- the mixed-state
// spinner would otherwise never appear or clear.
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	[self pushState];
}

- (NSView*)createFooterView
{
	NSTextField* statusTextField = [NSTextField labelWithString:@""];
	statusTextField.textColor = NSColor.secondaryLabelColor;
	statusTextField.font = [NSFont messageFontOfSize:NSFont.smallSystemFontSize];

	NSProgressIndicator* progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	progressIndicator.controlSize          = NSControlSizeSmall;
	progressIndicator.displayedWhenStopped = NO;
	progressIndicator.style                = NSProgressIndicatorStyleSpinning;

	NSView* footerView = [[NSView alloc] initWithFrame:NSZeroRect];
	NSView* footerHolder = OakWrapInGlass(footerView, NSGlassEffectViewStyleRegular);

	NSDictionary* footerViews = @{
		@"divider": OakCreateNSBoxSeparator(),
		@"spinner": progressIndicator,
		@"status":  statusTextField,
	};
	OakAddAutoLayoutViewsToSuperview(footerViews.allValues, footerHolder);
	[footerHolder addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[divider]|"                        options:0 metrics:nil views:footerViews]];
	[footerHolder addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[spinner]-(>=8)-[status]-(>=8)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:footerViews]];
	[footerHolder addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[divider(==1)]-4-[status]-4-|"     options:0 metrics:nil views:footerViews]];
	[statusTextField.centerXAnchor constraintEqualToAnchor:footerHolder.centerXAnchor].active = YES;

	[progressIndicator bind:NSAnimateBinding toObject:BundleInstallHelper.sharedInstance withKeyPath:@"busy" options:nil];
	[statusTextField   bind:NSValueBinding   toObject:BundleInstallHelper.sharedInstance withKeyPath:@"activityText" options:nil];

	return footerHolder;
}

- (void)loadView
{
	_bundlesModel = [[SettingsPaneBundles alloc] init];

	[BundlesManager.sharedInstance addObserver:self forKeyPath:@"bundles" options:0 context:NULL];
	[BundleInstallHelper.sharedInstance addObserver:self forKeyPath:@"bundlesBeingInstalled" options:0 context:NULL];

	NSView* footer = [self createFooterView];

	__weak __typeof__(self) weakSelf = self;
	self.view = [SettingsPaneFactory bundlesViewWithModel:_bundlesModel
	                                                footer:footer
	                                     onToggleInstalled:^(NSString* identifier){ [weakSelf toggleInstalledForIdentifier:identifier]; }
	                                           onAddBundle:^(NSString* url, NSString* ref){ [weakSelf addBundleFromURL:url ref:ref]; }
	                                    onToggleAutoUpdate:^(NSString* identifier){ [weakSelf toggleAutoUpdateForIdentifier:identifier]; }
	                                           onChangeRef:^(NSString* identifier, NSString* ref){ [weakSelf changeRefForIdentifier:identifier ref:ref]; }
	                                          onEditBundle:^(NSString* identifier, NSString* url, NSString* ref){ [weakSelf editBundleForIdentifier:identifier url:url ref:ref]; }
	                                           onUninstall:^(NSString* identifier){ [weakSelf uninstallForIdentifier:identifier]; }
	                                              onRemove:^(NSString* identifier){ [weakSelf removeForIdentifier:identifier]; }
	                                              onRevert:^(NSString* identifier){ [weakSelf revertForIdentifier:identifier]; }
	                                 onCheckForUpdatesNow:^{ [weakSelf checkForUpdatesNow]; }
	                          onResetDismissedSuggestions:^{ [weakSelf resetDismissedSuggestions]; }];

	[self pushState];
}

- (void)viewWillAppear
{
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = nil;
	[self pushState];
}

// Rebuilds the row/category snapshot and the reset-dismissed enablement rule
// from scratch and hands them to _bundlesModel in one call -- the same shape
// as TerminalPreferences' -pushState, called from every place that can change
// what the pane shows: load, viewWillAppear, the two KVO observers above, and
// every action's completion block below.
- (void)pushState
{
	NSMutableSet<NSString*>* categorySet = [NSMutableSet set];
	for(Bundle* bundle in BundlesManager.sharedInstance.bundles)
	{
		if(bundle.category)
			[categorySet addObject:bundle.category];
	}

	NSMutableArray<TMBundleRow*>* rows = [NSMutableArray array];
	for(Bundle* bundle in BundlesManager.sharedInstance.bundles)
	{
		TMBundleInstallState state = TMBundleInstallStateOff;
		switch(bundle.installedCellState)
		{
			case NSControlStateValueOn:    state = TMBundleInstallStateOn;    break;
			case NSControlStateValueMixed: state = TMBundleInstallStateMixed; break;
			default:                       state = TMBundleInstallStateOff;  break;
		}

		[rows addObject:[[TMBundleRow alloc] initWithIdentifier:bundle.identifier.UUIDString
		                                                     name:bundle.name
		                                                 category:bundle.category
		                                         webLinkURLString:bundle.htmlURL.absoluteString
		                                                  updated:bundle.downloadLastUpdated
		                                              textSummary:bundle.textSummary
		                                             installState:state
		                                   installedToggleEnabled:!bundle.isMandatory || !bundle.isInstalled
		                                              isMandatory:bundle.isMandatory
		                                              isInstalled:bundle.isInstalled
		                                        autoUpdateEnabled:bundle.autoUpdateEnabled
		                                                      ref:bundle.ref
		                                        downloadURLString:bundle.downloadURL.absoluteString
		                                                     path:bundle.path
		                                          isEditedShipped:[BundlesManager.sharedInstance bundleIsEditedShippedDefault:bundle]]];
	}

	NSArray* neverSuggestBundles  = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey];
	NSArray* neverSuggestGrammars = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsGrammarsToNeverSuggestKey];
	BOOL resetDismissedEnabled = (neverSuggestBundles.count + neverSuggestGrammars.count) > 0;

	[_bundlesModel updateWithRows:rows
	                    categories:[categorySet.allObjects sortedArrayUsingSelector:@selector(localizedCompare:)]
	        resetDismissedEnabled:resetDismissedEnabled];
}

- (Bundle*)bundleWithIdentifier:(NSString*)identifier
{
	for(Bundle* bundle in BundlesManager.sharedInstance.bundles)
	{
		if([bundle.identifier.UUIDString isEqualToString:identifier])
			return bundle;
	}
	return nil;
}

// ================
// = Actions, driven by BundlesPane.swift's callbacks
// ================

- (void)toggleInstalledForIdentifier:(NSString*)identifier
{
	if(Bundle* bundle = [self bundleWithIdentifier:identifier])
		bundle.installedCellState = bundle.installedCellState == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
	[self pushState];
}

- (void)addBundleFromURL:(NSString*)url ref:(NSString*)ref
{
	NSWindow* parent = self.view.window;
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching %@…", url];

	__weak __typeof__(self) weakSelf = self;
	[BundlesManager.sharedInstance addBundleFromURL:url ref:ref name:nil completion:^(NSString* sha, NSError* error){
		if(error)
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Add failed: %@", error.localizedDescription];
			NSAlert* errAlert = [NSAlert alertWithError:error];
			[errAlert beginSheetModalForWindow:parent completionHandler:nil];
		}
		else
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Added bundle @ %@", sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
		}
		[weakSelf pushState];
	}];
}

- (void)checkForUpdatesNow
{
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = @"Checking for bundle updates…";
	__weak __typeof__(self) weakSelf = self;
	[BundlesManager.sharedInstance checkForBundleUpdatesNowWithCompletion:^{
		BundleInstallHelper.sharedInstance.bundleInstallActivityText = @"Bundle check complete.";
		[weakSelf pushState];
	}];
}

- (void)resetDismissedSuggestions
{
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsBundlesToNeverSuggestKey];
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsGrammarsToNeverSuggestKey];
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = @"Reset dismissed bundle suggestions.";
	[self pushState];
}

- (void)toggleAutoUpdateForIdentifier:(NSString*)identifier
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle || bundle.isMandatory)
		return;

	BOOL newValue = !bundle.autoUpdateEnabled;
	[BundlesManager.sharedInstance setAutoUpdate:newValue forBundle:bundle];
	bundle.autoUpdateEnabled = newValue;
	[self pushState];
}

- (void)changeRefForIdentifier:(NSString*)identifier ref:(NSString*)ref
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle || bundle.isMandatory || ref.length == 0)
		return;

	NSWindow* parent = self.view.window;
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching “%@” @ %@…", bundle.name, ref];

	__weak __typeof__(self) weakSelf = self;
	[BundlesManager.sharedInstance updateBundle:bundle url:nil ref:ref completion:^(NSString* sha, NSError* error){
		if(error)
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Change failed: %@", error.localizedDescription];
			NSAlert* errAlert = [NSAlert alertWithError:error];
			[errAlert beginSheetModalForWindow:parent completionHandler:nil];
		}
		else
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Updated “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
		}
		[weakSelf pushState];
	}];
}

- (void)editBundleForIdentifier:(NSString*)identifier url:(NSString*)url ref:(NSString*)ref
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle || bundle.isMandatory || url.length == 0)
		return;

	NSWindow* parent = self.view.window;
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Fetching “%@”…", bundle.name];

	__weak __typeof__(self) weakSelf = self;
	[BundlesManager.sharedInstance updateBundle:bundle url:url ref:(ref.length ? ref : nil) completion:^(NSString* sha, NSError* error){
		if(error)
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Edit failed: %@", error.localizedDescription];
			NSAlert* errAlert = [NSAlert alertWithError:error];
			[errAlert beginSheetModalForWindow:parent completionHandler:nil];
		}
		else
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Updated “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
		}
		[weakSelf pushState];
	}];
}

- (void)uninstallForIdentifier:(NSString*)identifier
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle || bundle.isMandatory)
		return;

	[BundleInstallHelper.sharedInstance uninstallBundle:bundle];
	[self pushState];
}

- (void)removeForIdentifier:(NSString*)identifier
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle || bundle.isMandatory)
		return;

	NSAlert* alert = [[NSAlert alloc] init];
	alert.messageText = [NSString stringWithFormat:@"Remove bundle “%@”?", bundle.name];
	alert.informativeText = @"The bundle will be uninstalled and removed from the registry. You can re-add it later from the URL.";
	[alert addButtonWithTitle:@"Remove"];
	[alert addButtonWithTitle:@"Cancel"];

	__weak __typeof__(self) weakSelf = self;
	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){
		if(response != NSAlertFirstButtonReturn)
			return;
		[BundlesManager.sharedInstance removeBundleSpec:bundle];
		BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Removed bundle “%@”.", bundle.name];
		[weakSelf pushState];
	}];
}

- (void)revertForIdentifier:(NSString*)identifier
{
	Bundle* bundle = [self bundleWithIdentifier:identifier];
	if(!bundle)
		return;

	NSWindow* parent = self.view.window;
	BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Reverting “%@”…", bundle.name];

	__weak __typeof__(self) weakSelf = self;
	[BundlesManager.sharedInstance revertBundleToDefault:bundle completion:^(NSString* sha, NSError* error){
		if(error)
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Revert failed: %@", error.localizedDescription];
			NSAlert* errAlert = [NSAlert alertWithError:error];
			[errAlert beginSheetModalForWindow:parent completionHandler:nil];
		}
		else
		{
			BundleInstallHelper.sharedInstance.bundleInstallActivityText = [NSString stringWithFormat:@"Reverted “%@” @ %@", bundle.name, sha ? [sha substringToIndex:MIN(sha.length, 7u)] : @"(unknown)"];
		}
		[weakSelf pushState];
	}];
}
@end
