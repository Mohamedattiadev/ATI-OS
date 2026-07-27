#!/usr/bin/env python3
"""qupdate — floating pending-updates picker for qtile.

Lists pending pacman + AUR updates (via `paru -Qu`), lets user check
which to update, then runs update in a floating alacritty. Themed from
wal palette. Singleton via file lock.

CLI:
  qupdate.py            open window (single instance)
  qupdate.py --refresh  refresh package DB, then open

Wired from qtile CheckUpdates widget Button1.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


def shutil_which(cmd: str):
    return shutil.which(cmd)

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

UID = os.getuid()
LOCK_FILE = Path(f"/tmp/qupdate-{UID}.lock")
SOCK_PATH = Path(f"/tmp/qupdate-{UID}.sock")
CACHE_FILE = Path.home() / ".cache" / "qupdate.json"
QT_PALETTE = Path.home() / ".cache" / "qtile" / "current_palette.json"
WAL_COLORS = Path.home() / ".cache" / "wal" / "colors.json"

WIN_W = 620
WIN_H = 480
FADE_MS = 180
FADE_STEPS = 16

CSS_TEMPLATE = """
window#qupdate {{ background: transparent; }}
#qupdate-root {{
    background: {bg_alpha};
    border: 1px solid {border};
    border-radius: 12px;
}}
#qupdate-header {{
    padding: 10px 14px;
    background: {header_bg};
    border-bottom: 1px solid {border};
    border-radius: 12px 12px 0 0;
}}
#qupdate-subhdr {{
    padding: 8px 14px;
    background: {header_bg};
    border-bottom: 1px solid {border};
}}
stackswitcher button {{
    background: transparent;
    border: 1px solid transparent;
    margin: 0 4px;
    padding: 4px 12px;
    color: {muted};
}}
stackswitcher button:hover {{ color: {fg}; }}
stackswitcher button:checked {{
    background: {sel_bg};
    color: {fg};
    border-color: {accent};
}}
#qupdate-title {{
    color: {fg}; font-weight: 700; font-size: 13px;
}}
#qupdate-count {{
    color: {accent}; font-family: monospace; font-size: 11px;
    margin-left: 10px;
}}
#qupdate-footer {{
    padding: 10px 14px;
    background: {header_bg};
    border-top: 1px solid {border};
    border-radius: 0 0 12px 12px;
}}
button {{
    background: {btn_bg};
    color: {fg};
    border: 1px solid transparent;
    padding: 5px 11px;
    border-radius: 6px;
    font-size: 11px;
    margin-left: 6px;
}}
button:hover {{
    background: {hover_bg};
    color: {fg};
    border-color: {accent};
}}
button.suggested-action {{
    background: {accent};
    color: {bg};
    font-weight: 700;
    border-color: transparent;
}}
button.suggested-action:hover {{
    background: {accent}; color: {bg};
    border-color: {fg};
    opacity: 0.9;
}}
button:disabled {{ opacity: 0.4; }}
checkbutton label {{ color: {fg}; font-size: 11px; }}
row {{
    padding: 6px 12px;
    border-bottom: 1px solid {border};
    min-height: 28px;
}}
row:selected {{ background: {sel_bg}; }}
row label {{ color: {fg}; font-size: 11px; }}
row.aur label#pkg {{ color: {accent}; }}
#pkg {{ font-weight: 600; font-family: monospace; }}
#ver {{ color: {fg}; font-family: monospace; font-size: 10px; margin-left: 8px; opacity: 0.85; }}
#badge {{
    background: {accent}; color: {bg};
    border-radius: 3px; padding: 1px 6px;
    font-size: 8px; font-weight: 700; font-family: monospace;
    margin: 0 8px;
}}
#qupdate-search entry {{
    background: {btn_bg}; color: {fg};
    border: 1px solid {border}; border-radius: 6px;
    padding: 4px 8px;
}}
#qupdate-loading {{
    color: {muted}; font-size: 12px; margin: 60px;
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
        "accent": "#89b4fa",
    }
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
            "btn_hover": accent, "accent": accent,
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
            "btn_hover": accent, "accent": accent,
        }
    except Exception:
        return default


