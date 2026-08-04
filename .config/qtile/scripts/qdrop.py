#!/usr/bin/env python3
"""qdrop — native drop-stash for qtile. macOS-shelf-like.

CLI:
  qdrop.py                start daemon (single instance)
  qdrop.py --toggle       toggle visibility (auto-spawns daemon)
  qdrop.py --show         show
  qdrop.py --hide         hide
  qdrop.py --add-text TXT add text entry
  qdrop.py --status       print daemon status

Features:
- Drop files (text/uri-list) or text (text/plain) in.
- Drag items back out (single or multi-selection).
- Newest first. Persistence at ~/.cache/qdrop.json.
- Click = single-select. Ctrl+click = toggle. Ctrl+A = all. Esc/Ctrl+Shift+A = deselect.
- Delete = remove selected. Enter/dbl-click = open. Right-click = context menu.
- Auto-hide 8s after pointer leaves (cancels on hover / focus).
- Slide-down reveal, undecorated, sticks to top-center.
- Type badges (IMG/TXT/DIR/DOC).
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

UID = os.getuid()
STATE_FILE = Path.home() / ".cache" / "qdrop.json"
# Images pasted/dropped as raw bitmap data (a copied web image is pixels
# on the clipboard, not a file) have to be written somewhere before they
# can be an entry -- every entry is a path, a URL or text.
IMG_DIR = Path.home() / ".cache" / "qdrop-images"


def _display_tag() -> str:
    """A filename-safe token identifying the X display.

    The control socket has to be keyed by DISPLAY as well as UID. Keyed by
    UID alone, a second X session for the same user -- a nested Xephyr, a
    second seat, a VNC server -- resolves to the FIRST session's socket:
    `_client` connects to it, the already-running daemon obeys, and the
    shelf slides in on the wrong screen entirely. The flock singleton
    cannot catch this, because it was keyed by UID for the same reason.

    Found while recording the demo GIFs -- a `--toggle` inside a nested
    display drove the daemon on the real one.

    The screen suffix is dropped on purpose. DISPLAY is
    `[host]:display[.screen]`, and `.0`/`.1` select a screen on the SAME
    server, so keeping it would hand one X server two daemons.
    """
    disp = os.environ.get("DISPLAY", "")
    if not disp:
        return "nodisplay"
    host, _, rest = disp.rpartition(":")
    num = rest.split(".", 1)[0]
    tag = f"{host}-{num}" if host else num
    return re.sub(r"[^A-Za-z0-9_-]", "_", tag) or "nodisplay"


DISPLAY_TAG = _display_tag()
LOCK_FILE = Path(f"/tmp/qdrop-{UID}-{DISPLAY_TAG}.lock")
SOCK_PATH = Path(f"/tmp/qdrop-{UID}-{DISPLAY_TAG}.sock")
QT_PALETTE = Path.home() / ".cache" / "qtile" / "current_palette.json"
WAL_COLORS = Path.home() / ".cache" / "wal" / "colors.json"

THUMB = 48
AUTO_HIDE_MS = 8000
REVEAL_MS = 220  # open duration -- whole-window Y slide (see _slide_move).
HIDE_MS = 130  # close duration -- deliberately faster than REVEAL_MS;
# a lingering close reads as sluggish even when the open feels fine.
WIN_W = 620  # was 440, which was never the real width: the header's own
# minimum (title + stats chips + 6 buttons) already forced ~569px, so the
# 440 in the geometry hints was a lie qtile happened not to enforce. It
# also *varied* with the stats chips -- see STATS_W below. WIN_W is now
# wide enough that the header never binds, so the width is constant and
# the hints match reality. qdrop_test.py asserts the header still fits.
WIN_H = 320
STATS_W = 210  # fixed width of the header stats-chip strip; fits the
# worst case measured (999 items + a pinned chip = 206px), so nothing
# clips and the width still never depends on the counts.

IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg", ".tiff"}
DOC_EXT = {".pdf", ".doc", ".docx", ".odt", ".rtf"}
TEXT_EXT = {
    ".txt", ".md", ".py", ".js", ".ts", ".tsx", ".jsx", ".rs", ".go",
    ".c", ".h", ".cpp", ".hpp", ".java", ".kt", ".rb", ".php",
    ".html", ".css", ".scss", ".json", ".yaml", ".yml", ".toml",
    ".ini", ".conf", ".cfg", ".sh", ".bash", ".zsh", ".fish", ".sql",
    ".xml", ".csv", ".log", ".lua", ".vim", ".env", ".patch", ".diff",
    ".dockerfile",
}


def is_text_file(path: str) -> bool:
    ext = Path(path).suffix.lower()
    if ext in TEXT_EXT:
        return True
    if not os.path.isfile(path):
        return False
    try:
        r = subprocess.run(
            ["file", "--mime-type", "-b", path],
            capture_output=True, text=True, timeout=1,
        )
        return r.stdout.startswith("text/")
    except Exception:
        return False


def open_in_nvim(path: str, readonly: bool = False):
    args = [
        "setsid", "alacritty",
        "--class", "clip-view", "--title", "clip-view",
        "-o", "window.dimensions.columns=80",
        "-o", "window.dimensions.lines=20",
        "-o", "window.padding.x=8",
        "-o", "window.padding.y=8",
        "-o", "font.size=10",
        "-e", "nvim",
    ]
    if readonly:
        args += ["-R", "-c", "set nonumber norelativenumber signcolumn=no laststatus=0"]
    args.append(path)
    subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def open_image_preview(path: str):
    # Match qtile float rule for imv (floating_layout Match(wm_class="imv"))
    subprocess.Popen(
        ["setsid", "imv", "-W", "820", "-H", "500", "-s", "shrink", path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

CSS_TEMPLATE = """
window#qdrop {{ background: transparent; }}
#qdrop-root {{
    background: {bg_alpha};
    border: 1px solid {border};
    border-radius: 12px;
    min-width: 440px;
}}
#qdrop-header {{
    padding: 8px 12px;
    background: {header_bg};
    border-bottom: 1px solid {border};
    border-radius: 12px 12px 0 0;
}}
#qdrop-title {{
    color: {fg}; font-weight: 600; font-size: 12px;
    margin-right: 14px;
}}
#qdrop-stats {{ margin-right: 10px; }}
#qdrop-stats box {{ margin-right: 4px; }}
#qdrop-stats label {{
    color: {accent}; font-family: monospace; font-size: 11px;
}}
button {{
    background: {btn_bg};
    color: {fg};
    border: 1px solid transparent;
    padding: 4px 10px;
    border-radius: 6px;
    font-size: 11px;
    margin-left: 6px;
}}
button:hover {{
    background: {hover_bg};
    color: {fg};
    border-color: {accent};
}}
button:disabled, button:disabled:hover {{
    opacity: 0.35;
    background: {btn_bg};
    color: {muted};
    border-color: transparent;
}}
button:disabled image {{ opacity: 0.35; }}
flowbox {{ padding: 8px; }}
flowboxchild {{
    padding: 6px;
    margin: 4px;
    border-radius: 8px;
    border: 1px solid transparent;
    min-width: 76px;
}}
flowboxchild:hover {{
    background: {btn_bg};
    border-color: {border};
}}
flowboxchild:selected {{
    background: {sel_bg};
    border-color: {accent};
}}
flowboxchild:selected:hover {{ background: {sel_bg_hover}; }}
flowboxchild label {{
    color: {fg}; font-size: 10px; margin-top: 2px;
}}
flowboxchild:selected label {{ color: {sel_fg}; }}
#qdrop-badge {{
    background: {accent}; color: {bg};
    border-radius: 3px; padding: 1px 5px;
    font-size: 8px; font-weight: 700; font-family: monospace;
}}
#qdrop-empty {{ color: {muted}; font-size: 12px; margin: 40px; }}
#qdrop-rubber {{
    background: {sel_bg}; border: 1px solid {accent};
    border-radius: 3px;
}}
"""


def _hex_rgba(hex_color: str, alpha: float) -> str:
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r}, {g}, {b}, {alpha})"


def _mix_hex(h1: str, h2: str, t: float) -> str:
    h1 = h1.lstrip("#"); h2 = h2.lstrip("#")
    r = int(int(h1[0:2],16) * (1-t) + int(h2[0:2],16) * t)
    g = int(int(h1[2:4],16) * (1-t) + int(h2[2:4],16) * t)
    b = int(int(h1[4:6],16) * (1-t) + int(h2[4:6],16) * t)
    return f"#{r:02x}{g:02x}{b:02x}"


def load_palette() -> dict:
    default = {
        "bg": "#1e1e2e", "header_bg": "#181825",
        "fg": "#cdd6f4", "muted": "#6c7086",
        "border": "#45475a", "btn_bg": "#313244", "btn_hover": "#45475a",
        "accent": "#89b4fa", "sel_fg": "#ffffff",
    }
    # Prefer semantic palette written by theme-apply. Falls back to wal.
    try:
        d = json.loads(QT_PALETTE.read_text())
        bg = d["bg"]; fg = d["fg"]
        bg_alt = d.get("bg_alt", _mix_hex(bg, fg, 0.08))
        accent = d.get("blue", d.get("green", default["accent"]))
        muted = _mix_hex(bg, fg, 0.35)
        return {
            "bg": bg, "header_bg": bg_alt, "fg": fg,
            "muted": muted, "border": muted,
            "btn_bg": _mix_hex(bg, fg, 0.15),
            "btn_hover": accent,
            "accent": accent, "sel_fg": fg,
        }
    except Exception:
        pass
    try:
        data = json.loads(WAL_COLORS.read_text())
        sp = data.get("special", {}); cols = data.get("colors", {})
        bg = sp.get("background", default["bg"])
        fg = sp.get("foreground", default["fg"])
        accent = cols.get("color4", cols.get("color6", default["accent"]))
        muted = _mix_hex(bg, fg, 0.35)
        return {
            "bg": bg, "header_bg": _mix_hex(bg, fg, 0.08), "fg": fg,
            "muted": muted, "border": muted,
            "btn_bg": _mix_hex(bg, fg, 0.15),
            "btn_hover": accent,
            "accent": accent, "sel_fg": fg,
        }
    except Exception:
        return default


def build_css() -> bytes:
    p = load_palette()
    subs = dict(p)
    subs["bg_alpha"] = _hex_rgba(p["bg"], 0.97)
    subs["header_bg"] = _hex_rgba(p["header_bg"], 0.9)
    subs["sel_bg"] = _hex_rgba(p["accent"], 0.20)
    subs["sel_bg_hover"] = _hex_rgba(p["accent"], 0.30)
    subs["hover_bg"] = _hex_rgba(p["accent"], 0.30)
    return CSS_TEMPLATE.format(**subs).encode()

# ═══════════════════════════════════════════════════════════════════
# State helpers
# ═══════════════════════════════════════════════════════════════════


def uri_to_path(uri: str) -> str | None:
    if not uri.startswith("file://"):
        return None
    try:
        return unquote(urlparse(uri).path)
    except Exception:
        return None


def load_state() -> list[dict]:
    try:
        data = json.loads(STATE_FILE.read_text())
        out = []
        for e in data:
            if not isinstance(e, dict) or "type" not in e or "value" not in e:
                continue
            if e["type"] not in ("file", "text", "url"):
                continue
            if e["type"] == "file" and not os.path.exists(e["value"]):
                continue
            e.setdefault("added_ts", 0)
            e.setdefault("pinned", False)
            out.append(e)
        return out
    except Exception:
        return []


def save_pixbuf(pixbuf) -> str | None:
    """Write clipboard/drop image data to IMG_DIR, return its path.

    Copying an image in a browser puts the *bitmap* on the clipboard
    (image/png), usually alongside the page URL as text. qdrop entries
    are paths/URLs/text, so the bitmap is saved to a real PNG and added
    as a file entry -- which also gets it a thumbnail, `imv` preview and
    drag-out-to-another-app for free.
    """
    try:
        IMG_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest = IMG_DIR / f"qdrop-{stamp}.png"
        n = 2
        while dest.exists():  # several pastes inside the same second
            dest = IMG_DIR / f"qdrop-{stamp}-{n}.png"
            n += 1
        pixbuf.savev(str(dest), "png", [], [])
        return str(dest)
    except Exception:
        return None


IMG_CACHE_MAX_AGE_S = 30 * 24 * 3600


def prune_image_cache(entries: list[dict]) -> int:
    """Drop saved-image files no entry refers to any more.

    Pasted images are written to IMG_DIR and only ever removed here --
    remove_entry() deliberately leaves the file alone, since the user may
    have dragged it somewhere else in the meantime. Age-gated so a file
    that was just saved can never be swept out from under a paste that
    hasn't finished being added yet.
    """
    kept = {e["value"] for e in entries}
    removed = 0
    try:
        cutoff = time.time() - IMG_CACHE_MAX_AGE_S
        for p in IMG_DIR.glob("qdrop-*.png"):
            if str(p) in kept:
                continue
            try:
                if p.stat().st_mtime < cutoff:
                    p.unlink()
                    removed += 1
            except OSError:
                continue
    except Exception:
        pass
    return removed


def save_state(entries: list[dict]) -> None:
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(entries))
    except Exception:
        pass


URL_RE = re.compile(r"^https?://\S+$")


def entry_badge(entry: dict) -> str:
    t = entry["type"]
    if t == "url":
        return "URL"
    if t == "text":
        return "TXT"
    p = entry["value"]
    ext = Path(p).suffix.lower()
    if os.path.isdir(p):
        return "DIR"
    if ext in IMG_EXT:
        return "IMG"
    if ext in DOC_EXT:
        return "DOC"
    return "FILE"


def entry_label(entry: dict) -> str:
    t = entry["type"]
    if t == "text":
        v = entry["value"].strip()
        first = v.splitlines()[0] if v else "(empty)"
        return first[:24] or "(empty)"
    if t == "url":
        # show host
        try:
            return urlparse(entry["value"]).netloc[:24] or entry["value"][:24]
        except Exception:
            return entry["value"][:24]
    return Path(entry["value"]).name


def entry_tooltip(entry: dict) -> str:
    if entry["type"] in ("text", "url"):
        return entry["value"][:400]
    return entry["value"]


def entry_sort_key(entry: dict, mode: str):
    pinned = 0 if entry.get("pinned") else 1  # pinned first
    if mode == "name":
        return (pinned, entry_label(entry).lower())
    if mode == "type":
        return (pinned, entry_badge(entry), entry_label(entry).lower())
    # date: newest first (larger ts first)
    return (pinned, -entry.get("added_ts", 0))


def detect_text_entry_type(txt: str) -> str:
    if URL_RE.match(txt.strip()):
        return "url"
    return "text"


# ═══════════════════════════════════════════════════════════════════
# Item widget
# ═══════════════════════════════════════════════════════════════════


class Item(Gtk.EventBox):
    def __init__(self, entry: dict, win: "Dropzone"):
        super().__init__()
        self.entry = entry
        self.win = win
        self._drag_active = False
        self._press_time = 0
        self.set_name("qdrop-item")
        self.set_above_child(False)
        self.set_size_request(76, 96)

        overlay = Gtk.Overlay()
        self.add(overlay)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        overlay.add(box)

        img = self._build_image()
        box.pack_start(img, False, False, 0)

        lbl = Gtk.Label(label=entry_label(entry))
        lbl.set_max_width_chars(10)
        lbl.set_ellipsize(3)
        box.pack_start(lbl, False, False, 0)

        # Skip badge on image entries (thumbnail already conveys type)
        if not (entry["type"] == "file" and Path(entry["value"]).suffix.lower() in IMG_EXT):
            badge = Gtk.Label(label=entry_badge(entry))
            badge.set_name("qdrop-badge")
            badge.set_halign(Gtk.Align.START)
            badge.set_valign(Gtk.Align.START)
            badge.set_margin_top(0)
            badge.set_margin_start(0)
            overlay.add_overlay(badge)

        if entry.get("pinned"):
            it = Gtk.IconTheme.get_default()
            for name in ("view-pin-symbolic", "starred-symbolic", "emblem-favorite-symbolic"):
                if it.has_icon(name):
                    pin = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.MENU)
                    break
            else:
                pin = Gtk.Label(label="★")
            pin.set_halign(Gtk.Align.END)
            pin.set_valign(Gtk.Align.START)
            # Margins stay >= 0: GTK3 has no CSS-style negative margins,
            # and the -4/-4 that used to be here made the 16x16 icon ask
            # to be allocated 20x20 -- refused, with a size warning
            # logged on every single pin/unpin and stats refresh.
            pin.set_margin_top(0)
            pin.set_margin_end(0)
            overlay.add_overlay(pin)

        self.set_tooltip_text(entry_tooltip(entry))

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
        self.connect("drag-begin", self._on_drag_begin)
        self.connect("drag-end", self._on_drag_end)
        self.connect("drag-data-get", self._on_get)
        self.connect("button-press-event", self._on_press)
        self.connect("button-release-event", self._on_release)

    def _build_image(self) -> Gtk.Image:
        img = Gtk.Image()
        e = self.entry
        if e["type"] == "file":
            path = e["value"]
            ext = Path(path).suffix.lower()
            if ext in IMG_EXT and os.path.isfile(path):
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        path, THUMB, THUMB, True
                    )
                    img.set_from_pixbuf(pb)
                    return img
                except Exception:
                    pass
            icon = "folder-symbolic" if os.path.isdir(path) else "text-x-generic-symbolic"
            img.set_from_icon_name(icon, Gtk.IconSize.DND)
        elif e["type"] == "url":
            img.set_from_icon_name("web-browser-symbolic", Gtk.IconSize.DND)
        else:
            img.set_from_icon_name("text-x-generic-symbolic", Gtk.IconSize.DND)
        img.set_pixel_size(THUMB)
        return img

    # --- drag ------------------------------------------------------

    def _selection_entries(self) -> list[dict]:
        fbc = self.get_parent()
        flow = fbc.get_parent() if fbc else None
        selected = flow.get_selected_children() if flow else []
        if fbc in selected and len(selected) > 1:
            return [c.get_child().entry for c in selected]
        return [self.entry]

    def _on_drag_begin(self, _w, _ctx):
        self._drag_active = True

    def _on_drag_end(self, _w, _ctx):
        # small delay so release handler sees drag_active
        GLib.timeout_add(50, lambda: setattr(self, "_drag_active", False) or False)

    def _on_get(self, _w, _ctx, data, info, _time):
        entries = self._selection_entries()
        if info == 0:
            uris = [Path(e["value"]).as_uri() for e in entries if e["type"] == "file"]
            if uris:
                data.set_uris(uris)
        else:
            parts = [e["value"] for e in entries]
            data.set_text("\n".join(parts), -1)

    # --- click -----------------------------------------------------

    def _on_press(self, _w, ev):
        self._press_time = ev.time
        if ev.type == Gdk.EventType._2BUTTON_PRESS and ev.button == 1:
            self._open()
            return True
        if ev.button == 3:
            self._menu(ev)
            return True
        if ev.button == 2:
            self.win.remove_entry(self.entry)
            return True
        # button 1: let drag_source handle threshold; on release we treat as click
        return False

    def _on_release(self, _w, ev):
        if ev.button != 1:
            return False
        if self._drag_active:
            return False
        fbc = self.get_parent()
        flow = fbc.get_parent() if fbc else None
        if not flow:
            return False
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        shift = ev.state & Gdk.ModifierType.SHIFT_MASK
        if ctrl:
            if fbc in flow.get_selected_children():
                flow.unselect_child(fbc)
            else:
                flow.select_child(fbc)
            self.win._select_anchor = fbc
        elif shift:
            # Standard range-select: extend from the last plain/ctrl
            # click (the "anchor") through this item, inclusive, in
            # visual/sorted order -- not just add this one item like
            # before.
            anchor = self.win._select_anchor
            children = flow.get_children()
            if anchor is not None and anchor in children:
                i1, i2 = children.index(anchor), children.index(fbc)
                lo, hi = (i1, i2) if i1 <= i2 else (i2, i1)
                flow.unselect_all()
                for c in children[lo : hi + 1]:
                    flow.select_child(c)
            else:
                flow.unselect_all()
                flow.select_child(fbc)
                self.win._select_anchor = fbc
        else:
            # single-select semantics
            flow.unselect_all()
            flow.select_child(fbc)
            self.win._select_anchor = fbc
        return True

    def _open(self):
        t = self.entry["type"]
        if t == "url":
            subprocess.Popen(
                ["xdg-open", self.entry["value"]],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            return
        if t == "text":
            fd, tmp = tempfile.mkstemp(prefix="qdrop-", suffix=".txt")
            with os.fdopen(fd, "w") as f:
                f.write(self.entry["value"])
            open_in_nvim(tmp)
            return
        path = self.entry["value"]
        ext = Path(path).suffix.lower()
        if ext in IMG_EXT and os.path.isfile(path):
            open_image_preview(path)
        elif is_text_file(path):
            open_in_nvim(path)
        else:
            subprocess.Popen(
                ["xdg-open", path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )

    def _copy_text(self, text: str):
        if shutil.which("xclip"):
            subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode())
        elif shutil.which("wl-copy"):
            subprocess.run(["wl-copy"], input=text.encode())

    def _menu(self, ev):
        menu = Gtk.Menu()
        t = self.entry["type"]

        def item(lbl, cb):
            mi = Gtk.MenuItem(label=lbl)
            mi.connect("activate", lambda *_: cb())
            menu.append(mi)
            return mi

        item("Open", self._open)
        if t == "file":
            item("Copy path", lambda: self._copy_text(self.entry["value"]))
            item("Reveal in file manager", lambda: subprocess.Popen(
                ["xdg-open", str(Path(self.entry["value"]).parent)]))
        elif t == "url":
            item("Copy URL", lambda: self._copy_text(self.entry["value"]))
        else:
            item("Copy text", lambda: self._copy_text(self.entry["value"]))

        # Send-to submenu
        menu.append(Gtk.SeparatorMenuItem())
        send_mi = Gtk.MenuItem(label="Send to")
        send_sub = Gtk.Menu()
        send_mi.set_submenu(send_sub)
        menu.append(send_mi)

        def add_send(lbl, cb):
            mi = Gtk.MenuItem(label=lbl)
            mi.connect("activate", lambda *_: cb())
            send_sub.append(mi)

        add_send("Email", self._send_email)
        add_send("Telegram", self._send_telegram)

        # Pin toggle
        menu.append(Gtk.SeparatorMenuItem())
        pin_lbl = "Unpin" if self.entry.get("pinned") else "Pin"
        item(pin_lbl, self._toggle_pin)

        item("Remove", lambda: self.win.remove_entry(self.entry))
        menu.connect("show", lambda *_: self.win._enter_modal())
        menu.connect("hide", lambda *_: self.win._exit_modal())
        menu.show_all()
        menu.popup_at_pointer(ev)

    def _toggle_pin(self):
        self.entry["pinned"] = not self.entry.get("pinned", False)
        save_state(self.win.entries)
        self.win.rebuild_flow()

    def _send_email(self):
        t = self.entry["type"]
        if t == "file":
            subprocess.Popen(["xdg-email", "--attach", self.entry["value"]])
        elif t == "url":
            subprocess.Popen(["xdg-email", "--body", self.entry["value"]])
        else:
            subprocess.Popen(["xdg-email", "--body", self.entry["value"]])

    def _send_telegram(self):
        t = self.entry["type"]
        if t == "file":
            # Telegram Desktop CLI doesn't accept file directly; open telegram and copy path
            self._copy_text(self.entry["value"])
            subprocess.Popen(["xdg-open", "tg://"])
        else:
            url = f"tg://msg?text={quote(self.entry['value'])}"
            subprocess.Popen(["xdg-open", url])


# ═══════════════════════════════════════════════════════════════════
# Window
# ═══════════════════════════════════════════════════════════════════


class FixedWidth(Gtk.Bin):
    """Container that always requests exactly `width`, whatever it holds.

    The window is set_resizable(False), so GTK sizes it to whatever its
    content asks for -- and the header is the widest thing in it. With
    the stats chips asking for their natural width directly, that
    request changed whenever the chips did: one more digit in a count,
    or the pinned chip appearing, silently resized the whole window.
    Pinning the strip's request makes the header's request constant, so
    the trailing spacer absorbs content changes instead of the window.

    A ScrolledWindow with min/max content width does the same job, but
    its viewport re-negotiates the *height* of what it holds, which
    squeezed the chip icons below their minimum (GTK size warnings on
    every stats update). Overriding the width request alone touches
    nothing else.
    """

    def __init__(self, width: int):
        super().__init__()
        self._width = width

    def do_get_preferred_width(self):
        return self._width, self._width

    def do_get_preferred_height(self):
        child = self.get_child()
        return child.get_preferred_height() if child else (0, 0)


class Dropzone(Gtk.Window):
    def __init__(self):
        super().__init__(title="qdrop")
        self.set_name("qdrop")
        self.set_wmclass("qdrop", "qdrop")
        self.set_default_size(WIN_W, WIN_H)
        self.set_size_request(WIN_W, -1)
        self.set_keep_above(True)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
        self.set_icon_name("edit-copy")
        self.set_resizable(False)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)
        self.set_app_paintable(True)

        # Lock width regardless of content; height stays flexible for slide anim.
        # WIN_W is only the floor here -- the real lock is applied from
        # the first size-allocate (_lock_width), because the header's own
        # minimum, not this constant, is what ultimately decides the
        # width, and it shifts a little with fonts/icon theme. Declaring
        # a max the window then exceeds (the old hint said 440 while the
        # window drew at 569) means the hint is simply a lie that the WM
        # is free to act on.
        geo = Gdk.Geometry()
        geo.min_width = WIN_W
        geo.max_width = WIN_W
        geo.min_height = 1
        geo.max_height = 4096
        self.set_geometry_hints(
            None, geo,
            Gdk.WindowHints.MIN_SIZE | Gdk.WindowHints.MAX_SIZE,
        )
        self._width_locked = False
        self.connect("size-allocate", self._lock_width)

        self.revealer = Gtk.Revealer()
        self.revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.revealer.set_transition_duration(REVEAL_MS)
        self.revealer.set_reveal_child(False)
        self.add(self.revealer)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.set_name("qdrop-root")
        root.set_size_request(WIN_W, -1)
        self.revealer.add(root)

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hdr.set_name("qdrop-header")
        title = Gtk.Label(label="qdrop")
        title.set_name("qdrop-title")
        title.set_xalign(0)
        hdr.pack_start(title, False, False, 0)
        self.stats_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.stats_box.set_name("qdrop-stats")
        stats_clip = FixedWidth(STATS_W)
        stats_clip.add(self.stats_box)
        hdr.pack_start(stats_clip, False, False, 0)
        # spacer between stats and buttons — absorbs slack instead of stretching stats
        hdr.pack_start(Gtk.Box(), True, True, 0)

        def make_btn(icon_name: str, tip: str, cb, label: str | None = None) -> Gtk.Button:
            b = Gtk.Button()
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
            box.pack_start(
                Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.SMALL_TOOLBAR),
                False, False, 0,
            )
            if label:
                box.pack_start(Gtk.Label(label=label), False, False, 0)
            b.add(box)
            b.set_relief(Gtk.ReliefStyle.NONE)
            b.set_tooltip_text(tip)
            b.connect("clicked", cb)
            return b

        # right-to-left order:
        close_b = make_btn("window-close-symbolic", "Close (Esc)",
                           lambda *_: self.hide_animated())
        hdr.pack_end(close_b, False, False, 0)

        self.clear_btn = make_btn(
            "user-trash-symbolic", "Clear all (Ctrl+L)",
            lambda *_: self._confirm_clear(),
        )
        hdr.pack_end(self.clear_btn, False, False, 0)

        self.export_btn = make_btn(
            "package-x-generic-symbolic", "Export selection as zip",
            lambda *_: self._export_selection(),
        )
        self.export_btn.set_sensitive(False)
        hdr.pack_end(self.export_btn, False, False, 0)

        sort_btn = Gtk.MenuButton()
        sbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        sbox.pack_start(
            Gtk.Image.new_from_icon_name("view-sort-descending-symbolic",
                                         Gtk.IconSize.SMALL_TOOLBAR),
            False, False, 0,
        )
        self.sort_lbl = Gtk.Label(label="")  # hidden; sort mode reflected via tooltip
        sort_btn.add(sbox)
        sort_btn.set_relief(Gtk.ReliefStyle.NONE)
        sort_btn.set_tooltip_text("Sort by")
        sort_btn.set_popup(self._build_sort_menu())
        hdr.pack_end(sort_btn, False, False, 0)

        paste_b = make_btn("edit-paste-symbolic", "Paste clipboard (Ctrl+V)",
                           lambda *_: self._paste_clipboard())
        hdr.pack_end(paste_b, False, False, 0)

        search_b = make_btn("system-search-symbolic", "Search (Ctrl+F)",
                            lambda *_: self._toggle_search())
        hdr.pack_end(search_b, False, False, 0)

        root.pack_start(hdr, False, False, 0)

        # Search bar (revealer)
        self.search_rev = Gtk.Revealer()
        self.search_rev.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.search_rev.set_transition_duration(150)
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Filter…")
        self.search_entry.connect("search-changed", lambda *_: self.flow.invalidate_filter())
        self.search_entry.connect("stop-search", lambda *_: self._toggle_search(False))
        self.search_rev.add(self.search_entry)
        root.pack_start(self.search_rev, False, False, 0)

        self.stack = Gtk.Stack()
        self.stack.set_size_request(WIN_W, WIN_H - 40)
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

        overlay = Gtk.Overlay()
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        overlay.add(scroll)
        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(6)
        self.flow.set_column_spacing(2)
        self.flow.set_row_spacing(2)
        self.flow.set_homogeneous(True)
        self.flow.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.flow.set_activate_on_single_click(False)
        self.flow.set_filter_func(self._filter_child)
        self.flow.set_sort_func(self._sort_children)
        self.flow.connect("button-press-event", self._on_flow_click)
        self.flow.connect("selected-children-changed", lambda *_: self._update_export_sensitivity())
        scroll.add(self.flow)
        # viewport catches clicks/motion in empty area for rubber-band
        vp = scroll.get_child()
        if vp is not None:
            vp.add_events(
                Gdk.EventMask.BUTTON_PRESS_MASK
                | Gdk.EventMask.BUTTON_RELEASE_MASK
                | Gdk.EventMask.POINTER_MOTION_MASK
            )
            vp.connect("button-press-event", self._on_bg_press)
            vp.connect("motion-notify-event", self._on_bg_motion)
            vp.connect("button-release-event", self._on_bg_release)

        # rubber-band overlay
        self.rubber = Gtk.Box()
        self.rubber.set_name("qdrop-rubber")
        self.rubber.set_halign(Gtk.Align.START)
        self.rubber.set_valign(Gtk.Align.START)
        self.rubber.set_no_show_all(True)
        overlay.add_overlay(self.rubber)
        overlay.set_overlay_pass_through(self.rubber, True)

        self._rb_active = False
        self._rb_start = (0, 0)  # flow-relative
        self._rb_viewport = vp
        self._rb_scroll = scroll

        self.stack.add_named(overlay, "items")

        # info 2 = raw image data. Listed first so GTK prefers it: an
        # image dragged out of a browser offers its bitmap *and* the page
        # URL, and taking the URL turns a dropped picture into a link.
        drop_targets = [
            Gtk.TargetEntry.new("image/png", 0, 2),
            Gtk.TargetEntry.new("image/jpeg", 0, 2),
            Gtk.TargetEntry.new("image/bmp", 0, 2),
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
        self.connect("delete-event", lambda *_: (self.hide_animated(), True)[1])
        self.connect("key-press-event", self._on_key)
        self.connect("enter-notify-event", self._on_enter)
        self.connect("leave-notify-event", self._on_leave)
        self.connect("focus-out-event", self._on_focus_out)

        self.entries: list[dict] = []
        self._hide_timer = 0
        self._visible = False
        self._hiding = False
        self._mapped = False  # has show_animated() ever actually mapped us?
        self._slide_timer = 0  # in-flight _slide_move() tick, 0 if idle
        self._show_pending = False  # first-show waiting on its allocation pass
        self._y = None  # last Y we moved to; None until first move()
        self._anim_gen = 0  # bumped by every show/hide, cancels stale callbacks
        self._sort_mode = "date"
        self._search_shown = False
        self._suspend_hide = 0  # count of active modals/menus
        self._select_anchor = None  # FlowBoxChild shift-click range starts from

        self._palette_mtime = 0.0
        self._apply_css()
        try:
            self._palette_mtime = (
                QT_PALETTE.stat().st_mtime if QT_PALETTE.exists() else WAL_COLORS.stat().st_mtime
            )
        except Exception:
            pass
        GLib.timeout_add_seconds(3, self._poll_palette)
        loaded = load_state()
        for e in loaded:
            self._add(e, persist=False, at_start=False)
        self._refresh()
        prune_image_cache(loaded)

    def _poll_palette(self):
        try:
            src = QT_PALETTE if QT_PALETTE.exists() else WAL_COLORS
            m = src.stat().st_mtime
        except Exception:
            return True
        if m != self._palette_mtime:
            self._palette_mtime = m
            self._apply_css()
        return True

    # --- css / positioning ----------------------------------------

    def _apply_css(self):
        if not hasattr(self, "_css_provider"):
            self._css_provider = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                self._css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )
        self._css_provider.load_from_data(build_css())

    def _target_xy(self):
        display = Gdk.Display.get_default()
        monitor = None
        try:
            seat = display.get_default_seat()
            pointer = seat.get_pointer()
            _, px, py = pointer.get_position()
            monitor = display.get_monitor_at_point(px, py)
        except Exception:
            pass
        if monitor is None:
            monitor = display.get_primary_monitor() or display.get_monitor(0)
        geo = monitor.get_geometry()
        w = max(WIN_W, self.get_allocated_width() or WIN_W)
        x = geo.x + (geo.width - w) // 2
        y = geo.y + int(geo.height * 0.055)
        return x, y

    def _lock_width(self, _w, alloc):
        """Freeze the width at whatever the first real allocation was.

        Everything inside now requests a content-independent width, so
        the first allocation is the width forever -- pin the geometry
        hints to it so the WM and GTK agree, instead of advertising a
        constant the window may not actually honour.
        """
        if self._width_locked or alloc.width <= 1:
            return
        self._width_locked = True
        geo = Gdk.Geometry()
        geo.min_width = geo.max_width = alloc.width
        geo.min_height = 1
        geo.max_height = 4096
        self.set_geometry_hints(
            None, geo,
            Gdk.WindowHints.MIN_SIZE | Gdk.WindowHints.MAX_SIZE,
        )

    def _restore_natural_size(self):
        """Undo a size imposed from outside (tiling, fullscreen).

        Nothing here ever resized the window back, so any size the WM
        forced on it became permanent:

          * Height. A tiled or fullscreened qdrop is configured to the
            layout's height (~714 on this screen). GTK keeps that size
            afterwards -- set_resizable(False) is only a request, and the
            WM had already overridden it -- so qdrop stayed full-height
            with two items in it.
          * Width. Worse, because _lock_width() pins the geometry hints to
            the *first* real allocation. If that first allocation happened
            while qtile had the window tiled, the wrong width is frozen
            into min_width/max_width and the WM then enforces it forever
            -- which is why it settled at ~531 rather than WIN_W (620).

        Recomputing from GTK's preferred size fixes both: preferred size
        is derived from the content's own requests, independent of
        whatever the window is currently sized to. The stale hints are
        rewritten first, since a max_width of 531 would otherwise block
        the resize back out to 620.
        """
        try:
            _, nat_w = self.get_preferred_width()
            _, nat_h = self.get_preferred_height()
            w = max(WIN_W, nat_w)
            h = max(WIN_H, nat_h)
            if self.get_size() == (w, h):
                return
            geo = Gdk.Geometry()
            geo.min_width = geo.max_width = w
            geo.min_height = 1
            geo.max_height = 4096
            self.set_geometry_hints(
                None, geo,
                Gdk.WindowHints.MIN_SIZE | Gdk.WindowHints.MAX_SIZE,
            )
            # Keep _width_locked set: _lock_width must not re-freeze the
            # hints from a subsequent allocation, or a single bad frame
            # would pin the wrong width again.
            self._width_locked = True
            self.resize(w, h)
        except Exception:
            pass

    def _place_top_center(self):
        x, y = self._target_xy()
        self._move(x, y)

    def _slide_move(self, x, y_from, y_to, duration_ms, on_done=None):
        # Manual position-based slide, not GTK's Revealer: the outer
        # window here has a fixed size_request on its content (see
        # self.stack.set_size_request), so it never actually resizes as
        # the Revealer's reveal_child toggles -- confirmed empirically
        # via `xdotool getwindowgeometry` polling showing a completely
        # static size through the whole transition, appearing/
        # disappearing effectively instantly regardless of
        # transition_duration. Animating the window's Y position
        # directly is reliable regardless of that Revealer/sizing
        # interaction and gives an unambiguous slide-from-the-top.
        #
        # Only one slide may ever be in flight: a second one started
        # while the first is still ticking used to leave both timers
        # alive, each calling move() with its own idea of where the
        # window belongs -- the two interleave every 16ms and the window
        # visibly vibrates between the two paths. Starting a slide
        # therefore cancels whatever was running (and drops its
        # on_done, so e.g. a hide that gets reversed mid-flight never
        # runs the callback that would mark us invisible).
        self._cancel_slide()
        steps = max(1, duration_ms // 16)  # ~60fps
        state = {"i": 0}

        def _step():
            state["i"] += 1
            t = min(1.0, state["i"] / steps)
            eased = 1 - (1 - t) ** 3  # ease-out cubic
            y = int(y_from + (y_to - y_from) * eased)
            self._move(x, y)
            if t >= 1.0:
                self._slide_timer = 0
                if on_done:
                    on_done()
                return False
            return True

        self._slide_timer = GLib.timeout_add(16, _step)

    def _cancel_slide(self):
        if self._slide_timer:
            GLib.source_remove(self._slide_timer)
            self._slide_timer = 0

    def _move(self, x, y):
        """move() that remembers where we put the window.

        Reversing an animation needs the *current* Y, and asking X for
        it (get_position()) round-trips and lags a frame behind the
        move() we just issued; tracking it here is exact and free.
        """
        self._y = y
        self.move(x, y)

    def _reversed_duration(self, y_from, y_to, full_span, full_ms) -> int:
        """Duration for a slide that starts partway along its path.

        Without this, reversing a nearly-finished animation replays the
        full duration over a few remaining pixels, which reads as a
        stall rather than a redirect.

        Floored at 6 frames' worth (96ms): _slide_move runs
        duration//16 steps and eases *out*, so a 3-frame slide puts 70%
        of the travel in its first frame -- which looks like a snap, the
        very thing scaling the duration was meant to avoid. Six frames
        keeps the first one down to ~40% of an already-short distance.
        """
        if full_span <= 0:
            return full_ms
        frac = min(1.0, abs(y_to - y_from) / float(full_span))
        return max(96, int(full_ms * frac))

    # --- menu / search / sort / export ----------------------------

    def _build_sort_menu(self) -> Gtk.Menu:
        menu = Gtk.Menu()
        for mode, lbl in [("date", "Date added"), ("name", "Name"), ("type", "Type")]:
            mi = Gtk.MenuItem(label=lbl)
            mi.connect("activate", lambda _w, m=mode: self._set_sort(m))
            menu.append(mi)
        menu.connect("show", lambda *_: self._enter_modal())
        menu.connect("hide", lambda *_: self._exit_modal())
        menu.show_all()
        return menu

    def _update_export_sensitivity(self):
        has_files = any(
            e["type"] == "file" and os.path.exists(e["value"])
            for e in self._selected_entries()
        )
        has_texts = any(e["type"] in ("text", "url") for e in self._selected_entries())
        self.export_btn.set_sensitive(bool(has_files or has_texts))

    def _confirm_clear(self):
        removable = [e for e in self.entries if not e.get("pinned")]
        if not removable:
            return
        dlg = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Clear {len(removable)} item(s)?",
        )
        dlg.format_secondary_text("Pinned items will be kept.")
        self._enter_modal()
        try:
            if dlg.run() == Gtk.ResponseType.YES:
                self.clear()
        finally:
            dlg.destroy()
            self._exit_modal()

    def _set_sort(self, mode: str):
        self._sort_mode = mode
        self.rebuild_flow()
        self._update_header_stats()

    def _sort_children(self, a, b):
        ea = a.get_child().entry
        eb = b.get_child().entry
        ka = entry_sort_key(ea, self._sort_mode)
        kb = entry_sort_key(eb, self._sort_mode)
        return (ka > kb) - (ka < kb)

    def _filter_child(self, child) -> bool:
        if not self._search_shown:
            return True
        q = self.search_entry.get_text().strip().lower()
        if not q:
            return True
        e = child.get_child().entry
        hay = entry_label(e).lower() + " " + str(e.get("value", "")).lower()
        return q in hay

    def _toggle_search(self, show=None):
        if show is None:
            show = not self._search_shown
        self._search_shown = show
        self.search_rev.set_reveal_child(show)
        if show:
            self.search_entry.grab_focus()
        else:
            self.search_entry.set_text("")
        self.flow.invalidate_filter()

    def rebuild_flow(self):
        self._select_anchor = None  # about to destroy every FlowBoxChild
        for c in self.flow.get_children():
            c.destroy()
        for e in self.entries:
            item = Item(e, self)
            self.flow.add(item)
        self.flow.show_all()
        self.flow.invalidate_sort()
        self.flow.invalidate_filter()
        self._refresh()

    def _export_selection(self):
        entries = self._selected_entries()
        if not entries:
            return
        files = [e["value"] for e in entries if e["type"] == "file" and os.path.exists(e["value"])]
        texts = [e for e in entries if e["type"] in ("text", "url")]
        if not files and not texts:
            return
        default_name = f"qdrop-{datetime.now().strftime('%Y%m%d-%H%M%S')}.zip"
        dlg = Gtk.FileChooserDialog(
            title="Export selection",
            parent=self,
            action=Gtk.FileChooserAction.SAVE,
        )
        dlg.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL,
            "Export", Gtk.ResponseType.OK,
        )
        dlg.set_current_name(default_name)
        dlg.set_current_folder(str(Path.home() / "Downloads"))
        dlg.set_do_overwrite_confirmation(True)
        self._enter_modal()
        try:
            if dlg.run() == Gtk.ResponseType.OK:
                dest = dlg.get_filename()
                self._write_zip(dest, files, texts)
                subprocess.Popen(["xdg-open", str(Path(dest).parent)])
        finally:
            dlg.destroy()
            self._exit_modal()

    def _write_zip(self, dest: str, files: list[str], texts: list[dict]):
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in files:
                arc = Path(p).name
                if os.path.isdir(p):
                    for root, _dirs, fs in os.walk(p):
                        for f in fs:
                            full = os.path.join(root, f)
                            zf.write(full, os.path.join(arc, os.path.relpath(full, p)))
                else:
                    zf.write(p, arc)
            for i, e in enumerate(texts):
                name = f"text-{i+1}.{'url.txt' if e['type'] == 'url' else 'txt'}"
                zf.writestr(name, e["value"])

    # --- show / hide ----------------------------------------------

    def _force_qtile_focus(self):
        # GTK present() alone doesn't reliably win focus after the
        # hide()+togroup()+remap dance in _sync_to_current_qtile_group()
        # below -- confirmed empirically: a same-group show (fast path,
        # no remap) always gets focus via present(), but a cross-group
        # show left focus on whatever was previously active even though
        # the window displayed correctly. Likely qtile's own
        # focus_on_window_activation="smart" policy declining to honor
        # what looks like a newly-(re)managed client's activation
        # request. Asking qtile directly to focus us -- as an explicit
        # command rather than a passive client request -- sidesteps that
        # policy entirely.
        try:
            from libqtile.command.client import InteractiveCommandClient
            gdk_win = self.get_window()
            if gdk_win is None:
                return
            InteractiveCommandClient().window[gdk_win.get_xid()].focus()
        except Exception:
            pass

    def _raise_above_all(self):
        # Keep qdrop floating and on top.
        #
        # FLOATING half: floating_layout has had Match(wm_class="qdrop")
        # for a while and it does match -- verified live, both
        # config.floating_layout.match() and the group's own clone return
        # True for this window. Despite that, qtile was observed holding
        # it at FloatStates.NOT_FLOATING, i.e. as a regular tiled client:
        # monadtall then gave it a column and *resized every other window*
        # to make room, which is the "layout affects qdrop" bug. The state
        # is transient (it reads FLOATING at other times), so the rule is
        # applied and then lost again somewhere in the hide()+togroup()+
        # remap dance this window does on every cross-group show.
        #
        # Rather than chase where it gets dropped, assert it on each show:
        # the rule is declarative and one-shot, this is idempotent.
        #
        # Guarded on the current state on purpose. enable_floating() ends
        # up in _enablefloating(), which place()s the window at its stored
        # float geometry -- calling it unconditionally mid-reveal would
        # snap the window out of the slide. Only the already-broken case
        # pays for the correction.
        try:
            from libqtile.command.client import InteractiveCommandClient
            gdk_win = self.get_window()
            if gdk_win is not None:
                c = InteractiveCommandClient()
                win = c.window[gdk_win.get_xid()]
                if not win.info().get("floating", False):
                    win.enable_floating()
                    # enable_floating() places the window at the float
                    # geometry qtile stored for it -- which, coming out of
                    # a tiled state, is the tiled size. Undo that here or
                    # the correction above would itself leave qdrop the
                    # wrong shape.
                    self._restore_natural_size()
        except Exception:
            pass

        # Restack qdrop to the top, so a fullscreen window underneath does
        # not swallow it.
        #
        # GTK's set_keep_above() (applied at construction) only sets the
        # _NET_WM_STATE_ABOVE hint, and qtile does not implement an
        # always-on-top layer for it. Meanwhile a client going fullscreen
        # is raised to the top of the X stack, so it ends up above qdrop.
        # Focus does not help either: qtile's X11 Window.focus() is just
        # _do_focus(), with no restacking at all -- which is why qdrop
        # appeared to "not open" over a fullscreen video or browser while
        # working fine everywhere else.
        #
        # bring_to_front() is deliberately the *only* thing done here. It
        # restacks this one window and touches nothing else: the window
        # underneath keeps its fullscreen state, and the tiling layout is
        # not re-run -- so every other window behaves exactly as it did.
        try:
            from libqtile.command.client import InteractiveCommandClient
            gdk_win = self.get_window()
            if gdk_win is None:
                return
            InteractiveCommandClient().window[gdk_win.get_xid()].bring_to_front()
        except Exception:
            pass

    def _sync_to_current_qtile_group(self):
        # qdrop is a persistent daemon window that stays mapped forever
        # (see hide_animated()), so it's permanently attached to whatever
        # qtile group it happened to be on when last (re)mapped --
        # switching workspaces just hides it like any other group-bound
        # window, so without this it only ever reappears on that one
        # group instead of wherever the user currently is.
        #
        # qtile's own togroup() (what the built-in scratchpad dropdowns
        # use for this exact "follow me to the current group" behavior)
        # unconditionally does a real X11 unmap + floating-layout
        # replacement pass. That's fine for ordinary clients, but it
        # silently invalidates GTK's own cached "am I mapped" bookkeeping
        # if GTK doesn't find out about it -- confirmed empirically: after
        # letting qtile togroup() us reactively (on every workspace
        # switch, via a hook), the window got permanently stuck refusing
        # to reappear. Being explicit here instead: call our own hide()
        # (a real, GTK-tracked unmap) BEFORE asking qtile to move us, then
        # let the normal first-time-show path in show_animated() below
        # do a full, clean remap into the new group -- exactly the same
        # dance already proven correct for the very first show ever.
        if not self._mapped:
            return
        try:
            from libqtile.command.client import InteractiveCommandClient
            c = InteractiveCommandClient()
            gdk_win = self.get_window()
            if gdk_win is None:
                return
            xid = gdk_win.get_xid()
            my_group = c.window[xid].info().get("group")
            current_group = c.group.info().get("name")
            if my_group is None or my_group == current_group:
                return
            self.hide()  # real GTK-tracked unmap before qtile touches it
            c.window[xid].togroup()
            self._mapped = False
        except Exception:
            pass

    def show_animated(self):
        self._anim_gen += 1
        gen = self._anim_gen

        if self._hiding:
            # Mid-close and asked to open again (shake during the close
            # animation, or a second toggle). Previously this returned
            # early, so the window finished closing and the request was
            # silently dropped. Reverse the slide instead: cancel the
            # close, keep every other bit of state as-is, and run back
            # down from wherever the window currently sits.
            self._cancel_slide()
            self._hiding = False
            self._visible = True
            x, target_y = self._target_xy()
            height = self.get_allocated_height() or WIN_H
            cur_y = self._y if self._y is not None else -height
            self._slide_move(
                x, cur_y, target_y,
                self._reversed_duration(cur_y, target_y, height, REVEAL_MS),
            )
            self.present()
            self._raise_above_all()
            self._reset_hide_timer()
            return

        # Before deciding "already open, nothing to do", make sure
        # "open" still means "open where the user is looking". qtile
        # unmaps windows that aren't on the current group, so after a
        # workspace switch self._visible is still True while nothing is
        # on screen; the early-out below would then swallow the request
        # and qdrop would never appear. Syncing first clears _mapped on
        # a cross-group move, which drops us through to the full
        # (re)map path underneath.
        self._sync_to_current_qtile_group()

        if self._visible and self._mapped and not self._anim_busy():
            # Already open and settled. A SHOW here (shake while the
            # window is up, a second keybind press, qdrop --show twice)
            # must NOT re-run the reveal: that teleports the window to
            # -height and slides it back down, which looks exactly like
            # it closed and reopened. Just keep it up and restart the
            # auto-hide countdown, which is the useful half of the
            # request.
            self.present()
            # Still re-raise: something may have gone fullscreen (or just
            # been raised) while qdrop sat open, burying it. A SHOW in
            # that state has to bring it back to the top.
            self._raise_above_all()
            self._reset_hide_timer()
            return

        if self._visible and self._anim_busy():
            # Open and still sliding down (or waiting on the first-show
            # allocation pass). Let the in-flight reveal finish rather
            # than restarting it from the top.
            self._reset_hide_timer()
            return

        self._visible = True
        self._refresh()
        self.revealer.set_reveal_child(True)  # content visible immediately;
        # the window's own Y position is what slides now, not the revealer.

        # After the content is built and revealed (so GTK's preferred size
        # reflects the real item count), and before _target_xy() reads the
        # width to center on.
        self._restore_natural_size()

        x, target_y = self._target_xy()

        if self._mapped:
            # Already mapped -- just sitting off-screen from a previous
            # hide_animated() (see there for why we no longer unmap on
            # hide). Real allocation is already known and stable, so
            # this is a plain slide with no remap involved at all: the
            # exact same mechanism as the close animation, just
            # reversed. This is also what makes the close animation
            # "perfect" and the old open path glitchy -- every
            # show_all()/present() after a real unmap re-triggers
            # qtile's floating-window placement logic (it re-centers
            # newly *mapped* clients), which raced against our move()
            # and produced a one-frame flash at screen-center before
            # jumping to the real start position. Never unmapping means
            # that placement logic only ever runs once, on the very
            # first show below.
            self.present()
            height = self.get_allocated_height() or WIN_H
            # -height, not target_y-height: bottom edge must land at
            # screen y=0 (fully off), not at target_y (~42px on-screen --
            # left a permanent sliver visible even while "hidden", masked
            # before only because the old code unmapped on hide).
            start_y = -height
            self._slide_move(x, start_y, target_y, REVEAL_MS)
            # This is the common path (every show after the first), and
            # the one where a fullscreen window underneath would otherwise
            # hide the whole reveal -- present() is only a GTK-level
            # activation request and does not restack under qtile.
            self._raise_above_all()
            self._reset_hide_timer()
            return

        # First-ever show: the window has never been realized, so we
        # don't know its real content height yet -- confirmed
        # empirically that get_preferred_size() under-reports it before
        # the window has ever been realized (e.g. reported ~160px for
        # content that allocates to 329px once mapped, because
        # Gtk.FlowBox doesn't settle row heights until a real
        # size-allocate pass happens). Using that estimate to place the
        # window off-screen used to start it only barely above the top
        # edge, so a chunk of it was visible immediately on show.
        #
        # Fix: map far off-screen at a sentinel Y first (guaranteed
        # fully hidden no matter what the real height turns out to be),
        # then once the window is actually realized/allocated (20ms
        # later), jump to the *real* start_y computed from the now-
        # accurate get_allocated_height() -- that jump is invisible
        # since it's off-screen -> off-screen -- and only then start the
        # visible slide down to target_y.
        SAFE_OFFSCREEN_Y = -4096
        # move() MUST happen before show_all()/present() on a window that's
        # not currently mapped. Reason (confirmed via qtile's
        # layout/floating.py compute_client_position): qtile only skips
        # its own center-on-screen placement for a newly-mapped floating
        # window if has_user_set_position() is true, which checks the
        # X11 WM_NORMAL_HINTS USPosition/PPosition flags. GTK only sets
        # that hint from move() when the window is still unrealized;
        # calling move() after show_all() (i.e. after the window is
        # already mapped) just issues a plain post-map ConfigureRequest
        # with no position hint, so qtile centers it on that first map
        # and only *then* honors the reposition -- producing a
        # one-frame flash at screen-center before the window jumps to
        # start_y and the slide animation begins. Moving first avoids
        # the center placement entirely instead of racing to correct it
        # after the fact. This dance only matters for this very first
        # map -- see the self._mapped branch above for every later show.
        self._move(x, SAFE_OFFSCREEN_Y)
        self.show_all()
        self.present()
        self._force_qtile_focus()
        self._raise_above_all()
        self._mapped = True
        self._show_pending = True

        def _begin_slide():
            self._show_pending = False
            # A HIDE (or another SHOW) can land inside this 20ms gap.
            # Without the generation check the window would obediently
            # slide into view right after being told to go away.
            if gen != self._anim_gen or not self._visible:
                return False
            x2, target_y2 = self._target_xy()
            h = self.get_allocated_height() or WIN_H
            start_y = -h  # bottom edge at screen y=0, fully off
            self._move(x2, start_y)  # off-screen -> off-screen, invisible
            self._slide_move(x2, start_y, target_y2, REVEAL_MS)
            return False

        GLib.timeout_add(20, _begin_slide)
        self._reset_hide_timer()

    def _anim_busy(self) -> bool:
        """Is a reveal/close transition still in flight?"""
        return bool(self._slide_timer) or self._show_pending

    def hide_animated(self):
        if not self._visible or self._hiding:
            return
        self._anim_gen += 1
        self._hiding = True
        self._show_pending = False  # abandon a not-yet-started reveal
        self._cancel_hide_timer()
        x, target_y = self._target_xy()
        height = self.get_allocated_height() or WIN_H
        end_y = -height  # bottom edge at screen y=0, fully off
        # Start from where the window actually is, not from target_y: a
        # HIDE landing mid-reveal (auto-hide racing the open animation,
        # or Esc pressed while it slides in) used to snap the window
        # down to its final resting place first and close from there,
        # which reads as a jump.
        start_y = self._y if self._y is not None else target_y
        start_y = max(end_y, min(start_y, target_y))
        duration = self._reversed_duration(start_y, end_y, height, HIDE_MS)

        def _finish():
            self._visible = False
            self._hiding = False
            # Deliberately NOT calling self.hide() (unmap): staying
            # mapped but off-screen is what lets the *next*
            # show_animated() be a plain slide instead of a real remap
            # -- see the _mapped branch there for why that matters.
            # skip_taskbar/skip_pager/UTILITY type-hint (set in
            # __init__) already keep a mapped-but-off-screen window out
            # of any WM chrome, so there's no visible downside.

        self._slide_move(x, start_y, end_y, duration, on_done=_finish)

    def toggle(self):
        # _hiding first: mid-close, "toggle" means bring it back, not
        # "it's still visible so hide it" (which the old ordering did --
        # a no-op, since hide_animated() bails while already hiding, so
        # a toggle during the close animation did nothing at all).
        if self._hiding:
            self.show_animated()
        elif self._visible:
            self.hide_animated()
        else:
            self.show_animated()

    def _reset_hide_timer(self):
        self._cancel_hide_timer()
        if self._suspend_hide:
            return
        self._hide_timer = GLib.timeout_add(AUTO_HIDE_MS, self._auto_hide)

    def _enter_modal(self):
        self._suspend_hide += 1
        self._cancel_hide_timer()

    def _exit_modal(self):
        if self._suspend_hide > 0:
            self._suspend_hide -= 1
        if not self._suspend_hide:
            self._reset_hide_timer()

    def _cancel_hide_timer(self):
        if self._hide_timer:
            GLib.source_remove(self._hide_timer)
            self._hide_timer = 0

    def _auto_hide(self):
        self._hide_timer = 0
        if self._suspend_hide:
            return False
        self.hide_animated()
        return False

    def _on_enter(self, _w, ev):
        if ev.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._cancel_hide_timer()
        return False

    def _on_leave(self, _w, ev):
        if ev.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._reset_hide_timer()
        return False

    def _on_focus_out(self, *_):
        # Keep alive if pointer inside (may lose keyboard focus to menu etc.)
        return False

    # --- keyboard --------------------------------------------------

    def _on_key(self, _w, ev):
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        shift = ev.state & Gdk.ModifierType.SHIFT_MASK
        k = ev.keyval
        search_focused = self.get_focus() is self.search_entry

        if k == Gdk.KEY_Escape:
            if self._search_shown:
                self._toggle_search(False)
                return True
            if self.flow.get_selected_children():
                self._deselect_all()
                return True
            self.hide_animated()
            return True

        # while typing in search, let entry handle everything except our shortcuts
        if search_focused and not ctrl:
            return False

        if k == Gdk.KEY_Delete or k == Gdk.KEY_BackSpace:
            if search_focused:
                return False
            self._remove_selected()
            return True
        if k in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if search_focused:
                return False
            self._open_selected()
            return True
        if ctrl and k in (Gdk.KEY_a, Gdk.KEY_A):
            if shift:
                self._deselect_all()
            else:
                self._select_all()
            return True
        if ctrl and k in (Gdk.KEY_l, Gdk.KEY_L):
            self._confirm_clear()
            return True
        if ctrl and k in (Gdk.KEY_c, Gdk.KEY_C):
            self._copy_selected()
            return True
        if ctrl and k in (Gdk.KEY_v, Gdk.KEY_V):
            self._paste_clipboard()
            return True
        if ctrl and k in (Gdk.KEY_f, Gdk.KEY_F):
            self._toggle_search(True)
            return True
        return False

    def _paste_clipboard(self, cb=None):
        # cb is injectable so the tests can drive a private selection
        # instead of clobbering the real clipboard.
        if cb is None:
            cb = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        added = False
        uris = cb.wait_for_uris()
        if uris:
            for u in uris:
                p = uri_to_path(u)
                if p and os.path.exists(p) and not any(
                    e["type"] == "file" and e["value"] == p for e in self.entries
                ):
                    self._add({"type": "file", "value": p})
                    added = True
        if not added:
            # Before the text branch: an image copied from a web page
            # offers both image/png and the page URL as text, and the
            # text always won -- pasting a picture stored a link.
            pixbuf = cb.wait_for_image()
            if pixbuf is not None:
                path = save_pixbuf(pixbuf)
                if path:
                    self._add({"type": "file", "value": path})
                    added = True
        if not added:
            txt = cb.wait_for_text()
            if txt and txt.strip():
                self._add({"type": detect_text_entry_type(txt), "value": txt})
                added = True
        if added:
            self._refresh()

    def _on_flow_click(self, flow, ev):
        if ev.button != 1:
            return False
        child = flow.get_child_at_pos(int(ev.x), int(ev.y))
        if child is None:
            flow.unselect_all()
        return False

    # --- rubber-band selection -----------------------------------

    def _flow_coords_from_viewport(self, vx: float, vy: float) -> tuple[float, float]:
        """Viewport widget coords → flow-relative coords (accounts for scroll offset)."""
        vp = self._rb_viewport
        # get flow allocation relative to viewport
        ok, fx, fy = self.flow.translate_coordinates(vp, 0, 0)
        if not ok:
            return vx, vy
        return vx - fx, vy - fy

    def _on_bg_press(self, _w, ev):
        if ev.button != 1:
            return False
        # Deselect any current selection unless Ctrl held
        if not (ev.state & Gdk.ModifierType.CONTROL_MASK):
            self.flow.unselect_all()
        fx, fy = self._flow_coords_from_viewport(ev.x, ev.y)
        self._rb_active = True
        self._rb_start = (fx, fy)
        self._rb_add_mode = bool(ev.state & Gdk.ModifierType.CONTROL_MASK)
        self._rb_initial_selection = set(
            id(c) for c in self.flow.get_selected_children()
        )
        self._update_rubber(fx, fy)
        self.rubber.show()
        return False

    def _on_bg_motion(self, _w, ev):
        if not self._rb_active:
            return False
        fx, fy = self._flow_coords_from_viewport(ev.x, ev.y)
        self._update_rubber(fx, fy)
        return False

    def _on_bg_release(self, _w, ev):
        if not self._rb_active or ev.button != 1:
            return False
        self._rb_active = False
        self.rubber.hide()
        return False

    def _update_rubber(self, cx: float, cy: float):
        sx, sy = self._rb_start
        x, y = int(min(sx, cx)), int(min(sy, cy))
        w, h = int(abs(cx - sx)), int(abs(cy - sy))
        # position rubber inside overlay (overlay ~ scroll area)
        # translate flow coords back to overlay coords via viewport
        vp = self._rb_viewport
        ok, ox, oy = self.flow.translate_coordinates(self._rb_scroll, x, y)
        if not ok:
            ox, oy = x, y
        self.rubber.set_margin_start(max(0, ox))
        self.rubber.set_margin_top(max(0, oy))
        self.rubber.set_size_request(max(1, w), max(1, h))
        self._apply_rubber_selection(x, y, x + w, y + h)

    def _apply_rubber_selection(self, x1: int, y1: int, x2: int, y2: int):
        for fbc in self.flow.get_children():
            alloc = fbc.get_allocation()
            ax1, ay1 = alloc.x, alloc.y
            ax2, ay2 = ax1 + alloc.width, ay1 + alloc.height
            intersects = not (ax2 < x1 or ax1 > x2 or ay2 < y1 or ay1 > y2)
            if intersects:
                self.flow.select_child(fbc)
            else:
                if not self._rb_add_mode or id(fbc) not in self._rb_initial_selection:
                    self.flow.unselect_child(fbc)

    # --- selection ops --------------------------------------------

    def _select_all(self):
        self.flow.select_all()

    def _deselect_all(self):
        self.flow.unselect_all()

    def _selected_entries(self) -> list[dict]:
        return [c.get_child().entry for c in self.flow.get_selected_children()]

    def _remove_selected(self):
        for e in self._selected_entries():
            self.remove_entry(e, refresh=False)
        self._refresh()

    def _open_selected(self):
        for c in self.flow.get_selected_children():
            c.get_child()._open()

    def _copy_selected(self):
        entries = self._selected_entries()
        if not entries:
            return
        text = "\n".join(
            e["value"] if e["type"] == "text" else e["value"]
            for e in entries
        )
        if shutil.which("xclip"):
            subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode())
        elif shutil.which("wl-copy"):
            subprocess.run(["wl-copy"], input=text.encode())

    # --- drop / add -----------------------------------------------

    def _on_drop(self, _w, _ctx, _x, _y, data, info, _time):
        added = False
        if info == 2:
            pixbuf = data.get_pixbuf()
            if pixbuf is not None:
                path = save_pixbuf(pixbuf)
                if path:
                    self._add({"type": "file", "value": path})
                    added = True
        elif info == 0:
            for uri in (data.get_uris() or []):
                p = uri_to_path(uri)
                if p is None and uri.startswith(("http://", "https://")):
                    # Remote URI (dragging an image straight off a web
                    # page often offers only this). Keep it as a URL
                    # entry -- it used to be skipped outright, so the
                    # drop silently did nothing at all.
                    if not any(e["value"] == uri for e in self.entries):
                        self._add({"type": "url", "value": uri})
                        added = True
                    continue
                if not p or not os.path.exists(p):
                    continue
                if any(e["type"] == "file" and e["value"] == p for e in self.entries):
                    continue
                self._add({"type": "file", "value": p})
                added = True
        else:
            txt = data.get_text()
            if txt and txt.strip():
                self._add({"type": detect_text_entry_type(txt), "value": txt})
                added = True
        if added:
            self._refresh()

    def add_text(self, txt: str):
        if not txt or not txt.strip():
            return
        self._add({"type": detect_text_entry_type(txt), "value": txt})
        self._refresh()

    def _add(self, entry: dict, persist: bool = True, at_start: bool = True):
        entry.setdefault("added_ts", time.time())
        entry.setdefault("pinned", False)
        if at_start:
            self.entries.insert(0, entry)
        else:
            self.entries.append(entry)
        item = Item(entry, self)
        self.flow.add(item)  # sort_func decides position
        self.flow.show_all()
        self.flow.invalidate_sort()
        if persist:
            save_state(self.entries)

    def remove_entry(self, entry: dict, refresh: bool = True):
        try:
            self.entries.remove(entry)
        except ValueError:
            return
        for fbc in self.flow.get_children():
            child = fbc.get_child()
            if getattr(child, "entry", None) is entry:
                if fbc is self._select_anchor:
                    self._select_anchor = None
                fbc.destroy()
                break
        save_state(self.entries)
        if refresh:
            self._refresh()

    def clear(self):
        # keep pinned
        keep = [e for e in self.entries if e.get("pinned")]
        remove = [e for e in self.entries if not e.get("pinned")]
        self.entries = keep
        for fbc in self.flow.get_children():
            if fbc.get_child().entry in remove:
                fbc.destroy()
        save_state(self.entries)
        self._refresh()

    def _refresh(self):
        self._update_header_stats()
        name = "items" if self.entries else "empty"
        child = self.stack.get_child_by_name(name)
        if child is None:
            return
        # show() before set_visible_child(): a Gtk.Stack silently ignores
        # a request to switch to a child that isn't visible yet, and
        # nothing in __init__ has been shown at the point the saved
        # entries are loaded. So the very first show_animated() ran
        # show_all(), at which point the stack picked its *first* page
        # ("empty") on its own -- qdrop came up empty despite having
        # entries, and only looked right on the second open, once
        # _refresh() ran again with the pages finally visible.
        child.show()
        self.stack.set_visible_child(child)

    def _update_header_stats(self):
        for c in self.stats_box.get_children():
            c.destroy()
        n_files = sum(1 for e in self.entries if e["type"] == "file")
        n_text = sum(1 for e in self.entries if e["type"] == "text")
        n_url = sum(1 for e in self.entries if e["type"] == "url")
        n_pin = sum(1 for e in self.entries if e.get("pinned"))

        def pick(*names: str) -> str:
            it = Gtk.IconTheme.get_default()
            for n in names:
                if it.has_icon(n):
                    return n
            return names[-1]

        def chip(icon: str, count: int, tip: str):
            b = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
            img = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU)
            img.set_pixel_size(14)
            b.pack_start(img, False, False, 0)
            lbl = Gtk.Label(label=str(count))
            b.pack_start(lbl, False, False, 0)
            b.set_tooltip_text(tip)
            self.stats_box.pack_start(b, False, False, 0)

        total_icon = pick("view-app-grid-symbolic", "applications-utilities-symbolic",
                          "view-grid-symbolic", "view-list-symbolic")
        chip(total_icon, len(self.entries), "Total items")
        chip(pick("folder-documents-symbolic", "text-x-generic-symbolic"),
             n_files, "Files")
        chip(pick("accessories-text-editor-symbolic", "text-editor-symbolic"),
             n_text, "Text notes")
        chip(pick("emblem-web-symbolic", "applications-internet-symbolic",
                  "web-browser-symbolic"),
             n_url, "URLs")
        if n_pin:
            chip(pick("view-pin-symbolic", "starred-symbolic",
                      "emblem-favorite-symbolic"),
                 n_pin, "Pinned")
        self.stats_box.show_all()

        if hasattr(self, "sort_lbl"):
            self.sort_lbl.set_text({"date": "Date", "name": "Name", "type": "Type"}[self._sort_mode])


# ═══════════════════════════════════════════════════════════════════
# Socket IPC
# ═══════════════════════════════════════════════════════════════════


def _handle_cmd(win: Dropzone, cmd: str):
    parts = cmd.split(maxsplit=1)
    op = parts[0].upper() if parts else ""
    arg = parts[1] if len(parts) > 1 else ""

    def apply():
        if op == "SHOW":
            win.show_animated()
        elif op == "HIDE":
            win.hide_animated()
        elif op == "TOGGLE":
            win.toggle()
        elif op == "ADD-TEXT":
            win.add_text(arg)
        elif op == "RELOAD":
            win._apply_css()
        elif op == "STATUS":
            pass
        return False

    GLib.idle_add(apply)


def _serve(win: Dropzone):
    try:
        SOCK_PATH.unlink()
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(str(SOCK_PATH))
    os.chmod(SOCK_PATH, 0o600)
    srv.listen(4)
    while True:
        try:
            conn, _ = srv.accept()
            data = conn.recv(65536).decode(errors="replace").strip()
            _handle_cmd(win, data)
            conn.sendall(b"OK\n")
            conn.close()
        except Exception:
            time.sleep(0.05)


def _send_cmd(cmd: str, timeout: float = 0.5) -> bool:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(str(SOCK_PATH))
        s.sendall(cmd.encode())
        s.recv(64)
        s.close()
        return True
    except Exception:
        return False


# ═══════════════════════════════════════════════════════════════════
# Entry
# ═══════════════════════════════════════════════════════════════════


def _client(cmd: str) -> int:
    if _send_cmd(cmd):
        return 0
    # daemon not running: spawn + retry
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    for _ in range(40):
        time.sleep(0.05)
        if _send_cmd(cmd):
            return 0
    print("qdrop daemon did not start", file=sys.stderr)
    return 1


def _daemon() -> int:
    lock_fp = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("qdrop already running", file=sys.stderr)
        return 0

    win = Dropzone()
    t = threading.Thread(target=_serve, args=(win,), daemon=True)
    t.start()
    win.connect("destroy", Gtk.main_quit)
    Gtk.main()
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="qdrop")
    p.add_argument("--toggle", action="store_true")
    p.add_argument("--show", action="store_true")
    p.add_argument("--hide", action="store_true")
    p.add_argument("--add-text", metavar="TXT")
    p.add_argument("--reload", action="store_true", help="reload theme from wal")
    p.add_argument("--status", action="store_true")
    args = p.parse_args()

    if args.toggle:
        return _client("TOGGLE")
    if args.show:
        return _client("SHOW")
    if args.hide:
        return _client("HIDE")
    if args.add_text is not None:
        return _client(f"ADD-TEXT {args.add_text}")
    if args.reload:
        return _client("RELOAD")
    if args.status:
        ok = _send_cmd("STATUS")
        print("running" if ok else "not running")
        return 0 if ok else 1

    return _daemon()


if __name__ == "__main__":
    sys.exit(main())
