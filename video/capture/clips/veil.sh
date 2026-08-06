# shellcheck shell=bash
# Sourced by shoot.sh — not executed directly, hence no shebang.
#
# veil.gif — P1, re-shoot
#
# What it must show: the desktop frosting over, ONE CARD PER OPEN WINDOW
# appearing, a real progress indicator advancing (driven by the incoming
# qtile, not a fake timer), then the veil lifting onto a restored desktop
# with the same windows in the same groups.
#
# The shipped clip is on dracula, and its terminals show `bash-5.3$`. This
# one is doomone with fish, so it matches the page it sits on -- the point
# of c206da5.
#
# Needs windows open, and ideally across more than one group, or "the same
# windows in the same groups" has nothing to demonstrate. Run
# `./nest.sh seed` first.
#
# The restart is real: qtile re-execs inside the nest. Nothing here touches
# the owner's session, whose qtile is a different process on a different
# display.

REGION="1366x768+0+0"
DURATION=10
FPS_IN=24
FPS_OUT=14
STATS="full"            # the whole frame frosts over and clears
SETTLE=1.5

k() { DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "$@"; }

choreograph() {
  sleep 1.0
  k super+shift+r       # the veil, and a real qtile restart behind it
  sleep 8.0             # frost -> cards -> progress -> lift -> restored
}
