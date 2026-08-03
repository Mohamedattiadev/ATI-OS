"""Bluetooth device picker, backed by bluetoothctl.

Everything happens in this popup: scan, pair, trust, connect, disconnect and
remove. No blueman window is involved.

The traps this file exists to work around, all found the hard way against
bluez 5.87:

* `bluetoothctl connect <mac>` on a device that is out of range **never
  returns**. Every command therefore carries a timeout, and the connect-class
  ones carry a generous but finite one; subprocess kills the child when it
  expires.
* `bluetoothctl devices` embeds ANSI colour escapes even when its output is
  piped, so every line is stripped before it is parsed.
* bluez **forgets unpaired devices as soon as discovery stops**, so a
  scan-then-list design shows a list that empties itself moments later.
  Discovery therefore runs for as long as the popup is open, as a child
  process that is killed on close (leaving it running would keep the radio
  discovering for nothing).
* `bluetoothctl info <mac>` costs one process per device, so the list view is
  built from the four cheap `devices [Paired|Connected|Trusted]` queries and
  `info` is only asked for the devices that can actually use it: the paired
  ones (icon, battery) and whichever row is selected.

Pairing note: bluez asks a registered agent to confirm pairing. "Just works"
devices -- headphones, speakers, mice -- need no interaction. A device that
insists on a passkey will hand the prompt to whatever agent is registered on
the session (blueman-applet, if it is running).
"""

import re
import subprocess
import threading

from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger

from popups._scale import s as _s
from popups._wal_colors import load_colors as _load_wal_colors
from popups._wal_colors import fade_in_popup, fade_out_popup
from popups._wal_colors import _mix, ensure_contrast

# =============================================================================
# GLOBAL STATE
# =============================================================================
_LAYOUT = None
_QTILE = None
_CLOSING = False
_SESSION = 0

_DEVICES = []      # [{mac, name, paired, trusted, connected, icon, battery, rssi}]
_INDEX = 0
_OFFSET = 0

_POWERED = True
_ADAPTER = ""
_DISCOVERING = False
_INFO = {}         # mac -> parsed `info` dict, filled lazily

_STATUS = "Ready"
_STATUS_LEVEL = "idle"
_BUSY = False
_BUSY_PHASE = 0
_PENDING_REMOVE = None

_TIMERS = []
_SCAN_PROC = None   # long-lived `bluetoothctl scan on`, alive while we are

# The bluetoothctl process of whatever action is in flight, plus the flag its
# worker polls. Together they make a pair/connect abortable.
_PROC = None
_CANCEL = threading.Event()

# =============================================================================
# CONFIG & STYLING
# =============================================================================
POPUP_W = _s(940)
POPUP_H = _s(600)

FONT = "JetBrainsMono Nerd Font"
ROW_SIZE = _s(14)
HEAD_SIZE = _s(14)
HINT_SIZE = _s(13)
FOOT_SIZE = _s(14)

ROWS_VISIBLE = 17
MAX_NAME_LEN = 30

DETAIL_PAD = "  "

# Upper bound on a discovery session: a safety net in case the popup's own
# teardown never runs, not a value anyone should notice.
SCAN_SECONDS = 300
# The device list is four instant `bluetoothctl devices` calls, so it can be
# re-read often enough that devices appear as they are discovered.
REFRESH_INTERVAL = 4
SPIN_INTERVAL = 0.12

# Command timeouts. connect/pair hang forever on an absent device, so these
# are the difference between "it failed" and a wedged worker thread.
T_QUICK = 10
T_ACTION = 45


def _load_colors():
    base = _load_wal_colors()
    base["line"] = _mix(base["bg"], base["fg"], 0.22)
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)
    base["highlight_bg"] = base["blue"]   # bluetooth blue, not the wifi green
    base["highlight_fg"] = base["bg"]
    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)
    return base


COLORS = _load_colors()

_ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# `info`'s Icon field -> nerd font glyph.
_ICONS = {
    "audio-headset": "\U000f02cb",
    "audio-headphones": "",
    "audio-card": "",
    "audio-speakers": "",
    "input-mouse": "\U000f037d",
    "input-keyboard": "",
    "input-gaming": "",
    "input-tablet": "",
    "phone": "",
    "computer": "",
    "watch": "\U000f0b39",
    "printer": "",
    "camera-photo": "",
    "camera-video": "",
}
_ICON_DEFAULT = "\U000f00af"


# =============================================================================
# SMALL HELPERS
# =============================================================================
def esc(text):
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fit(text, width):
    text = str(text)
    if len(text) > width:
        text = text[: width - 1] + "…"
    return f"{text:<{width}}"


def strip_ansi(text):
    """bluetoothctl colours its output even when piped."""
    return _ANSI.sub("", text or "")


def run(cmd, timeout=T_QUICK, track=False):
    """Run a command, returning (ok, output). Never raises.

    `track` publishes the process handle so cancel() can kill it. Only the
    slow actions need it; the queries all return in milliseconds.
    """
    global _PROC

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
    except FileNotFoundError:
        return False, f"{cmd[0]} not found"
    except Exception as e:
        logger.warning("BluetoothPopup: %s failed: %s", cmd[0], e)
        return False, str(e)

    if track:
        _PROC = proc

    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode == 0, strip_ansi(out or "").strip()
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.communicate(timeout=5)
        except Exception:
            pass
        return False, "timed out"
    except Exception as e:
        logger.warning("BluetoothPopup: %s failed: %s", cmd[0], e)
        return False, str(e)
    finally:
        if track:
            _PROC = None


def bt(*args, timeout=T_QUICK, track=False):
    return run(["bluetoothctl", *args], timeout, track=track)


def on_ui(session, fn):
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        try:
            fn()
        except Exception as e:
            logger.exception("BluetoothPopup UI callback failed: %s", e)

    _QTILE.call_soon_threadsafe(_guarded)


def in_thread(fn, *args):
    threading.Thread(target=fn, args=args, daemon=True).start()


def add_timer(delay, session, fn):
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        fn()

    _TIMERS.append(_QTILE.call_later(delay, _guarded))


def cancel_timers():
    for timer in _TIMERS:
        try:
            timer.cancel()
        except Exception:
            pass
    _TIMERS.clear()


def set_status(msg, level="idle"):
    global _STATUS, _STATUS_LEVEL
    _STATUS, _STATUS_LEVEL = msg, level


# =============================================================================
# BLUETOOTHCTL QUERIES  (worker threads only)
# =============================================================================
def query_adapter():
    """(powered, name, discovering) for the default controller."""
    ok, out = bt("show")
    if not ok or not out:
        return False, "", False

    powered = discovering = False
    name = ""
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Name:"):
            name = line.split(":", 1)[1].strip()
        elif line.startswith("Powered:"):
            powered = line.split(":", 1)[1].strip() == "yes"
        elif line.startswith("Discovering:"):
            discovering = line.split(":", 1)[1].strip() == "yes"
    return powered, name, discovering


def _mac_set(*args):
    ok, out = bt("devices", *args)
    if not ok:
        return set()
    return {
        parts[1]
        for parts in (line.split() for line in out.splitlines())
        if len(parts) >= 2 and parts[0] == "Device"
    }


def parse_info(text):
    """The fields of `bluetoothctl info` worth showing."""
    info = {}
    for line in text.splitlines():
        line = line.strip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key, value = key.strip(), value.strip()
        if key in ("Name", "Alias", "Icon", "Class", "Modalias"):
            info[key.lower()] = value
        elif key in ("Paired", "Bonded", "Trusted", "Connected", "Blocked"):
            info[key.lower()] = value == "yes"
        elif key in ("Battery Percentage", "RSSI", "TxPower"):
            # "0x5f (95)" -- the decimal in the parens is the useful part.
            m = re.search(r"\((-?\d+)\)", value)
            if m:
                info[key.lower().replace(" ", "_")] = int(m.group(1))
    return info


