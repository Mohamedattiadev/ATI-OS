"""Card layout shared by the Qtile / Vim / Fish cheatsheet popups.

Three things this owns, all of which used to be copy-pasted (badly) into
each sheet:

**The grid.** All three carried the same fixed 4-column by 3-row grid of
equal `ROW_HEIGHT = 0.25` cells, and every section in every one of them
overflowed its cell -- silently, because **PopupText neither clips nor
wraps to its `height`**. The height only positions the control; text taller
than that keeps drawing downward until the popup *window* edge cuts it off.
The Qtile sheet's biggest column ended 101px below that edge, so its last
four entries had never once been on screen. Cards are now packed into
columns at the height the ones above them actually need, and onto a second
page when a page fills up.

**The font.** These popups asked for `sans`, and on this machine
`fc-match sans` answers *Noto Sans CJK KR* -- the same silent fallback that
was fixed for rofi in 242b8ff and never for these. Everything here is
monospace now (`FONT`), which is both what the rest of the popups use and
what makes the key column line up: every glyph is exactly `char_px` wide,
so a row can be padded to an exact column with spaces.

**The row shape.** A row is `label ......... KEY`, the key hard against the
card's right edge. That only works in a monospace face, and only if the
keys are written compactly -- see `compact()`.

Because the face is monospace and every row is one line at the body size,
the geometry is exact rather than estimated: a card is
`(2 + rows) * line_px` tall and `(2 + cols) * char_px` wide, full stop.
`selftest()` still measures it all with pango, since the day that stops
being true is the day the entries start vanishing again.
"""

from libqtile.log_utils import logger

# The system monospace. Never "sans": see the module docstring.
FONT = "JetBrainsMono Nerd Font"

# PopupRelativeLayout's own default. Control positions are fractions of the
# INNER box (size - 2*margin), which is what these numbers assume.
MARGIN = 5

# Matches WifiPopup/BluetoothPopup's card styling: 10px radius, a wider
# gutter between cards so the grid doesn't read as one solid block.
CARD_RADIUS = 10     # rounded corners on the section cards
PAD_CHARS = 1        # left/right padding inside a card, in characters
PAD_ROWS = 1         # blank rows at the top and bottom of a card

GRID_TOP = 0.155     # under the title block
GRID_BOTTOM = 0.925  # above the footer (raised when it got smaller)
FOOTER_Y = 0.93
CARD_GAP_PX = 16     # MINIMUM gap between cards, both directions
CARD_GAP_MAX = 56    # ...and the most the gap is allowed to grow to

# Gutter between the outer cards and the popup's left/right edges. Without
# it the grid is laid out across the full inner box, so the first and last
# columns sit hard against the border with only MARGIN (5px) of air and the
# sheet looks like it was cropped rather than composed. WifiPopup and
# BluetoothPopup inset their content by a comparable amount (pos_x=0.03).
#
# This comes out of the width available to the cards, so raising it either
# narrows them or has to be paid for with a wider popup -- see POPUP_W.
GRID_SIDE_PAD_PX = 20

# Blank columns a row must keep between its label and its key, in BASE
# characters. This is a floor, not the actual gap -- most rows have more,
# because a card is as wide as its widest row and the rest get the slack.
# It only bites on the longest row in each card, which is exactly the row
# that used to end up with a single space between the two columns and read
# as one run-on string.
#
# Cards are sized from this (see content_cols), so raising it widens every
# card and therefore the popup. 3 is about a word-space at this size.
ROW_GAP_CHARS = 3


# =============================================================================
# TEXT
# =============================================================================
def esc(text):
    """Escape for pango markup. Vim's keys are full of < and >."""
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


