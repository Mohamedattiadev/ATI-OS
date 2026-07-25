import subprocess
import threading
import time
from qtile_extras.popup import PopupRelativeLayout, PopupText

_LAYOUT = None
_QTILE = None

_NETWORKS = []

_ROW = 0
_COL = 0

_STATUS_MSG = "Ready"

_PROGRESS = 0
_CONNECTING = False
_REFRESHING = False

COLS = 2

COLORS = {
    "bg": "#1c1f24",
    "fg": "#bbc2cf",
    "blue": "#51afef",
    "green": "#98be65",
    "red": "#ff6c6b",
    "yellow": "#ECBE7B",
    "purple": "#c678dd",
    "muted": "#5b6268",
    "highlight_bg": "#51afef",
    "highlight_fg": "#1c1f24",
}


# ------------------------------------------------
# ICONS
# ------------------------------------------------


def icon_signal(signal):
    s = int(signal)

    if s > 80:
        return "󰤨   "

    if s > 60:
        return "󰤥   "

    if s > 40:
        return "󰤢   "

    if s > 20:
        return "󰤟   "

    return "󰤯   "


# ------------------------------------------------
# GET NETWORKS
# ------------------------------------------------


def get_networks():
    networks = []

    try:
        out = subprocess.run(
            ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi"],
            stdout=subprocess.PIPE,
            text=True,
            timeout=10,
        )

        for line in out.stdout.splitlines():
            active, ssid, signal, security = line.split(":")

            if not ssid:
                continue

            networks.append(
                {
                    "ssid": ssid,
                    "signal": signal,
                    "secure": security != "",
                    "active": active == "yes",
                }
            )

    except Exception:
        pass

    return networks


# ------------------------------------------------
# SPLIT NETWORKS INTO COLUMNS
# ------------------------------------------------


def split_columns():
    cols = [[] for _ in range(COLS)]

    for i, net in enumerate(_NETWORKS):
        cols[i % COLS].append((i, net))

    return cols


# ------------------------------------------------
# RENDER NETWORK COLUMNS
# ------------------------------------------------


def render_column(col):
    cols = split_columns()

    if col >= len(cols):
        return ""

    lines = []

    for row, (idx, net) in enumerate(cols[col]):
        icon = icon_signal(net["signal"])

        label = net["ssid"]

        if net["active"]:
            label += " (Connected)"

        if row == _ROW and col == _COL:
            text = (
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f"{icon}{label}</span>"
            )

        else:
            color = COLORS["green"] if net["active"] else COLORS["fg"]

            text = f'<span foreground="{color}">{icon}{label}</span>'

        lines.append(text)

    return "\n".join(lines)


# ------------------------------------------------
# STATUS PANEL
# ------------------------------------------------


def render_info():
    cols = split_columns()

    if not cols:
        return ""

    idx, net = cols[_COL][_ROW]

    security = "🔒 Secured" if net["secure"] else "🔓 Open"

    status = "Connected" if net["active"] else "Disconnected"

    status_color = COLORS["green"] if net["active"] else COLORS["red"]

    progress_bar = ""

    if _CONNECTING:
        filled = int(_PROGRESS / 10)

        bar = "█" * filled + "░" * (10 - filled)

        progress_bar = f"\n\n<span foreground='{COLORS['blue']}'>{bar}</span>"

    return (
        f"<b>{net['ssid']}</b>\n\n"
        f"<span foreground='{COLORS['muted']}'>Signal:</span> {net['signal']}%\n"
        f"<span foreground='{COLORS['muted']}'>Security:</span> {security}\n"
        f"<span foreground='{COLORS['muted']}'>Status:</span> "
        f"<span foreground='{status_color}'>{status}</span>"
        f"{progress_bar}"
    )


# ------------------------------------------------
# FOOTER
# ------------------------------------------------


def render_footer():
    msg = _STATUS_MSG.lower()

    color = COLORS["muted"]

    if "connecting" in msg:
        color = COLORS["blue"]

    elif "connected" in msg:
        color = COLORS["green"]

    elif "refresh" in msg:
        color = COLORS["yellow"]

    elif "error" in msg:
        color = COLORS["red"]

    return f"<span foreground='{color}' weight='bold'>{_STATUS_MSG}</span>"


# ------------------------------------------------
# UPDATE UI
# ------------------------------------------------


def update():
    if not _LAYOUT:
        return

    _LAYOUT.update_controls(
        col1=render_column(0),
        col2=render_column(1),
        info=render_info(),
        footer=render_footer(),
    )


# ------------------------------------------------
# WIFI CONNECTION WORKER
# ------------------------------------------------


