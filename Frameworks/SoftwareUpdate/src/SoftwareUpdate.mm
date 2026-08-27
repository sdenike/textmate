#import "SoftwareUpdate.h"
#import "OakDownloadManager.h"
#import "SUButtonSpec.h"
#import "SoftwareUpdate-Swift.h"
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakSound.h>
#import <Security/Security.h>

NSString* const kUserDefaultsLastSoftwareUpdateCheckKey                        = @"SoftwareUpdateLastPoll";
NSString* const kUserDefaultsSoftwareUpdateSuspendUntilKey                     = @"SoftwareUpdateSuspendUntil";
NSString* const kUserDefaultsDisableSoftwareUpdateKey                          = @"SoftwareUpdateDisablePolling";
NSString* const kUserDefaultsAskBeforeUpdatingKey                              = @"SoftwareUpdateAskBeforeUpdating";
NSString* const kUserDefaultsSoftwareUpdateChannelKey                          = @"SoftwareUpdateChannel";
NSString* const kUserDefaultsSoftwareUpdateDisableReadOnlyFileSystemWarningKey = @"SoftwareUpdateDisableReadOnlyFileSystemWarningKey";

NSString* const kSoftwareUpdateChannelRelease                                  = @"release";
NSString* const kSoftwareUpdateChannelPrerelease                               = @"beta";
NSString* const kSoftwareUpdateChannelCanary                                   = @"nightly";

static BOOL is_hex (char ch)
{
	return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F');
}

// Parses a git-upload-pack ref advertisement into a refname → SHA map.
// Returns nil when the data is not valid pkt-line format.
static NSDictionary<NSString*, NSString*>* OakRefsInUploadPackAdvertisement (NSData* data)
{
	if(!data.length)
		return nil;

	NSMutableDictionary<NSString*, NSString*>* shaForName = [NSMutableDictionary dictionary];

	char const* bytes = (char const*)data.bytes;
	NSUInteger size = data.length;
	for(NSUInteger offset = 0; offset + 4 <= size; )
	{
		NSUInteger pktLength = 0;
		for(NSUInteger i = 0; i < 4; ++i)
		{
			char ch = bytes[offset + i];
			if(!is_hex(ch))
				return nil;
			pktLength = (pktLength << 4) | (NSUInteger)(ch <= '9' ? ch - '0' : (ch | 0x20) - 'a' + 10);
		}

		if(pktLength == 0) // flush packet
		{
			offset += 4;
			continue;
		}

		if(pktLength < 4 || offset + pktLength > size)
			return nil;

		// Payload is “<40-hex-sha> <refname>[\0capabilities]\n”; the leading
		// “# service=…” pkt and anything else non-conforming is skipped.
		char const* payload = bytes + offset + 4;
		NSUInteger payloadLength = pktLength - 4;
		offset += pktLength;

		if(payloadLength < 42 || payload[40] != ' ')
			continue;

		BOOL shaValid = YES;
		for(NSUInteger i = 0; i < 40 && shaValid; ++i)
			shaValid = is_hex(payload[i]);
		if(!shaValid)
			continue;

		NSUInteger nameEnd = 41;
		while(nameEnd < payloadLength && payload[nameEnd] != '\0' && payload[nameEnd] != '\n')
			++nameEnd;
		if(nameEnd == 41)
			continue;

		NSString* sha  = [[NSString alloc] initWithBytes:payload length:40 encoding:NSASCIIStringEncoding];
		NSString* name = [[NSString alloc] initWithBytes:payload + 41 length:nameEnd - 41 encoding:NSUTF8StringEncoding];
		if(name)
			shaForName[name] = sha;
	}

	return shaForName;
}

NSString* OakSHAForRefInUploadPackAdvertisement (NSData* data, NSString* ref)
{
	if(!ref.length)
		return nil;

	NSDictionary<NSString*, NSString*>* shaForName = OakRefsInUploadPackAdvertisement(data);

	NSArray<NSString*>* candidates;
	if([ref isEqualToString:@"HEAD"])
		candidates = @[ @"HEAD" ];
	else if([ref hasPrefix:@"refs/"])
		candidates = @[ [ref stringByAppendingString:@"^{}"], ref ];
	else
		candidates = @[ [@"refs/heads/" stringByAppendingString:ref], [NSString stringWithFormat:@"refs/tags/%@^{}", ref], [@"refs/tags/" stringByAppendingString:ref] ];

	for(NSString* candidate in candidates)
	{
		if(NSString* sha = shaForName[candidate])
			return sha;
	}
	return nil;
}

NSString* OakLatestVersionInUploadPackAdvertisement (NSData* data, BOOL includePrereleases)
{
	NSString* best = nil;
	for(NSString* name in OakRefsInUploadPackAdvertisement(data))
	{
		if(![name hasPrefix:@"refs/tags/v"])
			continue;

		NSString* tag = [name substringFromIndex:[@"refs/tags/v" length]];
		if([tag hasSuffix:@"^{}"]) // peeled duplicate of an annotated tag
			tag = [tag substringToIndex:tag.length - 3];

		if(!tag.length || !isdigit([tag characterAtIndex:0])) // v2.1.0 yes, vendor-drop no
			continue;
		if(!includePrereleases && [tag containsString:@"-beta"]) // release.yml’s prerelease marker
			continue;

		if(!best || OakCompareVersionStrings(best, tag) == NSOrderedAscending)
			best = tag;
	}
	return best;
}

