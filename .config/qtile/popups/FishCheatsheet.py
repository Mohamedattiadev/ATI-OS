from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE
# =============================================================================
_FISH_KITTY_CHEATSHEET = None
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
# CHEATSHEET DATA (Fish + Kitty)
# =============================================================================
CHEATSHEET = {
    "Fish Most Used": [
        ("Clear", "cl"),
        ("Exit", "ex"),
        ("Reload config", "src"),
        ("Reset terminal", "reset"),
        ("vim in tmux", "vim 'filename'"),
        ("nvim (normal)", "nvim 'filename'"),
    ],

    "Fish Vi Mode": [
        ("Normal mode", "Esc"),
        ("Insert mode", "i"),
        ("Append", "a"),
        ("Move left / right", "h / l"),
        ("Move up / down", "k / j"),
        ("Delete char", "x"),
    ],

    "Directories": [
        ("Up one level", ".."),
        ("Up two levels", "..."),
        ("Up 3 levels", ".3"),
        ("Up 4 levels", ".4"),
        ("Up 5 levels", ".5"),
        ("zoxide", "zi"),
        ("zoxide history", "z 'path'"),
    ],

    "Clipboard": [
        ("Copy", "Ctrl + Shift + c"),
        ("Paste", "Ctrl + Shift + v"),
        ("Paste (selection)", "Shift + Insert"),
    ],

    "Kitty UI": [
        ("Fullscreen", "F11"),
        ("Scroll up", "Page Up"),
        ("Scroll down", "Page Down"),
        ("Scroll to top", "Shift + Home"),
        ("Scroll to bottom", "Shift + End"),
        ("Increase font", "Ctrl + +"),
        ("Decrease font", "Ctrl + -"),
    ],

    "Kitty Scrollback": [
        ("With (nvim)", "Ctrl + Shift + Space"),
        ("Fast mouse scroll", "Wheel ×5"),
    ],

    "FZF": [
        ("Find files", "Ctrl + t"),
        ("Search history", "Ctrl + r"),
        ("Change directory", "Alt + c"),
    ],

    "Tmux": [
        ("create session", "tmux <name>"),
        ("Dev session", "tmuxdev"),
        ("Medo session", "tmuxmedo"),
        ("Delete other sessions", "tmuxDel"),
    ],

    "Danger Zone": [
        ("Exit shell", "Ctrl + d"),
        ("Kill server", "tmux kill-server"),
        ("Cleanup orphans", "cleanup"),
    ],
}

COLUMNS = list(CHEATSHEET.items())


# =============================================================================
# GEOMETRY -- see popups/_cheatsheet_grid.py
# =============================================================================
POPUP_W = 1330
POPUP_H = 750

# 12pt, up from 11. The right-hand column of this sheet is shell COMMANDS,
# not key combos ("tmux kill-server"), so `compact()` has nothing to shorten
# and the rows are long. Four columns still fits every one of them on a
# single page -- three columns did not, and spilled two lonely cards onto a
# second page.
BODY_SIZE = 12
N_COLS = 4

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
        name="FishCheatsheet",
    )


def render_card(title, items, note, cols):
    return _grid.card_markup(
        title, items, cols=cols, colors=COLORS, note=note,
        danger=("kill", "exit", "cleanup", "delete"),
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
        f"  FISH + KITTY CHEATSHEET</span>{counter}\n"
        f'<span foreground="{COLORS["muted"]}">'
        f'⇧ Shift   ⌃ Ctrl   ␣ Space   ·   the right column is what you type'
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
    global _FISH_KITTY_CHEATSHEET

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

    _FISH_KITTY_CHEATSHEET = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"].lstrip("#") + "ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )
    _FISH_KITTY_CHEATSHEET.show(centered=True)


def toggle_fish_kitty_cheatsheet(qtile):
    global _FISH_KITTY_CHEATSHEET, _PAGE

    if _FISH_KITTY_CHEATSHEET:
        # kill(), not hide(): hide() leaves the window, its cairo drawer
        # and every pango layout allocated, and the show path builds a new
        # layout every time.
        _FISH_KITTY_CHEATSHEET.kill()
        _FISH_KITTY_CHEATSHEET = None
        return

    _PAGE = 0
    _build(qtile)
    fade_in_popup(_FISH_KITTY_CHEATSHEET)


def next_page(qtile, step=1):
    """Tab: show the next page."""
    global _PAGE

    if _FISH_KITTY_CHEATSHEET is None or len(layout_pages()) < 2:
        return
    _PAGE += step
    close_fish_kitty_cheatsheet()
    _build(qtile)


def is_open():
    """Whether this sheet is the one currently on screen.

    Only one of the three is ever open at a time, so config.py uses
    this to route Tab to whichever it is.
    """
    return _FISH_KITTY_CHEATSHEET is not None


def close_fish_kitty_cheatsheet():
    global _FISH_KITTY_CHEATSHEET
    if _FISH_KITTY_CHEATSHEET:
        _FISH_KITTY_CHEATSHEET.kill()
        _FISH_KITTY_CHEATSHEET = None


def show_fish_kitty_cheatsheet(qtile):
    global _PAGE
    if _FISH_KITTY_CHEATSHEET:
        return  # already open
    _PAGE = 0
    _build(qtile)
    fade_in_popup(_FISH_KITTY_CHEATSHEET)
