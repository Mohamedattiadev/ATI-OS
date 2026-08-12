#!/usr/bin/env bash
# ============================================================
#  focus-move — h/j/k/l focus, with the group case qtile had and
#  `movefocus` does not.
#
#  THE BUG THIS FIXES
#  ------------------
#  Reported as "Max and TreeTab switch, but I cannot get to the other app
#  under the current one". Exactly right, and it was never the layouts:
#  layout-cycle.sh builds both of them out of a Hyprland GROUP, and
#
#      **`movefocus` does not move between members of a group.**
#
#  It moves between TILES, and a group is one tile. So with three windows
#  grouped, all four direction keys had nothing to travel to and the two
#  windows behind the visible one were unreachable — which is the whole
#  point of Max and TreeTab. `changegroupactive` is the dispatcher that
#  walks the stack inside a tile, and nothing was calling it.
#
#  WHAT qtile ACTUALLY BOUND, which is why all four keys are here
#  --------------------------------------------------------------
#  config.py's mod+h and mod+l are `.when(layout=...)` pairs and mod+j /
#  mod+k are unconditional:
#
#      mod+h   layout.left()   monadtall … | layout.previous()  max, treetab
#      mod+l   layout.right()  monadtall … | layout.next()      max, treetab
#      mod+j   layout.down()   — in Max, down() IS "next window"
#      mod+k   layout.up()     — in Max, up() IS "previous window"
#
#  So in Max and TreeTab all FOUR keys cycle the stack: h and k go back,
#  l and j go forward. In MonadTall they are ordinary directional focus.
#  That is the behaviour reproduced below, one dispatcher each.
#
#  The layout is not consulted, and deliberately: what decides the
#  behaviour is whether the FOCUSED WINDOW is grouped, which is a fact
#  about the window and is true exactly when layout-cycle.sh has put the
#  workspace in Max or TreeTab. Reading the layout name instead would
#  answer the same question one indirection further away, and would be
#  wrong for a group made by hand with $mod G.
# ============================================================
set -euo pipefail

dir="${1:-}"

case "$dir" in
    h|j|k|l) ;;
    *) echo "usage: focus-move.sh h|j|k|l" >&2; exit 2 ;;
esac

active="$(hyprctl activewindow -j 2>/dev/null || echo '{}')"

# `.grouped` is the addresses of every window sharing this tile, INCLUDING
# the active one, and it is an empty array for an ungrouped window. The
# test is > 1 rather than > 0 because a one-member group is a group in name
# only: cycling it lands back on the window you started from, and the
# directional move is the more useful answer.
members="$(printf '%s' "$active" | jq -r '(.grouped // []) | length' 2>/dev/null || echo 0)"

if [ "${members:-0}" -gt 1 ]; then
    case "$dir" in
        h|k) exec hyprctl dispatch changegroupactive b ;;
        l|j) exec hyprctl dispatch changegroupactive f ;;
    esac
fi

case "$dir" in
    h) exec hyprctl dispatch movefocus l ;;
    j) exec hyprctl dispatch movefocus d ;;
    k) exec hyprctl dispatch movefocus u ;;
    l) exec hyprctl dispatch movefocus r ;;
esac
