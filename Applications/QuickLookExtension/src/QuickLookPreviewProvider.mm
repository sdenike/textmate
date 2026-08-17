#import "QuickLookPreviewProvider.h"
#import <OSAKit/OSAKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <buffer/buffer.h>
#import <bundles/bundles.h>
#import <file/bytes.h>
#import <file/type.h>
#import <file/reader.h>
#import <io/path.h>
#import <cf/cf.h>
#import <ns/ns.h>
#import <oak/misc.h>
#import <plist/fs_cache.h>
#import <scope/scope.h>
#import <settings/settings.h>
#import <theme/theme.h>
#import <OakFoundation/NSString Additions.h>

// Rendering logic ported from the retired TextMateQL CFPlugIn generator
// (Applications/QuickLookGenerator/src/generate.mm, generate.mm:1-137 for
// these four helpers, generate.mm:190-243 for what is now
// -providePreviewForFileRequest:completionHandler: below). None of it
// touched the deprecated QuickLook C API -- only the request/reply plumbing
// did, and that plumbing is what changed.

static void initialize (NSBundle* extensionBundle)
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		// extensionBundle is .../TextMate.app/Contents/PlugIns/QuickLookExtension.appex --
		// three path components up (the .appex itself, PlugIns, Contents) reaches the app bundle.
		NSString* parentBundlePath = [[[[extensionBundle bundlePath] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
		NSBundle* parentBundle = [NSBundle bundleWithPath:parentBundlePath];

		settings_t::set_default_settings_path([[parentBundle pathForResource:@"Default" ofType:@"tmProperties"] fileSystemRepresentation]);
		settings_t::set_global_settings_path(path::join(path::home(), "Library/Application Support/TextMate/Global.tmProperties"));

		// Load bundle index
		std::vector<std::string> paths;
		for(auto path : bundles::locations())
			paths.push_back(path::join(path, "Bundles"));

		plist::cache_t cache;
		cache.load(path::join(path::home(), "Library/Caches/com.shelbydenike.TextMate/BundlesIndex.binary"));

		auto index = create_bundle_index(paths, cache);
		bundles::set_index(index.first, index.second);
	});
}

static std::string URLtoString (CFURLRef url)
{
	std::string filePath = NULL_STR;
	if(CFStringRef path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle))
	{
		filePath = cf::to_s(path);
		CFRelease(path);
	}
	return filePath;
}

static std::string setup_buffer (CFURLRef url, ng::buffer_t& buffer, size_t maxSize = 20480, size_t maxLines = SIZE_T_MAX)
{
	std::string filePath = URLtoString(url);

	std::string fileContents = NULL_STR;
	if(path::extension(filePath) == ".scpt")
	{
		@autoreleasepool {
			NSDictionary* err = nil;
			if(OSAScript* script = [[OSAScript alloc] initWithContentsOfURL:(__bridge NSURL*)url error:&err])
			{
				fileContents = [[script source] UTF8String] ?: NULL_STR;
				std::replace(fileContents.begin(), fileContents.end(), '\r', '\n');
			}
		}
	}

	if(fileContents == NULL_STR)
		fileContents = file::read_utf8(filePath, nullptr, maxSize);

	if(maxLines != SIZE_T_MAX)
		fileContents.erase(std::find_if(fileContents.begin(), fileContents.end(), [&maxLines](char ch) { return ch == '\n' && --maxLines == 0; }), fileContents.end());

	buffer.insert(0, fileContents);

	// Apply appropriate grammar
	std::string fileType = file::type(filePath, std::make_shared<io::bytes_t>(fileContents.data(), fileContents.size(), false));
	if(fileType != NULL_STR)
	{
		for(auto item : bundles::query(bundles::kFieldGrammarScope, fileType, scope::wildcard, bundles::kItemTypeGrammar))
		{
			buffer.set_grammar(item);
			break;
		}
	}

	return fileType;
}

