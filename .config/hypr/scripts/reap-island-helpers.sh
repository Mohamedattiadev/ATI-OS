#!/usr/bin/env bash
# reap-island-helpers.sh — kill the backend's ORPHANED watcher processes.
#
# THE LEAK, AND WHERE IT ACTUALLY COMES FROM
# ------------------------------------------
# NEXT-SESSION.md has carried this for several sessions as an open item with
# the wrong conclusion attached:
#
#   "Something leaks `pactl subscribe`, and it broke the audio stack. Found
#    live: 62 orphaned `pactl subscribe` processes, PPID 1, dating back two
#    days, had exhausted pipewire-pulse's client limit ... THE SOURCE WAS NOT
#    FOUND: nothing in this repo spawns that command, and it is not in
#    ~/.local/bin, AtiScriptsV1 or /usr/local/bin either."
#
# All of that is true and the conclusion drawn from it was the wrong one. It
# is not in this repo because it is in the PACKAGED BACKEND — the one part of
# tide-island the fork deliberately does not vendor. `libIslandBackend.so`
# carries the strings
#
#     pactl / subscribe
#     [SystemServices] dbus-monitor is not available; notification mirroring is disabled
#     [SystemServices] dbus-monitor is not available; portal recording monitoring is disabled
#     [SystemServices] pw-mon is not available; PipeWire recording monitoring is disabled
#
# so `SystemServices` spawns up to four long-lived helpers per shell: a
# `pactl subscribe`, two `dbus-monitor`s and a `pw-mon`. They are QProcess
# children, and when the shell is killed rather than asked to quit they are
# NOT reaped — they reparent to init and run forever. The backend says so
# itself in the log line this tree has already recorded from an unrelated
# crash: `QProcess: Destroyed while process ("pactl") is still running`.
#
# Measured on a session that had been up a few hours and had the island
# restarted a couple of dozen times while a fix was being driven:
#
#     orphaned dbus-monitor (PPID 1):    104
#     orphaned pactl subscribe (PPID 1):  35
#
# and the audio one has already taken the desktop down once — pipewire-pulse
# refusing every client with "too many client application connections".
#
# WHY PPID 1 IS THE WHOLE MATCHER
# -------------------------------
# A LIVE shell's helpers have that shell as their parent. Only an orphan has
# PPID 1. So "PPID is 1 and the command line looks like one of the backend's
# watchers" is exactly the set that belongs to a shell that is already gone,
# and there is no timing window in which this can take a helper away from a
# running island. That is what makes it safe to run unconditionally at start.
#
# Called from island.sh and topbar.sh, because BOTH start entry points into
# the island's config — the island itself, and treetab.qml / popups.qml — and
# every one of them brings its own set.
#
# NOT `pkill -f`: that matches this script's own command line, which is the
# trap the RULES record. The awk walks the fields instead and excludes itself.
set -uo pipefail

reaped=0

# Each pattern is matched against the whole argv, but only for PPID 1, and
# `!/awk/` keeps this awk from matching the pattern it was handed.
while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null && reaped=$((reaped + 1))
done < <(ps -eo pid=,ppid=,args= | awk '
    !/awk/ && $2 == 1 {
        line = $0
        if (line ~ /dbus-monitor/ && line ~ /org\.freedesktop\.(portal|Notifications)/) { print $1; next }
        if (line ~ /pactl/ && line ~ /subscribe/) { print $1; next }
        if (line ~ /pw-mon/) { print $1; next }
    }')

[[ "$reaped" -gt 0 ]] && echo "reap-island-helpers: reaped $reaped orphaned backend watcher(s)" >&2
exit 0
