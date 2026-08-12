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
    # logical (width/scale).
    #
    #  ---- x/y ARE MONITOR-RELATIVE, NOT GLOBAL ----
    #
    #  This read the other way round until it was measured on a second
    #  monitor, and it cost nothing on a single-monitor machine because
    #  eDP-1 sits at 0,0 — adding an origin of zero twice is still zero.
    #
    #  Measured against 0.56.2 with a headless output at 1366,0
    #  (`hyprctl output create headless`), spawning kitty with
    #  `move 100 100` as an inline exec rule while that output was
    #  focused: the window landed at 1466,100.  So Hyprland adds the
    #  monitor's own origin to a rule's `move`, and a caller that has
    #  already added it gets the offset twice.
    #
    #  The symptom is not a window shifted by one screen width, which is
    #  what you would look for.  A doubled offset usually pushes the
    #  window past the monitor's edge, and Hyprland then places it
    #  somewhere else entirely — a 60%-wide scratchpad came back exactly
    #  centred, i.e. looking like the `move` had been ignored rather than
    #  applied twice.
    read -r w h x y < <(
        hyprctl monitors -j | jq -r --argjson g "[$pw,$ph,$px,$py]" '
            .[] | select(.focused)
            | (.width / .scale)  as $lw
            | (.height / .scale) as $lh
            | "\(($lw * $g[0] / 100) | round) \(($lh * $g[1] / 100) | round) \(($lw * $g[2] / 100) | round) \(($lh * $g[3] / 100) | round)"
        '
    )

    rules="workspace special:$name silent; float; size $w $h; move $x $y"
    [ -n "$opacity" ] && rules="$rules; opacity $opacity"

    #  ---- INLINE EXEC RULES ARE NOT ENOUGH, AND HERE IS WHY ----
    #
    #  Hyprland attaches the `[...]` rules of a `dispatch exec` to the
    #  process it spawns. That works for kitty and qalculate, which map
    #  their own window. It does NOT work for the three browser
    #  scratchpads: `brave --app=...` hands the URL to the ALREADY RUNNING
    #  brave and exits, so the window is created by a process Hyprland
    #  never spawned and the rules match nothing at all.
    #
    #  Measured: `dispatch exec "[workspace 8 silent] brave --app=... "`
    #  put the window on workspace 4 — the active one — at full tiled size.
    #  That is the whole of "the chatgpt/deepseek/whatsapp scratchpads do
    #  not behave like the terminal ones": no workspace, no float, no
    #  geometry, because the rules were addressed to the wrong process.
    #
    #  (Also worth knowing: brave IGNORES --class for --app windows. It
    #  derives one from the URL and profile instead, e.g.
    #  `brave-chat.openai.com__-Chatgpt`. So there is no class to hand it
    #  and nothing to match on until the window exists.)
    #
    #  So: spawn, then WAIT for whatever new window appeared and place it
    #  by address. Dispatchers do not care which process made the window.
    before=$(hyprctl clients -j | jq -r '.[].address' | sort)
    hyprctl dispatch exec "[$rules] $cmd"

    # Poll rather than sleep a fixed time. A terminal maps in ~200 ms; a
    # browser --app window on a cold profile can take several seconds, and
    # a fixed sleep long enough for the second makes the first feel broken.
    addr=""
    for _ in $(seq 1 60); do
        sleep 0.25
        addr=$(hyprctl clients -j | jq -r --arg b "$before" '
            ($b | split("\n")) as $old
            | [ .[] | select((.address | IN($old[])) | not) ] | .[0].address // empty
        ')
        [ -n "$addr" ] && break
    done

    if [ -n "$addr" ]; then
        # Place it explicitly. This is a no-op for the windows whose exec
        # rules already fired, and it is the only thing that works for the
        # ones whose rules did not.
        batch="dispatch movetoworkspacesilent special:$name,address:$addr"
        batch="$batch ; dispatch setfloating address:$addr"
        batch="$batch ; dispatch resizewindowpixel exact $w $h,address:$addr"
        # movewindowpixel is monitor-relative, same as the rule form —
        # see the note above where x and y are computed.
        batch="$batch ; dispatch movewindowpixel exact $x $y,address:$addr"
        [ -n "$opacity" ] && batch="$batch ; dispatch setprop address:$addr alpha $opacity"
        hyprctl --batch "$batch" >/dev/null
    fi
fi

hyprctl dispatch togglespecialworkspace "$name"
