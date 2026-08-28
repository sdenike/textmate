#!/bin/bash
# Measures time from opening a file to CPU quiescence: how long the app's
# process keeps burning CPU after a file is opened, including background
# work such as grammar parsing (see initiate_repair,
# Frameworks/buffer/src/parsing.cc). This is deliberately NOT
# measure-responsive.sh's metric -- that one only cares whether the main
# thread answers an Apple Event promptly, so it can show a win from moving
# work off the critical path. This harness cannot: quiescence includes the
# deferred work by definition. See CLAUDE.md's Benchmarking section.
#
# usage: measure-open.sh <label> </path/to/App.app> <file> [runs]

set -uo pipefail

LABEL="${1:?usage: measure-open.sh <label> <App.app> <file> [runs]}"
APP="${2:?usage: measure-open.sh <label> <App.app> <file> [runs]}"
FILE="${3:?usage: measure-open.sh <label> <App.app> <file> [runs]}"
RUNS="${4:-3}"

BIN_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")
BIN="$APP/Contents/MacOS/$BIN_NAME"

# Refuse outright, rather than kill anything, if any process with this
# executable name is already running -- anywhere, not just at this exact
# $APP path. Both are real hazards: an instance at exactly $APP is the
# literal "already running" case (this is the guard measure-responsive.sh
# is missing -- its unconditional `pkill -f "$APP/Contents/MacOS/$BIN_NAME"`
# at the top of every run kills whatever is at that path with no check, and
# CLAUDE.md records that this "nearly cost the maintainer their session").
# An instance of the same binary name at a *different* path is the same
# bundle id from another copy -- every build of this fork ships as
# com.shelbydenike.TextMate regardless of where it lives on disk (see
# measure.sh's other_instance_pid comment) -- and `open -a` given an
# explicit path is not verified here to always start a distinct process
# rather than activate that other one, so it is treated as the same hazard
# rather than assumed safe. Checked once, up front, before this script has
# launched anything of its own: anything matching here cannot be ours.
other_running () {
	local exe="$1" p cmd
	for p in $(pgrep -x "$exe" 2>/dev/null); do
		cmd=$(ps -o command= -p "$p" 2>/dev/null)
		[ -n "$cmd" ] && printf '%s\t%s\n' "$p" "$cmd"
	done
}

conflicts=$(other_running "$BIN_NAME")
if [ -n "$conflicts" ]; then
	echo "$LABEL: refusing to run -- already running, and this script did not start it:" >&2
	echo "$conflicts" >&2
	echo "$LABEL: quit it yourself first (not by this script)." >&2
	exit 1
fi

now_ms () { python3 -c 'import time;print(int(time.time()*1000))'; }

# `ps`'s %CPU is the kernel's own decaying recent-usage average (the same
# figure `top` shows), summed across every thread of the process -- it is
# NOT a lifetime-since-launch average, which matters because a process that
# ran hot for several seconds must still be able to read back near 0% soon
# after going idle. Verified directly before writing this: a throwaway
# process spun one core for 4s then went idle, sampled every 0.25s -- %CPU
# rose to ~10% while busy (this sandbox shares cores with other work, so the
# absolute number is not the point) and fell to 0.0% within ~1s of the busy
# loop ending. That is what makes the streak-based check below meaningful
# rather than a check that would just never fire for a long-lived process.
#
# This also sidesteps the other CPU-tooling trap CLAUDE.md records:
# `xctrace --launch` resolves through Launch Services by bundle id, not the
# path given, so it can silently profile the wrong copy of an app that
# shares a bundle id with another running instance (this fork's own
# lineage, always -- see measure.sh's other_instance_pid comment). Nothing
# here is addressed by id: the pid comes from `pgrep -f` against this exact
# $BIN path, and %CPU is read straight off that pid with `ps -p`, same as
# CLAUDE.md's advice to use `sample` on a directly executed binary rather
# than an id-resolved one.
cpu_of () {
	ps -o %cpu= -p "$1" 2>/dev/null | tr -d ' '
}

# Quiescent = %CPU at or below QUIET_PCT for QUIET_STREAK consecutive
# samples, SAMPLE_S apart. A single low sample is not trustworthy on its
# own: initiate_repair (Frameworks/buffer/src/parsing.cc) parses in batches
# and "bounces the completion back every ~10-20 lines" rather than running
# to completion in one shot, so a large file's background parse has brief
# gaps between batches that one low sample could mistake for "done". The
# streak requirement mirrors measure-responsive.sh's own "three in a row"
# reasoning for the identical kind of gap. QUIET_DEADLINE_S is generous
# because quiescence is the slower of the two metrics by design -- a 1 MB
# file's full parse is measured in seconds (CLAUDE.md's Performance
# section), not the milliseconds measure-responsive.sh bounds itself to.
QUIET_PCT=3
QUIET_STREAK=5
SAMPLE_S=0.25
QUIET_DEADLINE_S=60
SAMPLES_PER_SEC=4       # must match SAMPLE_S; kept separate so the sample
                         # budget below is plain bash integer arithmetic
