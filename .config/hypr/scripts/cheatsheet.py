#!/usr/bin/env python3
"""cheatsheet.py — the port of qtile's CheatSheet-Mode (16 bindings).

    cheatsheet.py hypr | vim | fish     print a sheet through rofi
    cheatsheet.py --sheet-json <which>  the same sheet, for the island
    cheatsheet.py --submap-json <name>  one submap's keys, for the chord HUD

THIS WAS ROFI, AND THE CHORD NOW USES THE ISLAND INSTEAD
--------------------------------------------------------
The argument for rofi is still on the record because it was a real one:
REQUIREMENTS.md item 3 says rebuild the *interactive* popups in the shell
and leave the *launcher* problems on rofi, and a cheatsheet is neither
stateful nor interactive — it is a list you read and dismiss, which rofi
already solves under XWayland, with search, for free.

It was overruled. Every other surface in this desktop lives in the notch,
and a rofi window opening over the desktop for the one chord whose job is
to explain the desktop was the odd one out. `$mod SHIFT K` now opens
`qml/cheatsheet/CheatsheetLayer.qml`, which calls back into THIS file for
its rows via `--sheet-json`.

**The rofi path is kept and still works.** `cheatsheet.py hypr` in a
terminal prints the sheet exactly as before; it is the one way to read
these keys that does not require the shell to be running, which is worth
having on the day the shell is what is broken.

What survives the move intact is the part that mattered: qtile's version
was a paged grid driven by `j`, `k`, `Tab` and `Shift+Tab` — four of the
sixteen bindings existed only to move a viewport around 129 rows of text.
rofi replaced all four with typing what you are looking for, and the QML
panel is built around reproducing that search field rather than around
rendering the rows. Those four keys are deliberately not reproduced in
either path; the rest of the chord (`k`, `v`, `f`, and the exits) is.

WHERE THE CONTENT COMES FROM
----------------------------
**The Hyprland sheet is generated from the LIVE compositor** —
`hyprctl binds -j` — not from a hand-written list and not by parsing
binds.conf. qtile's `QtileCheatsheet.py` carried 129 hand-maintained rows
which were only ever as true as the last person to update them. Reading
the compositor's own resolved binding table means the sheet cannot drift:
if a bind is in the sheet it is live, and if it is live it is in the sheet.
That includes every submap, which is where the keys you actually need
reminding of live.

**The vim and fish sheets are parsed out of the qtile popups**, whose
`CHEATSHEET` dicts are the originals. They are read with `ast`, never
imported — `popups/VimCheatsheet.py` imports `qtile_extras` at module level
and builds a popup as a side effect, so importing it from outside qtile
fails, and importing it from inside would draw a popup. `ast.literal_eval`
on the one assignment node reads the data and runs none of the file.
~/.config/qtile is READ-ONLY to this session and this keeps it that way
while still having exactly one copy of the content.
"""

import ast
import json
import os
import re
import subprocess
import sys

QTILE_POPUPS = os.path.expanduser("~/.config/qtile/popups")

SOURCES = {
    "vim": ("VimCheatsheet.py", "VIM"),
    "fish": ("FishCheatsheet.py", "FISH / KITTY"),
}

# `hyprctl binds` reports modifiers as a bitmask. These are wlroots'
# WLR_MODIFIER_* values, and they are NOT the same numbering as X11's --
# 64 is SUPER here and 8 is ALT, where X11 calls SUPER mod4 and ALT mod1.
# Getting this wrong silently mislabels every binding in the sheet.
MODIFIER_BITS = [
    (64, "SUPER"),
    (8, "ALT"),
    (4, "CTRL"),
    (1, "SHIFT"),
]

# Physical Alt is broken on this laptop and keyd remaps Caps Lock to it, so
# "ALT" in a printed sheet means a key that is not labelled ALT on the
# keyboard. Saying so once in the header is the difference between the
# sheet being useful and being confusing.
ALT_NOTE = "ALT = Caps Lock (remapped by keyd)"


def modifier_text(mask):
    parts = [name for bit, name in MODIFIER_BITS if mask & bit]
    return " + ".join(parts)


def key_text(entry):
    key = str(entry.get("key") or "").strip()
    if key:
        return key
    code = entry.get("keycode")
    # A bind written by keycode rather than by name. Reporting the raw
    # number is honest; inventing a name for it would be a guess that
    # depends on the layout, and this config has four.
    return "code %s" % code if code else "?"


