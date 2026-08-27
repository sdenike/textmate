#!/bin/bash
# Xcode Run Script build-phase script: generates mate_version.h into
# $DERIVED_FILE_DIR before Compile Sources, defining MATE_APP_VERSION so
# mate's --version moves with every release instead of colliding with
# upstream's own hardcoded 2.13.3 (see mate.mm's #ifndef fallback, which
# still applies if this header is ever missing).
#
# This replaces an earlier attempt that threaded the version through an
# environment variable (TEXTMATE_MATE_VERSION) exported by bin/build into
# GCC_PREPROCESSOR_DEFINITIONS. That only worked when bin/build itself ran
# the build -- bare xcodebuild, CI and Xcode's own ⌘B never set the
# variable, so :default=2.13.3 silently kicked in on every build that
# actually ships. A build script phase runs identically under all of them,
# the same reason assemble_resources.sh computes the app's own
# CFBundleShortVersionString this way instead of via an env var.
#
# Usage (from a project.yml preBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/gen_mate_version.sh"
set -euo pipefail

: "${SRCROOT:?gen_mate_version.sh must run as an Xcode build-phase script}"
: "${DERIVED_FILE_DIR:?gen_mate_version.sh must run as an Xcode build-phase script}"

# Same CHANGELOG.md heading grep/sed as assemble_resources.sh's app_version()
# -- kept verbatim so the two can never drift apart. `|| version=""` rather
# than letting a malformed heading trip `set -e`: the fallback below covers
# an empty value here the same way mate.mm's #ifndef covers the macro being
# absent entirely.
version="$(grep -om1 '^## .* (v.*)$' "$SRCROOT/CHANGELOG.md" | sed 's/.*(v\(.*\))/\1/')" || version=""
if [ -z "$version" ]; then
	version="2.13.3"
fi

out="$DERIVED_FILE_DIR/mate_version.h"

printf '#define MATE_APP_VERSION "%s"\n' "$version" > "$out~"

# Only replace the header when its contents actually changed. This script's
# phase is basedOnDependencyAnalysis: false (so a CHANGELOG.md version bump
# is never missed, the same reasoning as gen_test.sh's identical guard), and
# an unconditional mv would bump the generated header's mtime on every
# build -- forcing mate.mm to recompile (and mate to relink) every time.
# Comparing first keeps the correctness that setting bought while restoring
# incremental builds.
if cmp -s "$out~" "$out"; then
	rm -f "$out~"
else
	mv "$out~" "$out"
fi
