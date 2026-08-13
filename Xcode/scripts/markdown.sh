#!/bin/bash
# Xcode Run Script wrapper around bin/gen_html -- mirrors build.ninja's
# CompileMarkdown rule exactly (bin/rave:716-728):
#
#   rule CompileMarkdown
#     command = bin/gen_html > $out~ $flags $in && mv $out~ $out
#
# Applications/TextMate/default.rave's only MD_FLAGS are the header/footer
# templates (`add MD_FLAGS "-h'${HTML_HEADER}' -f'${HTML_FOOTER}'"`), shared
# by every markdown file the app's `files` directive reaches (about/*.md,
# ../../CHANGELOG.md, and resources/TextMate Help/*.md -- MD_FLAGS is
# target-scoped, not per-source-directory, so all three groups use the same
# header/footer), so this script takes them as plain positional args rather
# than hardcoding the template path.
#
# Usage:
#   markdown.sh <src.md> <dst.html> <header.html> <footer.html>
set -euo pipefail

src="${1:?usage: markdown.sh <src.md> <dst.html> <header.html> <footer.html>}"
dst="${2:?usage: markdown.sh <src.md> <dst.html> <header.html> <footer.html>}"
header="${3:?usage: markdown.sh <src.md> <dst.html> <header.html> <footer.html>}"
footer="${4:?usage: markdown.sh <src.md> <dst.html> <header.html> <footer.html>}"

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

mkdir -p "$(dirname -- "$dst")"
"$repo_root/bin/gen_html" -h "$header" -f "$footer" "$src" > "$dst~"
mv "$dst~" "$dst"
