import subprocess
import textwrap
import threading
from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger
from popups._wal_colors import fade_in_popup

_LAYOUT = None
_QTILE = None

_UPDATES = []

_INDEX = 0
_COL_OFFSET = 0

_SELECTED = set()

_STATUS = "Ready"
_CONFIRM = None

ROWS_PER_COL = 18
COL_COUNT = 2


COLORS = {
    "bg": "#1c1f24",
    "fg": "#bbc2cf",
    "muted": "#5b6268",
    "blue": "#51afef",
    "green": "#98be65",
    "purple": "#c678dd",
    "red": "#ff6c6b",
    "highlight_bg": "#51afef",
    "highlight_fg": "#1c1f24",
}


# ------------------------------------------------
# LOAD PACMAN UPDATES
# ------------------------------------------------


def load_updates():
    updates = []

    try:
        result = subprocess.run(
            ["pacman", "-Qu"],
            stdout=subprocess.PIPE,
            text=True,
            timeout=15,
        )

        for line in result.stdout.splitlines():
            p = line.split()

            if len(p) >= 4:
                updates.append(
                    {
                        "name": p[0],
                        "old": p[1],
                        "new": p[3],
                    }
                )

    except Exception:
        pass

    return updates


# ------------------------------------------------
# POSITION
# ------------------------------------------------


def index_to_pos(i):
    return i % ROWS_PER_COL, i // ROWS_PER_COL


def pos_to_index(row, col):
    idx = col * ROWS_PER_COL + row

    if 0 <= idx < len(_UPDATES):
        return idx

    return None


# ------------------------------------------------
# COLUMN RENDER
# ------------------------------------------------


def render_column(visible_col):
    lines = []

    actual_col = visible_col + _COL_OFFSET

    for row in range(ROWS_PER_COL):
        idx = pos_to_index(row, actual_col)

        if idx is None:
            break

        pkg = _UPDATES[idx]

        if idx in _SELECTED:
            icon = f'<span foreground="{COLORS["purple"]}">☑</span>'
            label = f"{icon} <span foreground='{COLORS['purple']}'>{pkg['name']}</span>"
        else:
            icon = "☐"
            label = f"{icon} {pkg['name']}"

        if idx == _INDEX:
            text = (
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f"{label}</span>"
            )

        else:
            text = f'<span foreground="{COLORS["fg"]}">{label}</span>'

        lines.append(text)

    return "\n".join(lines)


# ------------------------------------------------
# INFO PANEL
# ------------------------------------------------


def render_info():
    if not _UPDATES:
        return "System up to date"

    pkg = _UPDATES[_INDEX]["name"]
    old = _UPDATES[_INDEX]["old"]
    new = _UPDATES[_INDEX]["new"]

    repo = ""
    desc = ""
    size = ""

    try:
        info = subprocess.run(
            ["pacman", "-Si", pkg], stdout=subprocess.PIPE, text=True,
            timeout=5,
        ).stdout

        for line in info.splitlines():
            if line.startswith("Repository"):
                repo = line.split(":")[1].strip()

            elif line.startswith("Installed Size"):
                size = line.split(":")[1].strip()

            elif line.startswith("Description"):
                desc_raw = line.split(":", 1)[1].strip()
                desc = "\n".join(textwrap.wrap(desc_raw, 40))

    except Exception:
        pass

    return (
        f'<span foreground="{COLORS["blue"]}" weight="bold">{pkg}</span>\n\n'
        f'<span foreground="{COLORS["muted"]}">Repo:</span> '
        f'<span foreground="{COLORS["purple"]}">{repo}</span>\n'
        f'<span foreground="{COLORS["muted"]}">Version:</span> '
        f'{old} → <span foreground="{COLORS["green"]}">{new}</span>\n'
        f'<span foreground="{COLORS["muted"]}">Size:</span> {size}\n\n'
        f'<span foreground="{COLORS["muted"]}">{desc}</span>'
    )


# ------------------------------------------------
# FOOTER
# ------------------------------------------------


