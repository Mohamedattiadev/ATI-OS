from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE
# =============================================================================
_CHEATSHEET_LAYOUT = None
_SCROLL = 0.0        # how far down the sheet is scrolled, in pixels
_CARD_CONTROLS = []  # [(PopupText, y_px), ...] -- every card, not just the
                     # visible ones, so scroll() can reposition in place
                     # instead of tearing the popup down and rebuilding it.
_HEADER_CONTROL = None  # the one control scroll() has to touch: the % counter

# =============================================================================
# COLORS — wal-derived (dominant = green slot). Re-read at each toggle so
# a wallpaper switch retints the popup without qtile restart.
# =============================================================================
from popups._wal_colors import load_colors as _load_colors
from popups._wal_colors import fade_in_popup
from popups._wal_colors import _mix, ensure_contrast


def _colors():
    """Palette, adjusted for text drawn on cards rather than on `bg`.

    Same correction the WiFi and Bluetooth popups make: the shared loader
    derives `muted` against the background, but every row here is painted
    on a `surface` card sitting 7% closer to `fg`, which is enough to drop
    muted text and two of the accents under 3:1 on the preset themes.
    """
    base = _load_colors()
    base["line"] = _mix(base["bg"], base["fg"], 0.22)
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)
    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple", "line"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)
    return base


COLORS = _colors()

# =============================================================================
# MODE ENTRY KEYS (explicit, source of truth)
# =============================================================================
MODE_KEYS = {
    "MOUSE MODE": "Super + F",
    "MEDIA MODE": "Mod + /",
    "RESIZE MODE": "Super + R",
    "DRAW MODE": "Super + Shift + W",
    "ROFI MODE": "Mod + P",
    "ROFI MODE · pickers": "Mod + P",
    "LANGUAGE MODE": "Super + Space",
}

# =============================================================================
# CHEATSHEET DATA (single source of truth)
# =============================================================================
CHEATSHEET = {
    "Basics": [
        ("Terminal", "Mod + Enter"),
        ("Launcher (Rofi)", "Mod + Shift + Enter"),
        ("Reload Qtile", "Mod + Shift + r"),
        ("Kill window", "Mod + Shift + c"),
        ("Passthrough Mode", "Win + F12"),
        ("Toggle normal bar", "Mod + Shift + z"),
        ("Logout menu", "Mod + Shift + q"),
        ("Close notification", "Alt + n"),
        ("Refresh PC", "Mod + Shift + F5"),
    ],
    "Navigation": [
        ("WorkSpace[1-9]", "Mod + [1–9]"),
        ("Focus left", "Mod + h"),
        ("Focus down", "Mod + j"),
        ("Focus up", "Mod + k"),
        ("Focus right", "Mod + l"),
        ("Next layout", "Mod + Tab"),
        ("Next monitor", "Mod + ."),
        ("Prev monitor", "Mod + ,"),
    ],
    "Windows": [
        ("Move to group", "Mod + Shift + [1–9]"),
        ("Swap left", "Mod + Shift + h"),
        ("Swap right", "Mod + Shift + l"),
        ("Swap down", "Mod + Shift + j"),
        ("Toggle floating", "Mod + t"),
        ("Toggle fullscreen", "Mod + f"),
        ("Maximize window", "Mod + x"),
    ],
    "Session / Toggles": [
        ("Terminal toggle", "Mod + n"),
        ("File manager", "Mod + m"),
        ("Brave (browsing)", "Mod + b"),
        ("Qutebrowser (video)", "Mod + v"),
        ("Obsidian session", "Super + Shift + o"),
        ("Telegram session", "Mod + Shift + t"),
        ("Anki session", "Alt + Shift + a"),
        ("Phone mirror", "Mod + Shift + F6"),
        ("sum.md notes", "Mod + Shift + s"),
        ("Todos Preview", "Alt + p"),
        ("Cpu-Memo widget", "Super + `"),
        ("Lang-Volume widget", "Alt + `"),
    ],
    "MOUSE MODE": [
        ("Hint mode", "f"),
        ("Normal mode", "n"),
        ("Fast scroll up", "t"),
        ("Fast scroll down", "b"),
        ("Exit mode", "q / Esc"),
    ],
    "DRAW MODE": [
        ("Toggle draw", "w"),
        ("Clear drawings", "c"),
        ("Undo", "z"),
        ("Redo", "r"),
        ("Toggle visibility", "v"),
        ("Exit mode", "q / Esc"),
    ],
    # Mod+P is by far the biggest menu, so it is split in two: the scripts
    # it spawns, and the sub-chords / pickers it opens. One 22-item column
    # did not fit on screen -- see the layout notes further down.
    "ROFI MODE": [
        ("Translate text", "e"),
        ("Add Anki note", "a"),
        ("Screenshots", "i"),
        ("man pages", "m"),
        ("Notes", "o"),
        ("Documents", "d"),
        ("Video recorder", "r"),
        ("Close all notifs", "x"),
        ("Light / brightness", "l"),
        ("Config editor", "f"),
        ("dmscripts hub", "h"),
        ("Password menu", "p"),
        ("YouTube menu", "y"),
        ("Kill process", "k"),
        ("Spell check", "s"),
        # "Weather / w" used to sit here. dm-weather has been commented out
        # in config.py for a while, and w is the wallpaper picker now.
        ("Todo manager", "t"),
        ("Saved Links", "z"),
        ("Logout menu", "q"),
    ],
    "ROFI MODE · pickers": [
        ("Theme picker", "c"),
        # These three moved when Bluetooth landed: wallpaper b -> w,
        # WiFi w -> n, and b became Bluetooth.
        ("Wallpaper picker", "w"),
        ("WiFi picker", "n"),
        ("Bluetooth picker", "b"),
    ],
    "RESIZE MODE": [
        ("Shrink window", "Shift + h"),
        ("Grow window", "Shift + l"),
        ("Reset layout", "Shift + n"),
        ("Exit mode", "q / Esc"),
    ],
    "MEDIA MODE": [
        ("Volume down", "Shift + j"),
        ("Volume up", "Shift + k"),
        ("Mute", "Shift + m"),
        ("MPV PiP", "Shift + p"),
        ("Exit mode", "q / Esc"),
    ],
    "LANGUAGE MODE": [
        ("Arabic", "a"),
        ("English", "e"),
        ("Turkish", "t"),
        ("German", "d"),
        ("Exit mode", "Esc"),
    ],
}

