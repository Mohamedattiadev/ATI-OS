# scripts/mode_overlay.py
"""The bar's mode chip, mirrored over fullscreen windows.

A focused fullscreen window is stacked ABOVE the bar -- that is the
`full and focus` layer in X11's recommended stacking order, one step above
the `dock` layer the bar lives in (backend/x11/window.py,
get_layering_information). So the whole bar goes out of sight for exactly as
long as the window stays fullscreen, and every mode in this config announces
itself through two widgets that live on that bar: the Chord chip and the
hintium chip. Entering Rofi-Mode from a fullscreen video left nothing on
screen to say a mode was open at all, let alone which keys it had bound.

This puts the same label back as a floating chip at the top centre, for as
long as BOTH conditions hold: a mode is open, and a focused fullscreen window
is covering the bar. Drop either one and the chip goes away -- when the
window leaves fullscreen the bar comes back with the real chip already in it,
and showing both would just be the same label twice.

The chip's text and colours are not decided here. config.py registers
"providers" (see set_providers) so that the overlay renders whatever the bar
would have rendered, from the same label table and the same per-mode colour
map, instead of keeping a second copy of either.

Why the popup is destroyed and rebuilt on every show instead of being kept
around hidden: stacking. The popup is an Internal window, and qtile's
change_layer() only restacks windows that belong to a group -- it walks
`group.windows` plus the Static windows, and an Internal is in neither -- so
when a window goes fullscreen and finds nothing above it, it takes the
`sibling = stack[-1], above=True` branch and lands on top of the server's
entire stack, chip included. A window that already existed therefore ends up
UNDER the fullscreen window. A window created after it is on top of the stack
by definition, which is where this chip has to be, so creation order is what
does the work here rather than any raise call.
"""

from libqtile import qtile
from libqtile.log_utils import logger
from qtile_extras.popup import PopupRelativeLayout, PopupText

from popups._scale import s as _s

FONT = "JetBrainsMono Nerd Font"
FONT_SIZE = _s(13)
PAD_X = _s(18)  # breathing room either side of the label, inside the chip
PAD_Y = _s(7)
TOP_MARGIN = _s(10)  # gap between the top of the screen and the chip
RADIUS = _s(10)

# How often the chip re-checks whether it should be up. Both things it
# watches are invisible to hooks: hintium's modes are not qtile chords (they
# are a file the daemon writes, see hintium_mode_text in config.py) and qtile
# fires no hook when a window enters or leaves fullscreen. config.py calls
# refresh() directly from the chord hooks, so chord modes do not wait for
# this -- it is the fallback, not the main path.
POLL = 0.25

# Fallback if pango cannot be reached; JetBrainsMono's real advance is 0.6 em,
# rounded up here so a mis-measure errs towards a chip that is too wide rather
# than one that clips its own label.
FALLBACK_CHAR_RATIO = 0.62

_EXTENTS: dict = {}


def _text_extents(text):
    """(width, height) in pixels that qtile will draw `text` at FONT_SIZE."""
    key = (text, FONT_SIZE)
    cached = _EXTENTS.get(key)
    if cached is not None:
        return cached

    try:
        import gi

        gi.require_version("Pango", "1.0")
        gi.require_version("PangoCairo", "1.0")
        from gi.repository import Pango, PangoCairo
        import cairo

        ctx = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))
        # set_absolute_size, NOT the "Family 13" description string: qtile's
        # drawer sizes text in DEVICE PIXELS (backend/base/drawer.py) while a
        # description string is in POINTS, 4/3 larger at 96dpi. Measuring in
        # points builds every chip ~30% wider than the text it holds. Same
        # trap, documented at length, in popups/_cheatsheet_grid.py.
        desc = Pango.FontDescription(FONT)
        desc.set_absolute_size(FONT_SIZE * Pango.SCALE)
        layout = PangoCairo.create_layout(ctx)
        layout.set_font_description(desc)
        layout.set_text(text, -1)
        size = tuple(layout.get_pixel_size())
    except Exception:
        logger.exception("mode_overlay: pango unavailable, estimating chip width")
        size = (
            int(len(text) * FONT_SIZE * FALLBACK_CHAR_RATIO),
            int(FONT_SIZE * 1.4),
        )

    # The label set is small and fixed, but a mode could in principle show
    # changing text; cap the cache rather than let it grow for the life of the
    # session.
    if len(_EXTENTS) > 64:
        _EXTENTS.clear()
    _EXTENTS[key] = size
    return size