def query_info(mac):
    ok, out = bt("info", mac)
    if not ok or "not available" in out:
        return {}
    return parse_info(out)


def query_devices(with_info=True):
    """Every known device, connected first, then paired, then the rest."""
    ok, out = bt("devices")
    if not ok:
        return [], out

    # Two filtered queries, not three: `trusted` only appears in the details
    # panel, and info() already carries it for whichever row is selected.
    paired = _mac_set("Paired")
    connected = _mac_set("Connected")

    devices = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2 or parts[0] != "Device":
            continue
        mac = parts[1]
        name = parts[2] if len(parts) > 2 else mac
        devices.append({
            "mac": mac,
            # bluez names an unidentified device after its own MAC with
            # dashes; showing that twice per row is just noise.
            "name": name,
            "anonymous": name.replace("-", ":").upper() == mac.upper(),
            "paired": mac in paired,
            "connected": mac in connected,
            "trusted": bool(_INFO.get(mac, {}).get("trusted")),
            # Whatever a previous info() already told us; the refresh below
            # only *fetches* when asked to.
            "icon": _INFO.get(mac, {}).get("icon", ""),
            "battery": _INFO.get(mac, {}).get("battery_percentage"),
            "rssi": _INFO.get(mac, {}).get("rssi"),
        })

    # `info` costs a process per device, so it is fetched only on the opening
    # pass and for paired devices (icon, battery). The 4-second background
    # refresh reuses the cache above, which keeps a steady-state tick at
    # three short-lived processes no matter how many devices are in range.
    if with_info:
        for dev in devices:
            if dev["paired"] or dev["connected"]:
                info = query_info(dev["mac"])
                if info:
                    _INFO[dev["mac"]] = info
                    dev["icon"] = info.get("icon", dev["icon"])
                    dev["trusted"] = bool(info.get("trusted", dev["trusted"]))
                    if info.get("battery_percentage") is not None:
                        dev["battery"] = info["battery_percentage"]

    devices.sort(key=lambda d: (
        not d["connected"], not d["paired"], d["anonymous"], d["name"].lower()
    ))
    return devices, ""


# =============================================================================
# RENDERING
# =============================================================================
def device_icon(dev):
    return _ICONS.get(dev.get("icon") or "", _ICON_DEFAULT)


def selected_device():
    if 0 <= _INDEX < len(_DEVICES):
        return _DEVICES[_INDEX]
    return None


def render_list():
    if not _POWERED:
        message = "Bluetooth is off  (press t)"
    elif not _DEVICES:
        message = "Scanning…" if _BUSY else "No devices — press r to scan"
    else:
        message = None

    if message is not None:
        lines = []
        for row in range(ROWS_VISIBLE):
            lines.append(
                f'<span foreground="{COLORS["muted"]}">  {esc(message)}</span>'
                if row == ROWS_VISIBLE // 2 else ""
            )
        return "\n".join(lines)

    pad = f'<span foreground="{COLORS["surface"]}"> </span>'
    lines = []

    for row in range(ROWS_VISIBLE):
        idx = _OFFSET + row
        if idx >= len(_DEVICES):
            lines.append("")
            continue

        dev = _DEVICES[idx]
        name = dev["mac"] if dev["anonymous"] else dev["name"]

        if dev["connected"]:
            tag = "connected"
        elif dev["paired"]:
            tag = "paired"
        else:
            tag = ""

        battery = f"{dev['battery']:>3}%" if dev["battery"] is not None else "    "

        body = (
            f" {device_icon(dev)} {esc(fit(name, MAX_NAME_LEN))} "
            f"{fit(tag, 10)} {battery} "
        )

        if idx == _INDEX:
            lines.append(
                f"{pad}"
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">{body}</span>'
            )
        elif dev["connected"]:
            lines.append(
                f'{pad}<span foreground="{COLORS["green"]}" weight="bold">{body}</span>'
            )
        elif dev["paired"]:
            lines.append(f'{pad}<span foreground="{COLORS["fg"]}">{body}</span>')
        else:
            lines.append(f'{pad}<span foreground="{COLORS["muted"]}">{body}</span>')

    return "\n".join(lines)


