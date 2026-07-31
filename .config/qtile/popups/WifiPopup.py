"""WiFi picker popup, backed by nmcli.

Design notes that are easy to get wrong and expensive to rediscover:

* Nothing that talks to nmcli runs on the qtile event loop. A scan takes
  seconds and a connect can take tens of seconds; run on the loop, that is a
  frozen desktop. Every command goes to a worker thread and comes back via
  ``qtile.call_soon_threadsafe``.
* Every worker captures ``_SESSION`` when it starts and its callback is
  dropped if the session has moved on. Closing the popup bumps the session,
  so a scan still in flight when you hit Escape can't repaint a dead layout
  or reschedule a timer that outlives the popup.
* nmcli's terse output escapes ``:`` inside fields as ``\\:`` (BSSIDs are
  full of them), so the output is parsed with an escape-aware splitter
  rather than ``str.split(":")``.
* Access points are per-BSSID; the same SSID shows up once per radio/band.
  The list is deduplicated to the strongest BSSID per SSID.
* A saved profile's *name* is not its SSID (NetworkManager makes
  "MySSID 1", "MySSID 2", ... on repeat connects), so profiles are mapped to
  the SSID they actually carry before anything is matched against the scan.

Text input (passwords, hidden SSIDs) is delegated to rofi: it handles
masking, clipboard paste and keyboard layouts, none of which a popup built
from PopupText controls can do.
"""

import subprocess
import threading

from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger

from popups._wal_colors import load_colors as _load_wal_colors
from popups._wal_colors import fade_in_popup, fade_out_popup
from popups._wal_colors import _mix

# =============================================================================
# GLOBAL STATE
# =============================================================================
_LAYOUT = None
_QTILE = None
_CLOSING = False

# Bumped on every open and close. Worker callbacks and timers carry the value
# they were spawned with and no-op once it no longer matches.
_SESSION = 0

_NETWORKS = []     # [{ssid, signal, security, active, band, chan, bssid, rate}]
_INDEX = 0
_OFFSET = 0        # first visible row, for lists longer than ROWS_VISIBLE

_IFACE = None
_RADIO = True
_ACTIVE_SSID = None
_ACTIVE_PROFILE = None
_SAVED = {}        # ssid -> [profile names]
_DETAILS = {}      # ip / gateway / dns of the live connection

_STATUS = "Ready"
_STATUS_LEVEL = "idle"   # idle | busy | ok | error
_BUSY = False
_BUSY_PHASE = 0
_PENDING_FORGET = None   # ssid awaiting a confirming second `x`

_TIMERS = []

# =============================================================================
# CONFIG & STYLING
# =============================================================================
POPUP_W = 940
POPUP_H = 600

FONT = "JetBrainsMono Nerd Font"  # monospace: the padded rows only line up
ROW_SIZE = 14                     # in a fixed-width face
HEAD_SIZE = 14
HINT_SIZE = 13
FOOT_SIZE = 14

# qtile builds text layouts with a *pixel* font size ("<family> <n>px"), so
# these are px, not points: a ROW_SIZE line box is 20px tall and 17 rows
# (340px) sit inside the 373px list card with room to breathe.
ROWS_VISIBLE = 17
MAX_SSID_LEN = 34

SCAN_INTERVAL = 20    # seconds between idle background refreshes
SPIN_INTERVAL = 0.12  # seconds per frame of the busy bar


def _load_colors():
    base = _load_wal_colors()
    base["line"] = _mix(base["bg"], base["fg"], 0.22)
    base["highlight_bg"] = base["green"]
    base["highlight_fg"] = base["bg"]
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)
    return base


COLORS = _load_colors()


# =============================================================================
# SMALL HELPERS
# =============================================================================
def esc(text):
    """Escape text for Pango markup.

    SSIDs are free text from strangers -- an access point named "Free & Fast"
    is enough to make the whole row malformed markup, at which point pango
    silently drops the entire line rather than the one bad character.
    """
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fit(text, width):
    """Truncate with an ellipsis and pad to exactly `width` cells."""
    text = str(text)
    if len(text) > width:
        text = text[: width - 1] + "…"
    return f"{text:<{width}}"