MAX_SAMPLES=$((QUIET_DEADLINE_S * SAMPLES_PER_SEC))

# Waits for pid $1 to go quiescent. Prints elapsed ms and returns 0, or
# returns 1 (nothing printed) if the pid disappeared or never settled.
wait_quiescent () {
	local pid="$1" streak=0 cpu t0 sample
	t0=$(now_ms)
	for sample in $(seq 1 "$MAX_SAMPLES"); do
		kill -0 "$pid" 2>/dev/null || return 1
		cpu=$(cpu_of "$pid")
		[ -n "$cpu" ] || return 1
		# Integer part only ("12.3" -> "12"): precise enough at a
		# single-digit-percent threshold and avoids needing bash to do
		# floating-point comparison, which it cannot do natively.
		if [ "${cpu%.*}" -le "$QUIET_PCT" ]; then
			streak=$((streak+1))
		else
			streak=0
		fi
		if [ "$streak" -ge "$QUIET_STREAK" ]; then
			echo $(( $(now_ms) - t0 ))
			return 0
		fi
		sleep "$SAMPLE_S"
	done
	return 1
}

# Waits (bounded) for pid $1 to actually exit, rather than a flat sleep --
# same reasoning as measure.sh's GONE_DEADLINE: a fixed delay can still race
# a slow teardown and end up racing the next launch against a process that
# has not actually gone yet.
wait_gone () {
	local pid="$1" deadline=$((SECONDS + 5))
	while kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do
		sleep 0.1
	done
}

echo "#### $LABEL -- $(basename "$FILE")"

readings=()
pid=""
for run in $(seq 1 "$RUNS"); do
	# Fresh instance every run, same as measure-responsive.sh, so no run
	# benefits from another run's warmed-up in-process caches (e.g.
	# bundles::value_for_setting's memoised query, CLAUDE.md's Performance
	# section) -- kill only the pid this script itself observed launching,
	# never a broad pkill by path, so a race can never take out something
	# this run did not start.
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null
		wait_gone "$pid"
	fi

	open -a "$APP"

	pid=""
	for i in $(seq 1 100); do
		found=$(pgrep -n -f "$BIN" 2>/dev/null) && [ -n "$found" ] && pid="$found" && break
		sleep 0.1
	done
	if [ -z "$pid" ]; then
		echo "  run $run: skipped (app never launched)"
		continue
	fi

	# Untimed: drain session restore before the clock starts. CLAUDE.md is
	# explicit that this is not optional -- "Never hand-roll an
	# open-and-wait-for-idle loop. TextMate restores previously open
	# documents at launch, so such a loop times session restore rather than
	# the open; this produced a nonsensical negative reading and
	# invalidated two figures." measure-responsive.sh drains the same cost
	# with an untimed `open -a "$APP"; sleep 6` before its own timed
	# portion; this does at least as well by waiting on the actual signal
	# (quiescence) instead of a fixed guess, and skipping the run -- not
	# reporting a number -- if the app never settles.
	if ! wait_quiescent "$pid" >/dev/null; then
		echo "  run $run: skipped (never went idle after launch -- session restore or startup work still running)"
		kill "$pid" 2>/dev/null
		pid=""
		continue
	fi

	t0=$(now_ms)
	open -a "$APP" "$FILE"

	if elapsed=$(wait_quiescent "$pid"); then
		echo "  run $run: quiescent after ${elapsed} ms"
		readings+=("$elapsed")
	else
		echo "  run $run: not measured (never went quiescent within ${QUIET_DEADLINE_S}s)"
	fi
done

if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
	kill "$pid" 2>/dev/null
fi

# This machine drifts within a session (CLAUDE.md: "Identical builds have
# varied 28% across three consecutive rounds"), so report every reading
# plus the spread -- never a median alone.
if [ "${#readings[@]}" -gt 0 ]; then
	python3 -c "
import statistics, sys
vals = [int(x) for x in sys.argv[1:]]
med = statistics.median(vals)
lo, hi = min(vals), max(vals)
spread = (hi - lo) / med * 100 if med else 0.0
print('  readings: ' + ', '.join(str(v) for v in vals) + ' ms')
print(f'  min {lo} ms, median {med:g} ms, max {hi} ms, spread {spread:.1f}% of median')
" "${readings[@]}"
else
	echo "  no successful runs -- nothing to summarize"
fi

echo "[done: $LABEL]"
