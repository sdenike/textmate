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
echo "PASS: $found targets, all dependencies resolve"
