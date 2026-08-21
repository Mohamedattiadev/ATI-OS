#!/usr/bin/env bash
# ============================================================
#  $mod SHIFT S — the TODOS summary window.
#
#  ---- THE BINDING WAS PORTED FROM THE WRONG THREE LINES ----
#
#  ../qtile/config.py's Key([mod,"shift"],"s", ...) is NOT commented out —
#  the commented one at :6090 is an older `toggle_sum()` on mod2. The live
#  one is at :6007 and it calls
#
#      toggle_or_spawn_sum(qtile, myTerm, sum_file)
#
#  from `scripts/sum_app.py`, which this script is a transcription of. Read
#  that file, not this one, if the two ever disagree.
#
#  Three things the Hyprland side had wrong, each measured against qtile's
#  own source rather than assumed:
#
#  1. THE FILE.  It opened `~/sum.md`, which **does not exist on this
#     machine** (`ls: cannot access '/home/ati/sum.md'`). qtile's is
#
#         todos_dir = ~/${USER^^}TODOS          -> ~/ATITODOS
#         sum_file  = todos_dir/TODOS.md        -> ~/ATITODOS/TODOS.md
#
#     which is 813 bytes and syncthing-backed. So the key opened an empty
#     buffer at a path nothing else writes to, and every note typed into it
#     went somewhere the phone sync never looks.
#
#  2. THE CLASS AND TITLE.  qtile spawns
#
#         kitty --name sum-md --class sum-md --title sum.md \
#               -e nvim -c':set nonumber norelativenumber' <file>
#
#     Both halves of WM_CLASS are `sum-md`, and sum_app.py explains why:
#     WM_CLASS exists before the MapRequest, WM_NAME races it, so a
#     title-only rule loses often enough that the window tiles for a frame.
#     The Hyprland port used `--class nvimsum --title nvimsum` instead,
#     which matches nothing qtile ever wrote.
#
#  3. **GROUP "S" NEVER CLAIMED THIS WINDOW, AND THE PORT WAS BUILT ON THE
#     BELIEF THAT IT DID.**  Group("S") lists `Match(title="nvimsum")`
#     (:6955) and that is the whole basis for "the summary lives on S".
#     But nothing in qtile has been titled `nvimsum` since the alacritty
#     era — the only other mention is the commented-out Match at :6896.
#     kitty's `--title` overrides the program's own title, nvim never
#     changes it, so the window's title is `sum.md` and the group Match
#     cannot fire. It is dead config.
#
#     What actually places the window is `float_rules` (:7761-7765,
#     `Match(wm_class="sum-md")`) plus the `_float_and_center_sum`
#     client_managed hook (:1694), and toggle_or_spawn_sum's CASE 1, which
#     does `win.togroup(qtile.current_group.name)` — it drags the window to
#     **wherever you are standing**. That is the point of the binding: the
#     desc string is "Open or focus sum.md **globally**".
#
#     So the real behaviour is: floating, centred, 55%x65%, on the CURRENT
#     workspace — not on S. If you want it pinned to S instead, one
#     `windowrule = workspace name:S` in rules.conf does it; it is left out
#     because qtile does not do it.
#
#  ---- MINIMIZE ----
#
#  qtile's fourth branch is `win.toggle_minimize()`: press the key while the
#  window is focused and it hides, keeping its geometry and its nvim
#  session. Hyprland has no minimize. A special workspace is this config's
#  standing answer for "present but not on screen" (see scratchpad.sh), so
#  the window goes to `special:sum` and comes back from it.
#
#  ---- THE PULL ----
#
#  Every branch that SHOWS the window runs ati-simplenote-push --pull first, to
#  fetch anything typed on the phone. Backgrounded, never waited on: qtile's
#  comment records that the script allows itself 15s on a stalled
#  connection, and its event loop is single-threaded so blocking froze the
#  whole WM. Hyprland would not freeze — this is `exec`, not the compositor
#  — but the window still must not wait 15s to appear. nvim's autoread +
#  checktime autocmd picks the file up if the pull lands late.
# ============================================================
set -euo pipefail

file="$HOME/$(printf '%s' "${USER:-$LOGNAME}" | tr '[:lower:]' '[:upper:]')TODOS/TODOS.md"
cls="sum-md"
stash="special:sum"
pull="$HOME/.config/AtiScriptsV1/ati-simplenote-push"

# 55% x 65%, floors of 600x400 — sum_app.py's FLOAT_W_RATIO / FLOAT_H_RATIO
# / FLOAT_W_MIN / FLOAT_H_MIN. Resolved against the FOCUSED monitor at press
# time, not hardcoded, for the reason scratchpad.sh documents: hardcoding
# pixels fixes one monitor and breaks the other.
read -r mw mh < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.width) \(.height)"')
w=$(( mw * 55 / 100 )); [ "$w" -lt 600 ] && w=600
h=$(( mh * 65 / 100 )); [ "$h" -lt 400 ] && h=400

