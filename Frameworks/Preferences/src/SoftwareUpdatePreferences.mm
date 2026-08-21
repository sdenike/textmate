#import "SoftwareUpdatePreferences.h"
#import "Keys.h"
#import "Preferences-Swift.h"
#import "SettingsSupportBridge.h"
#import <SoftwareUpdate/SoftwareUpdate.h>

@interface SoftwareUpdatePreferences ()
{
	id _relativeDateUserDefaultsObserver;
	NSTimer* _relativeDateUpdateTimer;
	SettingsPaneUpdateStatus* _updateStatus;
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
	[self addObserver:self forKeyPath:@"lastCheckDescription" options:NSKeyValueObservingOptionInitial context:NULL];
}

- (void)viewDidDisappear
{
	[_relativeDateUpdateTimer invalidate];
	[NSNotificationCenter.defaultCenter removeObserver:_relativeDateUserDefaultsObserver];
	[self removeObserver:self forKeyPath:@"lastCheckDescription"];
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if([keyPath isEqualToString:@"lastCheckDescription"])
			[self pushUpdateStatus];
	else	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)pushUpdateStatus
{
	[_updateStatus updateWithLastCheckDescription:self.lastCheckDescription isChecking:self.softwareUpdateController.isChecking];
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
