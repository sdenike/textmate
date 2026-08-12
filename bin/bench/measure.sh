#!/bin/bash
# Measures one .app bundle. Usage: measure.sh <label> </path/to/App.app>
# Emits a single Markdown table row on stdout.
#
# Never launches an app Gatekeeper does not accept: this harness must stay
# safe to re-run unattended in later phases. If the assessment rejects the
# bundle (absent, broken, or ad-hoc signature included), only the static
# metrics are recorded; launch and RSS are reported as "not measured" with
# a reason instead of a fabricated number.
set -euo pipefail

LABEL="$1"
APP="$2"
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"

SIZE_KB=$(du -sk "$APP" | cut -f1)
ARCHS=$(lipo -archs "$BIN" 2>/dev/null | tr ' ' '+')
DYLIBS=$(otool -L "$BIN" | tail -n +2 | grep -c '@rpath\|@loader_path' || true)

LAUNCH_MS="not measured (Gatekeeper)"
RSS_MB="not measured (Gatekeeper)"

# official and undead (and, on a developer's own Mac, a real installed
# TextMate) all ship the identical CFBundleIdentifier com.macromates.TextMate.
# An Apple Event addressed "by id" resolves to whichever process currently
# owns that id system-wide, not necessarily the one this script launched at
# $APP. Detect any *other* process with the same executable name before
# trusting an id-addressed event to land on our own instance: a real
# session the user has open must never be sent a quit, and the readiness
# poll must never be allowed to answer from the wrong process and produce a
# plausible but wrong LAUNCH_MS.
other_instance_pid() {
	local exe p cmd
	exe=$(basename "$BIN")
	for p in $(pgrep -x "$exe" 2>/dev/null); do
		cmd=$(ps -o command= -p "$p" 2>/dev/null)
		[ -n "$cmd" ] || continue
		case "$cmd" in
		"$APP"/*) ;;
		*)
			printf '%s' "$p"
			return 0
			;;
		esac
	done
	return 1
}

# Runs one AppleScript command with a hard per-call timeout. osascript can
# block indefinitely rather than fail fast when the calling process lacks
# Automation (TCC) permission for the target app in a non-interactive
# session (confirmed while building this harness), so a plain `|| true`
# is not enough to guarantee the script ever returns. Written to stay
# correct under `set -e`: a killed `wait` must not abort the script before
# its exit status is captured. Refuses to send anything while another
# process owns this bundle id (see other_instance_pid above), since every
# script-issued AppleScript here addresses the target "by id".
osascript_bounded() {
	local secs="$1" script="$2" pid watchdog rc conflict
	if conflict=$(other_instance_pid); then
		echo "measure.sh: refusing Apple Event to \"$BUNDLE_ID\" -- pid $conflict owns it and is not this run's launch ($APP)" >&2
		return 1
	fi
	osascript -e "$script" >/dev/null 2>&1 &
	pid=$!
	( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
	watchdog=$!
	rc=0
	wait "$pid" 2>/dev/null || rc=$?
	kill "$watchdog" 2>/dev/null || true
	wait "$watchdog" 2>/dev/null || true
	return "$rc"
}

if spctl --assess --type execute "$APP" >/dev/null 2>&1; then
	BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")

	# Refuse the entire launch/measure sequence up front if some other
	# process (a real TextMate session, or a leftover from measuring the
	# other build) already owns this bundle id: open -a itself could
	# activate that other instance instead of starting ours, and every
	# id-addressed Apple Event below would be unsafe to send regardless.
	if conflict=$(other_instance_pid); then
		echo "measure.sh: pid $conflict already owns \"$BUNDLE_ID\" and is not at $APP -- skipping launch measurement for $LABEL" >&2
		LAUNCH_MS="not measured (bundle id owned by another process)"
		RSS_MB="not measured (bundle id owned by another process)"
	else
		osascript_bounded 3 "tell application id \"$BUNDLE_ID\" to quit" || true
		# Wait for a prior instance to actually exit rather than a flat sleep:
		# a fixed delay can still race a slow teardown, timing a fresh launch
		# against a process that is still there to be re-activated instead of
		# started cold, and later finding it gone when RSS is sampled.
		GONE_DEADLINE=$((SECONDS + 5))
		while pgrep -f "$APP" >/dev/null 2>&1 && [ "$SECONDS" -lt "$GONE_DEADLINE" ]; do
			sleep 0.1
		done

		# Untimed warm-up launch, discarded. The very first launch of a binary
		# includes Gatekeeper's first-run verification and (for one just
		# unpacked by this same run) a cold page cache, both one-time costs
		# that do not reflect what a user experiences on every later launch.
		# Recorded numbers below are the documented "second launch onward";
		# this is what makes that true rather than aspirational.
		open -a "$APP"
		WARM_DEADLINE=$((SECONDS + 30))
		while [ "$SECONDS" -lt "$WARM_DEADLINE" ]; do
			osascript_bounded 2 "tell application id \"$BUNDLE_ID\" to count windows" && break
			sleep 0.05
		done
		osascript_bounded 3 "tell application id \"$BUNDLE_ID\" to quit" || true
		GONE_DEADLINE=$((SECONDS + 5))
		while pgrep -f "$APP" >/dev/null 2>&1 && [ "$SECONDS" -lt "$GONE_DEADLINE" ]; do
			sleep 0.1
		done

		# Time to responsive: the app answers an Apple Event only once its
		# main run loop is up, which is a real "ready to use" signal rather
		# than a proxy for it.
		START=$(python3 -c 'import time; print(time.time())')
		open -a "$APP"

		READY=0
		DEADLINE=$((SECONDS + 30))
		while [ "$SECONDS" -lt "$DEADLINE" ]; do
			if osascript_bounded 2 "tell application id \"$BUNDLE_ID\" to count windows"; then
				READY=1
				break
			fi
			sleep 0.05
		done
		END=$(python3 -c 'import time; print(time.time())')

		if [ "$READY" -eq 1 ]; then
			LAUNCH_MS=$(python3 -c "print(round(($END - $START) * 1000))")
			# Guard against an empty pid reaching `ps -p`: BSD ps given an
			# empty -p argument prints an "Invalid process id" diagnostic that
			# includes uninitialized memory, which is not valid UTF-8 and
			# crashes Python's text-mode subprocess decoding (observed while
			# building this harness). Report 'n/a' instead, as originally
			# intended, rather than letting that crash the whole measurement.
			RSS_MB=$(python3 -c "
import subprocess
pid = subprocess.run(['pgrep','-n','-f','$APP'],capture_output=True,text=True).stdout.strip()
if pid:
    out = subprocess.run(['ps','-o','rss=','-p',pid],capture_output=True,text=True).stdout.strip()
    print(round(int(out)/1024)) if out else print('n/a')
else:
    print('n/a')
")
		else
			LAUNCH_MS="not measured (timeout)"
			RSS_MB="not measured (timeout)"
		fi

		# Best-effort quit, bounded the same way, then a plain SIGTERM
		# fallback (no special permission required) so a bundle this script
		# launched is never left running just because Automation was
		# unavailable to ask it nicely.
		osascript_bounded 3 "tell application id \"$BUNDLE_ID\" to quit" || true
		PID=$(pgrep -n -f "$APP" || true)
		[ -n "$PID" ] && kill "$PID" 2>/dev/null || true
	fi
fi

printf '| %s | %s | %s | %s | %s | %s |\n' \
	"$LABEL" "$SIZE_KB" "$ARCHS" "$DYLIBS" "$LAUNCH_MS" "$RSS_MB"