NSURL* OakUpdateAssetURLForVersion (NSString* version, NSURL* advertisementURL)
{
	if(!version.length)
		return nil;

	// Expect /{owner}/{repo}.git/info/refs
	NSArray<NSString*>* parts = advertisementURL.path.pathComponents;
	if(parts.count != 5 || ![parts[1] length] || ![parts[2] hasSuffix:@".git"] || [parts[2] length] < 5 || ![parts[3] isEqualToString:@"info"] || ![parts[4] isEqualToString:@"refs"])
		return nil;

	NSString* repo = [parts[2] substringToIndex:[parts[2] length] - 4];
	return [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/%@/%@/releases/download/v%@/TextMate-%@.tbz", advertisementURL.host, parts[1], repo, version, version]];
}

// Case-insensitive header lookup (HTTP/2 lowercases header names; the
// 10.15-only -valueForHTTPHeaderField: is below this framework's floor).
static NSString* OakHTTPHeaderValue (NSHTTPURLResponse* response, NSString* field)
{
	for(NSString* key in response.allHeaderFields)
	{
		if([key caseInsensitiveCompare:field] == NSOrderedSame)
		{
			NSString* value = response.allHeaderFields[key];
			return [value isKindOfClass:NSString.class] ? value : nil;
		}
	}
	return nil;
}

NSError* OakGitHubResponseError (NSURLResponse* response, id body)
{
	if(![response isKindOfClass:NSHTTPURLResponse.class])
		return nil;

	NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
	if(http.statusCode / 100 == 2)
		return nil;

	NSString* message;
	if([OakHTTPHeaderValue(http, @"x-ratelimit-remaining") isEqualToString:@"0"])
	{
		// The unauthenticated api.github.com quota (60 requests/hour per IP,
		// shared with everything else on the network) is exhausted — the
		// common cause of failed checks (issue #26). GitHub's own body
		// message is poor dialog copy, so say what happened and when the
		// quota resets.
		message = @"GitHub API rate limit reached for this network.";
		if(NSTimeInterval reset = OakHTTPHeaderValue(http, @"x-ratelimit-reset").doubleValue)
		{
			NSDateFormatter* formatter = [NSDateFormatter new];
			formatter.dateStyle = NSDateFormatterNoStyle;
			formatter.timeStyle = NSDateFormatterShortStyle;
			message = [message stringByAppendingFormat:@" Try again after %@.", [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:reset]]];
		}
	}
	else if([body isKindOfClass:NSDictionary.class] && [body[@"message"] isKindOfClass:NSString.class] && [body[@"message"] length])
	{
		message = body[@"message"]; // GitHub error bodies carry a human-readable “message”
	}
	else
	{
		message = [NSString stringWithFormat:@"HTTP %ld from update server.", (long)http.statusCode];
	}

	return [NSError errorWithDomain:@"SoftwareUpdate" code:http.statusCode userInfo:@{ NSLocalizedDescriptionKey: message }];
}

// Team Identifier of the currently running application, or nil if unsigned /
// ad-hoc signed (e.g. a local development build).
static NSString* OakRunningApplicationTeamIdentifier ()
{
	SecCodeRef selfCode = NULL;
	if(SecCodeCopySelf(kSecCSDefaultFlags, &selfCode) != errSecSuccess)
		return nil;

	NSString* teamID = nil;
	CFDictionaryRef info = NULL;
	if(SecCodeCopySigningInformation((SecStaticCodeRef)selfCode, kSecCSSigningInformation, &info) == errSecSuccess && info)
		teamID = [(__bridge NSString*)CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) copy];

	if(info)     CFRelease(info);
	if(selfCode) CFRelease(selfCode);
	return teamID;
}

// YES iff the bundle at appURL carries a valid Developer ID Application
// signature whose Team Identifier equals expectedTeamID. Fails closed when
// expectedTeamID is empty. Requirement string + flags validated by the
// 2026-05-26 Option B spike (see PLAN-eliminate-api-textmate-org.md).
static BOOL OakBundleIsSignedByTeam (NSURL* appURL, NSString* expectedTeamID)
{
	if(!expectedTeamID.length)
		return NO;

	SecStaticCodeRef code = NULL;
	if(SecStaticCodeCreateWithPath((__bridge CFURLRef)appURL, kSecCSDefaultFlags, &code) != errSecSuccess)
		return NO;

	NSString* requirement = [NSString stringWithFormat:
		@"anchor apple generic and "
		 "certificate 1[field.1.2.840.113635.100.6.2.6] exists and "      // Developer ID intermediate
		 "certificate leaf[field.1.2.840.113635.100.6.1.13] exists and "  // Developer ID Application leaf
		 "certificate leaf[subject.OU] = \"%@\"", expectedTeamID];

	SecRequirementRef req = NULL;
	OSStatus status = SecRequirementCreateWithString((__bridge CFStringRef)requirement, kSecCSDefaultFlags, &req);
	if(status == errSecSuccess)
		status = SecStaticCodeCheckValidityWithErrors(code, kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate, req, NULL);

	if(req)  CFRelease(req);
	if(code) CFRelease(code);
	return status == errSecSuccess;
}

