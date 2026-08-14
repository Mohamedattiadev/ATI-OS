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
        [ -n "$opacity" ] && batch="$batch ; dispatch setprop address:$addr alpha $opacity"
        hyprctl --batch "$batch" >/dev/null

        #  ---- THE MOVE COMES AFTER THE RESIZE, NOT INSIDE THE BATCH ----
        #
        #  A window with a minimum size does not get the height we asked
        #  for, which is its right — but the CLAMP RECENTRES it, and inside
        #  a batch that happens after the move, so the move is undone by the
        #  resize that precedes it.
        #
        #  Measured with qalculate-gtk, whose minimum height is 550 against
        #  the 461 this pad asks for:
        #
        #      requested   820x461 @273,77
        #      batch gave  820x550 @273,33     <- y is 77 - (550-461)/2
        #      move again  820x550 @273,77     correct
        #
        #  The 44 px is exactly half the overshoot, which is what named it:
        #  the window was not "placed wrong", it was placed right and then
        #  grown symmetrically about its own centre.
        #
        #  kitty and the browser pads never showed this because they accept
        #  the requested height, so the recentring is zero. It is only
        #  visible on a pad whose app refuses the size.
        #
        #  movewindowpixel is monitor-relative, same as the rule form — see
        #  the note above where x and y are computed.
        hyprctl dispatch movewindowpixel exact $x $y,address:$addr >/dev/null

        #  ---- AND AGAIN LATER, BECAUSE THE APP MOVES IT AFTER WE DO ----
        #
        #  The placement above is correct and then stops being correct. The
        #  timeline, sampled every 150 ms from spawn:
        #
        #      t=0.90s   820x461 @273,77     our rules, exactly right
        #      t=1.35s   820x550 @273,33     qalculate-gtk resizes ITSELF
        #      t=3.90s   820x550 @273,33     and stays there
        #
        #  So this is not the exec rules failing and not the batch racing.
        #  The app asks for a taller window half a second after mapping,
        #  Hyprland honours it, and a floating window grown about its own
        #  centre drifts up by half the overshoot — exactly the 44 px
        #  between y=77 and y=33.
        #
        #  Two fixes were measured and rejected before this one. Moving
        #  after the batch instead of inside it: no effect. Move-verify-
        #  remove up to four times: no effect either, and the reason is
        #  worth keeping — it SUCCEEDS, reads back @273,77, and breaks,
        #  and the app resizes after its last read. A verify loop cannot
        #  catch a change that happens after it stops looking.
        #
        #  Waiting for the size to settle before the first move would work,
        #  but every pad would pay ~1 s of first-launch latency for one
        #  app's habit. So the correction is BACKGROUNDED: the pad appears
        #  immediately, and a watcher re-asserts the position once the size
        #  has held steady for three reads. For kitty and the browsers,
        #  which never resize themselves, it confirms and exits.
        (
            prev=""; stable=0
            for _ in $(seq 1 30); do
                sleep 0.2
                cur=$(hyprctl clients -j | jq -r --arg a "$addr" \
                    '.[] | select(.address == $a) | "\(.size[0])x\(.size[1])"')
                [ -z "$cur" ] && exit 0        # window went away; nothing to fix
                if [ "$cur" = "$prev" ]; then
                    stable=$((stable + 1))
                else
                    stable=0
                fi
                prev="$cur"
                [ "$stable" -ge 3 ] && break
            done
            read -r ax ay < <(hyprctl clients -j | jq -r --arg a "$addr" \
                '.[] | select(.address == $a) | "\(.at[0]) \(.at[1])"')
            if [ "${ax:-}" != "$x" ] || [ "${ay:-}" != "$y" ]; then
                hyprctl dispatch movewindowpixel exact $x $y,address:$addr >/dev/null
            fi
        ) >/dev/null 2>&1 &
    fi
fi

#  ---- SHOW, DO NOT TOGGLE, WHEN WE JUST SPAWNED ----
#
#  `togglespecialworkspace` was called unconditionally, including on the
#  path that has only just created the window. That path KNOWS the end
#  state it wants — the pad you pressed the key for, on screen — and asking
#  for a toggle instead of a state is how it goes out of phase.
#
#  Seen live, and intermittently, which is what makes it worth a guard
#  rather than a retry: first launch of `calc` while `term2` was already
#  open left term2 on screen and calc hidden, so the key looked dead and a
#  second press was needed. It did not reproduce on the next attempt, and
#  it never reproduces with kitty — the pads whose app maps in under
#  250 ms always win the race. Hyprland's own semantics are not at fault:
#  toggling B while A is open switches to B, verified directly.
#
#  So the spawn path asserts the state instead of flipping it. The
#  no-spawn path is a real toggle and stays one — that is the whole
#  behaviour of a scratchpad key.
visible=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .specialWorkspace.name // ""')

#  An `&&` chain rather than an `if` would be shorter and wrong: under
#  `set -e` a false test as the script's last statement leaves a non-zero
#  exit code, and this script is run from a keybind where that is invisible
#  until something downstream starts checking it.
if [ "$count" -eq 0 ]; then
    if [ "$visible" != "special:$name" ]; then
        hyprctl dispatch togglespecialworkspace "$name"
    fi
else
    hyprctl dispatch togglespecialworkspace "$name"
fi
