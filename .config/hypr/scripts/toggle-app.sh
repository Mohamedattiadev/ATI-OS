#!/usr/bin/env bash
# ============================================================
#  toggle-app — the Hyprland replacement for scripts/toggle_apps.py
#
#  The qtile original imported libqtile directly and walked qtile's own
#  client list, so none of it survived the move.  This is the same
#  behaviour expressed against hyprctl:
#
#    not running        -> spawn it
#    running, unfocused -> focus it (and follow it to its workspace)
#    running, focused   -> send it to the special:stash workspace
#
#  That last step is what made the qtile version feel like a toggle
#  rather than a launcher: pressing the key again gets the window out of
#  your way.  Hyprland has no "minimise", so a special workspace is the
#  honest equivalent — the window keeps running, it just stops being on
#  screen, and the next press pulls it back.
#
#  Usage:  toggle-app.sh <class-regex> <command...>
# ============================================================
set -euo pipefail

class="${1:?usage: toggle-app.sh <class-regex> <command...>}"
shift
cmd="$*"

clients=$(hyprctl clients -j)

# Match on class OR initialClass: Electron apps (Telegram, Obsidian) and
# browser --app windows routinely report one and not the other.
addr=$(printf '%s' "$clients" | jq -r --arg c "$class" '
    [ .[] | select((.class // "") | test($c; "i"))
         // empty ] as $byclass
    | ( $byclass
        + [ .[] | select((.initialClass // "") | test($c; "i")) ] )
    | first | .address // empty
' 2>/dev/null || true)

if [ -z "$addr" ]; then
    # Not running. Spawn and stop — focus follows naturally as it maps.
    hyprctl dispatch exec "$cmd"
    exit 0
fi

focused=$(printf '%s' "$clients" | jq -r '.[] | select(.focusHistoryID == 0) | .address // empty')

if [ "$addr" = "$focused" ]; then
    # Already focused: stash it out of the way.
    hyprctl dispatch movetoworkspacesilent "special:stash,address:$addr"
else
    # Running but not focused. If it is stashed, pull it to the current
    # workspace first — otherwise focuswindow would drag us into the
    # special workspace instead of bringing the window here.
    ws=$(printf '%s' "$clients" | jq -r --arg a "$addr" \
        '.[] | select(.address == $a) | .workspace.name // empty')
    case "$ws" in
        special:*) hyprctl dispatch movetoworkspace "+0,address:$addr" ;;
    esac
    hyprctl dispatch focuswindow "address:$addr"
fi