def terse_split(line):
    """Split one line of `nmcli -t` output, honouring its backslash escapes.

    nmcli escapes the field separator inside values, so BSSIDs arrive as
    ``7A\\:83\\:C2\\:2D\\:3E\\:D6``. Splitting on ":" yields eleven fields for
    an eight-field query, which is precisely how the previous version of this
    popup managed to never list a single network: the unpack raised, the
    bare `except` swallowed it, and the list came back empty every time.
    """
    fields, buf, escaped = [], [], False
    for ch in line:
        if escaped:
            buf.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            fields.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    fields.append("".join(buf))
    return fields


def run(cmd, timeout=25):
    """Run a command, returning (ok, output). Never raises."""
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        return proc.returncode == 0, (proc.stdout or "").strip()
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except FileNotFoundError:
        return False, f"{cmd[0]} not found"
    except Exception as e:
        logger.warning("WifiPopup: %s failed: %s", cmd[0], e)
        return False, str(e)


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
            logger.exception("WifiPopup UI callback failed: %s", e)

    _QTILE.call_soon_threadsafe(_guarded)


def in_thread(fn, *args):
    threading.Thread(target=fn, args=args, daemon=True).start()


def add_timer(delay, session, fn):
    """call_later that dies with the session instead of outliving the popup.

    The old popup rescheduled a 6-second refresh unconditionally, including
    after it had been closed, so every open leaked another immortal timer.
    """
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
# NMCLI QUERIES  (worker threads only)
# =============================================================================
def query_iface():
    """(device, state, active connection name) for the first wifi device."""
    ok, out = run(
        ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"], 10
    )
    if not ok:
        return None, None, None

    for line in out.splitlines():
        parts = terse_split(line)
        if len(parts) >= 4 and parts[1] == "wifi":
            connection = parts[3] if parts[2] == "connected" else None
            return parts[0], parts[2], connection
    return None, None, None


def query_radio():
    ok, out = run(["nmcli", "-t", "radio", "wifi"], 10)
    # Fail open: if the query itself breaks, don't claim the radio is off and
    # hide a network list that may be perfectly fine.
    return (not ok) or out.strip() != "disabled"


def query_saved():
    """{ssid: [profile names]} for every saved wifi profile.

    Keyed by the SSID the profile carries, not by its name: NetworkManager
    happily stores "Cafe", "Cafe 1" and "Cafe 2" all pointing at one network,
    and matching on the name alone shows a known network as new.
    """
    saved = {}
    ok, out = run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], 10)
    if not ok:
        return saved

    for line in out.splitlines():
        parts = terse_split(line)
        if len(parts) < 2 or parts[1] != "802-11-wireless":
            continue
        name = parts[0]
        ok_ssid, ssid = run(
            ["nmcli", "-g", "802-11-wireless.ssid", "connection", "show", "id", name],
            10,
        )
        ssid = ssid.strip() if ok_ssid else ""
        saved.setdefault(ssid or name, []).append(name)
    return saved


def query_networks(rescan=False):
    """(networks, error): strongest BSSID per SSID, best signal first.

    `rescan` forces a fresh sweep of the radio (`--rescan yes`); background
    refreshes pass False and get `--rescan auto`, which reuses NetworkManager's
    cache but re-scans when it goes stale. Not `--rescan no`: the cache can
    come back with a single AP in it moments after a real scan saw a dozen,
    and the list would visibly collapse and refill every 20 seconds.
    """
    cmd = [
        "nmcli", "-t",
        "-f", "ACTIVE,SSID,SIGNAL,SECURITY,FREQ,RATE,CHAN,BSSID",
        "dev", "wifi", "list",
        "--rescan", "yes" if rescan else "auto",
    ]
    ok, out = run(cmd, 45 if rescan else 30)
    if not ok:
        return [], out

    best = {}
    for line in out.splitlines():
        parts = terse_split(line)
        if len(parts) < 8:
            continue

        active, ssid, signal, security, freq, rate, chan, bssid = parts[:8]
        if not ssid:
            continue  # hidden APs advertise an empty SSID; nothing to select

        try:
            signal = int(signal)
        except ValueError:
            signal = 0

        try:
            band = "5 GHz" if int(freq.split()[0]) >= 5000 else "2.4 GHz"
        except (ValueError, IndexError):
            band = ""

        net = {
            "ssid": ssid,
            "signal": signal,
            "security": security or "",
            "active": active == "yes",
            "band": band,
            "chan": chan,
            "rate": rate,
            "bssid": bssid,
        }

        prev = best.get(ssid)
        # The connected BSSID wins even when another one is louder, otherwise
        # the row you are connected through stops being the row you see.
        if prev is None or net["active"] or (
            not prev["active"] and signal > prev["signal"]
        ):
            best[ssid] = net

    return sorted(best.values(), key=lambda n: (not n["active"], -n["signal"])), ""


