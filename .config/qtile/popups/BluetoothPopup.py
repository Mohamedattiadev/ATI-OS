import subprocess
import threading
import time
from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger
from popups._wal_colors import fade_in_popup

_LAYOUT = None
_QTILE = None
_DEVICES = []
_INDEX = 0
_STATUS_MSG = "Ready"
_PROGRESS = 0
_CONNECTING = False
_CONFIRMING = False

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
# DEVICE DISCOVERY
# ------------------------------------------------


def get_devices():
    devices = []

    try:
        result = subprocess.run(
            ["bluetoothctl", "devices"], stdout=subprocess.PIPE, text=True,
            timeout=5,
        )

        for line in result.stdout.splitlines():
            parts = line.split(" ", 2)

            if len(parts) < 3:
                continue

            mac = parts[1]
            name = parts[2]

            try:
                info = subprocess.run(
                    ["bluetoothctl", "info", mac], stdout=subprocess.PIPE, text=True,
                    timeout=3,
                ).stdout
            except subprocess.TimeoutExpired:
                info = ""

            connected = "Connected: yes" in info

            battery = None
            for l in info.splitlines():
                if "Battery Percentage" in l:
                    battery = l.split(":")[-1].strip()

            devices.append(
                {
                    "mac": mac,
                    "name": name,
                    "connected": connected,
                    "battery": battery,
                }
            )

    except Exception as e:
        logger.error(f"Bluetooth error: {e}")

    return devices


# ------------------------------------------------
# DEVICE LIST
# ------------------------------------------------


def render_devices():
    lines = []

    for i, d in enumerate(_DEVICES):
        icon = ""
        color = COLORS["fg"]

        if d["connected"]:
            icon = ""
            color = COLORS["green"]

        if i == _INDEX:
            text = (
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f" {icon} {d['name']}</span>"
            )
        else:
            text = f'<span foreground="{color}"> {icon} {d["name"]}</span>'

        lines.append(text)

    return "\n".join(lines)


# ------------------------------------------------
# DEVICE INFO PANEL
# ------------------------------------------------


def render_info():
    if not _DEVICES:
        return ""

    d = _DEVICES[_INDEX]

    battery = d["battery"] if d["battery"] else "Unknown"

    status = "Connected" if d["connected"] else "Disconnected"
    status_color = COLORS["green"] if d["connected"] else COLORS["red"]

    progress_bar = ""

    if _CONNECTING:
        filled = int(_PROGRESS / 10)

        bar = "█" * filled + "░" * (10 - filled)

        progress_bar = f"\n<span foreground='{COLORS['blue']}'>{bar}</span>"

    return (
        f"<b>{d['name']}</b>\n"
        f"<span foreground='{COLORS['muted']}'>MAC:</span> {d['mac']}\n"
        f"<span foreground='{COLORS['muted']}'>Battery:</span> {battery}\n"
        f"<span foreground='{COLORS['muted']}'>Status:</span> "
        f"<span foreground='{status_color}'>{status}</span>"
        f"{progress_bar}"
    )


# ------------------------------------------------
# FOOTER COLOR LOGIC
# ------------------------------------------------


def render_footer():
    msg = _STATUS_MSG.lower()

    color = COLORS["muted"]

    if "connecting" in msg:
        color = COLORS["blue"]

    elif "connected" in msg:
        color = COLORS["green"]

    elif "disconnect" in msg:
        color = COLORS["red"]

    elif "refresh" in msg:
        color = COLORS["yellow"]

    return f"<span foreground='{color}' weight='bold'>{_STATUS_MSG}</span>"


# ------------------------------------------------
# UI UPDATE
# ------------------------------------------------


def update_ui():
    if not _LAYOUT:
        return

    _LAYOUT.update_controls(
        devices=render_devices(),
        info=render_info(),
        footer=render_footer(),
    )


# ------------------------------------------------
# AUTO REFRESH
# ------------------------------------------------


def refresh():
    global _DEVICES

    _DEVICES = get_devices()

    update_ui()

    if _LAYOUT and _QTILE:
        _QTILE.call_later(7, refresh)


def reload_devices():
    global _STATUS_MSG

    _STATUS_MSG = "Refreshing device list..."

    refresh()


# ------------------------------------------------
# CONNECTION WORKER
# ------------------------------------------------


