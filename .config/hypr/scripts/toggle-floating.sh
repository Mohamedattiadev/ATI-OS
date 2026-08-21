#!/usr/bin/env bash
# ============================================================
#  $mod T — togglefloating, but sized like a window instead of a sliver.
#
#  Plain `togglefloating` keeps whatever geometry the window already
#  had under the tiling layout, so floating a browser tile that was
#  squeezed into a stack slot floats it at that same squeezed size.
#  Going tiled -> floating here also resizes to 65%/70% of the focused
#  monitor and centres it. Going floating -> tiled is untouched — the
#  layout decides that geometry, not us.
#
#  Percentage `size`/`move` only apply through windowrule/exec-rule
#  syntax, and even then only partially (see scratchpad.sh). The
#  dispatchers used directly here, `resizeactive`/`movewindow`, take
#  pixels only, so the percentages are resolved against the focused
#  monitor by hand, same as scratchpad.sh does.
# ============================================================
set -euo pipefail

was_floating=$(hyprctl -j activewindow | jq -r '.floating // false')

hyprctl dispatch togglefloating >/dev/null

if [ "$was_floating" = "false" ]; then
    read -r w h < <(
        hyprctl monitors -j | jq -r '
            .[] | select(.focused)
            | (.width / .scale)  as $lw
            | (.height / .scale) as $lh
            | "\(($lw * 0.65) | round) \(($lh * 0.70) | round)"
        '
    )
    hyprctl dispatch resizeactive exact "$w" "$h" >/dev/null
    hyprctl dispatch centerwindow >/dev/null
fi
