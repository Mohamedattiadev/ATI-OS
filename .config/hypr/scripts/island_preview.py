"""island_preview — the settings app's live island, and the tray you drag into it.

WHY THIS EXISTS
---------------
Reported: "the island settings is too bad, just text and numbers — I want it
more interactive, show an example, and a person can drag and put in an example
notch island and it appears in the real island."

The app was 31 rows of spin buttons and combos. Every one is correct and none
of them shows you the thing you are editing, which for GEOMETRY is most of the
point: `islandHeight 35` and `islandTopMargin 11` are two numbers whose only
meaningful readout is the shape they make together.

So this module is two halves:

    draw_island / IslandPreview   the island, drawn from the live values
    SwipeTray                     the swipe readout as draggable chips

THE DRAWING IS A MODULE FUNCTION, NOT A METHOD, and that is deliberate: a
draw method on a GObject subclass cannot be called without constructing the
widget — `object.__new__` is refused for GObject types, measured — so the part
with all the arithmetic in it would have been testable only by starting the
app and looking. `_selftest` renders every shape to a PNG instead.

WHAT IT DOES NOT DO
-------------------
It does not write anything. Every commit goes back through the app's
`run_ctl(["--set", ...])`, so island-settings.py stays the only writer of
userconfig.json — the atomic write, the clamping, the enum check and the
fc-match all stay in one place, which is the rule that file's header sets out.
"""

import math

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GObject, Gtk  # noqa: E402


# The ten values dynamicIslandLeftSwipeItems accepts, with a short name and a
# sample reading for each. Kept in step with
# IslandSystemState.buildCustomSwipeItem — the descriptor's own note says
# anything outside this list renders as an empty slot rather than an error,
# which is the failure a free-text field would happily let you commit.
ITEM_LABELS = {
    "cpu": ("CPU", "42%"),
    "ram": ("RAM", "6.1G"),
    "storage": ("DISK", "128G"),
    "battery": ("BAT", "100%"),
    "volume": ("VOL", "60%"),
    "brightness": ("BRI", "50%"),
    "workspace": ("WS", "4"),
    "time": ("TIME", "23:41"),
    "date": ("DATE", "Aug 15"),
    "cava": ("CAVA", "▁▃▅▇▅▃"),
}

# The stage is the top STRIP of the screen, not the whole screen.
#
# Drawn to the full 1366x768 first, and it was useless: the fit put a 35 px
# island at under 7 px tall, which is a smudge rather than a preview. The
# island only ever lives in the top ~150 px, so that is what the stage shows —
# the same screen, cropped, at nearly 1:1. The aspect stays uniform, because a
# non-uniform fit would distort the one thing being judged.
SCREEN_W = 1366.0
STRIP_H = 170.0


