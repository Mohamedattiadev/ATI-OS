from qtile_extras.popup import PopupRelativeLayout, PopupText

# =============================================================================
# GLOBAL STATE
# =============================================================================
_FISH_KITTY_CHEATSHEET = None


def escape_markup(text: str) -> str:
    return (
        text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
    )


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


# =============================================================================
# CHEATSHEET DATA (Fish + Kitty)
# =============================================================================
CHEATSHEET = {
    "Fish Most Used": [
        ("Clear", "cl"),
        ("Exit", "ex"),
        ("Reload config", "src"),
        ("Reset terminal", "reset"),
        ("vim+tmux (remote)", "vim 'filename'"),
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
        ("zoxide history", "z 'file/foldername'"),
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
        ("Kill tmux server", "tmux kill-server"),
        ("Cleanup orphans", "cleanup"),
    ],
}

COLUMNS = list(CHEATSHEET.items())


# =============================================================================
# TEXT RENDERER
# =============================================================================
def render_section(title, items):
    lines = [
        f'<span size="large" weight="bold" foreground="{COLORS["purple"]}">{title}</span>',
        f'<span foreground="{COLORS["muted"]}">────────────────</span>',
    ]

    for label, combo in items:
        is_danger = any(k in label.lower() for k in ("kill", "exit", "cleanup"))
        combo_color = COLORS["red"] if is_danger else COLORS["green"]

        lines.append(
            f'<span foreground="{COLORS["muted"]}">•</span> '
            f'<span foreground="{COLORS["fg"]}">{escape_markup(label)} :</span> '
            f'<b><span foreground="{combo_color}">{escape_markup(combo)}</span></b>'
        )

    return "\n".join(lines)


# =============================================================================
# TOGGLE FUNCTION
# =============================================================================
def toggle_fish_kitty_cheatsheet(qtile):
    global _FISH_KITTY_CHEATSHEET

    if _FISH_KITTY_CHEATSHEET:
        _FISH_KITTY_CHEATSHEET.hide()
        _FISH_KITTY_CHEATSHEET = None
        return

    controls = []

    # ---------------- TITLE ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f'󰈺  FISH + KITTY</span>\n'
                f'<span foreground="{COLORS["green"]}">'
                f'Vi-mode<span foreground="{COLORS["blue"]}"><b>  |  </b></span> '
                f'<b><span foreground="{COLORS["blue"]}">Meow</span></b> '
                f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span> '
                f'<b><span foreground="{COLORS["purple"]}">Termianl</span></b>'
                f'</span>'
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
                f' <span> the  Fish + Kitty workflow Cheatsheet · </span>'
                f'</span>'
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

    _FISH_KITTY_CHEATSHEET = PopupRelativeLayout(
        qtile,
        width=1050,
        height=680,
        background="1c1f24ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )

    _FISH_KITTY_CHEATSHEET.show(centered=True)


def close_fish_kitty_cheatsheet():
    global _FISH_KITTY_CHEATSHEET
    if _FISH_KITTY_CHEATSHEET:
        _FISH_KITTY_CHEATSHEET.hide()
        _FISH_KITTY_CHEATSHEET = None

def show_fish_kitty_cheatsheet(qtile):
    global _FISH_KITTY_CHEATSHEET
    if _FISH_KITTY_CHEATSHEET:
        return  # already open
    toggle_fish_kitty_cheatsheet(qtile)
    