// ============================
// = SUDownloadViewController =
// ============================

@interface SUDownloadViewController : NSViewController
- (instancetype)initWithCompletionHandler:(void(^)())completionHandler;
- (void)presentUIForBackgroundCheck:(BOOL)backgroundCheck remoteURL:(NSURL*)remoteURL remoteVersion:(NSString*)remoteVersion redownloadEnabled:(BOOL)allowRedownload;
@end

// ==================
// = SoftwareUpdate =
// ==================

@interface SoftwareUpdate ()
{
	NSBackgroundActivityScheduler* _updateCheckScheduler;
	NSTimeInterval                 _updateCheckInterval;
}
@property (nonatomic, readwrite, getter = isChecking) BOOL checking;
@property (nonatomic, readwrite) NSString* errorString;
@property (nonatomic) BOOL automaticUpdateCheckEnabled;
@end

@implementation SoftwareUpdate
+ (instancetype)sharedInstance
{
	static SoftwareUpdate* sharedInstance = [self new];
	return sharedInstance;
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		kUserDefaultsSoftwareUpdateChannelKey: kSoftwareUpdateChannelRelease
	}];
}

- (instancetype)init
{
	if(self = [super init])
	{
		_updateCheckInterval = 60*60;

		[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults queue:nil usingBlock:^(NSNotification* notification){
			dispatch_async(dispatch_get_main_queue(), ^{
				self.automaticUpdateCheckEnabled = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSoftwareUpdateKey];
			});
		}];
		self.automaticUpdateCheckEnabled = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSoftwareUpdateKey];
	}
	return self;
}

- (void)setAutomaticUpdateCheckEnabled:(BOOL)flag
{
	if(_automaticUpdateCheckEnabled == flag)
		return;

	[_updateCheckScheduler invalidate];
	_updateCheckScheduler = nil;

	if(_automaticUpdateCheckEnabled = flag)
	{
		_updateCheckScheduler = [[NSBackgroundActivityScheduler alloc] initWithIdentifier:[NSString stringWithFormat:@"%@.%@", NSBundle.mainBundle.bundleIdentifier, @"SoftwareUpdate"]];
		_updateCheckScheduler.interval = _updateCheckInterval;
		_updateCheckScheduler.repeats  = YES;
		[_updateCheckScheduler scheduleWithBlock:^(NSBackgroundActivityCompletionHandler completionHandler){
			if(NSDate* suspendUntil = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsSoftwareUpdateSuspendUntilKey])
			{
				if([suspendUntil timeIntervalSinceNow] > 0)
				{
					os_log(OS_LOG_DEFAULT, "Skip version check: Suspended until %{public}@", suspendUntil);
					completionHandler(NSBackgroundActivityResultFinished);
					return;
				}
				[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsSoftwareUpdateSuspendUntilKey];
			}

			[self checkForTestBuild:NO completionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSError* error){
				self.errorString = error ? [NSString stringWithFormat:@"Error: %@", error.localizedDescription] : nil;
				if(error)
				{
					os_log(OS_LOG_DEFAULT, "Failed to check for update: %{public}@", error.localizedDescription);
					completionHandler(NSBackgroundActivityResultFinished);
				}
				else
				{
					SUDownloadViewController* alertViewController = [[SUDownloadViewController alloc] initWithCompletionHandler:^{
						completionHandler(NSBackgroundActivityResultFinished);
					}];
					[alertViewController presentUIForBackgroundCheck:YES remoteURL:remoteURL remoteVersion:remoteVersion redownloadEnabled:NO];
				}
			}];
		}];
	}
}

- (void)checkForUpdate:(id)sender
{
	BOOL isOptionDown = OakIsAlternateKeyOrMouseEvent(NSEventModifierFlagOption);
	BOOL isShiftDown  = OakIsAlternateKeyOrMouseEvent(NSEventModifierFlagShift);

	[self checkForTestBuild:isOptionDown completionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSError* error){
		SUDownloadViewController* alertViewController = [[SUDownloadViewController alloc] init];
		if(error)
				[alertViewController presentError:error];
		else	[alertViewController presentUIForBackgroundCheck:NO remoteURL:remoteURL remoteVersion:remoteVersion redownloadEnabled:isShiftDown];
	}];
}

