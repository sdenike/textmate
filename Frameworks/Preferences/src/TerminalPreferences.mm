#import "TerminalPreferences.h"
#import "Keys.h"
#import "Preferences-Swift.h"
#import "TerminalSupportBridge.h"
#import <OakAppKit/NSAlert Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <SoftwareUpdate/SoftwareUpdate.h> // OakCompareVersionStrings()
#import <io/path.h>
#import <io/exec.h>
#import <ns/ns.h>
#import <regexp/format_string.h>
#import <oak/compat.h>

static bool run_auth_command (AuthorizationRef& auth, std::string const cmd, ...)
{
	if(!auth && AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth) != errAuthorizationSuccess)
		return false;

	std::vector<char*> args;

	va_list ap;
	va_start(ap, cmd);
	char* arg = NULL;
	while((arg = va_arg(ap, char*)) && *arg)
		args.push_back(arg);
	va_end(ap);

	args.push_back(NULL);

	bool res = false;
	if(oak::execute_with_privileges(auth, cmd, kAuthorizationFlagDefaults, &args[0], NULL) == errAuthorizationSuccess)
	{
		int status;
		int pid = wait(&status);
		if(pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				res = true;
		else	errno = WEXITSTATUS(status);
	}
	else
	{
		errno = EPERM;
	}
	return res;
}

static bool mk_dir (std::string const& path, AuthorizationRef& auth)
{
	struct stat buf;
	if(stat(path.c_str(), &buf) == 0)
	{
		if(S_ISDIR(buf.st_mode))
			return true;
	}
	else if(path != "/" && mk_dir(path::parent(path), auth))
	{
		if(access(path::parent(path).c_str(), W_OK) == 0)
		{
			if(mkdir(path.c_str(), S_IRWXU|S_IRWXG|S_IRWXO) == 0)
				return true;
			perrorf("TerminalPreferences: mkdir(\"%s\")", path.c_str());
		}
		else
		{
			if(run_auth_command(auth, "/bin/mkdir", path.c_str(), NULL))
				return true;
			perrorf("TerminalPreferences: /bin/mkdir \"%s\"", path.c_str());
		}
	}
	return false;
}

static bool rm_path (std::string const& path, AuthorizationRef& auth)
{
	struct stat buf;
	if(lstat(path.c_str(), &buf) != 0)
		return true;

	if(access(path::parent(path).c_str(), W_OK) == 0)
	{
		if(unlink(path.c_str()) == 0)
			return true;
		perrorf("TerminalPreferences: unlink \"%s\"", path.c_str());
	}
	else
	{
		if(run_auth_command(auth, "/bin/rm", path.c_str(), NULL))
			return true;
		perrorf("TerminalPreferences: /bin/rm \"%s\"", path.c_str());
	}
	return false;
}

static bool cp_requires_admin (std::string const& dst)
{
	return access(dst.c_str(), W_OK) != 0 && (access(dst.c_str(), X_OK) == 0 || access(path::parent(dst).c_str(), W_OK) != 0);
}

static bool cp_path (std::string const& src, std::string const& dst, AuthorizationRef& auth)
{
	if(!cp_requires_admin(dst))
	{
		if(copyfile(src.c_str(), dst.c_str(), NULL, COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC) == 0)
			return true;
		perrorf("TerminalPreferences: copyfile(\"%s\", \"%s\", NULL, COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC)", src.c_str(), dst.c_str());
	}
	else
	{
		if(run_auth_command(auth, "/bin/cp", "-p", src.c_str(), dst.c_str(), NULL))
			return true;
		perrorf("TerminalPreferences: /bin/cp -p \"%s\" \"%s\"", src.c_str(), dst.c_str());
	}
	return false;
}

static bool install_mate (std::string const& src, std::string const& dst)
{
	AuthorizationRef auth = NULL;
	if(mk_dir(path::parent(dst), auth))
	{
		struct stat buf;
		if(lstat(dst.c_str(), &buf) == 0 && !S_ISREG(buf.st_mode) && !rm_path(dst, auth))
			return false;
		return cp_path(src, dst, auth);
	}
	return false;
}

static bool uninstall_mate (std::string const& path)
{
	AuthorizationRef auth = NULL;
	return access(path.c_str(), F_OK) != 0 || rm_path(path, auth);
}

