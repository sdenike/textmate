#import "SoftwareUpdatePreferences.h"
#import "Keys.h"
#import "Preferences-Swift.h"
#import "SettingsSupportBridge.h"
#import <SoftwareUpdate/SoftwareUpdate.h>

@interface SoftwareUpdatePreferences ()
{
	id _relativeDateUserDefaultsObserver;
	NSTimer* _relativeDateUpdateTimer;
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
}

- (void)viewDidDisappear
{
	[_relativeDateUpdateTimer invalidate];
	[NSNotificationCenter.defaultCenter removeObserver:_relativeDateUserDefaultsObserver];
}

- (void)loadView
{
	SoftwareUpdate* controller = self.softwareUpdateController;
	self.view = [SettingsPaneFactory softwareUpdateViewWithCheckNow:^{
		[controller checkForUpdate:nil];
	}];
}
@end
