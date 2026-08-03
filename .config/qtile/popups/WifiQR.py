"""Share the current WiFi network as a QR code.

Reads the active connection's SSID and stored PSK out of NetworkManager,
encodes them in the `WIFI:` URI that Android and iOS cameras understand, and
shows the code in a popup. Point a phone at it and it joins -- no reading a
20-character PSK off a screen.

Two things here are deliberate and easy to "fix" into breakage:

* The code is always rendered BLACK ON WHITE, whatever the desktop theme is,
  and sits on its own white card. Inverted (light-on-dark) codes are out of
  spec; plenty of phone cameras refuse them, and a QR you have to explain is
  worse than no QR.
* qrencode is run twice -- once at one pixel per module to learn how big the
  symbol is, then again at an integer scale that fills the card. Letting the
  popup scale the image instead would resample the modules at a fractional
  ratio and blur the edges the decoder needs.

nmcli reads the secret with --show-secrets, which works as the logged-in
user for system connections with psk-flags=0 (the default for anything
saved normally). No sudo, no polkit agent.
"""

import os
import subprocess
import threading

from qtile_extras.popup import PopupRelativeLayout, PopupText, PopupImage
from libqtile.config import Key, KeyChord
from libqtile.log_utils import logger

from popups._scale import s as _s
from popups._wal_colors import load_colors as _load_wal_colors
from popups._wal_colors import fade_in_popup, fade_out_popup
from popups._wal_colors import _mix, ensure_contrast

# =============================================================================
# STATE
# =============================================================================
_LAYOUT = None
_QTILE = None
_CLOSING = False
_SESSION = 0
# True while our Escape-only chord is grabbed. See _grab_escape().
_CHORD_HELD = False

CHORD_NAME = "Wifi-QR"

# =============================================================================
# CONFIG
# =============================================================================
POPUP_W = _s(380)
POPUP_H = _s(500)

FONT = "JetBrainsMono Nerd Font"
HEAD_SIZE = _s(14)
BODY_SIZE = _s(13)

# PopupRelativeLayout places controls as fractions of its *inner* box
# (width - 2*margin), not of the popup size. Converting through the inner
# box keeps these exact: at the naive px/POPUP_H the QR control came out
# 294px for a 296px symbol, and the popup silently resampled the modules --
# a blurred QR is a QR that some phones stop reading.
MARGIN = 5
INNER_W = POPUP_W - 2 * MARGIN
INNER_H = POPUP_H - 2 * MARGIN


def fx(px):
    return px / INNER_W


def fy(px):
    return px / INNER_H


QR_BOX = _s(300)          # px of card set aside for the symbol
CACHE_DIR = os.path.expanduser("~/.cache/qtile")

# Black on white, always. See the module docstring.
QR_DARK = "#000000"
QR_LIGHT = "#ffffff"


def _load_colors():
    base = _load_wal_colors()
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)
    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)
    return base


COLORS = _load_colors()


# =============================================================================
# HELPERS
# =============================================================================
def esc_markup(text):
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def esc_wifi(value):
    r"""Escape a field for the WIFI: URI.

    `\ ; , : "` are the separators of the format itself, so an SSID or PSK
    containing any of them silently truncates the payload -- the phone joins
    the wrong network, or asks for a password that looks right.
    """
    out = []
    for ch in str(value):
        if ch in "\\;,:\"":
            out.append("\\")
        out.append(ch)
    return "".join(out)


def run(cmd, timeout=15):
    try:
        proc = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=timeout,
        )
        return proc.returncode == 0, (proc.stdout or "").strip()
    except FileNotFoundError:
        return False, f"{cmd[0]} not found"
    except Exception as e:
        logger.warning("WifiQR: %s failed: %s", cmd[0], e)
        return False, str(e)


def on_ui(session, fn):
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION:
            return
        try:
            fn()
        except Exception as e:
            logger.exception("WifiQR UI callback failed: %s", e)

    _QTILE.call_soon_threadsafe(_guarded)


