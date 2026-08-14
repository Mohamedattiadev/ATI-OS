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

        # ---- the sidebar ------------------------------------------------
        #
        # WHY A SIDEBAR AND NOT A LONGER PAGE
        #
        # The groups already existed; they were headings on one scroll. With
        # 30 rows each carrying a paragraph, that page was about nine screens
        # tall, so "grouped" was true in the markup and false on screen —
        # you could not see a group boundary and a heading, which is the
        # only thing a heading is for.
        #
        # Categories become NAVIGATION instead. One category is on screen at
        # a time, every page fits without scrolling or nearly so, and the
        # sidebar is a table of contents that answers "what can I even
        # change here" — the question "not customisable" actually asks.
        self.sidebar_list = Gtk.ListBox(css_classes=["navigation-sidebar"])
        self.sidebar_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.sidebar_list.connect("row-selected", self.on_category)

        sidebar_scroll = Gtk.ScrolledWindow(hexpand=False, vexpand=True)
        sidebar_scroll.set_child(self.sidebar_list)

        sidebar_toolbar = Adw.ToolbarView()
        sidebar_header = Adw.HeaderBar()
        sidebar_header.set_title_widget(Adw.WindowTitle(title="Sections"))
        sidebar_toolbar.add_top_bar(sidebar_header)
        sidebar_toolbar.set_content(sidebar_scroll)

        self.split = Adw.NavigationSplitView(
            sidebar=Adw.NavigationPage(child=sidebar_toolbar, title="Sections"),
            content=Adw.NavigationPage(child=toolbar, title="Island Settings"),
        )
        self.split.set_min_sidebar_width(200)
        self.split.set_max_sidebar_width(260)

        self.toasts.set_child(self.split)
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

        self.build_sidebar()
        self.apply_filter()

    def groups_built(self):
        return getattr(self, "_groups", [])

    # ---- categories --------------------------------------------------

    MODIFIED = "​Modified"   # zero-width prefix: cannot collide with a
                                  # real group title, and never displayed.

    def modified_keys(self):
        """Keys whose value differs from the packaged default.

        Phase 8 asked for "a visible diff of what differs from the packaged
        defaults". The reset arrow already marks them one row at a time, but
        that only answers the question if you scroll all thirty rows and
        remember what you saw.
        """
        return [r["key"] for r in self.rows if r.get("value") != r.get("default")]

    def build_sidebar(self):
        """Rebuilt on every reload, because the Modified count moves.

        Selection is restored by TITLE rather than by index or by widget:
        build() runs after every write, and a row object from the previous
        build is a dead widget by the time this runs.
        """
        previous = getattr(self, "selected_category", None)

        while (child := self.sidebar_list.get_first_child()) is not None:
            self.sidebar_list.remove(child)

        self._sidebar_rows = {}
        # Counted from the widget map rather than from GROUPS, so "Other"
        # is included and a group whose keys are all absent is never listed.
        entries = []
        for group in self._groups:
            title = group.get_title()
            count = sum(1 for k, w in self.widgets.items()
                        if w.get_ancestor(Adw.PreferencesGroup) is group)
            entries.append((title, count))

        modified = self.modified_keys()
        if modified:
            entries.insert(0, (self.MODIFIED, len(modified)))

        for title, count in entries:
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                          margin_top=8, margin_bottom=8,
                          margin_start=10, margin_end=10)
            label = Gtk.Label(label="Changed" if title == self.MODIFIED else title,
                              xalign=0, hexpand=True)
            box.append(label)
            badge = Gtk.Label(label=str(count))
            badge.add_css_class("caption")
            badge.add_css_class("dim-label")
            box.append(badge)

            row = Gtk.ListBoxRow()
            row.set_child(box)
            row.category_title = title
            self.sidebar_list.append(row)
            self._sidebar_rows[title] = row

        target = previous if previous in self._sidebar_rows else None
        if target is None:
            # Open on the first real section, not on "Changed" — the diff is
            # a lens on the settings, not the settings.
            for title, _c in entries:
                if title != self.MODIFIED:
                    target = title
                    break
        if target is not None:
            self.selected_category = target
            self.sidebar_list.select_row(self._sidebar_rows[target])

    def select_section(self, name):
        """Select by visible name; "Changed" maps to the diff pseudo-section."""
        wanted = self.MODIFIED if name.strip().casefold() == "changed" else name
        target = self._sidebar_rows.get(wanted)
        if target is None:
            for title, row in self._sidebar_rows.items():
                if title.strip().casefold() == name.strip().casefold():
                    target = row
                    break
        if target is not None:
            self.sidebar_list.select_row(target)

    def on_category(self, _listbox, row):
        if row is None:
            return
        self.selected_category = row.category_title
        self.apply_filter()
        # Switching section must land at the TOP of it. Hiding rows does not
        # move the scroll position, so after leaving a long section the next
        # one opens part-way down — the same symptom the comment above
        # self.page describes for the nested-scroller bug, reached a
        # different way. Caught on the "Changed" view, which opened with its
        # first group already scrolled off.
        self.page.scroll_to_top()

    def make_group(self, title, description, rows):
        group = Adw.PreferencesGroup(title=title, description=description)
        for descriptor in rows:
            widget = self.make_row(descriptor)
            if widget is not None:
                group.add(widget)
                self.widgets[descriptor["key"]] = widget
        return group

    def subtitle_for(self, descriptor):
        """The `detail` prose, truncated to two lines by the caller.

        Showing `detail` at all is most of what "more detailed" means: the
        island panel has this text too but only for the selected row, and
        the packaged config app does not have it at all. Every one of these
        paragraphs is an argument someone had to reconstruct once.

        The font warning is NOT appended here any more. The subtitle is
        capped at two lines, so a warning glued to the end of a paragraph is
        a warning that gets ellipsized away exactly when the paragraph is
        long. It became an icon in the suffix — always visible, never
        truncated — with the full text in the ⓘ popover.
        """
        return (descriptor.get("detail") or "").strip()

    def make_info_button(self, descriptor):
        """The full descriptor, on demand: prose, key, type, default.

        This is where "more detailed" actually lives now that the subtitle
        is capped at two lines. It carries three things the flat page never
        showed at all:

          * the KEY. The app is a client of `island-settings.py --set <key>`,
            and the key is what you need to script it, to read
            userconfig.json, or to search this repo for why a row exists.
            `subtitle_for`'s docstring claimed the key was in the subtitle;
            it never was.
          * the DEFAULT, next to the current value, which is the per-row half
            of the diff the sidebar's "Changed" section shows in aggregate.
          * the type and range, so a refused write is predictable rather
            than a toast you have to trigger to learn from.
        """
        detail = (descriptor.get("detail") or "").strip()

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10,
                      margin_top=12, margin_bottom=12,
                      margin_start=12, margin_end=12)
        box.set_size_request(340, -1)

        if detail:
            prose = Gtk.Label(label=detail, xalign=0, wrap=True,
                              max_width_chars=44)
            prose.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
            box.append(prose)

        facts = Gtk.Grid(column_spacing=10, row_spacing=4)
        line = 0

        def fact(name, value, mono=False):
            nonlocal line
            k = Gtk.Label(label=name, xalign=0)
            k.add_css_class("caption")
            k.add_css_class("dim-label")
            v = Gtk.Label(label=str(value), xalign=0, wrap=True,
                          max_width_chars=30, selectable=True)
            v.add_css_class("caption")
            if mono:
                v.add_css_class("monospace")
            facts.attach(k, 0, line, 1, 1)
            facts.attach(v, 1, line, 1, 1)
            line += 1

        fact("Key", descriptor["key"], mono=True)
        fact("Type", descriptor.get("type", "?"))
        if descriptor.get("type") == "int" and "min" in descriptor:
            fact("Range", "%s – %s" % (descriptor.get("min"), descriptor.get("max")))
        if descriptor.get("type") == "enum" and descriptor.get("choices"):
            fact("Choices", ", ".join(str(c) for c in descriptor["choices"]))
        fact("Default", descriptor.get("default"), mono=True)
        fact("Current", descriptor.get("value"), mono=True)
        box.append(facts)

        if descriptor.get("type") == "font" and not descriptor.get("resolves", True):
            warn = Gtk.Label(
                label="⚠ This family does not resolve — %s."
                      % descriptor.get("resolveDetail", "it falls back"),
                xalign=0, wrap=True, max_width_chars=44)
            warn.add_css_class("caption")
            warn.add_css_class("warning")
            box.append(warn)

        popover = Gtk.Popover()
        popover.set_child(box)

        button = Gtk.MenuButton(icon_name="help-about-symbolic",
                                valign=Gtk.Align.CENTER,
                                tooltip_text="What this does, and its key")
        button.add_css_class("flat")
        button.set_popover(popover)
        return button

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
        # TWO lines, not unlimited, and this is the single biggest change to
        # how the app reads.
        #
        # It was `set_subtitle_lines(0)` — unlimited — so every one of the
        # thirty rows printed its whole `detail` paragraph, two to four lines
        # each. The page became about nine screens of justified grey text
        # with the controls stranded at the right margin, and the effect is
        # that nothing is scannable: finding a setting meant reading an essay
        # about each one you passed.
        #
        # The prose is still the point of this app, so it is not deleted and
        # not hidden behind a hover. It is TRUNCATED here and available in
        # full, immediately, from the ⓘ button added below. Two lines is
        # enough for the first sentence of nearly every descriptor, which is
        # reliably the one that says what the key does.
        if hasattr(row, "set_subtitle_lines"):
            row.set_subtitle_lines(2)

        suffix = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6,
                         valign=Gtk.Align.CENTER)

        if descriptor.get("type") == "font" and not descriptor.get("resolves", True):
            # An icon rather than prose, because a family that does not
            # resolve fails SILENTLY — fontconfig substitutes Noto Sans CJK
            # KR here and nothing reports it. This is the only cue that the
            # value in the box is not the font on screen.
            warn = Gtk.Image(icon_name="dialog-warning-symbolic",
                             valign=Gtk.Align.CENTER)
            warn.add_css_class("warning")
            warn.set_tooltip_text(
                "This family does not resolve — %s."
                % descriptor.get("resolveDetail", "it falls back"))
            suffix.append(warn)

        info = self.make_info_button(descriptor)
        if info is not None:
            suffix.append(info)

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

        if kind == "list":
            return self.make_list_row(descriptor)

        if kind in ("string", "path", "font"):
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

    def make_list_row(self, descriptor):
        """An ORDERED subset, edited as an order rather than as a string.

        `list` is the one type where a text entry is not merely inelegant but
        actively loses the setting's meaning. `dynamicIslandLeftSwipeItems` is
        an ordered subset of ten values, and island-settings.py's own comment
        is explicit that modelling it as one boolean per item would throw the
        ordering away — "which is half of what the row is for". A
        comma-separated entry keeps the ordering but hands the user the job of
        not typo-ing a member of a closed set, which is the same trade in the
        other direction.

        So: selected items in their real order, each able to move; unselected
        items below, each able to join at the end. Every mutation rewrites the
        whole list through --set, so the CLI still does the membership and
        duplicate checks — this widget cannot produce a value the schema would
        reject, but it is not TRUSTED not to.
        """
        key = descriptor["key"]
        values = list(descriptor.get("values", []))
        current = list(descriptor.get("value") or [])
        # Defensive: a value the schema no longer offers would otherwise be
        # invisible here and then be silently dropped by the first edit.
        current = [item for item in current if item in values]

        row = Adw.ExpanderRow()
        self.decorate(row, descriptor)
        row.set_expanded(False)

        summary = Gtk.Label(label=" → ".join(current) if current else "empty",
                            valign=Gtk.Align.CENTER)
        summary.add_css_class("dim-label")
        summary.add_css_class("caption")
        row.add_suffix(summary)

        def rewrite(new_items):
            self.commit(key, ",".join(new_items), lambda: None)

        for index, item in enumerate(current):
            child = Adw.ActionRow(title="%d. %s" % (index + 1, item))
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2,
                          valign=Gtk.Align.CENTER)

            up = Gtk.Button(icon_name="go-up-symbolic", tooltip_text="Move earlier")
            up.add_css_class("flat")
            up.set_sensitive(index > 0)
            up.connect("clicked", lambda _b, i=index: rewrite(
                current[:i - 1] + [current[i], current[i - 1]] + current[i + 1:]))

            down = Gtk.Button(icon_name="go-down-symbolic", tooltip_text="Move later")
            down.add_css_class("flat")
            down.set_sensitive(index < len(current) - 1)
            down.connect("clicked", lambda _b, i=index: rewrite(
                current[:i] + [current[i + 1], current[i]] + current[i + 2:]))

            remove = Gtk.Button(icon_name="list-remove-symbolic", tooltip_text="Remove")
            remove.add_css_class("flat")
            remove.connect("clicked", lambda _b, i=index: rewrite(
                current[:i] + current[i + 1:]))

            for button in (up, down, remove):
                box.append(button)
            child.add_suffix(box)
            row.add_row(child)

        available = [item for item in values if item not in current]
        for item in available:
            child = Adw.ActionRow(title=item)
            child.add_css_class("dim-label")
            add = Gtk.Button(icon_name="list-add-symbolic",
                             valign=Gtk.Align.CENTER, tooltip_text="Add to the end")
            add.add_css_class("flat")
            add.connect("clicked", lambda _b, it=item: rewrite(current + [it]))
            child.add_suffix(add)
            row.add_row(child)

        if not current:
            # The empty list is a LEGAL answer — "show nothing in the swipe
            # row" — and island-settings.py goes out of its way to keep it
            # spellable. Say so, rather than leaving a section that looks
            # broken.
            note = Adw.ActionRow(
                title="Nothing selected",
                subtitle="A legal choice: the swipe row shows nothing.")
            row.add_row(note)

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
        """Two gates, and the search one overrides the category one.

        A search that only looked inside the open section would be a worse
        search than the flat page had — arriving with "that thing about the
        exclusive zone" means not knowing which section it is in, which is
        the same reason the key and the detail are searched and not just the
        label. So a non-empty query ignores the sidebar entirely and shows
        matches from every section, with the section headings acting as the
        result grouping.
        """
        needle = self.search.get_text().strip().casefold()
        by_key = {row["key"]: row for row in self.rows}
        searching = bool(needle)
        category = getattr(self, "selected_category", None)
        modified = set(self.modified_keys()) if category == self.MODIFIED else None

        for group in self.groups_built():
            any_visible = False
            in_category = searching or category is None \
                or group.get_title() == category or modified is not None
            for key, widget in self.widgets.items():
                descriptor = by_key.get(key)
                if descriptor is None:
                    continue
                if widget.get_parent() is not None and widget.get_ancestor(Adw.PreferencesGroup) is not group:
                    continue
                if not in_category:
                    widget.set_visible(False)
                    continue
                if modified is not None and key not in modified:
                    widget.set_visible(False)
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
    def __init__(self, selftest=False, initial_filter="", initial_section=""):
        super().__init__(application_id="dev.ati.IslandSettings",
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.selftest = selftest
        self.initial_filter = initial_filter
        self.initial_section = initial_section

    def do_activate(self):
        window = self.props.active_window or SettingsWindow(self)
        if self.selftest:
            report(window)
            if self.selftest == "write":
                exercise_writes(window)
            self.quit()
            return
        # `--filter cpu` opens straight at the swipe readout. Useful on its
        # own — a settings app with 30 rows should be launchable AT a setting
        # rather than only at the top — and it is also the only way to get a
        # row below the fold into a screenshot without synthesising input.
        if self.initial_filter:
            window.search.set_text(self.initial_filter)
        # `--section Changed` opens on the diff. Same reasoning as --filter
        # above: a settings app should be launchable AT a place, and it is
        # also the only way to screenshot a section without synthesising a
        # click — and a stray click in THIS window writes config.
        if self.initial_section:
            window.select_section(self.initial_section)
        window.present()


def exercise_writes(window):
    """Drive commit() itself, not just the CLI underneath it.

    --set is already covered from the shell. What is NOT covered by that is
    this app's own path: that a refusal reverts the widget instead of leaving
    it showing a value that was never written, which is the GUI equivalent of
    the inert row — the control says one thing and the file says another.

    CALLER MUST BACK UP userconfig.json. This writes to it, and the restore
    at the end is NOT byte-exact — it restores the VALUE, not the ABSENCE.

    Measured: `islandAutoHideDelayMs` was not in the file at all, taking the
    schema default of 2500. This wrote 3300, then "restored" by setting 2500
    explicitly. Semantically identical, one key longer, and the file no
    longer matches what it was. `--set` has no unset, so restoring absence
    is not something this function can do — which is exactly why the backup
    is the caller's job and is stated first.
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

    # ---- navigation ----------------------------------------------------
    #
    # Driven here rather than by clicking the sidebar, and that is a safety
    # rule rather than convenience: this window's controls WRITE on change,
    # so a synthesised click that lands two pixels off a list row lands on a
    # switch instead and silently edits the user's config. Selecting the
    # category in code exercises the same apply_filter() path with nothing
    # on screen to miss.
    print("\n-- navigation --")

    def visible_keys():
        return {k for k, w in window.widgets.items() if w.get_visible()}

    total = len(window.widgets)
    for title in list(window._sidebar_rows):
        window.selected_category = title
        window.apply_filter()
        shown = visible_keys()
        name = "Changed" if title == window.MODIFIED else title
        if title == window.MODIFIED:
            expected = set(window.modified_keys())
            verdict = "PASS" if shown == expected else "FAIL"
        else:
            keys = [k for k, w in window.widgets.items()
                    if w.get_ancestor(Adw.PreferencesGroup) is not None
                    and w.get_ancestor(Adw.PreferencesGroup).get_title() == title]
            verdict = "PASS" if shown == set(keys) else "FAIL"
        print("  %-22s shows %2d/%d  %s" % (name, len(shown), total, verdict))

    # A query must ESCAPE the open section. Asserting "spans >1 section"
    # instead was the first version and it was a bad test: all seven matches
    # for "font" are legitimately in Typography, so a correct search failed
    # it. The property that actually matters is that results are not
    # confined to whatever happens to be selected.
    for needle in ("font", "enabled"):
        window.selected_category = "System"
        window.search.set_text(needle)
        window.apply_filter()
        across = visible_keys()
        sections = sorted(
            window.widgets[k].get_ancestor(Adw.PreferencesGroup).get_title()
            for k in across)
        outside = [k for k in across
                   if window.widgets[k].get_ancestor(Adw.PreferencesGroup)
                   .get_title() != "System"]
        print("  search %-9s from System: %2d rows, %d section(s), %d outside  %s"
              % ("'%s'" % needle, len(across), len(set(sections)), len(outside),
                 "PASS" if outside else "FAIL"))
    window.search.set_text("")
    window.apply_filter()

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

    initial = ""
    if "--filter" in sys.argv:
        index = sys.argv.index("--filter")
        if index + 1 < len(sys.argv):
            initial = sys.argv[index + 1]

    section = ""
    if "--section" in sys.argv:
        index = sys.argv.index("--section")
        if index + 1 < len(sys.argv):
            section = sys.argv[index + 1]

    args = [sys.argv[0]]
    sys.exit(App(selftest=mode, initial_filter=initial,
                 initial_section=section).run(args))
