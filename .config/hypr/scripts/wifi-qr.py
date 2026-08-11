#!/usr/bin/env python3
"""Share the current Wi-Fi network as a QR code — the port of qtile's WifiQR.

Reads the active connection's SSID and stored PSK out of NetworkManager,
encodes them in the `WIFI:` URI that Android and iOS cameras understand, and
renders a PNG. Point a phone at it and it joins, instead of reading a
20-character PSK off a screen.

Prints ONE line of JSON: `{"ok", "ssid", "password", "security", "path",
"size", "status"}`. The consumer is qml/wifi/WifiQrLayer.qml, which is a QML
Process reading stdout — anything printed on stderr with a non-zero exit
would be invisible to it.

`nmcli --show-secrets` reads the PSK as the logged-in user for system
connections with `psk-flags=0`, which is the default for anything saved
normally. No sudo and no polkit agent.

THREE THINGS HERE ARE DELIBERATE AND EASY TO "FIX" INTO BREAKAGE, all three
inherited from the qtile implementation:

* **The code is always BLACK ON WHITE**, whatever the desktop theme is, and
  it is drawn on its own white card. Inverted (light-on-dark) codes are out
  of spec and plenty of phone cameras refuse them. A QR you have to explain
  is worse than no QR.
* **qrencode runs TWICE** — once at one pixel per module to learn how big the
  symbol is, then again at an integer scale that fills the box. Letting the
  viewer scale the image instead resamples the modules at a fractional ratio
  and blurs exactly the edges the decoder needs.
* **`-8` pins byte mode.** The payload is UTF-8 and a QR carries no ECI
  header to say so, so a decoder is free to guess: zbar guesses Shift-JIS and
  hands back katakana for a Turkish SSID. Phones assume UTF-8 and read it
  correctly, and pinning the mode stops qrencode segmenting the data some
  other way.
"""

import json
import os
import shutil
import subprocess
import sys

CACHE_DIR = os.path.expanduser("~/.cache/hypr")
# Default box, in pixels, for the symbol including its quiet zone. The QML
# layer passes its own, derived from the island's scale factor.
DEFAULT_BOX = 240
QUIET_MARGIN = 2          # modules of quiet zone; the spec's minimum is 4,
                          # and 2 plus the white card around it reads the same


def run(args, timeout=15):
    try:
        proc = subprocess.run(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=timeout,
        )
    except FileNotFoundError:
        return False, f"{args[0]} not found"
    except Exception as error:
        return False, str(error)
    return proc.returncode == 0, (proc.stdout or "").strip()


def emit(**payload):
    payload.setdefault("ok", False)
    print(json.dumps(payload))
    return 0


def escape_field(value):
    r"""Escape a field for the WIFI: URI.

    `\ ; , : "` are the separators of the format itself, so an SSID or PSK
    containing any of them silently truncates the payload — the phone joins
    the wrong network, or asks for a password that looks right and is not.
    """
    out = []
    for char in str(value):
        if char in "\\;,:\"":
            out.append("\\")
        out.append(char)
    return "".join(out)


def active_profile():
    """The connection profile on the connected wifi device, or ''."""
    ok, out = run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION",
                   "dev", "status"])
    if not ok:
        return ""
    for line in out.splitlines():
        # DEVICE:TYPE:STATE:CONNECTION — the connection NAME may itself
        # contain colons, so only the first three fields are split off.
        parts = line.split(":", 3)
        if len(parts) == 4 and parts[1] == "wifi" and parts[2] == "connected":
            return parts[3]
    return ""


def field(profile, key, secrets=False):
    args = ["nmcli"]
    if secrets:
        args.append("--show-secrets")
    args += ["-g", key, "connection", "show", "id", profile]
    ok, out = run(args)
    return out.strip() if ok else ""


def gather(profile):
    """(payload, ssid, password, security, error) for a saved profile."""
    profile = profile or active_profile()
    if not profile:
        return None, "", "", "", "not connected to Wi-Fi"

    # A profile that does not exist answers "" to every -g query, and every
    # one of those empty answers is indistinguishable from a legitimately
    # empty field: no key-mgmt reads as an OPEN network, so a typo'd name
    # would produce a perfectly valid QR for an open network that does not
    # exist. Check the name resolves before believing anything else it says.
    if field(profile, "connection.id") == "":
        return None, profile, "", "", f"no saved connection named {profile}"

    ssid = field(profile, "802-11-wireless.ssid") or profile
    key_mgmt = field(profile, "802-11-wireless-security.key-mgmt")
    hidden = field(profile, "802-11-wireless.hidden").lower() in ("yes", "true")

    if key_mgmt in ("wpa-eap", "wpa-eap-suite-b-192"):
        # Enterprise needs a certificate and an identity, none of which fits
        # in the WIFI: URI. Better to say so than to emit a code that fails
        # on the phone with no explanation.
        return None, ssid, "", "802.1X", "enterprise networks can't be shared by QR"

    if not key_mgmt:
        auth, password = "nopass", ""
    else:
        auth = "WPA"        # WPA/WPA2/WPA3-SAE all scan as WPA on phones
        password = field(profile, "802-11-wireless-security.psk", secrets=True)
        if not password:
            return None, ssid, "", key_mgmt, "no stored password for this network"

    payload = f"WIFI:T:{auth};S:{escape_field(ssid)};P:{escape_field(password)};"
    if hidden:
        payload += "H:true;"
    payload += ";"
    return payload, ssid, password, (key_mgmt or "open"), ""


def png_width(path):
    """Width from a PNG header: bytes 16..20, big-endian."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
    except OSError:
        return 0
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
        return 0
    return int.from_bytes(head[16:20], "big")


def render(payload, box):
    """Write a crisp PNG for `payload`; returns (path, pixel size) or (None, 0)."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    probe = os.path.join(CACHE_DIR, "wifi-qr-probe.png")
    final = os.path.join(CACHE_DIR, "wifi-qr.png")

    # Pass 1: one pixel per module, no quiet zone → width == module count.
    ok, out = run(["qrencode", "-o", probe, "-s", "1", "-m", "0",
                   "-8", "-l", "M", "--", payload])
    if not ok:
        return None, 0, out

    modules = png_width(probe) or 33
    total = modules + 2 * QUIET_MARGIN
    # Integer scale only. A fractional one is what blurs the modules.
    scale = max(1, box // total)

    ok, out = run(["qrencode", "-o", final, "-s", str(scale),
                   "-m", str(QUIET_MARGIN), "-8", "-l", "M",
                   "--foreground", "000000", "--background", "ffffff",
                   "--", payload])
    if not ok:
        return None, 0, out
    return final, total * scale, ""


def main(argv):
    profile = ""
    box = DEFAULT_BOX
    args = argv[1:]
    while args:
        if args[0] == "--box" and len(args) > 1:
            try:
                box = max(60, int(args[1]))
            except ValueError:
                pass
            args = args[2:]
            continue
        profile = args[0]
        args = args[1:]

    if shutil.which("nmcli") is None:
        return emit(status="NetworkManager (nmcli) is not installed")
    if shutil.which("qrencode") is None:
        # Declared in .config/arch-config/modules/wm.yaml, so this only
        # happens on a machine where the module was not applied.
        return emit(status="qrencode is not installed")

    payload, ssid, password, security, error = gather(profile)
    if payload is None:
        return emit(ssid=ssid, security=security, status=error)

    path, size, message = render(payload, box)
    if path is None:
        return emit(ssid=ssid, security=security,
                    status="qrencode failed: " + (message or "no output"))

    return emit(ok=True, ssid=ssid, password=password, security=security,
                path=path, size=size, status="scan with a phone")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
