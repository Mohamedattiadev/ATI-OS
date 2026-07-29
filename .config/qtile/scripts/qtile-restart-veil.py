#!/usr/bin/env python3
"""Restart veil — masks qtile's boot scan during Super+Shift+R.

Why a separate process: measured in an isolated Xephyr sandbox, qtile's
boot scan maps EVERY window from EVERY group at once and leaves them
piled for ~2.2s, then hides the foreign ones ~0.1s BEFORE the `startup`
hook fires. No config-level code is alive while that frame is on screen,
so only something that outlives the execv can cover it.

Visual: the veil fades in over a frosted blur of the desktop as it was a
moment ago, with a card carrying each window's own icon. The cards fly to
a neat row in the middle and wait there through the reload, then fly back
out and the veil fades away onto the restored desktop. It reads as the
windows minimising and coming back — not as a black screen.

Safety (deliberately unlike the earlier feh --fullscreen attempt, which
behaved as an exclusive fullscreen app and needed a manual Esc):
  * override-redirect  -> the WM never manages it and it can never take
                          focus or participate in layout
  * empty input shape  -> every click and keystroke passes through; it is
                          incapable of blocking input even if it wedges
  * no grabs           -> never calls Gdk.Seat.grab / XGrabKeyboard
  * hard watchdog      -> self-destructs after --max-seconds regardless
  * plain kill works   -> no cleanup handshake needed to dispose of it
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import time

import gi

from gi.repository import GLib as _GLib_early  # noqa: E402

# Must be set before Gtk initialises; becomes WM_CLASS.
VEIL_CLASS = "qtile-restart-veil"
_GLib_early.set_prgname(VEIL_CLASS)

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango, PangoCairo  # noqa: E402

import cairo  # noqa: E402

QTILE_CONF_DIR = os.path.expanduser("~/.config/qtile")
ICON_PX = 48

# The bar is Ubuntu Mono / JetBrainsMono Nerd Font throughout. The veil
# used to ask for Inter, which is why it read as a web loading screen
# dropped onto a tiling WM rather than as part of the desktop.
FONT_MONO = "Ubuntu Mono, JetBrainsMono Nerd Font, DejaVu Sans Mono, monospace"

# Keybinding hints. Held back for a moment so a fast restart never
# flashes one, then swapped slowly enough to actually be read.
TIP_DELAY = 0.9
TIP_PERIOD = 2.6
TIP_FADE = 0.35


def load_icon(wm_class, name=""):
    """Best-effort app icon from the current icon theme.

    Blank cards read as unfinished, and they also make it impossible to
    tell which window is which. Falls back to a letter badge (drawn by
    the caller) when nothing resolves.
    """
    if not wm_class:
        return None
    theme = Gtk.IconTheme.get_default()
    base = wm_class.strip()
    cands = [
        base, base.lower(),
        base.split(".")[-1], base.split(".")[-1].lower(),
        base.replace(" ", "-").lower(),
    ]
    seen = set()
    for c in cands:
        if not c or c in seen:
            continue
        seen.add(c)
        try:
            info = theme.lookup_icon(c, ICON_PX, 0)
            if info is not None:
                pb = info.load_icon()
                if pb is not None:
                    return pb
        except Exception:
            continue
    return None


# ---------------------------------------------------------------- easing

def ease_in_out(t: float) -> float:
    """Symmetric cubic — calm, no overshoot, reads as deliberate."""
    t = max(0.0, min(1.0, t))
    return 4 * t * t * t if t < 0.5 else 1 - pow(-2 * t + 2, 3) / 2


def ease_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - pow(1 - t, 3)


def ease_out_expo(t: float) -> float:
    """Exponential settle: most of the distance is covered in the first
    third, then it eases in to rest.

    Used for the veil's own opacity at both ends, where cubic was doing
    the wrong thing in each direction. Coming in, cubic ramps opacity
    roughly linearly at the start, so the desktop underneath stays
    readable for the first ~80ms of a 160ms fade -- exactly the frames
    the veil exists to hide. Going out, the old symmetric cubic held near
    full opacity through the first half, so the desktop was already
    restored and the user was still looking at a scrim.

    Expo fixes both: opaque almost immediately on the way in, clearing
    immediately on the way out, with the slow part of the curve spent
    near the value that is not covering anything up. Same durations, so
    nothing here changes how long a restart takes -- only how much of it
    is spent looking at a half-transparent overlay.
    """
    t = max(0.0, min(1.0, t))
    return 1.0 if t >= 1.0 else 1 - pow(2, -10 * t)


def hex_rgb(s, fallback=(0.11, 0.11, 0.16)):
    try:
        s = s.lstrip("#")
        return tuple(int(s[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    except Exception:
        return fallback


def load_theme():
    """Resolve the palette exactly the way qtile does.

    Earlier this read ~/.cache/wal/colors.json directly, which only
    reflects reality in `wal` mode -- switching to a preset (dracula,
    gruvbox, ...) via theme-apply left the veil on stale wal colours.
    colors.active_palette() reads ~/.cache/qtile/theme_mode and returns
    the live palette for every mode, so the veil now always matches the
    bar.

    Palette indices follow config.py: 0=bg, 1=fg, 2=bg-alt, 3=red,
    4=green, 5=orange, 6=blue, 7=magenta, 8=cyan.

    `accent` is deliberately colors[7] and `accent2` colors[8]: those are
    what the bar itself uses for `this_current_screen_border` and for the
    active GroupBox, so the veil picks up the same two colours the user
    already reads as "qtile is highlighting something". Using colors[6]
    here meant the veil accented in a hue that appears nowhere in the bar.
    """
    theme = {
        "bg": (0.043, 0.067, 0.075),
        "fg": (0.88, 0.90, 0.94),
        "bg_alt": (0.02, 0.02, 0.03),
        "accent": (0.83, 0.53, 0.61),
        "accent2": (0.72, 0.73, 0.15),
    }
    try:
        if QTILE_CONF_DIR not in sys.path:
            sys.path.insert(0, QTILE_CONF_DIR)
        import colors as _colors

        pal = _colors.active_palette()

        def pick(i, fallback):
            try:
                v = pal[i]
                return hex_rgb(v[0] if isinstance(v, (list, tuple)) else v, fallback)
            except Exception:
                return fallback

        theme["bg"] = pick(0, theme["bg"])
        theme["fg"] = pick(1, theme["fg"])
        theme["bg_alt"] = pick(2, theme["bg_alt"])
        theme["accent"] = pick(7, theme["accent"])
        theme["accent2"] = pick(8, theme["accent2"])
    except Exception:
        pass

    # Every surface used to be mixed from white/black, which is why a
    # gruvbox desktop still produced a grey veil. These are the only
    # neutrals the drawing code is allowed to use, and both are derived
    # from the palette so they carry its temperature.
    br, bg_, bb = theme["bg"]
    fr, fg_, fb = theme["fg"]
    theme["line"] = tuple(b + (f - b) * 0.22 for b, f in
                          ((br, fr), (bg_, fg_), (bb, fb)))
    theme["dim"] = tuple(b + (f - b) * 0.55 for b, f in
                         ((br, fr), (bg_, fg_), (bb, fb)))
    # Card/keycap fill. NOT colors[2]: several palettes (gruvbox among
    # them) set the alt background to pure #000000, which turns every
    # card into a black hole punched through the blur. Lifting slightly
    # off colors[0] gives an elevated surface in every theme.
    theme["surface"] = tuple(b + (f - b) * 0.09 for b, f in
                             ((br, fr), (bg_, fg_), (bb, fb)))
    return theme


# ---------------------------------------------------------------- layout

def centre_slots(rects, sx, sy, sw, sh):
    """Neat centred row/grid of cards — one slot per window.

    The first version parked every card on the exact same point, so N
    windows looked like a single card. Distinct slots keep the count and
    the motion legible.
    """
    n = len(rects)
    if n == 0:
        return []
    cols = n if n <= 4 else math.ceil(n / 2)
    rows = math.ceil(n / cols)

    gap = max(12, int(sw * 0.014))
    band_w = sw * 0.52
    cell_w = (band_w - gap * (cols - 1)) / cols

    # Cap the cell so the band is a MAXIMUM width, not a target to fill.
    # Dividing the band by the column count meant the card size depended
    # on how many windows happened to be open: four windows got a sane
    # ~13%-of-width card each, but a single window got the entire 52%
    # band as one slab -- roughly 750px on a 1440px screen, with a card
    # so large the icon inside it read as oversized and the whole thing
    # stopped looking like a card at all. Cards should be a consistent
    # size and the row should simply be shorter when there are fewer of
    # them.
    cell_w = min(cell_w, sw * 0.165)
    cell_h = cell_w * 0.62

    max_band_h = sh * 0.42
    if rows * cell_h + gap * (rows - 1) > max_band_h:
        cell_h = (max_band_h - gap * (rows - 1)) / rows
        cell_w = cell_h / 0.62

    total_w = cell_w * cols + gap * (cols - 1)
    total_h = cell_h * rows + gap * (rows - 1)
    ox = sx + (sw - total_w) / 2
    oy = sy + (sh - total_h) / 2

    slots = []
    for i, rc in enumerate(rects):
        r, c = divmod(i, cols)
        # Preserve each window's aspect ratio inside its cell, so a tall
        # sidebar still reads as a tall card.
        try:
            ar = max(0.25, min(4.0, rc["w"] / max(1, rc["h"])))
        except Exception:
            ar = 1.6
        w = cell_w
        h = w / ar
        if h > cell_h:
            h = cell_h
            w = h * ar
        cx = ox + c * (cell_w + gap) + (cell_w - w) / 2
        cy = oy + r * (cell_h + gap) + (cell_h - h) / 2
        slots.append((cx, cy, w, h))
    return slots


# ---------------------------------------------------------------- window

class Veil(Gtk.Window):
    def __init__(self, args, theme):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.args = args
        self.theme = theme
        self.t0 = time.monotonic()
        self.done_seen_at: float | None = None
        self._announced = False
        self.stage_text = "Preparing"
        self.stage_frac = 0.05
        self.shown_frac = 0.0        # eased toward stage_frac
        self._last_stage_read = 0.0

        self.sx, self.sy = args.x, args.y
        self.sw, self.sh = args.width, args.height
        self.rects = args.rects or []
        self.tips = args.tips or []
        # Slots are handed out in list order, but the list arrives in
        # qtile's group.windows order -- which is focus/stack order, not
        # screen order. So the window on the RIGHT could be given the
        # LEFT slot and the two cards would swap sides on their way in,
        # crossing over each other. Sorting by actual position makes a
        # card always travel straight to where its window already was.
        self.rects.sort(key=lambda r: (r.get("x", 0), r.get("y", 0)))
        self.slots = centre_slots(self.rects, self.sx, self.sy, self.sw, self.sh)

        # Frosted-glass blur of whatever is actually on screen right now.
        # Grabbed BEFORE this window is mapped, so it captures the desktop
        # rather than ourselves. Downscale-then-upscale is a cheap, good
        # enough gaussian and costs ~ms, unlike decoding a full-size
        # wallpaper JPEG (which used to delay first paint by ~2s).
        self.backdrop = self._grab_blur()
        self.icons = [None] * len(self.rects)
        self._icons_tried = False
        self._topmost_thread = None

        try:
            self.set_wmclass(VEIL_CLASS, VEIL_CLASS)
        except Exception:
            pass
        self.set_title(VEIL_CLASS)
        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_accept_focus(False)
        self.set_focus_on_map(False)
        self.set_keep_above(True)
        self.set_default_size(self.sw, self.sh)
        self.resize(self.sw, self.sh)
        self.move(self.sx, self.sy)

        visual = self.get_screen().get_rgba_visual()
        self.have_alpha = visual is not None
        if self.have_alpha:
            self.set_visual(visual)

        self.connect("draw", self.on_draw)
        self.connect("realize", self.on_realize)

    def load_icons_async(self):
        if self._icons_tried:
            return False
        self._icons_tried = True
        out = []
        for rc in self.rects:
            surf = None
            raw = rc.get("icon_raw")
            if raw and os.path.exists(raw):
                try:
                    iw, ih = int(rc["icon_w"]), int(rc["icon_h"])
                    data = bytearray(open(raw, "rb").read())
                    stride = cairo.ImageSurface.format_stride_for_width(
                        cairo.FORMAT_ARGB32, iw)
                    if len(data) >= stride * ih:
                        surf = cairo.ImageSurface.create_for_data(
                            data, cairo.FORMAT_ARGB32, iw, ih, stride)
                except Exception:
                    surf = None
            if surf is None:
                pb = load_icon(rc.get("wm_class", ""), rc.get("name", ""))
                if pb is not None:
                    surf = pb
            out.append(surf)
        self.icons = out
        self.queue_draw()
        return False

    def _grab_blur(self):
        try:
            root = Gdk.get_default_root_window()
            shot = Gdk.pixbuf_get_from_window(root, self.sx, self.sy,
                                              self.sw, self.sh)
            if shot is None:
                return None
            # Downscale far enough to blur, then climb back in stages.
            #
            # This used to go to sw/14 and then halve again -- a 1440px
            # screen became 51px, and the single bilinear jump back to
            # full size interpolated between samples 28px apart. That
            # does not read as frosted glass: it produced horizontal
            # banding and turned every window edge into a hard vertical
            # seam. Recorded proof is in the 05:55 screen capture.
            #
            # sw/10 keeps a real blur radius, and doubling up in steps
            # keeps each bilinear pass interpolating between near
            # neighbours, which is what actually makes it smooth. Still
            # only a few ms -- the cost was never in the arithmetic.
            div = 10
            sw = max(2, self.sw // div)
            sh = max(2, self.sh // div)
            img = shot.scale_simple(sw, sh, GdkPixbuf.InterpType.BILINEAR)
            while sw * 2 < self.sw:
                sw, sh = sw * 2, max(1, sh * 2)
                img = img.scale_simple(sw, sh, GdkPixbuf.InterpType.BILINEAR)
            return img.scale_simple(self.sw, self.sh,
                                    GdkPixbuf.InterpType.BILINEAR)
        except Exception:
            return None

    def on_realize(self, _w):
        gw = self.get_window()
        gw.set_override_redirect(True)
        gw.input_shape_combine_region(cairo.Region(), 0, 0)   # click-through
        # picom will not reliably show the window without an explicit
        # resize/move/raise once it actually exists on the server.
        gw.resize(self.sw, self.sh)
        gw.move(self.sx, self.sy)
        gw.raise_()

    # ---- timeline ----------------------------------------------------

    def phase(self):
        el = time.monotonic() - self.t0
        if el < self.args.collapse:
            return "collapse", el / self.args.collapse
        if self.done_seen_at is None:
            return "hold", 1.0
        out = time.monotonic() - self.done_seen_at
        if out < self.args.expand:
            return "expand", out / self.args.expand
        return "gone", 1.0

    def start_topmost_watch(self):
        """Stay on top by REACTING to restacks instead of polling for them.

        tick() re-raises every 16ms, which is a poll: any window that
        raises itself just after a frame is visible on top of the veil
        until the next one. dunst was the obvious offender (it re-raises
        on every redraw), but anything override-redirect wins the same
        way -- tray menus, other notifiers, picom's own surfaces.

        This opens a second X connection on a daemon thread and asks for
        SubstructureNotify on the root window, which fires on every map
        and every restack of a top-level. wait_for_event() blocks, so the
        thread costs nothing while idle and answers in microseconds when
        something does stack itself above us. tick()'s raise stays as a
        backstop for anything that changes stacking without an event we
        see.

        Deliberately not on the GTK main loop: that loop is busy drawing
        at 60fps, and the whole point is to respond faster than a frame.
        """
        try:
            import threading
            import xcffib
            import xcffib.xproto as xp
        except Exception:
            return                      # no xcffib: tick() still covers us
        try:
            xid = self.get_window().get_xid()
        except Exception:
            return

        def run():
            try:
                c = xcffib.connect()
                root = c.get_setup().roots[0].root
                c.core.ChangeWindowAttributes(
                    root, xp.CW.EventMask,
                    [xp.EventMask.SubstructureNotify])
                c.flush()
                while True:
                    c.wait_for_event()          # blocks; not a poll
                    c.core.ConfigureWindow(
                        xid, xp.ConfigWindow.StackMode, [xp.StackMode.Above])
                    c.flush()
            except Exception:
                # Connection dropped (we are exiting) or the window is
                # gone. Nothing to do -- the process is on its way out.
                return

        t = threading.Thread(target=run, daemon=True)
        t.start()
        self._topmost_thread = t

    def tick(self):
        # Keep the veil on top. It is override-redirect, but qtile still
        # raises its own managed windows (on focus, on layout) and would
        # otherwise stack them over us mid-transition.
        #
        # dunst notifications are the hard case and the reason for
        # restack() rather than raise_(). A dunst popup is *also* an
        # override-redirect window, so no window manager arbitrates
        # between us -- X stacking is simply last-raiser-wins, and dunst
        # re-raises its window on every redraw (it redraws continuously
        # while a notification counts down). raise_() only lifts us above
        # our own toplevel group and lost that race, which is why one
        # would still surface on top of the veil now and then.
        #
        # restack(None, True) is the documented "put this above every
        # sibling in the stack" -- an unconditional XRaiseWindow to the
        # very top, re-asserted on every frame. Pausing dunst (which
        # qtile does before restarting) remains the primary defence; this
        # is what catches anything that slips through, including
        # notifications from anything that is not dunst at all.
        try:
            gw = self.get_window()
            if gw is not None:
                try:
                    gw.restack(None, True)
                except Exception:
                    gw.raise_()          # older GDK: best effort
        except Exception:
            pass
        if time.monotonic() - self.t0 > self.args.max_seconds:
            Gtk.main_quit()
            return False
        self.read_stage()
        if self.done_seen_at is None and os.path.exists(self.args.done_file):
            self.done_seen_at = time.monotonic()
        if self.phase()[0] == "gone":
            Gtk.main_quit()
            return False
        self.queue_draw()
        return True

    def read_stage(self):
        """Pick up qtile's reported stage. Cheap: a two-line file, polled
        at most 10x/sec."""
        now = time.monotonic()
        if now - self._last_stage_read < 0.1:
            return
        self._last_stage_read = now
        if not self.args.stage_file:
            return
        try:
            with open(self.args.stage_file) as f:
                frac, _, text = f.read().partition("\n")
            f = float(frac)
            if f >= self.stage_frac:      # never let the bar go backwards
                self.stage_frac = f
                self.stage_text = text.strip() or self.stage_text
        except Exception:
            pass

    def _announce(self):
        """Announce readiness from inside a real draw: by this point the
        window is mapped and has painted, so qtile can execv knowing the
        pile underneath will never become visible."""
        if self._announced:
            return
        self._announced = True
        if self.args.ready_file:
            try:
                open(self.args.ready_file, "w").close()
            except Exception:
                pass
        GLib.idle_add(self.load_icons_async)

    def _stagger(self, i, p):
        """Fan the cards out in time so they don't move as one rigid block."""
        n = max(1, len(self.rects))
        lead = 0.22
        start = (i / n) * lead
        return max(0.0, min(1.0, (p - start) / (1.0 - lead)))

    # ---- painting ----------------------------------------------------

    def on_draw(self, _w, cr):
        name, p = self.phase()

        if name == "collapse":
            # Cover fast, settle slow. The cards keep the cubic stagger
            # below -- only the scrim itself is expo, so the motion still
            # reads as deliberate rather than snapped.
            veil_a = ease_out_expo(p)
        elif name == "hold":
            veil_a = 1.0
        else:
            # Clear fast on the way out: the desktop is already restored
            # by this point, so any opacity left is pure latency.
            veil_a = 1.0 - ease_out_expo(p)
        if not self.have_alpha:
            veil_a = 1.0

        # --- background: frosted blur of the desktop as it was
        cr.save()
        cr.set_operator(cairo.OPERATOR_SOURCE)
        r, g, b = self.theme["bg"]
        cr.set_source_rgba(r, g, b, veil_a)
        cr.paint()
        cr.restore()

        if self.backdrop is not None and veil_a > 0.01:
            cr.save()
            Gdk.cairo_set_source_pixbuf(cr, self.backdrop, 0, 0)
            cr.paint_with_alpha(veil_a)
            # Dim + slight tint so the cards read clearly on any desktop.
            # Was 0.55 flat, which crushed an already-dark desktop into
            # mud. Lighter tint plus a soft vignette keeps the frosted look
            # while giving the centre panel something to sit on.
            # Was a 0.38 flat tint PLUS a 0.55 vignette -- together they
            # buried the blur and the whole veil read as a black screen,
            # which defeats the point of grabbing the desktop at all.
            # One light scrim is enough to keep text legible; the wallpaper
            # stays clearly visible through it.
            r, g, b = self.theme["bg"]
            cr.set_source_rgba(r, g, b, 0.25 * veil_a)
            cr.paint()
            cr.restore()

        self._announce()

        # --- cards
        for i, rc in enumerate(self.rects):
            if i >= len(self.slots):
                break
            sxx, syy, sww, shh = self.slots[i]
            x0, y0 = rc["x"], rc["y"]
            w0, h0 = max(1, rc["w"]), max(1, rc["h"])

            if name == "collapse":
                e = ease_in_out(self._stagger(i, p))
            elif name == "hold":
                e = 1.0
            else:
                e = 1.0 - ease_in_out(self._stagger(i, p))

            # Idle bob. Once collapsed, the cards used to hold a perfectly
            # rigid row for however many seconds qtile took, which is what
            # made the wait feel dead. A slow staggered float costs
            # nothing and keeps the frame breathing.
            bob = 0.0
            if e > 0.99:
                bob = math.sin(time.monotonic() * 1.15 + i * 0.8) * 5.0

            self.draw_card(
                cr,
                x0 + (sxx - x0) * e - self.sx,
                y0 + (syy - y0) * e - self.sy + bob,
                w0 + (sww - w0) * e,
                h0 + (shh - h0) * e,
                veil_a,
                e,
                self.icons[i] if i < len(self.icons) else None,
                rc.get("wm_class", "") or rc.get("name", ""),
            )

        if not self.rects:
            self.draw_placeholder(cr, veil_a, name)

        self.draw_status(cr, name, veil_a)
        return False

    # ---- text helpers -------------------------------------------------

    def _layout(self, cr, txt, size, weight, tracking=0.0):
        layout = PangoCairo.create_layout(cr)
        desc = Pango.FontDescription()
        desc.set_family(FONT_MONO)
        desc.set_absolute_size(size * Pango.SCALE)
        desc.set_weight(weight)
        layout.set_font_description(desc)
        if tracking:
            # Tracked-out caps are what makes a mono title read as a
            # heading instead of as a line of terminal output.
            try:
                attrs = Pango.AttrList()
                attrs.insert(Pango.attr_letter_spacing_new(
                    int(tracking * Pango.SCALE)))
                layout.set_attributes(attrs)
            except Exception:
                pass
        layout.set_text(txt, -1)
        return layout

    def _text(self, cr, txt, size, weight, x, y, alpha,
              colour=None, align_centre=True, tracking=0.0, align_right=False):
        if alpha <= 0.01 or not txt:
            return 0
        layout = self._layout(cr, txt, size, weight, tracking)
        w, h = layout.get_pixel_size()
        if align_right:
            ox = w
        elif align_centre:
            ox = w / 2
        else:
            ox = 0
        cr.save()
        cr.new_path()
        cr.move_to(x - ox, y)
        cr.set_source_rgba(*(colour or self.theme["fg"]), alpha)
        PangoCairo.show_layout(cr, layout)
        cr.restore()
        # cr.save()/restore() does NOT restore the path, so the move_to
        # above stays as the current point. The next arc() then draws a
        # connecting line from the text to the spinner -- the stray
        # diagonal line seen on screen. Clear it explicitly.
        cr.new_path()
        return h

    # ---- status block ---------------------------------------------------

    def draw_status(self, cr, name, alpha):
        """Title, real progress bar and live stage text.

        The static card row read as frozen during a multi-second reload,
        which is what made it feel slow. Everything here is driven by the
        stage qtile actually reports, so the bar stalling means qtile is
        genuinely busy rather than the animation having died.
        """
        if alpha <= 0.01:
            return

        # ease the bar toward the reported value so stage jumps glide
        self.shown_frac += (self.stage_frac - self.shown_frac) * 0.14
        if name == "expand":
            self.shown_frac = 1.0

        accent = self.theme["accent"]
        accent2 = self.theme["accent2"]
        fg = self.theme["fg"]
        dim = self.theme["dim"]
        line = self.theme["line"]

        cy_cards = self.sh * 0.5
        band = max(90.0, self.sh * 0.20)

        # Session line above the cards, different every reload. Real facts
        # about this desktop -- see _veil_message in config.py.
        if self.args.message:
            self._text(cr, self.args.message, 13.0, Pango.Weight.NORMAL,
                       self.sw / 2, cy_cards - band - 26, 0.70 * alpha,
                       colour=dim, tracking=0.8)

        # --- status as a row of bar-style chips
        #
        # This replaced a centred 21px tracked-caps title stacked over a
        # left/right justified status line over a wide progress bar. That
        # arrangement is the standard web/OS "loading screen" composition,
        # and no amount of recolouring stopped it reading as one. The bar
        # on this desktop is a row of small rounded chips with coloured
        # mono text, so the veil is now the same object.
        frac = max(0.0, min(1.0, self.shown_frac))
        label = "ready" if name == "expand" else self.stage_text.lower()
        el = time.monotonic() - self.t0

        chips = [
            ("qtile", accent, True),
            (label, fg, False),
            ("%d%%" % round(frac * 100), accent2, True),
            ("%.1fs" % el, dim, False),
        ]

        csize, cpad, cgap = 14.5, 11.0, 8.0
        measured = []
        for txt, col, bold in chips:
            w, h = self._layout(
                cr, txt, csize,
                Pango.Weight.BOLD if bold else Pango.Weight.NORMAL
            ).get_pixel_size()
            measured.append((txt, col, bold, w + cpad * 2, h + 9))
        ch = max(m[4] for m in measured)
        row_w = sum(m[3] for m in measured) + cgap * (len(measured) - 1)
        rx = (self.sw - row_w) / 2
        by = cy_cards + band

        for txt, col, bold, cw, _h in measured:
            cr.save()
            cr.new_path()
            self.rounded(cr, rx, by - ch, cw, ch, 4.0)
            cr.set_source_rgba(*self.theme["surface"], 0.92 * alpha)
            cr.fill_preserve()
            cr.set_source_rgba(*line, 0.9 * alpha)
            cr.set_line_width(1.0)
            cr.stroke()
            cr.restore()
            cr.new_path()
            self._text(cr, txt, csize,
                       Pango.Weight.BOLD if bold else Pango.Weight.NORMAL,
                       rx + cpad, by - ch + 4, 0.95 * alpha, colour=col,
                       align_centre=False)
            rx += cw + cgap

        # blinking block cursor after the row -- the terminal's "still
        # working" idiom, not a spinner
        if name == "hold" and (time.monotonic() * 1.6) % 2.0 < 1.0:
            cr.save()
            cr.new_path()
            cr.rectangle(rx - cgap + 6, by - ch + 7, 8, ch - 14)
            cr.set_source_rgba(*accent, 0.85 * alpha)
            cr.fill()
            cr.restore()
            cr.new_path()

        # progress hairline directly under the chip row, matched to its
        # width -- one object, not a second free-floating element
        bw = row_w
        bh = 2.0
        bx = (self.sw - row_w) / 2
        by += 8

        # --- the bar itself: flat palette accent on a palette track,
        # square ends. The gradient it replaces belonged to a web UI and
        # used two hues that appear nowhere in the bar.
        cr.save()
        cr.new_path()
        cr.rectangle(bx, by, bw, bh)
        cr.set_source_rgba(*line, 0.85 * alpha)
        cr.fill()
        cr.new_path()
        fw = frac * bw
        if fw > 0.5:
            cr.rectangle(bx, by, fw, bh)
            cr.set_source_rgba(*accent, 0.95 * alpha)
            cr.fill()
            # A progress bar that only moves when qtile reports a new
            # stage sits perfectly still for seconds at a time and reads
            # as frozen. This sweep keeps the filled section alive
            # without faking any progress -- it travels inside whatever
            # has genuinely completed.
            if name == "hold":
                cr.new_path()
                cr.rectangle(bx, by, fw, bh)
                cr.clip()
                sweep = ((time.monotonic() * 0.55) % 1.0) * (fw + 260) - 130
                gl = cairo.LinearGradient(bx + sweep - 130, by,
                                          bx + sweep + 130, by)
                gl.add_color_stop_rgba(0.0, *accent2, 0.0)
                gl.add_color_stop_rgba(0.5, *accent2, 0.85 * alpha)
                gl.add_color_stop_rgba(1.0, *accent2, 0.0)
                cr.set_source(gl)
                cr.paint()
        cr.restore()
        cr.new_path()

        self.draw_tip(cr, bx, by + 38, bw, alpha, name)

    def draw_placeholder(self, cr, alpha, name):
        """Shown when the group has no windows.

        An empty group left the middle of the screen completely blank
        with a progress bar floating under nothing, which looked broken
        rather than idle. Three hairline squares pulsing in sequence
        occupy the same band the cards would have.
        """
        if alpha <= 0.01:
            return
        t = time.monotonic() - self.t0
        side = min(96.0, self.sw * 0.07)
        gap = side * 0.55
        total = side * 3 + gap * 2
        x = (self.sw - total) / 2
        y = self.sh * 0.5 - side / 2
        for i in range(3):
            # each square leads the next, so the row reads left to right
            ph = (t * 1.1 - i * 0.42) % 2.4
            pulse = max(0.0, math.sin(ph * math.pi / 1.2)) if ph < 1.2 else 0.0
            bob = math.sin(time.monotonic() * 1.15 + i * 0.8) * 5.0
            cx = x + i * (side + gap)
            cr.save()
            cr.new_path()
            self.rounded(cr, cx, y + bob, side, side, 4.0)
            cr.set_source_rgba(*self.theme["surface"],
                               (0.35 + 0.30 * pulse) * alpha)
            cr.fill_preserve()
            cr.set_source_rgba(*self.theme["accent"],
                               (0.30 + 0.55 * pulse) * alpha)
            cr.set_line_width(1.0)
            cr.stroke()
            cr.restore()
            cr.new_path()

    def draw_tip(self, cr, x, y, w, alpha, name):
        """One of the user's own keybindings, rotating while qtile loads.

        A multi-second wait with nothing to read is what makes a restart
        feel long. These come from qtile.config.keys at launch time -- so
        they are always bindings that genuinely exist in the running
        config, and they stay correct when the config changes. Inventing
        plausible-looking shortcuts here would be worse than showing
        nothing.
        """
        if not self.tips or name != "hold" or alpha <= 0.01:
            return
        held = time.monotonic() - (self.t0 + self.args.collapse)
        if held < TIP_DELAY:
            return
        t = held - TIP_DELAY
        idx = int(t / TIP_PERIOD) % len(self.tips)
        ph = t % TIP_PERIOD
        # crossfade: in, hold, out
        if ph < TIP_FADE:
            fade = ph / TIP_FADE
        elif ph > TIP_PERIOD - TIP_FADE:
            fade = (TIP_PERIOD - ph) / TIP_FADE
        else:
            fade = 1.0
        fade *= alpha
        if fade <= 0.01:
            return

        tip = self.tips[idx]
        keys = str(tip.get("keys", ""))
        desc = str(tip.get("desc", ""))
        if not keys:
            return

        # One cap PER KEY rather than a single box around "Super + Shift +
        # O". Separate caps are how a keymap is actually written down, and
        # it reads as a shortcut instead of as a green label.
        toks = [t for t in keys.split(" + ") if t]
        pad, gap, joint = 9.0, 7.0, 9.0

        caps = []
        for t in toks:
            lay = self._layout(cr, t, 14.5, Pango.Weight.BOLD)
            tw, th = lay.get_pixel_size()
            caps.append((t, tw + pad * 2, th + 8))
        cap_h = max(c[2] for c in caps)
        total = sum(c[1] for c in caps) + gap * 2 * (len(caps) - 1)

        dlay = dw = None
        if desc:
            dlay = self._layout(cr, desc, 14.5, Pango.Weight.NORMAL)
            dw = dlay.get_pixel_size()[0]
            total += joint + 14.0 + dw

        # Centred on the screen, not left-aligned under the bar.
        cx = (self.sw - total) / 2

        for i, (t, cw, _ch) in enumerate(caps):
            cr.save()
            cr.new_path()
            self.rounded(cr, cx, y, cw, cap_h, 3.0)
            cr.set_source_rgba(*self.theme["surface"], 0.90 * fade)
            cr.fill_preserve()
            cr.set_source_rgba(*self.theme["accent2"], 0.60 * fade)
            cr.set_line_width(1.0)
            cr.stroke()
            cr.restore()
            cr.new_path()
            self._text(cr, t, 14.5, Pango.Weight.BOLD,
                       cx + pad, y + 4, 0.95 * fade,
                       colour=self.theme["accent2"], align_centre=False)
            cx += cw
            if i < len(caps) - 1:
                self._text(cr, "+", 14.5, Pango.Weight.NORMAL,
                           cx + gap - 3, y + 4, 0.45 * fade,
                           colour=self.theme["dim"], align_centre=False)
                cx += gap * 2

        if desc:
            self._text(cr, desc, 14.5, Pango.Weight.NORMAL,
                       cx + joint + 14.0, y + 4, 0.92 * fade,
                       colour=self.theme["fg"], align_centre=False)

    def draw_card(self, cr, x, y, w, h, alpha, e, icon=None, label=""):
        if w < 2 or h < 2 or alpha <= 0.01:
            return
        # Window corners on this desktop are barely rounded; the veil's
        # 18px pill corners were a different design language on their own.
        radius = 3 + 3 * e

        # No drop shadow. Six stacked black rounded rects lifted the cards
        # off the desktop like floating web elements -- the layout here is
        # tiled, nothing floats, and the shadow was also the only pure
        # black in the composition.

        # body: the palette's own alt background, so a card is the same
        # surface the bar sits on rather than a grey wash mixed from white
        self.rounded(cr, x, y, w, h, radius)
        cr.set_source_rgba(*self.theme["surface"], (0.62 + 0.30 * e) * alpha)
        cr.fill_preserve()
        # 1px hairline in the accent, at full strength once collapsed --
        # the same treatment as a focused window border
        cr.set_source_rgba(*self.theme["accent"], (0.25 + 0.55 * e) * alpha)
        cr.set_line_width(1.0)
        cr.stroke()
        cr.new_path()

        # The white top-highlight gradient that used to go here made every
        # card look like a glossy button. Flat surfaces read as native.

        # App icon, faded in as the card forms — at full-window size the
        # card is still overlapping the real window, so an icon there
        # would just look like clutter.
        ia = alpha * max(0.0, (e - 0.35) / 0.65)
        if ia <= 0.02:
            return
        side = min(w, h) * 0.42
        side = max(16.0, min(side, float(ICON_PX)))
        if icon is not None:
            try:
                iw0, ih0 = icon.get_width(), icon.get_height()
                sc = side / max(iw0, ih0)
                iw, ih = iw0 * sc, ih0 * sc
                cr.save()
                cr.translate(x + (w - iw) / 2, y + (h - ih) / 2)
                cr.scale(sc, sc)
                if isinstance(icon, cairo.ImageSurface):
                    cr.set_source_surface(icon, 0, 0)
                    cr.get_source().set_filter(cairo.FILTER_BILINEAR)
                else:
                    Gdk.cairo_set_source_pixbuf(cr, icon, 0, 0)
                cr.paint_with_alpha(ia)
                cr.restore()
                return
            except Exception:
                pass
        # letter badge fallback, in the palette rather than in white
        ch = (label or "?").strip()[:1].upper() or "?"
        cr.save()
        cr.select_font_face("Ubuntu Mono", cairo.FONT_SLANT_NORMAL,
                            cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(side * 0.9)
        ext = cr.text_extents(ch)
        cr.move_to(x + (w - ext.width) / 2 - ext.x_bearing,
                   y + (h - ext.height) / 2 - ext.y_bearing)
        cr.set_source_rgba(*self.theme["accent"], 0.65 * ia)
        cr.show_text(ch)
        cr.restore()

    @staticmethod
    def rounded(cr, x, y, w, h, r):
        r = max(0.0, min(r, w / 2, h / 2))
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--x", type=int, default=0)
    ap.add_argument("--y", type=int, default=0)
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    ap.add_argument("--rects-file", default=None)
    ap.add_argument("--tips-file", default=None)
    ap.add_argument("--message", default="")
    ap.add_argument("--done-file", required=True)
    ap.add_argument("--ready-file", default=None)
    ap.add_argument("--stage-file", default=None)
    ap.add_argument("--group", default="")
    ap.add_argument("--collapse", type=float, default=0.16)
    ap.add_argument("--expand", type=float, default=0.20)
    ap.add_argument("--max-seconds", type=float, default=8.0)
    args = ap.parse_args()

    args.rects = []
    if args.rects_file and os.path.exists(args.rects_file):
        try:
            with open(args.rects_file) as f:
                args.rects = json.load(f)
        except Exception:
            args.rects = []

    args.tips = []
    if args.tips_file and os.path.exists(args.tips_file):
        try:
            with open(args.tips_file) as f:
                args.tips = json.load(f)
        except Exception:
            args.tips = []

    for stale in (args.done_file, args.ready_file):
        if stale:
            try:
                os.remove(stale)
            except OSError:
                pass

    v = Veil(args, load_theme())
    v.show_all()
    v.start_topmost_watch()      # after show_all(): needs a realised XID
    GLib.timeout_add(16, v.tick)
    # Belt and braces: even if the GTK loop wedges, the process still dies.
    GLib.timeout_add(int((args.max_seconds + 2) * 1000),
                     lambda: (Gtk.main_quit(), False)[1])
    try:
        Gtk.main()
    finally:
        # Release dunst HERE, not on a timer in qtile. qtile paused it
        # before execv and could only guess when we were gone; the veil is
        # the one process that knows exactly when its window stops
        # existing, so unpausing anywhere else is a race -- dunst flushes
        # its whole queued backlog the instant it unpauses, and every one
        # of those lands on the veil if it is still up.
        #
        # This also closes a silent failure: qtile's unpause lives only in
        # _veil_signal_done(), so a restart that never reached
        # startup_complete left dunst paused forever and the user simply
        # stopped receiving notifications with nothing to indicate why.
        # Running it from `finally` means it happens on the watchdog path
        # and on a crash too.
        try:
            subprocess.Popen(["dunstctl", "set-paused", "false"],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
