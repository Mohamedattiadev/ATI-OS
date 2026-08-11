#!/usr/bin/env bash
# ============================================================
#  wallpaper-set — apply a wallpaper AND record it, in that order of
#  importance but the opposite order of operation.
#
#  ---- WHY THE ISLAND'S PICKER NEEDED THIS ----
#
#  Clicking a thumbnail in Tide Island's wallpaper picker did nothing at
#  all, and gave no error. Upstream's apply path shells out to
#
#      awww img <path> --transition-type ... --transition-step ...
#
#  i.e. swww, a wallpaper daemon that is not installed here and never was
#  — this machine has run hyprpaper since the Hyprland session existed.
#  The failure is silent by construction: the picker runs the command
#  through a `Process`, checks only `exitCode === 0` to decide whether to
#  emit "applied", and a missing binary exits non-zero, so the picker
#  simply closed and nothing changed. Nothing is logged, because nothing
#  went wrong from QML's point of view.
#
#  ---- WHY IT MUST ALSO WRITE ~/.cache/wall ----
#
#  ~/.cache/wall is the single source of truth for "the current
#  wallpaper" across BOTH sessions:
#
#      AtiScriptsV1/theme-apply   reads it (WALL_LINK, ~line 145) in
#                                 every theme mode, wal included
#      hypr/scripts/wallpaper-sync.sh   reads it at login
#      dm-setbg / the qtile WallpaperPopup   maintain it
#
#  A picker that sets the wallpaper without updating it leaves the two
#  sessions disagreeing about what is on screen, and the choice silently
#  reverts at the next login when wallpaper-sync reads the stale record.
#  So the record is written FIRST and the daemon is pointed at it second,
#  which also means a crash between the two leaves the record correct and
#  one `wallpaper-sync.sh` away from being live.
#
#  It is written as a symlink, which is theme-apply's own preferred form;
#  the readers all handle the legacy plain-text form too.
#
#  ---- THE hyprpaper 0.8.4 API TRAP ----
#
#  Do NOT call `hyprctl hyprpaper preload` first. That request was
#  REMOVED in 0.8.4 and answers "invalid hyprpaper request"; `wallpaper`
#  preloads the image itself now. Under `set -e` the dead preload aborts
#  the script before the wallpaper is ever set, which is exactly how a
#  previous session ended up with no wallpaper at all. The full probe is
#  in the header of wallpaper-sync.sh.
#
#  Usage:  wallpaper-set.sh <image>
# ============================================================
set -euo pipefail

WALL_LINK="$HOME/.cache/wall"

img="${1:-}"
if [ -z "$img" ]; then
    echo "wallpaper-set: no image given" >&2
    exit 2
fi

# Resolved before it is recorded: the picker can hand over a relative path
# or one through a symlinked library, and a record that only resolves from
# the picker's working directory is a record that fails at login.
img="$(readlink -f -- "$img")"

if [ ! -r "$img" ]; then
    echo "wallpaper-set: not readable: $img" >&2
    exit 1
fi

mkdir -p "$(dirname "$WALL_LINK")"
ln -sfn -- "$img" "$WALL_LINK"

# Delegate the actual set, so there is exactly ONE place that knows how to
# talk to hyprpaper. Duplicating the hyprctl call here is how the preload
# trap above would come back in a second copy that nobody re-probes.
exec "$(dirname "$(readlink -f "$0")")/wallpaper-sync.sh"
