#!/usr/bin/env bash
# startup-notifications.sh [seconds]   TEST TOOL, not a feature.
#
# Records every org.freedesktop.Notifications.Notify call on the session bus
# for `seconds` (default 180) and writes one line per notification:
#
#     +012.4s  app=[nm-applet]  summary=[Connection Established]  body=[...]
#
# to ~/.cache/hypr/startup-notifications.log, then exits.
#
# WHY THIS EXISTS
# ---------------
# Reported: "when i start the hyperland a lot of notifications appear, like
# 2-3 ones". Exactly the shape of bug this tree's RULES say cannot be answered
# by reading — it happens once, at login, before anything is watching, and by
# the time you can ask a question the evidence is gone.
#
# One cause WAS found by reading and is fixed: ati-adhkar notified before its
# first sleep, so a remembrance card went out the moment autostart launched
# it. The others could not be, and the guesses were all wrong when measured:
#
#   nm-applet     restarted under a live bus monitor, silent — and
#                 `disable-connected-notifications` is already true, so it
#                 does not announce the login association either
#   blueman-applet  silent on restart
#   kdeconnectd     silent on restart
#   battery-events  initialises LAST_AC before its loop, so the first
#                   upower event cannot read as a plug/unplug
#   qupdate --daemon  no notification on any startup path
#
# The restart test is the weak one and it is worth saying why: restarting a
# tray applet when the state it reports has ALREADY settled is not the same
# as starting it while the state is still arriving. Only a real login is.
#
# HOW TO USE IT
# -------------
# Add to autostart.conf for one session:
#
#     exec-once = ~/.config/hypr/scripts/test/startup-notifications.sh 180
#
# log out, log in, and read the log. Then take the line out again — this is a
# dbus-monitor sitting on the session bus, which is not something to leave
# running.
#
# It is DELIBERATELY not left in autostart behind a flag file. A recorder that
# is usually off but might be on is a second thing to reason about when a
# notification goes missing, and this is a five-second edit to enable.
set -uo pipefail

DURATION="${1:-180}"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
LOG="$LOG_DIR/startup-notifications.log"

command -v dbus-monitor >/dev/null 2>&1 || {
    echo "startup-notifications.sh: dbus-monitor is not installed" >&2
    exit 1
}

mkdir -p "$LOG_DIR"
{
    echo "# session started $(date -Is), recording ${DURATION}s"
} > "$LOG"

# `--session` and a match rule narrow enough that the awk below never sees
# anything else on the bus. Notify's argument order is fixed by the spec:
# app_name, replaces_id, app_icon, summary, body — so the 1st, 3rd and 4th
# STRINGS are what this wants, and counting them is more robust than trying
# to match on content that may be empty (a retraction sends two empty ones).
timeout "$DURATION" dbus-monitor --session \
    "interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null \
| awk -v t0="$(date +%s.%N)" '
    /member=Notify/ { inside = 1; n = 0; app = ""; sum = ""; body = ""; next }
    inside && /^ *string / {
        line = $0
        sub(/^ *string "/, "", line)
        sub(/"$/, "", line)
        n++
        if (n == 1) app = line
        else if (n == 3) sum = line
        else if (n == 4) {
            body = line
            cmd = "date +%s.%N"; cmd | getline now; close(cmd)
            printf "+%06.1fs  app=[%s]  summary=[%s]  body=[%s]\n",
                   now - t0, app, sum, substr(body, 1, 80)
            fflush()
            inside = 0
        }
    }
' >> "$LOG"

echo "# recording finished $(date -Is)" >> "$LOG"
