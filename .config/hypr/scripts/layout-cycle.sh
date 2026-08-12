#!/usr/bin/env bash
# ============================================================
#  Layout cycle — qtile's three layouts, on qtile's key ($mod Tab),
#  and qtile's PER-GROUP default layout, applied per workspace.
#
#  ../qtile/config.py's `layouts` list has exactly three entries, and
#  $mod Tab was lazy.next_layout() over them:
#
#      layout.MonadTall(ratio=0.75, min_ratio=0.6, max_ratio=0.85)
#      layout.Max(border_width=0, margin=0)
#      layout.TreeTab(panel_width=180, sections=[...])
#
#  What was here before was a one-line `$mod Tab` that flipped Hyprland's
#  general:layout between master and dwindle. That is two layouts, neither
#  of which is Max, and it silently dropped the two that this config
#  actually spends most of its time in.
#
#  ---- THE MAPPING, AND WHY ----
#
#  | qtile     | here                     | why |
#  |-----------|--------------------------|-----|
#  | MonadTall | master, mfact 0.75       | one master pane plus a stack IS MonadTall, and 0.75 is qtile's own ratio |
#  | Max       | a group, groupbar OFF    | one window visible at full size, the rest stacked behind it |
#  | TreeTab   | a group, groupbar ON     | the same stack, with the window list drawn — which is the only thing TreeTab adds to Max |
#
#  Hyprland has no Max layout and no tabbed layout. It has GROUPS, and a
#  group is precisely "several windows in one tile, one visible at a
#  time" — so Max and TreeTab are one mechanism with the tab bar hidden or
#  shown. Treating them as two different layouts would have needed a
#  plugin; treating them as one layout with a toggle needs neither.
#
#  ---- PER-WORKSPACE, WHICH IS THE HALF THAT WAS MISSING ----
#
#  Every qtile Group declares its own layout, and the port had none of it —
#  the layout was one global piece of state that whatever you last pressed
#  $mod Tab on decided for the whole session. Transcribed from
#  `groups = [...]` (config.py :6851-6960):
#
#      1 monadtall   4 monadtall   7 monadtall   S max
#      2 max         5 max         8 max         9 monadtall*
#      3 monadtall   6 monadtall
#
#      * Group("9") declares no layout at all, so qtile falls back to
#        layouts[0], which is the MonadTall above. Not a guess — the list
#        starts with ten commented-out layouts and MonadTall is the first
#        live entry.
#
#  Note 2, 5 and 8 are Max, not monadtall: browsers/readers, brave, and
#  documents. qtile says why for 8 in as many words — "a document is one
#  thing you read at a time, and monadtall's side column would hand half
#  the width to whatever else happened to be open".
#
#  **Hyprland has no per-workspace layout and cannot be given one.** The
#  workspace-rule parser was checked directly: `workspace = 7, layout:master`
#  returns `ok` and leaves `hyprctl configerrors` empty, because unknown
#  keys in a workspace rule are accepted and DISCARDED — it is not a
#  feature that exists. The keys the binary actually enumerates are
#  monitor, default, defaultName, gapsin, gapsout, border, bordersize,
#  rounding, decorate, shadow, persistent and on-created-empty. So the
#  per-workspace part has to be driven from outside, which is what
#  `workspace-layout.sh` does: it watches the event socket and calls this
#  script with `apply` on every workspace change.
#
#  ---- WHAT THIS DELIBERATELY DOES NOT DO ----
#
#  It does not touch windows on any workspace but the current one, and it
#  never moves a window between workspaces. Grouping is per-workspace in
#  qtile too.
#
#  Usage:  layout-cycle.sh [next|monadtall|max|treetab|apply]
#          apply = "restore this workspace's remembered layout, quietly"
# ============================================================
set -euo pipefail

# A DIRECTORY now, one file per workspace. The old version kept a single
# file at $XDG_RUNTIME_DIR/hypr-layout; if that is still lying around from
# a pre-upgrade session it would make mkdir fail, so it is cleared.
state_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr-layouts"
[ -f "${XDG_RUNTIME_DIR:-/tmp}/hypr-layout" ] && rm -f "${XDG_RUNTIME_DIR:-/tmp}/hypr-layout"
mkdir -p "$state_dir"

order=(monadtall max treetab)

# qtile's per-Group layout. Anything not listed falls through to the same
# default qtile uses for a Group that declares none: layouts[0], MonadTall.
default_for() {
    case "$1" in
        2|5|8|S) echo max ;;
        *)       echo monadtall ;;
    esac
}

ws=$(hyprctl activeworkspace -j | jq -r '.name')

# Special workspaces are scratchpads: one floating window, placed by
# scratchpad.sh, and grouping or re-tiling them is meaningless. qtile's
# ScratchPad group had no layout either.
case "$ws" in special:*) exit 0 ;; esac

state_file="$state_dir/$(printf '%s' "$ws" | tr -c '[:alnum:]' '_')"
current=$(cat "$state_file" 2>/dev/null || default_for "$ws")

want="${1:-next}"
quiet=0