# =============================================================================
# NETWORK DETAILS
# =============================================================================
def active_wifi_profile():
    """Name of the profile on the connected wifi device, or None."""
    ok, out = run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"])
    if not ok:
        return None
    for line in out.splitlines():
        # DEVICE:TYPE:STATE:CONNECTION -- the connection name may contain
        # colons, so split off only the first three fields.
        parts = line.split(":", 3)
        if len(parts) == 4 and parts[1] == "wifi" and parts[2] == "connected":
            return parts[3]
    return None


def _field(profile, key, secrets=False):
    cmd = ["nmcli"]
    if secrets:
        cmd.append("--show-secrets")
    cmd += ["-g", key, "connection", "show", "id", profile]
    ok, out = run(cmd)
    return out.strip() if ok else ""


def gather(profile=None):
    """(payload, ssid, password, security, error) for a saved profile.

    `profile` names a stored connection to share -- the WiFi popup passes the
    row you have selected, so you can hand over a network you are not
    currently on. Falls back to whatever the wifi device is connected to.
    """
    profile = profile or active_wifi_profile()
    if not profile:
        return None, None, None, None, "Not connected to WiFi"

    ssid = _field(profile, "802-11-wireless.ssid") or profile
    key_mgmt = _field(profile, "802-11-wireless-security.key-mgmt")
    hidden = _field(profile, "802-11-wireless.hidden").lower() in ("yes", "true")

    if key_mgmt in ("wpa-eap", "wpa-eap-suite-b-192"):
        # Enterprise networks need a certificate/identity, none of which fits
        # in the WIFI: URI. Better to say so than to emit a code that fails.
        return None, ssid, None, "802.1X", "Enterprise networks can't be shared by QR"

    if not key_mgmt:
        auth, password = "nopass", ""
    else:
        auth = "WPA"  # WPA/WPA2/WPA3-SAE all scan as WPA on phones
        password = _field(profile, "802-11-wireless-security.psk", secrets=True)
        if not password:
            return (None, ssid, None, key_mgmt,
                    "No stored password for this network")

    payload = f"WIFI:T:{auth};S:{esc_wifi(ssid)};P:{esc_wifi(password)};"
    if hidden:
        payload += "H:true;"
    payload += ";"

    return payload, ssid, password, (key_mgmt or "open"), None


# =============================================================================
# QR GENERATION
# =============================================================================
def _png_width(path):
    """Width from a PNG header: bytes 16..20, big-endian."""
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return 0
    return int.from_bytes(head[16:20], "big")


