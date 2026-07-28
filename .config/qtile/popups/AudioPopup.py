import subprocess
import json
from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger
from popups._wal_colors import fade_in_popup

_LAYOUT = None
_QTILE = None

_OUTPUTS = []
_INPUTS = []

_OUT_INDEX = 0
_IN_INDEX = 0
_ACTIVE_COL = 0

_DEFAULT_OUT = None
_DEFAULT_IN = None

_STATUS_MSG = "Ready"

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


def icon_output(name):
    name = name.lower()

    if "hdmi" in name:
        return "󰟎"

    if "headphone" in name or "headset" in name:
        return "󰋋"

    if "bluetooth" in name:
        return "󰂯"

    return "󰕾"


def icon_input(name):
    return "󰍬"


# ------------------------------------------------
# GET AUDIO DEVICES
# ------------------------------------------------


def get_audio():
    outputs = []
    inputs = []

    try:
        out = subprocess.run(
            ["pactl", "-f", "json", "list", "sinks"],
            stdout=subprocess.PIPE,
            text=True,
            timeout=3,
        )

        data = json.loads(out.stdout)

        for d in data:
            outputs.append(
                {
                    "name": d["name"],
                    "label": d["description"],
                    "icon": icon_output(d["description"]),
                }
            )

        inp = subprocess.run(
            ["pactl", "-f", "json", "list", "sources"],
            stdout=subprocess.PIPE,
            text=True,
            timeout=3,
        )

        data = json.loads(inp.stdout)

        for d in data:
            if "monitor" in d["name"]:
                continue

            inputs.append(
                {
                    "name": d["name"],
                    "label": d["description"],
                    "icon": icon_input(d["description"]),
                }
            )

        default_out = subprocess.run(
            ["pactl", "get-default-sink"], stdout=subprocess.PIPE, text=True,
            timeout=2,
        ).stdout.strip()

        default_in = subprocess.run(
            ["pactl", "get-default-source"], stdout=subprocess.PIPE, text=True,
            timeout=2,
        ).stdout.strip()

        return outputs, inputs, default_out, default_in

    except subprocess.TimeoutExpired:
        logger.warning("AudioPopup get_audio: pactl timed out")
    except Exception as e:
        logger.error(e)

    return [], [], None, None


# ------------------------------------------------
# RENDER OUTPUTS
# ------------------------------------------------


def render_outputs():
    lines = []

    for i, d in enumerate(_OUTPUTS):
        label = d["label"]

        if d["name"] == _DEFAULT_OUT:
            label += " (Default)"

        if _ACTIVE_COL == 0 and i == _OUT_INDEX:
            text = (
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f" {d['icon']} {label}</span>"
            )

        else:
            color = COLORS["green"] if d["name"] == _DEFAULT_OUT else COLORS["fg"]

            text = f'<span foreground="{color}"> {d["icon"]} {label}</span>'

        lines.append(text)

    return "\n".join(lines)


# ------------------------------------------------
# RENDER INPUTS
# ------------------------------------------------


def render_inputs():
    lines = []

    for i, d in enumerate(_INPUTS):
        label = d["label"]

        if d["name"] == _DEFAULT_IN:
            label += " (Default)"

        if _ACTIVE_COL == 1 and i == _IN_INDEX:
            text = (
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f" {d['icon']} {label}</span>"
            )

        else:
            color = COLORS["blue"] if d["name"] == _DEFAULT_IN else COLORS["fg"]

            text = f'<span foreground="{color}"> {d["icon"]} {label}</span>'

        lines.append(text)

    return "\n".join(lines)


# ------------------------------------------------
# FOOTER
# ------------------------------------------------


def render_footer():
    msg = _STATUS_MSG.lower()

    color = COLORS["muted"]

    if "output" in msg:
        color = COLORS["green"]

    elif "mic" in msg:
        color = COLORS["blue"]

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
        outputs=render_outputs(),
        inputs=render_inputs(),
        footer=render_footer(),
    )


# ------------------------------------------------
# SELECT DEVICE
# ------------------------------------------------