def connect_worker(device):
    global _STATUS_MSG, _PROGRESS, _CONNECTING

    _CONNECTING = True

    _STATUS_MSG = f"Connecting to {device['name']}..."

    for i in range(10):
        _PROGRESS = (i + 1) * 10

        # UI updates from thread must go through event loop.
        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(update_ui)

        time.sleep(0.15)

    try:
        subprocess.run(
            ["bluetoothctl", "connect", device["mac"]],
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        _STATUS_MSG = f"Timeout connecting to {device['name']}"
    else:
        _STATUS_MSG = f"Connected to {device['name']}"

    _CONNECTING = False
    _PROGRESS = 0

    if _QTILE is not None:
        _QTILE.call_soon_threadsafe(refresh)


# ------------------------------------------------
# CONNECT / DISCONNECT
# ------------------------------------------------


def toggle_device():
    device = _DEVICES[_INDEX]

    if device["connected"]:
        try:
            subprocess.run(
                ["bluetoothctl", "disconnect", device["mac"]],
                timeout=10,
            )
            _STATUS_MSG = f"Disconnected {device['name']}"
        except subprocess.TimeoutExpired:
            _STATUS_MSG = f"Timeout disconnecting {device['name']}"

        refresh()

    else:
        threading.Thread(
            target=connect_worker,
            args=(device,),
            daemon=True,
        ).start()


# ------------------------------------------------
# DISCONNECT CONFIRMATION
# ------------------------------------------------


def request_disconnect():
    global _STATUS_MSG, _CONFIRMING

    device = _DEVICES[_INDEX]

    if not device["connected"]:
        _STATUS_MSG = "Device not connected"

        update_ui()

        return

    _CONFIRMING = True

    _STATUS_MSG = f"⚠ Disconnect {device['name']} ?  [y] yes  [n] cancel"

    update_ui()


def confirm_disconnect(answer):
    global _CONFIRMING, _STATUS_MSG

    if not _CONFIRMING:
        return

    device = _DEVICES[_INDEX]

    if answer:
        subprocess.run(["bluetoothctl", "disconnect", device["mac"]])

        _STATUS_MSG = f"{device['name']} disconnected"

    else:
        _STATUS_MSG = "Cancelled"

    _CONFIRMING = False

    refresh()


# ------------------------------------------------
# NAVIGATION
# ------------------------------------------------


def move(step):
    global _INDEX

    if not _DEVICES:
        return

    _INDEX = (_INDEX + step) % len(_DEVICES)

    update_ui()


# ------------------------------------------------
# POPUP
# ------------------------------------------------


def show(qtile):
    global _LAYOUT, _DEVICES, _INDEX, _QTILE

    if _LAYOUT:
        return

    _QTILE = qtile

    _DEVICES = get_devices()

    _INDEX = 0

    controls = [
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰂯  BLUETOOTH MANAGER</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f'Navigate : <b><span foreground="{COLORS["green"]}">j k</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Connect : <b><span foreground="{COLORS["green"]}">Enter</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Disconnect : <b><span foreground="{COLORS["red"]}">x</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Refresh : <b><span foreground="{COLORS["yellow"]}">r</span></b>'
                f"</span>"
            ),
            markup=True,
            pos_x=0.05,
            pos_y=0.05,
            width=0.9,
            height=0.12,
            h_align="center",
        ),
        PopupText(
            name="devices",
            text=render_devices(),
            markup=True,
            pos_x=0.05,
            pos_y=0.20,
            width=0.4,
            height=0.60,
            h_align="left",
        ),
        PopupText(
            name="info",
            text=render_info(),
            markup=True,
            pos_x=0.48,
            pos_y=0.20,
            width=0.47,
            height=0.60,
            h_align="left",
        ),
        PopupText(
            name="footer",
            text=render_footer(),
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
        width=720,
        height=420,
        background=COLORS["bg"] + "F2",
        controls=controls,
        close_on_click=False,
    )

    _LAYOUT.show(centered=True)
    fade_in_popup(_LAYOUT)

    qtile.call_later(7, refresh)


# ------------------------------------------------
# CLOSE
# ------------------------------------------------


def close(qtile):
    global _LAYOUT

    if _LAYOUT:
        _LAYOUT.hide()
        _LAYOUT = None
