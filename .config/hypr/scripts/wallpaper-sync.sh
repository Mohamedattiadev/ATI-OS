#!/usr/bin/env bash
# ============================================================
#  wallpaper-sync — point hyprpaper at the session's current wallpaper
#
#  ---- WHY NOT ~/.cache/wal/wal ----
#
#  This script used to read ~/.cache/wal/wal, on the assumption that it
#  is "the path of the most recently applied wallpaper". It is not: that
#  file is pywal's OWN record, written only when pywal actually runs an
#  image through its backend — i.e. only in `wal` mode. On any of the 20+
#  named themes (doomone, dracula, gruvbox, ...) theme-apply never
#  invokes that path, so the file does not exist at all.
#
#  The symptom was silent and total: the script printed "no pywal record,
#  nothing to do", exited 0, and the Hyprland session simply had NO
#  wallpaper — hyprpaper running with nothing loaded, a flat colour
#  behind every window. Nothing in the logs, and exit 0 meant even a
#  careful reading of autostart looked fine.
#
#  The real record is ~/.cache/wall, which is what theme-apply itself
#  uses (WALL_LINK, line ~145) for EVERY mode, wal included, and what
#  dm-setbg and the qtile WallpaperPopup maintain. Reading the same file
#  theme-apply reads is also the only way to keep the two sessions in
#  step without inventing a second source of truth.
#
#  It is normally a symlink to the image; older dm-setbg versions wrote a
#  plain text file containing the path, and theme-apply still handles
#  both, so this does too.
#
#  Run at startup, and again after any wallpaper change.
# ============================================================
set -euo pipefail

WALL_LINK="$HOME/.cache/wall"

if [ ! -e "$WALL_LINK" ]; then
    echo "wallpaper-sync: no wallpaper record at $WALL_LINK — set one first" >&2
    exit 0
fi

if [ -L "$WALL_LINK" ]; then
    img=$(readlink -f "$WALL_LINK")
else
    # Legacy plain-text form, same fallback theme-apply keeps.
    img=$(head -n1 "$WALL_LINK" | tr -d '\r\n\0')
fi

if [ ! -r "$img" ]; then
    echo "wallpaper-sync: recorded wallpaper is unreadable: $img" >&2
    exit 1
fi

# ---- hyprpaper 0.8.4 dropped most of the IPC this script used ----
#
# Probed against the running daemon; only two of the five requests this
# script was built on still exist:
#
#     wallpaper ,<path>   OK — and it preloads the image itself now
#     listactive          OK — reports "eDP-1: /path"
#     preload <path>      error: invalid hyprpaper request
#     unload unused       error: invalid hyprpaper request
#     listloaded          error: invalid hyprpaper request
#
# So `preload` is gone (folded into `wallpaper`), and `unload` with it —
# which also removes the reason the old version called it. Note `set -e`
# made this fatal rather than cosmetic: preload failed, the script died
# before ever reaching the `wallpaper` line, and no wallpaper was set.
#
# The readiness probe uses listactive for the same reason — listloaded
# always errored, so the old loop never broke early and burned its full
# 4 seconds on every single login before continuing anyway.
for _ in $(seq 1 40); do
    hyprctl hyprpaper listactive >/dev/null 2>&1 && break
    sleep 0.1
done

hyprctl hyprpaper wallpaper ",$img" >/dev/null
