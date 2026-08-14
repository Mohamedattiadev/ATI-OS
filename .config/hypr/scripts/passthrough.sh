#!/usr/bin/env bash
# passthrough.sh enter|exit
#
# The two halves of qtile's passthrough that Hyprland's submap did not have.
#
# WHAT qtile ACTUALLY DOES  (config.py:669 _enable_passthrough)
# -------------------------------------------------------------
# Entering passthrough is three things, not one:
#
#   1. it sets `passthrough_active`
#   2. it SAVES BAR_MODE, forces the bar to "bottom", and re-applies it
#   3. it notifies "PASSTHROUGH MODE"
#
# and leaving is the mirror: restore the saved BAR_MODE, re-apply, notify
# "NORMAL MODE". Hyprland's side was `submap = passthrough` with one exit key
# and nothing else, so the mode was invisible — the one mode where you most
# need to know you are in it, because every key you press is going somewhere
# else.
#
# WHY THE BAR MOVES AT ALL, which is not obvious
# ----------------------------------------------
# qtile's two bars are the same two this desktop has: a chip bar at the top
# and a plain one at the bottom. Passthrough forces the BOTTOM one, and the
# reason is that passthrough is for a VM or a remote session that wants the
# whole keyboard — those run full-screen, and the bar that overlaps least with
# a full-screen client is the one that is not where its own titlebar is.
# Whether or not that reasoning still holds, reproducing it is the point: the
# same key in the same desktop should do the same thing.
#
# The saved value is a FILE and not a variable, because the two halves of this
# are two separate invocations from two different submaps.
#
# UNDER THE ISLAND there is no topbar process to move, and `qs ipc call`
# against a config with no instance exits 255 — so the switch is skipped and
# only the notification happens. That is the correct behaviour rather than a
# gap: the island has one form, so there is no second one to move to.

set -euo pipefail

TOPBAR_DIR="$HOME/.config/quickshell/topbar"
STATE_DIR="$HOME/.cache/hypr"
STATE_FILE="$STATE_DIR/passthrough-prev-bar"

topbar_ipc() {
    # `|| true` on every call: the topbar is not running under the island, and
    # a passthrough that fails to toggle is far better than one that refuses
    # to start because a bar it does not need is absent.
    qs -p "$TOPBAR_DIR" ipc call topbar "$@" 2>/dev/null || true
}

case "${1:-}" in
enter)
    mkdir -p "$STATE_DIR"
    # `status` returns top|bottom, or nothing at all when no topbar is up.
    prev="$(topbar_ipc status | tr -d '[:space:]')"
    printf '%s' "$prev" > "$STATE_FILE"
    [[ -n "$prev" ]] && topbar_ipc bottom
    notify-send "PASSTHROUGH MODE" 2>/dev/null || true
    ;;
exit)
    prev=""
    [[ -r "$STATE_FILE" ]] && prev="$(<"$STATE_FILE")"
    prev="${prev//[[:space:]]/}"
    # Only `top` is restored explicitly. If it was already bottom, or if
    # nothing was recorded because no bar was up, there is nothing to undo —
    # and re-asserting `bottom` would fight a $mod SHIFT Z the user pressed
    # while inside passthrough.
    case "$prev" in
        top) topbar_ipc top ;;
    esac
    rm -f "$STATE_FILE"
    notify-send "NORMAL MODE" 2>/dev/null || true
    ;;
*)
    echo "usage: passthrough.sh enter|exit" >&2
    exit 2
    ;;
esac
