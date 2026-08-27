// Frameworks/Preferences/src/TerminalSupportBridge.mm
#import "TerminalSupportBridge.h"

@implementation TMInstallPathItem
- (instancetype)initWithTitle:(NSString*)title isSeparator:(BOOL)isSeparator isOther:(BOOL)isOther
{
	if(self = [super init])
	{
		_title       = title;
		_isSeparator = isSeparator;
		_isOther     = isOther;
	}
	return self;
}
@end

NSArray<TMInstallPathItem*>* TMTerminalInstallPathItems (NSString* currentPath)
{
	NSMutableArray<TMInstallPathItem*>* items = [NSMutableArray array];
	if(currentPath && ![currentPath isEqualToString:@"~/bin/mate"] && ![currentPath isEqualToString:@"/usr/local/bin/mate"])
		[items addObject:[[TMInstallPathItem alloc] initWithTitle:currentPath isSeparator:NO isOther:NO]];
	[items addObject:[[TMInstallPathItem alloc] initWithTitle:@"/usr/local/bin/mate" isSeparator:NO isOther:NO]];
	[items addObject:[[TMInstallPathItem alloc] initWithTitle:@"~/bin/mate" isSeparator:NO isOther:NO]];
	[items addObject:[[TMInstallPathItem alloc] initWithTitle:@"" isSeparator:YES isOther:NO]];
	[items addObject:[[TMInstallPathItem alloc] initWithTitle:@"Other…" isSeparator:NO isOther:YES]];
	return items;
}