def query_details(iface):
    """IP / gateway / DNS of the live connection, for the details panel."""
    if not iface:
        return {}

    ok, out = run(
        ["nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "dev", "show", iface],
        10,
    )
    if not ok:
        return {}

    details = {"dns": []}
    for line in out.splitlines():
        key, _, value = line.partition(":")
        value = value.strip()
        if not value:
            continue
        if key.startswith("IP4.ADDRESS"):
            details.setdefault("ip", value)
        elif key.startswith("IP4.GATEWAY"):
            details["gateway"] = value
        elif key.startswith("IP4.DNS"):
            details["dns"].append(value)
    return details


# =============================================================================
# RENDERING
# =============================================================================
def signal_icon(signal):
    if signal >= 80:
        return "\U000f0928"
    if signal >= 60:
        return "\U000f0925"
    if signal >= 40:
        return "\U000f0922"
    if signal >= 20:
        return "\U000f091f"
    return "\U000f092f"


def selected_network():
    if 0 <= _INDEX < len(_NETWORKS):
        return _NETWORKS[_INDEX]
    return None


def render_list():
    """The network list card.

    Always emits exactly ROWS_VISIBLE lines so the card's v_align="middle"
    keeps rows pinned in the same place whether four networks are in range
    or forty, and every row is the same cell count so the selected row's
    block lands exactly where the other rows' text does.
    """
    if not _RADIO:
        message = "WiFi radio is off  (nmcli radio wifi on)"
    elif not _IFACE:
        message = "No WiFi device found"
    elif not _NETWORKS:
        message = "Scanning…" if _BUSY else "No networks in range"
    else:
        message = None

    if message is not None:
        lines = []
        for row in range(ROWS_VISIBLE):
            if row == ROWS_VISIBLE // 2:
                lines.append(
                    f'<span foreground="{COLORS["muted"]}">  {esc(message)}</span>'
                )
            else:
                lines.append("")
        return "\n".join(lines)

    pad = f'<span foreground="{COLORS["surface"]}"> </span>'
    lines = []

    for row in range(ROWS_VISIBLE):
        idx = _OFFSET + row
        if idx >= len(_NETWORKS):
            lines.append("")
            continue

        net = _NETWORKS[idx]
        # Written as escapes, not literal glyphs: both are exactly one cell
        # wide, and a lost/substituted glyph would shift every column after
        # it out of alignment on that row alone.
        lock = "\uf023" if net["security"] else "\uf09c"  # padlock: shut / open

        if net["active"]:
            tag = "connected"
        elif net["ssid"] in _SAVED:
            tag = "saved"
        else:
            tag = ""

        head = f" {signal_icon(net['signal'])} {esc(fit(net['ssid'], MAX_SSID_LEN))} "
        tail = f" {fit(tag, 10)} {net['signal']:>3}% "

        if idx == _INDEX:
            # One uniform block, padlock included: on the accent background a
            # differently-coloured cell reads as a rendering glitch.
            attrs = (
                f'background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold"'
            )
            lines.append(f"{pad}<span {attrs}>{head}{lock}{tail}</span>")
        else:
            colour = COLORS["green"] if net["active"] else COLORS["fg"]
            weight = ' weight="bold"' if net["active"] else ""
            # An open network is worth flagging, so the padlock cell gets its
            # own colour. Adjacent spans, so the row still reads as one line.
            lock_colour = COLORS["fg"] if net["security"] else COLORS["red"]
            lines.append(
                f'{pad}<span foreground="{colour}"{weight}>{head}</span>'
                f'<span foreground="{lock_colour}">{lock}</span>'
                f'<span foreground="{colour}"{weight}>{tail}</span>'
            )

    return "\n".join(lines)


def render_details():
    """Right-hand panel describing the selected network."""
    net = selected_network()
    if net is None:
        return f'<span foreground="{COLORS["muted"]}">No network selected</span>'

    def field(label, value, colour=None):
        return (
            f'<span foreground="{COLORS["muted"]}">{label:<10}</span>'
            f'<span foreground="{colour or COLORS["fg"]}">{esc(value)}</span>'
        )

    bar_len = 18
    filled = max(1, round(bar_len * net["signal"] / 100))
    strength = (
        f'<span foreground="{COLORS["muted"]}">{"signal":<10}</span>'
        f'<span foreground="{COLORS["highlight_bg"]}">{"━" * filled}</span>'
        f'<span foreground="{COLORS["line"]}">{"━" * (bar_len - filled)}</span>'
        f'<span foreground="{COLORS["fg"]}"> {net["signal"]}%</span>'
    )

    if net["active"]:
        state, state_colour = "connected", COLORS["green"]
    elif net["ssid"] in _SAVED:
        state, state_colour = "saved", COLORS["blue"]
    else:
        state, state_colour = "not saved", COLORS["muted"]

    band = f"{net['band']}  ·  ch {net['chan']}" if net["band"] else net["chan"]

    rows = [
        f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
        f'{esc(fit(net["ssid"], MAX_SSID_LEN).strip())}</span>',
        "",
        strength,
        field("security", net["security"] or "open",
              COLORS["fg"] if net["security"] else COLORS["red"]),
        field("band", band),
        field("max rate", net["rate"]),
        field("bssid", net["bssid"]),
        field("state", state, state_colour),
    ]

    if net["active"]:
        rows.append("")
        rows.append(field("ip", _DETAILS.get("ip", "—")))
        rows.append(field("gateway", _DETAILS.get("gateway", "—")))
        dns = _DETAILS.get("dns") or []
        rows.append(field("dns", dns[0] if dns else "—"))
        for extra in dns[1:3]:
            rows.append(field("", extra))
        if _ACTIVE_PROFILE:
            rows.append(field("profile", fit(_ACTIVE_PROFILE, 22).strip()))

    return "\n".join(rows)


def render_header():
    left = f"{_IFACE}  ·  {len(_NETWORKS)} networks" if _IFACE else "no wifi device"
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["fg"]}">'
        f"\U000f0928  Wi-Fi</span>\n"
        f'<span size="small" foreground="{COLORS["muted"]}">{esc(left)}</span>'
    )