def connect_worker(network):
    global _STATUS_MSG, _PROGRESS, _CONNECTING

    _CONNECTING = True

    _STATUS_MSG = f"Connecting to {network['ssid']}..."

    for i in range(10):
        _PROGRESS = (i + 1) * 10

        # UI updates from thread must go through event loop.
        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(update)

        time.sleep(0.15)

    try:
        subprocess.run(
            ["nmcli", "dev", "wifi", "connect", network["ssid"]],
            stdout=subprocess.PIPE,
            timeout=30,
        )
        _STATUS_MSG = f"Connected → {network['ssid']}"
    except subprocess.TimeoutExpired:
        _STATUS_MSG = f"Timeout connecting to {network['ssid']}"

    _CONNECTING = False
    _PROGRESS = 0

    if _QTILE is not None:
        _QTILE.call_soon_threadsafe(refresh)


# ------------------------------------------------
# REFRESH WORKER
# ------------------------------------------------


def refresh_worker():
    global _NETWORKS, _STATUS_MSG, _REFRESHING

    _REFRESHING = True

    def start_msg():
        global _STATUS_MSG
        _STATUS_MSG = "Refreshing WiFi networks..."
        update()

    def finish_refresh():
        global _NETWORKS, _STATUS_MSG, _REFRESHING
        _NETWORKS = get_networks()
        _REFRESHING = False
        update()
        _STATUS_MSG = "Ready"

    # schedule UI update safely
    _QTILE.call_soon_threadsafe(start_msg)

    # fetch networks in background
    nets = get_networks()

    # schedule UI update safely
    def apply():
        global _NETWORKS
        _NETWORKS = nets
        finish_refresh()

    _QTILE.call_soon_threadsafe(apply)


# ------------------------------------------------
# CONNECT
# ------------------------------------------------


def select():
    cols = split_columns()

    idx, net = cols[_COL][_ROW]

    threading.Thread(
        target=connect_worker,
        args=(net,),
        daemon=True,
    ).start()


# ------------------------------------------------
# NAVIGATION
# ------------------------------------------------


def move_vertical(step):
    global _ROW

    cols = split_columns()

    if not cols:
        return

    max_row = len(cols[_COL]) - 1

    _ROW = max(0, min(max_row, _ROW + step))

    update()


def move_horizontal(step):
    global _COL, _ROW

    _COL = (_COL + step) % COLS

    cols = split_columns()

    if _ROW >= len(cols[_COL]):
        _ROW = len(cols[_COL]) - 1

    update()


# ------------------------------------------------
# REFRESH
# ------------------------------------------------


def manual_refresh():
    threading.Thread(
        target=refresh_worker,
        daemon=True,
    ).start()


def refresh():
    global _NETWORKS

    if _REFRESHING:
        if _LAYOUT and _QTILE:
            _QTILE.call_later(6, refresh)
        return

    _NETWORKS = get_networks()

    update()

    if _LAYOUT and _QTILE:
        _QTILE.call_later(6, refresh)


# ------------------------------------------------
# POPUP
# ------------------------------------------------


def show(qtile):
    global _LAYOUT, _QTILE

    if _LAYOUT:
        return

    _QTILE = qtile

    controls = [
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰤨   WIFI NETWORKS</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f'Navigate : <b><span foreground="{COLORS["green"]}">j k</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Columns : <b><span foreground="{COLORS["purple"]}">h l</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Connect : <b><span foreground="{COLORS["green"]}">Enter</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Refresh : <b><span foreground="{COLORS["yellow"]}">r</span></b>'
                f"</span>"
            ),
            markup=True,
            pos_x=0.05,
            pos_y=0.05,
            width=0.9,
            height=0.13,
            h_align="center",
        ),
        PopupText(
            name="col1", markup=True, pos_x=0.05, pos_y=0.24, width=0.28, height=0.56
        ),
        PopupText(
            name="col2", markup=True, pos_x=0.35, pos_y=0.24, width=0.28, height=0.56
        ),
        PopupText(
            name="info", markup=True, pos_x=0.65, pos_y=0.24, width=0.30, height=0.56
        ),
        PopupText(
            name="footer",
            markup=True,
            pos_x=0.05,
            pos_y=0.83,
            width=0.9,
            height=0.10,
            h_align="center",
        ),
    ]

    _LAYOUT = PopupRelativeLayout(
        qtile,
        width=760,
        height=440,
        background=COLORS["bg"] + "F2",
        controls=controls,
        close_on_click=False,
    )

    _LAYOUT.show(centered=True)

    refresh()


# ------------------------------------------------
# CLOSE
# ------------------------------------------------


def close(qtile):
    global _LAYOUT

    if _LAYOUT:
        _LAYOUT.hide()
        _LAYOUT = None
