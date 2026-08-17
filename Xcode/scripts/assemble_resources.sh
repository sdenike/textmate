#!/bin/bash
# Xcode Run Script build-phase interpreter for the `files`/`copy` directives
# on Task 6's three bundle-like targets (TextMate.app, Dialog.tmplugin,
# Dialog2.tmplugin) -- the resource-assembly half of what rave2yaml's
# emit_app_target/emit_bundle_target can't express as a native Xcode build
# phase (there is no XcodeGen equivalent of rave's per-extension `files`
# transform dispatch over an arbitrary directory glob). Each target's
# manifest below is a line-by-line transcription of its own default.rave
# `files`/`copy` directives, verified by hand against the source file (same
# rationale as bin/rave2yaml's VENDOR_EXTRA/EMBED tables: this shape is a
# one-off for three targets, not worth teaching the generic parser).
#
# TextMateQL.qlgenerator, the fourth target this comment used to name, was
# retired for QuickLookExtension.appex (Phase 6): a modern app-extension
# target with no rave heritage, so it needs none of this -- INFOPLIST_FILE
# uses native Xcode `$(VAR)` substitution and there is no other resource to
# assemble, so it carries no postBuildScripts entry at all.
#
# NOT this script's job: embedding another target's OWN build product
# (@PrivilegedTool, @mate, @tm_query, @Dialog, @Dialog2, @QuickLookExtension,
# @tm_dialog, @tm_dialog2) -- native `dependencies: embed: true, copy:
# {destination, subpath}` (project.yml) -- or Entitlements.plist (rave2yaml's
# native `entitlements:` key writes that one at `xcodegen generate` time, not
# build time; see emit_app_target's own comment for why: a build-time script
# here created an unresolvable Xcode dependency-graph cycle with
# ProcessProductPackaging, three different ways, before that was abandoned
# for the native mechanism).
#
# Three of rave's six non-native rules are real per-extension transforms,
# each with its own wrapper script alongside this one (ExpandVariables ->
# expand_plist.sh, CompileMarkdown -> markdown.sh, ConvertToUTF16 ->
# utf16.sh); CompileIcon reuses bin/build_app_icon.sh, already written for
# exactly this. CompileXib is native Xcode behaviour EXCEPT for
# resources/English.lproj/MainMenu.xib specifically, which lives inside an
# English.lproj directory this script reassembles by hand rather than through
# Xcode's PBXVariantGroup localization mechanism (a single-language .lproj
# with only two files isn't worth fighting Xcode's localized-variant-group
# wiring for) -- so it is compiled directly here with the same `xcrun ibtool`
# invocation CompileXib uses (bin/rave:650-659, IB_FLAGS from default.rave:18).
#
# Usage (from a project.yml postBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/assemble_resources.sh" <TextMate|Dialog|Dialog2>
set -euo pipefail

name="${1:?usage: assemble_resources.sh <TextMate|Dialog|Dialog2>}"
: "${SRCROOT:?assemble_resources.sh must run as an Xcode build-phase script}"
: "${TARGET_BUILD_DIR:?assemble_resources.sh must run as an Xcode build-phase script}"
: "${CONTENTS_FOLDER_PATH:?assemble_resources.sh must run as an Xcode build-phase script}"

scripts="$SRCROOT/Xcode/scripts"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$contents"

expand_plist() { "$scripts/expand_plist.sh" "$@"; }
markdown()     { "$scripts/markdown.sh" "$@"; }
utf16()        { "$scripts/utf16.sh" "$@"; }

# InfoPlist.strings uses the same `${VAR}` syntax the plists do --
# NSHumanReadableCopyright carries `${YEAR}` -- but rave's per-file dispatch
# picked a transform by extension and sent .strings straight to utf16 with no
# expansion, so the shipped copyright read a literal "2004-${YEAR}". Expand
# first, then transcode. Files with no `${...}` in them pass through unchanged.
expand_utf16() { # <src> <dst>
	local tmp
	tmp=$(mktemp -t InfoPlistStrings)
	expand_plist "$1" "$tmp"
	utf16 "$tmp" "$2"
	rm -f "$tmp"
}

