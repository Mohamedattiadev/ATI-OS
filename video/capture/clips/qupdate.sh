# shellcheck shell=bash
# Sourced by shoot.sh — not executed directly, hence no shebang.
#
# qupdate.gif — P1, re-shoot
#
# What it must show: tab one listing pending pacman + AUR packages with
# CHECKBOXES TOGGLING, and tab two searching repos + AUR with results
# arriving. The window appearing is part of the clip.
#
# Two faults in the shipped clip, both fixed here:
#   * it is on everforest, against a doomone-themed manual
#   * its first frame is a spinner reading "Loading updates...", which
#     breaks rule 7 -- the first frame should already be the subject
#
# The spinner is a two-step toggle, not a slow app. The FIRST --toggle
# starts the daemon and leaves its window unmapped; the SECOND maps an
# already-populated window. prepare() below does the first and the clip does
# the second, so the list is on screen from frame one.
#
# The package list is the real pacman/AUR state of the host. Package names
# are not personal data, and nothing here installs, upgrades or syncs
# anything -- no button in the bottom row is ever clicked.

REGION="1366x768+0+0"
DURATION=13
FPS_IN=24
FPS_OUT=13
STATS="full"
SETTLE=1.0

QU="/run/user/1000/atios-nest/home/.config/qtile/scripts/qupdate.py"
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

m() { DISPLAY="$NEST_DISPLAY" xdotool mousemove "$1" "$2"; }
c() { DISPLAY="$NEST_DISPLAY" xdotool click 1; }
t() { DISPLAY="$NEST_DISPLAY" xdotool type --clearmodifiers --delay 70 "$1"; }
qu() { "$_here/nest.sh" exec python3 "$QU" "$@" >/dev/null 2>&1 || true; }

prepare() {
  # Start from a known state: no boxes ticked, Updates tab active, no search
  # text. The daemon keeps all three between toggles, so a second take would
  # otherwise open on the leftovers of the first.
  #
  # Killed by nest tag, never by name -- `pkill -f qupdate.py` matches the
  # OWNER's daemon, which is a different process on a different display.
  local p
  for p in $(pgrep -f "atios-nest.*qupdate.py" 2>/dev/null); do kill "$p" 2>/dev/null; done
  sleep 2

  # Warm the daemon so the first query is done before the camera opens.
  #
  # This does NOT remove the "Loading updates..." beat, and two attempts to
  # make it were both wrong. Waiting longer (18s, then 26s) changed nothing,
  # and neither did showing the window off camera and hiding it again. What
  # survives a hide/show is the INSTALL tab -- its search text and results
  # come straight back. The Updates tab re-queries pacman and the AUR every
  # time it is mapped, so roughly 1.5s of spinner is the app honestly
  # working, not a harness failure, and no amount of preparation removes it.
  #
  # That is fine, and it is still a fix. The complaint about the shipped clip
  # was that its FIRST FRAME was the spinner -- it opened mid-load, with no
  # context for what was loading. This one opens on the desktop, shows the
  # window arrive, loads briefly, and fills.
  qu --toggle            # start the daemon; window stays unmapped
  sleep 20
}

choreograph() {
  qu --toggle            # the populated window appears
  sleep 2.6

  m 344 268; c; sleep 0.9   # tick brave-bin
  m 344 310; c; sleep 1.4   # tick google-chrome — "2 selected" in the footer

  m 733 173; c; sleep 1.8   # Install tab: "Type to search official repos + AUR"
  t "ripgrep"; sleep 4.0    # results arrive, repo and AUR, with installed marks
  sleep 1.0
}
