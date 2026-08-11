#!/usr/bin/env bash
# ============================================================
#  submap-indicator — show which chord you are in.
#
#  qtile's KeyChord set a mode name in the bar, so entering a chord was
#  visible and leaving it was obvious. Hyprland submaps have no such
#  feedback: the compositor silently starts swallowing keys, and the only
#  way to know is to press something and see what happens. That is the
#  "which mode am I in" problem.
#
#  Hyprland announces every change on its event socket, so no polling:
#      submap>>rofi        entering
#      submap>>            leaving (empty payload == back to default)
#
#  Feedback goes through dunst, which is already running and already
#  themed by theme-apply, so this inherits the current palette for free.
#
#  WHY NOT IN THE ISLAND: Tide Island's IPC (`qs -p /usr/share/tide-island
#  ipc show`) exposes showCustom(), but it takes no arguments — the
#  content comes from the shell's own custom-info source, not from the
#  caller. Pushing arbitrary text into the island therefore needs a fork
#  of its QML, which is tracked in REQUIREMENTS.md item 1 along with the
#  notch morph. This is the honest interim: correct, immediate, and
#  removable in one line once the fork exists.
# ============================================================
set -euo pipefail

SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
NOTIFY_ID=99101   # fixed id so each mode REPLACES the last, never stacks

# The keys each chord actually offers, so the hint is useful rather than
# just naming the mode. Kept in step with submaps.conf by hand; if a key
# is added there and not here the hint is stale, not wrong.
hint_for() {
    case "$1" in
        rofi) printf 'a anki · c theme · d docs · e translate · f config · h hub\ni satty · k kill · l light · m man · o note · p pass · q logout\nr record · s spell · t todo · v pdf · x notif · y youtube · z shared\n1-9 workspace' ;;
        resize)      printf 'h j k l  resize · escape/q exit' ;;
        lang)        printf 'e english · a arabic · t turkish · d german' ;;
        draw)        printf 'gromit-mpx drawing · escape/q exit' ;;
        passthrough) printf 'ALL keys go to the app · $alt F12 to exit' ;;
        *)           printf 'escape or q to exit' ;;
    esac
}

command -v dunstify >/dev/null 2>&1 && NOTIFY=dunstify || NOTIFY=notify-send

show() {
    local map="$1"
    if [ "$NOTIFY" = dunstify ]; then
        dunstify -r "$NOTIFY_ID" -u low -t 0 \
            "  ${map^^}-MODE" "$(hint_for "$map")" || true
    else
        notify-send -u low -t 0 "  ${map^^}-MODE" "$(hint_for "$map")" || true
    fi
}

clear_it() {
    if [ "$NOTIFY" = dunstify ]; then
        dunstify -C "$NOTIFY_ID" 2>/dev/null || true
    fi
}

[ -S "$SOCKET" ] || { echo "no event socket: $SOCKET" >&2; exit 1; }

# -t 0 above means the notification never times out, so it stays for as
# long as the chord is held open and disappears the instant it closes —
# which is the property that makes it a mode INDICATOR and not a toast.
#
# The socket is read with python3 rather than socat: socat is not
# installed, and adding a package to this desktop's declared set for one
# `read` on a unix socket is a poor trade when python3 is already a hard
# dependency of half the scripts here. Line-buffered so events surface
# immediately instead of when a pipe block fills.
read_events() {
    python3 -u -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
buf = b""
while True:
    chunk = s.recv(4096)
    if not chunk:
        break
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        print(line.decode("utf-8", "replace"), flush=True)
' "$SOCKET"
}

read_events | while read -r line; do
    case "$line" in
        submap\>\>*)
            map="${line#submap>>}"
            if [ -z "$map" ] || [ "$map" = "default" ]; then
                clear_it
            else
                show "$map"
            fi
            ;;
    esac
done
