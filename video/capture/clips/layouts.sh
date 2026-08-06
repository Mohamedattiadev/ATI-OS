# shellcheck shell=bash
# Sourced by shoot.sh — not executed directly, hence no shebang.
# layouts.gif — P1
#
# What it must show: the layout chip's TEXT changing monadtall -> max ->
# treetab, and the tiling behind it rearranging in the same frame -- two
# dummy terminals side by side, then one full-width, then a TreeTab side
# panel.
#
# Full screen, because "the chip changed" and "the windows rearranged" have
# to be in one frame. A bar-strip crop would show half the story, which is
# the mistake the old mode-chip clips made.

REGION="1366x768+0+0"
DURATION=8
FPS_IN=24
FPS_OUT=14
STATS="full"             # most of the frame moves on every beat
SETTLE=1.2

k() { DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "$@"; }

choreograph() {
  sleep 0.8
  k super+Tab; sleep 2.0    # monadtall -> max
  k super+Tab; sleep 2.0    # max -> treetab
  k super+Tab; sleep 2.0    # onward
  k super+Tab; sleep 1.0    # back toward monadtall
}