def build_css() -> bytes:
    p = load_palette()
    subs = dict(p)
    subs["bg_alpha"] = _hex_rgba(p["bg"], 0.97)
    subs["header_bg"] = _hex_rgba(p["header_bg"], 0.9)
    subs["sel_bg"] = _hex_rgba(p["accent"], 0.18)
    subs["hover_bg"] = _hex_rgba(p["accent"], 0.30)
    return CSS_TEMPLATE.format(**subs).encode()


# ═══════════════════════════════════════════════════════════════════
# Package fetch
# ═══════════════════════════════════════════════════════════════════


def _run(cmd: list[str], timeout: int = 30) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except Exception:
        return ""


def fetch_updates(refresh: bool) -> list[dict]:
    """Return [{name, oldver, newver, aur}]. Parallel query."""
    if refresh:
        subprocess.run(["paru", "-Sy"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=60)

    aur_out: dict[str, str] = {}
    all_out: dict[str, str] = {}

    def get_all():
        all_out["v"] = _run(["paru", "-Qu"], 30)

    def get_aur():
        aur_out["v"] = _run(["paru", "-Qua"], 15)

    t1 = threading.Thread(target=get_all)
    t2 = threading.Thread(target=get_aur)
    t1.start(); t2.start()
    t1.join(); t2.join()

    aur_names: set[str] = set()
    for line in aur_out.get("v", "").splitlines():
        parts = line.split()
        if parts:
            aur_names.add(parts[0])

    out = []
    for line in all_out.get("v", "").splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "->":
            out.append({
                "name": parts[0],
                "oldver": parts[1],
                "newver": parts[3],
                "aur": parts[0] in aur_names,
            })
    return out


def _installed_names() -> set[str]:
    out = _run(["pacman", "-Qq"], 10)
    return set(l.strip() for l in out.splitlines() if l.strip())


def _parse_ss(text: str, installed: set[str], aur_source: bool) -> list[dict]:
    hits: list[dict] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        head = lines[i]
        if not head or head[0] == " ":
            i += 1
            continue
        parts = head.split()
        if not parts or "/" not in parts[0]:
            i += 1
            continue
        repo, name = parts[0].split("/", 1)
        aur = aur_source or repo.lower() == "aur"
        desc = ""
        if i + 1 < len(lines) and lines[i + 1].startswith((" ", "\t")):
            desc = lines[i + 1].strip()
            i += 2
        else:
            i += 1
        hits.append({
            "name": name,
            "aur": aur,
            "desc": desc,
            "installed": name in installed,
        })
    return hits


def paru_search(query: str, timeout: int = 15) -> list[dict]:
    """Search repo (pacman) + AUR (paru). Repo via pacman avoids
    paru's 'too many results' limit for common queries."""
    installed = _installed_names()
    repo_out = _run(["pacman", "-Ss", "--", query], timeout)
    hits = _parse_ss(repo_out, installed, aur_source=False)

    # Only query AUR when the term is specific enough to avoid the
    # "too many results" error.
    if len(query) >= 3:
        try:
            r = subprocess.run(
                ["paru", "-Ssa", "--", query],
                capture_output=True, text=True, timeout=timeout,
            )
            if r.returncode == 0 and r.stdout:
                hits.extend(_parse_ss(r.stdout, installed, aur_source=True))
        except Exception:
            pass

    # Dedupe by name (prefer repo entry over AUR duplicate)
    seen: set[str] = set()
    unique: list[dict] = []
    for h in hits:
        if h["name"] in seen:
            continue
        seen.add(h["name"])
        unique.append(h)
        if len(unique) >= 300:
            break
    return unique


def load_cache() -> list[dict]:
    try:
        return json.loads(CACHE_FILE.read_text())
    except Exception:
        return []


def save_cache(pkgs: list[dict]):
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps(pkgs))
    except Exception:
        pass


