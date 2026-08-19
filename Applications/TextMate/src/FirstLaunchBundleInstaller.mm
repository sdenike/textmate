#import "FirstLaunchBundleInstaller.h"
#import <BundlesManager/BundlesManager.h>
#import <BundlesManager/BundleRegistry.h>
#import <BundlesManager/BundleSpec.h>

@implementation FirstLaunchBundleInstaller

+ (NSArray<BundleSpec*>*)allShippedSpecs
{
	NSMutableArray<BundleSpec*>* res = [NSMutableArray array];
	for(BundleSpec* spec in BundleRegistry.sharedInstance.allSpecs)
	{
		if(spec.origin == TMBundleOriginShipped)
			[res addObject:spec];
	}
	[res sortUsingComparator:^NSComparisonResult(BundleSpec* a, BundleSpec* b){
		NSComparisonResult c = [(a.category ?: @"Other") localizedCaseInsensitiveCompare:b.category ?: @"Other"];
		return c != NSOrderedSame ? c : [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	return res;
}

+ (NSArray<BundleSpec*>*)candidateSpecs
{
	NSArray* never = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsBundlesToNeverSuggestKey] ?: @[];
	NSMutableSet<NSString*>* skipUUIDs = [NSMutableSet setWithCapacity:never.count];
	for(NSString* s in never)
		[skipUUIDs addObject:s.uppercaseString];

	// A filter over allShippedSpecs, so the sort above is not duplicated here:
	// filtering a sorted array preserves order.
	NSMutableArray<BundleSpec*>* res = [NSMutableArray array];
	for(BundleSpec* spec in self.allShippedSpecs)
	{
		if(spec.installedSHA)
			continue;
		if([skipUUIDs containsObject:spec.uuid.UUIDString.uppercaseString])
			continue;
		[res addObject:spec];
	}
	return res;
}

@end