def _rounded(cr, x, y, w, h, r_top, r_bottom):
    """One path for both forms.

    The notch and the floating pill are not two shapes here any more than they
    are in the QML: DESIGN-SPEC.md calls it one shape interpolated by
    notchProgress. The only difference this needs is which corners are round,
    so the two radii are arguments.
    """
    r_top = max(0.0, min(r_top, w / 2, h / 2))
    r_bottom = max(0.0, min(r_bottom, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r_top, y + r_top, r_top, -math.pi / 2, 0)
    cr.arc(x + w - r_bottom, y + h - r_bottom, r_bottom, 0, math.pi / 2)
    cr.arc(x + r_bottom, y + h - r_bottom, r_bottom, math.pi / 2, math.pi)
    cr.arc(x + r_top, y + r_top, r_top, math.pi, 3 * math.pi / 2)
    cr.close_path()


def draw_island(cr, width, height, v):
    """Paint the island on its mock screen strip. Pure — no widget, no state."""
    pad = 8.0
    scale = min((width - pad * 2) / SCREEN_W, (height - pad * 2) / STRIP_H)
    sw, sh = SCREEN_W * scale, STRIP_H * scale
    ox, oy = (width - sw) / 2, (height - sh) / 2

    # The screen's top strip. Only the TOP corners are round — the bottom edge
    # is a crop, not an edge, and rounding it would read as a device.
    cr.set_source_rgb(0.09, 0.09, 0.11)
    _rounded(cr, ox, oy, sw, sh, 6, 0)
    cr.fill()

    # A ghost window below the reserved zone, so the exclusive zone reads as
    # the GAP it is. This is the half that made the notch-off report visible.
    top = oy + (v["exclusive"] + 8) * scale
    if top < oy + sh - 2:
        cr.set_source_rgb(0.15, 0.15, 0.18)
        gap = 8 * scale
        cr.rectangle(ox + gap, top, sw - gap * 2, oy + sh - top)
        cr.fill()

    iw = v["width"] * scale
    ih = v["height"] * scale
    # islandPositionX is a percentage across the screen and positions the
    # island's CENTRE — 50 is centred, which is why this is not a left edge.
    ix = ox + sw * (v["position_x"] / 100.0) - iw / 2
    iy = oy + (0 if v["notch"] else v["top_margin"] * scale)

    r_top = 0.0 if v["notch"] else ih / 2
    r_bottom = ih / 2

    alpha = max(0.0, min(1.0, v["opacity"] / 100.0))
    cr.set_source_rgba(0.02, 0.02, 0.03, alpha)
    _rounded(cr, ix, iy, iw, ih, r_top, r_bottom)
    cr.fill()
    cr.set_source_rgba(0.4, 0.4, 0.46, alpha)
    cr.set_line_width(1)
    _rounded(cr, ix + 0.5, iy + 0.5, iw - 1, ih - 1, r_top, r_bottom)
    cr.stroke()

    items = v["items"]
    cr.select_font_face("sans")
    if items and iw > 30:
        cr.set_font_size(max(6.0, min(ih * 0.38, 13.0)))
        slot = iw / len(items)
        for index, name in enumerate(items):
            label = ITEM_LABELS.get(name, (name.upper(), ""))[1]
            extents = cr.text_extents(label)
            # A slot too narrow for its own text gets a dot rather than an
            # overlap. Four readouts in a 135 px island is a real setting, and
            # letting them collide would misreport it as fitting.
            if extents.width > slot - 4:
                label = "·"
                extents = cr.text_extents(label)
            cr.set_source_rgb(0.86, 0.86, 0.9)
            cr.move_to(ix + slot * index + (slot - extents.width) / 2,
                       iy + ih / 2 + extents.height / 2)
            cr.show_text(label)
    elif not items:
        cr.set_font_size(max(6.0, min(ih * 0.34, 11.0)))
        label = "drag a chip in"
        extents = cr.text_extents(label)
        cr.set_source_rgb(0.45, 0.45, 0.5)
        cr.move_to(ix + (iw - extents.width) / 2,
                   iy + ih / 2 + extents.height / 2)
        cr.show_text(label)

    # The two distances with no other readout, called out where they happen
    # instead of in a spin button: the margin above the island, and the
    # reserved zone that decides where windows begin.
    cr.set_font_size(10)
    cr.set_source_rgb(0.55, 0.55, 0.62)
    if not v["notch"] and v["top_margin"] > 0:
        cr.move_to(ox + 8, oy + 12)
        cr.show_text("top margin %d" % v["top_margin"])
    if top < oy + sh - 4:
        cr.move_to(ox + 8, min(oy + sh - 5, top + 13))
        cr.show_text("windows start at %d" % v["exclusive"])


class IslandPreview(Gtk.DrawingArea):
    """The island as it will look, on a mock screen strip.

    The stage is deliberately a SCREEN and not a swatch: islandPositionX is a
    percentage across the display and islandTopMargin is a distance from its
    top edge, and both are meaningless against a blank background.
    """

    def __init__(self, get_values):
        super().__init__()
        self._get = get_values
        self.set_content_height(190)
        self.set_hexpand(True)
        self.set_draw_func(lambda _a, cr, w, h, *_:
                           draw_island(cr, w, h, self._get()))
        self.add_css_class("card")

    def refresh(self):
        self.queue_draw()


class SwipeTray(Gtk.Box):
    """The swipe readout as two trays of draggable chips.

    In the island on the left, available on the right. A chip is dragged
    between them to add or remove it — order is what the setting MEANS, so a
    row of checkboxes could not express it and a text field could not
    validate it.
    """

    __gsignals__ = {
        # (csv,) — emitted only when membership actually changed, so the app
        # does not spawn a --set per drag that landed where it started.
        "items-changed": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, all_values, items):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self._all = list(all_values)
        self._items = [i for i in items if i in self._all]
        self._left = self._make_column("In the island", True)
        self._right = self._make_column("Available", False)
        self.append(self._left["box"])
        self.append(self._right["box"])
        self.rebuild()

    @property
    def items(self):
        return list(self._items)

    def set_items(self, items):
        self._items = [i for i in items if i in self._all]
        self.rebuild()

    def _commit(self):
        self.emit("items-changed", ",".join(self._items))

    def _make_column(self, title, is_selected):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_hexpand(True)
        label = Gtk.Label(label=title, xalign=0.0)
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        box.append(label)

        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                           column_spacing=6, row_spacing=6,
                           min_children_per_line=2, max_children_per_line=4)
        flow.set_hexpand(True)
        frame = Gtk.Frame()
        frame.set_child(flow)
        frame.add_css_class("view")
        frame.set_size_request(-1, 88)
        box.append(frame)

        # The whole TRAY is the drop target, not each chip: dropping onto a
        # 60x24 chip is a game of darts, and the thing being expressed is
        # "belongs in this group".
        drop = Gtk.DropTarget.new(GObject.TYPE_STRING, Gdk.DragAction.MOVE)
        drop.connect("drop", self._on_drop, is_selected)
        frame.add_controller(drop)
        return {"box": box, "flow": flow, "selected": is_selected}

    def _make_chip(self, name, is_selected):
        title, sample = ITEM_LABELS.get(name, (name.upper(), ""))
        button = Gtk.Button()
        button.add_css_class("pill")
        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        inner.append(Gtk.Label(label=title))
        if sample:
            muted = Gtk.Label(label=sample)
            muted.add_css_class("dim-label")
            inner.append(muted)
        button.set_child(inner)
        button.set_tooltip_text(
            "Drag to the other tray, or click, to %s"
            % ("remove it" if is_selected else "add it"))

        source = Gtk.DragSource()
        source.set_actions(Gdk.DragAction.MOVE)
        source.connect("prepare", self._on_prepare, name)
        button.add_controller(source)

        # Click as well as drag. Dragging is the asked-for gesture and it is
        # also the one that is awkward on a trackpad, so the same move is one
        # click away — and a click is something a test can synthesise.
        button.connect("clicked", self._on_chip_clicked, name, is_selected)
        return button

    def rebuild(self):
        for column in (self._left, self._right):
            flow = column["flow"]
            while (child := flow.get_first_child()) is not None:
                flow.remove(child)
        for name in self._items:
            self._left["flow"].append(self._make_chip(name, True))
        for name in self._all:
            if name not in self._items:
                self._right["flow"].append(self._make_chip(name, False))

    def _on_prepare(self, _source, _x, _y, name):
        return Gdk.ContentProvider.new_for_value(GObject.Value(str, name))

    def _on_chip_clicked(self, _button, name, is_selected):
        self.apply_move(name, not is_selected)

    def _on_drop(self, _target, value, _x, _y, into_selected):
        return self.apply_move(str(value), into_selected)

    def apply_move(self, name, into_selected):
        """Add or remove `name`. Returns True if anything changed.

        The one place membership is edited, so the drop handler and the click
        handler cannot drift — they are the same gesture with two spellings.
        """
        if name not in self._all:
            return False
        before = list(self._items)
        if into_selected:
            if name not in self._items:
                self._items.append(name)
        else:
            self._items = [i for i in self._items if i != name]
        if self._items == before:
            return False
        self.rebuild()
        self._commit()
        return True


