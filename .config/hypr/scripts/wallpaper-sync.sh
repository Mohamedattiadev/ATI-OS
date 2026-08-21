#!/usr/bin/env bash
# ============================================================
#  wallpaper-sync — point the wallpaper daemon at the session's current
#  wallpaper, with an animated transition.
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
#  wallpaper — a flat colour behind every window. Nothing in the logs, and
#  exit 0 meant even a careful reading of autostart looked fine.
#
#  The real record is ~/.cache/wall, which is what theme-apply itself
#  uses (WALL_LINK, line ~145) for EVERY mode, wal included, and what
#  ati-dm-setbg and the qtile WallpaperPopup maintain. Reading the same file
#  theme-apply reads is also the only way to keep the two sessions in
#  step without inventing a second source of truth.
#
#  It is normally a symlink to the image; older ati-dm-setbg versions wrote a
#  plain text file containing the path, and theme-apply still handles
#  both, so this does too.
#
#  ---- WHY awww AND NOT hyprpaper ----
#
#  hyprpaper has no transition of any kind: `hyprctl hyprpaper wallpaper`
#  swaps the buffer between two frames. Every wallpaper change in this
#  session was therefore a hard cut, which is what "the other repo's
#  wallpaper changing animation was perfect" was actually comparing
#  against.
#
#  The comparison was amanhex/ukishima, and the thing doing the work there
#  is not QML — it is `awww` driven from scripts/wallpaper.sh with a wave
#  transition. awww is the current name of the project that used to be
#  swww (Arch ships it as extra/awww 0.12.1-1); every guide still calls it
#  swww, which is why searching for the package under that name finds
#  nothing.
#
#  The flags below are ukishima's, adopted wholesale because they were the
#  known-good reference: type wave, angle 30, wave "60,30", fps 60,
#  step 90. Nothing here was arrived at independently.
#
#  MEASURED, and the reason this mattered: tide-island's own config has
#  carried `wallpaperTransitionType: "center"` the whole time. That is a
#  swww/awww parameter name, and with only hyprpaper installed it was
#  configuring a program that was not there — inert, and looking exactly
#  like a setting that simply did not work.
#
#  ---- THE FIRST SET AT LOGIN IS DELIBERATELY NOT ANIMATED ----
#
#  If we had to start the daemon ourselves there is nothing on screen to
#  transition FROM, so a wave would sweep the new wallpaper in over a bare
#  colour — an animation whose whole job is disguising a swap, played over
#  the one case where there is no swap. Same reasoning ukishima's script
#  uses for its animated picks. So: daemon started by us -> instant;
#  daemon already up -> wave.
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

# ---- X11 (qtile): awww needs a wlr-layer-shell compositor and there is
# none here, so it cannot even start — `awww query`/`awww-daemon` just
# fail, silently, forever, which is the qtile half of "wallpaper picker
# does nothing". `xwallpaper --stretch` is the tool already used for this
# exact case: AtiScriptsV1/theme-wallpaper's X11 branch and qtile's own
# WallpaperPopup.py both reach for it. Split on WAYLAND_DISPLAY per the
# RULES, not XDG_SESSION_TYPE — that is unset for a session started any
# way other than a display manager, and this one is.
#
# No transition: xwallpaper is a single blit, not a daemon, and there is
# no wave/fade to ask it for. Instant is the honest answer, the same one
# theme-wallpaper already gives on this session.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    command -v xwallpaper >/dev/null 2>&1 || {
        echo "wallpaper-sync: xwallpaper is not installed" >&2
        exit 1
    }
    xwallpaper --stretch "$img"
    exit 0
fi

# ---- daemon ----
#
# `awww query` is the readiness probe as well as the liveness check: it
# fails while the daemon is absent AND while it is still coming up, so the
# same loop covers both. Without the wait, the first `awww img` after a
# cold start races the socket and exits non-zero — which `set -e` would
# turn into no wallpaper at login, the exact failure this file already
# documents once.
daemon_was_running=true
if ! awww query >/dev/null 2>&1; then
    daemon_was_running=false
    awww-daemon >/dev/null 2>&1 &
    for _ in $(seq 1 40); do
        awww query >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

if [ "$daemon_was_running" = true ]; then
    awww img "$img" \
        --transition-type wave \
        --transition-angle 30 \
        --transition-wave "60,30" \
        --transition-fps 60 \
        --transition-step 90 >/dev/null
else
    awww img "$img" --transition-type none >/dev/null
fi
