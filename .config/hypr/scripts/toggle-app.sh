#!/usr/bin/env bash
# ============================================================
#  toggle-app — the Hyprland replacement for scripts/toggle_apps.py
#
#  ---- WHAT THIS USED TO DO, AND WHY IT WAS WRONG ----
#
#  The first version was spawn / focus / stash-to-special, all on the
#  CURRENT workspace. That is not what qtile did, and it is why every app
#  ended up on whichever workspace you happened to be standing on.
#
#  qtile's _toggle() (scripts/toggle_apps.py) is workspace-centric. Three
#  branches, in this order:
#
#    1. Focused window IS the app  -> go BACK to the workspace you came
#                                     from (remembered per app).
#    2. App exists somewhere       -> remember where you are, then go to
#                                     the workspace the window is ACTUALLY
#                                     on -- not where it is filed -- and
#                                     focus it.
#    3. App is not running         -> remember where you are, switch to
#                                     the app's home workspace, spawn it
#                                     there.
#
#  So $mod N from workspace 1 lands you on 4 with kitty; pressing it
#  again returns you to 1. That round trip is the whole point and it is
#  what the previous version could not do, having no memory at all.
#
#  Home workspaces match the `matches=[Match(...)]` lists in config.py's
#  groups, which are also expressed as `workspace` rules in rules.conf so
#  that an app opened by any OTHER route still files itself correctly.
#  This script only handles the keybind path.
#
#  Usage:  toggle-app.sh <class-regex> <home-workspace> <command...>
# ============================================================
set -euo pipefail

class="${1:?usage: toggle-app.sh <class-regex> <home-workspace> <command...>}"
home_ws="${2:?missing home workspace}"
shift 2
cmd="$*"

# Where "go back" goes. One file per app, because the apps are toggled
# independently: bouncing off kitty must not send you wherever brave was
# last summoned from. Lives under the runtime dir so it dies with the
# session rather than persisting stale workspace ids across reboots.
state_dir="${XDG_RUNTIME_DIR:-/tmp}/hypr-toggle"
mkdir -p "$state_dir"
state_file="$state_dir/$(printf '%s' "$class" | tr -c '[:alnum:]' '_')"

clients=$(hyprctl clients -j)
current_ws=$(hyprctl activeworkspace -j | jq -r '.name')

# Match on class OR initialClass: Electron apps (Telegram, Obsidian) and
# browser --app windows routinely report one and not the other.
# `test` is unanchored, so "qutebrowser" still matches the real Wayland
# app_id org.qutebrowser.qutebrowser.
matching=$(printf '%s' "$clients" | jq -c --arg c "$class" '
    [ .[] | select(((.class // "") | test($c; "i")) or ((.initialClass // "") | test($c; "i"))) ]
')

# `activewindow`, NOT `focusHistoryID == 0`.
#
# focusHistoryID 0 is the most recently focused window *globally*, and it
# keeps that rank while you stand on a different, empty workspace. Using
# it meant that pressing $mod N from an empty workspace saw "you are
# already on kitty", took the go-back branch, found no memory, and did
# nothing at all — the key looked dead. qtile's equivalent,
# qtile.current_window, is None when the current group has no focus, and
# `hyprctl activewindow` is empty in exactly that case.
focused_addr=$(hyprctl activewindow -j | jq -r '.address // empty')

# ---- Branch 1: standing on the app -> go back ----
# Deliberately NOT conditional on also being on the app's home workspace:
# if the window was moved elsewhere, qtile's old code missed this branch
# and the key appeared dead. Its comment says so explicitly.
if [ -n "$focused_addr" ] \
   && [ "$(printf '%s' "$matching" | jq -r --arg a "$focused_addr" 'any(.address == $a)')" = "true" ]; then
    if [ -s "$state_file" ]; then
        prev=$(cat "$state_file")
        # Only honour it if it is not where we already are, else the key
        # would look dead when the app's home IS the previous workspace.
        if [ "$prev" != "$current_ws" ]; then
            hyprctl dispatch workspace "$prev"
            exit 0
        fi
    fi
    # No memory (app was opened by hand, or we already went back once).
    # qtile leaves you put rather than guessing a destination.
    exit 0
fi

count=$(printf '%s' "$matching" | jq 'length')

if [ "$count" -gt 0 ]; then
    # ---- Branch 2: open somewhere -> go to where it really is ----
    addr=$(printf '%s' "$matching" | jq -r '.[0].address')
    ws=$(printf '%s' "$matching" | jq -r '.[0].workspace.name')

    printf '%s' "$current_ws" > "$state_file"

    # A window parked in a special workspace has to be pulled out first,
    # or focuswindow drags us into the special workspace instead.
    case "$ws" in
        special:*)
            hyprctl dispatch movetoworkspace "$home_ws,address:$addr"
            hyprctl dispatch workspace "$home_ws"
            ;;
        *)
            hyprctl dispatch workspace "$ws"
            ;;
    esac
    hyprctl dispatch focuswindow "address:$addr"
else
    # ---- Branch 3: not running -> land on its workspace and start it ----
    printf '%s' "$current_ws" > "$state_file"
    hyprctl dispatch workspace "$home_ws"
    # Spawn with an explicit workspace rule rather than relying on the
    # switch above having settled: exec is asynchronous, and a slow
    # starter (Electron, a browser) can map after you have moved on.
    hyprctl dispatch exec "[workspace $home_ws] $cmd"
fi