pull_sum() { [ -x "$pull" ] && ("$pull" --pull >/dev/null 2>&1 &) || true; }

# Match on class OR initialClass. kitty sets app_id from --class on Wayland
# and WM_CLASS from --name/--class under XWayland; both spellings are the
# same string here, but initialClass is the one that survives a client that
# renames itself later.
win=$(hyprctl clients -j | jq -c --arg c "$cls" '
    [ .[] | select((.class // "") == $c or (.initialClass // "") == $c) ] | .[0] // empty')

if [ -z "$win" ]; then
    # CASE 3 — not running. No workspace in the rule: the CURRENT one is
    # where it should land, and that is also where exec puts it.
    #
    # The size is an INLINE rule and it is in PIXELS, both deliberately.
    # A static `windowrule = size 55% 65%` is silently inert — measured, see
    # rules.conf — while the identical percentage in an inline exec rule
    # applies. Inline rules only attach to a process Hyprland spawns, which
    # kitty is (unlike `brave --app`, see scratchpad.sh). Pixels because the
    # percentage has already been resolved against the focused monitor
    # above, which is the only way this holds on both screens.
    # `-o background_opacity` for the same reason $term carries it in
    # binds.conf: hyprglass refracts what is BEHIND a window, and
    # kitty.conf's own 0.95 leaves nothing to refract, so a kitty spawned
    # without it is a flat rectangle while every other terminal on the
    # desktop is glass. This one was spawned bare and was the odd one out —
    # visible only by putting it beside another terminal, which is exactly
    # the kind of thing that never gets noticed on its own.
    #
    # It is NOT taken from $term: that is a Hyprland variable in binds.conf
    # and this is a shell script, which cannot see it. Duplicated
    # deliberately, and this comment is the pointer between the two.
    pull_sum
    exec hyprctl dispatch exec "[float; size $w $h; center 1] \
        kitty -o background_opacity=0.70 --name $cls --class $cls --title sum.md \
        -e nvim -c':set nonumber norelativenumber' $file"
fi

addr=$(printf '%s' "$win" | jq -r '.address')
ws=$(printf '%s' "$win" | jq -r '.workspace.name')
cur=$(hyprctl activeworkspace -j | jq -r '.name')
focused=$(hyprctl activewindow -j | jq -r '.address // empty')

# ---- BRANCH ORDER IS LOAD-BEARING: "is it here" BEFORE "is it focused" ----
#
# The first version asked `addr == focused?` first, and the result was that
# the key stashed the window and then could never get it back — press 2 and
# press 3 both left it on `special:sum`, measured. The reason is a Hyprland
# behaviour with no qtile counterpart:
#
#   **`movetoworkspacesilent` to a special workspace leaves the window as
#   `hyprctl activewindow`.** It is off screen, on a hidden workspace, and
#   still reports as the active window — so the very next press matched the
#   focused branch and stashed an already-stashed window.
#
# qtile could not have this bug: `qtile.current_window` is a property of the
# CURRENT GROUP, so a minimized window on another group is never it. The
# port of that guarantee is to ask about the workspace first. toggle-app.sh
# has a note about the mirror-image mistake — using focusHistoryID 0, which
# is global, where activewindow was wanted.
if [ "$ws" != "$cur" ]; then
    # CASE 1 / 2a — stashed, or open on another workspace: drag it to where
    # you are standing and re-place it. That is qtile's
    # `win.togroup(qtile.current_group.name)`; this window follows you, it
    # does not own a workspace.
    #
    # `setfloating` before the resize: a tiled window ignores
    # resizewindowpixel, and this one can arrive tiled if layout-cycle.sh
    # ever grouped it.
    pull_sum
    hyprctl --batch "dispatch movetoworkspacesilent $cur,address:$addr ; \
                     dispatch setfloating address:$addr ; \
                     dispatch resizewindowpixel exact $w $h,address:$addr" >/dev/null
    hyprctl dispatch focuswindow "address:$addr" >/dev/null
    # centerwindow acts on the ACTIVE floating window and takes no window
    # selector, so it has to come after the focus rather than in the batch.
    exec hyprctl dispatch centerwindow
fi

if [ "$addr" = "$focused" ]; then
    # CASE 2d — here and focused: "minimize". Silent, so the stash workspace
    # is not brought on screen along with it.
    exec hyprctl dispatch movetoworkspacesilent "$stash,address:$addr"
fi

# CASE 2c — same workspace, not focused: just focus it. qtile does not
# re-place the window in this branch and neither does this.
pull_sum
exec hyprctl dispatch focuswindow "address:$addr"
