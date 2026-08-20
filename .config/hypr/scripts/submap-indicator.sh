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
#  AND NOW THE KEYS, not just the name — `tide showModeKeys`, the island's
#  mode_keys state. See island_show_keys() for why the rows are read from
#  the compositor rather than from hint_for(), and why they are
#  percent-encoded on the way. The capsule remains the fallback.
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
# Scoped to the RUNNING instance, not fixed. Found live: a copy of this
# script from a Hyprland session that had already ended — a full day dead,
# HYPRLAND_INSTANCE_SIGNATURE pointed at a socket that no longer existed —
# was still holding the fixed lock file. It never noticed its own socket
# was gone (nothing makes it look until the next event tries to arrive, and
# none ever will), so it never exited, and this SESSION's own indicator,
# started fresh by autostart.conf, hit that lock, printed "another instance
# holds it" to a log nobody was watching, and exited. Every submap entered
# for the entire session went un-announced, on both bars, with no error
# visible anywhere short of `ps` and a signature mismatch. One fixed path
# for every Hyprland instance to ever run on this machine was the whole
# bug; keying it to THIS instance means a leftover from a dead one holds a
# lock file nothing new will ever contend for again.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/submap-indicator-${HYPRLAND_INSTANCE_SIGNATURE}.lock"

# Beside this script, and resolved through the symlink because ~/.config is
# stowed: $0 is the link, its target is the checkout, and cheatsheet.py is
# next to the real file rather than next to the link.
CHEATSHEET="$(dirname "$(readlink -f "$0")")/cheatsheet.py"

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
        # Kept in the SAME ORDER as the binds in submaps.conf, so the two can
        # be diffed by eye. This list had drifted: n, b, w and SHIFT+S were
        # all bound and none of them appeared here, which is worse than a
        # missing HUD — a key list that omits a third of the map teaches you
        # the map is wrong. j and SHIFT+K are the picker's, added with it.
        rofi) printf 'a anki · b bluetooth · c island theme · C theme · d docs · e translate\nf config · h hub · i screenshot · j workspaces · k kill · K close window\nl light · m man · n wifi · o note · p pass · q logout · r record\ns spell · S wifi qr · t todo · v pdf · w wallpaper · x notif\ny youtube · z shared · 1-9 workspace' ;;
        resize)      printf 'h j k l  resize · escape/q exit' ;;
        lang)        printf 'e english · a arabic · t turkish · d german' ;;
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
    qs -p "$ISLAND_DIR" ipc call tide clearModeKeys >/dev/null 2>&1
}

# ------------------------------------------------------------
#  The key list, which is the half the NAME never answered
# ------------------------------------------------------------
#  The capsule above answers "am I in a mode", and that was the missing
#  half when this script was written. It is not the question you have
#  while standing inside a 26-key chord, which is "and what are the keys".
#  qtile got away with the name alone because its chords were one-shot and
#  its cheatsheet was one keystroke away; Hyprland submaps are sticky, so
#  you sit in them, and the cheatsheet here is itself behind a chord.
#
#  The rows are READ FROM THE COMPOSITOR — `cheatsheet.py --submap-json`
#  over `hyprctl binds` — and not from the table below, for the same
#  reason the printed sheet reads itself: a hand-written key list is only
#  ever as true as the last person to edit it, and a wrong hint still
#  renders confidently. hint_for() stays as the dunst fallback's text,
#  where there is no island to ask.
#
#  ONLY THE MODE NAME CROSSES THE IPC, and the reason is the one thing
#  worth carrying away from building this: **Quickshell's IPC splits
#  arguments on whitespace, and shell quoting does not survive the split.**
#  A one-parameter call gets the remainder joined back up, which is why
#  `tide showText "hello world"` works and hides the problem completely; a
#  two-parameter call does not. Sending the rows as JSON therefore arrived
#  as 27 arguments instead of 2 ("wifi panel", "theme picker" — every space
#  is a new argument) and was rejected outright. Percent-encoding got past
#  the argument count and still produced an empty grid.
#
#  So the panel fetches its own rows, by running the very command below.
#  That is also the pattern every other panel in this shell already uses.
#  What is left here is the DECISION: ask first, and if this submap has no
#  readable keys, return non-zero so the caller falls back to the capsule
#  rather than drawing a title over an empty grid.
island_show_keys() {
    local map="$1"

    [ -x "$CHEATSHEET" ] || return 1

    # Failure here is not fatal and must not be: hyprctl can be slow or
    # absent mid-reload, and a mode with no readable keys is still worth
    # announcing by name. Returning non-zero drops us to island_show.
    "$CHEATSHEET" --submap-json "$map" 2>/dev/null | python3 -c '
import json, sys
try:
    sys.exit(0 if json.load(sys.stdin)["keys"] else 1)
except Exception:
    sys.exit(1)
' 2>/dev/null || return 1

    qs -p "$ISLAND_DIR" ipc call tide showModeKeys "$map" >/dev/null 2>&1
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

# ------------------------------------------------------------
#  Which bar the desktop is wearing
# ------------------------------------------------------------
#  Written by AtiScriptsV1/bar-switch and read by both sessions. Defaulting
#  to `island` matches bar-switch's own DEFAULT_MODE — a machine that has
#  never switched has always had the island.
#
#  Read PER EVENT rather than once at startup, for the same reason the
#  island is tried per event: bar-switch changes this file mid-session and
#  this script is not restarted when it does.
bar_mode() {
    local m=""
    [ -r "$HOME/.cache/bar-mode" ] && m="$(cat "$HOME/.cache/bar-mode" 2>/dev/null)"
    m="${m//[[:space:]]/}"
    case "$m" in native) echo native ;; *) echo island ;; esac
}

