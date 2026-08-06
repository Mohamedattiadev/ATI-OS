# shellcheck shell=bash
# Sourced by shoot.sh — not executed directly, hence no shebang.
#
# audio-popup.gif — P1, re-shoot
#
# What it must show: the Outputs view with per-sink volume / gain / balance /
# port / profile detail, Tab to Inputs, o/i/a switching views, j/k moving the
# cursor, and `m` muting a sink with the row VISIBLY changing state.
#
# ─── THIS CLIP TOUCHES THE REAL MACHINE ───────────────────────────────
#
# pipewire lives in the shared XDG_RUNTIME_DIR. The $HOME overlay cannot
# contain it, so the popup in the nest is driving the OWNER'S sink. `m` is
# not a simulation. gif_list.md flags this row and says it needs an explicit
# go-ahead per session, which it has.
#
# The mute is therefore toggled TWICE -- once to show the state change the
# row asks for, once to put it back -- and shoot.sh's caller restores and
# verifies the sink afterwards regardless of how this exits. Nothing here
# touches volume: the choreography has no volume keys, because this machine
# sits at 150% and a stray step would be silently destructive.
#
# Note the starting state is muted ALREADY. So the first `m` UNMUTES, which
# is the same visible state change in the opposite direction, and the second
# restores. Shooting this as mute-then-unmute would have been the version
# that leaves the machine wrong if it fails halfway.

REGION="1366x768+0+0"
DURATION=11
FPS_IN=24
FPS_OUT=13
STATS="full"
SETTLE=1.2

k() { DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "$@"; }
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

prepare() {
  # The nest is shared between takes, so whatever the previous clip left
  # open is still on screen. The first take of this one had qupdate's search
  # results sitting behind the audio popup for the whole clip. Close the
  # daemon-backed windows before the camera opens.
  local p
  for p in $(pgrep -f "atios-nest.*qupdate.py" 2>/dev/null); do kill "$p" 2>/dev/null; done
  for p in $(pgrep -f "atios-nest.*qdrop.py" 2>/dev/null); do kill "$p" 2>/dev/null; done
  sleep 1.5
}

choreograph() {
  sleep 0.6
  k alt+3;    sleep 2.2   # Outputs: per-sink volume, gain, balance, port, profile
  k j;        sleep 0.9   # cursor moves
  k m;        sleep 1.6   # state flips -- muted: yes -> no, visibly
  k m;        sleep 1.4   # and back, leaving the machine as it was found
  k Tab;      sleep 1.6   # Inputs (mics)
  k o;        sleep 1.4   # back to Outputs
  k Escape;   sleep 0.6
}