- (void)checkForTestBuild:(BOOL)testBuild completionHandler:(void(^)(NSURL* remoteURL, NSString* remoteVersion, NSError* error))completionHandler
{
	NSString* updateChannel = testBuild ? kSoftwareUpdateChannelCanary : [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsSoftwareUpdateChannelKey];
	if(!updateChannel)
		return completionHandler(nil, nil, [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"No channel configured." }]);

	NSURL* url = _channels[updateChannel];
	if(!url)
		return completionHandler(nil, nil, [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No channel named ‘%@’.", updateChannel] }]);

	os_activity_initiate("Software update check", OS_ACTIVITY_FLAG_DEFAULT, ^{
		self.checking = YES;

		NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60];
		[request setValue:OakDownloadManager.sharedInstance.userAgentString forHTTPHeaderField:@"User-Agent"];

		NSURLSessionDataTask* dataTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error){
			NSURL* remoteURL;
			NSString* remoteVersion;

			if(!error)
			{
				NSString* contentType = ((NSHTTPURLResponse*)response).allHeaderFields[@"Content-Type"];

				// Error bodies (e.g. from a proxy or a metered endpoint) are
				// JSON; the feed itself is a ref advertisement.
				id body = nil;
				if([contentType hasPrefix:@"application/json"])
					body = [NSJSONSerialization JSONObjectWithData:data options:0 error:nullptr];

				if(NSError* httpError = OakGitHubResponseError(response, body))
				{
					error = httpError;
				}
				else if([contentType hasPrefix:@"application/x-git-upload-pack-advertisement"])
				{
					// Anything other than the stable channel opts into prerelease tags. Nightly is
					// offered in Settings, and without this it would deliver exactly what release
					// does -- a control labelled "Nightly builds" that silently means "Normal
					// releases". The feed is git tags with two tiers, so nightly and prerelease
					// deliver the same updates until a nightly tag stream exists.
					BOOL includePrereleases = ![updateChannel isEqualToString:kSoftwareUpdateChannelRelease];
					remoteVersion = OakLatestVersionInUploadPackAdvertisement(data, includePrereleases);
					remoteURL     = OakUpdateAssetURLForVersion(remoteVersion, url);
					if(!remoteURL || !remoteVersion)
						error = [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"No release tags in server response." }];
				}
				else
				{
					// 200 with the wrong content type — e.g. a captive portal’s
					// HTML — names itself instead of “Incomplete server response.”
					// (Message built outside the dictionary literal: a comma there
					// breaks the enclosing os_activity_initiate macro expansion.)
					NSString* message = [@"Unexpected response type from update server: " stringByAppendingString:contentType ?: @"none"];
					error = [NSError errorWithDomain:@"SoftwareUpdate" code:0 userInfo:@{ NSLocalizedDescriptionKey: message }];
				}
			}

			dispatch_async(dispatch_get_main_queue(), ^{
				[NSUserDefaults.standardUserDefaults setObject:[NSDate date] forKey:kUserDefaultsLastSoftwareUpdateCheckKey];
				self.checking = NO;
				completionHandler(remoteURL, remoteVersion, error);
			});
		}];
		[dataTask resume];
	});
}
@end

// ============================
// = SUDownloadViewController =
// ============================

@interface SUDownloadViewController ()
{
	SUDownloadViewController* _retainedSelf;

	void(^_completionHandler)();
	BOOL(^_runModalCompletionHandler)(NSModalResponse);

	NSURL* _downloadedArchiveURL;
	NSURL* _remoteURL;

	// Folded in from the old SUProgressViewController, which owned an
	// identical timer driving its own text fields/NSProgressIndicator. Both
	// call sites that touch these are already main-thread -- see -setDownloadProgress:
	// and -progressTimerDidFire: below -- so no dispatch_async is needed here.
	NSProgress* _progress;
	NSTimer*    _progressTimer;

	// self.model.buttons is @Published, and a Combine property wrapper's
	// storage is not bridged to Objective-C -- there is no "buttons" property
	// on the generated SoftwareUpdateSheetModel interface to read it back
	// from. -progressTimerDidFire: needs whatever buttons the CURRENT state
	// set without changing them, so this mirrors it on the ObjC++ side
	// instead of trying to read it back through the model.
	NSArray<SoftwareUpdateButtonModel*>* _currentButtons;
}
@property (nonatomic, getter = isUpdateBadgeVisible) BOOL updateBadgeVisible;
@property (nonatomic) NSDictionary<NSString*, NSString*>* publicKeys;
@property (nonatomic) SoftwareUpdateSheetModel* model;
@end

@implementation SUDownloadViewController
- (instancetype)initWithCompletionHandler:(void(^)())completionHandler
{
	if(self = [super initWithNibName:nil bundle:nil])
	{
		_completionHandler = completionHandler;
		_publicKeys        = NSBundle.mainBundle.infoDictionary[@"TMSigningKeys"];
		_model             = [SoftwareUpdateSheetModel new];

		self.title = @"";
	}
	return self;
}

- (instancetype)init
{
	return [self initWithCompletionHandler:nil];
}

- (void)dealloc
{
	if(_completionHandler)
		_completionHandler();
}

// Every place below that used to mutate an NSTextField/NSButton in place now
// replaces self.model's state wholesale through these two, which is also
// where the window is re-measured -- see -resizeToFitContent. Called before
// the window (or even self.view) necessarily exists yet: presentError: and
// presentUIForBackgroundCheck: both push a first state before
// runModalWithCompletionHandler: ever asks for self.view, the same
// seed-before-measuring order SettingsPaneFactory's callers use.
- (void)showMessage:(NSString*)message informative:(NSString*)informative buttons:(NSArray<SoftwareUpdateButtonModel*>*)buttons
{
	_currentButtons = buttons;
	[self.model showWithMessage:message informative:informative buttons:buttons];
	[self resizeToFitContent];
}

