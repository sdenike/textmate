#!/bin/bash
# Xcode Run Script wrapper around bin/expand_variables -- mirrors build.ninja's
# ExpandVariables rule exactly (bin/rave:700-714):
#
#   rule ExpandVariables
#     command = bin/expand_variables -o $out $flags $in
#
# Used for both Info.plist and Entitlements.plist: both use rave's own
# `${VAR}` substitution syntax, which is NOT the `$(VAR)` syntax Xcode's own
# native Info.plist/entitlements processing understands, so those files must
# be pre-expanded by hand rather than left to INFOPLIST_FILE/
# CODE_SIGN_ENTITLEMENTS's native (and in this case silent no-op) handling.
#
# `-dYEAR=<current year>` is always passed first, matching
# ExpandVariables#transform's own unconditional `flags = ["-dYEAR=..."]`
# (bin/rave:704) -- callers add whatever else the specific file references
# (`-dAPP_VERSION=...`, `-d'CS_GET_TASK_ALLOW=...'`) as extra -d arguments.
# `${TARGET_NAME}` needs no explicit -d: bin/expand_variables falls back to
# ENV when a variable isn't in its -d table, and Xcode already exports
# $TARGET_NAME to every Run Script phase.
#
# Usage:
#   expand_plist.sh <src> <dst> [-d NAME=VALUE ...]
set -euo pipefail

src="${1:?usage: expand_plist.sh <src> <dst> [-d NAME=VALUE ...]}"
dst="${2:?usage: expand_plist.sh <src> <dst> [-d NAME=VALUE ...]}"
shift 2

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

mkdir -p "$(dirname -- "$dst")"
"$repo_root/bin/expand_variables" -o "$dst" -dYEAR="$(date +%Y)" "$@" "$src"
