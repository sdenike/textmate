#!/bin/bash
# Downloads the reference releases and measures each one.
set -euo pipefail

REPO=$(git rev-parse --show-toplevel)
# macOS's own default $TMPDIR ends in a trailing slash (e.g.
# /var/folders/xx/.../T/); strip it before joining so $WORK never contains
# a doubled slash. A doubled slash here is not cosmetic: pgrep -f later
# matches this same path as a literal substring against a running
# process's command line, and the kernel normalizes the actual process
# path to a single slash, so the doubled-slash pattern would never match.
WORK="${TMPDIR:-/tmp}"
WORK="${WORK%/}/tmr-baseline"
mkdir -p "$WORK"
cd "$WORK"

echo "| build | size KB | archs | rpath dylibs | launch ms | RSS MB |"
echo "|---|---|---|---|---|---|"

gh release download v2.0.23 --repo textmate/textmate --dir "$WORK/official" --clobber
gh release download v2.1.4-undead --repo textmatelives/textmate --dir "$WORK/undead" --clobber

# Release assets vary by publisher: .tbz, .zip, and .dmg have all been
# seen in the wild across these forks, so extraction handles whichever one
# actually shipped rather than assuming tar/zip only.
extract() {
	local archive="$1" dest="$2"
	case "$archive" in
	*.zip)
		unzip -oq "$archive" -d "$dest"
		;;
	*.dmg)
		local mnt
		mnt=$(mktemp -d)
		hdiutil attach "$archive" -nobrowse -readonly -mountpoint "$mnt" >/dev/null
		find "$mnt" -maxdepth 2 -name '*.app' -exec cp -R {} "$dest" \;
		hdiutil detach "$mnt" -quiet
		;;
	*)
		tar -xf "$archive" -C "$dest"
		;;
	esac
}

for d in official undead; do
	archive=$(find "$WORK/$d" -maxdepth 1 -type f \( -name '*.tbz' -o -name '*.zip' -o -name '*.dmg' \) | head -1)
	mkdir -p "$WORK/$d/x"
	extract "$archive" "$WORK/$d/x"
	app=$(find "$WORK/$d/x" -maxdepth 2 -name '*.app' | head -1)
	"$REPO/bin/bench/measure.sh" "$d" "$app"
done
