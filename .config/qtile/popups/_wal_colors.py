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


def load_colors():
    try:
        with open(os.path.expanduser("~/.cache/wal/colors.json")) as f:
            w = json.load(f)
        c = w["colors"]
        s = w["special"]
        return {
            "bg": s["background"],
            "fg": s["foreground"],
            "muted": c["color8"],
            "green": c["color10"],   # dominant (main accent)
            "blue": c["color12"],    # cool-fill
            "purple": c["color13"],  # complement
            "red": c["color9"],      # urgent
        }
    except Exception:
        return dict(_DOOMONE)
