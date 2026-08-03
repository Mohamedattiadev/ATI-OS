"""Audio picker popup, backed by pactl (PipeWire via the pulse shim).

The keyboard path this system otherwise doesn't have: pick an output, drag
the already-playing streams across with it, set per-app volume, and switch a
Bluetooth card between A2DP and HSP/HFP without opening pavucontrol.

Traps this file exists to work around, all found against pactl 17.0-98
talking to PipeWire 1.6.8:

* **Indices are serials and they move.** A sink's own `index` changed from 51
  to 249079 during testing, just from a `move-sink-input` -- PipeWire's pulse
  shim hands out monotonically increasing serials rather than the stable
  small integers real PulseAudio uses. Nothing here caches an index across a
  refresh: sinks/sources/cards are addressed by `name`, and the only place an
  index is used (sink-inputs, which have no name) it is re-read from a fresh
  `list sink-inputs` in the same worker pass that consumes it.
* **`monitor_of` is `None` on every source, including monitors.** The
  documented way to recognise a loopback monitor therefore matches nothing,
  and an unfiltered source list shows "Monitor of Built-in Audio" beside the
  real microphone. Monitors are detected by the `.monitor` name suffix and
  cross-checked against the sinks' `monitor_source` field.
* **Sinks carry no card reference.** Neither the JSON nor the text output has
  the `Card:` line PulseAudio emits, so a sink is matched to its card by the
  token both names share (`alsa_card.pci-0000_00_1f.3` ->
  `alsa_output.pci-0000_00_1f.3.analog-stereo`). The same trick is what makes
  it work for bluez, where the token is the MAC.
* **`profiles` is a dict, not a list** -- keyed by profile name, each value
  carrying `description`/`available`/`priority`. The built-in card here
  advertises 23 of them and only 5 are available, so the unavailable ones are
  hidden unless they are the active profile.

Setting a default sink does NOT move what is already playing: PulseAudio
only routes *new* streams to it. Enter therefore issues `set-default-sink`
and then walks every live sink-input with `move-sink-input`, which is the
entire reason this popup exists.
"""

import json
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor

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

# Bumped on every open and close. Worker callbacks and timers carry the value
# they were spawned with and no-op once it no longer matches.
_SESSION = 0

_SINKS = []      # [{name, desc, index, mute, vol, driver, spec, ports, ...}]
_SOURCES = []    # same shape, monitors filtered out
_APPS = []       # playback streams  [{index, app, media, sink, mute, vol, ...}]
_RECORDING = []  # capture streams   [{index, app, media, source, ...}]
_CARDS = []      # [{name, index, active, profiles: [...]}]

_DEFAULT_SINK = None
_DEFAULT_SOURCE = None

# One cursor per view, so switching back to a list puts you where you left it.
# The first four are the tab cycle (pavucontrol's four tabs); ports and
# profiles are opened against whatever device you are pointing at.
_VIEW = "outputs"
_TABS = ("outputs", "inputs", "playback", "recording")
_VIEWS = _TABS + ("ports", "profiles", "cards", "targets")
_INDEX = {v: 0 for v in _VIEWS}
_OFFSET = {v: 0 for v in _VIEWS}

# The card whose profiles the profiles view is showing. Set when `p` is
# pressed, so the view keeps describing that card even if the cursor in the
# outputs list moves underneath it.
_PROFILE_CARD = None

# The device whose ports the ports view is showing, and whether it is a
# capture device (which decides set-sink-port vs set-source-port).
_PORT_DEVICE = None
_PORT_IS_INPUT = False

# The stream the targets view is about to move, and whether it is a capture
# stream. Set by Enter on a stream row -- pavucontrol's per-stream device
# dropdown, which is the only way to put one app on the headset while
# another stays on the speakers.
_TARGET_STREAM = None
_TARGET_IS_INPUT = False

_STATUS = "Ready"
_STATUS_LEVEL = "idle"   # idle | busy | ok | error
_BUSY = False
_BUSY_PHASE = 0

_TIMERS = []

# Optimistic values that have not been confirmed by a read yet:
#   key -> {"vol": int|None, "mute": bool|None, "until": monotonic}
_PENDING = {}
# Coalesced pactl writes: key -> argv (latest wins), plus the flush timer.
_VOL_QUEUE = {}
_VOL_TIMER = None

# The pactl process of whatever long-running action is in flight, plus the
# flag its worker polls. Together they make a card-profile switch abortable.
_PROC = None
_CANCEL = threading.Event()

# =============================================================================
# CONFIG & STYLING
# =============================================================================
POPUP_W = _s(940)
POPUP_H = _s(600)

FONT = "JetBrainsMono Nerd Font"  # monospace: the padded rows only line up
ROW_SIZE = _s(14)                     # in a fixed-width face
HEAD_SIZE = _s(14)
HINT_SIZE = _s(13)
FOOT_SIZE = _s(14)

# qtile builds text layouts with a *pixel* font size ("<family> <n>px"), so
# these are px, not points: a ROW_SIZE line box is 20px tall and 17 rows
# (340px) sit inside the 373px list card with room to breathe.
ROWS_VISIBLE = 17
MAX_NAME_LEN = 28
# The list card is 464px -- 58 monospace cells at ROW_SIZE. A device row is
# pad+mark+icon+name+slider+readout+spacing, so the name column is what has
# to give to make room for the slider. Measured by the fit-check.
ROW_NAME_LEN = 20
STREAM_NAME_LEN = 21

# Left inset for the details card, in literal spaces -- a PopupText draws at
# (0, 0) of its own rect and its background *is* the card, so there is no
# padding property to set. Same reasoning as the wifi popup.
DETAIL_PAD = "  "

# Measured, not guessed (see the fit-check): the details card is 394px and a
# monospace cell is 8px at HINT_SIZE, so 49 cells fit. DETAIL_PAD plus a
# 10-cell label eats 12 of them, leaving 37 -- and a media title is easily
# longer than that. The footer bar is 874px (109 cells); the busy sweep and
# the "c to stop" suffix reserve 43, so a status message gets 64.
DETAIL_VALUE_LEN = 34
STATUS_MAX = 64

# Background refresh cadence while the popup is OPEN. Nothing polls once it
# is closed: close() cancels the timers and bumps the session.
REFRESH_INTERVAL = 3
SPIN_INTERVAL = 0.12

# Holding a volume key must not spawn a pactl process per repeat. Writes are
# coalesced over this window, newest target per device wins: ten fast presses
# become one or two processes instead of ten.
VOLUME_COALESCE = 0.045

# How long an optimistic local value outranks what the server reports. A
# refresh that STARTED before our write landed comes back carrying the old
# volume, and applying it drags the bar backwards -- which is exactly what
# made rapid presses look like they were being ignored.
PENDING_HOLD = 1.2

VOLUME_STEP = 5
# Volume is set absolutely rather than passed to pactl as "+5%": relative
# steps compound with whatever the last refresh has not yet shown.
#
# 150% is what pavucontrol's slider allows. Everything above 100% is software
# amplification and can clip, so the bar and the readout turn red up there
# rather than the popup refusing to go louder -- a hard cap at 100% was the
# one thing this could not do that pavucontrol could.
VOLUME_MAX = 150
VOLUME_UNITY = 100
BALANCE_STEP = 0.1

# pactl queries return in milliseconds; a card-profile switch on a Bluetooth
# device renegotiates the link and can take seconds.
T_QUICK = 5
T_ACTION = 20


def _load_colors():
    """The active theme palette, adjusted for text drawn on cards.

    Same correction as the wifi and bluetooth popups: the shared loader
    derives `muted` against `bg`, but this popup paints on `surface`, which
    is already 7% of the way to `fg`. That costs enough contrast to put
    muted labels under 3:1 on every preset theme-apply ships.
    """
    base = _load_wal_colors()
    base["line"] = _mix(base["bg"], base["fg"], 0.22)
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)

    # Selection block: purple, so audio reads as its own mode next to the
    # wifi picker's green and bluetooth's blue.
    base["highlight_bg"] = base["purple"]
    base["highlight_fg"] = base["bg"]

    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)

    return base


COLORS = _load_colors()

# Nerd font glyphs, written as escapes: a substituted glyph would be a
# different cell width and shift every column after it on that row alone.
ICON_SPEAKER = "\U000f057e"     # 󰕾
ICON_HEADPHONES = ""      #
ICON_HEADSET = "\U000f02cb"     # 󰋋
ICON_HDMI = "\U000f07ce"        # 󰟎
ICON_BLUETOOTH = "\U000f00af"   # 󰂯
ICON_USB = ""             #
ICON_MIC = "\U000f036c"         # 󰍬
ICON_APP = ""             #
ICON_CARD = "\U000f02cb"
ICON_PORT = "\U000f0338"        # 󰌸  -- the jack/port rows


