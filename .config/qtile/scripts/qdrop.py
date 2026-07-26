#!/usr/bin/env python3
"""qdrop — native drop stash for qtile scratchpad.

Features:
- Drop files (text/uri-list) or text (text/plain) in.
- Drag items back out.
- Ctrl+A selects all; dragging any selected item drags them all.
- Middle/right click removes single item.
- Slide-down reveal animation on show.
- Auto-hide when pointer leaves for AUTO_HIDE_MS.
- Persistence at ~/.cache/qdrop.json.
- WM_CLASS=qdrop for qtile scratchpad matching.
"""
import json
import os
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

THUMB = 56
AUTO_HIDE_MS = 8000
REVEAL_MS = 220
IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg", ".tiff"}
STATE_FILE = Path.home() / ".cache" / "qdrop.json"

CSS = b"""
window#qdrop { background: transparent; }
#qdrop-root {
    background: rgba(30, 30, 46, 0.97);
    border: 1px solid #45475a;
    border-radius: 10px;
}
#qdrop-header {
    padding: 6px 10px;
    background: rgba(24, 24, 37, 0.9);
    border-bottom: 1px solid #313244;
    border-radius: 10px 10px 0 0;
}
#qdrop-title { color: #cdd6f4; font-weight: 600; }
#qdrop-count {
    color: #89b4fa; font-family: monospace;
    margin-left: 6px;
}
button {
    background: #313244;
    color: #cdd6f4;
    border: none;
    padding: 3px 9px;
    border-radius: 4px;
    font-size: 11px;
}
button:hover { background: #45475a; }
flowboxchild {
    padding: 4px;
    border-radius: 6px;
    min-width: 68px;
}
flowboxchild:hover { background: #313244; }
flowboxchild:selected { background: #45475a; }
#qdrop-item label {
    color: #bac2de;
    font-size: 9px;
}
#qdrop-empty {
    color: #6c7086;
    font-size: 12px;
    margin: 40px;
}
"""


def uri_to_path(uri: str) -> str | None:
    if not uri.startswith("file://"):
        return None
    return unquote(urlparse(uri).path)


def load_state():
    try:
        data = json.loads(STATE_FILE.read_text())
        out = []
        for e in data:
            if e["type"] == "file" and not os.path.exists(e["value"]):
                continue
            out.append(e)
        return out
    except Exception:
        return []


def save_state(entries):
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(entries))
    except Exception:
        pass


class Item(Gtk.EventBox):
    def __init__(self, entry: dict, win: "Dropzone"):
        super().__init__()
        self.entry = entry
        self.win = win
        self.set_name("qdrop-item")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.add(box)

        img = Gtk.Image()
        if entry["type"] == "file":
            path = entry["value"]
            ext = Path(path).suffix.lower()
            if ext in IMG_EXT and os.path.isfile(path):
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, THUMB, THUMB, True)
                    img.set_from_pixbuf(pb)
                except Exception:
                    img.set_from_icon_name("image-x-generic-symbolic", Gtk.IconSize.DND)
                    img.set_pixel_size(THUMB)
            else:
                icon = "folder-symbolic" if os.path.isdir(path) else "text-x-generic-symbolic"
                img.set_from_icon_name(icon, Gtk.IconSize.DND)
                img.set_pixel_size(THUMB)
            label = Path(path).name
            tip = path
        else:
            img.set_from_icon_name("text-x-generic-symbolic", Gtk.IconSize.DND)
            img.set_pixel_size(THUMB)
            label = entry["value"].strip().splitlines()[0][:20] if entry["value"].strip() else "(empty)"
            tip = entry["value"][:400]

        box.pack_start(img, False, False, 0)
        lbl = Gtk.Label(label=label)
        lbl.set_max_width_chars(10)
        lbl.set_ellipsize(3)
        box.pack_start(lbl, False, False, 0)

        self.set_tooltip_text(tip)

        targets = [
            Gtk.TargetEntry.new("text/uri-list", 0, 0),
            Gtk.TargetEntry.new("text/plain", 0, 1),
            Gtk.TargetEntry.new("UTF8_STRING", 0, 1),
        ]
        self.drag_source_set(
            Gdk.ModifierType.BUTTON1_MASK,
            targets,
            Gdk.DragAction.COPY,
        )
        self.connect("drag-data-get", self._on_get)
        self.connect("button-press-event", self._on_click)

    def _selection_entries(self) -> list[dict]:
        fbc = self.get_parent()
        flow = fbc.get_parent() if fbc else None
        selected = flow.get_selected_children() if flow else []
        if fbc in selected and len(selected) > 1:
            return [c.get_child().entry for c in selected]
        return [self.entry]

    def _on_get(self, _w, _ctx, data, info, _time):
        entries = self._selection_entries()
        if info == 0:  # uri-list
            uris = [Path(e["value"]).as_uri() for e in entries if e["type"] == "file"]
            if uris:
                data.set_uris(uris)
        else:  # text
            parts = [e["value"] if e["type"] == "text" else e["value"] for e in entries]
            data.set_text("\n".join(parts), -1)

    def _on_click(self, _w, ev):
        if ev.button in (2, 3):
            self.win.remove_entry(self.entry)


