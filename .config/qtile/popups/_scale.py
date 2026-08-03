"""HiDPI scaling shared by every popup.

Everything in the qtile config multiplies pixel dimensions through
UI_SCALE -- the bar, the fonts, the margins -- and the popups did not.
On a 4K panel the bar and its fonts grew while every popup stayed at the
1366x768 sizes it was designed against, so the whole set rendered
correctly and postage-stamp small, with nothing in any log to say why.

What is safe to scale, and what is not
--------------------------------------
Scale anything measured in PIXELS: popup width and height, font sizes,
margins, corner radii, gaps, and any px box set aside for an image.

Do NOT scale:

* ratios (``GRID_TOP = 0.155``) -- they are already resolution-independent
* character counts (``MAX_NAME_LEN``, ``ROWS_VISIBLE``) -- a name is the
  same number of characters at any DPI, and the box grows to fit it
* durations (``SCAN_SECONDS``, ``T_ACTION``) -- seconds are not pixels
* percentages (``VOLUME_MAX``) -- likewise

Because a popup's box and its font size scale by the same factor, the
layout stays self-similar: the same content occupies the same fraction of
the same popup, just larger. That is what makes this a multiplication
rather than a redesign. Measured on the cheatsheets, which are the most
layout-sensitive of them: at 2.0 they come out at the same 3.6 / 2.0 / 1.4
screenfuls as at 1.0, with pango measuring the real glyph extents at both.

This lives in its own module rather than in config.py because config.py
imports the popups -- importing back would be circular.
"""

import os


def _load_ui_scale():
    """The factor `ui-scale` (AtiScriptsV1) computed for this display.

    A missing file means 1.0, which is exactly the reference machine's
    behaviour, so the popups still render correctly if ui-scale has never
    been run.
    """
    # QTILE_UI_SCALE_FORCE exists for the cheatsheet selftest, which
    # measures against a FIXED 1366x768 reference screen. On a scaled
    # display the popup would grow while that reference did not, and every
    # sheet would be reported as overflowing a screen it actually fits.
    forced = os.environ.get("QTILE_UI_SCALE_FORCE")
    if forced:
        try:
            return float(forced)
        except ValueError:
            pass
    try:
        with open(os.path.expanduser("~/.cache/qtile/ui_scale")) as f:
            v = float(f.read().strip())
        # Refuse absurd values rather than rendering a popup too small to
        # read the menu that would fix it.
        return v if 0.5 <= v <= 4.0 else 1.0
    except (OSError, ValueError):
        return 1.0


UI_SCALE = _load_ui_scale()


def s(px):
    """Scale a pixel dimension. Floor of 1 so nothing rounds away to zero."""
    return max(1, int(round(px * UI_SCALE)))
