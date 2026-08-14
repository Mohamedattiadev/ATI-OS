#!/usr/bin/env bash
# lock-player.sh — what is playing, for the lock screen.
#
#   lock-player.sh text     "Title · Artist", or nothing at all
#   lock-player.sh status   a transport glyph, or nothing at all
#   lock-player.sh art      refresh the album-art file; prints its path
#
# WHY A READOUT AND NOT A TRANSPORT
# ---------------------------------
# Asked for as "i wish if it had a player in it". hyprlock 0.9.6 has four
# widget types — background, image, shape, label — and an `input-field`.
# There is no button, no click target and no keybinding surface: the only
# key it reads is the password. So a play/pause control cannot be built
# here, and pretending otherwise would mean drawing buttons that do nothing.
#
# What CAN be built is the part you actually want on a lock screen: what is
# playing, who it is by, and whether it is paused. The hardware media keys
# keep working while locked — they are compositor binds, not client ones —
# so the transport is already there and this is the missing display for it.
#
# EVERYTHING PRINTS EMPTY WHEN NOTHING IS PLAYING
# -----------------------------------------------
# hyprlock draws a label's text and nothing else, so an empty string is an
# invisible widget. That is the whole "hide it when idle" mechanism, and it
# is why every path here exits 0 with no output rather than printing a dash
# or "Nothing playing" — a lock screen with a permanent empty music card is
# worse than one with no card.
#
# NO `playerctl --follow`. hyprlock re-runs the command on its own timer,
# so a long-lived follower would be a second process per label with nothing
# to deliver its output to.

set -uo pipefail

CACHE_DIR="$HOME/.cache/tide-island"
ART="$CACHE_DIR/lock-art.png"
# 1x1 fully transparent, so the image widget has something valid to draw
# when there is no art. hyprlock EXITS if an `image` path does not resolve —
# the same class of failure as the framebuffer bug in lock-assets.sh — so
# "no art" has to be a real file, not a missing one.
BLANK="$CACHE_DIR/lock-art-blank.png"

have_player() {
    command -v playerctl >/dev/null 2>&1 || return 1
    # -s so "No players found" does not reach stderr on every tick; the exit
    # code is the answer.
    [ -n "$(playerctl -s metadata --format '{{mpris:trackid}}' 2>/dev/null)" ]
}

case "${1:-}" in
text)
    have_player || exit 0
    # ONE playerctl call, split in the shell — not two calls, and not a
    # conditional in the template.
    #
    # playerctl's format language has NO `{{ if }}`. The obvious spelling,
    #
    #     '{{markup_escape(title)}}{{ if artist }} · {{markup_escape(artist)}}{{ endif }}'
    #
    # fails with `expecting "}}" (position 30)` — on STDERR, with a non-zero
    # exit, both of which this script was already discarding. The label went
    # silently blank and looked exactly like "nothing is playing", which is a
    # state it is designed to have. Caught only by running the format by hand.
    #
    # A separator that cannot occur in a tag is the substitute for the
    # conditional: split on it, and an absent artist leaves an empty half
    # rather than a dangling "Title · ".
    #
    # markup_escape is needed because hyprlock renders labels as Pango
    # markup — a track called "Sisters & Brothers" is invalid markup and
    # Pango drops the ENTIRE label, so the card would go blank on exactly
    # the tracks with an ampersand in them.
    meta="$(playerctl -s metadata --format \
              '{{markup_escape(title)}}@@{{markup_escape(artist)}}' 2>/dev/null)"
    [ -n "$meta" ] || exit 0
    title="${meta%%@@*}"
    artist="${meta#*@@}"
    if [ -n "$title" ] && [ -n "$artist" ]; then
        printf '%s · %s' "$title" "$artist" | head -c 120
    else
        printf '%s%s' "$title" "$artist" | head -c 120
    fi
    ;;
status)
    have_player || exit 0
    case "$(playerctl -s status 2>/dev/null)" in
        Playing) printf '' ;;   # nf-fa-play
        Paused)  printf '' ;;   # nf-fa-pause
        *)       : ;;
    esac
    ;;
art)
    mkdir -p "$CACHE_DIR"
    # The blank is generated once and reused. PNG32 + sRGB for the reason
    # lock-assets.sh names at its top: ImageMagick writes the narrowest
    # encoding that round-trips, and a fully transparent canvas comes out
    # greyscale, which then cannot be composited against a colour image.
    [ -f "$BLANK" ] || magick -size 1x1 xc:none -colorspace sRGB "PNG32:$BLANK" 2>/dev/null

    if ! have_player; then
        cp -f "$BLANK" "$ART" 2>/dev/null
        printf '%s' "$ART"; exit 0
    fi

    url="$(playerctl -s metadata mpris:artUrl 2>/dev/null || true)"
    src=""
    case "$url" in
        file://*) src="$(printf '%s' "${url#file://}" | sed 's/%20/ /g')" ;;
        http://*|https://*)
            # --max-time, because this runs on a timer behind a LOCKED
            # screen: a hung fetch on a captive-portal network would
            # otherwise pile up one stuck curl per tick, all night.
            tmp="$CACHE_DIR/.lock-art-dl"
            if command -v curl >/dev/null 2>&1 \
               && curl -sfL --max-time 4 -o "$tmp" "$url" 2>/dev/null; then
                src="$tmp"
            fi
            ;;
    esac

    if [ -n "$src" ] && [ -r "$src" ]; then
        # SQUARE. The corners are hyprlock's job — the `image` widget has a
        # `rounding` of its own, and rounding here as well meant two masks
        # fighting: the widget's `rounding = -1` (a full circle) won, and the
        # art came out as a second circle directly under the circular avatar,
        # which read as the same element repeated rather than as album art.
        # One shape, decided in one place.
        #
        # Written to a temp file and moved, because hyprlock reads this on a
        # 4 s timer and may look at any moment: a half-written PNG is a
        # widget that vanishes, and on this surface that is indistinguishable
        # from "nothing is playing".
        if magick "$src" -resize 128x128^ -gravity center -extent 128x128 \
             -colorspace sRGB "PNG32:$ART.tmp" 2>/dev/null; then
            mv -f "$ART.tmp" "$ART"
        else
            cp -f "$BLANK" "$ART" 2>/dev/null
        fi
    else
        cp -f "$BLANK" "$ART" 2>/dev/null
    fi
    printf '%s' "$ART"
    ;;
*)
    echo "usage: lock-player.sh text|status|art" >&2
    exit 2
    ;;
esac