static NSAttributedString* create_attributed_string (ng::buffer_t& buffer, std::string const& themeUUID, std::string const& fontName, size_t fontSize, theme_ptr* themeOut = nullptr)
{
	if(themeUUID == NULL_STR || fontName == NULL_STR || fontSize == 0)
		return nil;

	bundles::item_ptr themeItem = bundles::lookup(themeUUID);
	if(!themeItem)
		return nil;

	theme_ptr theme = parse_theme(themeItem);
	if(!theme)
		return nil;

	theme = theme->copy_with_font_name_and_size(fontName, fontSize);
	if(themeOut)
		*themeOut = theme;

	// Perform syntax highlighting
	buffer.wait_for_repair();
	std::map<size_t, scope::scope_t> scopes = buffer.scopes(0, buffer.size());

	// Construct RTF output
	NSMutableAttributedString* output = (__bridge_transfer NSMutableAttributedString*)CFAttributedStringCreateMutable(kCFAllocatorDefault, buffer.size());
	size_t from = 0;
	for(auto pair = scopes.begin(); pair != scopes.end(); )
	{
		styles_t styles = theme->styles_for_scope(pair->second);

		size_t to = ++pair != scopes.end() ? pair->first : buffer.size();

		[output appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:buffer.substr(from, to)] attributes:@{
			NSForegroundColorAttributeName:    [NSColor colorWithCGColor:styles.foreground()],
			NSBackgroundColorAttributeName:    [NSColor colorWithCGColor:styles.background()],
			NSFontAttributeName:               (__bridge NSFont*)styles.font(),
			NSUnderlineStyleAttributeName:     @(styles.underlined() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
			NSStrikethroughStyleAttributeName: @(styles.strikethrough() ? NSUnderlineStyleSingle : NSUnderlineStyleNone),
		}]];

		from = to;
	}

	return output;
}

// ==========================
// = QLPreviewingController =
// ==========================

@implementation QuickLookPreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest*)request completionHandler:(void (^)(QLPreviewReply* _Nullable reply, NSError* _Nullable error))handler
{
	initialize([NSBundle bundleForClass:[self class]]);

	NSURL* url = request.fileURL;
	CFURLRef cfURL = (__bridge CFURLRef)url;

	// Load file
	ng::buffer_t buffer;
	std::string fileType = setup_buffer(cfURL, buffer);

	if(fileType == NULL_STR)
	{
		// We don't know the type, let the system handle it
		QLPreviewReply* reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypePlainText contentSize:CGSizeZero dataCreationBlock:^NSData* (QLPreviewReply* replyToUpdate, NSError** error) {
			return [NSData dataWithContentsOfURL:url];
		}];
		handler(reply, nil);
		return;
	}

	NSUserDefaults* userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.shelbydenike.TextMate"];
	NSString* appearance = [userDefaults stringForKey:@"themeAppearance"];
	BOOL darkMode = [appearance isEqualToString:@"dark"];
	if(!darkMode && ![appearance isEqualToString:@"light"]) // If it is not ‘light’ then assume ‘auto’
		darkMode = [[NSAppearance.currentAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] isEqualToString:NSAppearanceNameDarkAqua];
	NSString* themeUUID = [userDefaults stringForKey:darkMode ? @"darkModeThemeUUID" : @"universalThemeUUID"];

	settings_t const settings = settings_for_path(URLtoString(cfURL), fileType);
	theme_ptr theme;
	NSFont* font = [NSFont userFixedPitchFontOfSize:0];
	NSAttributedString* output = create_attributed_string(buffer, to_s(themeUUID), settings.get(kSettingsFontNameKey, to_s([font fontName])), settings.get(kSettingsFontSizeKey, [font pointSize]), &theme);
	if(!output)
	{
		QLPreviewReply* reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypePlainText contentSize:CGSizeZero dataCreationBlock:^NSData* (QLPreviewReply* replyToUpdate, NSError** error) {
			return [NSData dataWithContentsOfURL:url];
		}];
		handler(reply, nil);
		return;
	}

	QLPreviewReply* reply = [[QLPreviewReply alloc] initWithDataOfContentType:UTTypeRTF contentSize:CGSizeZero dataCreationBlock:^NSData* (QLPreviewReply* replyToUpdate, NSError** error) {
		return [output RTFFromRange:NSMakeRange(0, [output length]) documentAttributes:@{
			NSDocumentTypeDocumentAttribute:    [NSString stringWithCxxString:fileType],
			NSBackgroundColorDocumentAttribute: theme ? [NSColor colorWithCGColor:theme->background(fileType)] : [NSColor whiteColor],
		}];
	}];

	handler(reply, nil);
}

@end
