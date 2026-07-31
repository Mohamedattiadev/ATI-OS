from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE
# =============================================================================
_CHEATSHEET_LAYOUT = None
_PAGE = 0            # which page is on screen; Tab cycles

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
        ("Close notification", "Super + n"),
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
        ("Swap up", "Mod + Shift + k"),
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
        ("Anki session", "Super + Shift + a"),
        ("Todos Preview", "Super + p"),
        ("Cpu-Memo widget", "Super + `"),
        ("Lang-Volume widget", "Mod + `"),
    ],
    "Scratchpads": [
        ("Terminal 1", "Super + 1"),
        ("Terminal 2", "Super + 2"),
        ("Mixer", "Super + 3"),
        ("2nd screen mgr", "Super + 4"),
        ("Calculator", "Super + 5"),
        ("WhatsApp", "Super + 8"),
        ("DeepSeek", "Super + 9"),
        ("ChatGPT", "Super + 0"),
        ("Collector", "Super + Shift + d"),
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
# Sized for the 1366x768 reference panel with a little air on each side.
POPUP_W = 1330
POPUP_H = 750

# 12pt, up from 9. The old size was not a design choice, it was what the
# broken layout needed to pretend 90 bindings fit on one screen -- and they
# did not, the bottom of the biggest column was drawn off the edge. Two
# pages at a readable size beats one page nobody can read.
BODY_SIZE = 12
N_COLS = 4

# Measured pango extents for "JetBrainsMono Nerd Font 12". Monospace, so
# these are exact rather than estimates: every row is one LINE_PX line and
# every glyph is CHAR_PX wide, which is what lets the key column align.
LINE_PX = 22
CHAR_PX = 10

FOOTER_Y = _grid.FOOTER_Y
FONT = _grid.FONT


def mode_note(title):
    """The 'press X to activate' line, for sections that are modes."""
    key = MODE_KEYS.get(title)
    return f"press {_grid.compact(key)}" if key else None


def layout_pages():
    """Every card, grouped into pages. See _cheatsheet_grid.pack()."""
    return _grid.pack(
        COLUMNS,
        n_cols=N_COLS,
        popup_w=POPUP_W,
        popup_h=POPUP_H,
        line_px=LINE_PX,
        char_px=CHAR_PX,
        has_note=mode_note,
        name="QtileCheatsheet",
    )


def render_card(title, items, note, cols):
    """Markup for one section card."""
    return _grid.card_markup(
        title, items, cols=cols, colors=COLORS, note=note,
        danger=("exit", "kill", "logout"),
    )


# =============================================================================
# BUILD
# =============================================================================
def _header(page_no, pages):
    """Title block: what this is, plus the legend the compact keys need."""
    counter = (
        f'<span foreground="{COLORS["muted"]}">   page </span>'
        f'<span foreground="{COLORS["green"]}" weight="bold">{page_no + 1}</span>'
        f'<span foreground="{COLORS["muted"]}">/{len(pages)}</span>'
        if len(pages) > 1 else ""
    )
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["blue"]}">'
        f"󰆍  QTILE CHEATSHEET</span>{counter}\n"
        f'<span foreground="{COLORS["muted"]}">'
        f'Mod <span foreground="{COLORS["green"]}">Win</span>'
        f'   Sup <span foreground="{COLORS["purple"]}">Alt</span>'
        f'   ⇧ Shift   ⌃ Ctrl   ⏎ Enter   ␣ Space'
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
    """(Re)draw the popup at the current page."""
    global _CHEATSHEET_LAYOUT

    COLORS.update(_colors())
    pages = layout_pages()
    page = pages[_PAGE % len(pages)]

    controls = [
        PopupText(
            text=_header(_PAGE % len(pages), pages),
            markup=True, font=FONT, fontsize=BODY_SIZE,
            pos_x=0.0, pos_y=0.02, width=1.0, height=0.10,
            h_align="center", v_align="middle",
        )
    ]

    # font and fontsize are passed explicitly on every card: LINE_PX and
    # CHAR_PX are measured for THIS family at THIS size, and PopupText
    # would otherwise default to `sans` 12 -- which on this machine is
    # Noto Sans CJK, proportional, and would misalign every key column.
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

    _CHEATSHEET_LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"].lstrip("#") + "ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )
    _CHEATSHEET_LAYOUT.show(centered=True)


def toggle_cheatsheet(qtile):
    global _CHEATSHEET_LAYOUT, _PAGE

    if _CHEATSHEET_LAYOUT:
        # kill(), not hide(): hide() only unmaps the window and leaves its
        # cairo drawer and pango layouts allocated, while the show path
        # builds a brand new layout every time -- ~2.7MB leaked per open at
        # this popup's size.
        _CHEATSHEET_LAYOUT.kill()
        _CHEATSHEET_LAYOUT = None
        return

    _PAGE = 0
    _build(qtile)
    fade_in_popup(_CHEATSHEET_LAYOUT)


def next_page(qtile, step=1):
    """Tab / n / p: show the next page.

    A rebuild, not an update: the cards on the next page are a different
    number of controls at different sizes, and PopupRelativeLayout fixes
    its control list at construction. No fade -- at 8 frames it reads as a
    flicker when you are paging, rather than as an entrance.
    """
    global _PAGE

    if _CHEATSHEET_LAYOUT is None:
        return
    if len(layout_pages()) < 2:
        return

    _PAGE += step
    close_qtile_cheatsheet()
    _build(qtile)


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
    global _PAGE

    if _CHEATSHEET_LAYOUT:
        return  # already open

    _PAGE = 0
    _build(qtile)
    fade_in_popup(_CHEATSHEET_LAYOUT)
