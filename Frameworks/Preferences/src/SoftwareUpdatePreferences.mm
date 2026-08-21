#import "SoftwareUpdatePreferences.h"
#import "Preferences-Swift.h"
#import "SettingsSupportBridge.h"
#import <SoftwareUpdate/SoftwareUpdate.h>

@interface SoftwareUpdatePreferences ()
{
	id _relativeDateUserDefaultsObserver;
	NSTimer* _relativeDateUpdateTimer;
	SettingsPaneUpdateStatus* _updateStatus;
	BOOL _observingLastCheckDescription;
}
@property (nonatomic) NSString* relativeStringForLastCheck;
@end

@implementation SoftwareUpdatePreferences
+ (NSSet*)keyPathsForValuesAffectingLastCheckDescription { return [NSSet setWithObjects:@"softwareUpdateController.checking", @"softwareUpdateController.errorString", @"relativeStringForLastCheck", nil]; }

- (id)init
{
	NSImage* icon = [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath" accessibilityDescription:@"Software Update"];
	return [super initWithNibName:nil label:@"Software Update" image:icon];
}

- (SoftwareUpdate*)softwareUpdateController
{
	return SoftwareUpdate.sharedInstance;
}

- (NSString*)lastCheckDescription
{
	return TMSettingsLastCheckDescription(self.softwareUpdateController.isChecking, self.softwareUpdateController.errorString, _relativeStringForLastCheck);
}

- (NSString*)relativeStringForDate:(NSDate*)date
{
	if(!date)
		return nil;
	return -[date timeIntervalSinceNow] < 5 ? @"Just now" : [[[NSRelativeDateTimeFormatter alloc] init] localizedStringForDate:date relativeToDate:NSDate.now];
}

- (void)viewWillAppear
{
	_relativeDateUserDefaultsObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* notification){
		self.relativeStringForLastCheck = [self relativeStringForDate:[NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsLastSoftwareUpdateCheckKey]];
	}];

	_relativeDateUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer* timer){
		self.relativeStringForLastCheck = [self relativeStringForDate:[NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsLastSoftwareUpdateCheckKey]];
	}];

	self.relativeStringForLastCheck = [self relativeStringForDate:[NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsLastSoftwareUpdateCheckKey]];

	// lastCheckDescription's own dependent keys (declared above) already cover
	// softwareUpdateController.checking/.errorString and relativeStringForLastCheck,
	// so observing that one derived property is enough to catch all three without
	// three separate observers. Initial fires this immediately on registration,
	// which is what re-syncs the SwiftUI status after a pane was hidden (and thus
	// unobserved) while a check ran or completed.
	//
	// Flag-guarded on both sides: -removeObserver:forKeyPath: throws when it is
	// unbalanced, unlike the -removeObserver: sitting beside it below. Today the
	// pair is balanced only because OakTransitionViewController removes the old
	// subview on animation completion, which is not this file's invariant to
	// rely on.
	if(!_observingLastCheckDescription)
	{
		[self addObserver:self forKeyPath:@"lastCheckDescription" options:NSKeyValueObservingOptionInitial context:NULL];
		_observingLastCheckDescription = YES;
	}
}

- (void)viewDidDisappear
{
	[_relativeDateUpdateTimer invalidate];
	[NSNotificationCenter.defaultCenter removeObserver:_relativeDateUserDefaultsObserver];
	if(_observingLastCheckDescription)
	{
		[self removeObserver:self forKeyPath:@"lastCheckDescription"];
		_observingLastCheckDescription = NO;
	}
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if([keyPath isEqualToString:@"lastCheckDescription"])
			[self pushUpdateStatus];
	else	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)pushUpdateStatus
{
	// -updateWithLastCheckDescription:isChecking: is @MainActor, and the @objc
	// thunk of a @MainActor method SIGTRAPs (exit 133) *before its body runs*
	// when invoked off-main under -swift-version 6. This is reachable off-main:
	// SoftwareUpdate.mm's NSBackgroundActivityScheduler block runs on an XPC
	// activity queue and gets here synchronously via checkForTestBuild:'s
	// `self.checking = YES` -> KVO -> observeValueForKeyPath:. So an automatic
	// hourly check with the pane open would kill the app. (The AppKit pane this
	// replaced fed the same off-main KVO into a Cocoa binding, which misbehaved
	// quietly instead of trapping -- the threading defect predates the port.)
	//
	// Conditional rather than an unconditional dispatch_async: -loadView seeds
	// the status synchronously and SettingsPaneFactory measures fittingSize off
	// the view it then builds, so deferring the on-main case by a runloop turn
	// would size the "Last check" row for empty text -- exactly what seeding
	// before the factory runs exists to prevent.
	NSString* description = self.lastCheckDescription;
	BOOL isChecking       = self.softwareUpdateController.isChecking;
	if(NSThread.isMainThread)
	{
		[_updateStatus updateWithLastCheckDescription:description isChecking:isChecking];
	}
	else
	{
		SettingsPaneUpdateStatus* status = _updateStatus;
		dispatch_async(dispatch_get_main_queue(), ^{
			[status updateWithLastCheckDescription:description isChecking:isChecking];
		});
	}
}

- (void)loadView
{
	// Seeded before the factory runs, not after: SettingsPaneFactory measures
	// fittingSize off the view it builds, and status starting at "" would size
	// the "Last check" row for empty text instead of the real string.
	_updateStatus = [[SettingsPaneUpdateStatus alloc] init];
	[self pushUpdateStatus];

	SoftwareUpdate* controller = self.softwareUpdateController;
	self.view = [SettingsPaneFactory softwareUpdateViewWithCheckNow:^{
		[controller checkForUpdate:nil];
	} status:_updateStatus];
}
@end
