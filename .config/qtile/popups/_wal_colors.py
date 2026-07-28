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


def current_theme_mode():
    """Active theme mode as written by theme-apply ("wal" or a preset name).

    Returns "" when the state file is unreadable, so callers gating on
    == "wal" fail closed (leave the current theme alone) rather than
    silently reapplying wal over a preset.
    """
    try:
        with open(os.path.expanduser("~/.cache/qtile/theme_mode")) as f:
            return f.read().strip()
    except Exception:
        return ""


def load_colors():
    for source in (_from_preset_json, _from_wal_json):
        try:
            return source()
        except Exception:
            continue
    return dict(_DOOMONE)


def _ease_out_cubic(t):
    """t in 0..1 -> eased 0..1. Fast start, soft landing.

    A linear opacity ramp reads as a mechanical flicker at these
    durations because perceived brightness is non-linear; easing the
    tail is what makes the same step count look like a real fade.
    """
    return 1 - (1 - t) ** 3


def _ease_in_cubic(t):
    """Mirror of _ease_out_cubic, for fades that end at transparent."""
    return t ** 3


def fade_in_popup(layout, duration=0.16, steps=10):
    """Fade a just-`.show()`-n PopupRelativeLayout in from transparent to
    its configured opacity via _NET_WM_WINDOW_OPACITY (picom renders each
    change live). Deliberately opacity-only, never touches position --
    unlike a slide animation this has no interaction with qtile's
    floating-window placement logic at all, so there's no equivalent of
    the qdrop center-flash bug class to worry about here.
    """
    try:
        win = layout.popup.win
        qtile = layout.qtile
        end_opacity = getattr(layout, "opacity", 1) or 1
    except Exception:
        return
    win.opacity = 0.0
    step_time = duration / steps

    def _step(i=1):
        try:
            win.opacity = min(end_opacity, end_opacity * _ease_out_cubic(i / steps))
        except Exception:
            return
        if i < steps:
            qtile.call_later(step_time, lambda: _step(i + 1))

    qtile.call_later(step_time, lambda: _step(1))


def fade_out_popup(layout, on_done, duration=0.14, steps=9):
    """Fade a PopupRelativeLayout out, then invoke on_done() to actually
    tear it down (`.hide()` / `.kill()`).

    Same opacity-only contract as fade_in_popup -- never touches
    position or size, so it cannot reintroduce the qdrop center-flash
    bug class (qtile re-centering a floating window whose geometry
    changes while mapped).

    on_done() is called exactly once, and is called immediately if the
    window is already gone or anything raises -- a popup must never be
    left stranded on screen just because its animation failed.
    """
    try:
        win = layout.popup.win
        qtile = layout.qtile
        start_opacity = getattr(layout, "opacity", 1) or 1
    except Exception:
        on_done()
        return

    state = {"done": False}

    def _finish():
        if state["done"]:
            return
        state["done"] = True
        try:
            on_done()
        except Exception:
            pass

    step_time = duration / steps

    def _step(i=1):
        try:
            win.opacity = max(0.0, start_opacity * (1 - _ease_in_cubic(i / steps)))
        except Exception:
            _finish()
            return
        if i < steps:
            qtile.call_later(step_time, lambda: _step(i + 1))
        else:
            _finish()

    qtile.call_later(step_time, lambda: _step(1))
