// Frameworks/Preferences/src/SettingsBundlesBridge.mm
#import "SettingsBundlesBridge.h"

NSString* const kUserDefaultsDisableBundleSuggestionsKey = @"disableBundleSuggestions";

@implementation TMBundleRow
- (instancetype)initWithIdentifier:(NSString*)identifier
                               name:(NSString*)name
                           category:(NSString*)category
                   webLinkURLString:(NSString*)webLinkURLString
                            updated:(NSDate*)updated
                        textSummary:(NSString*)textSummary
                       installState:(TMBundleInstallState)installState
             installedToggleEnabled:(BOOL)installedToggleEnabled
                        isMandatory:(BOOL)isMandatory
                        isInstalled:(BOOL)isInstalled
                  autoUpdateEnabled:(BOOL)autoUpdateEnabled
                                ref:(NSString*)ref
                  downloadURLString:(NSString*)downloadURLString
                               path:(NSString*)path
                    isEditedShipped:(BOOL)isEditedShipped
{
	if(self = [super init])
	{
		_identifier             = identifier;
		_name                   = name;
		_category               = category;
		_webLinkURLString       = webLinkURLString;
		_updated                = updated;
		_textSummary            = textSummary;
		_installState           = installState;
		_installedToggleEnabled = installedToggleEnabled;
		_isMandatory            = isMandatory;
		_isInstalled            = isInstalled;
		_autoUpdateEnabled      = autoUpdateEnabled;
		_ref                    = ref;
		_downloadURLString      = downloadURLString;
		_path                   = path;
		_isEditedShipped        = isEditedShipped;
	}
	return self;
}
@end

NSArray<TMBundleRow*>* TMBundlesFilterRows (NSArray<TMBundleRow*>* rows, NSString* searchText, NSString* category)
{
	NSMutableArray<TMBundleRow*>* res = [NSMutableArray array];
	for(TMBundleRow* row in rows)
	{
		if(searchText.length != 0)
		{
			NSRange range = [row.name rangeOfString:searchText options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
			if(range.location == NSNotFound)
				continue;
		}

		if(category && ![row.category isEqualToString:category])
			continue;

		[res addObject:row];
	}
	return res;
}

TMBundleMenuEnablement TMBundleMenuEnablementForRow (TMBundleRow* row)
{
	TMBundleMenuEnablement res;
	res.autoUpdateEnabled = !row.isMandatory;
	res.changeRefEnabled  = !row.isMandatory;
	res.editEnabled       = !row.isMandatory;
	res.uninstallEnabled  = !row.isMandatory && row.isInstalled;
	res.removeEnabled     = !row.isMandatory;
	res.revertEnabled     = row.isEditedShipped;
	res.copyURLEnabled    = row.downloadURLString != nil;
	res.revealEnabled     = row.path != nil;
	return res;
}
