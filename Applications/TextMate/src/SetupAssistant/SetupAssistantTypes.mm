#import "SetupAssistantTypes.h"

NSString* const TMThemeColorBackground = @"background";
NSString* const TMThemeColorForeground = @"foreground";
NSString* const TMThemeColorSelection  = @"selection";
NSString* const TMThemeColorCaret      = @"caret";
NSString* const TMThemeColorComment    = @"comment";
NSString* const TMThemeColorString     = @"string";
NSString* const TMThemeColorKeyword    = @"keyword";
NSString* const TMThemeColorNumber     = @"number";
NSString* const TMThemeColorFunction   = @"function";

@implementation TMThemeChoice
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier appearance:(NSString*)appearance colors:(NSDictionary<NSString*, NSColor*>*)colors
{
	TMThemeChoice* res = [self new];
	res->_name       = [name copy];
	res->_identifier = [identifier copy];
	res->_appearance = [appearance copy];
	res->_colors     = [colors copy];
	return res;
}
@end

@implementation TMBundleChoice
+ (instancetype)choiceWithName:(NSString*)name identifier:(NSString*)identifier category:(NSString*)category installed:(BOOL)installed recommended:(BOOL)recommended
{
	TMBundleChoice* res = [self new];
	res->_name        = [name copy];
	res->_identifier  = [identifier copy];
	res->_category    = [category copy];
	res->_installed   = installed;
	res->_recommended = recommended;
	return res;
}
@end

NSString* TMThemeAppearanceForSemanticClass (NSString* semanticClass)
{
	if([semanticClass containsString:@"theme.dark"])
		return @"dark";
	if([semanticClass containsString:@"theme.light"])
		return @"light";
	return @"unspecified";
}

NSArray<NSString*>* TMMergeNeverSuggestIdentifiers (NSArray<NSString*>* existing, NSArray<NSString*>* adding)
{
	NSMutableSet<NSString*>* set = [NSMutableSet setWithArray:existing ?: @[]];
	[set addObjectsFromArray:adding ?: @[]];
	return set.allObjects;
}