# =============================================================================
# SMALL HELPERS
# =============================================================================
def esc(text):
    """Escape text for Pango markup.

    Device and application names are free text -- a media player reporting
    itself as "Rhythm & Blues" is enough to make the row malformed markup,
    at which point pango drops the entire line rather than the one bad
    character.
    """
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fit(text, width):
    """Truncate with an ellipsis and pad to exactly `width` cells."""
    text = str(text)
    if len(text) > width:
        text = text[: width - 1] + "…"
    return f"{text:<{width}}"


def clip(text, width):
    """Truncate with an ellipsis, WITHOUT padding.

    fit() pads to a fixed cell count, which is what the list rows want so
    their columns line up. The footer and the details values are measured
    against the width of the card they sit on, where trailing spaces are
    width like any other cell -- padding there is what pushes a status
    message over the edge of the bar.
    """
    text = str(text)
    return text[: width - 1] + "…" if len(text) > width else text


def run(cmd, timeout=T_QUICK, track=False):
    """Run a command, returning (ok, output). Never raises.

    `track` publishes the process handle so cancel() can kill it mid-flight.
    Only a card-profile switch needs it -- every query here finishes in tens
    of milliseconds.
    """
    global _PROC

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
    except FileNotFoundError:
        return False, f"{cmd[0]} not found"
    except Exception as e:
        logger.warning("AudioPopup: %s failed: %s", cmd[0], e)
        return False, str(e)

    if track:
        _PROC = proc

    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode == 0, (out or "").strip()
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.communicate(timeout=5)
        except Exception:
            pass
        return False, "timed out"
    except Exception as e:
        logger.warning("AudioPopup: %s failed: %s", cmd[0], e)
        return False, str(e)
    finally:
        if track:
            _PROC = None


def pactl_json(*args):
    """`pactl -f json ...` decoded, or [] on any failure.

    pactl writes its errors to stderr and still exits non-zero, but it has
    also been known to emit a bare `[]` for an empty list -- both come back
    here as an empty list, which every caller treats as "nothing connected".
    """
    ok, out = run(["pactl", "-f", "json", *args], T_QUICK)
    if not ok or not out:
        return []
    try:
        data = json.loads(out)
    except ValueError:
        logger.warning("AudioPopup: pactl %s returned non-JSON", " ".join(args))
        return []
    return data if isinstance(data, list) else []


def on_ui(session, fn):
    """Schedule fn on the qtile event loop unless the session has moved on."""
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        try:
            fn()
        except Exception as e:
            logger.exception("AudioPopup UI callback failed: %s", e)

    _QTILE.call_soon_threadsafe(_guarded)


def in_thread(fn, *args):
    threading.Thread(target=fn, args=args, daemon=True).start()


def add_timer(delay, session, fn):
    """call_later that dies with the session instead of outliving the popup."""
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        fn()

    _TIMERS.append(_QTILE.call_later(delay, _guarded))


def cancel_timers():
    global _VOL_TIMER
    _VOL_TIMER = None
    for timer in _TIMERS:
        try:
            timer.cancel()
        except Exception:
            pass
    _TIMERS.clear()


def set_status(msg, level="idle"):
    global _STATUS, _STATUS_LEVEL
    _STATUS, _STATUS_LEVEL = msg, level


def _percent(volume):
    """Mean channel volume as an int, from pactl's per-channel volume dict.

    Every channel carries its own `value_percent` string ("65%"); a balance
    other than dead centre means they differ, and one number has to stand in
    for the pair.
    """
    if not isinstance(volume, dict) or not volume:
        return 0
    total = count = 0
    for channel in volume.values():
        try:
            total += int(str(channel.get("value_percent", "0%")).rstrip("%"))
            count += 1
        except (ValueError, AttributeError):
            continue
    return round(total / count) if count else 0


# =============================================================================
# OPTIMISTIC WRITES
# =============================================================================
def _pending_key(item):
    """Identity for an optimistic value. Devices by name, streams by index."""
    if item is None:
        return None
    if "name" in item:
        return ("dev", item["name"])
    return ("stream", item.get("index"))


def remember(item, vol=None, mute=None):
    """Record a value we have applied locally but not yet read back."""
    key = _pending_key(item)
    if key is None:
        return
    entry = _PENDING.setdefault(key, {"vol": None, "mute": None, "until": 0})
    if vol is not None:
        entry["vol"] = vol
    if mute is not None:
        entry["mute"] = mute
    entry["until"] = time.monotonic() + PENDING_HOLD


def apply_pending(pools):
    """Overlay unconfirmed local values onto freshly-read objects.

    Without this a refresh in flight when a key is pressed lands afterwards
    and reverts the bar to the pre-keypress volume.
    """
    now = time.monotonic()
    for key in [k for k, v in _PENDING.items() if v["until"] <= now]:
        del _PENDING[key]
    if not _PENDING:
        return
    for pool in pools:
        for item in pool:
            entry = _PENDING.get(_pending_key(item))
            if not entry:
                continue
            if entry["vol"] is not None:
                item["vol"] = entry["vol"]
            if entry["mute"] is not None:
                item["mute"] = entry["mute"]


def queue_write(item, cmd):
    """Send `cmd` after a short quiet period, newest per item wins.

    Key repeat fires far faster than pactl can round-trip. Queuing means a
    held key costs one process per COALESCE window rather than one per repeat,
    and the UI never waits on any of them.
    """
    global _VOL_TIMER

    key = _pending_key(item)
    if key is None or _QTILE is None:
        return
    _VOL_QUEUE[key] = cmd
    if _VOL_TIMER is not None:
        return                      # a flush is already pending

    session = _SESSION

    def flush():
        global _VOL_TIMER
        _VOL_TIMER = None
        if session != _SESSION:
            # Do NOT clear the queue here: it is shared, and by now it may
            # hold writes belonging to a NEWER session whose own flush has
            # not fired yet. Dropping those loses a volume change. show()
            # clears it on open, which is the only place that is safe.
            return
        batch = list(_VOL_QUEUE.values())
        _VOL_QUEUE.clear()
        if not batch:
            return

        def worker():
            for command in batch:
                ok, out = run(command, T_QUICK)
                if not ok:
                    on_ui(session, lambda o=out: (
                        set_status(_pactl_error(o), "error"), update_rows()
                    ))

        in_thread(worker)

    _VOL_TIMER = _QTILE.call_later(VOLUME_COALESCE, flush)
    _TIMERS.append(_VOL_TIMER)


def update_rows():
    """Repaint only what a volume/mute change can alter.

    A full update() rebuilds all seven controls; the header, hints and tabs
    cannot change here. Cheap either way (a repaint is well under a
    millisecond) -- the point is that this path never touches pactl.
    """
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(
        badge=render_header_badge(),
        devices=render_list(),
        details=render_details(),
        footer=render_footer(),
    )


# =============================================================================
# PACTL QUERIES  (worker threads only)
# =============================================================================
def _ports(entry):
    """The selectable ports of a device (Speakers / Headphones / Line Out).

    Kept in xrandr-ish priority order, highest first, because that is the
    order pavucontrol's dropdown uses and it puts the built-in speaker at the
    top where it belongs. Unavailable ports are kept rather than filtered:
    "Headphones — not available" is the answer to "why can't I pick
    headphones", and hiding the row leaves that question unanswered.
    """
    out = []
    for port in entry.get("ports") or []:
        if not isinstance(port, dict):
            continue
        availability = port.get("availability") or ""
        out.append({
            "name": port.get("name") or "",
            "desc": port.get("description") or port.get("name") or "",
            "type": port.get("type") or "",
            "priority": port.get("priority") or 0,
            # pactl says "not available" for a jack with nothing in it, and
            # "availability unknown" for one it cannot sense -- which is the
            # normal state of built-in speakers, so it must not read as bad.
            "available": availability != "not available",
            "availability": availability,
        })
    out.sort(key=lambda p: -p["priority"])
    return out


def _channels(volume):
    """{channel name: percent} for a pactl volume dict."""
    out = {}
    if not isinstance(volume, dict):
        return out
    for name, channel in volume.items():
        if not isinstance(channel, dict):
            continue
        try:
            out[name] = int(str(channel.get("value_percent", "0%")).rstrip("%"))
        except ValueError:
            continue
    return out


def _db(volume):
    """The first channel's dB readout, as pavucontrol shows beside the %."""
    if not isinstance(volume, dict) or not volume:
        return ""
    first = next(iter(volume.values()), None)
    return (first or {}).get("db", "") if isinstance(first, dict) else ""


