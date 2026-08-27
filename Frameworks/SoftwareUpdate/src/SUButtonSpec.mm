#import "SUButtonSpec.h"

@implementation SUButtonSpec
+ (instancetype)specWithTitle:(NSString*)title enabled:(BOOL)enabled isDefault:(BOOL)isDefault isCancel:(BOOL)isCancel
{
	SUButtonSpec* spec = [self new];
	spec->_title     = title;
	spec->_enabled   = enabled;
	spec->_isDefault = isDefault;
	spec->_isCancel  = isCancel;
	return spec;
}
@end

NSArray<SUButtonSpec*>* SUButtonsForVersionCheck (NSComparisonResult ordering, BOOL backgroundCheck, BOOL allowRedownload, NSString* remoteVersion)
{
	if(ordering == NSOrderedAscending)
	{
		return @[
			[SUButtonSpec specWithTitle:@"Download" enabled:YES isDefault:YES isCancel:NO],
			[SUButtonSpec specWithTitle:(backgroundCheck ? @"Later" : @"Cancel") enabled:YES isDefault:NO isCancel:YES],
		];
	}
	else if(ordering == NSOrderedDescending)
	{
		return @[
			[SUButtonSpec specWithTitle:@"OK" enabled:YES isDefault:YES isCancel:NO],
			[SUButtonSpec specWithTitle:[NSString stringWithFormat:@"Downgrade to %@", remoteVersion] enabled:YES isDefault:NO isCancel:NO],
		];
	}

	NSMutableArray<SUButtonSpec*>* buttons = [NSMutableArray arrayWithObject:[SUButtonSpec specWithTitle:@"OK" enabled:YES isDefault:YES isCancel:NO]];
	if(allowRedownload)
		[buttons addObject:[SUButtonSpec specWithTitle:@"Redownload" enabled:YES isDefault:NO isCancel:NO]];
	return buttons;
}