def render_footer():
    percent = int(((_INDEX + 1) / max(1, len(_UPDATES))) * 100)

    return (
        f'<span foreground="{COLORS["blue"]}" weight="bold">󰏖 UPDATES</span> '
        f'<span foreground="{COLORS["muted"]}">│</span> '
        f'<span foreground="{COLORS["green"]}">{_STATUS}</span> '
        f'<span foreground="{COLORS["muted"]}">│</span> '
        f'<span foreground="{COLORS["purple"]}">{percent}%</span>'
        f'<span foreground="{COLORS["muted"]}"> of {len(_UPDATES)}</span>'
    )


# ------------------------------------------------
# VIEWPORT
# ------------------------------------------------


def ensure_visible():
    global _COL_OFFSET

    row, col = index_to_pos(_INDEX)

    if col < _COL_OFFSET:
        _COL_OFFSET = col

    elif col >= _COL_OFFSET + COL_COUNT:
        _COL_OFFSET = col - COL_COUNT + 1


# ------------------------------------------------
# UPDATE UI
# ------------------------------------------------


def update_ui():
    if _LAYOUT is None:
        return

    updates = {}

    updates["info"] = render_info()
    updates["footer"] = render_footer()

    for c in range(COL_COUNT):
        updates[f"col{c}"] = render_column(c)

    _LAYOUT.update_controls(**updates)


# ------------------------------------------------
# NAVIGATION
# ------------------------------------------------


def move(drow=0, dcol=0):
    global _INDEX

    row, col = index_to_pos(_INDEX)

    idx = pos_to_index(row + drow, col + dcol)

    if idx is None:
        return

    _INDEX = idx

    ensure_visible()

    update_ui()


# ------------------------------------------------
# SELECT
# ------------------------------------------------


def toggle_select():
    if _INDEX in _SELECTED:
        _SELECTED.remove(_INDEX)

    else:
        _SELECTED.add(_INDEX)

    update_ui()


# ------------------------------------------------
# UPDATE REQUEST
# ------------------------------------------------


def request_update():
    global _STATUS, _CONFIRM

    if not _SELECTED:
        _STATUS = "No packages selected"

        update_ui()

        return

    _STATUS = "Update selected packages? y/n"

    _CONFIRM = "update"

    update_ui()


# ------------------------------------------------
# IGNORE SELECTED (NO CONFIRM)
# ------------------------------------------------


def ignore_selected():
    global _STATUS

    if not _SELECTED:
        _STATUS = "Nothing selected"
        update_ui()
        return

    pkgs = [_UPDATES[i]["name"] for i in _SELECTED]
    pkg_string = " ".join(pkgs)

    cmd = f"setsid bash -c 'sudo pacman -D --ignore {pkg_string}'"
    _QTILE.spawn(cmd)

    _STATUS = f"Ignored: {pkg_string}"

    _SELECTED.clear()

    update_ui()


# ------------------------------------------------
# CONFIRM
# ------------------------------------------------


def confirm(answer):
    global _CONFIRM, _STATUS

    if not _CONFIRM:
        return

    if not answer:
        _STATUS = "Cancelled"

        _CONFIRM = None

        update_ui()

        return

    pkgs = [_UPDATES[i]["name"] for i in _SELECTED]

    if _CONFIRM == "update":
        cmd = "setsid kitty -e sudo pacman -S " + " ".join(pkgs)

        _QTILE.spawn(cmd)

        _STATUS = "Opening pacman..."

    # elif _CONFIRM == "ignore":
    #     pkg_string = " ".join(pkgs)
    #
    #     cmd = f"setsid bash -c 'sudo pacman -D --ignore {pkg_string}'"
    #
    #     _QTILE.spawn(cmd)
    #
    #     _STATUS = "Ignored"

    _SELECTED.clear()

    _CONFIRM = None

    update_ui()


# ------------------------------------------------
# ROFI SEARCH
# ------------------------------------------------