def _device(entry):
    """The fields of a sink/source entry the list and details panel use."""
    props = entry.get("properties") or {}
    return {
        "name": entry.get("name") or "",
        "desc": entry.get("description") or entry.get("name") or "",
        "index": entry.get("index"),
        "mute": bool(entry.get("mute")),
        "vol": _percent(entry.get("volume")),
        "db": _db(entry.get("volume")),
        "balance": entry.get("balance", 0.0),
        "nchannels": len(entry.get("volume") or {}),
        # Per-channel levels, so the details panel can show what balance
        # actually did. Volume + balance together reach every (L, R) pair --
        # for a target (L, R) the volume is max(L, R) and the balance is
        # whatever pans to the other one -- so this is a readout, not a
        # separate control that would need its own keys.
        "vol_channels": _channels(entry.get("volume")),
        "driver": entry.get("driver") or "",
        "spec": entry.get("sample_specification") or "",
        "channels": entry.get("channel_map") or "",
        "state": entry.get("state") or "",
        "port": entry.get("active_port") or "",
        "ports": _ports(entry),
        "monitor_source": entry.get("monitor_source") or "",
        "bus": props.get("device.bus") or props.get("device.api") or "",
        "product": props.get("device.description") or "",
    }


def query_sinks():
    return [_device(s) for s in pactl_json("list", "sinks")]


def query_sources(sinks):
    """Real capture devices only.

    `monitor_of` is None on every source under the pulse shim, so the
    documented filter matches nothing. Two checks that do work: the
    `.monitor` name suffix, and the set of `monitor_source` names the sinks
    themselves point at.
    """
    monitors = {s["monitor_source"] for s in sinks if s["monitor_source"]}
    out = []
    for entry in pactl_json("list", "sources"):
        dev = _device(entry)
        if dev["name"].endswith(".monitor") or dev["name"] in monitors:
            continue
        out.append(dev)
    return out


def _stream(entry, target_key):
    props = entry.get("properties") or {}
    name = (
        props.get("application.name")
        or props.get("application.process.binary")
        or props.get("node.name")
        or "stream"
    )
    return {
        "index": entry.get("index"),
        "app": name,
        "media": props.get("media.name") or "",
        "target": entry.get(target_key),
        "mute": bool(entry.get("mute")),
        "vol": _percent(entry.get("volume")),
        "db": _db(entry.get("volume")),
        "corked": bool(entry.get("corked")),
    }


def query_apps():
    """Live playback streams -- pavucontrol's "Playback" tab.

    `target` here is whatever index the sink had *in this same pactl pass* --
    it is not stable across refreshes, so it is only ever compared against
    indices read at the same time.
    """
    return [_stream(e, "sink") for e in pactl_json("list", "sink-inputs")]


def query_recording():
    """Live capture streams -- pavucontrol's "Recording" tab.

    Same shape as the playback streams, pointing at a source instead of a
    sink. Without this, "which application is using my microphone right
    now" had no answer anywhere on the system.
    """
    return [_stream(e, "source") for e in pactl_json("list", "source-outputs")]


def query_cards():
    """Cards with their profiles, best profile first.

    `profiles` arrives as a dict keyed by profile name. Unavailable ones are
    dropped -- the built-in card lists 23 profiles and only 5 can be
    selected -- except the active one, which is always shown even if pactl
    has decided it is unavailable.
    """
    cards = []
    for entry in pactl_json("list", "cards"):
        active = entry.get("active_profile") or ""
        raw = entry.get("profiles")
        profiles = []
        if isinstance(raw, dict):
            for key, value in raw.items():
                value = value if isinstance(value, dict) else {}
                available = bool(value.get("available", True))
                if not available and key != active:
                    continue
                profiles.append({
                    "name": key,
                    "desc": value.get("description") or key,
                    "available": available,
                    "priority": value.get("priority") or 0,
                    "sinks": value.get("sinks", 0),
                    "sources": value.get("sources", 0),
                })
        profiles.sort(key=lambda p: -p["priority"])
        props = entry.get("properties") or {}
        cards.append({
            "name": entry.get("name") or "",
            "index": entry.get("index"),
            "active": active,
            "profiles": profiles,
            "product": props.get("device.description") or entry.get("name") or "",
        })
    return cards


def query_defaults():
    ok_sink, sink = run(["pactl", "get-default-sink"], T_QUICK)
    ok_source, source = run(["pactl", "get-default-source"], T_QUICK)
    return (
        sink.strip() if ok_sink else None,
        source.strip() if ok_source else None,
    )


# =============================================================================
# CARD <-> DEVICE MATCHING
# =============================================================================
def _card_token(card_name):
    """The part of a card name that also appears in its devices' names.

    `alsa_card.pci-0000_00_1f.3` -> `pci-0000_00_1f.3`, which is exactly the
    substring `alsa_output.pci-0000_00_1f.3.analog-stereo` carries. For a
    bluez card the token is the MAC, and it works identically. This is a
    heuristic because pactl gives us nothing better: the sink JSON has no
    card field at all under PipeWire.
    """
    _, _, token = (card_name or "").partition(".")
    return token


def card_for(device):
    """The card owning a sink/source, or None when nothing matches."""
    if not device:
        return None
    name = device.get("name") or ""
    for card in _CARDS:
        token = _card_token(card["name"])
        if token and token in name:
            return card
    return None


def profile_note(profile_name):
    """Plain-language warning for the bluez profiles that trade off.

    This is the whole reason profile switching is here: a headset that
    connects as a headset (HSP/HFP) sounds like a telephone, and one that
    connects as A2DP has no working microphone. Neither profile name says
    so, and the descriptions ("Handsfree Head Unit") don't either.
    """
    low = (profile_name or "").lower()
    if "a2dp" in low:
        return "hi-fi, no mic"
    if "headset" in low or "handsfree" in low or "hfp" in low or "hsp" in low:
        return "mic, low quality"
    if low == "off":
        return "device disabled"
    return ""


# =============================================================================
# VIEW / SELECTION
# =============================================================================
def current_items():
    """The rows the active view is showing."""
    if _VIEW == "outputs":
        return _SINKS
    if _VIEW == "inputs":
        return _SOURCES
    if _VIEW == "playback":
        return _APPS
    if _VIEW == "recording":
        return _RECORDING
    if _VIEW == "ports":
        return _PORT_DEVICE["ports"] if _PORT_DEVICE else []
    if _VIEW == "profiles":
        return _PROFILE_CARD["profiles"] if _PROFILE_CARD else []
    if _VIEW == "cards":
        return _CARDS
    if _VIEW == "targets":
        # Where the stream being moved could go.
        return _SOURCES if _TARGET_IS_INPUT else _SINKS
    return []


def is_stream_view():
    return _VIEW in ("playback", "recording")


def _has_volume():
    """Whether the rows in the active view carry a volume at all.

    A whitelist rather than a blacklist: profiles, ports, cards and targets
    list objects with no `vol`/`desc`, and enumerating the views that DO have
    one means adding a view can never reintroduce a KeyError in the volume
    and mute handlers. Blacklisting is precisely how `l` in the cards view
    came to raise.
    """
    return _VIEW in _TABS


def device_list_for(view):
    return _SOURCES if view == "inputs" else _SINKS


def selected():
    items = current_items()
    idx = _INDEX.get(_VIEW, 0)
    if 0 <= idx < len(items):
        return items[idx]
    return None


def _item_key(item):
    """Stable identity for an item, for holding the cursor across refreshes.

    Sinks, sources and profiles have names. Sink-inputs do not -- their only
    identity is an index that PipeWire may renumber -- so they fall back to
    the application name, which survives a renumber and is what the user is
    actually pointing at.
    """
    if item is None:
        return None
    if "name" in item:
        return ("name", item["name"])
    return ("app", item.get("app"), item.get("media"))


def device_icon(device, is_input=False):
    haystack = f"{device.get('name', '')} {device.get('desc', '')}".lower()
    if "bluez" in haystack or "bluetooth" in haystack:
        return ICON_BLUETOOTH
    if "hdmi" in haystack or "displayport" in haystack:
        return ICON_HDMI
    if "headset" in haystack:
        return ICON_HEADSET
    if "headphone" in haystack:
        return ICON_HEADPHONES
    if "usb" in haystack:
        return ICON_USB
    return ICON_MIC if is_input else ICON_SPEAKER


# =============================================================================
# RENDERING
# =============================================================================
def _volume_cell(vol, mute):
    """A right-aligned 4-cell volume readout, or "mute" when muted."""
    return " mute" if mute else f"{vol:>3}%"


