#!/usr/bin/env python3
"""A window that is both a drag SOURCE and a drop TARGET.  TEST TOOL.

    ./dnd-peer.py <file-to-offer> [--x11]

qdrop's two jobs are "drop things in" and "drag them back out", and neither
could be driven here. Every real drag source on this desktop is also a real
application holding real files — driving a synthetic drag out of pcmanfm-qt
means synthesising a file MOVE over somebody's home directory, which is not
a test, it is a gamble. This is the controlled other end: it offers exactly
one URI, the one named on the command line, and it prints whatever is
dropped on it to stdout.

It is a WAYLAND client by default, deliberately. That is the interesting
half of the question: qdrop runs under XWayland (it positions itself, which
Wayland forbids), so a drop from a Wayland file manager into the shelf
crosses Hyprland's wl_data_device <-> XDND bridge, and that bridge is the
thing that has never been exercised in this tree. `--x11` forces the source
onto XWayland for the same-backend comparison.

It cannot place itself — same reason qdrop needs GDK_BACKEND=x11 — so the
caller positions it with `hyprctl dispatch movewindowpixelexact` against the
`dnd-peer` class it sets.

Pair it with `uinput-shake.py to <x1> <y1> <x2> <y2>`, which is the drag
half: a real button-1 press, a closed-loop travel to the destination, and a
release, all through /dev/uinput.
"""
import os
import sys

if "--x11" in sys.argv:
    os.environ["GDK_BACKEND"] = "x11"

import gi

gi.require_version("Gtk", "3.0")
# Gdk needs its own require_version: without it `from gi.repository import
# Gdk` pulls 4.0 and then Gtk 3.0 cannot load beside it. qdrop.py pins all
# three of its namespaces for the same reason.
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402

TARGETS = [Gtk.TargetEntry.new("text/uri-list", 0, 0),
           Gtk.TargetEntry.new("text/plain", 0, 1)]


class Peer(Gtk.Window):
    def __init__(self, offer_uri: str):
        super().__init__(title="dnd-peer")
        self.set_default_size(420, 150)
        self.offer_uri = offer_uri
        # Under Wayland the app_id is the PROGRAM NAME, not anything a
        # Gtk.Window can set -- so this comes up as class `dnd-peer.py` and
        # matches no rule in rules.conf. Address it by title, or by the
        # address `hyprctl clients` gives you; the caller places it either
        # way, because a Wayland client cannot place itself.

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.src = Gtk.Label(label="SOURCE — drag me")
        self.src.set_size_request(-1, 60)
        self.dst = Gtk.Label(label="TARGET — drop here")
        self.dst.set_size_request(-1, 60)
        box.pack_start(self.src, True, True, 0)
        box.pack_start(self.dst, True, True, 0)
        self.add(box)

        ev_src = Gtk.EventBox()
        # The label has no window of its own, so the drag has to be set up
        # on something that can receive button events.
        box.remove(self.src)
        ev_src.add(self.src)
        box.pack_start(ev_src, True, True, 0)
        box.reorder_child(ev_src, 0)
        ev_src.drag_source_set(Gdk.ModifierType.BUTTON1_MASK, TARGETS,
                               Gdk.DragAction.COPY)
        ev_src.connect("drag-data-get", self.on_get)
        # Loud about the steps BEFORE the drag, because "nothing was
        # dropped" has three very different causes -- the pointer never
        # arrived, the button never arrived, or the drag never began -- and
        # they are indistinguishable from the far end.
        ev_src.add_events(Gdk.EventMask.BUTTON_PRESS_MASK
                          | Gdk.EventMask.POINTER_MOTION_MASK
                          | Gdk.EventMask.ENTER_NOTIFY_MASK)
        ev_src.connect("enter-notify-event",
                       lambda *_: print("SRC: pointer entered", flush=True))
        ev_src.connect("button-press-event",
                       lambda *_: print("SRC: button pressed", flush=True))
        ev_src.connect("drag-begin",
                       lambda *_: print("SRC: drag begun", flush=True))

        ev_dst = Gtk.EventBox()
        box.remove(self.dst)
        ev_dst.add(self.dst)
        box.pack_start(ev_dst, True, True, 0)
        ev_dst.drag_dest_set(Gtk.DestDefaults.ALL, TARGETS, Gdk.DragAction.COPY)
        ev_dst.connect("drag-data-received", self.on_recv)

        self.connect("destroy", Gtk.main_quit)
        self.show_all()
        print(f"peer up, offering {self.offer_uri}", flush=True)

    def on_get(self, _w, _ctx, data, info, _t):
        if info == 0:
            data.set_uris([self.offer_uri])
        else:
            data.set_text(self.offer_uri, -1)
        print(f"DRAG-OUT: handed over {self.offer_uri}", flush=True)

    def on_recv(self, _w, ctx, _x, _y, data, _info, t):
        uris = data.get_uris()
        text = data.get_text()
        print(f"DROP-IN: uris={uris} text={text!r}", flush=True)
        Gtk.drag_finish(ctx, True, False, t)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("usage: dnd-peer.py <file-to-offer> [--x11]", file=sys.stderr)
        sys.exit(2)
    path = os.path.abspath(args[0])
    Peer("file://" + path)
    Gtk.main()


if __name__ == "__main__":
    main()