# ═══════════════════════════════════════════════════════════════════
# Window
# ═══════════════════════════════════════════════════════════════════


class Updater(Gtk.Window):
    def __init__(self):
        super().__init__(title="qupdate")
        self.set_name("qupdate")
        self.set_wmclass("qupdate", "qupdate")
        self.set_default_size(WIN_W, WIN_H)
        self.set_keep_above(True)
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)
        self.set_app_paintable(True)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.set_name("qupdate-root")
        self.add(root)

        # header
        # --- header: title + tab switcher + close ---
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hdr.set_name("qupdate-header")
        title = Gtk.Label(label="qupdate")
        title.set_name("qupdate-title")
        title.set_xalign(0)
        hdr.pack_start(title, False, False, 0)

        self.tab_stack = Gtk.Stack()
        self.tab_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.tab_stack.set_transition_duration(140)
        self.tab_stack.connect("notify::visible-child", lambda *_: self._on_tab_switch())

        switcher = Gtk.StackSwitcher()
        switcher.set_stack(self.tab_stack)
        switcher.set_halign(Gtk.Align.CENTER)
        hdr.pack_start(switcher, True, True, 0)

        close_btn = Gtk.Button(label="×")
        close_btn.set_tooltip_text("Close (Esc)")
        close_btn.connect("clicked", lambda *_: self.close_win())
        hdr.pack_end(close_btn, False, False, 0)

        root.pack_start(hdr, False, False, 0)

        # --- tabs ---
        self.tab_stack.add_titled(self._build_updates_page(), "updates", "Updates")
        self.tab_stack.add_titled(self._build_install_page(), "install", "Install")
        root.pack_start(self.tab_stack, True, True, 0)

        # --- footer (contextual per tab) ---
        ftr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        ftr.set_name("qupdate-footer")

        cancel = Gtk.Button(label="Close")
        cancel.connect("clicked", lambda *_: self.close_win())
        ftr.pack_start(cancel, False, False, 0)

        info_btn = Gtk.Button(label="?")
        info_btn.set_tooltip_text("What is paru / yay / pacman / dcli?")
        info_btn.connect("clicked", lambda *_: self._show_info())
        ftr.pack_start(info_btn, False, False, 0)

        self.bg_check = Gtk.CheckButton(label="Run in background")
        self.bg_check.set_tooltip_text(
            "No terminal. Auto-confirm. Notifies when done. "
            "AUR review skipped (safe for repo pkgs, less safe for AUR)."
        )
        ftr.pack_start(self.bg_check, False, False, 0)

        self.sel_lbl = Gtk.Label(label="")
        self.sel_lbl.set_xalign(1)
        ftr.pack_start(self.sel_lbl, True, True, 0)

        # Updates-tab actions
        self.update_sel_btn = Gtk.Button(label="Update selected")
        self.update_sel_btn.get_style_context().add_class("suggested-action")
        self.update_sel_btn.set_sensitive(False)
        self.update_sel_btn.connect("clicked", lambda *_: self._run_update(only_selected=True))
        ftr.pack_end(self.update_sel_btn, False, False, 0)

        has_dcli = shutil_which("dcli")
        self.tool_combo = Gtk.ComboBoxText()
        if has_dcli:
            self.tool_combo.append("dcli", "dcli sync")
        self.tool_combo.append("paru", "paru -Syu")
        self.tool_combo.append("pacman", "sudo pacman -Syu")
        self.tool_combo.set_active(0)
        self.tool_combo.set_tooltip_text(
            "dcli sync — declarative (uses arch-config modules, "
            "timeshift snapshot). paru — AUR + repo. pacman — repo only."
        )
        ftr.pack_end(self.tool_combo, False, False, 0)

        self.update_all_btn = Gtk.Button(label="Full upgrade")
        self.update_all_btn.set_tooltip_text(
            "Upgrade all pending packages using the tool at right."
        )
        self.update_all_btn.connect("clicked", lambda *_: self._run_update(only_selected=False))
        ftr.pack_end(self.update_all_btn, False, False, 0)

        # Install-tab action
        self.install_btn = Gtk.Button(label="Install selected")
        self.install_btn.get_style_context().add_class("suggested-action")
        self.install_btn.set_sensitive(False)
        self.install_btn.connect("clicked", lambda *_: self._run_install())
        ftr.pack_end(self.install_btn, False, False, 0)

        root.pack_start(ftr, False, False, 0)

        self.connect("key-press-event", self._on_key)
        self.connect("delete-event", lambda *_: (self.close_win(), True)[1])
        self.connect("destroy", Gtk.main_quit)

        self._apply_css()
        self._palette_mtime = 0.0
        try:
            src = QT_PALETTE if QT_PALETTE.exists() else WAL_COLORS
            self._palette_mtime = src.stat().st_mtime
        except Exception:
            pass
        GLib.timeout_add_seconds(3, self._poll_palette)
        self.rows: list[Gtk.ListBoxRow] = []
        self._pkgs: list[dict] = []

        # Show cache immediately if present
        cached = load_cache()
        if cached:
            self._populate(cached)
            self.count_lbl.set_text(f"{len(cached)} package(s) (cached · refreshing)")
        else:
            self.stack.set_visible_child_name("loading")
        self._start_fetch(refresh=False)
        self._on_tab_switch()  # set initial button visibility

    # --- tab builders ---

    def _build_updates_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bar.set_name("qupdate-subhdr")
        page.pack_start(bar, False, False, 0)

        self.count_lbl = Gtk.Label(label="…")
        self.count_lbl.set_name("qupdate-count")
        self.count_lbl.set_xalign(0)
        bar.pack_start(self.count_lbl, True, True, 0)

        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.set_tooltip_text("Sync package DB (paru -Sy)")
        refresh_btn.connect("clicked", lambda *_: self._refresh(True))
        bar.pack_end(refresh_btn, False, False, 0)

        none_btn = Gtk.Button(label="None")
        none_btn.connect("clicked", lambda *_: self._set_all(False))
        bar.pack_end(none_btn, False, False, 0)

        all_btn = Gtk.Button(label="All")
        all_btn.connect("clicked", lambda *_: self._set_all(True))
        bar.pack_end(all_btn, False, False, 0)

        self.search = Gtk.SearchEntry()
        self.search.set_name("qupdate-search")
        self.search.set_placeholder_text("Filter…")
        self.search.connect("search-changed",
                            lambda *_: self.listbox.invalidate_filter())
        bar.pack_end(self.search, False, False, 0)

        self.stack = Gtk.Stack()
        page.pack_start(self.stack, True, True, 0)

        loading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        loading.set_valign(Gtk.Align.CENTER)
        loading.set_halign(Gtk.Align.CENTER)
        sp = Gtk.Spinner(); sp.start()
        loading.pack_start(sp, False, False, 0)
        ll = Gtk.Label(label="Loading updates…")
        ll.set_name("qupdate-loading")
        loading.pack_start(ll, False, False, 0)
        self.stack.add_named(loading, "loading")

        empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        empty.set_valign(Gtk.Align.CENTER)
        empty.set_halign(Gtk.Align.CENTER)
        ei = Gtk.Image.new_from_icon_name("emblem-ok-symbolic", Gtk.IconSize.DIALOG)
        ei.set_pixel_size(48)
        empty.pack_start(ei, False, False, 0)
        el = Gtk.Label(label="System is up to date")
        el.set_name("qupdate-loading")
        empty.pack_start(el, False, False, 0)
        self.stack.add_named(empty, "empty")

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self.listbox.set_filter_func(self._filter_row)
        scroll.add(self.listbox)
        self.stack.add_named(scroll, "list")

        return page

    def _build_install_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bar.set_name("qupdate-subhdr")
        page.pack_start(bar, False, False, 0)

        self.install_search = Gtk.SearchEntry()
        self.install_search.set_name("qupdate-search")
        self.install_search.set_placeholder_text("Search packages…")
        self.install_search.set_size_request(320, -1)
        self.install_search.connect("search-changed", lambda *_: self._schedule_install_search())
        bar.pack_start(self.install_search, True, True, 0)

        self.install_status_lbl = Gtk.Label(label="")
        self.install_status_lbl.set_name("qupdate-count")
        self.install_status_lbl.set_xalign(1)
        bar.pack_end(self.install_status_lbl, False, False, 0)

        self.install_stack = Gtk.Stack()
        page.pack_start(self.install_stack, True, True, 0)

        hint = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hint.set_valign(Gtk.Align.CENTER)
        hint.set_halign(Gtk.Align.CENTER)
        hi = Gtk.Image.new_from_icon_name("system-search-symbolic", Gtk.IconSize.DIALOG)
        hi.set_pixel_size(48)
        hint.pack_start(hi, False, False, 0)
        hl = Gtk.Label(label="Type to search official repos + AUR")
        hl.set_name("qupdate-loading")
        hint.pack_start(hl, False, False, 0)
        self.install_stack.add_named(hint, "hint")

        loading2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        loading2.set_valign(Gtk.Align.CENTER)
        loading2.set_halign(Gtk.Align.CENTER)
        sp2 = Gtk.Spinner(); sp2.start()
        loading2.pack_start(sp2, False, False, 0)
        ll2 = Gtk.Label(label="Searching…")
        ll2.set_name("qupdate-loading")
        loading2.pack_start(ll2, False, False, 0)
        self.install_stack.add_named(loading2, "loading")

        no_hits = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        no_hits.set_valign(Gtk.Align.CENTER)
        no_hits.set_halign(Gtk.Align.CENTER)
        ni = Gtk.Image.new_from_icon_name("action-unavailable-symbolic",
                                          Gtk.IconSize.DIALOG)
        ni.set_pixel_size(48)
        no_hits.pack_start(ni, False, False, 0)
        no_hits.pack_start(Gtk.Label(label="No matching packages"),
                           False, False, 0)
        self.install_stack.add_named(no_hits, "no_hits")

        scroll2 = Gtk.ScrolledWindow()
        scroll2.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.install_listbox = Gtk.ListBox()
        self.install_listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll2.add(self.install_listbox)
        self.install_stack.add_named(scroll2, "list")

        self.install_stack.set_visible_child_name("hint")
        self._install_search_timer = 0
        self._install_search_seq = 0
        self._install_rows: list[Gtk.ListBoxRow] = []
        return page

    def _on_tab_switch(self):
        tab = self.tab_stack.get_visible_child_name() or "updates"
        is_upd = tab == "updates"
        for w in (self.update_sel_btn, self.update_all_btn, self.tool_combo):
            w.set_no_show_all(True)
            w.set_visible(is_upd)
        self.install_btn.set_no_show_all(True)
        self.install_btn.set_visible(not is_upd)
        if is_upd:
            self._update_sel_state()
        else:
            self._update_install_sel_state()

    # --- install: search + run ---

    def _schedule_install_search(self):
        if self._install_search_timer:
            GLib.source_remove(self._install_search_timer)
        self._install_search_timer = GLib.timeout_add(350, self._run_install_search)

    def _run_install_search(self):
        self._install_search_timer = 0
        q = self.install_search.get_text().strip()
        if len(q) < 2:
            self.install_stack.set_visible_child_name("hint")
            self.install_status_lbl.set_text("")
            return False
        self.install_stack.set_visible_child_name("loading")
        self.install_status_lbl.set_text("searching…")
        self._install_search_seq += 1
        seq = self._install_search_seq

        def worker():
            hits = paru_search(q, timeout=15)
            GLib.idle_add(self._populate_install, seq, hits)

        threading.Thread(target=worker, daemon=True).start()
        return False

    def _populate_install(self, seq: int, hits: list[dict]):
        if seq != self._install_search_seq:
            return False
        for r in self._install_rows:
            r.destroy()
        self._install_rows.clear()
        n = len(hits)
        self.install_status_lbl.set_text(f"{n} result(s)")
        if not hits:
            self.install_stack.set_visible_child_name("no_hits")
            self._update_install_sel_state()
            return False

        # rank: exact match → prefix → contains, then repo before AUR,
        # not-installed before installed, shorter name first
        q = self.install_search.get_text().strip().lower()

        def rank(h: dict):
            name = h["name"].lower()
            if name == q:
                exact = 0
            elif name.startswith(q):
                exact = 1
            elif q in name:
                exact = 2
            else:
                exact = 3
            return (exact, int(h["aur"]), int(h.get("installed", False)),
                    len(name))

        hits.sort(key=rank)

        for h in hits:
            self._install_rows.append(self._make_install_row(h))
        self.install_stack.set_visible_child_name("list")
        self.install_listbox.show_all()
        self._update_install_sel_state()
        return False

    def _make_install_row(self, pkg: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        if pkg["aur"]:
            row.get_style_context().add_class("aur")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add(box)

        cb = Gtk.CheckButton()
        cb.set_active(False)
        cb.connect("toggled", lambda *_: self._update_install_sel_state())
        box.pack_start(cb, False, False, 0)

        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name = Gtk.Label(label=pkg["name"])
        name.set_name("pkg")
        name.set_xalign(0)
        name.set_ellipsize(3)
        top.pack_start(name, False, False, 0)

        badge = Gtk.Label(label="AUR" if pkg["aur"] else "PKG")
        badge.set_name("badge")
        badge.set_valign(Gtk.Align.CENTER)
        top.pack_start(badge, False, False, 0)

        if pkg.get("installed"):
            inst = Gtk.Label(label="installed")
            inst.set_name("ver")
            top.pack_end(inst, False, False, 0)

        v.pack_start(top, False, False, 0)

        desc = Gtk.Label(label=pkg.get("desc", ""))
        desc.set_name("ver")
        desc.set_xalign(0)
        desc.set_ellipsize(3)
        desc.set_max_width_chars(80)
        v.pack_start(desc, False, False, 0)

        box.pack_start(v, True, True, 0)

        row.pkg = pkg
        row.checkbox = cb
        self.install_listbox.add(row)
        return row

    def _install_selected(self) -> list[dict]:
        return [r.pkg for r in self._install_rows if r.checkbox.get_active()]

    def _update_install_sel_state(self):
        n = len(self._install_selected())
        if self.tab_stack.get_visible_child_name() == "install":
            self.sel_lbl.set_text(f"{n} selected")
        self.install_btn.set_sensitive(n > 0)

    def _run_install(self):
        pkgs = [p["name"] for p in self._install_selected()]
        if not pkgs:
            return
        base = "paru -S --needed"
        args = " ".join(pkgs)
        if self.bg_check.get_active():
            self._run_background(base, args)
        else:
            self._run_terminal(base, args)
        self.close_win()

    # --- css / palette ---

    def _apply_css(self):
        if not hasattr(self, "_css_provider"):
            self._css_provider = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                self._css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )
        self._css_provider.load_from_data(build_css())

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

    # --- keyboard ---

    def _on_key(self, _w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            self.close_win()
            return True
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and ev.keyval in (Gdk.KEY_a, Gdk.KEY_A):
            self._set_all(True)
            return True
        if ctrl and ev.keyval in (Gdk.KEY_f, Gdk.KEY_F):
            self.search.grab_focus()
            return True
        return False

    def close_win(self):
        self.hide()

    def show_win(self):
        self.show_all()
        self.present()
        self._start_fetch(refresh=False)

    # --- fetch ---

    def _start_fetch(self, refresh: bool):
        self.stack.set_visible_child_name("loading")
        self.count_lbl.set_text("…")

        def worker():
            try:
                pkgs = fetch_updates(refresh)
            except Exception:
                pkgs = []
            GLib.idle_add(self._populate, pkgs)

        threading.Thread(target=worker, daemon=True).start()

    def _refresh(self, sync: bool):
        self._start_fetch(refresh=sync)

    def _populate(self, pkgs: list[dict]):
        for r in self.rows:
            r.destroy()
        self.rows.clear()
        self._pkgs = pkgs
        n_aur = sum(1 for p in pkgs if p["aur"])
        n_repo = len(pkgs) - n_aur
        self.count_lbl.set_text(
            f"{len(pkgs)} package(s)  ({n_repo} repo · {n_aur} AUR)"
        )
        save_cache(pkgs)

        if not pkgs:
            self.stack.set_visible_child_name("empty")
            self._update_sel_state()
            return

        for p in pkgs:
            self.rows.append(self._make_row(p))
        self.stack.set_visible_child_name("list")
        self.listbox.show_all()
        self._update_sel_state()
        return False

    def _make_row(self, pkg: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        if pkg["aur"]:
            row.get_style_context().add_class("aur")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add(box)

        cb = Gtk.CheckButton()
        cb.set_active(False)
        cb.connect("toggled", lambda *_: self._update_sel_state())
        box.pack_start(cb, False, False, 0)

        name = Gtk.Label(label=pkg["name"])
        name.set_name("pkg")
        name.set_xalign(0)
        name.set_ellipsize(3)
        name.set_width_chars(20)
        box.pack_start(name, False, False, 0)

        badge_wrap = Gtk.Box()
        badge = Gtk.Label(label="AUR" if pkg["aur"] else "PKG")
        badge.set_name("badge")
        badge.set_valign(Gtk.Align.CENTER)
        badge_wrap.pack_start(badge, False, False, 0)
        box.pack_start(badge_wrap, False, False, 0)

        # spacer
        box.pack_start(Gtk.Box(), True, True, 0)

        ver = Gtk.Label(label=f"{pkg['oldver']}  →  {pkg['newver']}")
        ver.set_name("ver")
        ver.set_xalign(1)
        ver.set_ellipsize(3)
        ver.set_max_width_chars(40)
        box.pack_end(ver, False, False, 0)

        row.pkg = pkg
        row.checkbox = cb
        self.listbox.add(row)
        return row

    def _filter_row(self, row) -> bool:
        q = self.search.get_text().strip().lower()
        if not q:
            return True
        return q in row.pkg["name"].lower()

    def _set_all(self, checked: bool):
        for r in self.rows:
            r.checkbox.set_active(checked)

    def _selected(self) -> list[dict]:
        return [r.pkg for r in self.rows if r.checkbox.get_active()]

    def _update_sel_state(self):
        n = len(self._selected())
        if self.tab_stack.get_visible_child_name() != "install":
            self.sel_lbl.set_text(f"{n} selected")
        self.update_sel_btn.set_sensitive(n > 0)

    # --- run update ---

    def _run_update(self, only_selected: bool):
        if only_selected:
            pkgs = [p["name"] for p in self._selected()]
            if not pkgs:
                return
            base = "paru -S --needed"
            args = " ".join(pkgs)
            bg_noconfirm = "--noconfirm"
        else:
            tool = self.tool_combo.get_active_id() or "paru"
            if tool == "dcli":
                base = "dcli sync"
            elif tool == "pacman":
                base = "sudo pacman -Syu"
            else:
                base = "paru -Syu"
            args = ""
            bg_noconfirm = "--noconfirm" if tool != "dcli" else ""

        if self.bg_check.get_active():
            self._run_background(base, args, bg_noconfirm)
        else:
            self._run_terminal(base, args)
        self.close_win()

    def _run_terminal(self, base: str, args: str):
        cmd = f"{base} {args}".strip()
        shell = (
            f'{cmd}; echo; echo "---"; '
            f'echo "Done. Press Enter to close."; read'
        )
        subprocess.Popen(
            [
                "setsid", "alacritty",
                "--class", "clip-view", "--title", "qupdate-run",
                "-o", "window.dimensions.columns=90",
                "-o", "window.dimensions.lines=24",
                "-o", "window.padding.x=8",
                "-o", "window.padding.y=8",
                "-o", "font.size=10",
                "-e", "sh", "-c", shell,
            ],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    def _run_background(self, base: str, args: str, noconfirm: str = "--noconfirm"):
        log = f"/tmp/qupdate-{UID}-run.log"
        cmd = f"{base} {noconfirm} {args}".strip()
        shell = (
            f'echo "$ {cmd}" > {log}; '
            f'({cmd}) >> {log} 2>&1; '
            f'if [ $? -eq 0 ]; then '
            f'  notify-send -a qupdate -i emblem-ok "Update complete" "See {log}"; '
            f'else '
            f'  notify-send -a qupdate -u critical -i dialog-error '
            f'    "Update failed" "See {log}"; '
            f'fi'
        )
        subprocess.Popen(
            ["setsid", "sh", "-c", shell],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        subprocess.Popen(
            ["notify-send", "-a", "qupdate", "-i", "system-software-update",
             "qupdate", "Update started in background"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _show_info(self):
        dlg = Gtk.MessageDialog(
            transient_for=self, modal=True,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.CLOSE,
            text="pacman vs yay vs paru",
        )
        dlg.format_secondary_markup(
            "<b>pacman</b> — Arch's native package manager. Handles official repos only.\n"
            "<b>yay</b> — AUR helper. Wraps pacman + builds AUR packages from source.\n"
            "<b>paru</b> — Newer AUR helper (rewrite of yay in Rust). Faster + more features.\n"
            "<b>dcli</b> — Declarative wrapper. Reads ~/.config/arch-config/modules/*.yaml, "
            "syncs to that state, and takes a timeshift snapshot before every run.\n\n"
            "qupdate defaults to <b>dcli sync</b> for full-upgrades so your snapshots + module "
            "state stay in sync. For picking specific packages it uses <b>paru</b> "
            "(covers both repo + AUR in one call)."
        )
        dlg.run()
        dlg.destroy()


# ═══════════════════════════════════════════════════════════════════
# Entry
# ═══════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════
# Socket IPC
# ═══════════════════════════════════════════════════════════════════


def _handle_cmd(win: "Updater", cmd: str):
    op = cmd.strip().upper()

    def apply():
        if op == "SHOW":
            win.show_win()
        elif op == "HIDE":
            win.close_win()
        elif op == "TOGGLE":
            if win.get_visible():
                win.close_win()
            else:
                win.show_win()
        elif op == "REFRESH":
            win.show_win()
            win._refresh(True)
        elif op == "STATUS":
            pass
        return False

    GLib.idle_add(apply)


def _serve(win: "Updater"):
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
            data = conn.recv(4096).decode(errors="replace").strip()
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


def _client(cmd: str) -> int:
    if _send_cmd(cmd):
        return 0
    subprocess.Popen(
        [sys.executable, os.path.abspath(__file__)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    for _ in range(50):
        time.sleep(0.05)
        if _send_cmd(cmd):
            return 0
    print("qupdate daemon did not start", file=sys.stderr)
    return 1


def _daemon(show_now: bool) -> int:
    lock_fp = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("qupdate already running", file=sys.stderr)
        return 0

    win = Updater()
    if show_now:
        win.show_all()
    t = threading.Thread(target=_serve, args=(win,), daemon=True)
    t.start()
    Gtk.main()
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="qupdate")
    p.add_argument("--show", action="store_true")
    p.add_argument("--hide", action="store_true")
    p.add_argument("--toggle", action="store_true")
    p.add_argument("--refresh", action="store_true")
    p.add_argument("--status", action="store_true")
    p.add_argument("--daemon", action="store_true",
                   help="start hidden (autostart usage)")
    args = p.parse_args()

    if args.status:
        ok = _send_cmd("STATUS")
        print("running" if ok else "not running")
        return 0 if ok else 1
    if args.show:
        return _client("SHOW")
    if args.hide:
        return _client("HIDE")
    if args.toggle:
        return _client("TOGGLE")
    if args.refresh:
        return _client("REFRESH")

    # no flag: legacy behaviour = spawn window (via daemon)
    return _daemon(show_now=not args.daemon)


if __name__ == "__main__":
    sys.exit(main())