COLUMNS = list(CHEATSHEET.items())


# =============================================================================
# GEOMETRY -- see popups/_cheatsheet_grid.py
# =============================================================================
# 1330x750 on a 1366x768 screen was 97% of the width and 98% of the height:
# a "popup" you could not see past, covering the very window you had opened
# it to ask a question about. It was that big because paging tied capacity
# to size -- the only way to show more bindings was to be bigger.
#
# Scrolling breaks that tie, so the sheet is sized like a popup rather than
# like a document. Capacity is no longer a function of this number; it only
# decides how much you see at once.
#
# This TRACKS BODY_SIZE and is not free to set on its own. Cards are sized
# in CHARACTERS, so the width the three of them need is
# 3 * (card_cols + 2*PAD_CHARS) * CHAR_PX -- at 15/9px that is 3*252=756px,
# hence 850 with gutters. Set this much wider and the grid stops reaching
# the edges and leaves a band of dead background down one side, which is
# the thing that made these sheets look broken. Change BODY_SIZE and this
# has to move with it; `python3 -m popups._cheatsheet_grid` prints the
# numbers to size it from.
POPUP_W = 880
POPUP_H = 580

# 15, down from an 18 that was too big to read comfortably, and up from the
# 12 this started at. 12 was never a design choice -- it was what the broken
# layout needed to pretend 90 bindings fit on one screen, and they did not.
# Scrolling removed that pressure entirely, so this is set by what is
# comfortable at arm's length, and POPUP_W above follows it.
#
# NB this is not points. qtile sizes fonts with set_absolute_size(), so 15
# means 15 DEVICE PIXELS -- about 11pt. See LINE_PX/CHAR_PX below.
BODY_SIZE = 15

# 3, down from 4, because the popup lost 330px of width. Card width is what
# actually matters (the rows are `label ... KEY` and clip when it shrinks).
N_COLS = 3

