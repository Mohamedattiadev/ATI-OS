#!/usr/bin/env bash
# ============================================================
#  workspace-layout — qtile's per-Group layout, on a compositor that
#  has no such concept.
#
#  Every Group in ../qtile/config.py declares its own layout, and the
#  layout follows the group: arriving on group 2 puts you in Max whether
#  you got there by keybind, by clicking the bar, or by an app opening
#  there. The table itself lives in layout-cycle.sh's header, next to the
#  code that acts on it.
#
#  ---- WHY THIS IS A DAEMON AND NOT A WORKSPACE RULE ----
#
#  Because Hyprland has no per-workspace layout to set. Measured against
#  the running 0.56.2 rather than read off a wiki page:
#
#      hyprctl keyword workspace "7, layout:master"   -> ok
#      hyprctl configerrors                           -> empty
#
#  and nothing happens. A workspace rule accepts unknown keys and discards
#  them, so the syntax that looks like it should work is silently inert —
#  the same failure shape as the percentage `size` rules documented in
#  MIGRATION.md, and just as invisible. The keys the binary actually
#  enumerates are monitor, default, defaultName, gapsin, gapsout, border,
#  bordersize, rounding, decorate, shadow, persistent, on-created-empty.
#  There is a `layoutopt:` prefix, and it carries orientation for master
#  and dwindle, not a layout name.
#
#  ---- WHY NOT JUST WRAP THE KEYBIND ----
#
#  The obvious alternative is to change `bind = $mod, 2, workspace, 2` into
#  a script that switches and then applies. That covers the keys and
#  nothing else. Workspaces here are also reached by:
#
#      * toggle-app.sh   ($mod B/N/M/V, $mod SHIFT T/O, $alt SHIFT A)
#      * rules.conf      (an app opening on its home workspace)
#      * the island      (clicking a workspace, scrolling the notch)
#      * dispatchers run by hand
#
#  qtile's layout followed the group down every one of those routes,
#  because it was a property OF the group. Watching the event socket is the
#  only place with the same reach — and it keeps the binds as plain
#  dispatchers, which is worth something on its own: a keybind that shells
#  out has a startup cost on the hottest keys in the config.
#
#  ---- WHICH EVENTS, AND WHY openwindow IS ONE OF THEM ----
#
#      workspacev2      you switched workspace
#      focusedmonv2     you switched MONITOR, which changes the active
#                       workspace without a workspacev2 event
#      openwindow       a window appeared
#
#  The last one is what makes "workspace 2 is Max" true rather than
#  aspirational. Without it, a Max workspace stops being Max the moment a
#  new window opens on it: Hyprland tiles the newcomer beside the group
#  instead of into it, and you are looking at a split screen on a workspace
#  whose whole point is that you are not. qtile had no equivalent problem —
#  Max is a layout, so it owned every window the group ever received.
#
#  This is safe to run on every one of those because `layout-cycle.sh
#  apply` is a no-op when the workspace already matches: both the grouping
#  and the ungrouping paths are guarded by a `grouped_count` check, so the
#  common case costs one `hyprctl clients -j` and two keywords.
#
#  Structure — the flock, the process substitution instead of a pipeline,
#  and the python socket reader — is lifted from submap-indicator.sh, which
#  documents why each is that way. The one that bites: a `reader | while
#  read` pipeline is a single foreground command that never returns, so
#  bash defers every trap until after it, and SIGTERM leaves the process
#  alive.
# ============================================================
set -euo pipefail

SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/workspace-layout.lock"

# Beside this script, resolved through the symlink: ~/.config is stowed, so
# $0 is the link and layout-cycle.sh is next to the real file.
CYCLE="$(dirname "$(readlink -f "$0")")/layout-cycle.sh"

# Two instances would both answer every event and both walk the workspace
# with focuswindow, interleaved — which is how you get focus landing
# somewhere neither of them chose. Non-blocking: if one is already running
# this one is redundant.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "workspace-layout: another instance holds $LOCK_FILE — exiting" >&2
    exit 0
fi

[ -x "$CYCLE" ] || { echo "workspace-layout: $CYCLE not executable" >&2; exit 1; }
[ -S "$SOCKET" ] || { echo "no event socket: $SOCKET" >&2; exit 1; }

# ------------------------------------------------------------
#  Serialised by construction, which is why there is no second lock here
# ------------------------------------------------------------
#  Concurrency would be a real problem: two overlapping layout-cycle runs
#  would both read `grouped_count`, both decide the group needs seeding,
#  and `togglegroup` being a toggle (see layout-cycle.sh) means the second
#  DISBANDS what the first built.
#
#  It cannot happen. The loop below calls this synchronously and nothing is
#  backgrounded, so a burst — switching to a workspace an app is opening on
#  fires workspacev2 and openwindow milliseconds apart — simply queues in
#  the socket's own buffer and is handled one line at a time. The trailing
#  run is a no-op by the guards in layout-cycle.sh.
#
#  Errors are swallowed on purpose. `hyprctl` can fail mid-reload, and a
#  layout that did not get applied is a cosmetic miss; a daemon that exits
#  because of one is a silent loss of the feature for the whole session.
apply() {
    "$CYCLE" apply >/dev/null 2>&1 || true
}

cleanup() {
    trap - EXIT TERM INT HUP
    [ -n "${READER_PID:-}" ] && kill "$READER_PID" 2>/dev/null
    exit 0
}
trap cleanup EXIT TERM INT HUP

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

# Apply once at startup so the workspace you log in on gets its layout
# without waiting for you to leave it and come back.
apply

# ------------------------------------------------------------
#  RECONNECT — the same fix as submap-indicator.sh, for the same reason
# ------------------------------------------------------------
#  Both scripts listen on socket2 and both were written to read it once.
#  Both were found dead mid-session while the two autostart entries with a
#  `pgrep -x ... ||` re-check behind them were still up. This one fails
#  even more quietly than the indicator does: there is no popup to notice
#  the absence of, the workspace simply stops getting its layout and looks
#  like a layout bug.
#
#  A read that ends is a reconnect. Hyprland going away is the socket FILE
#  disappearing, which is a different condition and the only one that
#  exits. Full reasoning in submap-indicator.sh.
RECONNECTS=0
while [ -S "$SOCKET" ]; do
    exec 7< <(read_events)
    READER_PID=$!

    while IFS= read -r line <&7; do
        case "$line" in
            workspacev2\>\>*|focusedmonv2\>\>*|openwindow\>\>*) apply ;;
        esac
    done

    exec 7<&-
    [ -n "${READER_PID:-}" ] && kill "$READER_PID" 2>/dev/null || true

    [ -S "$SOCKET" ] || break

    RECONNECTS=$((RECONNECTS + 1))
    if [ "$RECONNECTS" -le 5 ]; then
        sleep 1
    else
        sleep 5
    fi
    echo "workspace-layout: event socket read ended, reconnecting" \
         "(attempt $RECONNECTS)" >&2

    # Re-apply on the way back in: events were missed while disconnected,
    # so the current workspace's layout may be whatever the last one set.
    apply
done
