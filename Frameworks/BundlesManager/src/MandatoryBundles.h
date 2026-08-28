#import <Foundation/Foundation.h>

// Compile-time pinned list of bundles required by TextMate to function.
// Users cannot remove, disable, or repoint these via the bundle registry.
//
// The `sha` field IS the pinned ref — bundles are always fetched (and
// embedded) at this exact commit. Branch names are documented in the
// trailing comment for human reference only; bumping the pin is done by
// editing this file and re-running bin/fetch_embedded_bundles.sh.
//
// Matching tmbundle directories are embedded inside the .app under
// Contents/SharedSupport/Bundles/<name>.tmbundle/ so a fresh launch with
// no network still yields a functional editor.

struct TMMandatoryBundle
{
	char const* uuid;
	char const* name;
	char const* url;
	char const* sha;
	char const* category;
};

static struct TMMandatoryBundle const kTMMandatoryBundles[] = {
	// branch: main — carries the ruby18 compatibility shim in
	// Support/shared/bin/, which is what makes the many `#!/usr/bin/env ruby18`
	// shebangs in *other* bundles run at all. That shim is a stopgap: those
	// bundles still need forking and porting properly. See its header comment.
	// Also carries Ruby 2.6 compatibility shims (jcode, parsedate, iconv) in
	// Support/shared/lib/ for third-party bundles that still `require` them,
	// reached via a RUBYLIB entry in Preferences/Shared Support Path.tmPreferences.
	{
		"0BB1F01A-4F0A-475A-ACDD-0F5578F2EFC3",
		"Bundle Support",
		"https://github.com/sdenike/bundle-support.tmbundle",
		"809b321afddaad82ecfdea6e07f6401683adf22f",
		"Other",
	},
	// branch: main
	{
		"B7BC3FFD-6E4B-11D9-91AF-000D93589AF6",
		"Text",
		"https://github.com/sdenike/text.tmbundle",
		"34ab58910c42f53798f19dd2cba3d7732a3e8d03",
		"Other",
	},
	// branch: main — carries the ruby18 shebang fix for the Move to EOL macro
	{
		"4F45FDC0-62CA-4786-9134-8BC7C1F5606F",
		"Source",
		"https://github.com/sdenike/source.tmbundle",
		"36685fda6c3b0ea63f360f95284c765b9e0d1e11",
		"Other",
	},
	// branch: master (fork of textmate/themes.tmbundle — pure data, no Ruby)
	{
		"A4380B27-F366-4C70-A542-B00D26ED997E",
		"Themes",
		"https://github.com/sdenike/themes.tmbundle",
		"e6e918506291b2dec178ad1b7e6f04653d25818c",
		"Themes",
	},
};

static size_t const kTMMandatoryBundleCount = sizeof(kTMMandatoryBundles) / sizeof(kTMMandatoryBundles[0]);