class ModeOverlay:
    """Owns at most one chip window, and the timer that decides if it is up."""

    def __init__(self):
        # Each provider is a zero-argument callable returning either None (no
        # mode of its kind is open) or (text, background, foreground).
        self.providers = []
        self._layout = None
        self._shown = None  # the (text, bg, fg) currently on screen
        # Bumped by start()/stop(). A tick carries the generation it was
        # scheduled under and returns without rescheduling once it is stale,
        # so re-running config.py (reload_config keeps this module loaded)
        # replaces the timer loop instead of stacking a second one on it.
        self._generation = 0

    def set_providers(self, providers):
        self.providers = list(providers)

    # ------------------------------------------------------------------
    # timer
    # ------------------------------------------------------------------
    def start(self):
        self._generation += 1
        self._hide()
        self._schedule(self._generation)

    def stop(self):
        self._generation += 1
        self._hide()

    def _schedule(self, generation):
        try:
            qtile.call_later(POLL, self._tick, generation)
        except Exception:
            logger.exception("mode_overlay: could not schedule the next check")

    def _tick(self, generation):
        if generation != self._generation:
            return
        try:
            self.refresh()
        except Exception:
            logger.exception("mode_overlay: refresh failed")
        self._schedule(generation)

    # ------------------------------------------------------------------
    # state
    # ------------------------------------------------------------------
    def _bar_is_covered(self):
        """True when a focused fullscreen window is hiding the bar.

        Focus is part of the test, not an extra: the fullscreen layer in
        get_layering_information() is `full and focus`. An unfocused
        fullscreen window sits in the ordinary layer with the bar stacked
        above it, so the real chip is still visible and a second copy would
        be wrong.
        """
        try:
            window = qtile.current_window
        except Exception:
            return False
        return window is not None and bool(getattr(window, "fullscreen", False))

    def _wanted(self):
        if not self._bar_is_covered():
            return None
        for provider in self.providers:
            try:
                entry = provider()
            except Exception:
                logger.exception("mode_overlay: provider failed")
                continue
            if not entry:
                continue
            text, background, foreground = entry
            text = (text or "").strip()
            if text:
                return (text, background, foreground)
        return None

    def refresh(self):
        """Bring the chip in line with the current mode/fullscreen state."""
        wanted = self._wanted()
        if wanted == self._shown:
            return
        self._hide()
        if wanted is not None:
            self._show(*wanted)

    # ------------------------------------------------------------------
    # the window
    # ------------------------------------------------------------------
    def _show(self, text, background, foreground):
        width, height = _text_extents(text)
        # The rounded chip is the CONTROL's background, not the popup's: a
        # popup window is a plain rectangle, but _PopupWidget.clear() fills
        # `rectangle()`, which is a rounded path of highlight_radius. Leaving
        # the popup itself fully transparent means the corners outside that
        # path stay transparent and the result is a real pill rather than a
        # pill drawn on a visible square.
        control = PopupText(
            text,
            pos_x=0,
            pos_y=0,
            width=1,
            height=1,
            font=FONT,
            fontsize=FONT_SIZE,
            foreground=foreground,
            background=background,
            highlight_radius=RADIUS,
            h_align="center",
            v_align="middle",
            can_focus=False,
        )
        try:
            self._layout = PopupRelativeLayout(
                qtile,
                width=width + 2 * PAD_X,
                height=height + 2 * PAD_Y,
                margin=0,
                border_width=0,
                background="#00000000",
                close_on_click=False,
                controls=[control],
            )
            # relative_to=2 is the top-centre of the screen, so the chip lands
            # where the bar's own chips would be if the bar were visible.
            self._layout.show(x=0, y=TOP_MARGIN, relative_to=2)
        except Exception:
            logger.exception("mode_overlay: could not show the chip")
            self._layout = None
            return
        self._shown = (text, background, foreground)

    def _hide(self):
        if self._layout is not None:
            try:
                self._layout.kill()
            except Exception:
                logger.exception("mode_overlay: could not close the chip")
            self._layout = None
        self._shown = None


mode_overlay = ModeOverlay()
