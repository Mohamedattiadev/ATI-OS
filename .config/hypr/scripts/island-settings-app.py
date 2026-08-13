#!/usr/bin/env python3
"""island-settings-app — the full settings surface for Tide Island.

WHY THIS EXISTS AND WHY IT IS NOT THE ISLAND PANEL
--------------------------------------------------
The island's own SettingsLayer is not a smaller version of this app that
could be grown into it. It is a different thing with a hard constraint:
it lives under a Hyprland keyboard grab, so it cannot own a text entry —
a field there would swallow the next character typed into the focused
window. That is why the four font families, the wallpaper folder and
every other free-text key had no row at all until `island-settings.py`
grew the `string`/`path`/`font` types and the `panel` flag.

So the division is not "simple vs advanced". It is:

    SettingsLayer   the 25 rows that can be driven by arrow keys alone
    this app        all 30, including the 5 that need a keyboard

WHY IT SHELLS OUT INSTEAD OF READING THE JSON
---------------------------------------------
`island-settings.py` is the only thing that writes userconfig.json, and
this app does not become a second writer. Every commit here is a
`--set`, which means this app inherits, for free and without a copy:

  * the atomic temp-file-and-rename write that ForkConfig.qml's watcher
    depends on (a truncate-in-place gives it a real chance to parse half
    a file),
  * the type coercion, so a spin button cannot store "35" where the C++
    backend expects 35 and silently gets 0,
  * the fc-match font check,
  * the clamping, the enum membership test, the list de-duplication.

A GUI that wrote JSON itself would have to reimplement all of it, and
would drift on the first schema change. The cost is a subprocess per
commit, which is ~50 ms on a control the user has just released.

Reads are `--list`, which reports each row's descriptor, its CURRENT
value, whether the island panel can render it, and for fonts whether the
family actually resolves.
"""

import json
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk, Pango  # noqa: E402

CTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "island-settings.py")

# Grouping lives HERE rather than in the schema, and that is a deliberate
# trade rather than an oversight.
#
# A `group` field on all 30 rows would be the tidier answer and would put
# presentation into a file whose entire job is to be the machine-readable
# contract between four consumers. Grouping is this app's opinion about
# layout; the schema should not have to hold an opinion about a window it
# does not know exists.
#
# The failure mode is bounded on purpose: a key missing from this table
# lands in "Other" and is still fully editable. It cannot vanish, which is
# the only outcome that would matter.
GROUPS = [
    ("Shape", "The notch itself — geometry, position, and how much screen it claims.", [
        "forkNotchMode", "islandHeight", "islandWidth", "islandTopMargin",
        "islandExclusiveZone", "islandPositionX", "islandBackgroundOpacity",
    ]),
    ("Typography", "Families and sizes. Families are checked against fontconfig before they are written.", [
        "textFontFamily", "timeFontFamily", "heroFontFamily", "iconFontFamily",
        "bodyFontSize", "titleFontSize", "iconFontSize",
    ]),
    ("Behaviour", "What the island does when you click it, hover it, or leave it alone.", [
        "dynamicIslandPrimaryAction", "dynamicIslandSecondaryAction",
        "hoverExpandAction", "islandAutoHideEnabled", "islandAutoHideDelayMs",
        "islandShowWorkspaceOnAutoHide", "disableAutoExpandOnTrackChange",
    ]),
    ("Content", "What it shows, and in what order.", [
        "clockFormat", "dynamicIslandLeftSwipeItems", "forkRestingEqEnabled",
        "forkModeKeysEnabled",
    ]),
    ("Effects", "Animations and alternate surfaces.", [
        "forkThemeTransitionEnabled", "forkRingOsdEnabled",
    ]),
    # "and", not "&": AdwPreferencesGroup titles are parsed as Pango markup,
    # so a bare ampersand is an unterminated entity and the whole title is
    # dropped with a warning rather than escaped.
    ("Wallpaper and theme", "Where wallpapers come from and who owns the palette.", [
        "wallpaperLibraryPath", "wallpaperPywalEnabled",
    ]),
    ("System", "Privileged actions.", [
        "tlpPermissionMode",
    ]),
]


def run_ctl(args):
    """(ok, parsed-json-or-None, stderr-text). Never raises for a bad exit."""
    try:
        proc = subprocess.run(
            [sys.executable, CTL] + args,
            capture_output=True, text=True, timeout=20)
    except (subprocess.SubprocessError, OSError) as exc:
        return False, None, str(exc)

    payload = None
    if proc.stdout.strip():
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            payload = None

    if proc.returncode != 0:
        # island-settings.py reports failures as {"ok": false, "error": ...}
        # on stdout, so prefer that over stderr when it is there.
        if isinstance(payload, dict) and payload.get("error"):
            return False, payload, payload["error"]
        return False, payload, proc.stderr.strip() or "exit %d" % proc.returncode

    return True, payload, proc.stderr.strip()


class SettingsWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Island Settings")
        self.set_default_size(880, 760)

        self.rows = []          # descriptors from --list
        self.widgets = {}       # key -> the Adw row, for rebuilding after a write
        self.suppress = False   # True while we are setting widget state ourselves

        self.toasts = Adw.ToastOverlay()
        self.search = Gtk.SearchEntry(placeholder_text="Search settings, keys and descriptions")
        self.search.connect("search-changed", lambda *_: self.apply_filter())

        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="Island Settings",
                                                subtitle="Tide Island"))

        reload_button = Gtk.Button(icon_name="view-refresh-symbolic",
                                   tooltip_text="Re-read from disk")
        reload_button.connect("clicked", lambda *_: self.reload())
        header.pack_end(reload_button)

        search_bar = Gtk.SearchBar(search_mode_enabled=True)
        search_bar.set_child(self.search)
        search_bar.set_key_capture_widget(self)

        # NOT wrapped in a Gtk.ScrolledWindow. AdwPreferencesPage already
        # contains one, and nesting a second scroller inside it gives the
        # inner one an unbounded height to scroll within — the window then
        # opens part-way down the page instead of at the top, which is how
        # this was caught: the first screenshot showed the fourth group.
        self.page = Adw.PreferencesPage(hexpand=True, vexpand=True)

        self.banner = Adw.Banner(revealed=False)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(search_bar)
        content.append(self.banner)
        content.append(self.page)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(header)
        toolbar.set_content(content)

        self.toasts.set_child(toolbar)
        self.set_content(self.toasts)

        self.reload()

    # ---- data ------------------------------------------------------

    def reload(self):
        ok, payload, err = run_ctl(["--list"])
        if not ok or not isinstance(payload, dict):
            self.banner.set_title("Could not read the schema: %s" % (err or "unknown"))
            self.banner.set_revealed(True)
            return

        self.rows = payload.get("settings", [])
        warnings = payload.get("warnings", [])
        self.config_path = payload.get("path", "")

        if warnings:
            self.banner.set_title("settings-extra.json: " + "; ".join(warnings))
            self.banner.set_revealed(True)
        else:
            self.banner.set_revealed(False)

        self.build()

    def commit(self, key, raw, on_error_restore):
        """--set, then re-read. Reverts the widget if the CLI refused."""
        ok, payload, err = run_ctl(["--set", key, str(raw)])
        if not ok:
            self.toasts.add_toast(Adw.Toast(title=err or "write refused", timeout=6))
            self.suppress = True
            try:
                on_error_restore()
            finally:
                self.suppress = False
            return False

        # Re-read rather than patching our copy: a --set re-reads
        # settings-extra.json too, so the row list can legitimately change
        # shape underneath a write, and a locally patched value would then
        # disagree with the file it claims to show.
        #
        # DEFERRED to the next main-loop iteration, because reload() rebuilds
        # every group and this function is reached from a widget's own signal
        # handler — destroying the widget whose callback is still on the stack
        # is how you get a use-after-free rather than a refresh.
        GLib.idle_add(self._reload_once, priority=GLib.PRIORITY_DEFAULT_IDLE)
        return True

    def _reload_once(self):
        self.reload()
        return GLib.SOURCE_REMOVE

    def value_of(self, key):
        for row in self.rows:
            if row["key"] == key:
                return row.get("value")
        return None

    def default_of(self, key):
        for row in self.rows:
            if row["key"] == key:
                return row.get("default")
        return None

    # ---- ui --------------------------------------------------------

    def build(self):
        for group in list(self.groups_built()):
            self.page.remove(group)

        self._groups = []
        self.widgets = {}

        by_key = {row["key"]: row for row in self.rows}
        placed = set()

        for title, description, keys in GROUPS:
            present = [by_key[k] for k in keys if k in by_key]
            if not present:
                continue
            placed.update(k for k in keys if k in by_key)
            self._groups.append(self.make_group(title, description, present))

        leftover = [row for row in self.rows if row["key"] not in placed]
        if leftover:
            self._groups.append(self.make_group(
                "Other",
                "Present in the schema but not yet assigned to a section here.",
                leftover))

        for group in self._groups:
            self.page.add(group)

        self.apply_filter()

    def groups_built(self):
        return getattr(self, "_groups", [])

    def make_group(self, title, description, rows):
        group = Adw.PreferencesGroup(title=title, description=description)
        for descriptor in rows:
            widget = self.make_row(descriptor)
            if widget is not None:
                group.add(widget)
                self.widgets[descriptor["key"]] = widget
        return group

    def subtitle_for(self, descriptor):
        """The `detail` prose, plus the key, plus why it may not be editable here.

        Showing `detail` at all is most of what "more detailed" means: the
        island panel has this text too but only for the selected row, and
        the packaged config app does not have it at all. Every one of these
        paragraphs is an argument someone had to reconstruct once.
        """
        bits = [descriptor.get("detail", "").strip()]
        if descriptor.get("type") == "font" and not descriptor.get("resolves", True):
            bits.append("⚠ This family does not resolve — %s."
                        % descriptor.get("resolveDetail", "it falls back"))
        return "\n\n".join(b for b in bits if b)

    def decorate(self, row, descriptor):
        row.set_title(descriptor.get("label", descriptor["key"]))
        # Adw.EntryRow has a title and NO subtitle — its title doubles as the
        # field's floating label — so this is guarded rather than assumed.
        # That is also why the text types are wrapped in an ExpanderRow below:
        # the `detail` prose is most of what this app is for, and a row type
        # that cannot show it is the wrong container regardless of how well
        # it edits.
        if hasattr(row, "set_subtitle"):
            row.set_subtitle(self.subtitle_for(descriptor))
        if hasattr(row, "set_subtitle_lines"):
            row.set_subtitle_lines(0)

        suffix = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                         valign=Gtk.Align.CENTER)

        if descriptor.get("scope") == "fork":
            tag = Gtk.Label(label="fork only")
            tag.add_css_class("caption")
            tag.add_css_class("dim-label")
            suffix.append(tag)

        if not descriptor.get("panel", True):
            tag = Gtk.Label(label="app only")
            tag.add_css_class("caption")
            tag.add_css_class("dim-label")
            tag.set_tooltip_text(
                "The island's own settings panel has no editor for this type — "
                "it runs under a keyboard grab and cannot own a text field.")
            suffix.append(tag)

        if descriptor.get("value") != descriptor.get("default"):
            reset = Gtk.Button(icon_name="edit-undo-symbolic",
                               valign=Gtk.Align.CENTER,
                               tooltip_text="Reset to %r" % (descriptor.get("default"),))
            reset.add_css_class("flat")
            reset.connect("clicked", lambda *_, d=descriptor: self.reset(d))
            suffix.append(reset)

        row.add_suffix(suffix)
        return row

    def reset(self, descriptor):
        default = descriptor.get("default")
        if isinstance(default, bool):
            raw = "true" if default else "false"
        elif isinstance(default, list):
            raw = ",".join(default)
        else:
            raw = str(default)
        self.commit(descriptor["key"], raw, lambda: None)

    def make_row(self, descriptor):
        kind = descriptor.get("type")
        key = descriptor["key"]
        value = descriptor.get("value")

        if kind == "bool":
            row = Adw.SwitchRow(active=bool(value))
            row.connect("notify::active", self.on_switch, descriptor)
            return self.decorate(row, descriptor)

        if kind == "int":
            adjustment = Gtk.Adjustment(
                value=float(value if isinstance(value, int) else descriptor["default"]),
                lower=float(descriptor["min"]), upper=float(descriptor["max"]),
                step_increment=float(descriptor.get("step", 1)),
                page_increment=float(descriptor.get("step", 1)) * 5)
            row = Adw.SpinRow(adjustment=adjustment, digits=0)
            # Commit on focus-leave and on Enter rather than on every tick of
            # the adjustment: holding the + button would otherwise fire one
            # subprocess per repeat.
            row.connect("notify::value", self.on_spin_queued, descriptor)
            return self.decorate(row, descriptor)

        if kind == "enum":
            values = descriptor.get("values", [])
            model = Gtk.StringList.new(values)
            row = Adw.ComboRow(model=model)
            if value in values:
                row.set_selected(values.index(value))
            row.connect("notify::selected", self.on_combo, descriptor)
            return self.decorate(row, descriptor)

        if kind in ("string", "path", "font", "list"):
            text = ",".join(value) if isinstance(value, list) else str(value or "")

            entry = Adw.EntryRow(title=descriptor.get("label", key))
            entry.set_text(text)
            # Apply button rather than commit-on-every-keystroke: each commit
            # is a subprocess AND a write to the file ForkConfig.qml watches,
            # so committing per character would rewrite userconfig.json once
            # per letter of a font name and make the shell re-read each time.
            entry.set_show_apply_button(True)
            entry.connect("apply", self.on_entry, descriptor)

            # The container exists to carry the description. Adw.EntryRow has
            # no subtitle, and dropping the `detail` for these five keys would
            # remove it from exactly the rows that need it most — they are the
            # free-text ones, where a wrong value is a typo rather than an
            # out-of-range number the schema can catch.
            row = Adw.ExpanderRow()
            self.decorate(row, descriptor)
            row.add_row(entry)

            if kind == "font":
                button = Gtk.Button(icon_name="font-x-generic-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Choose a font family")
                button.add_css_class("flat")
                button.connect("clicked", self.on_pick_font, entry, descriptor)
                entry.add_suffix(button)
            elif kind == "path":
                button = Gtk.Button(icon_name="folder-open-symbolic",
                                    valign=Gtk.Align.CENTER,
                                    tooltip_text="Choose a folder")
                button.add_css_class("flat")
                button.connect("clicked", self.on_pick_folder, entry, descriptor)
                entry.add_suffix(button)
            elif kind == "list":
                entry.set_tooltip_text(
                    "Comma-separated and ORDERED. Allowed: "
                    + ", ".join(descriptor.get("values", [])))

            # Open the ones that are wrong, so a font that does not resolve is
            # visible without hunting for it.
            if kind == "font" and not descriptor.get("resolves", True):
                row.set_expanded(True)

            return row

        # An unknown type is shown, not hidden. A row that silently vanishes
        # because this app is older than the schema is the failure this whole
        # tree keeps re-learning; a visible read-only row says so instead.
        row = Adw.ActionRow()
        self.decorate(row, descriptor)
        label = Gtk.Label(label=str(value), valign=Gtk.Align.CENTER)
        label.add_css_class("dim-label")
        row.add_suffix(label)
        row.set_subtitle(self.subtitle_for(descriptor)
                         + "\n\nUnknown type %r — this app cannot edit it." % kind)
        return row

    # ---- handlers --------------------------------------------------

    def on_switch(self, row, _param, descriptor):
        if self.suppress:
            return
        want = row.get_active()
        self.commit(descriptor["key"], "true" if want else "false",
                    lambda: row.set_active(not want))

    def on_spin_queued(self, row, _param, descriptor):
        if self.suppress:
            return
        # Coalesce: one commit 400 ms after the last change, so dragging or
        # holding a spin button is one write rather than forty.
        source = getattr(row, "_commit_source", 0)
        if source:
            GLib.source_remove(source)
        row._commit_source = GLib.timeout_add(
            400, self.on_spin_commit, row, descriptor)

    def on_spin_commit(self, row, descriptor):
        row._commit_source = 0
        if not self.suppress:
            previous = descriptor.get("value")
            self.commit(descriptor["key"], int(row.get_value()),
                        lambda: row.set_value(float(previous)))
        return GLib.SOURCE_REMOVE

    def on_combo(self, row, _param, descriptor):
        if self.suppress:
            return
        values = descriptor.get("values", [])
        index = row.get_selected()
        if 0 <= index < len(values):
            previous = descriptor.get("value")
            self.commit(descriptor["key"], values[index],
                        lambda: row.set_selected(values.index(previous)
                                                 if previous in values else 0))

    def on_entry(self, row, descriptor):
        if self.suppress:
            return
        previous = descriptor.get("value")
        restore = ",".join(previous) if isinstance(previous, list) else str(previous or "")
        self.commit(descriptor["key"], row.get_text(),
                    lambda: row.set_text(restore))

    def on_pick_font(self, _button, row, descriptor):
        dialog = Gtk.FontDialog(title="Choose a family for %s" % descriptor.get("label"))
        # FAMILY, not FONT: these keys hold a family name that fontconfig
        # resolves, not a full "Inter Medium 11" description with a size in
        # it. Handing the backend a size here would put one in a QString the
        # shell then renders literally.
        dialog.set_language(Pango.Language.get_default())

        def done(source, result):
            try:
                family = source.choose_family_finish(result)
            except GLib.Error:
                return
            if family is not None:
                row.set_text(family.get_name())
                self.on_entry(row, descriptor)

        dialog.choose_family(self, None, None, done)

    def on_pick_folder(self, _button, row, descriptor):
        dialog = Gtk.FileDialog(title="Choose a folder for %s" % descriptor.get("label"))
        current = row.get_text()
        if current and os.path.isdir(current):
            dialog.set_initial_folder(Gio.File.new_for_path(current))

        def done(source, result):
            try:
                folder = source.select_folder_finish(result)
            except GLib.Error:
                return
            if folder is not None:
                row.set_text(folder.get_path())
                self.on_entry(row, descriptor)

        dialog.select_folder(self, None, done)

    # ---- search ----------------------------------------------------

    def apply_filter(self):
        needle = self.search.get_text().strip().casefold()
        by_key = {row["key"]: row for row in self.rows}

        for group in self.groups_built():
            any_visible = False
            for key, widget in self.widgets.items():
                descriptor = by_key.get(key)
                if descriptor is None:
                    continue
                if widget.get_parent() is not None and widget.get_ancestor(Adw.PreferencesGroup) is not group:
                    continue
                # Key and detail are searched, not only the label. The label
                # is the one thing a user does NOT know when they arrive
                # looking for "that thing about the exclusive zone".
                haystack = " ".join([
                    descriptor.get("label", ""), descriptor["key"],
                    descriptor.get("detail", ""),
                ]).casefold()
                visible = needle in haystack if needle else True
                widget.set_visible(visible)
                any_visible = any_visible or visible
            group.set_visible(any_visible)


