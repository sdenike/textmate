#!/bin/bash
# Xcode Run Script build-phase interpreter for the `files`/`copy` directives
# on Task 6's four bundle-like targets (TextMate.app, Dialog.tmplugin,
# Dialog2.tmplugin, TextMateQL.qlgenerator) -- the resource-assembly half of
# what rave2yaml's emit_app_target/emit_bundle_target/emit_qlgenerator_target
# can't express as a native Xcode build phase (there is no XcodeGen
# equivalent of rave's per-extension `files` transform dispatch over an
# arbitrary directory glob). Each target's manifest below is a line-by-line
# transcription of its own default.rave `files`/`copy` directives, verified
# by hand against the source file (same rationale as bin/rave2yaml's
# VENDOR_EXTRA/EMBED tables: this shape is a one-off for four targets, not
# worth teaching the generic parser).
#
# NOT this script's job: embedding another target's OWN build product
# (@PrivilegedTool, @mate, @tm_query, @Dialog, @Dialog2, @TextMateQL,
# @tm_dialog, @tm_dialog2). Those go through XcodeGen's native `dependencies:
# ... embed: true, copy: {destination, subpath}` Copy Files phase instead
# (see project.yml) -- a real Xcode build phase, ordered and codesign-on-copy
# handled by Xcode itself, rather than a raw `cp -R` racing the rest of the
# build.
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
#   "$SRCROOT/Xcode/scripts/assemble_resources.sh" <TextMate|Dialog|Dialog2|TextMateQL>
set -euo pipefail

name="${1:?usage: assemble_resources.sh <TextMate|Dialog|Dialog2|TextMateQL>}"
: "${SRCROOT:?assemble_resources.sh must run as an Xcode build-phase script}"
: "${TARGET_BUILD_DIR:?assemble_resources.sh must run as an Xcode build-phase script}"
: "${CONTENTS_FOLDER_PATH:?assemble_resources.sh must run as an Xcode build-phase script}"
: "${CONFIGURATION:?assemble_resources.sh must run as an Xcode build-phase script}"

scripts="$SRCROOT/Xcode/scripts"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
mkdir -p "$contents"

expand_plist() { "$scripts/expand_plist.sh" "$@"; }
markdown()     { "$scripts/markdown.sh" "$@"; }
utf16()        { "$scripts/utf16.sh" "$@"; }

# Dialog (PlugIns/dialog-1.x/default.rave:7-19) and Dialog2
# (PlugIns/dialog/default.rave:7-20) have an identical resource shape --
# `files English.lproj "Resources"` + `files Info.plist "."` -- differing
# only in which source directory and which embedded tool (tm_dialog /
# tm_dialog2, handled by the native dependency embed, not here).
assemble_plugin() { # <rave-source-dir>
	local dir="$SRCROOT/$1"
	expand_plist "$dir/Info.plist" "$contents/Info.plist"
	utf16 "$dir/English.lproj/InfoPlist.strings" "$contents/Resources/English.lproj/InfoPlist.strings"
}

# QuickLookGenerator/default.rave:1-11 -- only `files Info.plist "."`.
assemble_textmateql() {
	expand_plist "$SRCROOT/Applications/QuickLookGenerator/Info.plist" "$contents/Info.plist"
}

# Applications/TextMate/default.rave:26-32, in order:
#   files resources/* icons/*.icns @PrivilegedTool "Resources"
#   files @mate @tm_query    "MacOS"                        (native embed)
#   files about/* ../../CHANGELOG.md "Resources/About"
#   files Info.plist         "."
#   copy  support/*          "SharedSupport"
#   copy  @Dialog @Dialog2   "PlugIns"                       (native embed)
#   copy  @TextMateQL        "Library/QuickLook"             (native embed)
assemble_textmate() {
	local app="$SRCROOT/Applications/TextMate"
	local header="$app/templates/header.html" footer="$app/templates/footer.html"
	local changelog="$SRCROOT/CHANGELOG.md"

	# capture TEXTMATE_VERSION -- same grep/sed one-liner as default.rave:8.
	local app_version
	app_version=$(grep -om1 '^## .* (v.*)$' "$changelog" | sed 's/.*(v\(.*\))/\1/')

	local get_task_allow=false
	[[ "$CONFIGURATION" == Debug ]] && get_task_allow=true

	# Info.plist (files) + Entitlements.plist (expand -- both carry the
	# target's PLIST_FLAGS: TARGET_NAME via env, YEAR from expand_plist.sh,
	# APP_MIN_OS/APP_VERSION/CS_GET_TASK_ALLOW here, matching
	# default.rave:20 `add PLIST_FLAGS "-dAPP_VERSION=..."` and the
	# config debug/release CS_GET_TASK_ALLOW blocks). CODE_SIGN_ENTITLEMENTS
	# (Base.xcconfig) points at this same DERIVED_FILE_DIR path.
	expand_plist "$app/Info.plist" "$contents/Info.plist" \
		-dAPP_MIN_OS='10.12' -dAPP_VERSION="$app_version"
	expand_plist "$app/Entitlements.plist" "$DERIVED_FILE_DIR/Entitlements.plist" \
		-dAPP_MIN_OS='10.12' -dAPP_VERSION="$app_version" -d"CS_GET_TASK_ALLOW=$get_task_allow"

	# resources/* -- files, non-recursive top-level glob; each entry's own
	# extension picks its transform, same as rave's per-file dispatch.
	utf16 "$app/resources/English.lproj/InfoPlist.strings" \
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

	# about/* + ../../CHANGELOG.md -- files -> Resources/About.
	mkdir -p "$contents/Resources/About/css" "$contents/Resources/About/js"
	for f in About Legal Contributions; do
		markdown "$app/about/$f.md" "$contents/Resources/About/$f.html" "$header" "$footer"
	done
	markdown "$changelog" "$contents/Resources/About/CHANGELOG.html" "$header" "$footer"
	cp -p "$app/about/css/"* "$contents/Resources/About/css/"
	cp -p "$app/about/js/"* "$contents/Resources/About/js/"

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
TextMateQL) assemble_textmateql ;;
TextMate) assemble_textmate ;;
*)
	echo >&2 "assemble_resources.sh: unknown target '$name'"
	exit 1
	;;
esac