# The inline slider is drawn with two different CHARACTERS rather than two
# colours: the selected row is one uniform highlight block, and a bar that
# relied on colour would vanish exactly when you are adjusting it.
SLIDER_CELLS = 12
SLIDER_FULL = "━"
SLIDER_EMPTY = "─"
SLIDER_KNOB = "╋"
SLIDER_OVER = "═"        # the boosted stretch past 100%


def _slider(vol, mute, cells=SLIDER_CELLS):
    """A pavucontrol-style level bar, sized so 100% lands at `cells`.

    The scale runs to VOLUME_MAX, with unity marked, so a boosted device
    reads as "past the line" instead of just "full". Muted draws an empty
    track: the number still says what it will return to.
    """
    unity_at = round(cells * VOLUME_UNITY / VOLUME_MAX)
    if mute:
        return SLIDER_EMPTY * cells
    filled = max(0, min(cells, round(cells * vol / VOLUME_MAX)))
    out = []
    for i in range(cells):
        if i == filled - 1:
            out.append(SLIDER_KNOB)
        elif i < filled:
            out.append(SLIDER_OVER if i >= unity_at else SLIDER_FULL)
        elif i == unity_at:
            out.append("┊")          # the 100% mark, visible when below it
        else:
            out.append(SLIDER_EMPTY)
    return "".join(out)


def _vol_colour(vol, mute):
    if mute:
        return COLORS["red"]
    return COLORS["red"] if vol > VOLUME_UNITY else COLORS["green"]


def _empty_list(message):
    lines = []
    for row in range(ROWS_VISIBLE):
        lines.append(
            f'<span foreground="{COLORS["muted"]}">  {esc(message)}</span>'
            if row == ROWS_VISIBLE // 2 else ""
        )
    return "\n".join(lines)


def render_list():
    """The list card.

    Always emits exactly ROWS_VISIBLE lines so the card's v_align="middle"
    keeps rows pinned in the same place whether one device is present or
    twenty, and every row is the same cell count so the selected row's block
    lands exactly where the other rows' text does.
    """
    items = current_items()

    if not items:
        return _empty_list({
            "outputs": "No outputs — press r to refresh",
            "inputs": "No microphones found",
            "playback": "Nothing is playing",
            "recording": "Nothing is recording",
            "ports": "This device has no selectable ports",
            "profiles": "No card for this device",
            "cards": "No sound cards found",
            "targets": "Nowhere to move this stream",
        }.get(_VIEW, "Nothing here"))

    pad = f'<span foreground="{COLORS["surface"]}"> </span>'
    index, offset = _INDEX.get(_VIEW, 0), _OFFSET.get(_VIEW, 0)
    lines = []

    for row in range(ROWS_VISIBLE):
        idx = offset + row
        if idx >= len(items):
            lines.append("")
            continue

        item = items[idx]

        if _VIEW == "cards":
            active = next(
                (p for p in item["profiles"] if p["name"] == item["active"]), None
            )
            body = (
                f" {ICON_CARD} {esc(fit(item['product'], 20))} "
                f"{esc(fit(active['desc'] if active else item['active'], 22))} "
                f"{len(item['profiles']):>2} "
            )
            highlight, strong = idx == index, False
        elif _VIEW == "targets":
            default = _DEFAULT_SOURCE if _TARGET_IS_INPUT else _DEFAULT_SINK
            here = _TARGET_STREAM and item["index"] == _TARGET_STREAM["target"]
            body = (
                f" {device_icon(item, _TARGET_IS_INPUT)} "
                f"{esc(fit(item['desc'], 26))} "
                f"{fit('current' if here else ('default' if item['name'] == default else ''), 8)} "
                f"{_volume_cell(item['vol'], item['mute'])} "
            )
            highlight, strong = idx == index, bool(here)
        elif _VIEW == "profiles":
            active = _PROFILE_CARD and item["name"] == _PROFILE_CARD["active"]
            icon = ICON_CARD
            body = (
                f" {icon} {esc(fit(item['desc'], MAX_NAME_LEN))} "
                f"{esc(fit(profile_note(item['name']), 16))} "
                f"{'active' if active else '      '} "
            )
            highlight, strong = idx == index, bool(active)
        elif _VIEW == "ports":
            active = _PORT_DEVICE and item["name"] == _PORT_DEVICE["port"]
            body = (
                f" {ICON_PORT} {esc(fit(item['desc'], 18))} "
                f"{esc(fit(item['type'].lower(), 10))} "
                f"{fit('' if item['available'] else 'unplugged', 11)} "
                f"{'active' if active else '      '} "
            )
            highlight, strong = idx == index, bool(active)
        elif is_stream_view():
            icon = ICON_APP if _VIEW == "playback" else ICON_MIC
            label = item["media"] or item["app"]
            body = (
                f" {icon} {esc(fit(label, STREAM_NAME_LEN))} "
                f"{_slider(item['vol'], item['mute'])} "
                f"{_volume_cell(item['vol'], item['mute'])} "
            )
            highlight, strong = idx == index, not item["corked"]
        else:
            is_input = _VIEW == "inputs"
            default = _DEFAULT_SOURCE if is_input else _DEFAULT_SINK
            active = item["name"] == default
            # The default marker is a glyph rather than the word "default":
            # the slider is worth more of the row than seven cells of text.
            mark = "●" if active else " "
            body = (
                f" {mark}{device_icon(item, is_input)} "
                f"{esc(fit(item['desc'], ROW_NAME_LEN))} "
                f"{_slider(item['vol'], item['mute'])} "
                f"{_volume_cell(item['vol'], item['mute'])} "
            )
            highlight, strong = idx == index, bool(active)

        if highlight:
            # One uniform block: on the accent background a differently
            # coloured cell reads as a rendering glitch.
            lines.append(
                f"{pad}"
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">{body}</span>'
            )
        elif strong:
            lines.append(
                f'{pad}<span foreground="{COLORS["green"]}" weight="bold">{body}</span>'
            )
        else:
            lines.append(f'{pad}<span foreground="{COLORS["fg"]}">{body}</span>')

    return "\n".join(lines)


def _bar(value, length=16, colour=None):
    filled = max(0, min(length, round(length * value / 100)))
    return (
        f'<span foreground="{colour or COLORS["green"]}">{"━" * filled}</span>'
        f'<span foreground="{COLORS["line"]}">{"━" * (length - filled)}</span>'
    )


def _balance_row(balance):
    """A centre-anchored L/R bar, the way pavucontrol draws balance.

    Drawn from the middle out rather than as a 0..100 fill: balance is a
    signed value around a centre, and a left-filling bar would make dead
    centre look like "half way to the right".
    """
    half = 7
    try:
        balance = max(-1.0, min(1.0, float(balance)))
    except (TypeError, ValueError):
        balance = 0.0
    offset = round(balance * half)
    cells = []
    for i in range(-half, half + 1):
        if i == offset:
            cells.append(f'<span foreground="{COLORS["fg"]}">┃</span>')
        elif i == 0:
            cells.append(f'<span foreground="{COLORS["muted"]}">┼</span>')
        else:
            cells.append(f'<span foreground="{COLORS["line"]}">━</span>')
    if abs(balance) < 0.005:
        label = "centre"
    else:
        label = f"{abs(balance) * 100:.0f}% {'R' if balance > 0 else 'L'}"
    return (
        f'<span foreground="{COLORS["muted"]}">{"balance":<10}</span>'
        f'{"".join(cells)}'
        f'<span foreground="{COLORS["fg"]}"> {label}</span>'
    )