def rofi_search():
    names = "\n".join(p["name"] for p in _UPDATES)

    def _run_rofi():
        try:
            result = subprocess.run(
                ["rofi", "-dmenu", "-p", "Search package"],
                input=names,
                text=True,
                stdout=subprocess.PIPE,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            return
        except Exception as e:
            logger.warning("UpdatesPopup rofi_search failed: %s", e)
            return

        choice = result.stdout.strip()
        if not choice:
            return

        def _apply():
            global _INDEX
            for i, p in enumerate(_UPDATES):
                if p["name"] == choice:
                    _INDEX = i
                    ensure_visible()
                    update_ui()
                    break

        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(_apply)

    threading.Thread(target=_run_rofi, daemon=True).start()


# ------------------------------------------------
# CLOSE
# ------------------------------------------------


def close(qtile):
    global _LAYOUT

    if _LAYOUT:
        _LAYOUT.hide()

        _LAYOUT = None


# ------------------------------------------------
# POPUP
# ------------------------------------------------


def show(qtile):
    global _LAYOUT, _QTILE, _UPDATES

    if _LAYOUT:
        return

    _QTILE = qtile

    # Load updates in background — pacman -Qu can take seconds if db is busy.
    _UPDATES = []

    def _bg_load():
        nets = load_updates()
        def _apply():
            global _UPDATES
            _UPDATES = nets
            update_ui()
        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(_apply)

    threading.Thread(target=_bg_load, daemon=True).start()

    controls = []

    # controls.append(
    #     PopupText(
    #         text=(
    #             f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
    #             f"󰏖 SYSTEM UPDATES</span>\n"
    #             f'<span foreground="{COLORS["muted"]}">'
    #             f"Navigate : <b>hjkl</b> │ Select : <b>space</b> │ Search : <b>/</b> │ Update : <b>Enter</b> │ Ignore : <b>x</b>"
    #             f"</span>"
    #         ),
    #         markup=True,
    #         pos_x=0.05,
    #         pos_y=0.05,
    #         width=0.9,
    #         height=0.12,
    #         h_align="center",
    #     )
    # )

    controls.append(
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰏖 SYSTEM UPDATES</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f"Navigate : </span>"
                f'<span foreground="{COLORS["green"]}"><b>hjkl</b></span>'
                f'<span foreground="{COLORS["muted"]}"> │ Select : </span>'
                f'<span foreground="{COLORS["green"]}"><b>space</b></span>'
                f'<span foreground="{COLORS["muted"]}"> │ Search : </span>'
                f'<span foreground="{COLORS["purple"]}"><b>/</b></span>'
                f'<span foreground="{COLORS["muted"]}"> │ Update : </span>'
                f'<span foreground="{COLORS["blue"]}"><b>Enter</b></span>'
                f'<span foreground="{COLORS["muted"]}"> │ Ignore : </span>'
                f'<span foreground="{COLORS["red"]}"><b>X</b></span>'
            ),
            markup=True,
            pos_x=0.05,
            pos_y=0.05,
            width=0.9,
            height=0.12,
            h_align="center",
        )
    )
    start_x = 0.05
    col_width = 0.28
    gap = 0.02

    for c in range(COL_COUNT):
        controls.append(
            PopupText(
                name=f"col{c}",
                markup=True,
                pos_x=start_x + c * (col_width + gap),
                pos_y=0.22,
                width=col_width,
                height=0.60,
                h_align="left",
            )
        )

    controls.append(
        PopupText(
            name="info",
            markup=True,
            pos_x=0.65,
            pos_y=0.22,
            width=0.30,
            height=0.60,
        )
    )

    controls.append(
        PopupText(
            name="footer",
            markup=True,
            pos_x=0.05,
            pos_y=0.85,
            width=0.9,
            height=0.1,
            h_align="center",
        )
    )

    _LAYOUT = PopupRelativeLayout(
        qtile,
        width=820,
        height=560,
        background=COLORS["bg"] + "F2",
        controls=controls,
        close_on_click=False,
    )

    _LAYOUT.show(centered=True)
    fade_in_popup(_LAYOUT)

    update_ui()
