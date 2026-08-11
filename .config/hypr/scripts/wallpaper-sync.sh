#!/usr/bin/env bash
# ============================================================
#  wallpaper-sync — point hyprpaper at whatever pywal last used
#
#  ~/.cache/wal/wal holds the path of the most recently applied
#  wallpaper.  Reading it here keeps the Hyprland session in step with
#  the qtile session's wallpaper without introducing a second place
#  where "the current wallpaper" is recorded.
#
#  Run at startup, and again after any wallpaper change.
# ============================================================
set -euo pipefail

WAL_RECORD="$HOME/.cache/wal/wal"

if [ ! -r "$WAL_RECORD" ]; then
    echo "wallpaper-sync: no pywal record at $WAL_RECORD, nothing to do" >&2
    exit 0
fi

img=$(head -n1 "$WAL_RECORD")

if [ ! -r "$img" ]; then
    echo "wallpaper-sync: recorded wallpaper is unreadable: $img" >&2
    exit 1
fi

# Wait for the hyprpaper IPC socket rather than sleeping a fixed amount;
# at startup this script routinely wins the race against the daemon.
for _ in $(seq 1 40); do
    hyprctl hyprpaper listloaded >/dev/null 2>&1 && break
    sleep 0.1
done

hyprctl hyprpaper preload "$img" >/dev/null
hyprctl hyprpaper wallpaper ",$img" >/dev/null

# Drop any previously loaded image so long sessions with many wallpaper
# changes do not accumulate decoded framebuffers in hyprpaper's memory.
hyprctl hyprpaper unload unused >/dev/null 2>&1 || true