- (void)showProgressMessage:(NSString*)message informative:(NSString*)informative fraction:(double)fraction indeterminate:(BOOL)indeterminate buttons:(NSArray<SoftwareUpdateButtonModel*>*)buttons
{
	_currentButtons = buttons;
	[self.model showProgressWithMessage:message informative:informative fraction:fraction indeterminate:indeterminate buttons:buttons];
	[self resizeToFitContent];
}

// Re-measures the hosted SwiftUI content and resizes the window to match,
// keeping the top-left corner stationary -- the closest AppKit equivalent to
// what OakTransitionViewController did for the old per-controller subviews,
// minus its crossfade (SwiftUI switches its own content instantly on the
// @Published change that triggers this). fittingSize reflects self.model's
// CURRENT values synchronously, the same guarantee SettingsPaneFactory's
// callers already rely on -- no runloop turn is needed between updating the
// model and reading it back.
- (void)resizeToFitContent
{
	NSView* view = self.view;
	NSSize fitting = view.fittingSize;

	NSWindow* window = view.window;
	if(!window)
	{
		view.frame = (NSRect){ .size = fitting };
		return;
	}

	if(NSEqualSizes(fitting, view.frame.size))
		return;

	NSRect contentRect = [window contentRectForFrameRect:window.frame];
	contentRect.origin.y -= (fitting.height - contentRect.size.height); // keep the top edge stationary
	contentRect.size = fitting;

	view.frame = (NSRect){ .size = fitting };
	[window setFrame:[window frameRectForContentRect:contentRect] display:YES animate:window.isVisible];
}

- (void)loadView
{
	NSImage* icon = [NSImage imageNamed:NSImageNameApplicationIcon];
	icon.size = NSMakeSize(64, 64);
	self.view = [SoftwareUpdateViewFactory makeSheetViewWithModel:self.model icon:icon];
}

- (void)viewWillAppear
{
	_retainedSelf = self;
}

- (void)viewDidDisappear
{
	self.updateBadgeVisible = NO;
	[_progress cancel];
	[_progressTimer invalidate];
	_progressTimer = nil;

	if(_downloadedArchiveURL)
	{
		NSError* error;
		if(![NSFileManager.defaultManager removeItemAtURL:_downloadedArchiveURL error:&error])
			os_log_error(OS_LOG_DEFAULT, "Unable to remove %{public}@: %{public}@", _downloadedArchiveURL.path, error.localizedDescription);
		_downloadedArchiveURL = nil;
	}

	_retainedSelf = nil;
}

- (BOOL)presentError:(NSError*)error
{
	__weak __typeof__(self) weakSelf = self;
	SoftwareUpdateButtonModel* ok = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"OK" enabled:YES isDefault:YES isCancel:NO action:^{
		[weakSelf respondToModalWithResponse:NSAlertFirstButtonReturn];
	}];
	[self showMessage:@"Error Checking for Update" informative:error.localizedDescription buttons:@[ ok ]];

	[self runModalWithCompletionHandler:nil];

	return YES;
}

- (void)presentAlertWithMessage:(NSString*)messageText informativeText:(NSString*)informativeText buttonTitles:(NSArray<NSString*>*)buttonTitles completionHandler:(BOOL(^)(NSModalResponse))completionHandler
{
	NSAlert* alert = [[NSAlert alloc] init];

	alert.messageText     = messageText;
	alert.informativeText = informativeText;

	for(NSString* title in buttonTitles)
		[alert addButtonWithTitle:title];

	[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode){
		if(!completionHandler || completionHandler(returnCode))
			[self.view.window close];
	}];
}

- (void)runModalWithCompletionHandler:(BOOL(^)(NSModalResponse))completionHandler
{
 	NSWindow* window = [NSPanel windowWithContentViewController:self];

	window.animationBehavior       = NSWindowAnimationBehaviorAlertPanel;
	window.excludedFromWindowsMenu = YES;
	window.hidesOnDeactivate       = NO;
	window.level                   = NSModalPanelWindowLevel;
	window.styleMask               = NSWindowStyleMaskTitled;

	// If we use -[NSApplication runModalForWindow:] then the window
	// won’t stay above document windows after the modal session ends
	_runModalCompletionHandler = completionHandler;
	[window makeKeyAndOrderFront:self];
}

// Replaces didClickButton:'s tag lookup: a SwiftUI button's own action closure
// now names the response code directly (see presentUIForBackgroundCheck:
// below) instead of a target/action/tag triple resolving it indirectly.
- (void)respondToModalWithResponse:(NSModalResponse)response
{
	if(!_runModalCompletionHandler || _runModalCompletionHandler(response))
		[self.view.window close];
	_runModalCompletionHandler = nil;
}

