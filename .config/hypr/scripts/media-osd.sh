#!/usr/bin/env bash
# media-osd.sh volume up|down|mute|micmute
# media-osd.sh brightness up|down
#
# The change AND the feedback, in one place, for every key that moves volume
# or brightness — the media submap's six and the hardware keys' five.
#
# WHAT WAS WRONG
# --------------
# The binds called `wpctl` and `brightnessctl` directly and nothing raised an
# OSD. submaps.conf's note explained why that was acceptable — "the island
# draws the OSD for those" — and it is true exactly half the time: bar-switch
# STOPS the island to start the topbar, so under the qtile-style bar these
# keys changed the volume with no feedback of any kind. Reported as such.
#
# The same note also worried that routing one path through qtile's module and
# the other through wpctl "would give the same key two different OSDs and two
# different rounding behaviours". That concern is answered by this file rather
# than argued with: every path goes through here now, so there is one step
# size, one ceiling, and one OSD.
#
# WHO DRAWS IT
# ------------
# The island watches Pipewire itself and draws its own OSD, so raising a
# notification while it is up would show TWO for one keypress. The bar mode
# decides, the same way AtiScriptsV1/ati-bar-action decides everything else:
#
#     island  ->  the island already drew it; do nothing
#     native  ->  qtile's notification, which IS qtile's OSD
#
# THE NOTIFICATION IS qtile's, FLAG FOR FLAG
# ------------------------------------------
# scripts/volume_control.py and brightness_control.py, and the three hints are
# what make it an OSD rather than a message:
#
#   -h string:x-dunst-stack-tag:volume   replaces the previous one instead of
#                                        stacking, so holding a key leaves ONE
#   -h int:value:<n>                     draws the PROGRESS BAR — this is the
#                                        whole reason it reads as an OSD
#   -i <icon>                            the level-appropriate symbolic icon
#
# Drop the stack tag and a held key leaves forty notifications; drop the value
# and it is a text popup that happens to say a number.
#
# The numbers are qtile's: ±5, and a 150% ceiling — `-l 1.5` is where
# volume_control.py's `min(150, ...)` lands.

set -euo pipefail

STEP=5
CEILING=1.5            # wpctl's form of qtile's min(150, …)
SINK="@DEFAULT_AUDIO_SINK@"
SOURCE="@DEFAULT_AUDIO_SOURCE@"
MODE_FILE="$HOME/.cache/bar-mode"

bar_mode() {
    local m=""
    [[ -r "$MODE_FILE" ]] && m="$(<"$MODE_FILE")"
    m="${m//[[:space:]]/}"
    # Default ISLAND, matching ati-bar-action and bar-switch: on a machine that
    # has never switched, the Hyprland session has always had the island.
    case "$m" in native) echo native ;; *) echo island ;; esac
}

notify() {
    # Only when nothing else is drawing one. See the header.
    [[ "$(bar_mode)" == native ]] || return 0
    local app="$1" tag="$2" value="$3" icon="$4" title="$5" body="$6"
    notify-send -a "$app" -u normal \
        -h "string:x-dunst-stack-tag:$tag" \
        ${value:+-h "int:value:$value"} \
        -i "$icon" \
        "$title" "$body" 2>/dev/null || true
}

sink_percent() {
    # `wpctl get-volume` prints "Volume: 0.55" or "Volume: 0.55 [MUTED]".
    local out
    out="$(wpctl get-volume "$SINK" 2>/dev/null || echo "Volume: 0")"
    awk '{ printf "%d", ($2 * 100) + 0.5 }' <<<"$out"
}

sink_muted() {
    wpctl get-volume "$SINK" 2>/dev/null | grep -q MUTED
}

volume_icon() {
    local pct="$1"
    if (( pct <= 0 ));  then echo audio-volume-muted-symbolic
    elif (( pct < 30 )); then echo audio-volume-low-symbolic
    elif (( pct < 70 )); then echo audio-volume-medium-symbolic
    else                     echo audio-volume-high-symbolic
    fi
}

brightness_icon() {
    local pct="$1"
    if (( pct <= 0 ));  then echo display-brightness-off-symbolic
    elif (( pct < 34 )); then echo display-brightness-low-symbolic
    elif (( pct < 67 )); then echo display-brightness-medium-symbolic
    else                     echo display-brightness-high-symbolic
    fi
}

case "${1:-}" in
volume)
    case "${2:-}" in
    up)   wpctl set-volume -l "$CEILING" "$SINK" "${STEP}%+" ;;
    down) wpctl set-volume "$SINK" "${STEP}%-" ;;
    mute)
        wpctl set-mute "$SINK" toggle
        if sink_muted; then
            notify Volume volume "" audio-volume-muted-symbolic Volummute Muted
        else
            notify Volume volume "" audio-volume-high-symbolic Volummute Unmuted
        fi
        exit 0 ;;
    micmute)
        wpctl set-mute "$SOURCE" toggle
        if wpctl get-volume "$SOURCE" 2>/dev/null | grep -q MUTED; then
            notify Volume mic "" microphone-disabled-symbolic Microphone Muted
        else
            notify Volume mic "" microphone-sensitivity-high-symbolic Microphone Unmuted
        fi
        exit 0 ;;
    *) echo "usage: media-osd.sh volume up|down|mute|micmute" >&2; exit 2 ;;
    esac
    pct="$(sink_percent)"
    notify Volume volume "$pct" "$(volume_icon "$pct")" Volume "${pct}%"
    ;;
brightness)
    case "${2:-}" in
    up)   brightnessctl set "${STEP}%+" >/dev/null ;;
    down) brightnessctl set "${STEP}%-" >/dev/null ;;
    *) echo "usage: media-osd.sh brightness up|down" >&2; exit 2 ;;
    esac
    # brightnessctl's own percentage, not a second calculation off max: the
    # two disagree by a percent at the ends because of integer rounding, and
    # an OSD that says 99% at full is worse than one that says nothing.
    pct="$(brightnessctl -m 2>/dev/null | awk -F, '{ gsub("%","",$4); print $4 }')"
    pct="${pct:-0}"
    notify Brightness brightness "$pct" "$(brightness_icon "$pct")" \
        Brightness "${pct}%"
    ;;
*)
    echo "usage: media-osd.sh volume|brightness <action>" >&2
    exit 2 ;;
esac
