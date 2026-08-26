#import "FilesPreferences.h"
#import "Preferences-Swift.h"
#import "SettingsFieldsBridge.h"
#import <OakAppKit/OakEncodingPopUpButton.h>
#import <OakFoundation/NSString Additions.h>
#import <bundles/bundles.h>
#import <ns/ns.h>

// The encoding shim declared in Preferences-Bridging-Header.h. extern "C" is
// load-bearing: this is Objective-C++, ClangImporter parses that header as
// Objective-C, and without it Swift looks up a symbol nobody defines.
extern "C" {

NSPopUpButton* TMCreateEncodingPopUpButton (void)
{
	return [[OakEncodingPopUpButton alloc] init];
}

NSString* TMEncodingPopUpButtonGetEncoding (NSPopUpButton* button)
{
	return ((OakEncodingPopUpButton*)button).encoding;
}

void TMEncodingPopUpButtonSetEncoding (NSPopUpButton* button, NSString* encoding)
{
	((OakEncodingPopUpButton*)button).encoding = encoding;
}

}

@implementation FilesPreferences
- (id)init
{
	NSImage* icon = [NSImage imageWithSystemSymbolName:@"doc.on.doc" accessibilityDescription:@"Files"];
	return [super initWithNibName:nil label:@"Files" image:icon];
}

// Everything SwiftUI cannot reach: bundles::query is C++, and a bridging
// header may contain none of it. The three rules that turn the query into a
// menu -- drop hidden grammars, drop scope-less ones, order by name -- live in
// TMFileTypeItemsSorted, where bin/gen_test can reach them.
- (void)loadView
{
	NSMutableArray<TMFileTypeItem*>* candidates = [NSMutableArray array];
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar))
	{
		[candidates addObject:[[TMFileTypeItem alloc] initWithName:[NSString stringWithCxxString:item->name()]
		                                                    scope:[NSString stringWithCxxString:item->value_for_field(bundles::kFieldGrammarScope)]
		                                                   hidden:item->hidden_from_user()]];
	}

	self.view = [SettingsPaneFactory filesViewWithFileTypes:TMFileTypeItemsSorted(candidates)];
}
@end