def render_details():
    dev = selected_device()
    if dev is None:
        return f'{DETAIL_PAD}<span foreground="{COLORS["muted"]}">No device selected</span>'

    info = _INFO.get(dev["mac"], {})

    def field(label, value, colour=None):
        return (
            f'<span foreground="{COLORS["muted"]}">{label:<10}</span>'
            f'<span foreground="{colour or COLORS["fg"]}">{esc(value)}</span>'
        )

    if dev["connected"]:
        state, state_colour = "connected", COLORS["green"]
    elif dev["paired"]:
        state, state_colour = "paired", COLORS["blue"]
    else:
        state, state_colour = "not paired", COLORS["muted"]

    name = dev["mac"] if dev["anonymous"] else dev["name"]
    rows = [
        f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
        f'{esc(fit(name, MAX_NAME_LEN).strip())}</span>',
        "",
        field("address", dev["mac"]),
        field("type", info.get("icon", "unknown")),
        field("state", state, state_colour),
        field("trusted", "yes" if dev["trusted"] else "no"),
    ]

    battery = dev["battery"] if dev["battery"] is not None else info.get("battery_percentage")
    if battery is not None:
        bar_len = 14
        filled = max(1, round(bar_len * battery / 100))
        colour = COLORS["red"] if battery <= 20 else COLORS["green"]
        rows.append(
            f'<span foreground="{COLORS["muted"]}">{"battery":<10}</span>'
            f'<span foreground="{colour}">{"━" * filled}</span>'
            f'<span foreground="{COLORS["line"]}">{"━" * (bar_len - filled)}</span>'
            f'<span foreground="{COLORS["fg"]}"> {battery}%</span>'
        )

    if info.get("rssi") is not None:
        rows.append(field("signal", f"{info['rssi']} dBm"))
    if info.get("class"):
        rows.append(field("class", info["class"]))

    return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])


def render_header():
    left = f"{_ADAPTER or 'controller'}  ·  {len(_DEVICES)} devices"
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["fg"]}">'
        f"\U000f00af  Bluetooth</span>\n"
        f'<span size="small" foreground="{COLORS["muted"]}">{esc(left)}</span>'
    )


def render_header_badge():
    connected = [d for d in _DEVICES if d["connected"]]
    if not _POWERED:
        text, colour, icon = "off", COLORS["red"], "\U000f00b2"
    elif connected:
        name = connected[0]["mac"] if connected[0]["anonymous"] else connected[0]["name"]
        text, colour, icon = name, COLORS["green"], "\U000f00b1"
    elif _DISCOVERING:
        text, colour, icon = "scanning", COLORS["blue"], "\U000f00af"
    else:
        text, colour, icon = "nothing connected", COLORS["muted"], "\U000f00af"

    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{colour}" '
        f'weight="bold"> {icon} {esc(fit(text, 24).strip())} </span>'
    )


def _key(label):
    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{COLORS["fg"]}" '
        f'weight="bold"> {label} </span>'
    )


def render_hints():
    gap = f'<span foreground="{COLORS["line"]}"> </span>'
    pairs = [
        ("jk", "move"),
        ("↵", "connect"),
        ("d", "drop"),
        ("x", "remove"),
        ("t", "power"),
        ("r", "scan"),
        ("/", "find"),
        ("Esc", "close"),
    ]
    return gap.join(
        f'{_key(k)}<span foreground="{COLORS["muted"]}"> {desc}</span>'
        for k, desc in pairs
    )


