#import "ProjectsPreferences.h"
#import "Preferences-Swift.h"
#import "Keys.h"

@interface ProjectsPreferences ()
{
	SettingsPaneFileBrowserLocation* _fileBrowserLocation;
}
@end

@implementation ProjectsPreferences
- (id)init
{
	NSImage* icon = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:@"Projects"];
	return [super initWithNibName:nil label:@"Projects" image:icon];
}

- (SettingsFileBrowserLocationItem*)itemForURL:(NSURL*)aURL
{
	NSImage* image;
	NSError* error;
	if([aURL getResourceValue:&image forKey:NSURLEffectiveIconKey error:&error])
	{
		image = [image copy];
		image.size = NSMakeSize(16, 16);
	}
	else
	{
		os_log_error(OS_LOG_DEFAULT, "No NSURLEffectiveIconKey for %{public}@: %{public}@", aURL, error);
		image = nil;
	}

	NSString* title = [NSFileManager.defaultManager displayNameAtPath:aURL.path];
	return [[SettingsFileBrowserLocationItem alloc] initWithTitle:title icon:image url:aURL.absoluteString isSeparator:NO isOther:NO];
}

// Reproduces the old -updatePathPopUp exactly (same standing entries, same
// "custom URL first plus a separator" rule, same trailing "Other…"), just
// building plain items for Swift instead of NSMenuItems for an NSPopUpButton.
- (void)updateFileBrowserLocations
{
	NSArray<NSURL*>* const defaultURLs = @[
		[NSFileManager.defaultManager URLForDirectory:NSDesktopDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil],
		NSFileManager.defaultManager.homeDirectoryForCurrentUser,
		[NSURL fileURLWithPath:@"/" isDirectory:YES],
	];

	NSURL* url = defaultURLs[1];
	if(NSString* urlString = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsInitialFileBrowserURLKey])
		url = [NSURL URLWithString:urlString];

	NSMutableArray<SettingsFileBrowserLocationItem*>* items = [NSMutableArray array];
	NSInteger selectedIndex = 0;

	if(![defaultURLs containsObject:url])
	{
		[items addObject:[self itemForURL:url]];
		[items addObject:[[SettingsFileBrowserLocationItem alloc] initWithTitle:@"" icon:nil url:@"" isSeparator:YES isOther:NO]];
	}

	for(NSURL* defaultURL in defaultURLs)
	{
		if([defaultURL isEqual:url])
			selectedIndex = items.count;
		[items addObject:[self itemForURL:defaultURL]];
	}

	[items addObject:[[SettingsFileBrowserLocationItem alloc] initWithTitle:@"" icon:nil url:@"" isSeparator:YES isOther:NO]];
	[items addObject:[[SettingsFileBrowserLocationItem alloc] initWithTitle:@"Other…" icon:nil url:@"" isSeparator:NO isOther:YES]];

	[_fileBrowserLocation updateWithItems:items selectedIndex:selectedIndex];
}

// The callback SettingsPaneFactory's Picker invokes with the chosen item's
// url -- empty exactly for the synthetic "Other…" row, since a real
// location's absoluteString is never empty.
- (void)selectFileBrowserLocationURLString:(NSString*)urlString
{
	if(urlString.length == 0)
	{
		NSOpenPanel* openPanel = [NSOpenPanel openPanel];
		openPanel.canChooseFiles       = NO;
		openPanel.canChooseDirectories = YES;
		__weak __typeof__(self) weakSelf = self;
		[openPanel beginSheetModalForWindow:[self view].window completionHandler:^(NSModalResponse result) {
			if(result == NSModalResponseOK)
				[NSUserDefaults.standardUserDefaults setObject:[[openPanel URL] absoluteString] forKey:kUserDefaultsInitialFileBrowserURLKey];
			[weakSelf updateFileBrowserLocations];
		}];
	}
	else
	{
		[NSUserDefaults.standardUserDefaults setObject:urlString forKey:kUserDefaultsInitialFileBrowserURLKey];
		[self updateFileBrowserLocations];
	}
}

- (void)loadView
{
	// Seeded before the factory runs, not after: SettingsPaneFactory measures
	// fittingSize off the view it builds, and an empty location list would
	// size that row for no content instead of the real first item.
	_fileBrowserLocation = [[SettingsPaneFileBrowserLocation alloc] init];
	[self updateFileBrowserLocations];

	__weak __typeof__(self) weakSelf = self;
	self.view = [SettingsPaneFactory projectsViewWithFileBrowserLocation:_fileBrowserLocation onSelectLocation:^(NSString* urlString){
		[weakSelf selectFileBrowserLocationURLString:urlString];
	}];
}
@end
