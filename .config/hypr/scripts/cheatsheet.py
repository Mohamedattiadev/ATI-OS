#!/usr/bin/env python3
"""cheatsheet.py — the port of qtile's CheatSheet-Mode (16 bindings).

    cheatsheet.py hypr | vim | fish

WHY THIS IS ROFI AND NOT A QML PANEL
------------------------------------
REQUIREMENTS.md item 3 states the rule: rebuild the *interactive* popups in
the shell, leave the *launcher* problems on rofi. A cheatsheet is neither
stateful nor interactive — it is a list you read and dismiss, which is the
exact shape rofi already solves, under XWayland, with fuzzy search, for
free. Building a scrolling read-only grid in QML would be several hundred
lines to end up with something worse at the one thing it has to do.

It is also strictly better than what qtile had. qtile's version was a
paged grid driven by `j`, `k`, `Tab` and `Shift+Tab` — four of the sixteen
bindings existed only to move a viewport around 129 rows of text. rofi
replaces all four with typing what you are looking for. Those keys are
deliberately not reproduced; the rest of the chord (`k`, `v`, `f`, and the
exits) is.

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


def hyprland_rows():
    """Every live bind, grouped by submap, root bindings first."""
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
        groups.setdefault(submap, []).append((describe(entry), combo))

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


def main(argv):
    which = (argv[0] if argv else "hypr").lower()

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
