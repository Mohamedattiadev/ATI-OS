from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE
# =============================================================================
_VIM_CHEATSHEET = None
_PAGE = 0            # which page is on screen; Tab cycles

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
        ("Left / Down / Up / Right", "h j k l"),
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
POPUP_W = 1330
POPUP_H = 750

# 12pt, up from 10. Vim's rows are the longest of the three sheets
# ("Left/Down/Up/Right" against "⇥ h j k l"), so it gets 3 wide columns
# rather than 4 narrow ones, and runs to two pages.
BODY_SIZE = 12
N_COLS = 3

# Measured pango extents for "JetBrainsMono Nerd Font 12". Monospace, so
# exact: every row is one LINE_PX line, every glyph CHAR_PX wide.
LINE_PX = 22
CHAR_PX = 10

FOOTER_Y = _grid.FOOTER_Y
FONT = _grid.FONT


def layout_pages():
    """Every card, grouped into pages. See _cheatsheet_grid.pack()."""
    return _grid.pack(
        COLUMNS,
        n_cols=N_COLS,
        popup_w=POPUP_W,
        popup_h=POPUP_H,
        line_px=LINE_PX,
        char_px=CHAR_PX,
        name="VimCheatsheet",
    )


def render_card(title, items, note, cols):
    return _grid.card_markup(
        title, items, cols=cols, colors=COLORS, note=note,
        danger=("quit", "close", "delete", "clear"),
    )


# =============================================================================
# BUILD
# =============================================================================
def _header(page_no, pages):
    counter = (
        f'<span foreground="{COLORS["muted"]}">   page </span>'
        f'<span foreground="{COLORS["green"]}" weight="bold">{page_no + 1}</span>'
        f'<span foreground="{COLORS["muted"]}">/{len(pages)}</span>'
        if len(pages) > 1 else ""
    )
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["blue"]}">'
        f"  VIM CHEATSHEET</span>{counter}\n"
        f'<span foreground="{COLORS["muted"]}">'
        f'␣ Leader <span foreground="{COLORS["green"]}">Space</span>'
        f'   (v) visual mode   ⇧ Shift   ⌃ Ctrl   ⇥ Tab'
        f"</span>"
    )


def _footer(pages):
    keys = [("Esc", "close")]
    if len(pages) > 1:
        keys.insert(0, ("Tab", "next page"))
    parts = [
        f'<span foreground="{COLORS["green"]}" weight="bold">{k}</span>'
        f'<span foreground="{COLORS["muted"]}"> {v}</span>'
        for k, v in keys
    ]
    sep = f'<span foreground="{COLORS["line"]}">   ·   </span>'
    return sep.join(parts)


def _build(qtile):
    global _VIM_CHEATSHEET

    COLORS.update(_colors())
    pages = layout_pages()
    page = pages[_PAGE % len(pages)]

    controls = [
        PopupText(
            text=_header(_PAGE % len(pages), pages),
            markup=True, font=FONT, fontsize=BODY_SIZE,
            pos_x=0.0, pos_y=0.02, width=1.0, height=0.09,
            h_align="center", v_align="middle",
        )
    ]

    # font and fontsize on every card: LINE_PX/CHAR_PX are measured for
    # THIS family at THIS size, and PopupText would otherwise default to
    # `sans` 12 -- Noto Sans CJK here, proportional, misaligning every key.
    for title, items, note, cols, px, py, pw, ph in page:
        controls.append(
            PopupText(
                text=render_card(title, items, note, cols),
                markup=True,
                font=FONT,
                fontsize=BODY_SIZE,
                background=COLORS["surface"],
                highlight_radius=_grid.CARD_RADIUS,
                pos_x=px, pos_y=py, width=pw, height=ph,
                h_align="left", v_align="top",
            )
        )

    controls.append(
        PopupText(
            text=_footer(pages),
            markup=True, font=FONT, fontsize=BODY_SIZE,
            pos_x=0.0, pos_y=FOOTER_Y, width=1.0, height=0.05,
            h_align="center", v_align="middle",
        )
    )

    _VIM_CHEATSHEET = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"].lstrip("#") + "ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )
    _VIM_CHEATSHEET.show(centered=True)


def toggle_vim_cheatsheet(qtile):
    global _VIM_CHEATSHEET, _PAGE

    if _VIM_CHEATSHEET:
        # kill(), not hide(): hide() leaves the window, its cairo drawer
        # and every pango layout allocated, and the show path builds a new
        # layout every time.
        _VIM_CHEATSHEET.kill()
        _VIM_CHEATSHEET = None
        return

    _PAGE = 0
    _build(qtile)
    fade_in_popup(_VIM_CHEATSHEET)


def next_page(qtile, step=1):
    """Tab: show the next page. A rebuild -- the control list is fixed at
    construction, and the next page is a different set of cards."""
    global _PAGE

    if _VIM_CHEATSHEET is None or len(layout_pages()) < 2:
        return
    _PAGE += step
    close_vim_cheatsheet()
    _build(qtile)


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
    global _PAGE
    if _VIM_CHEATSHEET:
        return  # already open
    _PAGE = 0
    _build(qtile)
    fade_in_popup(_VIM_CHEATSHEET)