def select():
    global _STATUS_MSG

    if _ACTIVE_COL == 0:
        dev = _OUTPUTS[_OUT_INDEX]

        try:
            subprocess.run(
                ["pactl", "set-default-sink", dev["name"]], timeout=2
            )
            _STATUS_MSG = f"Output → {dev['label']}"
        except subprocess.TimeoutExpired:
            _STATUS_MSG = "Output set timed out"

    else:
        dev = _INPUTS[_IN_INDEX]

        try:
            subprocess.run(
                ["pactl", "set-default-source", dev["name"]], timeout=2
            )
            _STATUS_MSG = f"Mic → {dev['label']}"
        except subprocess.TimeoutExpired:
            _STATUS_MSG = "Mic set timed out"

    refresh()


# ------------------------------------------------
# NAVIGATION
# ------------------------------------------------


def move(step):
    global _OUT_INDEX, _IN_INDEX

    if _ACTIVE_COL == 0:
        _OUT_INDEX = (_OUT_INDEX + step) % len(_OUTPUTS)
    else:
        _IN_INDEX = (_IN_INDEX + step) % len(_INPUTS)

    update()


def left():
    global _ACTIVE_COL
    _ACTIVE_COL = 0
    update()


def right():
    global _ACTIVE_COL
    _ACTIVE_COL = 1
    update()


# ------------------------------------------------
# REFRESH
# ------------------------------------------------


def refresh():
    global _OUTPUTS, _INPUTS, _DEFAULT_OUT, _DEFAULT_IN

    _OUTPUTS, _INPUTS, _DEFAULT_OUT, _DEFAULT_IN = get_audio()

    update()

    if _LAYOUT and _QTILE:
        _QTILE.call_later(5, refresh)


# ------------------------------------------------
# POPUP
# ------------------------------------------------


def show(qtile):
    global _LAYOUT, _QTILE

    if _LAYOUT:
        return

    _QTILE = qtile

    refresh()

    controls = [
        PopupText(
            text=(
                f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
                f"󰓃 AUDIO CONTROL</span>\n"
                f'<span foreground="{COLORS["muted"]}">'
                f'Navigate : <b><span foreground="{COLORS["green"]}">j k</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Columns : <b><span foreground="{COLORS["purple"]}">h l</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Select : <b><span foreground="{COLORS["green"]}">Enter</span></b>'
                f'<span foreground="{COLORS["blue"]}"><b> | </b></span>'
                f'Refresh : <b><span foreground="{COLORS["yellow"]}">r</span></b>'
                f"</span>"
            ),
            markup=True,
            pos_x=0.05,
            pos_y=0.05,
            width=0.9,
            height=0.14,
            h_align="center",
        ),
        PopupText(
            text=f'<span size="large" foreground="{COLORS["purple"]}" weight="bold">OUTPUT DEVICES</span>',
            markup=True,
            pos_x=0.05,
            pos_y=0.18,
            width=0.42,
            height=0.05,
        ),
        PopupText(
            text=f'<span size="large" foreground="{COLORS["purple"]}" weight="bold">MICROPHONES</span>',
            markup=True,
            pos_x=0.53,
            pos_y=0.18,
            width=0.42,
            height=0.05,
        ),
        PopupText(
            name="outputs",
            text=render_outputs(),
            markup=True,
            pos_x=0.05,
            pos_y=0.23,
            width=0.42,
            height=0.54,
        ),
        PopupText(
            name="inputs",
            text=render_inputs(),
            markup=True,
            pos_x=0.53,
            pos_y=0.23,
            width=0.42,
            height=0.54,
        ),
        PopupText(
            name="footer",
            text=render_footer(),
            markup=True,
            pos_x=0.05,
            pos_y=0.82,
            width=0.9,
            height=0.12,
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
    fade_in_popup(_LAYOUT)


# ------------------------------------------------
# CLOSE
# ------------------------------------------------


def close(qtile):
    global _LAYOUT

    if _LAYOUT:
        _LAYOUT.hide()
        _LAYOUT = None
