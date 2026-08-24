#import "VariablesPreferences.h"
#import "Preferences-Swift.h"

@interface VariablesPreferences ()
{
	SettingsPaneVariables* _variables;
}
@end

@implementation VariablesPreferences
- (id)init
{
	NSImage* icon = [NSImage imageWithSystemSymbolName:@"dollarsign.circle" accessibilityDescription:@"Variables"];
	return [super initWithNibName:nil label:@"Variables" image:icon];
}

- (void)loadView
{
	// Seeded before the factory runs: SettingsPaneFactory measures fittingSize
	// off the view it builds, and an empty table would size the pane for no
	// rows.
	_variables = [[SettingsPaneVariables alloc] init];
	self.view = [SettingsPaneFactory variablesViewWithVariables:_variables];
}

// Load-bearing, and the only commit trigger that runs BEFORE the pane switch is
// allowed to proceed: Preferences.mm:35 refuses to switch panes when this
// returns NO, and swaps our view out at :48. The AppKit table handed first
// responder back from the field editor here; the SwiftUI table has no field
// editor to hand back, so this flushes the edited row to NSUserDefaults instead.
// -commit skips the write when nothing changed, so the overlap with the view's
// own .onDisappear costs a read.
- (BOOL)commitEditing
{
	[_variables commit];
	return YES;
}
@end