# Written out rather than typed in full, because the row only fits when the
# key does. "Mod + Shift + Enter" is 19 characters and pushes the card past
# a quarter of the screen on its own; "Mod ⇧ ↵" is 7 and says the same
# thing. Order matters -- longest first, so "Shift" is gone before "Sh".
#
# Every glyph here must exist in FONT. A missing one does not error -- it
# falls back to some other family at some other width, and the whole key
# column stops lining up. U+21B5 ↵ was the obvious choice for Enter and is
# NOT in JetBrainsMono; U+23CE ⏎ is. `selftest()` checks the whole set
# against the installed font so the next addition cannot slip through.
KEY_SUBS = (
    ("<leader>", "␣"),      # Vim's leader IS Space; the header says so too
    ("<tab>", "⇥"),
    ("Shift", "⇧"),
    ("Ctrl", "⌃"),
    ("Enter", "⏎"),
    ("Return", "⏎"),
    ("Escape", "Esc"),
    ("Space", "␣"),
    ("Super", "Sup"),
    ("[1–9]", "1-9"),
    ("[1-9]", "1-9"),
    ("H1–H6", "H1-6"),
)


def compact(key):
    """Shorten a key combo so the row fits the card.

    Only touches modifier and named-key spellings. Anything that is not a
    key combo -- Fish lists shell commands in this column -- comes through
    untouched, because there is nothing safe to shorten in `tmux
    kill-server`.
    """
    out = str(key)
    for long, short in KEY_SUBS:
        out = out.replace(long, short)
    # " + " is pure padding once the names are symbols: "Mod ⇧ ↵" reads as
    # well as "Mod + ⇧ + ↵" and is four characters shorter.
    out = out.replace(" + ", " ")
    return " ".join(out.split())


def fit(text, width):
    """Clip to `width` columns, marking the clip."""
    text = str(text)
    return text if len(text) <= width else text[: max(0, width - 1)] + "…"


def key_chip(label, colors):
    """A key rendered as a filled pill, `colors["surface_alt"]` behind bold
    text -- the same chip WifiPopup/BluetoothPopup use for their footer key
    hints (`_key()` there). Used for the header/footer legends, not the row
    keys inside a card: at BODY_SIZE a chip per row would be noisier than
    the plain right-aligned column card_markup() already draws.
    """
    return (
        f'<span background="{colors["surface_alt"]}" foreground="{colors["fg"]}" '
        f'weight="bold"> {label} </span>'
    )


# The label (left) column is set one step down from the key column, so the
# key -- the thing you actually came to read -- is what carries the row.
#
# "smaller" rather than an explicit size on purpose: pango's `size` in
# markup is in POINTS, while these layouts are sized in absolute PIXELS
# (see the selftest), so a number here would be the same points-vs-pixels
# mismatch that once made every card 30% too big. The keyword scales
# whatever the base absolute size is, so it cannot drift.
LABEL_SIZE = "smaller"


PANGO_SCALE = 1024  # pango units per device pixel at an absolute font size


def _gap_markup(gap_px, small_px, base_px):
    """ONE space stretched to EXACTLY `gap_px` wide.

    The label is drawn smaller than the key, so its width is no longer a
    whole number of base characters and ordinary `" " * n` padding cannot
    land the key on the card's right edge -- the key column jitters by up
    to a character from row to row.

    Whole spaces cannot fix that on their own: a gap has to be built out of
    8px and 9px pieces, and 10, 22 and 55 (among others) are not reachable
    from those at all -- 55 is exactly their Frobenius number. Three rows
    on the Qtile sheet landed on precisely those values.

    `letter_spacing` sidesteps the arithmetic. It adds an exact number of
    PANGO units per grapheme -- 1024 to the device pixel -- so a single
    space asked for `gap_px - small_px` of extra spacing measures `gap_px`
    on the nose, at any gap, with no divisibility to satisfy. Verified
    against pango for gaps from 1px up.
    """
    extra = (gap_px - small_px) * PANGO_SCALE
    return (
        f'<span size="{LABEL_SIZE}" letter_spacing="{extra}"> </span>'
    )


