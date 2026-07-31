"""Column packing shared by the Qtile / Vim / Fish cheatsheet popups.

All three used to carry the same copy-pasted block: a fixed 4-column by
3-row grid of equal `ROW_HEIGHT = 0.25` cells. Every one of them overflowed
its cells, and none of them showed it, because **PopupText neither clips
nor wraps to its `height`**. The height you pass only positions the
control; text taller than that keeps drawing downward over whatever is
below, until the popup *window* edge cuts it off. So a section either ran
into empty space (invisible) or off the bottom of the popup (silently lost
its last entries -- four of them in Qtile's ROFI MODE, and the tail of
four Vim sections).

What replaces it: sections are stacked top to bottom inside a column, each
placed at the height the ones above it actually need, and a column is
closed when the next section will not fit. Adding an entry now shifts what
follows instead of pushing it off the screen.

Heights are estimated in LINES, because the line count is the one thing
derivable from the data. The per-line pixel figures each caller passes in
are **measured pango extents at that popup's font size**, not guesses --
change the font size without re-measuring them and every position below is
wrong. Callers must also pass `fontsize` to their PopupTexts explicitly:
inheriting PopupText's default of 12 does exactly that.
"""

from libqtile.log_utils import logger

# PopupRelativeLayout's own default. Control positions are fractions of the
# INNER box (size - 2*margin), which is what these numbers assume.
MARGIN = 5

GRID_TOP = 0.16      # under the title block
GRID_BOTTOM = 0.90   # above the footer
FOOTER_Y = 0.93
SECTION_GAP = 0.025  # breathing room between stacked sections
COL_GAP = 0.015


def pack(sections, *, n_cols, popup_h, body_px, title_px, note_px, has_note, name):
    """Place `sections` into `n_cols` columns.

    `sections` is an ordered [(title, items), ...]; order is preserved, so
    related sections stay adjacent. `has_note(title)` reports whether that
    section renders the extra mode-note + divider pair.

    Yields (title, items, pos_x, pos_y, width, height), all as fractions of
    the popup's inner box, ready to hand to PopupText.
    """
    inner_h = popup_h - 2 * MARGIN
    line, title_h, note_h = body_px / inner_h, title_px / inner_h, note_px / inner_h
    col_w = (1.0 - (n_cols - 1) * COL_GAP) / n_cols

    col, y = 0, GRID_TOP
    for title, items in sections:
        h = title_h + len(items) * line + (note_h if has_note(title) else 0)
        if y + h > GRID_BOTTOM:
            col, y = col + 1, GRID_TOP
            if col >= n_cols:
                # The old grid failed exactly here and said nothing. Say it
                # out loud: the section still renders (off the right edge),
                # but the log names what to change.
                logger.warning(
                    "%s: content no longer fits %d columns (overflow starts "
                    "at %r) -- raise n_cols, or lower the font size and "
                    "re-measure body_px/title_px/note_px.",
                    name, n_cols, title,
                )
        yield title, items, col * (col_w + COL_GAP), y, col_w, h
        y += h + SECTION_GAP


# =============================================================================
# SELFTEST
#
# The original bug was invisible by construction -- nothing errors, the
# entries simply are not drawn -- so it survived until someone counted the
# lines on screen against the source. This measures instead: pango is asked
# for the real extents of every section at its real font size, and the
# result is checked against the popup it has to fit in.
#
#     python3 -m popups._cheatsheet_grid     (from ~/.config/qtile)
#
# Run by validate.sh, so an entry added to any sheet cannot quietly push
# another one off the bottom again.
# =============================================================================
SHEETS = ("QtileCheatsheet", "VimCheatsheet", "FishCheatsheet")


def selftest(sheets=SHEETS, verbose=True):
    """Return a list of failure strings; empty means every sheet fits."""
    import gi

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo

    ctx = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))

    def extents(markup, size, width_px=None):
        lay = PangoCairo.create_layout(ctx)
        lay.set_font_description(Pango.FontDescription(f"sans {size}"))
        if width_px:
            lay.set_width(width_px * Pango.SCALE)
            lay.set_wrap(Pango.WrapMode.WORD_CHAR)
        lay.set_markup(markup, -1)
        return lay.get_pixel_size()

    failures = []
    for name in sheets:
        mod = __import__(f"popups.{name}", fromlist=["x"])
        W, H = mod.POPUP_W, mod.POPUP_H
        in_w, in_h = W - 2 * MARGIN, H - 2 * MARGIN
        footer_top = MARGIN + mod.FOOTER_Y * in_h

        for title, items, _px, py, pw, ph in mod.layout_sections():
            markup = mod.render_section(title, items)
            col_px = int(pw * in_w)
            raw_w, _ = extents(markup, mod.BODY_SIZE)
            _, real_h = extents(markup, mod.BODY_SIZE, col_px)
            bottom = MARGIN + py * in_h + real_h

            if raw_w > col_px:
                failures.append(
                    f"{name}/{title}: wraps -- needs {raw_w}px, column is "
                    f"{col_px}px. Lower BODY_SIZE or N_COLS."
                )
            if bottom > H:
                failures.append(
                    f"{name}/{title}: {bottom - H:.0f}px BELOW the popup edge "
                    f"-- these entries never render."
                )
            elif bottom > footer_top:
                failures.append(
                    f"{name}/{title}: overlaps the footer by "
                    f"{bottom - footer_top:.0f}px."
                )
            # Guards the hand-measured BODY_PX / TITLE_PX / NOTE_PX against
            # a font-size change that forgot to re-measure them.
            est = ph * in_h
            if abs(est - real_h) > 6:
                failures.append(
                    f"{name}/{title}: height estimate is {est - real_h:+.0f}px "
                    f"out -- re-measure BODY_PX/TITLE_PX/NOTE_PX at "
                    f"{mod.BODY_SIZE}pt."
                )
        if verbose:
            print(f"{name}: {W}x{H}, {mod.BODY_SIZE}pt, {mod.N_COLS} columns")

    return failures


if __name__ == "__main__":
    import sys

    bad = selftest()
    for line in bad:
        print("FAIL:", line, file=sys.stderr)
    print("cheatsheets: all sections fit" if not bad else f"{len(bad)} failure(s)")
    sys.exit(1 if bad else 0)