- (void)setUpdateBadgeVisible:(BOOL)flag
{
	if(_updateBadgeVisible == flag)
		return;

	if(_updateBadgeVisible = flag)
	{
		if(NSImage* dlBadge = [NSImage imageNamed:@"Update Badge" inSameBundleAsClass:[self class]])
		{
			NSImage* appIcon = NSApp.applicationIconImage;
			NSApp.applicationIconImage = [NSImage imageWithSize:appIcon.size flipped:NO drawingHandler:^BOOL(NSRect dstRect){
				NSRect upperRightRect = NSIntersectionRect(dstRect, NSOffsetRect(dstRect, round(NSWidth(dstRect) * 2 / 3), (NSHeight(dstRect) * 2 / 3)));
				[appIcon drawInRect:dstRect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
				[dlBadge drawInRect:upperRightRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
				return YES;
			}];
		}
	}
	else
	{
		NSApp.applicationIconImage = nil;
	}
}

- (void)presentUIForBackgroundCheck:(BOOL)backgroundCheck remoteURL:(NSURL*)remoteURL remoteVersion:(NSString*)remoteVersion redownloadEnabled:(BOOL)allowRedownload
{
	NSString* localVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSComparisonResult ordering = OakCompareVersionStrings(localVersion, remoteVersion);

	if(backgroundCheck && ordering != NSOrderedAscending)
		return;

	NSString* message;
	NSString* informative;
	if(ordering == NSOrderedAscending)
	{
		message     = @"New Version Available";
		informative = [NSString stringWithFormat: @"%@ %@ is now available. You have version %@. Would you like to download it now?", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"], remoteVersion, localVersion];
	}
	else if(ordering == NSOrderedSame)
	{
		message     = @"Up To Date";
		informative = [NSString stringWithFormat:@"You are running %@ which is the latest version available.", remoteVersion];
	}
	else
	{
		message     = @"You are Using a Prerelease";
		informative = [NSString stringWithFormat:@"%@ is the latest version available. You have version %@.", remoteVersion, localVersion];
	}

	__weak __typeof__(self) weakSelf = self;
	NSMutableArray<SoftwareUpdateButtonModel*>* buttons = [NSMutableArray array];
	[SUButtonsForVersionCheck(ordering, backgroundCheck, allowRedownload, remoteVersion) enumerateObjectsUsingBlock:^(SUButtonSpec* spec, NSUInteger idx, BOOL* stop){
		NSModalResponse response = NSAlertFirstButtonReturn + idx;
		[buttons addObject:[[SoftwareUpdateButtonModel alloc] initWithTitle:spec.title enabled:spec.enabled isDefault:spec.isDefault isCancel:spec.isCancel action:^{
			[weakSelf respondToModalWithResponse:response];
		}]];
	}];
	[self showMessage:message informative:informative buttons:buttons];

	[self runModalWithCompletionHandler:^BOOL(NSModalResponse response){
		if(response == (ordering == NSOrderedAscending ? NSAlertFirstButtonReturn : NSAlertSecondButtonReturn))
		{
			struct statfs sfsb;
			if(statfs(NSBundle.mainBundle.bundlePath.fileSystemRepresentation, &sfsb) == 0 && (sfsb.f_flags & MNT_RDONLY))
			{
				NSString* informativeText = [NSString stringWithFormat:@"%1$@ is running on a read-only file system and can therefore not be updated.\n\nIf you downloaded %1$@ from the internet then moving it out of the Downloads folder should solve the problem.", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
				[self presentAlertWithMessage:@"Read-only File System" informativeText:informativeText buttonTitles:@[ @"OK" ] completionHandler:^BOOL(NSModalResponse returnCode){
					return YES; // Close window
				}];
			}
			else
			{
				[self downloadSoftwareUpdateAtURL:remoteURL];
			}
			return NO; // Keep window open
		}
		else
		{
			if(backgroundCheck)
				[NSUserDefaults.standardUserDefaults setObject:[[NSDate date] dateByAddingTimeInterval:24*60*60] forKey:kUserDefaultsSoftwareUpdateSuspendUntilKey];
			return YES; // Close window
		}
	}];
}

- (void)cancel:(id)sender
{
	[self.view.window close];
}

// downloadArchiveAtURL:forReplacingURL:publicKeys:completionHandler:'s
// completion handler always arrives on the main thread: OakDownloadManager.mm
// creates the NSURLSession with delegateQueue:NSOperationQueue.mainQueue, so
// its NSURLSessionDataDelegate callbacks (including
// -URLSession:task:didCompleteWithError:, which invokes this on the error
// path) run on main, and the success path additionally wraps its call in
// dispatch_group_notify(..., dispatch_get_main_queue(), ...). No hop is
// needed before pushing into self.model.
- (void)downloadSoftwareUpdateAtURL:(NSURL*)downloadURL
{
	_remoteURL = downloadURL;

	__weak __typeof__(self) weakSelf = self;
	id <NSProgressReporting> progressReporting = [OakDownloadManager.sharedInstance downloadArchiveAtURL:downloadURL forReplacingURL:NSBundle.mainBundle.bundleURL publicKeys:self.publicKeys completionHandler:^(NSURL* extractedArchiveURL, NSError* error){
		[weakSelf downloadDidFinishWithArchiveURL:extractedArchiveURL downloadURL:downloadURL error:error];
	}];

	SoftwareUpdateButtonModel* install = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Install & Relaunch" enabled:NO isDefault:YES isCancel:NO action:^{}];
	SoftwareUpdateButtonModel* cancelButton = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Cancel" enabled:YES isDefault:NO isCancel:YES action:^{
		[weakSelf cancel:nil];
	}];
	[self showProgressMessage:@"" informative:@"" fraction:0 indeterminate:YES buttons:@[ install, cancelButton ]];

	// -setDownloadProgress: fires an immediate tick (see below), which reads
	// self.model.buttons back to preserve whatever was just set above -- the
	// buttons must already be correct in self.model before that first tick,
	// or it would momentarily show the PREVIOUS state's buttons (e.g. still
	// "Download"/"Cancel" from New Version Available).
	[self setDownloadProgress:progressReporting.progress];
}

- (void)downloadDidFinishWithArchiveURL:(NSURL*)extractedArchiveURL downloadURL:(NSURL*)downloadURL error:(NSError*)error
{
	[self setDownloadProgress:nil];

	__weak __typeof__(self) weakSelf = self;
	if(extractedArchiveURL)
	{
		self.updateBadgeVisible = YES;
		if(NSApp.isActive)
			OakPlayUISound(OakSoundDidCompleteSomethingUISound);

		_downloadedArchiveURL = extractedArchiveURL; // Will be deleted in viewDidDisappear

		SoftwareUpdateButtonModel* install = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Install & Relaunch" enabled:YES isDefault:YES isCancel:NO action:^{
			[weakSelf installUpdateAtURL:extractedArchiveURL];
		}];
		SoftwareUpdateButtonModel* cancelButton = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Cancel" enabled:YES isDefault:NO isCancel:YES action:^{
			[weakSelf cancel:nil];
		}];
		[self showMessage:[NSString stringWithFormat:@"Downloaded %@", downloadURL.lastPathComponent] informative:@"" buttons:@[ install, cancelButton ]];
	}
	else
	{
		SoftwareUpdateButtonModel* retry = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Retry" enabled:YES isDefault:YES isCancel:NO action:^{
			[weakSelf downloadSoftwareUpdateAtURL:downloadURL];
		}];
		SoftwareUpdateButtonModel* cancelButton = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Cancel" enabled:YES isDefault:NO isCancel:YES action:^{
			[weakSelf cancel:nil];
		}];
		[self showMessage:@"Error Downloading Update" informative:(error.localizedDescription ?: @"") buttons:@[ retry, cancelButton ]];
	}
}

