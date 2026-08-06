# shellcheck shell=bash
# Sourced by shoot.sh — not executed directly, hence no shebang.
# groups.gif — P1
#
# What it must show: the GroupBox in the bar, the active group's ICON GLYPH
# recolouring to the accent as the number changes, and the TaskList to its
# left emptying and refilling with that group's windows.
#
# Two config facts that decide whether this clip shows anything at all:
#   * highlight_method="text" -- there is NO PILL. Only the glyph recolours.
#     A clip shot expecting a moving highlight block records nothing.
#   * hide_unused=True -- an empty group is not drawn. Windows must be
#     seeded across several groups first or there is nothing to see move.
#     Run `./nest.sh seed` before this clip; group 8 is left empty on
#     purpose so the clip shows both states.

REGION="1366x38+0+0"    # top bar strip, native
DURATION=7
FPS_IN=24
FPS_OUT=12
STATS="diff"             # a bar strip is ~95% static pixels
SETTLE=1.2

k() { DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "$@"; }

choreograph() {
  # At least 4 groups, including one with windows and one empty.
  k super+1; sleep 1.4
  k super+2; sleep 1.4
  k super+4; sleep 1.4
  k super+8; sleep 1.4
  k super+1; sleep 1.0
}