def describe(entry):
    dispatcher = str(entry.get("dispatcher") or "")
    arg = str(entry.get("arg") or "").strip()

    if dispatcher == "exec":
        # Long exec lines are mostly path noise. The interesting part is the
        # program, and for the island's IPC it is the function name at the
        # end -- "qs -p ... ipc call tide toggleControlCenter" should read as
        # "toggleControlCenter", not as forty characters of socket path.
        if " ipc call " in arg:
            return "island: " + arg.split(" ipc call ", 1)[1]
        return arg
    if dispatcher == "submap":
        return "MODE: %s" % arg if arg != "reset" else "leave this mode"
    if arg:
        return "%s %s" % (dispatcher, arg)
    return dispatcher


def hyprland_rows(label=None):
    """Every live bind, grouped by submap, root bindings first.

    `label` chooses how a bind is described. It defaults to describe(),
    the exact command, which is what the printed sheet wants. The island
    panel passes short_label() instead — see sheet_json().
    """
    label = label or describe
    try:
        raw = subprocess.run(["hyprctl", "binds", "-j"],
                             capture_output=True, text=True, timeout=6)
        binds = json.loads(raw.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return [("ERROR", [("could not read hyprctl binds", "")])]

    groups = {}
    for entry in binds:
        submap = str(entry.get("submap") or "")
        combo = " + ".join(filter(None, [modifier_text(entry.get("modmask", 0)),
                                         key_text(entry)]))
        groups.setdefault(submap, []).append((label(entry), combo))

    sections = []
    if "" in groups:
        sections.append(("ROOT", groups.pop("")))
    for name in sorted(groups):
        # Each submap's own `submap reset` rows are noise in a printed
        # sheet -- there are two per action and they all say the same
        # thing. The one that matters (how to LEAVE) is kept once.
        rows = groups[name]
        kept, seen_leave = [], False
        for label, combo in rows:
            if label == "leave this mode":
                if seen_leave:
                    continue
                seen_leave = True
            kept.append((label, combo))
        sections.append(("MODE: " + name.upper(), kept))
    return sections


def parsed_rows(filename):
    """Pull a CHEATSHEET dict out of a qtile popup without importing it."""
    path = os.path.join(QTILE_POPUPS, filename)
    try:
        tree = ast.parse(open(path).read())
    except (OSError, SyntaxError):
        return [("ERROR", [("could not read %s" % path, "")])]

    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if not any(getattr(target, "id", "") == "CHEATSHEET"
                   for target in node.targets):
            continue
        try:
            data = ast.literal_eval(node.value)
        except ValueError:
            return [("ERROR", [("CHEATSHEET in %s is not literal data"
                                % filename, "")])]
        return [(str(section), [(str(a), str(b)) for a, b in rows])
                for section, rows in data.items()]
    return [("ERROR", [("no CHEATSHEET in %s" % filename, "")])]


def render(sections, title, note=""):
    """One pango-marked-up line per row, section headers between.

    Two spaces of leading indent on every row rather than a fixed-width
    column: rofi's list is not a monospace grid and padding computed here
    lands wrong the moment a proportional font is used. The em-dash
    separator does the alignment work the eye needs.
    """
    lines = []
    header = "<b>%s</b>" % title
    if note:
        header += "   <i>%s</i>" % note
    lines.append(header)
    for section, rows in sections:
        lines.append("")
        lines.append("<b>%s</b>" % escape(section))
        for label, combo in rows:
            if combo:
                lines.append("  %s  —  <b>%s</b>"
                             % (escape(label), escape(combo)))
            else:
                lines.append("  %s" % escape(label))
    return lines


def escape(text):
    # rofi renders these with -markup-rows, so anything that looks like a
    # tag has to be neutralised or the row silently disappears.
    return (str(text).replace("&", "&amp;")
                     .replace("<", "&lt;")
                     .replace(">", "&gt;"))


def show(lines, prompt):
    command = [
        "rofi", "-dmenu", "-i", "-markup-rows",
        "-p", prompt,
        "-no-custom",
        # Wide, because these rows are "description — KEY COMBO" and
        # wrapping a key combo onto a second line makes it unreadable.
        "-theme-str", "window { width: 62%; } listview { lines: 18; }",
    ]
    try:
        subprocess.run(command, input="\n".join(lines), text=True)
    except FileNotFoundError:
        # No rofi: print the sheet instead of failing silently. Anyone
        # running this from a terminal gets what they asked for.
        print("\n".join(lines))


def short_label(entry):
    """A few words, for the island's mode panel.

    describe() is right for the printed sheet, where the exact command is
    the useful thing and there is room for it. It is wrong for a panel you
    read in the half second before pressing a key: "wpctl set-volume -l 1.5
    @DEFAULT_AUDIO_SINK@ 5%+" is a correct answer to a question nobody asked
    while holding down a chord.

    Everything below is a presentation rule and nothing here changes what a
    key DOES, so an unrecognised command falling through to describe() is a
    perfectly good outcome — verbose, never wrong.
    """
    dispatcher = str(entry.get("dispatcher") or "")
    arg = str(entry.get("arg") or "").strip()

    if dispatcher == "exec":
        if " ipc call " in arg:
            # "qs -p ... ipc call tide toggleWallpaperPicker" -> "wallpaper picker"
            tail = arg.split(" ipc call ", 1)[1].split()[-1]
            tail = re.sub(r"^(toggle|show|open)", "", tail)
            return re.sub(r"(?<!^)(?=[A-Z])", " ", tail).strip().lower() or tail

        if "wpctl set-volume" in arg:
            return "volume up" if "%+" in arg else "volume down"
        if "wpctl set-mute" in arg:
            return "mute"
        if "brightnessctl" in arg:
            return "brightness up" if "%+" in arg else "brightness down"

        if "switchxkblayout" in arg:
            # `exec, hyprctl switchxkblayout all N` — the index is the whole
            # point, and the layout order is input.conf's kb_layout. Named
            # rather than numbered because "layout 2" tells you nothing.
            layouts = ["us", "ara", "tr", "de"]
            index = arg.split()[-1]
            return "layout " + (layouts[int(index)]
                                if index.isdigit() and int(index) < len(layouts)
                                else index)

        # A script: its name is the best short answer it has. Skip past an
        # interpreter or `env`, or every python-launched tool in the rofi
        # chord reads "python3" — which is true of six of them and useful
        # for none.
        words = [w for w in arg.split() if not w.startswith("-")]
        first = words[0] if words else arg
        if os.path.basename(first) in ("python3", "python", "sh", "bash", "env"):
            first = words[1] if len(words) > 1 else first
        base = os.path.basename(first)
        base = re.sub(r"\.(sh|py)$", "", base)
        # dm-documents / rofi_anki -> documents / anki
        base = re.sub(r"^(dm-|rofi[-_])", "", base)
        base = base.replace("_", " ").replace("-", " ") or arg

        # Keep what distinguishes one bind from its neighbours. Five keys in
        # the draw chord are all `gromit-mpx` and differ only by flag, and
        # three in the cheatsheet chord are all this file and differ only by
        # argument — without the tail they render as the same row repeated,
        # which is worse than the raw command because it looks like a bug.
        tail = arg.split()[arg.split().index(first) + 1:] if first in arg.split() else []
        tail = [t for t in tail if not t.startswith("~") and "/" not in t]
        if tail:
            suffix = " ".join(tail)
            if len(suffix) <= 14:
                base = "%s %s" % (base, suffix)
        return base

    if dispatcher == "resizeactive":
        return "resize"
    if dispatcher == "layoutmsg":
        if "splitratio" in arg or "mfact" in arg:
            return "wider" if "+" in arg else ("reset ratio" if "exact" in arg else "narrower")
        return arg
    if dispatcher == "workspace":
        return "workspace " + arg
    if dispatcher == "switchxkblayout":
        return "layout " + arg.split()[-1]

    return describe(entry)


def sheet_json(which):
    """A WHOLE cheatsheet as JSON, for the island's panel.

    Deliberately the same sections that render() prints, from the same two
    builders, so the panel and the printed sheet cannot say different
    things about the same key. The only difference is the marshalling:
    render() emits pango-marked-up lines, this emits the rows and lets QML
    do its own layout. escape() is NOT applied — that exists for rofi's
    `-markup-rows`, where an unescaped `<` silently eats the row, and QML
    Text with textFormat left at PlainText has no such hazard.
    """
    which = (which or "hypr").lower()

    if which in ("hypr", "hyprland", "qtile"):
        sections = hyprland_rows(short_label)
        title, note = "HYPRLAND KEYS", ALT_NOTE
    elif which in SOURCES:
        filename, title = SOURCES[which]
        sections, note = parsed_rows(filename), ""
    else:
        return json.dumps({"which": which, "title": "", "note": "",
                           "sections": []})

    return json.dumps({
        "which": which,
        "title": title,
        "note": note,
        # The WM sheet's labels are re-derived through short_label().
        #
        # hyprland_rows() builds them with describe(), which is right for
        # the PRINTED sheet — there the exact command is the useful thing
        # and a rofi row is as wide as the screen. In a panel it is neither:
        # `~/.config/hypr/scripts/focus-move.sh h` is three quarters path
        # and tells you nothing that "focus move h" does not, and four such
        # rows in a column push the column that matters off the edge.
        #
        # short_label() is the same prettifier the chord HUD uses, so a key
        # is described identically wherever it appears on screen — and it
        # falls through to describe() for anything it does not recognise,
        # which makes it verbose in the worst case and never wrong.
        #
        # Only the hypr sheet has entries to re-derive: vim and fish rows
        # are prose from the qtile popups, and `entry` is None for them.
        "sections": [
            {"title": str(section),
             "rows": [{"label": str(label), "combo": str(combo)}
                      for label, combo in rows]}
            for section, rows in sections
        ],
    })


def submap_keys_json(name):
    """The live bindings of ONE submap, as JSON, for the island's mode panel.

    This lives here and not in a script of its own so that describe() has
    exactly one definition. The mode panel and the printed cheatsheet must
    label a binding the same way — two prettifiers would drift, and a wrong
    label still renders, which is the failure mode this whole file is
    built to avoid (see the note about qtile's 129 hand-maintained rows).

    Emitted rather than printed as a sheet because the consumer is QML.
    Only the keys that DO something are included: every submap carries two
    binds per action (the action and its `submap reset`), plus its own
    entry combination and an Escape, and listing those turns a 20-key chord
    into a 45-row wall that is harder to read than no help at all.
    """
    try:
        raw = subprocess.run(["hyprctl", "binds", "-j"],
                             capture_output=True, text=True, timeout=6)
        binds = json.loads(raw.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return json.dumps({"name": name, "keys": []})

    rows, seen = [], set()
    for entry in binds:
        if str(entry.get("submap") or "") != name:
            continue
        if str(entry.get("dispatcher") or "") == "submap":
            continue
        combo = " ".join(filter(None, [modifier_text(entry.get("modmask", 0)),
                                       key_text(entry)]))
        if not combo or combo in seen:
            continue
        seen.add(combo)
        rows.append({"key": combo, "action": short_label(entry)})

    # The nine workspace binds every chord repeats are true, and they are
    # also nine of the twenty rows. Collapsed to one line so the keys that
    # are actually specific to this mode are what you read.
    digits = [r for r in rows if r["key"].isdigit()]
    if len(digits) > 3:
        rows = [r for r in rows if not r["key"].isdigit()]
        rows.append({"key": "1-9", "action": "workspace"})

    return json.dumps({"name": name, "keys": rows})


def main(argv):
    which = (argv[0] if argv else "hypr").lower()

    if which == "--submap-json":
        print(submap_keys_json(argv[1] if len(argv) > 1 else ""))
        return 0

    if which == "--sheet-json":
        print(sheet_json(argv[1] if len(argv) > 1 else "hypr"))
        return 0

    if which in ("hypr", "hyprland", "qtile"):
        # "qtile" is accepted because the chord key is qtile's `k` and the
        # muscle memory says "the WM sheet". It shows HYPRLAND's bindings:
        # a sheet of qtile's keys would be a sheet for a session that is
        # not running.
        show(render(hyprland_rows(), "HYPRLAND KEYS", ALT_NOTE), "hypr")
        return 0

    if which in SOURCES:
        filename, title = SOURCES[which]
        show(render(parsed_rows(filename), title), which)
        return 0

    print("usage: cheatsheet.py hypr|vim|fish", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
