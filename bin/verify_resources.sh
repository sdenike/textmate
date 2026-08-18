#!/bin/bash
# Set-difference check for Xcode/scripts/assemble_resources.sh: every resource
# a framework ships under gfx/, resources/, or icons/ must show up somewhere
# under Contents/Resources of a built app. A miss is silent at runtime --
# imageNamed:/pathForResource:/URLForResource: all just return nil -- so this
# is a set comparison, not a threshold. Printing nothing is the only pass.
#
# This is the third time assemble_resources.sh's resource glob shipped an
# incomplete set (see CLAUDE.md's Liquid Glass section for the first two),
# each time because nothing actually verified presence, only assumed it from
# the extension list looking exhaustive. Run after any build that touches
# resource assembly:
#
#   bin/verify_resources.sh [path/to/TextMate.app]
#
# With no argument, searches $builddir (default ~/build) for the newest
# TextMate.app, same lookup bin/deploy-local uses.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -ge 1 ]; then
	APP="$1"
else
	SEARCH="${builddir:-$HOME/build}"
	APP=$(find "$SEARCH" -maxdepth 6 -name 'TextMate.app' -type d -print0 2>/dev/null \
		| xargs -0 -r ls -dt 2>/dev/null | head -1 || true)
fi

if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
	echo "verify_resources.sh: no built TextMate.app found. Build first, or pass the path." >&2
	exit 1
fi

RESOURCES="$APP/Contents/Resources"
if [ ! -d "$RESOURCES" ]; then
	echo "verify_resources.sh: $RESOURCES does not exist" >&2
	exit 1
fi

# Expected: basename of every file/symlink under a framework's gfx/,
# resources/, or icons/ directory -- the same three directory names
# assemble_resources.sh globs, deliberately not filtered by extension (an
# extension allowlist is exactly the bug this guards against). *.xib ships
# compiled, not copied, so its expected name is <name>.nib, matching the
# ibtool loop in assemble_resources.sh.
expected=$(find Frameworks -type d \( -name gfx -o -name resources -o -name icons \) \
	-exec find {} \( -type f -o -type l \) -not -path '*/tests/*' -print0 \; \
	| xargs -0 -n1 basename \
	| sed 's/\.xib$/.nib/' \
	| sort -u)

# Shipped: basename of every file actually in Contents/Resources, searched
# recursively so subdirectories (English.lproj/, DocumentTypes/) don't need
# naming here too -- except SharedSupport, the rsynced bundle tree, which is
# thousands of files with no relation to framework resources.
shipped=$(find "$RESOURCES" -name SharedSupport -prune -o -type f -exec basename {} \; \
	| sort -u)

missing=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$shipped"))

if [ -n "$missing" ]; then
	echo "verify_resources.sh: FAIL -- referenced under Frameworks/{gfx,resources,icons} but missing from $RESOURCES:" >&2
	printf '%s\n' "$missing" >&2
	exit 1
fi

count=$(printf '%s\n' "$expected" | wc -l | tr -d ' ')
echo "verify_resources.sh: OK -- all $count framework resource basenames present in $RESOURCES"
