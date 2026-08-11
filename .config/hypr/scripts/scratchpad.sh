#!/usr/bin/env bash
# ============================================================
#  Scratchpad toggle — the spawn-on-first-use half of qtile's DropDown.
#
#  qtile's DropDown("term1", "kitty", ...) did two jobs: it spawned the
#  client the first time you hit the key, and toggled visibility every
#  time after.  Hyprland's `togglespecialworkspace` only does the second
#  — on an empty special workspace it happily shows you nothing, which
#  is why binding it directly does not reproduce the old behaviour.
#
#  This restores the first job: if the named special workspace has no
#  clients, spawn the command into it; otherwise just toggle.
#
#  ---- WHY GEOMETRY LIVES HERE AND NOT IN rules.conf ----
#
#  It used to live there, as:
#      windowrule = size 60% 60%, match:workspace special:term1
#      windowrule = move 20% 10%, match:workspace special:term1
#
#  Tested against Hyprland 0.56.2, that silently does nothing.  Measured
#  on a 1366x768 monitor, spawning kitty with `size 50% 25%, move 10% 40%`
#  (want 683x192 @ 137,307):
#
#      percent size+move, special workspace -> 1346x748 @ 10,10   both ignored
#      pixel   size+move, special workspace ->  683x192 @ 137,307 correct
#      percent size+move, normal  workspace ->  683x192 @ 342,288 size ok, move ignored (centred)
#      pixel   size+move, normal  workspace ->  683x192 @ 137,307 correct
#
#  So: percentage `move` never applies, and on a special workspace
#  percentage `size` does not either.  Pixel values work everywhere.
#  `float` applied correctly in all four cases, which is what made this
#  hard to spot — the window floats, so it looks like the rules fired,
#  but it keeps its full tiled geometry.  There is no error and
#  `hyprctl configerrors` stays empty.
#
#  Hardcoding pixels in rules.conf would fix one monitor and break the
#  other, so instead we resolve percentages against the *focused*
#  monitor here, at spawn time, and pass the result as inline exec
#  rules — which are applied atomically as the window maps.
#
#  Usage:  scratchpad.sh <name> <command...>
# ============================================================
set -euo pipefail

name="${1:?usage: scratchpad.sh <name> <command...>}"
shift
cmd="$*"

# Geometry as percentages, transcribed from the DropDown() calls in
# ../qtile/config.py.  Kept here so binds.conf stays a plain name+command
# list and there is exactly one place to edit a scratchpad's size.
#            width height  x    y   opacity
case "$name" in
    term1|term2|calc) geom=(60 60 20 10 "")    ;;  # qtile: 0.6/0.6 @ 0.2/0.1
    chatgpt)          geom=(70 80 15 10 "")    ;;  # qtile: 0.7/0.8 @ 0.15/0.1
    deepseek|whats)   geom=(70 80 15 10 0.95)  ;;  # these two were opacity=0.95
    *)                geom=(60 60 20 10 "")    ;;
esac
pw=${geom[0]} ph=${geom[1]} px=${geom[2]} py=${geom[3]} opacity=${geom[4]}

# `hyprctl clients -j` lists every client with its workspace; count the
# ones sitting in special:<name>.  jq is the only hard dependency here.
count=$(hyprctl clients -j | jq --arg ws "special:$name" '[.[] | select(.workspace.name == $ws)] | length')

if [ "$count" -eq 0 ]; then
    # Resolve the percentages against the focused monitor.  Sizes are
    # logical (width/scale), and x/y are global compositor coordinates,
    # so the monitor's own origin has to be added or the window lands on
    # the wrong screen entirely once a second monitor is attached.
    read -r w h x y < <(
        hyprctl monitors -j | jq -r --argjson g "[$pw,$ph,$px,$py]" '
            .[] | select(.focused)
            | (.width / .scale)  as $lw
            | (.height / .scale) as $lh
            | "\(($lw * $g[0] / 100) | round) \(($lh * $g[1] / 100) | round) \((.x + $lw * $g[2] / 100) | round) \((.y + $lh * $g[3] / 100) | round)"
        '
    )

    rules="workspace special:$name silent; float; size $w $h; move $x $y"
    [ -n "$opacity" ] && rules="$rules; opacity $opacity"

    # Spawn into the special workspace directly, so the window never
    # flashes on the current one first.
    hyprctl dispatch exec "[$rules] $cmd"
    # Then reveal it.  The client needs a moment to map before the
    # toggle registers it; without this the first press appears to do
    # nothing and the second one hides an already-hidden workspace.
    sleep 0.35
fi

hyprctl dispatch togglespecialworkspace "$name"
