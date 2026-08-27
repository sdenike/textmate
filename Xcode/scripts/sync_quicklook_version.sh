#!/bin/bash
# Xcode Run Script build-phase script: rewrites the built QuickLookExtension
# appex's Info.plist CFBundleShortVersionString from CHANGELOG.md. Runs as a
# postBuildScripts phase specifically because it must run AFTER Xcode has
# already processed INFOPLIST_FILE -- anywhere earlier and this would just be
# overwritten.
#
# macOS requires an app extension's CFBundleShortVersionString to match its
# containing app's exactly. Applications/QuickLookExtension/Info.plist used
# to hardcode that string as a literal, which was correct the day it was
# written and stale the next time the app's version bumped --
# Applications/TextMate/Info.plist's own CFBundleShortVersionString is never
# a literal; it is `${APP_VERSION}`, expanded at build time by
# expand_plist.sh from assemble_resources.sh's app_version(). Reading
# CHANGELOG.md here the same way is what keeps the two from ever drifting
# apart again.
#
# CFBundleVersion is deliberately left untouched: unlike
# CFBundleShortVersionString, Applications/TextMate/Info.plist's own
# CFBundleVersion is a plain literal ("9800"), not derived from
# CHANGELOG.md, and it already matches the extension's -- there is nothing
# for this script to keep in sync there.
#
# Usage (from a project.yml postBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/sync_quicklook_version.sh"
set -euo pipefail

: "${SRCROOT:?sync_quicklook_version.sh must run as an Xcode build-phase script}"
: "${TARGET_BUILD_DIR:?sync_quicklook_version.sh must run as an Xcode build-phase script}"
: "${INFOPLIST_PATH:?sync_quicklook_version.sh must run as an Xcode build-phase script}"

# Same CHANGELOG.md heading grep/sed as assemble_resources.sh's app_version()
# -- kept verbatim (as gen_mate_version.sh already does, for the same reason)
# so none of the three can drift apart. `|| version=""` rather than letting
# a malformed heading trip `set -e`: the fallback below covers an empty
# value here the same way the checked-in Info.plist placeholder covers this
# script never having run at all.
version="$(grep -om1 '^## .* (v.*)$' "$SRCROOT/CHANGELOG.md" | sed 's/.*(v\(.*\))/\1/')" || version=""
if [ -z "$version" ]; then
	version="0.0.0"
fi

plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
