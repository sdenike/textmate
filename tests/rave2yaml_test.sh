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

# --emit-yaml on a vendor target must RAISE, not silently emit a project.yml
# pointing at a nonexistent Frameworks/kvdb/src. Vendor targets (kvdb,
# Onigmo, xdiff) declare no `executable`, so they pass the 'framework' kind
# check same as any real framework -- nothing else catches them without an
# explicit vendor check. Regression test for that gap: a rave2yaml that lost
# the check would print a project.yml here instead of failing.
if out=$(./bin/rave2yaml --emit-yaml kvdb 2>&1); then
    echo "FAIL: --emit-yaml kvdb should have raised (vendor target), produced output instead:"
    echo "$out"
    exit 1
fi
grep -q 'vendor target' <<<"$out" || {
    echo "FAIL: --emit-yaml kvdb failed, but not with a vendor-target error: $out"; exit 1; }
grep -q 'vendor/kvdb/default.rave' <<<"$out" || {
    echo "FAIL: --emit-yaml kvdb error doesn't name the .rave file: $out"; exit 1; }

echo "PASS: $found targets, all dependencies resolve"
