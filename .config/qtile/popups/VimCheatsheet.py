from qtile_extras.popup import PopupRelativeLayout, PopupText

# =============================================================================
# GLOBAL STATE
# =============================================================================
_VIM_CHEATSHEET = None


def escape_markup(text: str) -> str:
    return (
        text
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )

# =============================================================================
# COLORS (Doom One – same as Qtile)
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
"Basic 2": [

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

"Basic 3": [

    # --- Editing basics ---
    ("Insert mode", "i"),
    ("Append after cursor", "a"),
    ("Append end of line", "Shift + a "),
    ("Delete char", "x"),
    ("Delete line", "dd"),
    ("Delete word", "dw"),
    ("Change word", "cw"),
],

    "Movement + Extras": [
        ("Fast move (x5)", "<tab> + h j k l"),
        ("Next tab", "L"),
        ("Prev tab", "H"),
        ("Split Terminal", "<leader> + tt"),
    ],

    "Editing": [
        ("Copy (yanking)", "y"),
        ("Copy line", "Shift + y"),
        ("Paste ", "p"),
        ("Move line down (v) ", "Shift + J "),
        ("Move line up (v)", "Shift + K"),
        ("replace cururent word", "c + i + w"),
        ("replace inside parn. ()", "c + i + b"),
        ("replace inside quo. '' ", "c + i + q")
    ],

    "Buffers / Tabs": [
        ("New tab", "<leader> bn"),
        ("Switch tab →", "Shift + l"),
        ("Switch tab ←", "Shift + h"),
    ],

    "Search / Telescope": [
        ("Find files", "<leader> + ff"),
        ("Find files 2", "<leader> <leader>"),
        ("Find recent files", "<leader> + oo"),
        ("Live grep", "<leader> + fg"),
        ("Word under cursor", "<leader> + fw"),
        ("Find Todos", "<leader> + ft"), 
        ("Find recent Buffers", "<leader> + bb"),
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
        ("Save file", "<leader> + w"),
        ("Quit", "<leader> q"),
        ("Quit all", "<leader> <leader> q"),
        ("Close buffer", "<leader> bd"),
        ("Clear search ", "Escape"),
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
        is_exit = any(k in label.lower() for k in ("quit", "close", "delete"))
        combo_color = COLORS["red"] if is_exit else COLORS["green"]

        safe_label = escape_markup(label)
        safe_combo = escape_markup(combo)

        lines.append(
            f'<span foreground="{COLORS["muted"]}">•</span> '
            f'<span foreground="{COLORS["fg"]}">{safe_label} :</span> '
            f'<b><span foreground="{combo_color}">{safe_combo}</span></b>'
        )

    return "\n".join(lines)

# =============================================================================
# TOGGLE FUNCTION
# =============================================================================
def toggle_vim_cheatsheet(qtile):
    global _VIM_CHEATSHEET

    if _VIM_CHEATSHEET:
        _VIM_CHEATSHEET.hide()
        _VIM_CHEATSHEET = None
        return

    controls = []

    # ---------------- TITLE ----------------
    controls.append(
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f'  VIM CHEATSHEET</span>\n'
            #     f'<span foreground="{COLORS["muted"]}">'
            #     f'Leader = <b><span foreground="{COLORS["green"]}">Space</span></b>'
            #     f'<b><span foreground="{COLORS["green"]}">|</span></b>'
            #     f'Visual mode = <b><span foreground="{COLORS["green"]}">(v)</span></b>'
            #     f'Normal mode = <b><span foreground="{COLORS["green"]}">(n)</span></b>'
            #     f'</span>'
            # ),

                f'<span foreground="{COLORS["muted"]}">'
                f'Leader = <b><span foreground="{COLORS["green"]}">Space</span></b> '
                f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span> '
                f'Visual Mode = <b><span foreground="{COLORS["purple"]}">(v)</span></b>'
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
                f' <span> the  Vim Cheatsheet · </span>'
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

    _VIM_CHEATSHEET = PopupRelativeLayout(
        qtile,
        width=1050,
        height=680,
        background="1c1f24ee",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )

    _VIM_CHEATSHEET.show(centered=True)

def close_vim_cheatsheet():
    global _VIM_CHEATSHEET
    if _VIM_CHEATSHEET:
        _VIM_CHEATSHEET.hide()
        _VIM_CHEATSHEET = None

def show_vim_cheatsheet(qtile):
    global _VIM_CHEATSHEET
    if _VIM_CHEATSHEET:
        return  # already open
    toggle_vim_cheatsheet(qtile)