def render_details():
    """Right-hand panel describing the selected row.

    Every line is indented by DETAIL_PAD and the block starts one blank line
    down: a PopupText draws at (0, 0) of its rect and its background *is* the
    card, so the inset has to come from the markup.
    """
    item = selected()
    if item is None:
        return f'{DETAIL_PAD}<span foreground="{COLORS["muted"]}">Nothing selected</span>'

    def field(label, value, colour=None):
        # Values are clipped here rather than at every call site: a media
        # title or a bluez profile name is free text and long enough to run
        # off the card, and this is the one place all of them pass through.
        return (
            f'<span foreground="{COLORS["muted"]}">{label:<10}</span>'
            f'<span foreground="{colour or COLORS["fg"]}">'
            f'{esc(clip(value, DETAIL_VALUE_LEN))}</span>'
        )

    if _VIEW == "profiles":
        active = _PROFILE_CARD and item["name"] == _PROFILE_CARD["active"]
        note = profile_note(item["name"])
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["desc"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("profile", item["name"]),
            field("state", "active" if active else "available",
                  COLORS["green"] if active else COLORS["muted"]),
            field("outputs", str(item["sinks"])),
            field("inputs", str(item["sources"])),
        ]
        if note:
            rows.append(field("trade-off", note, COLORS["blue"]))
        if _PROFILE_CARD:
            rows.append("")
            rows.append(field("card", fit(_PROFILE_CARD["name"], 24).strip()))
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    if _VIEW == "cards":
        active = next(
            (p for p in item["profiles"] if p["name"] == item["active"]), None
        )
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["product"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("card", item["name"]),
            field("profile", active["desc"] if active else item["active"],
                  COLORS["green"]),
        ]
        note = profile_note(item["active"])
        if note:
            rows.append(field("", note, COLORS["blue"]))
        rows.append(field("choices", f"{len(item['profiles'])} selectable"))
        rows.append("")
        rows.append(f'<span foreground="{COLORS["muted"]}">'
                    f'Enter opens this card’s profiles</span>')
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    if _VIEW == "targets":
        here = _TARGET_STREAM and item["index"] == _TARGET_STREAM["target"]
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["desc"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("moving", _TARGET_STREAM["app"] if _TARGET_STREAM else "—",
                  COLORS["purple"]),
            field("state", "already here" if here else "press Enter to move",
                  COLORS["green"] if here else COLORS["fg"]),
            "",
            field("volume", f"{item['vol']}%"),
            field("driver", item["driver"] or "—"),
            field("format", item["spec"] or "—"),
        ]
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    if _VIEW == "ports":
        active = _PORT_DEVICE and item["name"] == _PORT_DEVICE["port"]
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["desc"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("port", item["name"]),
            field("type", item["type"].lower() or "—"),
            field("state", "active" if active else "available",
                  COLORS["green"] if active else COLORS["muted"]),
            field("jack", item["availability"] or "unknown",
                  COLORS["fg"] if item["available"] else COLORS["red"]),
        ]
        if _PORT_DEVICE:
            rows.append("")
            rows.append(field("device", _PORT_DEVICE["desc"]))
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    if is_stream_view():
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["app"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("playing" if _VIEW == "playback" else "capturing",
                  item["media"] or "—"),
            field("state", "paused" if item["corked"] else
                  ("playing" if _VIEW == "playback" else "recording"),
                  COLORS["muted"] if item["corked"] else COLORS["green"]),
            "",
            f'<span foreground="{COLORS["muted"]}">{"volume":<10}</span>'
            f'{_bar(item["vol"], 16, _vol_colour(item["vol"], item["mute"]))}'
            f'<span foreground="{_vol_colour(item["vol"], item["mute"])}">'
            f' {item["vol"]}%</span>',
            field("gain", item["db"] or "—"),
            field("muted", "yes" if item["mute"] else "no",
                  COLORS["red"] if item["mute"] else COLORS["fg"]),
        ]
        # The stream's target index is only meaningful against the device
        # list read in the same pass, so it is resolved to a name here
        # rather than shown raw.
        pool = _SINKS if _VIEW == "playback" else _SOURCES
        target = next((d for d in pool if d["index"] == item["target"]), None)
        rows.append("")
        rows.append(field("output" if _VIEW == "playback" else "input",
                          target["desc"] if target else "—"))
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    is_input = _VIEW == "inputs"
    default = _DEFAULT_SOURCE if is_input else _DEFAULT_SINK
    active = item["name"] == default
    card = card_for(item)

    colour = _vol_colour(item["vol"], item["mute"])
    rows = [
        f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
        f'{esc(fit(item["desc"], MAX_NAME_LEN).strip())}</span>',
        "",
        f'<span foreground="{COLORS["muted"]}">{"volume":<10}</span>'
        f'{_bar(item["vol"], 16, colour)}'
        f'<span foreground="{colour}"> {item["vol"]}%</span>',
        field("gain", item["db"] or "—"),
        field("muted", "yes" if item["mute"] else "no",
              COLORS["red"] if item["mute"] else COLORS["fg"]),
        field("state", "default" if active else (item["state"] or "—").lower(),
              COLORS["green"] if active else COLORS["muted"]),
    ]

    # Balance only means anything on a stereo device, and showing "0.00" for
    # a mono microphone is noise.
    if item.get("nchannels", 0) >= 2:
        rows.append(_balance_row(item.get("balance", 0.0)))
        # The resulting per-channel levels. pavucontrol shows these as two
        # unlockable sliders; here they are a readout, because volume and
        # balance together already reach every (L, R) pair.
        chans = item.get("vol_channels") or {}
        if len(chans) == 2:
            (ln, lv), (rn, rv) = list(chans.items())[:2]
            rows.append(
                f'<span foreground="{COLORS["muted"]}">{"channels":<10}</span>'
                f'<span foreground="{COLORS["fg"]}">{lv:>3}%</span>'
                f'<span foreground="{COLORS["muted"]}"> {esc(ln[:5])}   </span>'
                f'<span foreground="{COLORS["fg"]}">{rv:>3}%</span>'
                f'<span foreground="{COLORS["muted"]}"> {esc(rn[:5])}</span>'
            )

    rows += [
        "",
        field("driver", item["driver"] or "—"),
        field("format", item["spec"] or "—"),
        field("channels", item["channels"] or "—"),
    ]

    # The active port, plus how many others could be picked -- the hint that
    # `P` has somewhere to go.
    ports = item.get("ports") or []
    active_port = next((p for p in ports if p["name"] == item["port"]), None)
    if ports:
        rows.append(field(
            "port",
            f"{active_port['desc'] if active_port else item['port']}"
            f"{f'  (+{len(ports) - 1})' if len(ports) > 1 else ''}",
        ))
    elif item["port"]:
        rows.append(field("port", item["port"]))

    if card:
        rows.append("")
        profile = next(
            (p for p in card["profiles"] if p["name"] == card["active"]), None
        )
        rows.append(field("profile", profile["desc"] if profile else card["active"]))
        note = profile_note(card["active"])
        if note:
            rows.append(field("", note, COLORS["blue"]))

    return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])


def render_header():
    counts = {
        "outputs": len(_SINKS),
        "inputs": len(_SOURCES),
        "playback": len(_APPS),
        "recording": len(_RECORDING),
        "ports": len(_PORT_DEVICE["ports"]) if _PORT_DEVICE else 0,
        "profiles": len(_PROFILE_CARD["profiles"]) if _PROFILE_CARD else 0,
        "cards": len(_CARDS),
        "targets": len(_SOURCES if _TARGET_IS_INPUT else _SINKS),
    }
    label = {
        "outputs": "outputs",
        "inputs": "microphones",
        "playback": "playing",
        "recording": "recording",
        "ports": "ports",
        "profiles": "profiles",
        "cards": "cards",
        "targets": "destinations",
    }[_VIEW]
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["fg"]}">'
        f"{ICON_SPEAKER}  Audio</span>\n"
        f'<span size="small" foreground="{COLORS["muted"]}">'
        f'{esc(f"{counts[_VIEW]} {label}")}</span>'
    )


def render_header_badge():
    """The current default output, which is what the popup is mostly about."""
    device = next((s for s in _SINKS if s["name"] == _DEFAULT_SINK), None)
    if device is None:
        text, colour, icon = "no output", COLORS["red"], ICON_SPEAKER
    elif device["mute"]:
        text, colour, icon = f"{device['desc']} muted", COLORS["red"], ICON_SPEAKER
    else:
        text = f"{device['desc']}  {device['vol']}%"
        colour, icon = COLORS["green"], device_icon(device)

    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{colour}" '
        f'weight="bold"> {icon} {esc(fit(text, 30).strip())} </span>'
    )


def _key(label):
    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{COLORS["fg"]}" '
        f'weight="bold"> {label} </span>'
    )


def render_hints():
    """The hint bar.

    One space between chips. The bar is 874px wide and nothing clips a
    control -- an overflowing bar spills over the cards below rather than
    being cut off -- so this list is measured, not guessed. Drop a pair
    before adding one.
    """
    gap = f'<span foreground="{COLORS["line"]}"> </span>'
    pairs = [
        ("jk", "move"),
        ("↵", "use"),
        ("hl", "vol"),
        ("m", "mute"),
        ("Tab", "view"),
        ("P", "port"),
        ("p", "profile"),
        ("b", "balance"),
        ("Esc", "close"),
    ]
    return gap.join(
        f'{_key(k)}<span foreground="{COLORS["muted"]}"> {desc}</span>'
        for k, desc in pairs
    )