class Dropzone(Gtk.Window):
    def __init__(self):
        super().__init__(title="qdrop")
        self.set_name("qdrop")
        self.set_wmclass("qdrop", "qdrop")
        self.set_default_size(460, 320)
        self.set_keep_above(True)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_icon_name("edit-copy")

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)
        self.set_app_paintable(True)

        self.revealer = Gtk.Revealer()
        self.revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.revealer.set_transition_duration(REVEAL_MS)
        self.revealer.set_reveal_child(False)
        self.add(self.revealer)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.set_name("qdrop-root")
        self.revealer.add(root)

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hdr.set_name("qdrop-header")
        title = Gtk.Label(label="qdrop")
        title.set_name("qdrop-title")
        title.set_xalign(0)
        hdr.pack_start(title, False, False, 0)
        self.count_lbl = Gtk.Label(label="0")
        self.count_lbl.set_name("qdrop-count")
        hdr.pack_start(self.count_lbl, True, False, 0)

        all_btn = Gtk.Button(label="All")
        all_btn.set_tooltip_text("Select all (Ctrl+A)")
        all_btn.connect("clicked", lambda *_: self._select_all())
        hdr.pack_end(all_btn, False, False, 0)
        clr = Gtk.Button(label="Clear")
        clr.connect("clicked", lambda *_: self.clear())
        hdr.pack_end(clr, False, False, 0)
        root.pack_start(hdr, False, False, 0)

        self.stack = Gtk.Stack()
        root.pack_start(self.stack, True, True, 0)

        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        empty.set_valign(Gtk.Align.CENTER)
        empty.set_halign(Gtk.Align.CENTER)
        ei = Gtk.Image.new_from_icon_name("insert-object-symbolic", Gtk.IconSize.DIALOG)
        ei.set_pixel_size(48)
        empty.pack_start(ei, False, False, 0)
        el = Gtk.Label(label="Drop files or text here")
        el.set_name("qdrop-empty")
        empty.pack_start(el, False, False, 0)
        self.stack.add_named(empty, "empty")

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(7)
        self.flow.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        scroll.add(self.flow)
        self.stack.add_named(scroll, "items")

        drop_targets = [
            Gtk.TargetEntry.new("text/uri-list", 0, 0),
            Gtk.TargetEntry.new("text/plain", 0, 1),
            Gtk.TargetEntry.new("UTF8_STRING", 0, 1),
        ]
        self.drag_dest_set(
            Gtk.DestDefaults.ALL,
            drop_targets,
            Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK,
        )
        self.connect("drag-data-received", self._on_drop)
        self.connect("delete-event", lambda *_: self.hide() or True)
        self.connect("key-press-event", self._on_key)
        self.connect("map-event", self._on_map)
        self.connect("enter-notify-event", self._on_enter)
        self.connect("leave-notify-event", self._on_leave)

        self.entries: list[dict] = []
        self._hide_timer = 0
        self._apply_css()
        for e in load_state():
            self._add(e, persist=False)
        self._refresh()

    def _apply_css(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _on_map(self, *_):
        self.revealer.set_reveal_child(False)
        GLib.timeout_add(20, lambda: (self.revealer.set_reveal_child(True), False)[1])
        self._reset_hide_timer()

    def _reset_hide_timer(self):
        if self._hide_timer:
            GLib.source_remove(self._hide_timer)
        self._hide_timer = GLib.timeout_add(AUTO_HIDE_MS, self._auto_hide)

    def _cancel_hide_timer(self):
        if self._hide_timer:
            GLib.source_remove(self._hide_timer)
            self._hide_timer = 0

    def _auto_hide(self):
        self._hide_timer = 0
        self.revealer.set_reveal_child(False)
        GLib.timeout_add(REVEAL_MS + 30, lambda: (self.hide(), False)[1])
        return False

    def _on_enter(self, *_):
        self._cancel_hide_timer()
        return False

    def _on_leave(self, _w, ev):
        if ev.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._reset_hide_timer()
        return False

    def _on_key(self, _w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            self._auto_hide()
            return True
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and ev.keyval in (Gdk.KEY_a, Gdk.KEY_A):
            self._select_all()
            return True
        if ctrl and ev.keyval in (Gdk.KEY_l, Gdk.KEY_L):
            self.clear()
            return True
        return False

    def _select_all(self):
        self.flow.select_all()

    def _on_drop(self, _w, _ctx, _x, _y, data, info, _time):
        added = False
        if info == 0:  # uris
            for uri in (data.get_uris() or []):
                p = uri_to_path(uri)
                if p and os.path.exists(p) and not any(
                    e["type"] == "file" and e["value"] == p for e in self.entries
                ):
                    self._add({"type": "file", "value": p})
                    added = True
        else:
            txt = data.get_text()
            if txt and txt.strip():
                self._add({"type": "text", "value": txt})
                added = True
        if added:
            self._refresh()

    def _add(self, entry: dict, persist: bool = True):
        self.entries.append(entry)
        item = Item(entry, self)
        self.flow.add(item)
        self.flow.show_all()
        if persist:
            save_state(self.entries)

    def remove_entry(self, entry: dict):
        try:
            self.entries.remove(entry)
        except ValueError:
            return
        for fbc in self.flow.get_children():
            child = fbc.get_child()
            if getattr(child, "entry", None) is entry:
                fbc.destroy()
                break
        save_state(self.entries)
        self._refresh()

    def clear(self):
        self.entries.clear()
        for c in self.flow.get_children():
            c.destroy()
        save_state(self.entries)
        self._refresh()

    def _refresh(self):
        self.count_lbl.set_text(str(len(self.entries)))
        self.stack.set_visible_child_name("items" if self.entries else "empty")


def main():
    win = Dropzone()
    win.show_all()
    win.connect("destroy", Gtk.main_quit)
    Gtk.main()


if __name__ == "__main__":
    sys.exit(main() or 0)
