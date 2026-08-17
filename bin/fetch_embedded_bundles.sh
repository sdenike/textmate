#!/usr/bin/env bash
# Materialize the mandatory bundles into Applications/TextMate/support/Bundles/
# at the SHAs pinned in Frameworks/BundlesManager/src/MandatoryBundles.h.
#
# Safe to re-run: each bundle carries a .sha marker; unchanged bundles
# are skipped. Run after bumping a pin in MandatoryBundles.h.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
header="$repo_root/Frameworks/BundlesManager/src/MandatoryBundles.h"
dest_root="$repo_root/Applications/TextMate/support/Bundles"

mkdir -p "$dest_root"

# Parse entries from the header. Each entry is five consecutive quoted
# C-strings in order uuid, name, url, sha, category. The category is
# unused by this script but consumed by C++.
strings=()
while IFS= read -r line; do
	strings+=("$line")
done < <(grep -oE '"[^"]+"' "$header" | tr -d '"')

count=${#strings[@]}
if (( count % 5 != 0 )); then
	echo >&2 "fetch_embedded_bundles.sh: unexpected entry count in $header: $count"
	exit 1
fi

for (( i = 0; i < count; i += 5 )); do
	uuid=${strings[i]}
	name=${strings[i+1]}
	url=${strings[i+2]}
	sha=${strings[i+3]}

	# Derive owner/repo from the URL.
	if [[ ! $url =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
		echo >&2 "fetch_embedded_bundles.sh: cannot parse URL: $url"
		exit 1
	fi
	owner=${BASH_REMATCH[1]}
	repo=${BASH_REMATCH[2]}

	dest_dir="$dest_root/$name.tmbundle"
	marker="$dest_dir/.sha"

	if [[ -f $marker ]] && [[ $(cat "$marker") == "$sha" ]]; then
		echo "[skip] $name @ $sha"
		continue
	fi

	echo "[fetch] $name @ $sha"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT

	curl --silent --show-error --fail --location \
		"https://codeload.github.com/$owner/$repo/tar.gz/$sha" \
		| tar -zxmkC "$tmp" --strip-components 1 --disable-copyfile --exclude '._*'

	# Sanity check: info.plist present.
	if [[ ! -f "$tmp/info.plist" ]]; then
		echo >&2 "fetch_embedded_bundles.sh: $name @ $sha has no info.plist"
		exit 1
	fi

	# Sanity check: info.plist carries expected UUID.
	extracted_uuid=$(/usr/libexec/PlistBuddy -c 'Print :uuid' "$tmp/info.plist" 2>/dev/null | tr '[:lower:]' '[:upper:]')
	expected_uuid=$(printf '%s' "$uuid" | tr '[:lower:]' '[:upper:]')
	if [[ $extracted_uuid != $expected_uuid ]]; then
		echo >&2 "fetch_embedded_bundles.sh: UUID mismatch in $name: expected $uuid, got $extracted_uuid"
		exit 1
	fi

	rm -rf "$dest_dir"
	mkdir -p "$dest_dir"
	cp -R "$tmp"/. "$dest_dir"/

	# Scrub artifacts the embedded copy must not carry:
	#   .github/                              — CI metadata, no runtime use
	#   Support/shared/bin/CocoaDialog.app/   — Intel-only, blocks notarization
	#                                            (kept upstream but removed here
	#                                             per commit 297d39de)
	#   src/                                  — find_app.cc and a default.rave
	#                                            build file. The prebuilt find_app
	#                                            binary ships in Support/shared/bin,
	#                                            so these have no runtime use, and
	#                                            d07cc0c8 deleted the rave build
	#                                            system from this repository.
	#                                            Without this scrub, every pin bump
	#                                            silently reintroduces a .rave file.
	rm -rf "$dest_dir/.github"
	rm -rf "$dest_dir/Support/shared/bin/CocoaDialog.app"
	rm -rf "$dest_dir/src"

	# Thin every prebuilt Mach-O to arm64.
	#
	# Upstream ships find_app, plist.bundle and keychain.bundle as universal
	# x86_64+arm64 binaries — 144 KB of the embedded copy is a dead Intel slice
	# this fork can never execute, and shipping it contradicts the arm64-only
	# rule the project declares. These are vendored artifacts we do not compile,
	# so thinning here is the only place it can be enforced; doing it in the
	# checked-in copy alone would be undone by the next pin bump, exactly as the
	# src/ scrub above exists to prevent.
	#
	# lipo fails on a thin binary, so only convert files that really are fat.
	find "$dest_dir" -type f -perm +111 -print0 | while IFS= read -r -d '' bin; do
		archs=$(lipo -archs "$bin" 2>/dev/null) || continue
		case "$archs" in
		*\ *)
			case "$archs" in
			*arm64*)
				if lipo -thin arm64 "$bin" -output "$bin.arm64" 2>/dev/null; then
					# lipo's output does not inherit the executable bit. chmod
					# --reference would be the precise way to copy it, but that is a
					# GNU extension and macOS ships BSD chmod; the find above already
					# selected only executables, so +x restores what was there.
					chmod +x "$bin.arm64"
					mv "$bin.arm64" "$bin"
					echo "  thinned to arm64: ${bin#$dest_dir/}"
				else
					rm -f "$bin.arm64"
					echo >&2 "  WARNING: could not thin $bin (left universal)"
				fi
				;;
			*)
				echo >&2 "  WARNING: $bin has no arm64 slice ($archs) — left as is"
				;;
			esac
			;;
		esac
	done

	echo -n "$sha" > "$marker"

	rm -rf "$tmp"
	trap - EXIT
done

echo "done."