def render_tabs():
    """The four tabs, plus whichever sub-view is open.

    Ports and profiles are not in the Tab cycle -- they belong to a device
    rather than sitting beside the device lists -- so they only appear here
    once something has opened them.
    """
    labels = [
        ("outputs", "Outputs"),
        ("inputs", "Mics"),
        ("playback", "Playback"),
        ("recording", "Recording"),
    ]
    if _PORT_DEVICE is not None or _VIEW == "ports":
        labels.append(("ports", "Ports"))
    if _PROFILE_CARD is not None or _VIEW == "profiles":
        labels.append(("profiles", "Profiles"))
    if _VIEW == "cards":
        labels.append(("cards", "Cards"))
    if _VIEW == "targets":
        labels.append(("targets", "Move to…"))

    out = []
    for view, label in labels:
        if view == _VIEW:
            out.append(
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold"> {label} </span>'
            )
        else:
            out.append(f'<span foreground="{COLORS["muted"]}"> {label} </span>')
    return f'<span foreground="{COLORS["line"]}"> </span>'.join(out)


def render_footer():
    colour = {
        "busy": COLORS["blue"],
        "ok": COLORS["green"],
        "error": COLORS["red"],
    }.get(_STATUS_LEVEL, COLORS["muted"])

    prefix = ""
    suffix = ""
    if _BUSY:
        # Indeterminate sweep: pactl reports no progress, and a percentage
        # animated on a timer would be a fiction.
        track, window = 24, 4
        pos = _BUSY_PHASE % (track + window)
        cells = [
            (COLORS["purple"] if pos - window < i <= pos else COLORS["line"])
            for i in range(track)
        ]
        prefix = "".join(f'<span foreground="{c}">━</span>' for c in cells) + "   "
        # The only place this can be advertised without a permanent chip.
        suffix = f'<span foreground="{COLORS["muted"]}">   ·   c to stop</span>'

    return (
        f'{prefix}<span foreground="{colour}" weight="bold">'
        f'{esc(clip(_STATUS, STATUS_MAX))}</span>'
        f"{suffix}"
    )


def update_footer():
    """Redraw just the status bar.

    The busy animation ticks eight times a second; a full update() would
    rebuild and re-layout all seven controls (17 rows of markup included)
    every frame to animate twenty-four characters.
    """
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(footer=render_footer())


def update():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(
        header=render_header(),
        badge=render_header_badge(),
        tabs=render_tabs(),
        devices=render_list(),
        details=render_details(),
        footer=render_footer(),
    )


# =============================================================================
# REFRESH
# =============================================================================
def refresh(loud=False, reason=None, full=None):
    """Re-read every list in one worker pass.

    All four queries go together because they are cross-referenced: sources
    are filtered against the sinks' monitor names, apps resolve their sink
    against the sink list, and the details panel matches a device to a card.
    Reading them in separate passes would let a sink appear in one list and
    not the other.
    """
    global _BUSY

    session = _SESSION
    if full is None:
        full = loud
    if loud:
        _BUSY = True
        set_status(reason or "Refreshing…", "busy")
        spin(session)
        update()

    def worker():
        # Six independent pactl processes. Run serially they cost ~180ms;
        # fanned out they cost about as much as the slowest one. They are all
        # read-only, so ordering does not matter -- except that sources are
        # filtered against the sinks' monitor names, which is done after the
        # fan-in.
        want_cards = full or not _CARDS
        with ThreadPoolExecutor(max_workers=5) as pool:
            f_sinks = pool.submit(query_sinks)
            f_apps = pool.submit(query_apps)
            f_rec = pool.submit(query_recording)
            f_defaults = pool.submit(query_defaults)
            # Cards carry 23 profiles to parse and change only when hardware
            # appears or a profile is switched, so the cheap tick reuses them.
            f_cards = pool.submit(query_cards) if want_cards else None

            sinks = f_sinks.result()
            apps = f_apps.result()
            recording = f_rec.result()
            default_sink, default_source = f_defaults.result()
            cards = f_cards.result() if f_cards else _CARDS
        sources = query_sources(sinks)

        def apply():
            global _SINKS, _SOURCES, _APPS, _RECORDING, _CARDS, _BUSY
            global _DEFAULT_SINK, _DEFAULT_SOURCE, _PROFILE_CARD, _PORT_DEVICE
            global _TARGET_STREAM

            keep = _item_key(selected())

            _SINKS, _SOURCES, _CARDS = sinks, sources, cards
            _APPS, _RECORDING = apps, recording
            _DEFAULT_SINK, _DEFAULT_SOURCE = default_sink, default_source

            # A read that started before the last keypress landed carries the
            # pre-keypress volume; without this overlay it would rewind the
            # bar under the user's fingers.
            apply_pending((_SINKS, _SOURCES, _APPS, _RECORDING))

            # Re-bind the profiles view to the refreshed card object, or drop
            # out of it if that card is gone (a Bluetooth device that just
            # disconnected takes its card with it).
            if _PROFILE_CARD is not None:
                _PROFILE_CARD = next(
                    (c for c in _CARDS if c["name"] == _PROFILE_CARD["name"]), None
                )
                if _PROFILE_CARD is None and _VIEW == "profiles":
                    set_view("outputs")

            # Same for the ports view: it holds a device dict that the
            # refresh has just replaced, so without this the active-port
            # marker would keep pointing at the pre-refresh value.
            if _TARGET_STREAM is not None:
                pool = _RECORDING if _TARGET_IS_INPUT else _APPS
                _TARGET_STREAM = next(
                    (t for t in pool
                     if _item_key(t) == _item_key(_TARGET_STREAM)), None
                )
                if _TARGET_STREAM is None and _VIEW == "targets":
                    # The app stopped playing while its picker was open.
                    set_view("recording" if _TARGET_IS_INPUT else "playback")

            if _PORT_DEVICE is not None:
                pool = _SOURCES if _PORT_IS_INPUT else _SINKS
                _PORT_DEVICE = next(
                    (d for d in pool if d["name"] == _PORT_DEVICE["name"]), None
                )
                if _PORT_DEVICE is None and _VIEW == "ports":
                    set_view("outputs")

            # Hold the cursor on the same row: streams come and go, and the
            # device list re-orders when a card profile changes.
            items = current_items()
            if keep is not None:
                match = next(
                    (i for i, it in enumerate(items) if _item_key(it) == keep), None
                )
                if match is not None:
                    _INDEX[_VIEW] = match
            clamp_index()
            ensure_visible()

            if loud:
                _BUSY = False
                set_status(f"{len(sinks)} outputs · {len(apps)} streams", "ok")

            update()

        on_ui(session, apply)

    in_thread(worker)


def spin(session):
    """Advance the busy bar until whatever is running finishes."""
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
            refresh(loud=False)
        schedule_refresh(session)

    add_timer(REFRESH_INTERVAL, session, tick)


# =============================================================================
# ACTIONS
# =============================================================================
def _finish(session, ok, message, level=None):
    """Land a worker's result on the UI and re-read the real state."""
    def apply():
        global _BUSY
        _BUSY = False
        set_status(message, level or ("ok" if ok else "error"))
        update()
        # Re-read so the rows, the badge and the details panel all agree with
        # what PipeWire actually did rather than what we asked for. full=True:
        # switching a profile or a port is exactly what changes the card data
        # the cheap ticks otherwise reuse.
        refresh(loud=False, full=True)

    on_ui(session, apply)


def _pactl_error(output):
    """The useful line out of a pactl failure, trimmed to fit the footer."""
    for line in (output or "").splitlines():
        line = line.strip()
        if line:
            return line[:70]
    return "failed"