def render_qr(payload):
    """Write a crisp PNG for `payload`; returns its path or None."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    probe = os.path.join(CACHE_DIR, "wifi-qr-probe.png")
    final = os.path.join(CACHE_DIR, "wifi-qr.png")

    # -8 pins 8-bit (byte) mode. The payload is UTF-8 and there is no ECI
    # header to declare that, so a decoder is free to guess the charset --
    # zbar guesses Shift-JIS and hands back katakana mojibake for a Turkish
    # SSID. Phones assume UTF-8 and read it correctly (verified: the stored
    # bytes are byte-identical to the UTF-8 payload), but pinning the mode
    # keeps qrencode from ever segmenting the data some other way.
    if not payload:
        return None

    # Pass 1: one pixel per module, no quiet zone -> width == module count.
    ok, out = run(["qrencode", "-o", probe, "-s", "1", "-m", "0",
                   "-8", "-l", "M", "--", payload])
    if not ok:
        logger.warning("WifiQR: qrencode probe failed: %s", out)
        return None

    modules = _png_width(probe) or 33
    margin = 2
    # Integer scale that fits inside the control. PopupImage centres but also
    # *scales* to fit, so anything larger than the control gets resampled.
    scale = max(1, QR_BOX // (modules + 2 * margin))

    ok, out = run(["qrencode", "-o", final, "-s", str(scale), "-m", str(margin),
                   "-8", "-l", "M", "--foreground", QR_DARK.lstrip("#"),
                   "--background", QR_LIGHT.lstrip("#"), "--", payload])
    if not ok:
        logger.warning("WifiQR: qrencode failed: %s", out)
        return None
    return final


# =============================================================================
# ESCAPE HANDLING
# =============================================================================
def _grab_escape(qtile):
    """Grab a chord whose only binding is Escape, so Escape closes this.

    This popup is opened by a bar click, not a chord, so nothing routes keys
    to it. The obvious alternative -- letting qtile_extras take keyboard
    focus (which it does as soon as any control is focusable) -- would pull
    focus off whatever you were typing in and kill the popup on the next
    focus change, through a code path that calls layout.kill() directly and
    strands this module's state.

    Grabbing a chord instead touches nothing but the Escape key: every other
    key still reaches the focused window, and the chord chip shows what is
    going on. qtile's KeyChord appends its own bare Escape after the
    submappings and later grabs win, so the actual close runs from
    cleanup_on_leave() in config.py via the leave_chord hook -- the same
    route Wifi-Mode uses.
    """
    global _CHORD_HELD
    try:
        qtile.grab_chord(
            KeyChord([], "Escape", [Key([], "Escape")], mode=True, name=CHORD_NAME)
        )
        _CHORD_HELD = True
    except Exception as e:
        # Not fatal: the popup is still dismissable by clicking it or the
        # chip, so a failure here costs the Escape shortcut and nothing else.
        logger.warning("WifiQR: could not grab Escape chord: %s", e)
        _CHORD_HELD = False


def _release_escape():
    """Drop our chord, unless qtile already popped it (the Escape path)."""
    global _CHORD_HELD
    if not _CHORD_HELD:
        return
    _CHORD_HELD = False
    try:
        _QTILE.ungrab_chord()
    except Exception:
        pass


def on_chord_left():
    """leave_chord landed on our chord: qtile has already ungrabbed it."""
    global _CHORD_HELD
    _CHORD_HELD = False
    close()


# =============================================================================
# POPUP
# =============================================================================
def _build(qtile, qr_path, ssid, password, security, error, grab=True):
    global _LAYOUT

    # close_on_click would call layout.kill() itself, behind this module's
    # back: _LAYOUT would still point at a dead layout and the Escape chord
    # would stay grabbed with nothing to release it. Every control gets an
    # explicit click handler instead, so all three dismissal routes (click,
    # Escape, the chip) land in close().
    #
    # can_focus=False matters as much as the callback: "auto" turns any
    # control with a Button1 handler into a focusable one, which flips the
    # layout into keyboard-navigation mode and makes it steal focus on show.
    dismiss = {"Button1": lambda: close()}

    controls = [
        PopupText(
            text=(
                f'<span size="large" weight="bold" foreground="{COLORS["fg"]}">'
                f"\uf029  Share Wi-Fi</span>"
            ),
            markup=True,
            font=FONT,
            fontsize=HEAD_SIZE,
            pos_x=fx(20),
            pos_y=fy(16),
            width=fx(330),
            height=fy(32),
            h_align="center",
            v_align="middle",
            mouse_callbacks=dismiss,
            can_focus=False,
        ),
        PopupText(
            text=(
                f'<span foreground="{COLORS["green"]}" weight="bold">'
                f"{esc_markup(ssid or '—')}</span>"
            ),
            markup=True,
            font=FONT,
            fontsize=BODY_SIZE,
            pos_x=fx(20),
            pos_y=fy(50),
            width=fx(330),
            height=fy(26),
            h_align="center",
            v_align="middle",
            mouse_callbacks=dismiss,
            can_focus=False,
        ),
    ]

    if error:
        controls.append(
            PopupText(
                text=(
                    f'<span foreground="{COLORS["red"]}">'
                    f"{esc_markup(error)}</span>"
                ),
                markup=True,
                font=FONT,
                fontsize=BODY_SIZE,
                pos_x=fx(20),
                pos_y=fy(180),
                width=fx(330),
                height=fy(120),
                h_align="center",
                v_align="middle",
                wrap=True,
                mouse_callbacks=dismiss,
                can_focus=False,
            )
        )
    else:
        # White card behind the symbol: the quiet zone is part of the spec,
        # and a dark desktop bleeding into it costs decoders their margin.
        controls.append(
            PopupImage(
                filename=qr_path,
                background=QR_LIGHT,
                highlight_radius=8,
                pos_x=fx(35),
                pos_y=fy(82),
                width=fx(300),
                height=fy(QR_BOX),
                name="qr",
                mouse_callbacks=dismiss,
                can_focus=False,
            )
        )
        controls.append(
            PopupText(
                text=(
                    f'<span foreground="{COLORS["muted"]}" size="small">password</span>\n'
                    f'<span foreground="{COLORS["fg"]}">'
                    f"{esc_markup(password or '(open network)')}</span>"
                ),
                markup=True,
                font=FONT,
                fontsize=BODY_SIZE,
                background=COLORS["surface"],
                highlight_radius=10,
                pos_x=fx(35),
                pos_y=fy(392),
                width=fx(300),
                height=fy(54),
                h_align="center",
                v_align="middle",
                mouse_callbacks=dismiss,
                can_focus=False,
            )
        )

    controls.append(
        PopupText(
            text=(
                f'<span foreground="{COLORS["muted"]}" size="small">'
                f"scan with a phone  ·  Esc or click to close</span>"  # 301px of the 330px control; longer wording ellipsises
            ),
            markup=True,
            font=FONT,
            fontsize=BODY_SIZE,
            pos_x=fx(20),
            pos_y=fy(454),
            width=fx(330),
            height=fy(24),
            h_align="center",
            v_align="middle",
            mouse_callbacks=dismiss,
            can_focus=False,
        )
    )

    _LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"] + "F2",
        border=COLORS["surface_alt"],
        border_width=2,
        close_on_click=False,  # handled per-control; see `dismiss` above
        controls=controls,
    )
    _LAYOUT.show(centered=True)
    fade_in_popup(_LAYOUT, duration=0.2, steps=14)
    if grab:
        _grab_escape(qtile)


def show(qtile, profile=None, grab=True):
    """Open the QR popup.

    `grab=False` when opening from inside another chord (the WiFi popup):
    that chord already owns Escape, and stacking a second one would leave
    the popup's fate tied to a chord pop this module never sees.
    """
    global _QTILE, _SESSION

    _QTILE = qtile
    if _LAYOUT is not None or _CLOSING:
        return

    COLORS.update(_load_colors())
    _SESSION += 1
    session = _SESSION

    def worker():
        payload, ssid, password, security, error = gather(profile)
        qr_path = None
        if payload:
            qr_path = render_qr(payload)
            if qr_path is None:
                error = "qrencode failed (is it installed?)"

        on_ui(
            session,
            lambda: _build(qtile, qr_path, ssid, password, security, error, grab),
        )

    # nmcli + qrencode off the event loop: four short subprocesses is still
    # four subprocesses, and this runs from a bar click.
    threading.Thread(target=worker, daemon=True).start()


def close(qtile=None):
    global _LAYOUT, _CLOSING, _SESSION

    if _LAYOUT is None or _CLOSING:
        return

    layout = _LAYOUT
    _CLOSING = True
    _SESSION += 1
    _LAYOUT = None
    _release_escape()

    def teardown():
        global _CLOSING
        try:
            # kill(), not hide(): hide() leaves the window and its cairo
            # surface allocated and show() builds a new layout every time.
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
