#!/bin/bash
# Measures time-to-responsive when opening a file: how long the main thread
# stays too busy to answer an Apple Event.
#
# This is deliberately NOT measure-open.sh's metric. That one waits for CPU
# quiescence, which includes every deferred background task and therefore
# cannot show a win from moving work off the critical path. What a user
# perceives is whether the window responds, so that is what this measures.
#
# usage: measure-responsive.sh <label> </path/to/App.app> <file> [runs]

set -uo pipefail

LABEL="${1:?usage: measure-responsive.sh <label> <App.app> <file> [runs]}"
APP="${2:?usage: measure-responsive.sh <label> <App.app> <file> [runs]}"
FILE="${3:?usage: measure-responsive.sh <label> <App.app> <file> [runs]}"
RUNS="${4:-3}"

BIN_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")

# Refuse to measure if a TextMate we did not start owns the bundle id -- an
# id-addressed Apple Event resolves to whichever process owns it, which would
# silently measure the wrong instance.
# NOTE: the case statement lives in a function rather than inline in the
# command substitution. macOS ships bash 3.2 (frozen at GPLv2), whose parser
# fails on `case` inside $( ... | while ... ) with "syntax error near `;;'".
# It parses fine under Homebrew bash 5.x, so this breaks only on the stock
# shell -- exactly where the harness actually runs.
other_instance () {
	local p
	for p in $(pgrep -x "$BIN_NAME" 2>/dev/null); do
		case "$(ps -o command= -p "$p" 2>/dev/null)" in
		"$APP"/*) ;;
		*)        echo "$p"; return 0 ;;
		esac
	done
	return 1
}
conflict=$(other_instance)
if [ -n "$conflict" ]; then
	echo "$LABEL: refusing to measure -- pid $conflict owns $BUNDLE_ID and is not at $APP" >&2
	exit 1
fi

now_ms () { python3 -c 'import time;print(int(time.time()*1000))'; }

# One bounded Apple Event. Prints its round-trip latency in ms, or 9999 if it
# did not answer within the timeout -- a non-answer is a data point (the main
# thread was busy), not an error.
ping_ms () {
	local t0 t1
	t0=$(now_ms)
	osascript -e "tell application id \"$BUNDLE_ID\" to count windows" >/dev/null 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 $pid 2>/dev/null && [ $waited -lt 30 ]; do
		sleep 0.1; waited=$((waited+1))
	done
	if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null; echo 9999; return; fi
	wait $pid 2>/dev/null
	t1=$(now_ms)
	echo $((t1-t0))
}

echo "#### $LABEL -- $(basename "$FILE")"

for run in $(seq 1 "$RUNS"); do
	pkill -f "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null; sleep 2
	open -a "$APP"; sleep 6

	# Confirm the app answers promptly before we start, so the number we report
	# is the cost of the open and not a slow launch bleeding into it.
	base=$(ping_ms)
	if [ "$base" -gt 900 ]; then
		echo "  run $run: skipped (app not idle before open: baseline ping ${base}ms)"
		continue
	fi

	t0=$(now_ms)
	open -a "$APP" "$FILE"

	# Time until three consecutive pings come back quickly: the main thread has
	# stopped being saturated. Three in a row, because a single fast reply can
	# land in a gap between work chunks.
	good=0; responsive=""
	for i in $(seq 1 400); do
		p=$(ping_ms)
		if [ "$p" -lt 400 ]; then good=$((good+1)); else good=0; fi
		if [ "$good" -ge 3 ]; then responsive=$(( $(now_ms) - t0 )); break; fi
	done

	if [ -n "$responsive" ]; then
		echo "  run $run: time-to-responsive ${responsive} ms"
	else
		echo "  run $run: not measured (never became responsive)"
	fi
done

pkill -f "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null
echo "[done: $LABEL]"