# How far j/k move, in text rows. One row is too slow to cross a sheet this
# tall and a full screenful loses your place; three tracks the eye.
SCROLL_ROWS = 3

# Measured pango extents for "JetBrainsMono Nerd Font" at BODY_SIZE, in
# ABSOLUTE pixels -- which is how qtile sizes a font (its drawer calls
# set_absolute_size), NOT the points a "Family 18" description string
# means. These were measured in POINTS once, which made them 33% too big,
# and since a card's width and height are computed FROM them every card was
# built a third larger than the text it held -- a dead band under the last
# row and a gap between the key column and the card's right edge. Nothing
# caught it because the selftest measured in points too. It now checks both
# numbers against pango at BODY_SIZE, so they cannot drift again.
#
# Monospace, so these are exact: every row is one LINE_PX line and every
# glyph is CHAR_PX wide, which is what lets the key column align and lets
# grid_metrics() size cards in whole characters.
LINE_PX = 21
CHAR_PX = 9

# One LABEL_SIZE character. The label column is set a step down from the
# key column, so it is narrower than CHAR_PX and rows have to be assembled
# in pixels rather than columns. Measured like the two above; selftest()
# checks it against pango.
LABEL_CHAR_PX = 8

FOOTER_Y = _grid.FOOTER_Y
FONT = _grid.FONT


def mode_note(title):
    """The 'press X to activate' line, for sections that are modes."""
    key = MODE_KEYS.get(title)
    return f"press {_grid.compact(key)}" if key else None


# This sheet SCROLLS instead of paging; the selftest keys off this to check
# it the right way (a card below the popup edge is the normal state here,
# not the bug it is on a paged sheet).
SCROLLS = True


def layout_scroll():
    """Every card on one tall page, plus its total height in pixels."""
    return _grid.pack_scroll(
        COLUMNS,
        n_cols=N_COLS,
        popup_w=POPUP_W,
        popup_h=POPUP_H,
        line_px=LINE_PX,
        char_px=CHAR_PX,
        label_char_px=LABEL_CHAR_PX,
        has_note=mode_note,
        name="QtileCheatsheet",
    )


def layout_pages():
    """The cards as a single page, for the selftest and for callers that
    still speak in pages. Kept so `pages` means the same thing in every
    sheet; this one simply never has more than one."""
    cards, _ = layout_scroll()
    in_h = POPUP_H - 2 * _grid.MARGIN
    top = _grid.GRID_TOP * in_h
    return [[
        (title, items, note, cols, px, (top + y) / in_h, pw, h / in_h)
        for title, items, note, cols, px, y, pw, h in cards
    ]]


def render_card(title, items, note, cols):
    """Markup for one section card."""
    return _grid.card_markup(
        title, items, cols=cols, colors=COLORS, note=note,
        char_px=CHAR_PX, label_char_px=LABEL_CHAR_PX,
        danger=("exit", "kill", "logout"),
    )


# =============================================================================
# BUILD
# =============================================================================
def _header(page_no=0, pages=(), *, pct=None):
    """Title block: what this is, plus the legend the compact keys need.

    `pct` is how far down the sheet you are, 0-100. It replaces the old page
    counter: scrolling has no page number, but it still has to answer "is
    there more below this?" -- without that the sheet looks like it simply
    ends wherever the viewport happens to cut it.
    """
    # A step down from the title it sits beside: it is a position readout,
    # not a heading, and at full size it competed with the sheet's name.
    counter = (
        f'  <span size="{_grid.LABEL_SIZE}">'
        f'{_grid.key_chip(f"{pct:.0f}%", COLORS)}</span>'
        if pct is not None else ""
    )
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["blue"]}">'
        f"󰆍  QTILE CHEATSHEET</span>{counter}\n"
        # A short spacer line so the legend is not crowded under
        # the title, and the legend a step down from body text --
        # it is a key, not something you read every time.
        f'<span size="x-small">\n</span>'
        f'<span size="{_grid.LABEL_SIZE}" foreground="{COLORS["muted"]}">'
        f'Mod <span foreground="{COLORS["green"]}">Win</span>'
        f'   Sup <span foreground="{COLORS["purple"]}">Alt</span>'
        f'   ⇧ Shift   ⌃ Ctrl   ⏎ Enter   ␣ Space'
        f"</span>"
    )