case "$want" in
    apply) want="$current"; quiet=1 ;;
    next)
        idx=0
        for i in "${!order[@]}"; do
            [ "${order[$i]}" = "$current" ] && idx=$(( (i + 1) % ${#order[@]} ))
        done
        want="${order[$idx]}"
        ;;
esac

wsid=$(hyprctl activeworkspace -j | jq -r '.id')

# Addresses on this workspace, in layout order. `hyprctl clients` is not
# sorted, and grouping walks the list, so a stable order keeps the result
# reproducible rather than depending on focus history.
mapfile -t addrs < <(
    hyprctl clients -j | jq -r --argjson ws "$wsid" '
        [ .[] | select(.workspace.id == $ws) | select(.floating | not) ]
        | sort_by(.at[0], .at[1]) | .[].address'
)

# Every path below walks the workspace with `focuswindow`, which is a real
# focus change. That was tolerable when this only ran on a keypress; it is
# not now that it runs on every workspace switch, where a wandering focus
# reads as the compositor losing your place. Whatever was focused when we
# started is put back at the end.
restore_focus=$(hyprctl activewindow -j | jq -r '.address // empty')
put_focus_back() {
    [ -n "$restore_focus" ] || return 0
    hyprctl clients -j | jq -e --arg a "$restore_focus" 'any(.address == $a)' >/dev/null \
        && hyprctl dispatch focuswindow "address:$restore_focus" >/dev/null || true
}

grouped_count() {
    hyprctl clients -j | jq -r --argjson ws "$wsid" '
        [ .[] | select(.workspace.id == $ws) | select(.floating | not)
              | select((.grouped | length) > 0) ] | length'
}

ungroup_all() {
    # GUARDED, because `apply` runs on every workspace switch. Without this
    # the monadtall path did a focuswindow + moveoutofgroup for every window
    # on the workspace each time you arrived on it, which is a burst of
    # focus changes to achieve nothing.
    [ "$(grouped_count)" -eq 0 ] && return 0
    for a in "${addrs[@]}"; do
        # Only a grouped window answers to this; on an ungrouped one the
        # dispatcher is a no-op, so there is nothing to guard.
        hyprctl dispatch focuswindow "address:$a" >/dev/null
        hyprctl dispatch moveoutofgroup >/dev/null 2>&1 || true
    done
}

group_all() {
    [ "${#addrs[@]}" -lt 2 ] && return 0

    # IDEMPOTENT ON PURPOSE. `togglegroup` is a toggle, so calling this a
    # second time — which is exactly what Max -> TreeTab does, since both
    # want the same group — DISBANDED the group instead of keeping it, and
    # the tab bar appeared over three ordinary tiled windows. Measured:
    # max gave grouped=3, and treetab straight after gave grouped=0.
    #
    # So seed the group only if there is not one already. This guard is also
    # what makes `apply` cheap enough to run on every workspace switch.
    if [ "$(grouped_count)" -lt "${#addrs[@]}" ]; then
        hyprctl dispatch focuswindow "address:${addrs[0]}" >/dev/null
        if [ "$(grouped_count)" -eq 0 ]; then
            hyprctl dispatch togglegroup >/dev/null
        fi
        # `moveintogroup` takes a DIRECTION, not an address, so the group
        # has to be the neighbour being moved towards — which is why the
        # list is sorted by position and walked in that order.
        for a in "${addrs[@]:1}"; do
            hyprctl dispatch focuswindow "address:$a" >/dev/null
            for dir in l u r d; do
                if hyprctl dispatch moveintogroup "$dir" 2>/dev/null | grep -q '^ok'; then
                    break
                fi
            done
        done
    fi
}

case "$want" in
    monadtall)
        ungroup_all
        hyprctl --batch "keyword general:layout master ; keyword master:mfact 0.75" >/dev/null
        # The keyword sets the DEFAULT for new arrangements; it does not
        # re-split windows that are already laid out, so on its own the
        # master pane kept whatever ratio it had (measured: 735 px of 1346,
        # i.e. 0.55, with master:mfact reading back a correct 0.75). The
        # layoutmsg is what acts on the live workspace.
        hyprctl dispatch layoutmsg mfact exact 0.75 >/dev/null 2>&1 || true
        label="MonadTall"
        ;;
    max)
        hyprctl keyword group:groupbar:enabled false >/dev/null
        group_all
        label="Max"
        ;;
    treetab)
        hyprctl keyword group:groupbar:enabled true >/dev/null
        group_all
        label="TreeTab"
        ;;
    *)
        echo "unknown layout: $want" >&2
        exit 1
        ;;
esac

put_focus_back
printf '%s' "$want" > "$state_file"

[ "$quiet" = 1 ] && exit 0

# qtile's bar had a CurrentLayout widget, so switching layouts always said
# what you switched to. The island has no such widget; the mode-indicator
# IPC is the same idea and already exists.
#
# Not on the `apply` path: that fires on every workspace switch, and a
# capsule flashing "Max" every time you press $mod 2 is noise, not
# information. qtile's widget did not blink either — it just read the
# current layout.
qsi="qs -p $HOME/.config/quickshell/tide-island-fork ipc call"
$qsi tide showText "$label" >/dev/null 2>&1 || true
(sleep 1.2; $qsi tide clearText >/dev/null 2>&1 || true) &
