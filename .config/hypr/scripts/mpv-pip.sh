#!/usr/bin/env bash
# ============================================================
#  mpv PiP toggle — the one binding in qtile's Media-Mode that was not
#  a volume or brightness key.
#
#  qtile's version is ../qtile/scripts/mpv_manager.py, and it does NOT
#  port: it imports libqtile at module level and drives qtile's own
#  window objects (togroup, keep_above, change_layer, floating state).
#  What ports is the BEHAVIOUR, and its numbers are taken from that file
#  rather than reinvented:
#
#      PIP_W      = 320   # width of the corner window
#      PIP_MARGIN = 20    # from the screen edges
#      PIP_GAP    = 12    # between stacked PiP windows
#      CENTER_*   = 0.60 x 0.50   # what it toggles back to
#
#  ---- WHAT STANDS IN FOR keep_above ----
#
#  qtile called window.keep_above(True), because "a PiP that can be
#  covered is not much of a PiP". Hyprland's equivalent for a floating
#  window is `pin`, which also keeps it across workspace switches — that
#  is a bonus here, since mpv_manager.py had a whole follow_to_new_group()
#  hook to achieve the same thing by hand.
#
#  ---- WHY THERE IS NO STATE FILE ----
#
#  mpv_manager.py keeps ~/.cache/qtile/mpv_state.json so it can re-adopt
#  windows after a qtile restart. The state here is readable off the
#  window itself — a PiP is the floating, pinned one that is PIP_W wide —
#  which is what qtile's own _is_pip() fell back to (`window.width ==
#  PIP_W`). No file means nothing to go stale, and `hyprctl reload` does
#  not disturb windows at all.
#
#  Usage:  mpv-pip.sh
# ============================================================
set -euo pipefail

PIP_W=320
PIP_MARGIN=20
PIP_GAP=12
CENTER_W_RATIO=0.60
CENTER_H_RATIO=0.50

clients=$(hyprctl clients -j)
focused=$(hyprctl activewindow -j | jq -r '.address // empty')

# The window a keybind should act on: the focused mpv if there is one,
# otherwise the most recently focused mpv. Same rule as qtile's target().
addr=$(printf '%s' "$clients" | jq -r --arg f "$focused" '
    [ .[] | select((.class // "") | test("^mpv$"; "i")) ]
    | (map(select(.address == $f)) + sort_by(.focusHistoryID))
    | .[0].address // empty
')

if [ -z "$addr" ]; then
    notify-send -a mpv "PiP" "No mpv window" 2>/dev/null || true
    exit 0
fi

read -r cw ch is_float is_pinned mon < <(
    printf '%s' "$clients" | jq -r --arg a "$addr" '
        .[] | select(.address == $a)
        | "\(.size[0]) \(.size[1]) \(.floating) \(.pinned) \(.monitor)"'
)

read -r mx my mw mh < <(
    hyprctl monitors -j | jq -r --argjson m "$mon" '
        .[] | select(.id == $m)
        | "\(.x) \(.y) \((.width / .scale) | round) \((.height / .scale) | round)"'
)

# Already a PiP?  Floating, pinned, and PIP_W wide — all three, so a
# window merely floated by hand is not mistaken for one.
if [ "$is_float" = "true" ] && [ "$is_pinned" = "true" ] && [ "$cw" -eq "$PIP_W" ]; then
    # Back to qtile's centre mode: 60% x 50%, centred, unpinned.
    w=$(awk -v m="$mw" -v r="$CENTER_W_RATIO" 'BEGIN{printf "%d", m*r}')
    h=$(awk -v m="$mh" -v r="$CENTER_H_RATIO" 'BEGIN{printf "%d", m*r}')
    x=$(( mx + (mw - w) / 2 ))
    y=$(( my + (mh - h) / 2 ))
    hyprctl --batch "dispatch pin address:$addr ; \
                     dispatch resizewindowpixel exact $w $h,address:$addr ; \
                     dispatch movewindowpixel exact $x $y,address:$addr"
    exit 0
fi

# Becoming a PiP. Keep the window's own aspect ratio rather than assuming
# 16:9 — mpv_manager.py read it off the video and fell back to 16/9 only
# when it could not.
h=$(awk -v w="$PIP_W" -v cw="$cw" -v ch="$ch" \
    'BEGIN{ r = (cw>0 && ch>0) ? ch/cw : 9/16; printf "%d", w*r }')

# Stack upward from the corner instead of piling every PiP on one spot.
# Count only the OTHER windows that are already PiP, exactly as
# restack_pips() ordered them.
offset=$(printf '%s' "$clients" | jq -r --arg a "$addr" --argjson pw "$PIP_W" --argjson gap "$PIP_GAP" '
    [ .[]
      | select(.address != $a)
      | select((.class // "") | test("^mpv$"; "i"))
      | select(.floating and .pinned and .size[0] == $pw)
      | .size[1] + $gap ]
    | add // 0
')

x=$(( mx + mw - PIP_W - PIP_MARGIN ))
y=$(( my + mh - h - PIP_MARGIN - offset ))

# `pin` requires the window to be floating already, so the order matters:
# setfloating, then geometry, then pin. Batching keeps it to one frame.
hyprctl --batch "dispatch setfloating address:$addr ; \
                 dispatch resizewindowpixel exact $PIP_W $h,address:$addr ; \
                 dispatch movewindowpixel exact $x $y,address:$addr ; \
                 dispatch pin address:$addr"