def _selftest(path="/tmp/island-preview.png", width=900, height=190):
    """Render every shape to a PNG, without starting the app.

    A preview whose only test is "open the app and look" is the thing this
    module was written to replace.
    """
    import cairo

    cases = [
        ("notch, 3 readouts",
         dict(notch=True, height=35, width=135, top_margin=11, exclusive=33,
              position_x=50, opacity=100, items=["cpu", "battery", "ram"])),
        ("floating — the gap this session fixed",
         dict(notch=False, height=35, width=135, top_margin=11, exclusive=46,
              position_x=50, opacity=100, items=["cpu", "battery", "ram"])),
        ("wide, off-centre, 80% opacity",
         dict(notch=False, height=48, width=320, top_margin=18, exclusive=66,
              position_x=25, opacity=80,
              items=["time", "date", "cava", "volume"])),
        ("empty",
         dict(notch=True, height=28, width=150, top_margin=0, exclusive=28,
              position_x=75, opacity=100, items=[])),
    ]
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height * len(cases))
    cr = cairo.Context(surface)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    for index, (name, values) in enumerate(cases):
        cr.save()
        cr.translate(0, height * index)
        draw_island(cr, width, height, values)
        cr.set_source_rgb(0.3, 0.3, 0.35)
        cr.select_font_face("sans")
        cr.set_font_size(12)
        cr.move_to(10, height - 6)
        cr.show_text(name)
        cr.restore()
    surface.write_to_png(path)
    return path


if __name__ == "__main__":
    print(_selftest())