def render_header_badge():
    if not _RADIO:
        text, colour, icon = "radio off", COLORS["red"], "\U000f092e"
    elif _ACTIVE_SSID:
        text, colour, icon = _ACTIVE_SSID, COLORS["green"], "\U000f0928"
    else:
        text, colour, icon = "not connected", COLORS["muted"], "\U000f092e"

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
    gap = f'<span foreground="{COLORS["line"]}">   </span>'
    pairs = [
        ("jk", "move"),
        ("↵", "connect"),
        ("d", "disconnect"),
        ("x", "forget"),
        ("n", "hidden"),
        ("r", "rescan"),
        ("/", "search"),
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
        # Indeterminate sweep rather than a percentage: nmcli reports no
        # progress, and the old popup's 0-100% bar was a fiction animated on
        # a timer while the real connect hadn't even been started yet.
        track, window = 24, 4
        pos = _BUSY_PHASE % (track + window)
        cells = [
            (COLORS["highlight_bg"] if pos - window < i <= pos else COLORS["line"])
            for i in range(track)
        ]
        bar = "".join(f'<span foreground="{c}">━</span>' for c in cells)
        prefix = f"{bar}   "

    return f'{prefix}<span foreground="{colour}" weight="bold">{esc(_STATUS)}</span>'


def update():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(
        header=render_header(),
        badge=render_header_badge(),
        networks=render_list(),
        details=render_details(),
        footer=render_footer(),
    )


# =============================================================================
# SCANNING
# =============================================================================
def start_scan(rescan=False, reason=None, then=None):
    """Refresh device / radio / saved / scan state in one worker pass."""
    global _BUSY

    session = _SESSION
    if rescan:
        _BUSY = True
        set_status(reason or "Scanning for networks…", "busy")
        spin(session)
        update()

    def worker():
        iface, state, connection = query_iface()
        radio = query_radio()
        saved = query_saved()
        nets, err = query_networks(rescan=rescan) if (radio and iface) else ([], "")
        details = query_details(iface) if state == "connected" else {}

        def apply():
            global _IFACE, _RADIO, _SAVED, _NETWORKS, _DETAILS, _BUSY
            global _ACTIVE_SSID, _ACTIVE_PROFILE, _INDEX

            keep = selected_network()

            _IFACE, _RADIO, _SAVED = iface, radio, saved
            _NETWORKS, _DETAILS = nets, details
            _ACTIVE_PROFILE = connection
            _ACTIVE_SSID = next((n["ssid"] for n in nets if n["active"]), None)

            # Hold the cursor on the same SSID across a refresh: the list is
            # sorted by signal, so rows shuffle under you every few seconds.
            if keep is not None:
                _INDEX = next(
                    (i for i, n in enumerate(_NETWORKS) if n["ssid"] == keep["ssid"]),
                    min(_INDEX, max(0, len(_NETWORKS) - 1)),
                )
            else:
                _INDEX = min(_INDEX, max(0, len(_NETWORKS) - 1))
            ensure_visible()

            if rescan:
                _BUSY = False
                if err:
                    set_status(err.splitlines()[0][:70], "error")
                elif not radio:
                    set_status("WiFi radio is off", "error")
                elif not iface:
                    set_status("No WiFi device found", "error")
                else:
                    set_status(f"Found {len(nets)} networks", "ok")

            update()
            if then is not None:
                then()

        on_ui(session, apply)

    in_thread(worker)


def spin(session):
    """Advance the busy bar until whatever is running finishes."""
    def tick():
        global _BUSY_PHASE
        if not _BUSY:
            return
        _BUSY_PHASE += 1
        update()
        add_timer(SPIN_INTERVAL, session, tick)

    add_timer(SPIN_INTERVAL, session, tick)


def schedule_autoscan(session):
    def tick():
        if not _BUSY:
            start_scan(rescan=False)
        schedule_autoscan(session)

    add_timer(SCAN_INTERVAL, session, tick)


def rescan():
    """r: force a fresh scan."""
    if _BUSY:
        return
    start_scan(rescan=True, reason="Rescanning…")


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
        # Re-read so the row, the badge and the details panel all agree with
        # what NetworkManager actually did, rather than what we asked for.
        start_scan(rescan=False)

    on_ui(session, apply)


def _cancel(message):
    global _BUSY
    _BUSY = False
    set_status(message, "idle")
    update()


def _nmcli_error(output):
    """First useful line of an nmcli failure, trimmed to fit the footer."""
    for line in (output or "").splitlines():
        line = line.strip()
        if line.lower().startswith("error:"):
            line = line[6:].strip()
        if line:
            return line[:70]
    return "failed"


def rofi_prompt(prompt, password=False):
    """Blocking rofi prompt -- callers must already be on a worker thread."""
    cmd = [
        "rofi", "-dmenu", "-l", "0", "-p", prompt,
        "-theme-str", "window {width: 32%;}",
    ]
    if password:
        cmd.append("-password")

    try:
        proc = subprocess.run(
            cmd, input="", stdout=subprocess.PIPE, text=True, timeout=180
        )
        return proc.stdout.strip() if proc.returncode == 0 else None
    except Exception as e:
        logger.warning("WifiPopup: rofi prompt failed: %s", e)
        return None


def connect():
    """Enter: connect to the selected network."""
    global _BUSY, _PENDING_FORGET
    _PENDING_FORGET = None

    net = selected_network()
    if net is None or _BUSY:
        return

    if net["active"]:
        set_status(f"Already connected to {net['ssid']}", "ok")
        update()
        return

    session = _SESSION
    ssid = net["ssid"]
    profiles = _SAVED.get(ssid) or []
    secured = bool(net["security"])

    _BUSY = True
    set_status(f"Connecting to {ssid}…", "busy")
    spin(session)
    update()

    def worker():
        if profiles:
            # Known network: bring the stored profile up, no password needed.
            ok, out = run(["nmcli", "connection", "up", "id", profiles[0]], 60)
        elif secured:
            password = rofi_prompt(f"Password for {ssid}", password=True)
            if not password:
                on_ui(session, lambda: _cancel("Cancelled"))
                return
            ok, out = run(
                ["nmcli", "dev", "wifi", "connect", ssid, "password", password], 60
            )
        else:
            ok, out = run(["nmcli", "dev", "wifi", "connect", ssid], 60)

        _finish(session, ok, f"Connected to {ssid}" if ok else _nmcli_error(out))

    in_thread(worker)


def disconnect():
    """d: drop the active connection on the wifi device."""
    global _BUSY, _PENDING_FORGET
    _PENDING_FORGET = None

    if _BUSY:
        return
    if not _ACTIVE_PROFILE:
        set_status("Not connected", "idle")
        update()
        return

    session = _SESSION
    profile, iface = _ACTIVE_PROFILE, _IFACE

    _BUSY = True
    set_status(f"Disconnecting from {_ACTIVE_SSID or profile}…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = run(["nmcli", "connection", "down", "id", profile], 30)
        if not ok and iface:
            # Fall back to the device: a profile can go down underneath us
            # between the last scan and the keypress.
            ok, out = run(["nmcli", "dev", "disconnect", iface], 30)
        _finish(session, ok, "Disconnected" if ok else _nmcli_error(out))

    in_thread(worker)


def forget():
    """x: delete every saved profile for the selected SSID.

    Two-step on purpose: the first press arms it and says so in the footer,
    a second press on the same row does it. Destroying a stored password on
    one keypress, sat next to `d`, is too easy to do by accident.
    """
    global _BUSY, _PENDING_FORGET

    net = selected_network()
    if net is None or _BUSY:
        return

    ssid = net["ssid"]
    profiles = _SAVED.get(ssid) or []
    if not profiles:
        _PENDING_FORGET = None
        set_status(f"{ssid} is not saved", "idle")
        update()
        return

    if _PENDING_FORGET != ssid:
        _PENDING_FORGET = ssid
        set_status(f"Press x again to forget {ssid}", "error")
        update()
        return

    _PENDING_FORGET = None
    session = _SESSION

    _BUSY = True
    set_status(f"Forgetting {ssid}…", "busy")
    spin(session)
    update()

    def worker():
        ok, out = True, ""
        for profile in profiles:
            good, output = run(["nmcli", "connection", "delete", "id", profile], 30)
            if not good:
                ok, out = False, output
        _finish(session, ok, f"Forgot {ssid}" if ok else _nmcli_error(out))

    in_thread(worker)


def connect_hidden():
    """n: join a network that doesn't broadcast its SSID."""
    global _PENDING_FORGET
    _PENDING_FORGET = None

    if _BUSY:
        return

    session = _SESSION

    def worker():
        ssid = rofi_prompt("Hidden network SSID")
        if not ssid:
            return
        password = rofi_prompt(f"Password for {ssid}  (empty = open)", password=True)

        def begin():
            global _BUSY
            _BUSY = True
            set_status(f"Connecting to {ssid}…", "busy")
            spin(session)
            update()

        on_ui(session, begin)

        cmd = ["nmcli", "dev", "wifi", "connect", ssid, "hidden", "yes"]
        if password:
            cmd[5:5] = ["password", password]
        ok, out = run(cmd, 60)
        _finish(session, ok, f"Connected to {ssid}" if ok else _nmcli_error(out))

    in_thread(worker)


def search():
    """/: jump to a network by name via rofi."""
    global _PENDING_FORGET
    _PENDING_FORGET = None

    if not _NETWORKS:
        return

    session = _SESSION
    names = "\n".join(n["ssid"] for n in _NETWORKS)

    def worker():
        try:
            proc = subprocess.run(
                ["rofi", "-dmenu", "-i", "-p", "Network",
                 "-theme-str", "window {width: 40%;}"],
                input=names, stdout=subprocess.PIPE, text=True, timeout=120,
            )
            choice = proc.stdout.strip()
        except Exception as e:
            logger.warning("WifiPopup: rofi search failed: %s", e)
            return

        if not choice:
            return

        def apply():
            global _INDEX
            for i, net in enumerate(_NETWORKS):
                if net["ssid"] == choice:
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
    _OFFSET = max(0, min(_OFFSET, max(0, len(_NETWORKS) - ROWS_VISIBLE)))


def move(step):
    global _INDEX, _PENDING_FORGET
    if _LAYOUT is None or not _NETWORKS:
        return
    _PENDING_FORGET = None  # moving off the row disarms a pending forget
    _INDEX = max(0, min(len(_NETWORKS) - 1, _INDEX + step))
    ensure_visible()
    update()


def jump(where):
    global _INDEX, _PENDING_FORGET
    if _LAYOUT is None or not _NETWORKS:
        return
    _PENDING_FORGET = None
    _INDEX = 0 if where == "top" else len(_NETWORKS) - 1
    ensure_visible()
    update()


# =============================================================================
# POPUP CONTROL
# =============================================================================
def show(qtile):
    global _LAYOUT, _QTILE, _SESSION, _INDEX, _OFFSET, _NETWORKS
    global _BUSY, _BUSY_PHASE, _PENDING_FORGET

    _QTILE = qtile
    if _LAYOUT is not None or _CLOSING:
        return

    # Refresh from the palette cache so the popup retints after a theme
    # switch without a qtile restart (same pattern as the other popups).
    COLORS.update(_load_colors())

    _SESSION += 1
    session = _SESSION
    _INDEX = _OFFSET = 0
    _NETWORKS = []
    _BUSY = False
    _BUSY_PHASE = 0
    _PENDING_FORGET = None
    set_status("Scanning for networks…", "busy")

    head_y, head_h = 24 / POPUP_H, 54 / POPUP_H
    hint_y, hint_h = 88 / POPUP_H, 30 / POPUP_H
    body_y, body_h = 132 / POPUP_H, 380 / POPUP_H
    foot_y, foot_h = 524 / POPUP_H, 54 / POPUP_H

    controls = [
        PopupText(
            text=render_header(),
            markup=True,
            font=FONT,
            fontsize=HEAD_SIZE,
            pos_x=0.03,
            pos_y=head_y,
            width=0.45,
            height=head_h,
            h_align="left",
            v_align="middle",
            name="header",
        ),
        PopupText(
            text=render_header_badge(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            pos_x=0.5,
            pos_y=head_y,
            width=0.47,
            height=head_h,
            h_align="right",
            v_align="middle",
            name="badge",
        ),
        PopupText(
            text=render_hints(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            background=COLORS["surface"],
            highlight_radius=8,
            pos_x=0.03,
            pos_y=hint_y,
            width=0.94,
            height=hint_h,
            h_align="center",
            v_align="middle",
            name="hints",
        ),
        PopupText(
            text=render_list(),
            markup=True,
            font=FONT,
            fontsize=ROW_SIZE,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.03,
            pos_y=body_y,
            width=0.499,
            height=body_h,
            h_align="left",
            v_align="middle",
            name="networks",
        ),
        PopupText(
            text=render_details(),
            markup=True,
            font=FONT,
            fontsize=HINT_SIZE,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.5452,
            pos_y=body_y,
            width=0.4238,
            height=body_h,
            h_align="left",
            v_align="top",
            name="details",
        ),
        PopupText(
            text=render_footer(),
            markup=True,
            font=FONT,
            fontsize=FOOT_SIZE,
            background=COLORS["surface"],
            highlight_radius=10,
            pos_x=0.03,
            pos_y=foot_y,
            width=0.94,
            height=foot_h,
            h_align="center",
            v_align="middle",
            name="footer",
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

    # Open on a forced rescan: the cached list is whatever nmcli last saw,
    # which after a suspend/resume is frequently nothing at all.
    start_scan(rescan=True, reason="Scanning for networks…")
    schedule_autoscan(session)


def close(qtile=None):
    global _LAYOUT, _CLOSING, _SESSION, _BUSY, _PENDING_FORGET

    if _LAYOUT is None or _CLOSING:
        return

    layout = _LAYOUT
    _CLOSING = True
    # Bump the session first: in-flight nmcli workers and timers check it and
    # drop their callbacks rather than draw into a popup that is going away.
    _SESSION += 1
    _BUSY = False
    _PENDING_FORGET = None
    cancel_timers()
    _LAYOUT = None

    def teardown():
        global _CLOSING
        try:
            layout.hide()
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
