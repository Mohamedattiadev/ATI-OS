#!/usr/bin/env bash
# gifenc.sh — lossless capture -> shipping GIF, and then LOOK at it.
#
#   ./gifenc.sh <in.mkv> <out.gif> [fps] [stats_mode]
#
# Two-pass palettegen/paletteuse, because a single-pass GIF picks its palette
# from the first frame and banding shows up in every frame after it.
#
# stats_mode=diff weights the palette toward the pixels that CHANGE, which is
# what a mostly-static clip needs -- a bar strip where one chip recolours is
# 95% identical pixels, and `full` spends the whole 256 entries describing the
# parts nobody is looking at. Use `full` for a clip where most of the frame
# moves (a full-screen tour, a layout rearrange).
#
# NOTHING IS SCALED. Capture at the region's real pixel size and leave it
# there. Re-shooting the mode chips at native size took them from 1.0-2.5 MB
# to 17-37 KB with identical content -- a 30-60x saving purely from not
# upscaling a 640x38 strip.
set -Eeuo pipefail

in="${1:?usage: gifenc.sh <in.mkv> <out.gif> [fps] [stats_mode]}"
out="${2:?usage: gifenc.sh <in.mkv> <out.gif> [fps] [stats_mode]}"
fps="${3:-13}"
stats="${4:-diff}"

[[ -f "$in" ]] || { echo "no such file: $in" >&2; exit 1; }

g=$'\033[32m'; y=$'\033[33m'; r=$'\033[31m'; d=$'\033[90m'; o=$'\033[0m'

ffmpeg -v error -y -i "$in" \
  -vf "fps=${fps},split[a][b];[a]palettegen=stats_mode=${stats}[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$out"

bytes=$(stat -c%s "$out")
kb=$(( bytes / 1024 ))
read -r w h nframes < <(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,nb_read_frames -count_frames \
  -of csv=p=0 "$out" | tr ',' ' ')

printf '%s%s%s  %sx%s  %s frames @ %s fps  %s KB\n' "$g" "$out" "$o" "$w" "$h" "$nframes" "$fps" "$kb"

# Size cap, per notes/gif_list.md: ~1 MB per clip, and a bar-only strip over
# 100 KB means the pipeline is wrong, not the content.
if (( h <= 120 )) && (( kb > 100 )); then
  printf '%s!%s a %spx-tall strip should not be %s KB — check for upscaling or too many frames\n' "$y" "$o" "$h" "$kb"
elif (( kb > 1024 )); then
  printf '%s!%s over the 1 MB cap — drop fps, trim, or crop tighter\n' "$y" "$o"
fi

# "A clip that recorded successfully is not a clip that shows the feature."
# This project has already shipped a screenshot that was QEMU's "display not
# initialized" placeholder. Extract frames so they can actually be looked at.
frames="${out%.gif}.frames"
rm -rf "$frames"; mkdir -p "$frames"
ffmpeg -v error -i "$out" -vsync 0 "$frames/f%03d.png"
printf '%s   frames for inspection: %s/ (%s files) — LOOK AT THEM%s\n' \
  "$d" "$frames" "$(find "$frames" -name '*.png' | wc -l)" "$o"

# A clip whose frames are all identical recorded nothing. Cheap to check,
# and it is the failure that looks most like success.
uniq_count=$(find "$frames" -name '*.png' -exec md5sum {} + | awk '{print $1}' | sort -u | wc -l)
if (( uniq_count <= 1 )); then
  printf '%s✗ every frame is identical — this clip shows nothing%s\n' "$r" "$o"
  exit 1
fi
printf '%s   %s distinct frames%s\n' "$d" "$uniq_count" "$o"
