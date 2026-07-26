"""Shared wal-aware colors for cheatsheet popups.

load_colors() reads ~/.cache/wal/colors.json (written per-wallpaper by
theme-apply) and returns a dict matching the doom-one keys used by all
three cheatsheet popups. Falls back to doom-one on any error.

Popups call load_colors() inside their toggle function so re-opening
the popup after a wallpaper switch picks up the new palette without a
qtile restart.
"""
import json
import os

_DOOMONE = {
    "bg": "#1c1f24",
    "fg": "#bbc2cf",
    "muted": "#5b6268",
    "green": "#98be65",
    "blue": "#51afef",
    "purple": "#c678dd",
    "red": "#ff6c6b",
}


def _mix(hex_a, hex_b, t):
    """Linear blend hex_a -> hex_b, t=0..1. Used to derive mid-tone gray."""
    a = [int(hex_a[i:i+2], 16) for i in (1, 3, 5)]
    b = [int(hex_b[i:i+2], 16) for i in (1, 3, 5)]
    m = [int(a[i] + (b[i] - a[i]) * t) for i in range(3)]
    return "#{:02x}{:02x}{:02x}".format(*m)


def _from_preset_json():
    """Preferred source: ~/.cache/qtile/current_palette.json dumped by
    theme-apply on every preset AND wal apply. Guarantees the popup
    matches the currently-active mode instead of leaking a stale wal
    palette from the last wallpaper switch."""
    with open(os.path.expanduser("~/.cache/qtile/current_palette.json")) as f:
        d = json.load(f)
    bg, fg = d["bg"], d["fg"]
    muted = _mix(bg, fg, 0.40)
    return {
        "bg": bg,
        "fg": fg,
        "muted": muted,
        "green": d["green"],
        "blue": d["blue"],
        "purple": d["purple"],
        "red": d["red"],
    }


def _from_wal_json():
    with open(os.path.expanduser("~/.cache/wal/colors.json")) as f:
        w = json.load(f)
    c = w["colors"]
    s = w["special"]
    bg, fg = s["background"], s["foreground"]
    muted = _mix(bg, fg, 0.40)
    return {
        "bg": bg,
        "fg": fg,
        "muted": muted,
        "green": c["color10"],
        "blue": c["color12"],
        "purple": c["color13"],
        "red": c["color9"],
    }


def load_colors():
    for source in (_from_preset_json, _from_wal_json):
        try:
            return source()
        except Exception:
            continue
    return dict(_DOOMONE)
