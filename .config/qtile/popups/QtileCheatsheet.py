from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

# =============================================================================
# GLOBAL STATE (toggle)
# =============================================================================
_CHEATSHEET_LAYOUT = None

# =============================================================================
# COLORS — wal-derived (dominant = green slot). Re-read at each toggle so
# a wallpaper switch retints the popup without qtile restart.
# =============================================================================
from popups._wal_colors import load_colors as _load_colors
from popups._wal_colors import fade_in_popup
COLORS = _load_colors()

MODE_NOTE_TEMPLATE = (
    '<span size="small" foreground="{muted}" style="italic">'
    'Press <b><span foreground="{key_color}">{key}</span></b> '
    "to activate the mode"
    "</span>"
)

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
    "LANUAGE SWITCH MODE": "Super + Space",
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
        ("Toggle Normal bar ", "Mod + Shift + z"),
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
    "session / Toggles": [
        ("Terminal toggle", "Mod + n"),
        ("File manager", "Mod + m"),
        ("Brave browser (Browsing)", "Mod + b"),
        ("Qutebrowser (Video)", "Mod + v"),
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
        ("2nd screen manager", "Super + 4"),
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
        ("Close All notifications", "x"),
        ("Light / Britness", "l"),
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
    "LANUAGE SWITCH MODE": [
        ("Arabic", "a"),
        ("English", "e"),
        ("Turkish", "t"),
        ("German", "d"),
        ("Exit mode", "Esc"),
    ],
}

COLUMNS = list(CHEATSHEET.items())


# =============================================================================
# GEOMETRY -- see popups/_cheatsheet_grid.py for why this is not a grid
# =============================================================================
# Sized for the 1366x768 reference panel with a little air on each side.
# It cannot grow much: this popup is already most of that screen.
POPUP_W = 1300
POPUP_H = 730

# 9, not the PopupText default of 12. The content is 12 sections / 90
# bindings, and on a 1366px-wide screen the two constraints fight: a bigger
# font needs more columns to fit the height, and more columns are too
# narrow for the widest line ("Launcher (Rofi) : Mod + Shift + Enter"), so
# it wraps -- which makes sections taller, which needs more columns again.
# Swept with pango over every size/column split that fits the panel; 9pt in
# 5 columns is the largest that clears both. At 10pt nothing fits.
BODY_SIZE = 9
N_COLS = 5

# Measured pango extents at "sans 9": a body line is 18px, the "large"
# title 22px, and the mode note plus its divider rule 33px together.
BODY_PX, TITLE_PX, NOTE_PX = 18, 22, 33

MARGIN = _grid.MARGIN
FOOTER_Y = _grid.FOOTER_Y


def layout_sections():
    """Place every section. See _cheatsheet_grid.pack()."""
    return _grid.pack(
        COLUMNS,
        n_cols=N_COLS,
        popup_h=POPUP_H,
        body_px=BODY_PX,
        title_px=TITLE_PX,
        note_px=NOTE_PX,
        has_note=lambda title: title in MODE_KEYS,
        name="QtileCheatsheet",
    )


# =============================================================================
# TEXT RENDERER
# =============================================================================
def render_section(title, items):
    lines = [
        f'<span size="large" weight="bold" foreground="{COLORS["purple"]}">{title}</span>'
    ]

    # ---------------- MODE NOTE ----------------
    if title in MODE_KEYS:
        lines.append(
            MODE_NOTE_TEMPLATE.format(
                muted=COLORS["muted"],
                key_color=COLORS["blue"],
                key=MODE_KEYS[title],
            )
        )
        lines.append(f'<span foreground="{COLORS["muted"]}">────────────────</span>')

    # ---------------- ITEMS ----------------
    for label, combo in items:
        combo_color = COLORS["red"] if "Exit" in label else COLORS["green"]

        lines.append(
            f'<span foreground="{COLORS["muted"]}">•</span> '
            f'<span foreground="{COLORS["fg"]}">{label} :</span> '
            f'<b><span foreground="{combo_color}">{combo}</span></b>'
        )

    return "\n".join(lines)


# =============================================================================
# TOGGLE FUNCTION
# =============================================================================
def toggle_cheatsheet(qtile):
    global _CHEATSHEET_LAYOUT

    if _CHEATSHEET_LAYOUT:
        # kill(), not hide(): hide() only unmaps the window and leaves its
        # cairo drawer and pango layouts allocated, while the show path
        # below builds a brand new layout every time -- ~2.7MB leaked per
        # open at this popup's size.
        _CHEATSHEET_LAYOUT.kill()
        _CHEATSHEET_LAYOUT = None
        return

    COLORS.update(_load_colors())
    controls = []

    # ---------------- TITLE ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰆍  QTILE CHEATSHEET</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f'Mod = <b><span foreground="{COLORS["green"]}">Win</span></b> '
                f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span> '
                f'Super = <b><span foreground="{COLORS["purple"]}">Alt</span></b>'
                f"</span>"
            ),
            markup=True,
            pos_x=0.0,
            pos_y=0.03,
            width=1.0,
            height=0.08,
            h_align="center",
            v_align="middle",
        )
    )

    # ---------------- SECTIONS ----------------
    # fontsize is passed explicitly: the LINE_FRAC constants that place
    # these are measured at BODY_SIZE, so inheriting PopupText's default of
    # 12 would silently invalidate every position above.
    for title, items, px, py, pw, ph in layout_sections():
        controls.append(
            PopupText(
                text=render_section(title, items),
                markup=True,
                fontsize=BODY_SIZE,
                pos_x=px,
                pos_y=py,
                width=pw,
                height=ph,
                h_align="left",
                v_align="top",
            )
        )

    # ---------------- FOOTER ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="small" foreground="{COLORS["muted"]}">'
                f' · <b><span foreground="{COLORS["blue"]}">Esc to close ·</span></b> '
                f" the Qtile Cheatsheet · </span>"
            ),
            markup=True,
            pos_x=0.0,
            pos_y=FOOTER_Y,
            width=1.0,
            height=0.05,
            h_align="center",
            v_align="middle",
        )
    )

    # ---------------- POPUP ----------------
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
    fade_in_popup(_CHEATSHEET_LAYOUT)


def close_qtile_cheatsheet():
    global _CHEATSHEET_LAYOUT
    if _CHEATSHEET_LAYOUT:
        _CHEATSHEET_LAYOUT.kill()
        _CHEATSHEET_LAYOUT = None


def show_qtile_cheatsheet(qtile):
    global _CHEATSHEET_LAYOUT

    if _CHEATSHEET_LAYOUT:
        return  # already open

    toggle_cheatsheet(qtile)