def _footer(pages=(), *, scrollable=True):
    keys = [("Esc", "close")]
    if scrollable:
        keys.insert(0, ("j / k", "scroll"))
    gap = f'<span foreground="{COLORS["line"]}"> </span>'
    # Smaller than the cards: this is a legend you read once, not content.
    # The chips inherit the size, since key_chip() sets no size of its own.
    return (
        f'<span size="{_grid.LABEL_SIZE}">'
        + gap.join(
            f'{_grid.key_chip(k, COLORS)}'
            f'<span foreground="{COLORS["muted"]}"> {v}</span>'
            for k, v in keys
        )
        + "</span>"
    )


def _build(qtile):
    """Build the popup ONCE, with every card as a control -- not just the
    ones on screen at offset 0.

    That is what makes scroll() real: PopupRelativeLayout only computes a
    control's offsetx/offsety from its pos_x/pos_y fraction the first time
    ("if not control.placed"), so every card below is created here with
    `placed` already True and its pixel offsety pre-computed by hand. From
    then on scroll() moves them by writing that attribute directly and
    asking the SAME window to repaint -- no kill(), no rebuild, no flash of
    an empty popup between frames.
    """
    global _CHEATSHEET_LAYOUT, _CARD_CONTROLS, _HEADER_CONTROL

    COLORS.update(_colors())
    cards, content_px = layout_scroll()
    _, off, pct, max_off = _grid.viewport(
        cards, content_px, popup_h=POPUP_H, scroll_px=_SCROLL
    )

    in_h = POPUP_H - 2 * _grid.MARGIN
    in_w = POPUP_W - 2 * _grid.MARGIN
    top_px = _grid.GRID_TOP * in_h

    controls = []
    _CARD_CONTROLS = []

    # font and fontsize are passed explicitly on every card: LINE_PX and
    # CHAR_PX are measured for THIS family at THIS size, and PopupText
    # would otherwise default to `sans` 12 -- which on this machine is
    # Noto Sans CJK, proportional, and would misalign every key column.
    for title, items, note, cols, x_frac, y_px, w_frac, h_px in cards:
        card = PopupText(
            text=render_card(title, items, note, cols),
            markup=True,
            font=FONT,
            fontsize=BODY_SIZE,
            background=COLORS["surface"],
            highlight_radius=_grid.CARD_RADIUS,
            h_align="left", v_align="top",
        )
        card.width = int(w_frac * in_w)
        card.height = int(h_px)
        card.offsetx = int(x_frac * in_w) + _grid.MARGIN
        card.offsety = int(top_px + y_px - off) + _grid.MARGIN
        card.placed = True
        controls.append(card)
        _CARD_CONTROLS.append((card, y_px))

    # Header and footer come LAST, and they are OPAQUE. PopupText does not
    # clip to its height (that is this module's oldest bug), so the card
    # straddling the top of the viewport keeps drawing upward into the title
    # block and the one at the bottom draws down through the legend.
    # Controls paint in order, so these two, added after the cards and given
    # a solid background, are what stops the scrolled text from smearing
    # over them. They also span the full band up to and past the grid edge,
    # since a transparent sliver above the header would show the same bleed.
    # Placed in absolute pixels, like the cards, so they cover the popup's
    # MARGIN as well. Sized as FRACTIONS they only span the inner box, which
    # left a ~6px strip of bare margin at each end -- and since PopupText
    # does not clip, the card straddling the viewport edge drew straight
    # through it: half a row of text hanging below the footer.
    _HEADER_CONTROL = PopupText(
        text=_header(pct=pct if max_off > 0 else None),
        markup=True, font=FONT, fontsize=BODY_SIZE,
        background=COLORS["bg"],
        h_align="center", v_align="middle",
    )
    _HEADER_CONTROL.offsetx, _HEADER_CONTROL.offsety = 0, 0
    _HEADER_CONTROL.width = POPUP_W
    _HEADER_CONTROL.height = int(top_px) + _grid.MARGIN
    _HEADER_CONTROL.placed = True
    controls.append(_HEADER_CONTROL)

    foot_y = int(_grid.GRID_BOTTOM * in_h) + _grid.MARGIN
    footer = PopupText(
        text=_footer(scrollable=max_off > 0),
        markup=True, font=FONT, fontsize=BODY_SIZE,
        background=COLORS["bg"],
        h_align="center", v_align="middle",
    )
    footer.offsetx, footer.offsety = 0, foot_y
    footer.width = POPUP_W
    footer.height = POPUP_H - foot_y
    footer.placed = True
    controls.append(footer)

    _CHEATSHEET_LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        # Matches WifiPopup/BluetoothPopup: ~95% opaque card fill, a
        # subtle 2px border in the same surface_alt used for chips, so the
        # popup reads as one designed surface instead of a color rectangle.
        background=COLORS["bg"] + "F2",
        border=COLORS["surface_alt"],
        border_width=2,
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )
    _CHEATSHEET_LAYOUT.show(centered=True)


