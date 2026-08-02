"""Role colours for rofi pickers, taken from the active rofi palette.

The translator and dm-spellcheck draw pango-marked-up tables, and pango
markup cannot reference rofi theme variables — every colour has to be a
literal in the row string. They were literals of the doom-one palette,
so switching `themes/current-palette.rasi` (which is what theme-apply
swaps) recoloured the window frame and left the table stubbornly blue
and green.

This reads the palette rofi is actually using and hands back a small set
of *roles* instead of raw names, so callers never have to know whether a
palette calls its red `urgent` or `selectedone`. Every palette in
themes/ defines the same seven keys, which is what makes this safe.

Order of preference:

  1. ~/.config/rofi/themes/current-palette.rasi — the real answer.
  2. ~/.cache/wal/colors.json — the wallpaper palette, for when the rasi
     file is missing but pywal has run.
  3. doom-one, hardcoded, so a picker never comes out unreadable.

`dim`, `muted`, `example` and `syn` are blends rather than palette
entries: a palette has no "comment gray", and picking `background-alt`
for it (the obvious candidate) produces text the same colour as the
background it sits on.
"""

import json
import os
import re

PALETTE_FILE = os.path.expanduser(
    "~/.config/rofi/themes/current-palette.rasi"
)
WAL_FILE = os.path.expanduser("~/.cache/wal/colors.json")

# doom-one, the palette these pickers were written against.
DEFAULTS = {
    "background": "#282c34",
    "background-alt": "#21242b",
    "foreground": "#bbc2cf",
    "selected": "#61afef",
    "selectedone": "#e06c75",
    "urgent": "#e06c75",
    "active": "#98c379",
}

_HEX = re.compile(
    r"^\s*([a-z][a-z0-9-]*)\s*:\s*(#[0-9a-fA-F]{3,8})\s*;", re.MULTILINE
)


def _parse_rasi(path):
    try:
        with open(path, encoding="utf-8") as f:
            return dict(_HEX.findall(f.read()))
    except OSError:
        return {}


def _parse_wal(path):
    """Map pywal's numbered colours onto the palette's named roles."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    colors = data.get("colors", {})
    special = data.get("special", {})
    if not colors:
        return {}
    return {
        "background": special.get("background", DEFAULTS["background"]),
        "background-alt": colors.get("color8", DEFAULTS["background-alt"]),
        "foreground": special.get("foreground", DEFAULTS["foreground"]),
        "selected": colors.get("color4", DEFAULTS["selected"]),
        "selectedone": colors.get("color1", DEFAULTS["selectedone"]),
        "urgent": colors.get("color1", DEFAULTS["urgent"]),
        "active": colors.get("color2", DEFAULTS["active"]),
    }


def _rgb(color):
    color = color.lstrip("#")
    if len(color) == 3:
        color = "".join(c * 2 for c in color)
    color = color[:6]
    try:
        return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return (0, 0, 0)


def mix(a, b, weight):
    """`weight` of a, the rest of b, as #rrggbb."""
    ra, rb = _rgb(a), _rgb(b)
    return "#" + "".join(
        f"{round(x * weight + y * (1 - weight)):02x}"
        for x, y in zip(ra, rb)
    )


def load():
    """Return the role → colour map the pickers use."""
    raw = _parse_rasi(PALETTE_FILE) or _parse_wal(WAL_FILE)
    palette = dict(DEFAULTS)
    palette.update({k: v for k, v in raw.items() if k in DEFAULTS})

    bg = palette["background"]
    fg = palette["foreground"]
    return {
        "text": fg,
        "head": palette["selected"],
        "good": palette["active"],
        "bad": palette["urgent"],
        "accent": palette["selectedone"],
        # Blends: legible against the background, clearly secondary to
        # the content they annotate.
        "muted": mix(fg, bg, 0.72),
        "dim": mix(fg, bg, 0.5),
        "example": mix(palette["selected"], fg, 0.55),
        "syn": mix(palette["active"], fg, 0.55),
    }