show() {
    local map="$1"
    local title="${map^^}-MODE"

    # Three backends, best first. The key panel needs the island AND a
    # submap the compositor has bindings for; the capsule needs only the
    # island; dunst needs neither. Each falls through to the next, which
    # is why the panel's failure is silent rather than loud.
    if island_show_keys "$map"; then
        notify_clear
        return
    fi

    if island_show "$title"; then
        # Belt and braces: if a previous event fell back to dunst (island
        # still starting, say), that toast is non-expiring and would sit
        # under the island forever. Clear it whenever the island takes over.
        notify_clear
        return
    fi

    # ------------------------------------------------------------
    #  NO TOAST WHEN THE TOPBAR IS UP
    # ------------------------------------------------------------
    #  Reported: "when i try to open a mode rofi, in qtile it was not
    #  showing notification — have the same behaviour".
    #
    #  It is the same bug as the one the reconnect note below describes,
    #  inverted. Both island calls above fail in native mode — and they
    #  fail LOUDLY enough to be missed: `qs ipc call` against a config with
    #  no running instance exits 255, so the fallback fires exactly when
    #  the topbar is the live bar. That is the one case where there is
    #  already an indicator on screen: the topbar draws chord_chip, with
    #  qtile's own CHORD_CHIP_LABELS in it, which is what qtile did instead
    #  of notifying.
    #
    #  So dunst stays the fallback for having NO bar at all — an island
    #  that is still starting, or one that has died — and stops being a
    #  second copy of a chip that is already showing the same words.
    if [ "$(bar_mode)" = native ]; then
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
# ------------------------------------------------------------
#  RECONNECT, because falling out of the loop used to be fatal
# ------------------------------------------------------------
#  This was a single read loop, on the assumption that the only way it
#  ends is Hyprland going away. That assumption was wrong, and the way it
#  was wrong is invisible:
#
#  Found live. The user reported "the mode popups do not appear at all,
#  but the mode itself works". Both are true and they have one cause —
#  Hyprland handles submap keys itself, so the chord keeps working while
#  the only thing that ANNOUNCES it is gone. There is nothing on screen to
#  suggest a process is missing rather than a feature being broken.
#
#  Measured at the time of the report: this script was not running, its
#  lock was free, and `workspace-layout.sh` — the other listener on this
#  same socket, started by the same autostart.conf — was also dead. The
#  two survivors in that file are `adhkar` and `battery-events`, and those
#  are precisely the two with a `sleep 40; pgrep -x ... || ...` re-check
#  behind them. So the pattern that dies is "connect to socket2 once".
#
#  The trigger was not recovered — nothing in the repo kills either script
#  (checked; the only `pkill -f` is rofi_shared's, on a feh title). What
#  is certain is the shape: if the reader ever returns, the process exits
#  and never comes back, and the desktop quietly loses a feature.
#
#  So a read that ends is now a reconnect, not an exit. Hyprland going
#  away is still an exit, and it is detected by the SOCKET FILE being gone
#  rather than by the read ending — that is the distinction the original
#  loop collapsed.
RECONNECTS=0
while [ -S "$SOCKET" ]; do
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

    exec 8<&-
    [ -n "${READER_PID:-}" ] && kill "$READER_PID" 2>/dev/null || true

    # Hyprland really is gone: stop, and let the EXIT trap clean up.
    [ -S "$SOCKET" ] || break

    # Whatever was on screen describes a submap we can no longer track.
    clear_it

    # Backoff, so a socket that accepts and immediately closes cannot spin
    # this into a hot loop. Capped rather than unbounded: the point is to
    # keep trying for the life of the session, not to give up politely.
    RECONNECTS=$((RECONNECTS + 1))
    if [ "$RECONNECTS" -le 5 ]; then
        sleep 1
    else
        sleep 5
    fi
    echo "submap-indicator: event socket read ended, reconnecting" \
         "(attempt $RECONNECTS)" >&2
done

# The socket file is gone — Hyprland went away. cleanup runs via the EXIT
# trap.