def activate():
    """Enter: use the selected row.

    For an output this is the headline feature: PulseAudio's default sink
    only affects streams that start *afterwards*, so setting it without
    moving the live sink-inputs leaves the music playing out of the device
    you just switched away from.
    """
    global _BUSY

    item = selected()
    if item is None or _BUSY:
        return

    session = _SESSION

    if _VIEW == "profiles":
        card = _PROFILE_CARD
        if card is None:
            return
        name, desc = item["name"], item["desc"]
        _CANCEL.clear()
        _BUSY = True
        set_status(f"Switching to {desc}…", "busy")
        spin(session)
        update()

        def worker():
            # Slow and tracked: a bluez profile switch renegotiates the link.
            ok, out = run(
                ["pactl", "set-card-profile", card["name"], name],
                T_ACTION, track=True,
            )
            if _CANCEL.is_set():
                return
            _finish(session, ok, f"Profile: {desc}" if ok else _pactl_error(out))

        in_thread(worker)
        return

    if _VIEW == "ports":
        device = _PORT_DEVICE
        if device is None:
            return
        if not item["available"]:
            # pactl accepts the switch and silently routes to nothing, which
            # looks exactly like broken audio.
            set_status(f"{item['desc']} has nothing plugged in", "error")
            update()
            return
        setter = "set-source-port" if _PORT_IS_INPUT else "set-sink-port"
        name, desc = device["name"], item["desc"]
        _BUSY = True
        set_status(f"Switching to {desc}…", "busy")
        spin(session)
        update()

        def worker():
            ok, out = run(["pactl", setter, name, item["name"]], T_QUICK)
            _finish(session, ok, f"Port: {desc}" if ok else _pactl_error(out))

        in_thread(worker)
        return

    if _VIEW == "cards":
        # Enter on a card opens its profiles, which is the only thing there
        # is to do with a card.
        open_profiles_for(item)
        return

    if _VIEW == "targets":
        # Enter here commits the move that the stream view set up.
        stream = _TARGET_STREAM
        if stream is None:
            return
        mover = "move-source-output" if _TARGET_IS_INPUT else "move-sink-input"
        index, label, dest = stream["index"], stream["app"], item["name"]
        _BUSY = True
        set_status(f"Moving {label} to {item['desc']}…", "busy")
        spin(session)
        update()

        def worker():
            ok, out = run(["pactl", mover, str(index), dest], T_QUICK)

            def done():
                set_view("recording" if _TARGET_IS_INPUT else "playback")
            on_ui(session, done)
            _finish(session, ok,
                    f"{label} → {item['desc']}" if ok else _pactl_error(out))

        in_thread(worker)
        return

    if is_stream_view():
        # Open the device picker rather than assuming the default sink.
        # Sending everything to the default is the common case but not the
        # interesting one -- putting the browser on the headset while the
        # video player stays on the speakers needs a choice.
        show_targets()
        return

    is_input = _VIEW == "inputs"
    name, desc = item["name"], item["desc"]
    _BUSY = True
    set_status(f"Switching to {desc}…", "busy")
    spin(session)
    update()

    def worker():
        if is_input:
            ok, out = run(["pactl", "set-default-source", name], T_QUICK)
            _finish(session, ok, f"Mic: {desc}" if ok else _pactl_error(out))
            return

        ok, out = run(["pactl", "set-default-sink", name], T_QUICK)
        if not ok:
            _finish(session, False, _pactl_error(out))
            return

        # Drag the running streams across. The sink-input list is re-read
        # here rather than reused from the last refresh: indices are
        # PipeWire serials and a stream that started (or was renumbered)
        # since then would be moved by the wrong number, or missed.
        moved = failed = 0
        for app in query_apps():
            good, _ = run(
                ["pactl", "move-sink-input", str(app["index"]), name], T_QUICK
            )
            if good:
                moved += 1
            else:
                # A stream that ended between the list and the move is the
                # common case here, and it is not worth reporting as an error.
                failed += 1

        if moved:
            message = f"Output: {desc}  ·  moved {moved} stream{'s' * (moved != 1)}"
        elif failed:
            message = f"Output: {desc}  ·  {failed} stream(s) would not move"
        else:
            message = f"Output: {desc}"
        _finish(session, True, message)

    in_thread(worker)


def change_volume(step):
    """h/l: adjust the selected row's volume.

    Absolute, not pactl's relative "+5%": relative steps compound with
    whatever the last refresh has not yet shown, and pactl will amplify past
    100% without complaint.
    """
    global _BUSY

    item = selected()
    if item is None or _BUSY or not _has_volume():
        return

    session = _SESSION
    target = max(0, min(VOLUME_MAX, item["vol"] + step))

    if _VIEW == "playback":
        cmd = ["pactl", "set-sink-input-volume", str(item["index"]), f"{target}%"]
        label = item["app"]
    elif _VIEW == "recording":
        cmd = ["pactl", "set-source-output-volume", str(item["index"]), f"{target}%"]
        label = item["app"]
    else:
        setter = "set-source-volume" if _VIEW == "inputs" else "set-sink-volume"
        cmd = ["pactl", setter, item["name"], f"{target}%"]
        label = item["desc"]

    # Optimistic and immediate. The old version repainted, then ran pactl,
    # then triggered a FULL refresh -- 180ms of subprocesses per keypress,
    # whose stale result then overwrote the value you had just set. Holding
    # the key made the bar move once and stall. Now: set it, draw it, and let
    # the coalescer write it out behind you.
    item["vol"] = target
    remember(item, vol=target)
    set_status(f"{label}  {target}%", "ok")
    update_rows()
    queue_write(item, cmd)


def toggle_mute():
    """m: mute or unmute the selected row."""
    item = selected()
    if item is None or _BUSY or not _has_volume():
        return

    session = _SESSION

    if _VIEW == "playback":
        cmd = ["pactl", "set-sink-input-mute", str(item["index"]), "toggle"]
        label = item["app"]
    elif _VIEW == "recording":
        cmd = ["pactl", "set-source-output-mute", str(item["index"]), "toggle"]
        label = item["app"]
    else:
        setter = "set-source-mute" if _VIEW == "inputs" else "set-sink-mute"
        cmd = ["pactl", setter, item["name"], "toggle"]
        label = item["desc"]

    item["mute"] = not item["mute"]
    remember(item, mute=item["mute"])
    set_status(f"{label}  {'muted' if item['mute'] else 'unmuted'}", "ok")
    update_rows()
    queue_write(item, cmd)


def change_balance(step):
    """b / B: pan the selected device left or right, 0 to re-centre.

    pactl has no balance setter, so this writes the two channel volumes
    directly -- `set-sink-volume NAME <left>% <right>%` -- derived from the
    device's current mean volume. Stereo only: there is nothing to pan on a
    mono microphone, and a surround map would need more than two values.
    """
    item = selected()
    if item is None or _BUSY or _VIEW not in ("outputs", "inputs"):
        return
    if item.get("nchannels", 0) != 2:
        set_status("Balance needs a stereo device", "idle")
        update()
        return

    session = _SESSION
    try:
        balance = float(item.get("balance", 0.0))
    except (TypeError, ValueError):
        balance = 0.0
    balance = 0.0 if step == 0 else max(-1.0, min(1.0, balance + step))

    # left drops as balance goes right, and vice versa -- the same mapping
    # PulseAudio itself uses, so the value read back matches what we set.
    vol = item["vol"]
    left = round(vol * (1 - max(0.0, balance)))
    right = round(vol * (1 + min(0.0, balance)))

    setter = "set-source-volume" if _VIEW == "inputs" else "set-sink-volume"
    cmd = ["pactl", setter, item["name"], f"{left}%", f"{right}%"]

    item["balance"] = balance
    item["vol_channels"] = dict(zip(item.get("vol_channels", {}), (left, right)))
    set_status(
        f"{item['desc']}  balance "
        f"{'centre' if abs(balance) < 0.005 else f'{abs(balance) * 100:.0f}% ' + ('R' if balance > 0 else 'L')}",
        "ok",
    )
    update_rows()
    queue_write(item, cmd)


def show_targets():
    """Enter on a stream: pick which device it should play through."""
    global _TARGET_STREAM, _TARGET_IS_INPUT

    if not is_stream_view():
        return
    stream = selected()
    if stream is None:
        return

    _TARGET_IS_INPUT = _VIEW == "recording"
    pool = _SOURCES if _TARGET_IS_INPUT else _SINKS
    if not pool:
        set_status("Nowhere to move it to", "idle")
        update()
        return

    _TARGET_STREAM = stream
    set_view("targets")
    # Start on the device it is already using, so Enter-Enter is a no-op
    # rather than a surprise move.
    _INDEX["targets"] = next(
        (i for i, d in enumerate(pool) if d["index"] == stream["target"]), 0
    )
    ensure_visible()
    set_status(f"Move {stream['app']} to…", "idle")
    update()