// Read byte-for-byte out of TerminalPreferences.xib (git history) rather than
// retyped: statusTextFormat used to be the initial stringValue of a text field
// in that xib, and summaryTextFormat likewise. Both are still expanded through
// format_string::expand exactly as before -- only the copy's home changed, not
// its meaning. "installed" is only ever bound to the literal "installed" (its
// absence, not its emptiness, is what the ternary tests), and mate_path is
// deliberately either the real installed path or whatever the Location popup
// currently shows as a preview -- see -pushState.
//
// The summary format's "${mate_path/^~/\$HOME/}" is a LIVE format_string
// substitution, not inert text: it rewrites a leading ~ to the four literal
// characters $HOME (the backslash escapes the $ so format_string does not try
// to expand it as another variable), because the surrounding sentence is
// itself a line meant to be pasted into ~/.bashrc, where bash performs that
// expansion at shell-startup time, not here.
static std::string const kMateStatusTextFormat = "Shell support ${installed:?:not }installed";
static std::string const kMateSummaryTextFormat =
	"To use TextMate as editor for subversion, git, and similar you need to install the mate shell command and add a line like the following to ~/.bashrc:\n"
	"\n"
	"\texport EDITOR=\"${mate_path/^~/\\$HOME/} -w\"\n"
	"\n"
	"For more information use the help button down in the corner.";

@interface TerminalPreferences ()
{
	// The Location popup's current selection, independent of what is actually
	// installed: nil until the user picks something, an abbreviated (~-form)
	// path afterwards. Kept as an ivar because SwiftUI has no NSPopUpButton of
	// its own to ask -- TMTerminalInstallPathItems rebuilds the item list from
	// this on every -pushState, exactly as -updatePopUp: used to rebuild an
	// NSMenu from its `path` argument.
	NSString* _selectedPathTitle;
	SettingsPaneMateInstall* _installModel;
}
@end

@implementation TerminalPreferences
- (id)init
{
	NSImage* icon = [NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:@"Terminal"];
	return [super initWithNibName:nil label:@"Terminal" image:icon];
}

// Rebuilds every piece of pushed state from scratch and hands it to
// _installModel in one call. Called after every event that can change what
// the pane shows: load, picking a path (standard or via the Other… save
// panel), and install/uninstall -- exactly the set of places the AppKit pane
// called -updateUI:. Recomputing the item list on each call rather than
// caching it is deliberate: it is four objects, and the alternative is a
// second place the list and the selection can disagree.
- (void)pushState
{
	NSString* installedPath = self.mateInstallPath;
	BOOL isInstalled = installedPath != nil;

	NSArray<TMInstallPathItem*>* items = TMTerminalInstallPathItems(_selectedPathTitle);
	NSInteger selectedIndex = 0;
	if(_selectedPathTitle)
	{
		for(NSUInteger i = 0; i < items.count; ++i)
		{
			if(!items[i].isSeparator && !items[i].isOther && [items[i].title isEqualToString:_selectedPathTitle])
			{
				selectedIndex = i;
				break;
			}
		}
	}

	// Same fallback the AppKit popup gave you for free by simply never calling
	// -selectItemWithTitle: when path was nil, leaving its first item selected:
	// when installed, show the real path; otherwise preview whatever the
	// popup is currently sitting on.
	NSString* displayedPath = isInstalled ? [installedPath stringByAbbreviatingWithTildeInPath] : items[selectedIndex].title;

	std::map<std::string, std::string> variables;
	if(isInstalled)
		variables["installed"] = "installed";
	variables["mate_path"] = to_s(displayedPath);

	NSString* statusText  = [NSString stringWithCxxString:format_string::expand(kMateStatusTextFormat, variables)];
	NSString* summaryText = [NSString stringWithCxxString:format_string::expand(kMateSummaryTextFormat, variables)];
	NSImage*  statusImage = [NSImage imageNamed:(isInstalled ? NSImageNameStatusAvailable : NSImageNameStatusUnavailable)];

	[_installModel updateWithStatusText:statusText summaryText:summaryText isInstalled:isInstalled statusImage:statusImage pathItems:items selectedPathIndex:selectedIndex];
}

// The fallback used when nothing has been explicitly selected yet: the first
// entry TMTerminalInstallPathItems(nil) produces, i.e. "/usr/local/bin/mate" --
// the same default the xib's popup had pre-selected (state="on" on that menu
// item).
- (NSString*)selectedPathTitleOrDefault
{
	return _selectedPathTitle ?: TMTerminalInstallPathItems(nil).firstObject.title;
}

