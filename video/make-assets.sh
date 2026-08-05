#!/usr/bin/env bash
# Rebuild video/public/ from the real recordings.
#
# Remotion cannot animate a .gif (an <Img> freezes on frame 1), so every source
# is transcoded to h264 first. public/ is not committed; the sources are.
#
# NOTHING IS SCALED, IN SPACE OR IN TIME.
#   * The composition is 1366x768 because that is the resolution the desktop
#     was captured at, so every full-screen clip plays 1:1.
#   * The composition is 24 fps because that is what the captures are. An
#     earlier cut ran at 30 and sped clips up with playbackRate; against a
#     10-14 fps GIF source that produces visible judder, which is what "looks
#     laggy" was. Nothing is sped up any more — beats are short because they
#     are cut short.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
imgs="$here/../IMGS"
usage_src="${USAGE_MKV:-$HOME/tmp/atios-video/out/usage.mkv}"
install_gif="${1:-$HOME/ati-os-install.gif}"
out="$here/public"
mkdir -p "$out"

enc() { # <src> <dest> [extra ffmpeg input args...]
  local src="$1" dest="$2"; shift 2
  ffmpeg -y -v error "$@" -i "$src" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=24" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow "$out/$dest"
}

# The 28 s real-usage take, recorded in the Xephyr nest against a scrubbed
# home. Trimmed to the part that reads: the trailing seconds are the session
# returning to the terminal.
enc "$usage_src" usage.mp4 -t 29.5

# The re-recorded feature set (2026-08-05), straight out of the same nest.
for g in veil overview qupdate theme-picker keybindings; do
  enc "$imgs/$g.gif" "$g.mp4"
done

# two moments of one real VM install: the package pull and the 46-module run.
# The third install shot is a still of the REAL machine (real-desktop.png) —
# QEMU has no GPU, so its desktop segment has no qtile bar at all.
enc "$install_gif" install-a.mp4 -ss 8  -to 20
enc "$install_gif" install-b.mp4 -ss 58 -to 78

cp "$imgs/themes.png" "$out/themes.png"
cp "$here/../docs/assets/img/real-desktop.png" "$out/real-desktop.png"

echo
printf '%-20s %-12s %s\n' CLIP DIMENSIONS FRAMES
for f in "$out"/*.mp4; do
  printf '%-20s %-12s %s\n' "$(basename "$f")" \
    "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$f")" \
    "$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$f")"
done
