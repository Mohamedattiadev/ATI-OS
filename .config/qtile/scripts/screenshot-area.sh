#!/usr/bin/env bash
# Select a screen area and put the PNG straight on the clipboard.
#
# Bound to the camera chip in the bottom bar and to Print. Kept as a real script
# rather than an inline `sh -c` string in config.py so that failures land in the
# log below instead of vanishing silently when the button appears to do nothing.

set -uo pipefail

log="/tmp/qtile-screenshot-$(id -u).log"
exec 2>>"$log"
printf -- '--- %s: invoked ---\n' "$(date '+%F %T')" >>"$log"

for dep in maim xclip notify-send; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        printf 'missing dependency: %s\n' "$dep" >>"$log"
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u critical "Screenshot" "Missing: $dep"
        exit 1
    fi
done

f=$(mktemp --suffix=.png) || {
    printf 'mktemp failed (TMPDIR=%s)\n' "${TMPDIR:-unset}" >>"$log"
    notify-send -u critical "Screenshot" "Could not create temp file"
    exit 1
}
trap 'rm -f "$f"' EXIT

# maim exits non-zero when the selection is cancelled, and writes nothing. The
# -s size check keeps a cancel from handing xclip an empty file, which would
# silently wipe whatever was already on the clipboard.
if maim --hidecursor --select "$f" && [ -s "$f" ]; then
    if xclip -selection clipboard -t image/png -i "$f"; then
        printf 'ok: %s bytes copied\n' "$(stat -c%s "$f")" >>"$log"
        notify-send -t 2000 "Screenshot" "Area copied to clipboard"
    else
        printf 'xclip failed\n' >>"$log"
        notify-send -u critical "Screenshot" "xclip failed — see $log"
    fi
else
    printf 'cancelled or empty capture\n' >>"$log"
    notify-send -t 1500 "Screenshot" "Cancelled"
fi