def toggle_cheatsheet(qtile):
    global _CHEATSHEET_LAYOUT, _SCROLL

    if _CHEATSHEET_LAYOUT:
        # kill(), not hide(): hide() only unmaps the window and leaves its
        # cairo drawer and pango layouts allocated, while the show path
        # builds a brand new layout every time -- ~2.7MB leaked per open at
        # this popup's size.
        _CHEATSHEET_LAYOUT.kill()
        _CHEATSHEET_LAYOUT = None
        return

    _SCROLL = 0.0
    _build(qtile)
    fade_in_popup(_CHEATSHEET_LAYOUT)


def scroll(qtile, rows=SCROLL_ROWS):
    """j / k: move the viewport down or up by `rows` text rows.

    An in-place repaint, not a rebuild: every card was already created in
    _build() with `placed=True`, so this only has to overwrite each one's
    `offsety` and ask the layout to redraw -- same popup window, same
    pango layouts, nothing torn down. That's what makes it look like
    scrolling instead of the sheet blinking closed and open again.

    The clamp still matters: at either end the offset does not move, and
    redrawing an identical frame would be a visible flash that says
    "something happened" when nothing did. So it returns instead.
    """
    global _SCROLL

    if _CHEATSHEET_LAYOUT is None:
        return

    cards, content_px = layout_scroll()
    _, off, pct, max_off = _grid.viewport(
        cards, content_px, popup_h=POPUP_H, scroll_px=_SCROLL + rows * LINE_PX
    )
    if off == _SCROLL:
        return
    _SCROLL = off

    in_h = POPUP_H - 2 * _grid.MARGIN
    top_px = _grid.GRID_TOP * in_h
    for card, y_px in _CARD_CONTROLS:
        card.offsety = int(top_px + y_px - off) + _grid.MARGIN

    if _HEADER_CONTROL is not None:
        text = _header(pct=pct if max_off > 0 else None)
        _HEADER_CONTROL._text = text
        _HEADER_CONTROL.layout.text = text

    _CHEATSHEET_LAYOUT.draw()


def next_page(qtile, step=1):
    """Kept for config.py's Tab binding: on a scrolling sheet, Tab moves a
    screenful rather than a page. Tab is still the key you reach for when
    you want "more of this", and it has one less thing to mean now."""
    in_h = POPUP_H - 2 * _grid.MARGIN
    view_px = (_grid.GRID_BOTTOM - _grid.GRID_TOP) * in_h
    scroll(qtile, rows=step * max(1, int(view_px / LINE_PX) - 1))


def is_open():
    """Whether this sheet is the one currently on screen.

    Only one of the three is ever open at a time, so config.py uses
    this to route Tab to whichever it is.
    """
    return _CHEATSHEET_LAYOUT is not None


def close_qtile_cheatsheet():
    global _CHEATSHEET_LAYOUT
    if _CHEATSHEET_LAYOUT:
        _CHEATSHEET_LAYOUT.kill()
        _CHEATSHEET_LAYOUT = None


def show_qtile_cheatsheet(qtile):
    global _SCROLL

    if _CHEATSHEET_LAYOUT:
        return  # already open

    _SCROLL = 0.0
    _build(qtile)
    fade_in_popup(_CHEATSHEET_LAYOUT)
