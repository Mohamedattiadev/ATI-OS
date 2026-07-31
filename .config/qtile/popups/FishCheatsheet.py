from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups import _cheatsheet_grid as _grid

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
# COLORS — wal-derived (dominant = green slot). Re-read at each toggle so
# a wallpaper switch retints the popup without qtile restart.
# =============================================================================
from popups._wal_colors import load_colors as _load_colors
from popups._wal_colors import fade_in_popup
COLORS = _load_colors()


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
# GEOMETRY -- see popups/_cheatsheet_grid.py for why this is not a grid
# =============================================================================
# Sized for the 1366x768 reference panel with a little air on each side.
POPUP_W = 1300
POPUP_H = 730

# 11, not the PopupText default of 12. At 12 every column was ~40px wider
# than the cell it was given, so all nine wrapped, and Danger Zone ran 32px
# past the footer. This sheet is the smallest of the three, so it can
# afford the largest type: swept with pango, 11pt in 4 columns fits with
# room to spare.
BODY_SIZE = 11
N_COLS = 4

# Measured pango extents at "sans 11". Every section renders a divider rule
# under its title, so NOTE_PX is one body line and has_note is always true.
BODY_PX, TITLE_PX, NOTE_PX = 23, 27, 23

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
        has_note=lambda title: True,
        name="FishCheatsheet",
    )


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
        # kill(), not hide(): hide() only unmaps the window and leaves its
        # cairo drawer and pango layouts allocated, while the show path
        # below builds a brand new layout every time -- ~2.7MB leaked per
        # open at this popup's size.
        _FISH_KITTY_CHEATSHEET.kill()
        _FISH_KITTY_CHEATSHEET = None
        return

    COLORS.update(_load_colors())
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

    # ---------------- SECTIONS ----------------
    # fontsize is passed explicitly: BODY_PX/TITLE_PX are measured at
    # BODY_SIZE, so inheriting PopupText's default of 12 would invalidate
    # every position the packer computed.
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
                f' <span> the  Fish + Kitty workflow Cheatsheet · </span>'
                f'</span>'
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
    fade_in_popup(_FISH_KITTY_CHEATSHEET)


def close_fish_kitty_cheatsheet():
    global _FISH_KITTY_CHEATSHEET
    if _FISH_KITTY_CHEATSHEET:
        _FISH_KITTY_CHEATSHEET.kill()
        _FISH_KITTY_CHEATSHEET = None

def show_fish_kitty_cheatsheet(qtile):
    global _FISH_KITTY_CHEATSHEET
    if _FISH_KITTY_CHEATSHEET:
        return  # already open
    toggle_fish_kitty_cheatsheet(qtile)
    
