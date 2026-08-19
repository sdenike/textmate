#import "FirstLaunchBundleInstaller.h"
#import <BundlesManager/BundlesManager.h>
#import <BundlesManager/BundleRegistry.h>
#import <BundlesManager/BundleSpec.h>

@implementation FirstLaunchBundleInstaller

+ (NSArray<BundleSpec*>*)candidateSpecs
{
	NSArray* never = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey] ?: @[];
	NSMutableSet<NSString*>* skipUUIDs = [NSMutableSet setWithCapacity:never.count];
	for(NSString* s in never)
		[skipUUIDs addObject:s.uppercaseString];

	NSMutableArray<BundleSpec*>* res = [NSMutableArray array];
	for(BundleSpec* spec in BundleRegistry.sharedInstance.allSpecs)
	{
		if(spec.origin != TMBundleOriginShipped)
			continue;
		if(spec.installedSHA)
			continue;
		if([skipUUIDs containsObject:spec.uuid.UUIDString.uppercaseString])
			continue;
		[res addObject:spec];
	}
	[res sortUsingComparator:^NSComparisonResult(BundleSpec* a, BundleSpec* b){
		NSComparisonResult c = [(a.category ?: @"Other") localizedCaseInsensitiveCompare:b.category ?: @"Other"];
		return c != NSOrderedSame ? c : [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return res;
}

@end
