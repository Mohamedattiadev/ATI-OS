from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE
# =============================================================================
_VIM_CHEATSHEET = None
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
    """Palette, adjusted for text drawn on cards rather than on `bg`."""
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
# CHEATSHEET DATA
# =============================================================================
CHEATSHEET = {
"Basics 1": [
    # --- Cursor movement (words / lines) ---
        ("Left/Down/Up/Right", "h j k l"),
    ("Next word", "w"),
    ("Previous word", "b"),
    ("End of word", "e"),
    # --- File navigation ---
    ("Top of file", "gg"),
    ("Bottom of file", "Shift + g"),

    ("Undo", "u"),
    ("Redo", "Ctrl + r"),

    ],
"Basics 2": [

    # --- Line navigation ---
    ("Start of line", "0"),
    ("First non-blank", "^"),
    ("End of line", "Shift + 4"),


    # --- Scrolling ---
    ("Scroll down", "Ctrl + d"),
    ("Scroll up", "Ctrl + u"),
    ("Scroll line down", "Ctrl + e"),
    ("Scroll line up", "Ctrl + y"),
    ],

"Basics 3": [

    # --- Editing basics ---
    ("Insert mode", "i"),
    ("Append after cursor", "a"),
    ("Append end of line", "Shift + a"),
    ("Delete char", "x"),
    ("Delete line", "dd"),
    ("Delete word", "dw"),
    ("Change word", "cw"),
],

    "Movement + Extras": [
        ("Fast move (x5)", "<tab> h j k l"),
        ("Next tab", "L"),
        ("Prev tab", "H"),
        ("Split Terminal", "<leader> tt"),
    ],

    "Editing": [
        ("Copy (yanking)", "y"),
        ("Copy line", "Shift + y"),
        ("Paste", "p"),
        ("Move line down (v)", "Shift + J"),
        ("Move line up (v)", "Shift + K"),
        ("replace current word", "c + i + w"),
        ("replace in parens ()", "c + i + b"),
        ("replace in quotes ''", "c + i + q")
    ],

    "Buffers / Tabs": [
        ("New tab", "<leader> bn"),
        ("Switch tab →", "Shift + l"),
        ("Switch tab ←", "Shift + h"),
    ],

    "Search / Telescope": [
        ("Find files", "<leader> ff"),
        ("Find files 2", "<leader> <leader>"),
        ("Find recent files", "<leader> oo"),
        ("Live grep", "<leader> fg"),
        ("Word under cursor", "<leader> fw"),
        ("Find Todos", "<leader> ft"), 
        ("Find recent Buffers", "<leader> bb"),
        ("LazyGit", "<leader> gg"),
    ],


    "Mini.files": [
        ("Open file explorer", "<leader> e"),
        ("Go in", "l / Enter"),
        ("Go out", "h / H"),
        ("Close", "q"),
    ],

    "Markdown": [
        ("Toggle fold", "Enter"),
        ("Open all folds", "zR"),
        ("Toggle H1–H6", "<leader> 1–6"),
        ("Toggle all folds", "<leader> 0"),
    ],

    "LSP": [
        ("Go to definition", "<leader> gd"),
        ("Hover (split)", "K"),
        ("Diagnostics", "<leader> xx"),
    ],

    "Screenshots": [
        ("Copy code image", "<leader> sc"),
        ("Save code image", "<leader> sf"),
        ("Shoot screenshot", "<leader> ss"),
    ],

    "Exit / Save": [
        ("Save file", "<leader> w"),
        ("Quit", "<leader> q"),
        ("Quit all", "<leader> <leader> q"),
        ("Close buffer", "<leader> bd"),
        ("Clear search", "Escape"),
    ],
}

COLUMNS = list(CHEATSHEET.items())

# =============================================================================
# GEOMETRY -- see popups/_cheatsheet_grid.py
# =============================================================================
POPUP_W = 880
POPUP_H = 580

# 12pt, up from 10.
BODY_SIZE = 15
N_COLS = 3

# Measured pango extents for "JetBrainsMono Nerd Font" at BODY_SIZE, in
# ABSOLUTE pixels -- which is how qtile sizes a font (its drawer calls
# set_absolute_size), NOT the points a "Family 18" description string
# means. Measuring in points made these 33% too big, and every card was
# built that much larger than the text inside it. selftest() now checks
# both numbers against pango so they cannot drift again.
LINE_PX = 21
CHAR_PX = 9

# One LABEL_SIZE character. The label column is set a step down from the
# key column, so it is narrower than CHAR_PX and rows have to be assembled
# in pixels rather than columns. Measured like the two above; selftest()
# checks it against pango.
LABEL_CHAR_PX = 8

FOOTER_Y = _grid.FOOTER_Y
FONT = _grid.FONT


# This sheet SCROLLS instead of paging; the selftest keys off this.
SCROLLS = True