def send_to_default():
    """d: shortcut for the common case -- put this stream on the default."""
    global _BUSY

    if not is_stream_view() or _BUSY:
        return
    stream = selected()
    if stream is None:
        return

    playback = _VIEW == "playback"
    target = _DEFAULT_SINK if playback else _DEFAULT_SOURCE
    if not target:
        set_status("No default device", "error")
        update()
        return

    session = _SESSION
    mover = "move-sink-input" if playback else "move-source-output"
    index, label = stream["index"], stream["app"]

    _BUSY = True
    set_status(f"Moving {label} to the default device…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = run(["pactl", mover, str(index), target], T_QUICK)
        _finish(session, ok, f"Moved {label}" if ok else _pactl_error(out))

    in_thread(worker)


def show_cards():
    """C: every card and its active profile -- pavucontrol's Configuration tab.

    The per-device `p` answers "what is THIS thing doing"; this answers
    "what is everything doing", which is the question when a card you are
    not pointing at is the one in the wrong mode.
    """
    if _VIEW == "cards":
        set_view("outputs")
        return
    if not _CARDS:
        set_status("No sound cards found", "idle")
        update()
        return
    set_view("cards")
    set_status(f"{len(_CARDS)} card(s)", "idle")
    update()


def open_profiles_for(card):
    """Open the profiles view against a specific card."""
    global _PROFILE_CARD
    if not card:
        return
    _PROFILE_CARD = card
    set_view("profiles")
    _INDEX["profiles"] = next(
        (i for i, p in enumerate(card["profiles"]) if p["name"] == card["active"]),
        0,
    )
    ensure_visible()
    update()


def show_ports():
    """P: switch to the port list of the selected device.

    The dropdown at the top of pavucontrol's device rows, and the reason a
    headphone jack was unreachable from the keyboard: a sink can expose
    Speakers, Headphones and Line Out and only one of them is live.
    """
    global _PORT_DEVICE, _PORT_IS_INPUT

    if _VIEW == "ports":
        set_view("outputs")
        return

    if _VIEW in ("outputs", "inputs"):
        device, is_input = selected(), _VIEW == "inputs"
    else:
        # From a stream view, fall back to the default device -- pressing P
        # there should still land somewhere useful.
        device = next((s for s in _SINKS if s["name"] == _DEFAULT_SINK), None)
        is_input = False

    if device is None or not device.get("ports"):
        set_status("This device has no selectable ports", "idle")
        update()
        return

    _PORT_DEVICE, _PORT_IS_INPUT = device, is_input
    set_view("ports")
    active = next(
        (i for i, p in enumerate(device["ports"]) if p["name"] == device["port"]), 0
    )
    _INDEX["ports"] = active
    ensure_visible()
    update()


def show_profiles():
    """p: switch to the card profiles of the selected device.

    Bound to a device rather than offered as a flat card list: "which
    profile is my headset on" is the question, and the card that answers it
    is whichever one owns the row you are looking at.
    """
    global _PROFILE_CARD

    if _VIEW == "profiles":
        set_view("outputs")
        return

    device = selected() if _VIEW in ("outputs", "inputs") else None
    card = card_for(device) if device else None
    if card is None:
        # Fall back to the card of the default output: pressing p from the
        # apps view should still get somewhere useful.
        card = card_for(next((s for s in _SINKS if s["name"] == _DEFAULT_SINK), None))
    if card is None:
        set_status("No card for this device", "idle")
        update()
        return

    _PROFILE_CARD = card
    set_view("profiles")
    # Land on the active profile rather than the top of the list.
    active = next(
        (i for i, p in enumerate(card["profiles"]) if p["name"] == card["active"]),
        0,
    )
    _INDEX["profiles"] = active
    ensure_visible()
    update()


def cancel():
    """c: abort a card-profile switch that is taking too long.

    Killing pactl only drops the client; PipeWire carries on with the
    profile change it was asked for. There is no counter-command for a
    profile switch, so this reports honestly rather than pretending to have
    undone it -- the follow-up refresh shows whatever actually landed.
    """
    global _BUSY

    if not _BUSY:
        set_status("Nothing to cancel", "idle")
        update()
        return

    session = _SESSION
    _CANCEL.set()

    proc = _PROC
    if proc is not None:
        try:
            proc.kill()
        except Exception:
            pass

    _BUSY = False
    set_status("Cancelled", "idle")
    update()
    on_ui(session, lambda: refresh(loud=False))


# =============================================================================
# NAVIGATION
# =============================================================================
def clamp_index():
    items = current_items()
    _INDEX[_VIEW] = max(0, min(_INDEX.get(_VIEW, 0), max(0, len(items) - 1)))


def ensure_visible():
    items = current_items()
    index = _INDEX.get(_VIEW, 0)
    offset = _OFFSET.get(_VIEW, 0)
    if index < offset:
        offset = index
    elif index >= offset + ROWS_VISIBLE:
        offset = index - ROWS_VISIBLE + 1
    _OFFSET[_VIEW] = max(0, min(offset, max(0, len(items) - ROWS_VISIBLE)))


def move(step):
    if _LAYOUT is None or not current_items():
        return
    _INDEX[_VIEW] = max(0, min(len(current_items()) - 1, _INDEX.get(_VIEW, 0) + step))
    ensure_visible()
    update()


def jump(where):
    if _LAYOUT is None or not current_items():
        return
    _INDEX[_VIEW] = 0 if where == "top" else len(current_items()) - 1
    ensure_visible()
    update()


def set_view(view):
    global _VIEW
    if view not in _VIEWS:
        return
    if view == "profiles" and _PROFILE_CARD is None:
        return
    if view == "ports" and _PORT_DEVICE is None:
        return
    if view == "targets" and _TARGET_STREAM is None:
        return
    if view == "cards" and not _CARDS:
        return
    _VIEW = view
    clamp_index()
    ensure_visible()
    if _LAYOUT is not None:
        update()


def cycle_view(step=1):
    """Tab: move through the four device/stream tabs.

    Ports and profiles are deliberately outside the cycle -- they describe
    one device rather than standing beside the lists, and Tab landing on a
    stale port list every time round was worse than reaching it with P.
    Tab from either of them returns to the tabs.
    """
    order = list(_TABS)
    try:
        pos = order.index(_VIEW)
    except ValueError:
        # Coming out of a sub-view: Tab goes back to the tab it was opened
        # from, so Tab never dead-ends.
        if _VIEW == "targets":
            set_view("recording" if _TARGET_IS_INPUT else "playback")
        elif _VIEW == "ports" and _PORT_IS_INPUT:
            set_view("inputs")
        else:
            set_view("outputs")
        return
    set_view(order[(pos + step) % len(order)])


# =============================================================================
# POPUP CONTROL
# =============================================================================
def show(qtile):
    global _LAYOUT, _QTILE, _SESSION, _VIEW, _PROFILE_CARD, _PORT_DEVICE
    global _TARGET_STREAM, _VOL_TIMER
    global _SINKS, _SOURCES, _APPS, _RECORDING, _CARDS, _BUSY, _BUSY_PHASE

    _QTILE = qtile
    if _LAYOUT is not None or _CLOSING:
        return

    # Refresh from the palette cache so the popup retints after a theme
    # switch without a qtile restart (same pattern as the other popups).
    COLORS.update(_load_colors())

    _SESSION += 1
    session = _SESSION
    _VIEW = "outputs"
    _PROFILE_CARD = None
    _PORT_DEVICE = None
    _TARGET_STREAM = None
    _PENDING.clear()
    _VOL_QUEUE.clear()
    # Belt and braces: a non-None _VOL_TIMER makes queue_write believe a
    # flush is already scheduled and return without queuing, which would
    # silently kill every volume key for the whole session. close() clears
    # it via cancel_timers(), but an open must not depend on a clean close.
    _VOL_TIMER = None
    _SINKS = _SOURCES = _APPS = _RECORDING = _CARDS = []
    for view in _VIEWS:
        _INDEX[view] = _OFFSET[view] = 0
    _BUSY = False
    _BUSY_PHASE = 0
    set_status("Reading devices…", "busy")

    head_y, head_h = 24 / POPUP_H, 54 / POPUP_H
    hint_y, hint_h = 88 / POPUP_H, 30 / POPUP_H
    tabs_y, tabs_h = 126 / POPUP_H, 26 / POPUP_H
    body_y, body_h = 162 / POPUP_H, 350 / POPUP_H
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
            text=render_tabs(), markup=True, font=FONT, fontsize=HINT_SIZE,
            pos_x=0.03, pos_y=tabs_y, width=0.94, height=tabs_h,
            h_align="center", v_align="middle", name="tabs",
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

    refresh(loud=True, reason="Reading devices…")
    schedule_refresh(session)


def close(qtile=None):
    global _LAYOUT, _CLOSING, _SESSION, _BUSY, _PROFILE_CARD, _PORT_DEVICE
    global _TARGET_STREAM

    if _LAYOUT is None or _CLOSING:
        return

    layout = _LAYOUT
    _CLOSING = True
    # Bump the session first: in-flight pactl workers and timers check it and
    # drop their callbacks rather than draw into a popup that is going away.
    _SESSION += 1
    _BUSY = False
    _PROFILE_CARD = None
    _PORT_DEVICE = None
    _TARGET_STREAM = None
    _PENDING.clear()
    _VOL_QUEUE.clear()
    cancel_timers()
    _LAYOUT = None

    def teardown():
        global _CLOSING
        try:
            # kill(), not hide(). hide() only unmaps the X window: the window,
            # its cairo drawer and the controls' pango layouts all stay
            # allocated, while show() builds a *new* PopupRelativeLayout every
            # time -- which is how the old popups leaked ~2.7MB per open.
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
