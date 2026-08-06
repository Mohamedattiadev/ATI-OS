#!/usr/bin/env bash
# shoot.sh — record one clip from notes/gif_list.md.
#
#   ./shoot.sh <clip>          record, encode, report
#   ./shoot.sh <clip> --keep   also keep the lossless .mkv
#
# A clip is a file in clips/ that declares its region, duration and encode
# settings, then drives the nested session with xdotool. shoot.sh starts the
# capture, runs the choreography against it, and encodes the result.
#
# The nest must already be up (./nest.sh up). It is deliberately NOT started
# here: bringing it up takes seconds, seeding it with the right windows is
# per-clip work, and a shoot that silently rebuilt the world would make every
# clip a cold start.
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEST_DISPLAY="${NEST_DISPLAY:-:9}"
ROOT="${NEST_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/atios-nest}"
OUT="${CAPTURE_OUT:-$ROOT/clips}"

r=$'\033[31m'; g=$'\033[32m'; d=$'\033[90m'; o=$'\033[0m'
die() { printf '%s✗%s %s\n' "$r" "$o" "$*" >&2; exit 1; }

clip="${1:?usage: shoot.sh <clip> [--keep]}"
keep="${2:-}"
script="$here/clips/$clip.sh"
[[ -f "$script" ]] || die "no choreography: $script
available: $(cd "$here/clips" 2>/dev/null && ls *.sh 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')"

[[ -e "/tmp/.X11-unix/X${NEST_DISPLAY#:}" ]] || die "nest is not up — ./nest.sh up"

# Defaults; each clip overrides what it needs.
REGION="1366x768+0+0"   # WxH+X+Y, at NATIVE size. Never upscale.
DURATION=8
FPS_IN=24               # 20-24 in, never more
FPS_OUT=13              # drop on output where motion allows
STATS="diff"            # `full` when most of the frame moves
SETTLE=1.0              # let the desktop stop moving before the first frame

# shellcheck source=/dev/null
source "$script"        # sets the above and defines choreograph()

declare -F choreograph >/dev/null || die "$script defines no choreograph()"

size="${REGION%%+*}"
offs="${REGION#*+}"; x="${offs%%+*}"; y="${offs##*+}"

mkdir -p "$OUT"
mkv="$OUT/$clip.mkv"
gif="$OUT/$clip.gif"

printf '%s::%s %s — %s at %s, %ss @ %s fps in / %s out\n' \
  "$d" "$o" "$clip" "$size" "+$x,$y" "$DURATION" "$FPS_IN" "$FPS_OUT"

sleep "$SETTLE"

# ffvhuff: lossless, so the palette pass sees real pixels rather than
# h264 ringing around the text.
ffmpeg -v error -y -f x11grab -framerate "$FPS_IN" -video_size "$size" \
       -i "${NEST_DISPLAY}.0+${x},${y}" -codec:v ffvhuff -t "$DURATION" "$mkv" &
ffpid=$!

sleep 0.6                     # let the capture actually open
choreograph                   # drive the nest
wait "$ffpid" || die "capture failed"

"$here/gifenc.sh" "$mkv" "$gif" "$FPS_OUT" "$STATS"

if [[ "$keep" != "--keep" ]]; then rm -f "$mkv"; else printf '%s   kept %s%s\n' "$d" "$mkv" "$o"; fi
printf '%s→%s %s\n' "$g" "$o" "$gif"