// Folded in from the old SUProgressViewController.setProgress:/
// checkProgressTimerDidFire:. The timer is armed only from inside
// -downloadSoftwareUpdateAtURL:, which -- see that method's own comment -- is
// itself always main-thread, so scheduledTimerWithTimeInterval: here lands on
// the main run loop and every tick below is main-thread too.
- (void)setDownloadProgress:(NSProgress*)newProgress
{
	if(_progress && !newProgress)
		[self progressTimerDidFire:nil];

	if(_progress = newProgress)
	{
		[self progressTimerDidFire:nil];
		_progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(progressTimerDidFire:) userInfo:nil repeats:YES];
	}
	else
	{
		[_progressTimer invalidate];
		_progressTimer = nil;
	}
}

- (void)progressTimerDidFire:(NSTimer*)timer
{
	[self showProgressMessage:_progress.localizedDescription
	               informative:(_progress.isIndeterminate ? @"Estimating time remaining." : _progress.localizedAdditionalDescription)
	                  fraction:_progress.fractionCompleted
	             indeterminate:_progress.isIndeterminate
	                   buttons:_currentButtons];
}

- (BOOL)isInstallableApplicationAtURL:(NSURL*)applicationURL
{
	NSError* error;
	NSNumber* boolean;
	BOOL res = [[applicationURL URLByAppendingPathComponent:[NSString stringWithFormat:@"Contents/MacOS/%@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]] isDirectory:NO] getResourceValue:&boolean forKey:NSURLIsExecutableKey error:&error] && boolean.boolValue;
	if(!res && error)
		os_log_error(OS_LOG_DEFAULT, "Failed checking if %{public}@ has an executable: %{public}@", applicationURL.path, error.localizedDescription);
	return res;
}

// Not weakifying self in the alert-completion blocks below: they are one-shot
// blocks owned transiently by NSAlert's own sheet machinery (released once
// the sheet completes), the same shape presentAlertWithMessage:...: already
// uses, not blocks stored long-term inside self.model the way a button's
// action is -- see the comment on self.model.buttons in showMessage:.
- (void)installUpdateAtURL:(NSURL*)applicationURL
{
	if([self isInstallableApplicationAtURL:applicationURL])
	{
		// Trust gate: the update must carry a valid Developer ID Application
		// signature whose Team Identifier matches the running app. Distinct from
		// the integrity (incomplete-download) failure below — a trust failure is
		// not fixed by redownloading, so we do not offer that here.
		NSString* expectedTeamID = OakRunningApplicationTeamIdentifier();
		if(!OakBundleIsSignedByTeam(applicationURL, expectedTeamID))
		{
			// Two different situations reach here, and naming the wrong one costs
			// the user real time. A nil expectedTeamID means the RUNNING copy
			// carries no Developer ID -- an ad-hoc local build -- so no download
			// could ever match it and the download is not what is wrong. A
			// non-nil expectedTeamID that failed to match is the genuine trust
			// failure this gate exists for. Both used to report the latter, which
			// reads as an accusation against a download that is perfectly fine,
			// and every contributor running a local build hits it.
			BOOL runningCopyIsUnsigned = expectedTeamID == nil;

			os_log_error(OS_LOG_DEFAULT, "Software update rejected: %{public}@ is not signed by the expected Developer ID team (%{public}@)", applicationURL.path, expectedTeamID ?: @"<none>");

			NSString* message = runningCopyIsUnsigned ? @"This Copy Cannot Update Itself" : @"Update Could Not Be Verified";
			NSString* details = runningCopyIsUnsigned
				? @"This copy of TextMate was built locally rather than installed from a signed release, so it has no developer identity to check an update against. The download itself is fine — it just cannot be installed over an unsigned build.\n\nTo get automatic updates, install a release: brew install --cask textmate-revived, or download it from the project’s Releases page."
				: @"The downloaded update is not signed by the expected developer, so it will not be installed.\n\nDownload the latest version manually from the project’s Releases page.";

			[self presentAlertWithMessage:message informativeText:details buttonTitles:@[ @"OK" ] completionHandler:^BOOL(NSModalResponse returnCode){
				return YES; // close the update window
			}];
			return;
		}

		SoftwareUpdateButtonModel* install = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Install & Relaunch" enabled:NO isDefault:YES isCancel:NO action:^{}];
		SoftwareUpdateButtonModel* cancelButton = [[SoftwareUpdateButtonModel alloc] initWithTitle:@"Cancel" enabled:NO isDefault:NO isCancel:YES action:^{}];
		[self showProgressMessage:[NSString stringWithFormat:@"Installing %@…", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]] informative:@"" fraction:0 indeterminate:YES buttons:@[ install, cancelButton ]];

		NSError* error;
		if([NSFileManager.defaultManager replaceItemAtURL:NSBundle.mainBundle.bundleURL withItemAtURL:applicationURL backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:nil error:&error])
		{
			[self showProgressMessage:[NSString stringWithFormat:@"Relaunching %@…", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]] informative:@"" fraction:0 indeterminate:YES buttons:@[ install, cancelButton ]];

			NSString* script = [NSString stringWithFormat:@"{ kill %1$d; while ps -xp %1$d; do if (( ++n == 300 )); then exit; fi; sleep .2; done; open \"$0\" --args $1; } &>/dev/null &", getpid()];

			NSTask* task = [[NSTask alloc] init];
			task.launchPath     = @"/bin/sh";
			task.arguments      = @[ @"-c", script, NSBundle.mainBundle.bundlePath, @"-showReleaseNotes YES" ];
			task.standardInput  = NSFileHandle.fileHandleWithNullDevice;
			task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
			task.standardError  = NSFileHandle.fileHandleWithNullDevice;

			@try {
				[task launch];
			}
			@catch (NSException* e) {
				os_log_error(OS_LOG_DEFAULT, "-[NSTask launch]: %{public}@", e.reason);
			}
		}
		else
		{
			// Left indeterminate/spinning behind the "Failed to Install Update"
			// alert rather than reverting to a static determinate bar the old
			// stopAnimation/indeterminate=NO pair produced -- this path has no
			// test coverage either way, and a live spinner reads at least as
			// well as a stale full progress bar sitting behind the alert.
			[self presentAlertWithMessage:@"Failed to Install Update" informativeText:error.localizedDescription buttonTitles:@[ @"Retry", @"Cancel" ] completionHandler:^BOOL(NSModalResponse returnCode){
				if(returnCode == NSAlertFirstButtonReturn)
					[self installUpdateAtURL:applicationURL];
				return returnCode == NSAlertSecondButtonReturn; // Close window if clicking “Cancel”
			}];
		}
	}
	else
	{
		[self presentAlertWithMessage:@"Integrity Check Failed" informativeText:@"The download is incomplete. This can happen if the system has been deleting temporary files.\n\nWould you like to redownload the update?" buttonTitles:@[ @"Redownload", @"Cancel" ] completionHandler:^BOOL(NSModalResponse returnCode){
			if(returnCode == NSAlertFirstButtonReturn)
			{
				[self downloadSoftwareUpdateAtURL:_remoteURL];

				NSError* error;
				if(![NSFileManager.defaultManager removeItemAtURL:applicationURL error:&error])
					os_log_error(OS_LOG_DEFAULT, "Unable to remove %{public}@: %{public}@", applicationURL.path, error.localizedDescription);

				_downloadedArchiveURL = nil;
			}
			return returnCode == NSAlertSecondButtonReturn; // Close window if clicking “Cancel”
		}];
	}
}
@end
