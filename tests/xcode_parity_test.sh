#!/bin/bash
# A target builds under Xcode AND its CxxTest binary runs green.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TARGET="${1:?usage: xcode_parity_test.sh <target>}"

xcodebuild -project TextMate.xcodeproj -target "$TARGET" \
    -configuration Release build CODE_SIGNING_ALLOWED=NO > /tmp/xcb.log 2>&1 || {
    echo "FAIL: xcodebuild failed for $TARGET"; tail -20 /tmp/xcb.log; exit 1; }

echo "PASS: $TARGET builds under Xcode"