// The Other… row's save-panel flow. Cancelling resets the selection to
// whichever item is first in the CURRENT list rather than clearing it, which
// reproduces -updatePopUp:'s old cancel branch exactly: it called
// [installPathPopUp selectItemAtIndex:0] without rebuilding the menu, so a
// previously-picked custom path (still item 0) stayed selected, while a plain
// standard selection reverted to "/usr/local/bin/mate".
- (void)selectInstallPath:(id)sender
{
	NSSavePanel* savePanel = [NSSavePanel savePanel];
	[savePanel setNameFieldStringValue:@"mate"];
	[savePanel beginSheetModalForWindow:[self view].window completionHandler:^(NSModalResponse result) {
		if(result == NSModalResponseOK)
				self->_selectedPathTitle = [[[savePanel.URL filePathURL] path] stringByAbbreviatingWithTildeInPath];
		else	self->_selectedPathTitle = TMTerminalInstallPathItems(self->_selectedPathTitle).firstObject.title;
		[self pushState];
	}];
}

// The callback SettingsPaneFactory's Location Picker invokes with the chosen
// item's title -- empty exactly for the synthetic "Other…" row, the same
// convention ProjectsPreferences uses for its file browser location popup.
- (void)selectInstallPathTitle:(NSString*)title
{
	if(title.length == 0)
			[self selectInstallPath:self];
	else
	{
		_selectedPathTitle = title;
		[self pushState];
	}
}

- (void)loadView
{
	if(NSString* path = self.mateInstallPath)
	{
		if(access([path fileSystemRepresentation], F_OK) != 0)
		{
			[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsMateInstallPathKey];
			[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsMateInstallVersionKey];
		}
	}

	_installModel = [[SettingsPaneMateInstall alloc] init];
	[self pushState];

	// Built and fully wired here rather than in Swift: help: is inherited from
	// PreferencesPane and is not visible across the bridging header, and its
	// anchor comes from -alternateTitle (PreferencesPane.help: reads
	// [sender alternateTitle]), so the button has to be the real thing, not a
	// SwiftUI reimplementation. target:self sidesteps any question of whether
	// this view controller sits in the responder chain once its view is a
	// hosted SwiftUI tree.
	NSButton* helpButton = [NSButton buttonWithTitle:@"" target:self action:@selector(help:)];
	helpButton.bezelStyle     = NSBezelStyleHelpButton;
	helpButton.alternateTitle = @"terminal";

	__weak __typeof__(self) weakSelf = self;
	self.view = [SettingsPaneFactory terminalViewWithModel:_installModel helpButton:helpButton onSelectPath:^(NSString* title){
		[weakSelf selectInstallPathTitle:title];
	} onInstallOrUninstall:^{
		[weakSelf performInstallOrUninstall];
	}];

	LSSetDefaultHandlerForURLScheme(CFSTR("txmt"), CFBundleGetIdentifier(CFBundleGetMainBundle()));
}

- (NSString*)mateInstallPath
{
	NSString* path = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsMateInstallPathKey];
	return [path stringByExpandingTildeInPath];
}

- (void)setMateInstallPath:(NSString*)aPath
{
	if(aPath)
			[NSUserDefaults.standardUserDefaults setObject:aPath forKey:kUserDefaultsMateInstallPathKey];
	else	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsMateInstallPathKey];
}