# How far j/k move, in text rows.
SCROLL_ROWS = 3


def layout_scroll():
    """Every card on one tall page, plus its height. See pack_scroll()."""
    return _grid.pack_scroll(
        COLUMNS,
        n_cols=N_COLS,
        popup_w=POPUP_W,
        popup_h=POPUP_H,
        line_px=LINE_PX,
        char_px=CHAR_PX,
        label_char_px=LABEL_CHAR_PX,
        name="VimCheatsheet",
    )


def layout_pages():
    """The cards as a single page, for the selftest."""
    cards, _ = layout_scroll()
    in_h = POPUP_H - 2 * _grid.MARGIN
    top = _grid.GRID_TOP * in_h
    return [[
        (title, items, note, cols, px, (top + y) / in_h, pw, h / in_h)
        for title, items, note, cols, px, y, pw, h in cards
    ]]


def render_card(title, items, note, cols):
    return _grid.card_markup(
        title, items, cols=cols, colors=COLORS, note=note,
        char_px=CHAR_PX, label_char_px=LABEL_CHAR_PX,
        danger=("quit", "close", "delete", "clear"),
    )


# =============================================================================
# BUILD
# =============================================================================
def _header(page_no=0, pages=(), *, pct=None):
    # A step down from the title it sits beside: it is a position readout,
    # not a heading, and at full size it competed with the sheet's name.
    counter = (
        f'  <span size="{_grid.LABEL_SIZE}">'
        f'{_grid.key_chip(f"{pct:.0f}%", COLORS)}</span>'
        if pct is not None else ""
    )
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["blue"]}">'
        f"  VIM CHEATSHEET</span>{counter}\n"
        # A short spacer line so the legend is not crowded under
        # the title, and the legend a step down from body text --
        # it is a key, not something you read every time.
        f'<span size="x-small">\n</span>'
        f'<span size="{_grid.LABEL_SIZE}" foreground="{COLORS["muted"]}">'
        f'␣ Leader <span foreground="{COLORS["green"]}">Space</span>'
        f'   (v) visual mode   ⇧ Shift   ⌃ Ctrl   ⇥ Tab'
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
    ones on screen at offset 0. See QtileCheatsheet._build() for why."""
    global _VIM_CHEATSHEET, _CARD_CONTROLS, _HEADER_CONTROL

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

    # font and fontsize on every card: LINE_PX/CHAR_PX are measured for
    # THIS family at THIS size, and PopupText would otherwise default to
    # `sans` 12 -- Noto Sans CJK here, proportional, misaligning every key.
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

    # Header and footer come LAST, and they are OPAQUE: PopupText does not
    # clip to its height, so the cards straddling the top and bottom of the
    # viewport keep drawing into the title block and the legend. Controls
    # paint in order, so these two are what stops the smear.
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

    _VIM_CHEATSHEET = PopupRelativeLayout(
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
    _VIM_CHEATSHEET.show(centered=True)


def toggle_vim_cheatsheet(qtile):
    global _VIM_CHEATSHEET, _SCROLL

    if _VIM_CHEATSHEET:
        # kill(), not hide(): hide() leaves the window, its cairo drawer
        # and every pango layout allocated, and the show path builds a new
        # layout every time.
        _VIM_CHEATSHEET.kill()
        _VIM_CHEATSHEET = None
        return

    _SCROLL = 0.0
    _build(qtile)
    fade_in_popup(_VIM_CHEATSHEET)


def scroll(qtile, rows=SCROLL_ROWS):
    """j / k: move the viewport down or up by `rows` text rows.

    An in-place repaint, not a rebuild -- see QtileCheatsheet.scroll().
    """
    global _SCROLL

    if _VIM_CHEATSHEET is None:
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

    _VIM_CHEATSHEET.draw()


def next_page(qtile, step=1):
    """Kept for config.py's Tab binding: on a scrolling sheet, Tab moves a
    screenful rather than a page."""
    in_h = POPUP_H - 2 * _grid.MARGIN
    view_px = (_grid.GRID_BOTTOM - _grid.GRID_TOP) * in_h
    scroll(qtile, rows=step * max(1, int(view_px / LINE_PX) - 1))


def is_open():
    """Whether this sheet is the one currently on screen.

    Only one of the three is ever open at a time, so config.py uses
    this to route Tab to whichever it is.
    """
    return _VIM_CHEATSHEET is not None


def close_vim_cheatsheet():
    global _VIM_CHEATSHEET
    if _VIM_CHEATSHEET:
        _VIM_CHEATSHEET.kill()
        _VIM_CHEATSHEET = None


def show_vim_cheatsheet(qtile):
    global _SCROLL
    if _VIM_CHEATSHEET:
        return  # already open
    _SCROLL = 0.0
    _build(qtile)
    fade_in_popup(_VIM_CHEATSHEET)
