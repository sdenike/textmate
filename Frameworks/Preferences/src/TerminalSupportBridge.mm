// Frameworks/Preferences/src/TerminalSupportBridge.mm
#import "TerminalSupportBridge.h"
#import <regexp/regexp.h>
#import <ns/ns.h>
#import <OakFoundation/NSString Additions.h>

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

NSString* TMParseMateVersion (NSString* output)
{
	// str must be a named local, not an inline to_s(output) temporary:
	// regexp::search(pattern_t const&, std::string const&) hands back a
	// match_t whose buf points straight into that string's own buffer
	// (regexp.cc), and binding the match to `m` only lifetime-extends the
	// match_t itself, not an argument temporary it was built from -- an
	// inline temporary is destroyed before m[1] below ever reads through it.
	std::string const str = to_s(output);
	if(regexp::match_t const& m = regexp::search("\\Amate (\\S+)", str))
		return [NSString stringWithCxxString:m[1]];
	return nil;
}
