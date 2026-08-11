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
#  NOW NATIVE TO THE ISLAND. The previous revision said arbitrary text in
#  the island "needs a fork of its QML, tracked in REQUIREMENTS.md item 1".
#  That fork now exists, and with it a `tide showText` IPC that takes a
#  string and holds it until `tide clearText` — which is exactly the
#  never-expiring, replace-in-place behaviour this needs. So the mode name
#  goes where qtile put it: in the bar.
#
#  dunst remains as a fallback, not as a preference — see NOTIFY_FALLBACK.
# ============================================================
set -euo pipefail

SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

# Fixed id so each mode REPLACES the last and never stacks. It is also
# what makes the startup and exit clears below possible: without a known
# id there is nothing to address.
NOTIFY_ID=99101

ISLAND_DIR="${TIDE_ISLAND_FORK_DIR:-$HOME/.config/quickshell/tide-island-fork}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/submap-indicator.lock"

# ------------------------------------------------------------
#  Only one of us
# ------------------------------------------------------------
#  Two instances is not a cosmetic problem. Both would answer every
#  submap event, and on the way out both would clear — but the second
#  clear can land after the first has already re-shown a new mode, so
#  entering a chord would silently blank its own indicator. It also makes
#  the stale-indicator bug below unfixable in principle: whichever
#  instance you kill, the other one still owns the display.
#
#  Non-blocking: if an indicator is already running, this one is
#  redundant, so it leaves rather than queueing up behind it.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "submap-indicator: another instance holds $LOCK_FILE — exiting" >&2
    exit 0
fi

# The keys each chord actually offers. Only the dunst fallback shows
# these: the island's capsule is one short line, and eliding a
# four-line key list into 220 px produces something worse than nothing.
# The mode NAME is the thing that was actually missing — knowing that the
# compositor is swallowing your keys, and which map is doing it.
hint_for() {
    case "$1" in
        rofi) printf 'a anki · c theme · C island theme · d docs · e translate · f config · h hub\ni satty · k kill · l light · m man · o note · p pass · q logout\nr record · s spell · t todo · v pdf · x notif · y youtube · z shared\n1-9 workspace' ;;
        resize)      printf 'h j k l  resize · escape/q exit' ;;
        lang)        printf 'e english · a arabic · t turkish · d german' ;;
        draw)        printf 'gromit-mpx drawing · escape/q exit' ;;
        passthrough) printf 'ALL keys go to the app · $alt F12 to exit' ;;
        *)           printf 'escape or q to exit' ;;
    esac
}

command -v dunstify >/dev/null 2>&1 && NOTIFY=dunstify || NOTIFY=notify-send

# ------------------------------------------------------------
#  Display backends
# ------------------------------------------------------------
#  The island is tried per-event, not probed once at startup. This script
#  is launched from autostart.conf alongside the island, so at the moment
#  it starts the island may not have finished loading — deciding the
#  backend then would pin us to dunst for the whole session over a race
#  measured in milliseconds.
island_show() {
    qs -p "$ISLAND_DIR" ipc call tide showText "$1" >/dev/null 2>&1
}

island_clear() {
    qs -p "$ISLAND_DIR" ipc call tide clearText >/dev/null 2>&1
}

notify_show() {
    if [ "$NOTIFY" = dunstify ]; then
        dunstify -r "$NOTIFY_ID" -u low -t 0 "  $1" "$2" || true
    else
        notify-send -u low -t 0 "  $1" "$2" || true
    fi
}

# Addressed by id, so it clears OUR notification and nothing else. Only
# dunstify can do this; notify-send has no close-by-id, which is why the
# fallback-to-the-fallback leaves a toast behind and says so here rather
# than pretending otherwise.
notify_clear() {
    [ "$NOTIFY" = dunstify ] && dunstify -C "$NOTIFY_ID" 2>/dev/null || true
}

show() {
    local map="$1"
    local title="${map^^}-MODE"

    if island_show "$title"; then
        # Belt and braces: if a previous event fell back to dunst (island
        # still starting, say), that toast is non-expiring and would sit
        # under the island forever. Clear it whenever the island takes over.
        notify_clear
        return
    fi

    notify_show "$title" "$(hint_for "$map")"
}

clear_it() {
    island_clear || true
    notify_clear
}

[ -S "$SOCKET" ] || { echo "no event socket: $SOCKET" >&2; exit 1; }

# ------------------------------------------------------------
#  Clear once at startup, and again on the way out
# ------------------------------------------------------------
#  THE BUG THIS FIXES, which was hit live:
#
#  -t 0 means the notification never expires. That is the whole point for
#  a mode indicator — it is not a toast, it should last exactly as long as
#  the mode does. But "never expires" also means nothing else will ever
#  remove it, so the ONLY thing that clears it is this script seeing the
#  matching `submap>>` leave event.
#
#  Every way of not seeing that event leaves a lie on screen:
#
#    * the script is killed while a chord is open
#    * it is restarted (hyprctl reload, a fresh login into a session that
#      still has the old notification) and starts up with no memory
#    * the socket read drops an event
#
#  and the result is a permanent "ROFI-MODE" hovering over a desktop that
#  is not in any submap at all — telling you your keys are being swallowed
#  when they are not, which is worse than no indicator, because you
#  believe it.
#
#  Two halves to the fix. The clear below runs BEFORE the event loop, so a
#  fresh instance always starts from a known-clean display regardless of
#  how the last one died. The trap runs on the way out, so this instance
#  never becomes the thing that leaves the mess.
#
#  EXIT alone is not enough: bash runs the EXIT trap for a normal return
#  and for a signal it has a handler for, but an untrapped SIGTERM or
#  SIGINT terminates the shell without running it. TERM and INT are named
#  explicitly so that `pkill`, a logout, and Ctrl-C all clean up. HUP is
#  in the list for the session-teardown case, where the terminal or the
#  compositor goes away underneath us.
clear_it

cleanup() {
    # Disarm first. Without this the explicit `exit` below re-enters
    # through the EXIT trap and clears twice, which is harmless today but
    # only because clear_it happens to be idempotent.
    trap - EXIT TERM INT HUP

    # The event reader is a child; killing it here means the process
    # substitution does not outlive us reading a socket nobody listens to.
    [ -n "${READER_PID:-}" ] && kill "$READER_PID" 2>/dev/null
    clear_it
    exit 0
}

trap cleanup EXIT TERM INT HUP

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

# ------------------------------------------------------------
#  The event loop, and why it is NOT a pipeline
# ------------------------------------------------------------
#  This was `read_events | while read -r line; do ... done`, and the trap
#  above did not work with it. Verified, not assumed: sending SIGTERM left
#  the process alive and the indicator on screen.
#
#  Bash does not run a trap handler in the middle of a foreground command
#  — it defers until that command returns. A pipeline is one foreground
#  command that never returns, so the handler was queued forever. Worse,
#  SIGTERM to the script does not reach the pipeline's children, so
#  nothing ended and the mode name stayed up: the exact stale-indicator
#  bug the trap was added to fix, reintroduced by the shape of the loop.
#
#  Reading from a process substitution instead puts the `read` builtin in
#  the main shell as the foreground command, and `read` IS interruptible —
#  a trapped signal makes it return so the handler runs immediately. It
#  also means the loop body executes in this shell rather than in a
#  subshell, so anything it sets survives the iteration.
exec 8< <(read_events)
READER_PID=$!

while IFS= read -r line <&8; do
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

# Falling out of the loop means the socket closed — Hyprland went away.
# cleanup runs via the EXIT trap.
