#!/usr/bin/env bash
# lock-assets.sh — generate the two images hyprlock.conf needs.
#
# WHY THESE ARE GENERATED AND NOT COMMITTED
# -----------------------------------------
# Both are derived: the avatar from the username's first letter, the gradient
# from nothing but a size. Committing them would put two binaries in a
# dotfiles repo whose whole content is text, and they would then be wrong on
# any machine with a different user.
#
# Idempotent, and it does NOT overwrite a real avatar. If ~/.face exists —
# because the user put a photograph there, which is the point of that path —
# this script leaves it alone. Only the fallback is regenerated.
#
# ---- THE TWO IMAGEMAGICK TRAPS THIS SCRIPT IS WRITTEN AROUND ----
#
# Both were paid for earlier in this repo and both fail SILENTLY, which is why
# they are worth naming at the top of the file rather than at the line:
#
#   1. A canvas with no colour in it gets written as GREYSCALE. ImageMagick
#      picks the narrowest encoding that round-trips the pixels it has, so a
#      white-on-black avatar comes out as a grey PNG — which then cannot take
#      a coloured tint later, and reports no error at any point. Every write
#      here is forced through `PNG32:` and `-colorspace sRGB`.
#
#   2. `-alpha shape` on an image with NO alpha channel silently does
#      nothing. The rounded mask below therefore builds its alpha explicitly
#      rather than assuming the source has one.
#
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tide-island"
mkdir -p "$CACHE"

AVATAR="$CACHE/lock-avatar.png"
GRADIENT="$CACHE/lock-gradient.png"

if ! command -v magick >/dev/null 2>&1; then
    echo "lock-assets.sh: ImageMagick not installed; nothing generated" >&2
    exit 0
fi

# ---- THE AVATAR ----
#
# A real photograph wins if there is one. ~/.face is the freedesktop
# convention and is what a display manager already reads, so a user who has
# set one should not have to set it twice.
#
# 256 px: hyprlock draws it at 120 and this is the next power of two up, so
# the downscale is a clean one and the image is still right if the widget
# grows.
if [[ -f "$HOME/.face" ]]; then
    SOURCE="$HOME/.face"
    magick "$SOURCE" -colorspace sRGB -resize 256x256^ -gravity center -extent 256x256 \
        \( -size 256x256 xc:none -fill white -draw "circle 128,128 128,0" -alpha extract \) \
        -compose CopyOpacity -composite \
        "PNG32:$AVATAR"
else
    # No photograph: the first letter of the username on a flat disc.
    #
    # Deliberately NOT themed. This file is generated once and the palette
    # changes underneath it; an avatar that was gruvbox-brown while the lock
    # screen is nord-blue is worse than one that never claimed to match. Flat
    # near-black with white type reads as neutral on every palette, and the
    # lock background is a blurred desktop rather than a theme surface anyway.
    INITIAL=$(printf '%s' "${USER:-$(id -un)}" | cut -c1 | tr '[:lower:]' '[:upper:]')

    # ---- THE WEIGHT IS ASKED FOR EXPLICITLY, AND IT WAS MEASURED ----
    #
    # The first version said `-font "Inter-SemiBold"`. fc-match resolves that
    # to "Inter" "Regular" — a DIFFERENT WEIGHT — and reports success, because
    # fc-match ALWAYS reports success. The avatar would have rendered, looked
    # slightly wrong, and nothing would have said why.
    #
    # What settled it was not fc-match but ink coverage: the same glyph at the
    # same point size, mean luminance over the canvas, lower being more ink.
    #
    #     -family "Inter" -weight 400            0.968461
    #     -family "Inter" -weight 600            0.955774
    #     -family "Inter Display" -weight 600    0.955864
    #     -font "Inter-Display-SemiBold"         0.955864   (identical)
    #
    # So the hyphenated form does work — ImageMagick resolves it itself,
    # whatever fc-match says about it — and family+weight is the same pixels
    # while saying out loud which axis is being asked for. That is the form to
    # copy, because it is the one that cannot quietly become Regular if the
    # face is repackaged under a different style name.
    #
    # `-annotate` and not `-draw text`: annotate honours -gravity, so the
    # letter is centred on the disc rather than positioned from a baseline
    # that moves with the glyph.
    magick -size 256x256 xc:none -colorspace sRGB \
        -fill '#1c1c1e' -draw "circle 128,128 128,0" \
        -family "Inter Display" -weight 600 -pointsize 128 -fill '#f5f5f7' \
        -gravity center -annotate +0+0 "$INITIAL" \
        "PNG32:$AVATAR"
fi

# ---- THE TOP GRADIENT ----
#
# hyprlock has no gradient primitive, and the alternatives were eliminated by
# running it against probe configs in a NESTED compositor — never by locking
# the live session:
#
#     shape { color = <gradient> }   "cannot parse as an int" — shape takes a
#                                    FLAT colour, and a flat wash over a
#                                    blurred desktop is a band with a hard
#                                    edge exactly where it must be invisible
#     image { size = 4000, 420 }     "cannot parse as an int" — size is ONE int
#     image { size = 100% }          "cannot parse as an int"
#
# ---- `size` IS THE WIDTH, AND THE HEIGHT COMES FROM THIS FILE ----
#
# That one int is the WIDTH; hyprlock scales the height by the source image's
# aspect ratio. The first version of this script did not know that and emitted
# an 8x1024 strip on the theory that a 1:128 sliver would be stretched to fit.
# At `size = 2400` hyprlock asked the GPU for a 2400 x 307200 texture:
#
#     [gl] GL_INVALID_VALUE in glTexImage2D(invalid width=2400 or
#          height=307200 or depth=1)
#     ERR: Framebuffer incomplete, couldn't create! (FB status: 36054)
#
# and hyprlock EXITED — which on a real session is a lock screen that dies at
# the moment you lock, leaving Hyprland's "the lockscreen app died" recovery
# screen. That is the single worst outcome available on this surface, it was
# caught only because the nested compositor showed it, and it is the whole
# justification for the nested-test rule.
#
# So the aspect ratio is load-bearing and is written here rather than implied:
#
#     on-screen height = size / (WIDTH / HEIGHT)
#                      = 2400 / (1600 / 280)
#                      = 420 px
#
# 1600x280 rather than something screen-sized: the gradient is uniform
# horizontally, so width buys nothing but the aspect, and this is a 4 KB file.
#
# Black to transparent, opaque at the TOP: this exists to keep the clock
# readable over whatever was on screen at the instant of locking, which on
# this machine is usually a bright terminal. A 20% dim is not enough on its
# own — 20% off a white page is still a white page.
GRADIENT_W=1600
GRADIENT_H=280

magick -size ${GRADIENT_W}x${GRADIENT_H} -colorspace sRGB \
    gradient:'rgba(0,0,0,0.72)-rgba(0,0,0,0)' \
    "PNG32:$GRADIENT"

echo "lock-assets.sh: wrote $AVATAR and $GRADIENT"