# capture TEXTMATE_VERSION -- same grep/sed one-liner as default.rave:8.
app_version() {
	grep -om1 '^## .* (v.*)$' "$SRCROOT/CHANGELOG.md" | sed 's/.*(v\(.*\))/\1/'
}

# Dialog (PlugIns/dialog-1.x/default.rave:7-19) and Dialog2
# (PlugIns/dialog/default.rave:7-20) have an identical resource shape --
# `files English.lproj "Resources"` + `files Info.plist "."` -- differing
# only in which source directory and which embedded tool (tm_dialog /
# tm_dialog2, handled by the native dependency embed, not here).
assemble_plugin() { # <rave-source-dir>
	local dir="$SRCROOT/$1"
	expand_plist "$dir/Info.plist" "$contents/Info.plist"
	expand_utf16 "$dir/English.lproj/InfoPlist.strings" "$contents/Resources/English.lproj/InfoPlist.strings"
}

# Applications/TextMate/default.rave:26-32, in order (minus Entitlements.plist
# -- not a files/copy line, and not this script's job, see the file header):
#   files resources/* icons/*.icns @PrivilegedTool "Resources"
#   files @mate @tm_query    "MacOS"                        (native embed)
#   files about/* ../../CHANGELOG.md "Resources/About"
#   files Info.plist         "."
#   copy  support/*          "SharedSupport"
#   copy  @Dialog @Dialog2 @QuickLookExtension "PlugIns"    (native embed)
assemble_textmate() {
	local app="$SRCROOT/Applications/TextMate"
	local header="$app/templates/header.html" footer="$app/templates/footer.html"
	local changelog="$SRCROOT/CHANGELOG.md"

	# Info.plist (files) -- carries the target's PLIST_FLAGS: TARGET_NAME via
	# env, YEAR from expand_plist.sh, APP_MIN_OS/APP_VERSION here.
	expand_plist "$app/Info.plist" "$contents/Info.plist" \
		-dAPP_MIN_OS='10.12' -dAPP_VERSION="$(app_version)"

	# resources/* -- files, non-recursive top-level glob; each entry's own
	# extension picks its transform, same as rave's per-file dispatch.
	expand_utf16 "$app/resources/English.lproj/InfoPlist.strings" \
		"$contents/Resources/English.lproj/InfoPlist.strings"

	mkdir -p "$contents/Resources/English.lproj"
	xcrun ibtool --compile "$contents/Resources/English.lproj/MainMenu.nib" \
		--errors --warnings --notices --output-format human-readable-text \
		"$app/resources/English.lproj/MainMenu.xib"

	"$SRCROOT/bin/build_app_icon.sh" "$app/resources/textmate_lives.icon" "$contents/Resources/Assets.car"

	local f
	for f in WKWebView.js TextMate.scriptSuite TextMate.scriptTerminology Default.tmProperties KeyBindings.dict; do
		cp -p "$app/resources/$f" "$contents/Resources/$f"
	done

	mkdir -p "$contents/Resources/TextMate Help/css" "$contents/Resources/TextMate Help/images"
	for f in "$app/resources/TextMate Help"/*.md; do
		markdown "$f" "$contents/Resources/TextMate Help/$(basename "$f" .md).html" "$header" "$footer"
	done
	cp -p "$app/resources/TextMate Help/css/"* "$contents/Resources/TextMate Help/css/"
	cp -p "$app/resources/TextMate Help/images/"* "$contents/Resources/TextMate Help/images/"

	# icons/*.icns -- files, flat glob, plain copy (no transform for .icns).
	mkdir -p "$contents/Resources"
	cp -p "$app/icons/"*.icns "$contents/Resources/"

	# Framework image assets. The frameworks are statically linked into the
	# app, so +[NSImage imageNamed:inSameBundleAsClass:] resolves through
	# +[NSBundle bundleForClass:] to the app bundle itself -- these must sit
	# flat in Resources/, not under a gfx/ subdirectory, or the lookup misses.
	#
	# A miss is silent: imageNamed: returns nil, and an NSButton with neither
	# image nor title falls back to drawing AppKit's default title, "Button".
	# That is exactly what shipped in v3.0.0-revived.16 and .17 -- the tab
	# overflow button and the per-tab close button both rendered as the word
	# "Button". Verify after changing this with:
	#   find "$APP/Contents/Resources" -name 'TabOverflowThinTemplate*'
	#
	# Two things this glob got wrong until 2026-08-15, both silent, and together
	# they cost another 40 images on top of the 40 the .18 fix recovered:
	#
	#   * It only looked in directories named `gfx`. Four frameworks keep their
	#     artwork elsewhere -- FileBrowser, DocumentWindow and OakTextView under
	#     `resources/`, Preferences under `icons/`.
	#   * It only matched `*.png`. The entire gutter icon set is PDF: the folding
	#     arrows, bookmarks, and the diff/error/warning/note marks.
	#
	# So the file browser's search, favorites and SCM buttons drew nothing, the
	# Preferences toolbar had no icons, and the gutter had no folding arrows --
	# from the Xcode migration until this was fixed.
	#
	# `-type f -o -type l` rather than plain `-type f`: BundleEditor ships
	# Proxy.png as a symlink to Settings.png, and -type f silently excludes
	# symlinks, so the plain form copied 39 of the 40 images. cp follows the
	# link and writes a real file, which is what the bundle wants.
	#
	# Flattening is safe: every image basename under Frameworks/ is unique, so
	# nothing overwrites anything. If that ever stops being true this loop will
	# silently pick a winner, so check with:
	#   find Frameworks -name '*.png' -o -name '*.pdf' | xargs -n1 basename | sort | uniq -d
	while IFS= read -r -d '' gfx; do
		cp -p "$gfx" "$contents/Resources/$(basename "$gfx")"
	done < <(find "$SRCROOT/Frameworks" -type d \( -name gfx -o -name resources -o -name icons \) \
		-exec find {} \( -type f -o -type l \) \( -name '*.png' -o -name '*.pdf' -o -name '*.tiff' \) -print0 \;)

	# about/* + ../../CHANGELOG.md -- files -> Resources/About.
	mkdir -p "$contents/Resources/About/css"
	for f in About Legal; do
		markdown "$app/about/$f.md" "$contents/Resources/About/$f.html" "$header" "$footer"
	done
	markdown "$changelog" "$contents/Resources/About/CHANGELOG.html" "$header" "$footer"
	cp -p "$app/about/css/"* "$contents/Resources/About/css/"

	# support/* -- copy, never a compiler transform (rave's `copy` directive
	# bypasses Compiler.transform entirely -- always a literal byte copy), so
	# the whole tree (Bundle Support.tmbundle, Themes.tmbundle,
	# Avian.tmbundle, Text.tmbundle, Source.tmbundle) is one verbatim rsync
	# rather than hundreds of individually-transformed entries. Confirmed no
	# symlinks under support/ before relying on a recursive copy here (Task
	# 5's FileBrowser/scm symlink lesson).
	mkdir -p "$contents/SharedSupport"
	rsync -a --delete "$app/support/" "$contents/SharedSupport/"
}

case "$name" in
Dialog) assemble_plugin PlugIns/dialog-1.x ;;
Dialog2) assemble_plugin PlugIns/dialog ;;
TextMate) assemble_textmate ;;
*)
	echo >&2 "assemble_resources.sh: unknown target '$name'"
	exit 1
	;;
esac