def render_footer():
    colour = {
        "busy": COLORS["blue"],
        "ok": COLORS["green"],
        "error": COLORS["red"],
    }.get(_STATUS_LEVEL, COLORS["muted"])

    prefix = ""
    if _BUSY:
        track, window = 24, 4
        pos = _BUSY_PHASE % (track + window)
        cells = [
            (COLORS["blue"] if pos - window < i <= pos else COLORS["line"])
            for i in range(track)
        ]
        prefix = "".join(f'<span foreground="{c}">━</span>' for c in cells) + "   "

    suffix = ""
    if _BUSY:
        suffix = f'<span foreground="{COLORS["muted"]}">   ·   c to stop</span>'

    return (
        f'{prefix}<span foreground="{colour}" weight="bold">{esc(_STATUS)}</span>'
        f"{suffix}"
    )


def update_footer():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(footer=render_footer())


def update():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(
        header=render_header(),
        badge=render_header_badge(),
        devices=render_list(),
        details=render_details(),
        footer=render_footer(),
    )


# =============================================================================
# DISCOVERY
# =============================================================================
def start_discovery():
    """Begin discovery and keep it running until stop_discovery().

    Held open as a child process rather than issued as a one-shot: bluez
    drops every unpaired device it knows the moment discovery ends, so a
    finite scan produces a list that empties itself a few seconds later.
    """
    global _SCAN_PROC

    stop_discovery()
    try:
        _SCAN_PROC = subprocess.Popen(
            ["bluetoothctl", "--timeout", str(SCAN_SECONDS), "scan", "on"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception as e:
        logger.warning("BluetoothPopup: could not start discovery: %s", e)
        _SCAN_PROC = None


def stop_discovery():
    """Stop discovery. bluez ends it when the client goes away."""
    global _SCAN_PROC
    proc, _SCAN_PROC = _SCAN_PROC, None
    if proc is None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=2)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


# =============================================================================
# REFRESH
# =============================================================================
def refresh(scan=False, reason=None):
    global _BUSY

    session = _SESSION
    if scan:
        _BUSY = True
        set_status(reason or f"Scanning for {SCAN_SECONDS}s…", "busy")
        spin(session)
        update()

    def worker():
        powered, name, discovering = query_adapter()
        devices, err = query_devices(with_info=scan) if powered else ([], "")

        def apply():
            global _DEVICES, _POWERED, _ADAPTER, _DISCOVERING, _INDEX, _BUSY

            keep = selected_device()
            _POWERED, _ADAPTER, _DISCOVERING = powered, name, discovering
            _DEVICES = devices

            # Hold the cursor on the same device: the list re-sorts as things
            # connect and disconnect.
            if keep is not None:
                _INDEX = next(
                    (i for i, d in enumerate(_DEVICES) if d["mac"] == keep["mac"]),
                    min(_INDEX, max(0, len(_DEVICES) - 1)),
                )
            else:
                _INDEX = min(_INDEX, max(0, len(_DEVICES) - 1))
            ensure_visible()

            if scan:
                _BUSY = False
                if err:
                    set_status(err.splitlines()[0][:70], "error")
                elif not powered:
                    set_status("Bluetooth is off", "error")
                else:
                    set_status(
                        f"{len(devices)} devices  ·  still discovering", "ok"
                    )

            update()

        on_ui(session, apply)

    in_thread(worker)


def spin(session):
    def tick():
        global _BUSY_PHASE
        if not _BUSY:
            return
        _BUSY_PHASE += 1
        update_footer()
        add_timer(SPIN_INTERVAL, session, tick)

    add_timer(SPIN_INTERVAL, session, tick)


def schedule_refresh(session):
    def tick():
        if not _BUSY:
            refresh(scan=False)
        schedule_refresh(session)

    add_timer(REFRESH_INTERVAL, session, tick)


def scan():
    """r: restart discovery (and re-read the list straight away)."""
    if _BUSY:
        return
    if not _POWERED:
        set_status("Bluetooth is off — press t first", "error")
        update()
        return
    start_discovery()
    refresh(scan=True, reason="Discovering…")


# =============================================================================
# ACTIONS
# =============================================================================
def _finish(session, ok, message, level=None, rescan=False):
    def apply():
        global _BUSY
        _BUSY = False
        set_status(message, level or ("ok" if ok else "error"))
        update()
        # with_info via scan=True: pairing/removing is exactly what changes
        # the icon/battery/trusted facts the cheap ticks reuse.
        refresh(scan=True, reason=message)

    on_ui(session, apply)


def _bt_error(output):
    """The useful line out of a bluetoothctl failure."""
    for line in reversed((output or "").splitlines()):
        line = line.strip()
        if line.lower().startswith("failed"):
            return line[:70]
        if line and not line.startswith("Attempting") and "Agent" not in line:
            return line[:70]
    return "failed"


def cancel():
    """c: abort whatever action is in flight.

    Killing bluetoothctl only drops the D-Bus client; bluez carries on with
    the pairing or connection it was asked for. `cancel-pairing` and
    `disconnect` are what actually stop it, and both can block, so they run
    on a worker.
    """
    global _BUSY

    if not _BUSY:
        set_status("Nothing to cancel", "idle")
        update()
        return

    session = _SESSION
    dev = selected_device()
    mac = dev["mac"] if dev else None
    _CANCEL.set()

    proc = _PROC
    if proc is not None:
        try:
            proc.kill()
        except Exception:
            pass

    _BUSY = False
    set_status("Cancelling…", "idle")
    update()

    def worker():
        if mac:
            bt("cancel-pairing", mac, timeout=T_QUICK)
            bt("disconnect", mac, timeout=T_QUICK)

        def done():
            set_status("Cancelled", "idle")
            update()
            refresh(scan=False)

        on_ui(session, done)

    in_thread(worker)


def connect():
    """Enter: pair (if needed), trust, then connect the selected device."""
    global _BUSY, _PENDING_REMOVE
    _PENDING_REMOVE = None

    dev = selected_device()
    if dev is None or _BUSY:
        return

    if dev["connected"]:
        set_status(f"Already connected to {dev['name']}", "ok")
        update()
        return

    session = _SESSION
    mac, name, paired = dev["mac"], dev["name"], dev["paired"]

    _CANCEL.clear()
    _BUSY = True
    set_status(f"{'Connecting to' if paired else 'Pairing with'} {name}…", "busy")
    spin(session)
    update()

    def worker():
        if not paired:
            ok, out = bt("pair", mac, timeout=T_ACTION, track=True)
            if _CANCEL.is_set():
                return
            if not ok and "already" not in out.lower():
                _finish(session, False, _bt_error(out))
                return
            # Trust it so it reconnects on its own next time; a failure here
            # is not worth aborting the connect over.
            bt("trust", mac, timeout=T_QUICK)

        ok, out = bt("connect", mac, timeout=T_ACTION, track=True)
        if _CANCEL.is_set():
            # The kill made bluetoothctl look like a failure; it was us.
            return
        _finish(session, ok, f"Connected to {name}" if ok else _bt_error(out))

    in_thread(worker)


def disconnect():
    """d: drop the selected device (or the connected one)."""
    global _BUSY, _PENDING_REMOVE
    _PENDING_REMOVE = None

    if _BUSY:
        return

    dev = selected_device()
    if dev is None or not dev["connected"]:
        dev = next((d for d in _DEVICES if d["connected"]), None)
    if dev is None:
        set_status("Nothing connected", "idle")
        update()
        return

    session = _SESSION
    mac, name = dev["mac"], dev["name"]

    _CANCEL.clear()
    _BUSY = True
    set_status(f"Disconnecting {name}…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = bt("disconnect", mac, timeout=T_ACTION, track=True)
        _finish(session, ok, f"Disconnected {name}" if ok else _bt_error(out))

    in_thread(worker)


def remove():
    """x: forget the selected device. Two presses, like the wifi popup."""
    global _BUSY, _PENDING_REMOVE

    dev = selected_device()
    if dev is None or _BUSY:
        return

    if not dev["paired"] and not dev["trusted"]:
        _PENDING_REMOVE = None
        set_status(f"{dev['name']} is not paired", "idle")
        update()
        return

    if _PENDING_REMOVE != dev["mac"]:
        _PENDING_REMOVE = dev["mac"]
        set_status(f"Press x again to remove {dev['name']}", "error")
        update()
        return

    _PENDING_REMOVE = None
    session = _SESSION
    mac, name = dev["mac"], dev["name"]

    _BUSY = True
    set_status(f"Removing {name}…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = bt("remove", mac, timeout=T_ACTION, track=True)
        _INFO.pop(mac, None)
        _finish(session, ok, f"Removed {name}" if ok else _bt_error(out))

    in_thread(worker)


def toggle_power():
    """t: power the controller on or off."""
    global _BUSY, _PENDING_REMOVE
    _PENDING_REMOVE = None

    if _BUSY:
        return

    session = _SESSION
    turning_on = not _POWERED

    _BUSY = True
    set_status("Turning Bluetooth on…" if turning_on else "Turning Bluetooth off…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = bt("power", "on" if turning_on else "off", timeout=T_QUICK)
        if ok:
            # Discovery cannot outlive the radio, and restarting it is the
            # only way the list repopulates after a power cycle.
            if turning_on:
                start_discovery()
            else:
                stop_discovery()
        _finish(
            session, ok,
            ("Bluetooth on" if turning_on else "Bluetooth off") if ok
            else _bt_error(out),
            rescan=turning_on,
        )

    in_thread(worker)


def search():
    """/: jump to a device by name via rofi."""
    global _PENDING_REMOVE
    _PENDING_REMOVE = None

    if not _DEVICES:
        return

    session = _SESSION
    labels = [
        f"{d['mac']}  {d['mac'] if d['anonymous'] else d['name']}" for d in _DEVICES
    ]

    def worker():
        try:
            proc = subprocess.run(
                ["rofi", "-dmenu", "-i", "-p", "Device",
                 "-theme-str", "window {width: 40%;}"],
                input="\n".join(labels), stdout=subprocess.PIPE, text=True, timeout=120,
            )
            choice = proc.stdout.strip()
        except Exception as e:
            logger.warning("BluetoothPopup: rofi search failed: %s", e)
            return

        if not choice:
            return
        mac = choice.split()[0]

        def apply():
            global _INDEX
            for i, dev in enumerate(_DEVICES):
                if dev["mac"] == mac:
                    _INDEX = i
                    ensure_visible()
                    update()
                    return

        on_ui(session, apply)

    in_thread(worker)


# =============================================================================
# NAVIGATION
# =============================================================================
def ensure_visible():
    global _OFFSET
    if _INDEX < _OFFSET:
        _OFFSET = _INDEX
    elif _INDEX >= _OFFSET + ROWS_VISIBLE:
        _OFFSET = _INDEX - ROWS_VISIBLE + 1
    _OFFSET = max(0, min(_OFFSET, max(0, len(_DEVICES) - ROWS_VISIBLE)))


def move(step):
    global _INDEX, _PENDING_REMOVE
    if _LAYOUT is None or not _DEVICES:
        return
    _PENDING_REMOVE = None
    _INDEX = max(0, min(len(_DEVICES) - 1, _INDEX + step))
    ensure_visible()
    _fetch_info_for_selection()
    update()


def jump(where):
    global _INDEX, _PENDING_REMOVE
    if _LAYOUT is None or not _DEVICES:
        return
    _PENDING_REMOVE = None
    _INDEX = 0 if where == "top" else len(_DEVICES) - 1
    ensure_visible()
    _fetch_info_for_selection()
    update()


def _fetch_info_for_selection():
    """Fill in the details panel for a row we have not inspected yet.

    One process, off the event loop, and only the first time a given device
    is selected -- holding `j` down does not spawn anything.
    """
    dev = selected_device()
    if dev is None or dev["mac"] in _INFO:
        return

    session = _SESSION
    mac = dev["mac"]

    def worker():
        info = query_info(mac)
        if not info:
            return

        def apply():
            _INFO[mac] = info
            for d in _DEVICES:
                if d["mac"] == mac:
                    d["icon"] = info.get("icon", d["icon"])
                    if info.get("battery_percentage") is not None:
                        d["battery"] = info["battery_percentage"]
            update()

        on_ui(session, apply)

    in_thread(worker)


# =============================================================================
# POPUP CONTROL
# =============================================================================
def show(qtile):
    global _LAYOUT, _QTILE, _SESSION, _INDEX, _OFFSET, _DEVICES
    global _BUSY, _BUSY_PHASE, _PENDING_REMOVE

    _QTILE = qtile
    if _LAYOUT is not None or _CLOSING:
        return

    COLORS.update(_load_colors())

    _SESSION += 1
    session = _SESSION
    _INDEX = _OFFSET = 0
    _DEVICES = []
    _BUSY = False
    _BUSY_PHASE = 0
    _PENDING_REMOVE = None
    set_status("Scanning for devices…", "busy")

    head_y, head_h = 24 / POPUP_H, 54 / POPUP_H
    hint_y, hint_h = 88 / POPUP_H, 30 / POPUP_H
    body_y, body_h = 132 / POPUP_H, 380 / POPUP_H
    foot_y, foot_h = 524 / POPUP_H, 54 / POPUP_H

    controls = [
        PopupText(
            text=render_header(), markup=True, font=FONT, fontsize=HEAD_SIZE,
            pos_x=0.03, pos_y=head_y, width=0.45, height=head_h,
            h_align="left", v_align="middle", name="header",
        ),
        PopupText(
            text=render_header_badge(), markup=True, font=FONT, fontsize=HINT_SIZE,
            pos_x=0.5, pos_y=head_y, width=0.47, height=head_h,
            h_align="right", v_align="middle", name="badge",
        ),
        PopupText(
            text=render_hints(), markup=True, font=FONT, fontsize=HINT_SIZE,
            background=COLORS["surface"], highlight_radius=8,
            pos_x=0.03, pos_y=hint_y, width=0.94, height=hint_h,
            h_align="center", v_align="middle", name="hints",
        ),
        PopupText(
            text=render_list(), markup=True, font=FONT, fontsize=ROW_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.03, pos_y=body_y, width=0.499, height=body_h,
            h_align="left", v_align="middle", name="devices",
        ),
        PopupText(
            text=render_details(), markup=True, font=FONT, fontsize=HINT_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.5452, pos_y=body_y, width=0.4238, height=body_h,
            h_align="left", v_align="top", name="details",
        ),
        PopupText(
            text=render_footer(), markup=True, font=FONT, fontsize=FOOT_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.03, pos_y=foot_y, width=0.94, height=foot_h,
            h_align="center", v_align="middle", name="footer",
        ),
    ]

    _LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"] + "F2",
        border=COLORS["surface_alt"],
        border_width=2,
        close_on_click=False,
        controls=controls,
    )

    _LAYOUT.show(centered=True)
    fade_in_popup(_LAYOUT, duration=0.24, steps=16)

    # Discovery starts with the popup and runs until it closes; without it
    # the list is only whatever bluez still remembers, which minutes after
    # the last scan is nothing at all.
    start_discovery()
    refresh(scan=True, reason="Discovering…")
    schedule_refresh(session)


def close(qtile=None):
    global _LAYOUT, _CLOSING, _SESSION, _BUSY, _PENDING_REMOVE

    if _LAYOUT is None or _CLOSING:
        return

    layout = _LAYOUT
    _CLOSING = True
    _SESSION += 1
    _BUSY = False
    _PENDING_REMOVE = None
    cancel_timers()
    stop_discovery()   # leaving the radio discovering costs power for nothing
    _LAYOUT = None

    def teardown():
        global _CLOSING
        try:
            # kill(), not hide(): hide() leaves the window and its cairo
            # surface allocated while show() builds a new layout every time.
            layout.kill()
        except Exception:
            pass
        _CLOSING = False

    fade_out_popup(layout, teardown)


def toggle(qtile):
    if _CLOSING:
        return
    if _LAYOUT is not None:
        close(qtile)
    else:
        show(qtile)