- (void)installMateAs:(NSString*)dstPath
{
	if(NSString* srcPath = [NSBundle.mainBundle pathForAuxiliaryExecutable:@"mate"])
	{
		if(install_mate(to_s(srcPath), to_s(dstPath)))
		{
			[self setMateInstallPath:dstPath];
			std::string res = io::exec(to_s(srcPath), "--version", NULL);
			if(NSString* version = TMParseMateVersion([NSString stringWithCxxString:res]))
				[NSUserDefaults.standardUserDefaults setObject:version forKey:kUserDefaultsMateInstallVersionKey];
		}
	}
	else
	{
		NSAlert* alert        = [[NSAlert alloc] init];
		alert.messageText     = @"Unable to find ‘mate’";
		alert.informativeText = @"The ‘mate’ binary is missing from the application bundle. We recommend that you re-download the application.";
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
	[self pushState];
}

- (void)performInstallMate
{
	NSString* dstObjPath = [[self selectedPathTitleOrDefault] stringByExpandingTildeInPath];

	struct stat buf;
	std::string dstPath = to_s(dstObjPath);
	if(lstat(dstPath.c_str(), &buf) == 0)
	{
		char const* itemType = "An item";
		if(S_ISREG(buf.st_mode))
			itemType = "A file";
		else if(S_ISDIR(buf.st_mode))
			itemType = "A folder";
		else if(S_ISLNK(buf.st_mode))
			itemType = "A link";

		std::string summary = text::format("%s with the name “mate” already exists in the folder %s. Do you want to replace it?", itemType, path::with_tilde(path::parent(dstPath)).c_str());

		NSAlert* alert = [[NSAlert alloc] init];
		[alert setAlertStyle:NSAlertStyleWarning];
		[alert setMessageText:@"File Already Exists"];
		[alert setInformativeText:[NSString stringWithCxxString:summary]];
		[alert addButtons:@"Replace", @"Cancel", nil];
		[alert beginSheetModalForWindow:[self.view window] completionHandler:^(NSModalResponse returnCode){
			if(returnCode == NSAlertFirstButtonReturn)
				[self installMateAs:[[self selectedPathTitleOrDefault] stringByExpandingTildeInPath]];
		}];
	}
	else
	{
		[self installMateAs:dstObjPath];
	}
	[self pushState];
}

- (void)performUninstallMate
{
	if(uninstall_mate(to_s(self.mateInstallPath)))
		[self setMateInstallPath:nil];
	[self pushState];
}

// The Install/Uninstall button is a single control in the SwiftUI pane, its
// title and behaviour both following isInstalled -- the same state the AppKit
// button's -setAction:/-setState: pair used to switch on.
- (void)performInstallOrUninstall
{
	if(self.mateInstallPath)
			[self performUninstallMate];
	else	[self performInstallMate];
}

+ (void)updateMateIfRequired
{
	NSString* oldMate    = [[NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsMateInstallPathKey] stringByExpandingTildeInPath];
	NSString* oldVersion = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsMateInstallVersionKey];
	NSString* newMate    = [NSBundle.mainBundle pathForAuxiliaryExecutable:@"mate"];

	if(oldMate && newMate)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			std::string res = io::exec(to_s(newMate), "--version", NULL);
			if(NSString* newVersion = TMParseMateVersion([NSString stringWithCxxString:res]))
			{
				// oldVersion (the remembered default) can be stale, absent, or
				// describe a binary someone else replaced -- the installed
				// binary's own --version is authoritative. io::exec on a path
				// that no longer exists returns NULL_STR (spawn fails, process_t
				// stays default-constructed/falsy, vexec bails before waiting on
				// anything), which TMParseMateVersion then reports as nil, so
				// this only falls back to the stored default when the installed
				// binary genuinely can't be asked.
				std::string installedRes = io::exec(to_s(oldMate), "--version", NULL);
				NSString* installedVersion = TMParseMateVersion([NSString stringWithCxxString:installedRes]) ?: oldVersion;
				if(OakCompareVersionStrings(installedVersion, newVersion) == NSOrderedAscending)
				{
					if(cp_requires_admin(to_s(oldMate)))
					{
						dispatch_async(dispatch_get_main_queue(), ^{
							NSAlert* alert        = [[NSAlert alloc] init];
							alert.messageText     = @"Update Shell Support";
							alert.informativeText = [NSString stringWithFormat:@"Would you like to update the installed version of mate to version %@?", newVersion];
							[alert addButtons:@"Update", @"Cancel", nil];
							if([alert runModal] == NSAlertFirstButtonReturn) // "Update"
							{
								if(!install_mate(to_s(newMate), to_s(oldMate)))
									return;
							}

							// Avoid asking again by storing the new version number
							[NSUserDefaults.standardUserDefaults setObject:newVersion forKey:kUserDefaultsMateInstallVersionKey];
						});
					}
					else
					{
						if(install_mate(to_s(newMate), to_s(oldMate)))
							[NSUserDefaults.standardUserDefaults setObject:newVersion forKey:kUserDefaultsMateInstallVersionKey];
					}
				}
			}
		});
	}
}
@end