def card_markup(title, items, *, cols, colors, char_px, label_char_px,
                note=None, danger=()):
    """The markup for one section card.

    `cols` is the card's inner width in BASE characters -- the title, the
    rule and the key column are all base-sized, so that is the unit the
    card is measured in. Labels are `LABEL_SIZE` and therefore narrower;
    `label_char_px` is how wide one of them is, and the row is assembled in
    pixels because of it.

    A PopupText draws at (0, 0) of its own rect and its background IS the
    card, so there is no padding property to set -- the inset has to come
    from the markup, which is why every line starts with PAD_CHARS spaces
    and the block starts one blank row down.

    `danger` is a predicate or a tuple of substrings; matching rows get the
    warm accent instead of the green one.
    """
    pad = " " * PAD_CHARS
    is_danger = danger if callable(danger) else (
        lambda label: any(d in label.lower() for d in danger)
    )
    row_px = cols * char_px

    lines = [""]  # top inset: the card is v_align="top"
    lines.append(
        f'{pad}<span foreground="{colors["purple"]}" weight="bold">'
        f"{esc(fit(title, cols))}</span>"
    )
    if note:
        lines.append(
            f'{pad}<span foreground="{colors["muted"]}" style="italic">'
            f"{esc(fit(note, cols))}</span>"
        )
    lines.append(f'{pad}<span foreground="{colors["line"]}">{"─" * cols}</span>')

    min_gap_px = ROW_GAP_CHARS * char_px
    for label, key in items:
        key_text = compact(key)
        # Right-align the key, and give the label whatever is left.
        # ROW_GAP_CHARS is the floor; below that the label is clipped rather
        # than allowed to crowd the key.
        room_px = row_px - len(key_text) * char_px - min_gap_px
        label_text = fit(label, max(1, room_px // label_char_px))
        gap_px = max(
            min_gap_px,
            row_px - len(label_text) * label_char_px - len(key_text) * char_px,
        )
        colour = colors["red"] if is_danger(label) else colors["green"]
        lines.append(
            f'{pad}<span size="{LABEL_SIZE}" foreground="{colors["fg"]}">'
            f"{esc(label_text)}</span>"
            f"{_gap_markup(gap_px, label_char_px, char_px)}"
            f'<span foreground="{colour}" weight="bold">{esc(key_text)}</span>'
        )

    return "\n".join(lines)


def card_rows(items, note=None):
    """How many text rows a card occupies: pad, title, [note], rule, items, pad."""
    return PAD_ROWS + 2 + (1 if note else 0) + len(items) + PAD_ROWS


def content_cols(title, items, note=None, *, char_px, label_char_px):
    """BASE character-columns this card's own content actually needs -- the
    longest of its title, its note, or any `label + gap + key` row.

    Every card used to be stretched to its COLUMN's width regardless of
    how little it held: a MOUSE MODE card, five rows of one label and one
    letter, painted the same width as Basics next to it. This is what lets
    pack()/pack_scroll() size the card to what it actually holds instead --
    capped by the column's width, never wider than it.

    Title and note are base-sized so they measure in whole columns. A ROW
    does not: its label is LABEL_SIZE, so it is measured in pixels (label,
    one small space, key) and converted back up, which is why cards got
    narrower when the labels shrank.
    """
    widths = [len(title), len(note) if note else 0]
    widths += [
        -(-(len(label) * label_char_px
            + ROW_GAP_CHARS * char_px
            + len(compact(key)) * char_px) // char_px)   # ceil-divide
        for label, key in items
    ]
    return max(widths)


def grid_metrics(sections, notes, *, n_cols, in_w, char_px, label_char_px):
    """The one card width every card on the sheet uses, plus where to put
    them so the row FILLS the popup.

    Two rules, and they fight each other unless they are decided together:

    * **Every card is the same size.** Sizing each card to only its own
      content made the grid a jumble -- MOUSE MODE narrow, Basics wide,
      nothing lining up. So the width is the widest row found ANYWHERE on
      the sheet, and every card gets it.
    * **The row fills the popup.** That width is usually narrower than an
      even Nth of the popup, and the old code still positioned cards on the
      wide Nth-slot pitch -- which parked all the slack in one lump at the
      right edge instead of between the cards. The leftover is spread into
      the GAPS instead, so the grid reaches both edges.

    The gap is clamped: never tighter than CARD_GAP_PX (cards touching),
    never looser than CARD_GAP_MAX (three cards marooned in a wide popup).
    Anything still left over after the clamp is split as an outer margin,
    which centres the block rather than letting it hang off one side.

    "Fills the popup" means fills the width INSIDE GRID_SIDE_PAD_PX, not
    the whole inner box -- the outer cards keep that gutter off the border.

    Returns (card_cols, card_w_px, gap_px, x0_px).
    """
    usable_w = in_w - 2 * GRID_SIDE_PAD_PX

    slot_w_px = (usable_w - (n_cols - 1) * CARD_GAP_PX) / n_cols
    slot_cols = int(slot_w_px / char_px) - 2 * PAD_CHARS

    card_cols = min(slot_cols, max(
        (max(1, content_cols(title, items, note,
                            char_px=char_px, label_char_px=label_char_px))
         for (title, items), note in zip(sections, notes)),
        default=1,
    ))
    card_w_px = (card_cols + 2 * PAD_CHARS) * char_px

    gap_px = CARD_GAP_PX
    if n_cols > 1:
        spread = (usable_w - n_cols * card_w_px) / (n_cols - 1)
        gap_px = max(CARD_GAP_PX, min(spread, CARD_GAP_MAX))

    block_w = n_cols * card_w_px + (n_cols - 1) * gap_px
    x0_px = GRID_SIDE_PAD_PX + max(0.0, (usable_w - block_w) / 2)
    return card_cols, card_w_px, gap_px, x0_px


# =============================================================================
# LAYOUT
# =============================================================================
def pack(sections, *, n_cols, popup_w, popup_h, line_px, char_px,
         label_char_px, has_note=lambda title: None, name="cheatsheet"):
    """Lay every section out as a card, paginating when a page fills up.

    `sections` is an ordered [(title, items), ...]; order is preserved, so
    related sections stay adjacent. `has_note(title)` returns the section's
    note line, or None.

    Returns a list of pages. Each page is a list of
    (title, items, note, cols, pos_x, pos_y, width, height) -- positions as
    fractions of the popup's inner box, `cols` the card's inner width in
    characters, ready to hand to PopupText.
    """
    in_w, in_h = popup_w - 2 * MARGIN, popup_h - 2 * MARGIN

    notes = [has_note(title) for title, _ in sections]
    card_cols, card_w_px, gap_px, x0_px = grid_metrics(
        sections, notes, n_cols=n_cols, in_w=in_w, char_px=char_px,
        label_char_px=label_char_px,
    )

    top_px, bottom_px = GRID_TOP * in_h, GRID_BOTTOM * in_h
    grid_px = bottom_px - top_px

    # First fit, not "fill one column then move on". Strict sequential
    # packing left a card-sized hole under any section that missed the
    # bottom of its column by a few pixels -- Navigation overshot Basics'
    # column by 9px and the whole first column sat half empty. First fit
    # drops each card in the leftmost column that still has room, which
    # keeps reading order left-to-right and closes the holes.
    pages, page, tops = [], [], [top_px] * n_cols

    for (title, items), note in zip(sections, notes):
        h_px = card_rows(items, note) * line_px

        if h_px > grid_px:
            # One card taller than the whole grid. It will still draw, and
            # it will still run off the bottom -- but now it says so.
            logger.warning(
                "%s: section %r is %d rows, taller than a full column "
                "(%d rows) -- split it.",
                name, title, card_rows(items, note), int(grid_px / line_px),
            )

        col = next(
            (c for c in range(n_cols) if tops[c] + h_px <= bottom_px), None
        )
        if col is None:
            pages.append(page)
            page, tops = [], [top_px] * n_cols
            col = 0

        page.append((
            title, items, note, card_cols,
            (x0_px + col * (card_w_px + gap_px)) / in_w,
            tops[col] / in_h,
            card_w_px / in_w,
            h_px / in_h,
        ))
        tops[col] += h_px + CARD_GAP_PX

    if page:
        pages.append(page)
    return pages


def pack_scroll(sections, *, n_cols, popup_w, popup_h, line_px, char_px,
                label_char_px, has_note=lambda title: None,
                name="cheatsheet"):
    """Lay every section out as ONE tall page, for a sheet that scrolls.

    Same cards as `pack()`, without the pagination: the columns grow as tall
    as they need to and the VIEWPORT moves over them instead. That is the
    whole difference, and it is the better trade for a reference you read
    while doing something else -- paging asks you to remember which page a
    binding was on, and a sheet you have to page through is one you close
    and reopen rather than scroll back up.

    It also decouples the popup's SIZE from how much it can hold. Paging
    made those the same question, which is why these sheets had grown to
    1330x750 on a 1366x768 screen: the only way to show more was to be
    bigger, and the sheet ended up covering the window you opened it to ask
    about.

    Cards go into the SHORTEST column rather than the first one with room.
    With no bottom to fill against, first-fit degenerates into "everything
    in column one until it passes the others", which on these sheets left
    the last column half the height of the first.

    Returns (cards, content_px). A card is
    (title, items, note, cols, pos_x, y_px, width, height_px) -- x and width
    as fractions of the inner box exactly like `pack()`, but y and height in
    PIXELS from the top of the grid, since the caller subtracts the scroll
    offset before it can convert them.
    """
    in_w, in_h = popup_w - 2 * MARGIN, popup_h - 2 * MARGIN

    notes = [has_note(title) for title, _ in sections]
    card_cols, card_w_px, gap_px, x0_px = grid_metrics(
        sections, notes, n_cols=n_cols, in_w=in_w, char_px=char_px,
        label_char_px=label_char_px,
    )

    tops = [0.0] * n_cols
    cards = []

    for (title, items), note in zip(sections, notes):
        h_px = card_rows(items, note) * line_px
        # Ties go to the leftmost column, so a run of equal-height cards
        # still reads left to right instead of hopping.
        col = min(range(n_cols), key=lambda c: (tops[c], c))

        cards.append((
            title, items, note, card_cols,
            (x0_px + col * (card_w_px + gap_px)) / in_w,
            tops[col],
            card_w_px / in_w,
            h_px,
        ))
        tops[col] += h_px + CARD_GAP_PX

    # The trailing gap under the last card in the tallest column is not
    # content; leaving it in adds a blank screenful at the bottom of the
    # scroll.
    content_px = max(max(tops) - CARD_GAP_PX, 0.0) if cards else 0.0
    return cards, content_px


def viewport(cards, content_px, *, popup_h, scroll_px):
    """Where the visible cards go, for a given scroll offset.

    Shared by all three sheets so the clamp cannot drift between them: an
    offset past `content - viewport` leaves you looking at an empty popup
    with nothing to say which way is back.

    Returns (visible, offset, pct, max_off) where `visible` is
    (title, items, note, cols, pos_x, pos_y, width, height) with pos_y and
    height back in FRACTIONS, ready for PopupText, and cards entirely
    outside the viewport already dropped.
    """
    in_h = popup_h - 2 * MARGIN
    top_px = GRID_TOP * in_h
    view_px = GRID_BOTTOM * in_h - top_px
    max_off = max(0.0, content_px - view_px)
    off = min(max(scroll_px, 0.0), max_off)

    visible = []
    for title, items, note, cols, px, y_px, pw, h_px in cards:
        y = top_px + y_px - off
        # Only what is ENTIRELY outside is dropped. A card straddling the
        # edge still has to be drawn, or the sheet would lose one at each
        # end and scrolling would flick cards in and out of existence
        # rather than move them.
        if y + h_px <= top_px or y >= top_px + view_px:
            continue
        visible.append(
            (title, items, note, cols, px, y / in_h, pw, h_px / in_h)
        )

    pct = 100.0 * off / max_off if max_off > 0 else 0.0
    return visible, off, pct, max_off


# =============================================================================
# SELFTEST
#
# The original bug was invisible by construction -- nothing errors, the
# entries simply are not drawn -- so it survived until someone counted the
# lines on screen against the source. This measures instead: pango is asked
# for the real extents of every card at its real font size, and the result
# is checked against the popup it has to fit in.
#
#     python3 -m popups._cheatsheet_grid     (from ~/.config/qtile)
#
# Run by validate.sh, so an entry added to any sheet cannot quietly push
# another one off the bottom again.
# =============================================================================
SHEETS = ("QtileCheatsheet", "VimCheatsheet", "FishCheatsheet")

# The reference panel. Every sheet has to fit on the smallest screen this
# config supports, because that is the one it was designed on.
SCREEN_W, SCREEN_H = 1366, 768


def _font_charset(family):
    """The set of codepoint ranges `family` actually covers, via fontconfig."""
    import subprocess

    out = subprocess.run(
        ["fc-list", "--format=%{charset}\n", family],
        capture_output=True, text=True, timeout=10,
    ).stdout
    ranges = set()
    for line in out.split("\n"):
        for part in line.split():
            if "-" in part:
                lo, hi = part.split("-")
                ranges.add((int(lo, 16), int(hi, 16)))
            elif part:
                v = int(part, 16)
                ranges.add((v, v))
    return ranges


def _covered(charset, ch):
    c = ord(ch)
    return any(lo <= c <= hi for lo, hi in charset)


def selftest(sheets=SHEETS, verbose=True):
    """Return a list of failure strings; empty means every sheet fits."""
    import gi
    import re as _re

    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
    import cairo

    ctx = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))

    def _font_desc(size):
        """A description sized the way QTILE sizes it, which is not the way
        `Pango.FontDescription("Family 14")` does.

        qtile's drawer sets the size with `set_absolute_size()` (see
        libqtile/backend/base/drawer.py), so a PopupText `fontsize` is in
        DEVICE PIXELS. A description string is in POINTS, which at 96dpi is
        4/3 larger -- "14" as points renders 33% bigger than "14" as
        absolute.

        This measured in points while qtile drew in pixels, so every card
        was built ~30% wider and taller than the text it held: the dead
        band under the last row of every card, and the gap between the key
        column and the card's right edge. The selftest agreed with itself
        and passed the whole time, because it was the only thing checking.
        """
        desc = Pango.FontDescription(FONT)
        desc.set_absolute_size(size * Pango.SCALE)
        return desc

    def extents(markup, size):
        lay = PangoCairo.create_layout(ctx)
        lay.set_font_description(_font_desc(size))
        lay.set_markup(markup, -1)
        return lay.get_pixel_size()

    def cell(size):
        """The (char_px, line_px) qtile will actually draw at `size`."""
        lay = PangoCairo.create_layout(ctx)
        lay.set_font_description(_font_desc(size))
        lay.set_text("M" * 100, -1)
        w, _ = lay.get_pixel_size()
        lay2 = PangoCairo.create_layout(ctx)
        lay2.set_font_description(_font_desc(size))
        lay2.set_text("\n".join("M" * 10), -1)
        _, h = lay2.get_pixel_size()
        return w / 100, h / 10

    failures = []

    # A silently-substituted font would break every width below, and the
    # symptom (CJK glyphs, nothing lines up) is exactly what this file
    # exists to stop. Check the family really resolves.
    import subprocess

    charset = None
    try:
        matched = subprocess.run(
            ["fc-match", "-f", "%{family}", FONT],
            capture_output=True, text=True, timeout=10,
        ).stdout
        if FONT.lower() not in matched.lower():
            failures.append(
                f"font {FONT!r} is not installed -- fc-match answers "
                f"{matched!r}, so every column would be misaligned"
            )
        charset = _font_charset(FONT)
    except Exception as e:  # fc-match missing: not worth failing over
        if verbose:
            print(f"  (could not inspect the font: {e})")

    for name in sheets:
        mod = __import__(f"popups.{name}", fromlist=["x"])
        W, H = mod.POPUP_W, mod.POPUP_H
        in_w, in_h = W - 2 * MARGIN, H - 2 * MARGIN
        footer_top = mod.FOOTER_Y * in_h
        pages = mod.layout_pages()

        # A scrolling sheet is taller than its popup BY DESIGN -- that is
        # what there is to scroll. The vertical checks below are asking
        # "does everything fit on screen at once", which is the right
        # question for a paged sheet and the wrong one here; running them
        # anyway would fail every card past the first screenful. Everything
        # else -- glyph coverage, clipped rows, card WIDTH -- still applies,
        # because none of it is fixed by being able to scroll.
        scrolls = getattr(mod, "SCROLLS", False)

        if W > SCREEN_W or H > SCREEN_H:
            failures.append(
                f"{name}: popup is {W}x{H}, larger than the {SCREEN_W}x"
                f"{SCREEN_H} reference panel"
            )

        # The sheet's CHAR_PX/LINE_PX are what every card's width and height
        # are computed from. If they disagree with what pango will actually
        # draw, the cards come out the wrong size and NOTHING else here
        # notices -- the geometry checks below all use the same wrong
        # numbers, so they stay self-consistently green. That is exactly how
        # a 30% oversize survived: the constants said 11x26 (points) while
        # qtile drew 8x20 (pixels), and every card carried the difference as
        # dead space. Check the constants against reality first.
        real_char, real_line = cell(mod.BODY_SIZE)
        if abs(real_char - mod.CHAR_PX) > 0.5:
            failures.append(
                f"{name}: CHAR_PX is {mod.CHAR_PX} but {FONT} at "
                f"{mod.BODY_SIZE} draws {real_char:.2f}px per glyph -- "
                f"cards are sized wrong by "
                f"{abs(real_char - mod.CHAR_PX) / real_char:.0%}."
            )
        if abs(real_line - mod.LINE_PX) > 0.5:
            failures.append(
                f"{name}: LINE_PX is {mod.LINE_PX} but {FONT} at "
                f"{mod.BODY_SIZE} draws {real_line:.2f}px per line -- "
                f"cards are sized wrong by "
                f"{abs(real_line - mod.LINE_PX) / real_line:.0%}."
            )

        # Same check for the label column. _gap_markup() solves for an exact
        # pixel fit using this number, so if it is wrong the key column
        # stops being a column.
        lw, _ = extents(f'<span size="{LABEL_SIZE}">{"M" * 100}</span>',
                        mod.BODY_SIZE)
        real_label = lw / 100
        if abs(real_label - mod.LABEL_CHAR_PX) > 0.5:
            failures.append(
                f"{name}: LABEL_CHAR_PX is {mod.LABEL_CHAR_PX} but "
                f'size="{LABEL_SIZE}" at {mod.BODY_SIZE} draws '
                f"{real_label:.2f}px per glyph -- the key column will not "
                f"line up."
            )

        # Every glyph the popup draws must be in FONT. A missing one does
        # not error -- it falls back to another family at another width and
        # un-aligns the key column. Header and footer are checked too: the
        # legend is exactly where a hardcoded U+21B5 ↵ slipped past a
        # cards-only version of this check.
        def glyph_check(markup, where):
            if not charset:
                return
            plain = _re.sub(r"<[^>]*>", "", markup)
            missing = {
                c for c in plain if c not in "\n\t " and not _covered(charset, c)
            }
            if missing:
                names = ", ".join(f"U+{ord(c):04X}" for c in sorted(missing))
                failures.append(
                    f"{where}: {FONT} has no glyph for "
                    f"{''.join(sorted(missing))!r} ({names}) -- it would "
                    f"fall back and break alignment."
                )

        if hasattr(mod, "_header"):
            glyph_check(mod._header(0, pages), f"{name}/header")
        if hasattr(mod, "_footer"):
            glyph_check(mod._footer(pages), f"{name}/footer")

        for pageno, page in enumerate(pages, 1):
            for title, items, note, cols, _px, py, pw, ph in page:
                markup = mod.render_card(title, items, note, cols)
                where = f"{name} p{pageno}/{title}"
                glyph_check(markup, where)

                # A clipped row is a broken entry: "z 'file/folderna…" is
                # not a thing you can type. card_markup() clips rather than
                # letting the key spill off the card, which is the right
                # failure -- but it is still a failure, so say so.
                if len(fit(title, cols)) < len(title):
                    failures.append(f"{where}: title is clipped.")
                for label, key in items:
                    # Measured the way card_markup() lays the row out: the
                    # label in LABEL_SIZE characters, the key in base ones.
                    # Counting the label in base characters (as this used
                    # to) over-states every row by the size difference and
                    # fails rows that fit perfectly well.
                    need = content_cols(
                        "", [(label, key)],
                        char_px=mod.CHAR_PX, label_char_px=mod.LABEL_CHAR_PX,
                    )
                    if need > cols:
                        failures.append(
                            f"{where}: {label!r} + {compact(key)!r} needs "
                            f"{need} columns, card holds {cols} -- shorten "
                            f"it or widen the cards."
                        )

                w, h = extents(markup, mod.BODY_SIZE)
                card_w, card_h = pw * in_w, ph * in_h
                bottom = py * in_h + card_h
                where = f"{name} p{pageno}/{title}"

                if w > card_w:
                    failures.append(
                        f"{where}: text is {w:.0f}px wide, card is "
                        f"{card_w:.0f}px -- lower N_COLS or BODY_SIZE."
                    )
                if h > card_h + 2:
                    failures.append(
                        f"{where}: text is {h:.0f}px tall, card is "
                        f"{card_h:.0f}px -- LINE_PX is wrong for "
                        f"{mod.BODY_SIZE}pt."
                    )
                if not scrolls and bottom > footer_top:
                    failures.append(
                        f"{where}: overlaps the footer by "
                        f"{bottom - footer_top:.0f}px."
                    )
                if not scrolls and bottom > in_h:
                    failures.append(
                        f"{where}: {bottom - in_h:.0f}px BELOW the popup "
                        f"edge -- these entries never render."
                    )

        # What replaces those two checks on a scrolling sheet: every card
        # has to be REACHABLE. The offset is clamped to
        # content - viewport, so a card starting past that clamp can never
        # be scrolled to and is exactly as invisible as one drawn off the
        # bottom used to be.
        if scrolls:
            cards, content_px = mod.layout_scroll()
            view_px = (GRID_BOTTOM - GRID_TOP) * in_h
            max_off = max(0.0, content_px - view_px)
            for title, items, note, cols, _px, y_px, _pw, h_px in cards:
                if y_px > max_off + view_px - h_px + 1:
                    failures.append(
                        f"{name}/{title}: starts {y_px:.0f}px down but the "
                        f"scroll stops at {max_off:.0f}px -- unreachable."
                    )

        if verbose:
            n = sum(len(p) for p in pages)
            if scrolls:
                _, content_px = mod.layout_scroll()
                view_px = (GRID_BOTTOM - GRID_TOP) * in_h
                print(
                    f"{name}: {W}x{H}, {mod.BODY_SIZE}px, {mod.N_COLS} "
                    f"columns, {n} cards, scrolls "
                    f"{content_px:.0f}px in a {view_px:.0f}px viewport "
                    f"({content_px / view_px:.1f} screenfuls)"
                )
            else:
                print(
                    f"{name}: {W}x{H}, {mod.BODY_SIZE}px, {mod.N_COLS} "
                    f"columns, {n} cards over {len(pages)} page(s)"
                )

    return failures


if __name__ == "__main__":
    import sys

    bad = selftest()
    for line in bad:
        print("FAIL:", line, file=sys.stderr)
    print("cheatsheets: all cards fit" if not bad else f"{len(bad)} failure(s)")
    sys.exit(1 if bad else 0)
