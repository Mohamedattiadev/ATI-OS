#!/usr/bin/env bash
# lock-player.sh — what is playing, for the lock screen.
#
#   lock-player.sh text     "Title · Artist", or nothing at all
#   lock-player.sh status   a transport glyph, or nothing at all
#   lock-player.sh art      refresh the album-art file; prints its path
#
# IT IS A REAL TRANSPORT, AND THE FIRST PASS SAID IT COULD NOT BE
# ---------------------------------------------------------------
# That pass wrote, in this header: "hyprlock 0.9.6 has four widget types
# and an input-field. There is no button, no click target and no keybinding
# surface, so a play/pause control cannot be built here."
#
# The widget LIST was right and the conclusion was wrong, because it was
# drawn from the list instead of from the program. hyprlock's `label` takes
# an `onclick`:
#
#     strings /usr/bin/hyprlock | grep -x onclick
#
# and it sits in the label option table between `shadow_boost` and the
# widget defaults. The parser also rejects unknown keys loudly — that is how
# `general:grace`, `no_fade_in` and `disable_loading_bar` were caught — so a
# config carrying `onclick` and drawing no complaint is a config whose
# `onclick` is real.
#
# So the card has < play/pause > buttons that run `playerctl`, asked for as
# "make it minimal and has the player < = >". The hardware media keys keep
# working too — they are compositor binds, not client ones — but they were
# never the point: you cannot press a key you cannot see, on a screen whose
# whole job is to be looked at.
#
# EVERYTHING PRINTS EMPTY WHEN NOTHING IS PLAYING
# -----------------------------------------------
# hyprlock draws a label's text and nothing else, so an empty string is an
# invisible widget. That is the whole "hide it when idle" mechanism, and it
# is why every path here exits 0 with no output rather than printing a dash
# or "Nothing playing" — a lock screen with a permanent empty music card is
# worse than one with no card.
#
# ---- THE TWO IMAGEMAGICK TRAPS THIS SCRIPT IS WRITTEN AROUND ----
#
# Inherited from scripts/lock-assets.sh, which generated the avatar and the
# gradient this lock screen no longer draws and which is deleted. Both traps
# fail SILENTLY and both still apply to the album art below:
#
#   1. A canvas with no colour in it is written as GREYSCALE. ImageMagick
#      picks the narrowest encoding that round-trips the pixels it has, so a
#      fully transparent 1x1 comes out grey — which then cannot be
#      composited against a colour image, and reports no error at any point.
#      Every write here is forced through `PNG32:` and `-colorspace sRGB`.
#
#   2. `-alpha shape` on an image with NO alpha channel silently does
#      nothing. Nothing here relies on it any more — the art is square and
#      hyprlock rounds it — but the next person to add a mask should know.
#
# NO `playerctl --follow`. hyprlock re-runs the command on its own timer,
# so a long-lived follower would be a second process per label with nothing
# to deliver its output to.

set -uo pipefail

CACHE_DIR="$HOME/.cache/tide-island"
ART="$CACHE_DIR/lock-art.png"
# 1x1 fully transparent, so the image widget has something valid to draw
# when there is no art. hyprlock EXITS if an `image` path does not resolve,
# so "no art" has to be a real file, not a missing one.
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
prev|next|toggle)
    # ---- THE TRANSPORT GLYPHS ----
    #
    # Printed by a script rather than written into hyprlock.conf as literal
    # text, for one reason: they have to VANISH when nothing is playing.
    # hyprlock draws a label's text and nothing else, so an empty string is
    # an invisible widget — but a literal glyph in the config is always
    # there, and three dead buttons under an empty card is worse than no
    # card at all.
    #
    # ALL BMP private-use codepoints, and that is deliberate rather than
    # incidental: the SUPPLEMENTARY private-use glyphs this Nerd Font also
    # carries (U+F022C and neighbours) do not render in this stack at all —
    # measured in the island's picker, where the font HAS the glyph, the
    # widget draws a BMP one in the same face, and the supplementary one
    # paints nothing. Anything drawn on this surface stays in the BMP block.
    #
    #   U+F048 step-backward   U+F04B play   U+F04C pause   U+F051 step-forward
    have_player || exit 0
    case "$1" in
        prev)   printf '\uf048' ;;
        next)   printf '\uf051' ;;
        toggle)
            # The button shows what pressing it DOES, which is the opposite
            # of the current state: playing means the button offers pause.
            case "$(playerctl -s status 2>/dev/null)" in
                Playing) printf '\uf04c' ;;
                *)       printf '\uf04b' ;;
            esac
            ;;
    esac
    ;;
art)
    mkdir -p "$CACHE_DIR"
    # The blank is generated once and reused. PNG32 + sRGB for trap 1 in
    # the header: a fully transparent canvas is written greyscale
    # otherwise, and greyscale cannot composite against a colour image.
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
    echo "usage: lock-player.sh text|status|art|prev|next|toggle" >&2
    exit 2
    ;;
esac
