from qtile_extras.popup import PopupRelativeLayout, PopupText

# =============================================================================
# GLOBAL STATE (toggle)
# =============================================================================
_CHEATSHEET_LAYOUT = None

# =============================================================================
# COLORS (Doom One)
# =============================================================================
COLORS = {
    "bg": "#1c1f24",
    "fg": "#bbc2cf",
    "muted": "#5b6268",
    "green": "#98be65",
    "blue": "#51afef",
    "purple": "#c678dd",
    "red": "#ff6c6b",
}

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
        ("CheetSheet", "Super + Shift + k"),
        ("Toggle Normal bar ", "Mod + Shift + z"),
        ("Logout menu", "Mod + Shift + q"),
        ("Close notification", "Super + n"),
        ("Remap Alt (sys)", "Super + Shift + R"),
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
        ("Cpu-Memo-Battery widget", "Super + `"),
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
    "ROFI MODE": [
        ("Translate text", "e"),
        ("Add Anki note", "a"),
        ("Screenshots", "i"),
        ("man pages", "m"),
        ("Video recorder", "r"),
        ("Close All notifications", "x"),
        ("Light / Britness", "l"),
        ("Config editor", "f"),
        ("Password menu", "p"),
        ("YouTube menu", "y"),
        ("Kill process", "k"),
        ("Spell check", "s"),
        ("Weather", "w"),
        ("Todo manager", "t"),
        ("Wallpaper picker", "b"),
        ("Saved Links", "z"),
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
        _CHEATSHEET_LAYOUT.hide()
        _CHEATSHEET_LAYOUT = None
        return

    controls = []

    # ---------------- TITLE ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰆍  QTILE CHEATSHEET</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f'Mod = <b><span foreground="{COLORS["green"]}">Alt</span></b> '
                f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span> '
                f'Super = <b><span foreground="{COLORS["purple"]}">Win</span></b>'
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

    # ---------------- GRID ----------------
    column_width = 0.21

    gap_x = 0.03
    gap_y = 0.03
    start_x = 0.05
    start_y = 0.16
    MAX_COLS = 4
    ROW_HEIGHT = 0.25

    for i, (title, items) in enumerate(COLUMNS):
        col = i % MAX_COLS
        row = i // MAX_COLS

        controls.append(
            PopupText(
                text=render_section(title, items),
                markup=True,
                pos_x=start_x + col * (column_width + gap_x),
                pos_y=start_y + row * (ROW_HEIGHT + gap_y),
                width=column_width,
                height=ROW_HEIGHT,
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
            pos_y=0.93,
            width=1.0,
            height=0.05,
            h_align="center",
            v_align="middle",
        )
    )

    # ---------------- POPUP ----------------
    _CHEATSHEET_LAYOUT = PopupRelativeLayout(
        qtile,
        width=1050,
        height=680,
        background="1c1f24ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )

    _CHEATSHEET_LAYOUT.show(centered=True)


def close_qtile_cheatsheet():
    global _CHEATSHEET_LAYOUT
    if _CHEATSHEET_LAYOUT:
        _CHEATSHEET_LAYOUT.hide()
        _CHEATSHEET_LAYOUT = None


def show_qtile_cheatsheet(qtile):
    global _CHEATSHEET_LAYOUT

    if _CHEATSHEET_LAYOUT:
        return  # already open

    toggle_cheatsheet(qtile)
