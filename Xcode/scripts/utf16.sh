#!/bin/bash
# Xcode Run Script wrapper mirroring build.ninja's ConvertToUTF16 rule
# exactly, same shell logic and all (bin/rave:689-698):
#
#   rule ConvertToUTF16
#     command = if [[ "$(head -c2 $in)" == $'\xFF\xFE' || "$(head -c2 $in)" == \
#       $'\xFE\xFF' ]]; then /bin/cp -Xp $in $out && touch $out; else iconv -f \
#       utf-8 -t utf-16 < $in > $out~ && mv $out~ $out; fi
#
# Only real user in this tree: English.lproj/InfoPlist.strings (TextMate,
# Dialog, Dialog2 -- TextMateQL has no .strings file).
#
# Usage:
#   utf16.sh <src> <dst>
set -euo pipefail

src="${1:?usage: utf16.sh <src> <dst>}"
dst="${2:?usage: utf16.sh <src> <dst>}"

mkdir -p "$(dirname -- "$dst")"
if [[ "$(head -c2 "$src")" == $'\xFF\xFE' || "$(head -c2 "$src")" == $'\xFE\xFF' ]]; then
	/bin/cp -Xp "$src" "$dst"
else
	iconv -f utf-8 -t utf-16 < "$src" > "$dst~"
	mv "$dst~" "$dst"
fi