class App(Adw.Application):
    def __init__(self, selftest=False):
        super().__init__(application_id="dev.ati.IslandSettings",
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.selftest = selftest

    def do_activate(self):
        window = self.props.active_window or SettingsWindow(self)
        if self.selftest:
            report(window)
            if self.selftest == "write":
                exercise_writes(window)
            self.quit()
            return
        window.present()


def exercise_writes(window):
    """Drive commit() itself, not just the CLI underneath it.

    --set is already covered from the shell. What is NOT covered by that is
    this app's own path: that a refusal reverts the widget instead of leaving
    it showing a value that was never written, which is the GUI equivalent of
    the inert row — the control says one thing and the file says another.

    CALLER MUST BACK UP userconfig.json. This writes to it.
    """
    print("\n-- write path --")

    row = next(r for r in window.rows if r["key"] == "islandAutoHideDelayMs")
    before = row["value"]
    ok = window.commit("islandAutoHideDelayMs", 3300, lambda: None)
    window.reload()  # commit() defers; selftest has no main loop to defer into
    after = window.value_of("islandAutoHideDelayMs")
    print("  accepted write : ok=%s %r -> %r %s"
          % (ok, before, after, "PASS" if ok and after == 3300 else "FAIL"))

    font_row = next(r for r in window.rows if r["key"] == "textFontFamily")
    original = font_row["value"]
    reverted = {"called": False}

    def restore():
        reverted["called"] = True

    ok = window.commit("textFontFamily", "Totally Fake Font XYZ", restore)
    window.reload()
    unchanged = window.value_of("textFontFamily") == original
    print("  refused write  : ok=%s reverted=%s file-unchanged=%s %s"
          % (ok, reverted["called"], unchanged,
             "PASS" if (not ok and reverted["called"] and unchanged) else "FAIL"))

    window.commit("islandAutoHideDelayMs", before, lambda: None)
    window.reload()
    print("  restored       : %r" % window.value_of("islandAutoHideDelayMs"))


def report(window):
    """Print what the UI actually built, then exit.

    This exists because the alternative way to check that all 30 rows render
    is a screenshot, and a screenshot of a scrolling window shows the ten
    rows that happen to be above the fold. Two of the three things worth
    checking here — that every TYPE constructs a widget, and that the five
    app-only rows are present — are invisible in any single capture, and the
    third (that nothing threw) is exactly the kind of thing a normal-looking
    window hides. Same argument as reading the quickshell log instead of
    trusting the desktop.
    """
    kinds = {}
    lines = []

    for descriptor in window.rows:
        key = descriptor["key"]
        widget = window.widgets.get(key)
        kind = descriptor["type"]
        kinds[kind] = kinds.get(kind, 0) + 1
        lines.append("  %-30s %-7s %-14s %s" % (
            key, kind,
            type(widget).__name__.replace("Adw", "") if widget else "MISSING",
            "app-only" if not descriptor.get("panel", True) else ""))

    missing = [r["key"] for r in window.rows if r["key"] not in window.widgets]

    print("built %d/%d rows into %d groups"
          % (len(window.widgets), len(window.rows), len(window.groups_built())))
    print("types:", ", ".join("%s=%d" % kv for kv in sorted(kinds.items())))
    print("missing widgets:", missing or "none")
    print("\n".join(lines))


if __name__ == "__main__":
    mode = False
    if "--selftest-write" in sys.argv:
        mode = "write"
    elif "--selftest" in sys.argv:
        mode = True
    args = [a for a in sys.argv if not a.startswith("--selftest")]
    sys.exit(App(selftest=mode).run(args))
