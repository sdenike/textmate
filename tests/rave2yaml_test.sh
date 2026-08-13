#!/bin/bash
# Every .rave-declared target must appear in the inventory, and dependency
# names must resolve to known targets. A parser that silently drops targets
# is worse than one that crashes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Count declared target BLOCKS, not files: Frameworks/CommitWindow/default.rave
# declares two (CommitWindow, CommitWindowTool), so a file-based `grep -l`
# count undercounts by one. `target` opens every target block in this
# grammar (see bin/rave's Parser#flatten), so counting the directive
# itself -- rather than inferring targets from sources/executable -- is
# exact.
declared=$(grep -hE '^[[:space:]]*target[[:space:]]' \
    Frameworks/*/default.rave Applications/*/default.rave | wc -l | tr -d ' ')
found=$(./bin/rave2yaml --inventory | grep -c '^target ')

[ "$declared" = "$found" ] || {
    echo "FAIL: $declared targets declared in .rave, $found found by parser"; exit 1; }

# every `require` name must resolve -- against Frameworks/Applications
# targets AND vendor targets. Applications/TextMate/default.rave requires
# "kvdb", which is a vendor/ target (see rave2yaml's `vendor-target`
# label); vendor targets are real `require` targets, just reported
# separately, so both label lines count as valid dependency names.
./bin/rave2yaml --inventory > /tmp/inv.txt
names=$(awk '/^target /||/^vendor-target /{print $2}' /tmp/inv.txt | sort -u)
for dep in $(awk '/^  requires /{$1=""; print}' /tmp/inv.txt | tr ' ' '\n' | sort -u); do
    grep -qx "$dep" <<<"$names" || { echo "FAIL: unresolved dependency: $dep"; exit 1; }
done

# --emit-yaml on a vendor target (kvdb, Onigmo, xdiff) must translate it as
# a library.static target with an explicit, resolved sources: file list --
# never a `path: Frameworks/kvdb/src` directory reference (that directory
# doesn't exist; vendor targets don't follow the Frameworks/<name>/src/
# convention). Regression test for the gap 04ac5128 originally closed by
# raising: a rave2yaml that regresses to guessing a Frameworks/<name>/src
# directory for a vendor target would silently emit a project.yml pointing
# nowhere real instead of either translating it correctly or failing loud.
out=$(./bin/rave2yaml --emit-yaml kvdb 2>&1) || {
    echo "FAIL: --emit-yaml kvdb should now succeed (vendor targets are translated), got:"
    echo "$out"
    exit 1; }
grep -q 'type: library.static' <<<"$out" || {
    echo "FAIL: --emit-yaml kvdb didn't emit a library.static target: $out"; exit 1; }
grep -q 'path: "vendor/kvdb/' <<<"$out" || {
    echo "FAIL: --emit-yaml kvdb didn't emit explicit vendor/kvdb/... source paths: $out"; exit 1; }
grep -q 'Frameworks/kvdb/src' <<<"$out" && {
    echo "FAIL: --emit-yaml kvdb referenced a nonexistent Frameworks/kvdb/src: $out"; exit 1; }

# A vendor target with no VENDOR_EXTRA entry must still raise -- the
# fail-loud guard's spirit (04ac5128) survives for anything the table
# hasn't been taught, even though the 3 known vendor targets now translate.
# There's no 4th vendor fixture to exercise this end-to-end (no --root
# override, and adding a fake vendor/ directory would be its own scope), so
# this is a static check that checked_target's guard clause and its
# VENDOR_EXTRA gate are both still present in the source, rather than an
# eval of the script (arbitrary-code-execution risk for no real benefit
# here -- the guard's shape is simple enough to assert on textually).
grep -q "target.vendor && !VENDOR_EXTRA.key?(name)" bin/rave2yaml || {
    echo "FAIL: checked_target's unknown-vendor-target guard (VENDOR_EXTRA gate) is missing"; exit 1; }
for v in kvdb Onigmo xdiff; do
    grep -q "'$v'" <<<"$(sed -n '/^VENDOR_EXTRA = {/,/^}.freeze/p' bin/rave2yaml)" || {
        echo "FAIL: VENDOR_EXTRA has no entry for '$v'"; exit 1; }
done

echo "PASS: $found targets, all dependencies resolve"
