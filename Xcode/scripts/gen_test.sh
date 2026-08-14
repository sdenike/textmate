#!/bin/bash
# Xcode Run Script build-phase wrapper around bin/gen_test: generates one
# framework's CxxTest runner into $DERIVED_FILE_DIR before Compile Sources,
# so the `sources: { path: $(DERIVED_FILE_DIR)/_T<name>.<ext>, optional: true }`
# entry rave2yaml emits for a `<name>_test` target has something to compile.
#
# Mirrors build.ninja's `GenTest` rule -- same program, same sorted
# `tests/t_*.{cc,mm}` input, same atomic `$out~ && mv $out~ $out` write --
# rather than reinventing the CxxTest generation step:
#
#   rule GenTest
#     command = bin/gen_test $in > $out~ && mv $out~ $out
#
# Usage (from a project.yml preBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/gen_test.sh" <framework-name>
set -euo pipefail

name="${1:?usage: gen_test.sh <framework-name>}"
: "${SRCROOT:?gen_test.sh must run as an Xcode build-phase script}"
: "${DERIVED_FILE_DIR:?gen_test.sh must run as an Xcode build-phase script}"

# Vendor targets (Onigmo is the only one with `tests`) live at
# vendor/<name>/tests/, not Frameworks/<name>/tests/ -- Frameworks/<name>
# doesn't exist for them at all, so fall back the same way rave2yaml's own
# `resolved`/glob logic effectively does (it reads the real .rave-declared
# path, whichever tree the target lives under). Applications/<name> is the
# same fallback one level further: TextMate's own tests/ (e.g. preferences
# migration) live under Applications/TextMate, not a Frameworks/ subtree.
base="Frameworks/$name"
[ -d "$SRCROOT/$base" ] || base="vendor/$name"
[ -d "$SRCROOT/$base" ] || base="Applications/$name"

# Seven frameworks (buffer, document, BundlesManager, FileBrowser, ns,
# encoding, SoftwareUpdate) have .mm test sources alongside .cc; nullglob
# keeps a framework with only one extension from leaving a literal
# unmatched pattern in the list. bin/rave's `tests` builder does a plain
# `.sort` across both extensions combined, not a `.cc` glob followed by a
# `.mm` glob, so re-sort here under the C locale to match: a same-line
# `t_*.{cc,mm}` brace expansion globs+sorts each extension separately and
# only concatenates, which disagrees with build.ninja's GenTest input
# order whenever a .cc and .mm file interleave alphabetically (e.g.
# buffer's t_buffer.mm sorts before t_indexed_map.cc).
shopt -s nullglob
tests=("$SRCROOT/$base"/tests/t_*.cc "$SRCROOT/$base"/tests/t_*.mm)
shopt -u nullglob
# "${tests[@]+"${tests[@]}"}" (not bare "${tests[@]}") everywhere below:
# /bin/bash on this machine is Apple's frozen 3.2.57 (GPLv2-licensed
# ceiling), which treats expanding a zero-element array under `set -u` as
# an unbound-variable error -- reproduced directly (`arr=(); set -u; for x
# in "${arr[@]}"; do :; done` -> "arr[@]: unbound variable") -- fixed in
# bash 4.4+, but this is what Xcode's build-phase scripts actually run
# under. Onigmo is the case that exposed it: bin/gen_test with truly zero
# matched test files (before the `base` fix above, it always searched the
# wrong, nonexistent Frameworks/Onigmo/tests/).
IFS=$'\n' tests=($(printf '%s\n' "${tests[@]+"${tests[@]}"}" | LC_ALL=C sort)); unset IFS

# bin/gen_test textually concatenates every input file's body into ONE
# generated translation unit (it splices #line-tagged source, not separate
# compiled objects), so the runner's OWN extension must be able to hold the
# richest language any input needs: ObjC++ (.mm) is a syntactic superset of
# plain C++ (.cc), but not the other way around. Matches bin/rave's own
# choice exactly (bin/rave:1392: `test_sources.any? { |f| f.end_with?('.mm',
# '.m') } ? '.mm' : '.cc'`) -- and must, since rave2yaml's emit_test_target
# picks the DERIVED_FILE_DIR filename (and GCC_PREFIX_HEADER) the same way;
# disagreeing here would make Xcode look for a file this script never
# writes.
ext=.cc
for t in "${tests[@]+"${tests[@]}"}"; do
  case "$t" in *.mm|*.m) ext=.mm ;; esac
done

out="$DERIVED_FILE_DIR/_T${name}${ext}"

"$SRCROOT/bin/gen_test" "${tests[@]+"${tests[@]}"}" > "$out~"
# Only replace the runner when its contents actually changed. This script runs on
# every build (its phase is basedOnDependencyAnalysis: false, so that adding or
# editing a test is never missed), and an unconditional mv would bump the
# generated file's mtime every time -- forcing a recompile and relink of every
# test target on every build. Comparing first keeps the correctness that setting
# bought while restoring incremental builds.
if cmp -s "$out~" "$out"; then
	rm -f "$out~"
else
	mv "$out~" "$out"
fi
