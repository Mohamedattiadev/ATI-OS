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


def island_call(arg):
    """The `<target> <function> [arg]` half of a command addressing the island.

    TWO SPELLINGS REACH THE SAME IPC, and only one of them was recognised.

        qs -p <fork> ipc call tide showPicker anki
        bar-action           tide showPicker anki

    `bar-action` is the WRAPPER that picks between the island's IPC and the
    rofi twin depending on which bar is up, and every bind in the rofi submap
    goes through it. A labeller that reduces an exec to its PROGRAM therefore
    collapsed twenty-six different keys to the wrapper's own name -- the whole
    mode HUD read "bar action", twenty-six times. `SHIFT C` was the only row
    with a real label, and only because it runs something else.

    So the wrapper is looked PAST rather than at, and both spellings are
    reduced to the same tail, which is what makes one prettifier enough for
    both. Returns "" for anything that is not an island call.
    """
    if " ipc call " in arg:
        return arg.split(" ipc call ", 1)[1].strip()
    words = arg.split()
    for index, word in enumerate(words):
        # By BASENAME and by whole argument, not by substring: a path to the
        # script and a bare `bar-action` are the same command, and a window
        # title that happens to contain the word is not.
        if os.path.basename(word) == "bar-action":
            return " ".join(words[index + 1:]).strip()
    return ""


def describe(entry):
    dispatcher = str(entry.get("dispatcher") or "")
    arg = str(entry.get("arg") or "").strip()

    if dispatcher == "exec":
        # Long exec lines are mostly path noise. The interesting part is the
        # program, and for the island's IPC it is the function name at the
        # end -- "qs -p ... ipc call tide toggleControlCenter" should read as
        # "toggleControlCenter", not as forty characters of socket path.
        #
        # Deliberately NOT island_call(): a `bar-action` line is already short
        # and it is already exact, and the printed sheet wants the command
        # that runs. Calling it "island:" would also be a lie under the topbar,
        # where the same key opens a rofi menu.
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
        call = island_call(arg)
        if call:
            # "... ipc call tide toggleWallpaperPicker" -> "wallpaper picker"
            # "bar-action  tide showPicker anki"        -> "anki"
            # "bar-action  bar  systemBox"              -> "system box"
            # "bar-action  overview toggle"             -> "overview"
            # "bar-action  tide showOnboarding 0"       -> "onboarding"
            #
            # No table: a function that takes a NAME is named by it (showPicker
            # is one function covering fourteen menus, and they differ nowhere
            # else), a function that takes none is named by itself, and the
            # TARGET is the last resort for the two whose function is a bare
            # verb. `bar-action`'s own case statement stays the authority for
            # what each of these DOES; this only has to tell them apart.
            parts = call.split()
            target = parts[0] if parts else ""
            func = parts[1] if len(parts) > 1 else ""
            param = parts[2] if len(parts) > 2 else ""
            # A numeric argument is a PARAMETER, not a name -- showOnboarding's
            # `0` is a page index and labelled the row "0".
            name = param if param and not param.isdigit() else func
            name = re.sub(r"^(toggle|show|open)", "", name)
            words = re.sub(r"(?<!^)(?=[A-Z])", " ", name).strip().lower()
            return words or target or call

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
            # `env` is followed by its ASSIGNMENTS, not by the program, so
            # taking the next word gave "GTK THEME=x qalculate-gtk". Skip past
            # every VAR=VALUE to reach the command being run.
            rest = [w for w in words[1:] if not re.match(r"^\w+=", w)]
            first = rest[0] if rest else (words[1] if len(words) > 1 else first)
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


# ---------------------------------------------------------------- island --
#
#  ---- THIS TABLE IS HAND-MAINTAINED, AND THAT IS NOT A SHORTCUT ----
#
#  Every other sheet in this file is DERIVED. The Hyprland one reads
#  `hyprctl binds`, so it cannot disagree with the compositor; the vim and
#  fish ones parse the qtile popup sources, so they cannot disagree with
#  those. This one has nothing to read. The island's keys are
#  `Keys.onPressed` switch statements inside QML components, and there is no
#  runtime that will enumerate them — Quickshell has no equivalent of
#  `hyprctl binds`, and a QML key handler is a function body, not data.
#
#  So it is a copy, and copies rot. The mitigation is to name the file each
#  section was read out of, so checking a row is opening one file rather
#  than searching the tree:
#
#    Settings panel     qml/island/SettingsLayer.qml
#    List picker        qml/island/PickerLayer.qml
#    App launcher       qml/island/ApplicationLauncherLayer.qml
#    Wi-Fi / Bluetooth  qml/connectivity/ConnectivityDetailPanel.qml
#    Theme picker       qml/island/ThemePickerLayer.qml
#    Wallpaper picker   qml/island/WallpaperPickerLayer.qml
#
#  The alternative was to leave the settings panel undocumented, which is
#  what it was: it has had h/j/k/l, g/G and three separate keys that mean
#  "change this value" since it was written, and nothing on screen said so.

ISLAND_SECTIONS = [
    ("SETTINGS PANEL", [
        ("next setting", "j  /  Down"),
        ("previous setting", "k  /  Up"),
        ("decrease, or previous value", "h  /  Left"),
        ("increase, next value, or toggle", "l  /  Right  /  Enter  /  Space"),
        ("first setting", "g"),
        ("last setting", "Shift g"),
        ("close", "q  /  Escape"),
    ]),
    # j/k and q are qualified because the panel qualifies them: they are
    # movement while the box is empty and letters the moment it is not, or
    # "jack" and "qutebrowser" would be untypeable. Ctrl+n/p are the pair
    # that works in both states, so they are listed first.
    ("LIST PICKER", [
        ("move down / up", "Ctrl n  /  Ctrl p  /  Down  /  Up"),
        ("move down / up, empty box only", "j  /  k"),
        ("run the selected row", "Enter"),
        ("filter the list", "just type"),
        ("back one page", "Backspace on an empty box  /  Ctrl h"),
        ("re-read the list", "Ctrl r"),
        ("close", "q on an empty box  /  Escape"),
    ]),
    # The launcher is the one panel whose motions carry Ctrl, and the sheet
    # has to say so rather than list "j / k" like its neighbours above. Its
    # field is cleared on every open, so a bare letter there is always a
    # letter — see the long comment in ApplicationLauncherLayer.qml. Left and
    # Right are listed second because they are the ones that stop working
    # once there is text in the box (they become cursor keys, which is what
    # you want them to be).
    ("APPLICATION LAUNCHER", [
        ("next app", "Ctrl l  /  Ctrl j  /  Ctrl n"),
        ("previous app", "Ctrl h  /  Ctrl k  /  Ctrl p"),
        ("next / previous, empty box only", "Right  /  Left"),
        ("next / previous, always", "Down  /  Tab  /  Up  /  Shift Tab"),
        ("search", "just type"),
        ("launch", "Enter"),
        ("launch a favourite", "1 - 9, on an empty box"),
        ("favourite / unfavourite", "right-click an app"),
        ("close", "Escape"),
    ]),
    ("WI-FI  /  BLUETOOTH", [
        ("move down / up", "j  /  k  /  Down  /  Up"),
        ("join network, pair or connect device", "Enter  /  Space"),
        ("first / last row", "g  /  Shift g"),
        ("close", "q  /  Escape"),
    ]),
    # These were one row reading "move — Left / Right" and are now two
    # sections, because the two panels stopped having the same keys: the
    # theme picker is a grid and grew j/k and g/G with it, and the wallpaper
    # picker is a carousel with a random jump. Neither has a search box, so
    # both can spend bare letters and both do.
    ("THEME PICKER", [
        ("move within a row", "h  /  l  /  Left  /  Right"),
        ("move a whole row", "j  /  k  /  Down  /  Up"),
        ("first / last theme", "g  /  Shift g"),
        ("apply", "Enter  /  Space"),
        ("close", "Escape"),
    ]),
    ("WALLPAPER PICKER", [
        ("move", "h  /  l  /  Left  /  Right  /  Tab  /  Shift Tab"),
        ("jump to a random wallpaper", "r"),
        ("apply — the only key that writes", "Enter"),
        ("close", "Escape"),
    ]),
    ("REACHING THESE PANELS", [
        ("island settings", "ALT 7"),
        ("application launcher", "SUPER Shift Return  /  SUPER d"),
        ("kill a process", "SUPER p  then  k"),
        ("close a window", "SUPER p  then  Shift k"),
        ("go to workspace", "SUPER p  then  j"),
        ("Wi-Fi list", "SUPER p  then  n"),
        ("Bluetooth list", "SUPER p  then  b"),
        ("this sheet", "SUPER Shift k  then  i"),
    ]),
]


# ---- THE DOCS AND TROUBLESHOOTING SHEETS -------------------------------
#
# `$mod SHIFT /` was asked for as "like i am clicking on win+? ... will show
# all the documentation keymaps troubleshooting etc". The keymaps half
# already existed — this file has generated it from `hyprctl binds -j`
# since the panel was built, which is why it cannot drift. These two
# sheets are the other half.
#
# They are PROSE, not generated, and that is a deliberate difference from
# the WM sheet. A troubleshooting entry is a claim about what a symptom
# MEANS, and there is nothing to derive it from; the honest thing is to
# write it down and let it be reviewed, rather than to synthesise it from
# something that does not know.
#
# Every troubleshooting row is a symptom and the command that PROVES the
# cause, never a description of the cause. Which of the two is drawn on
# the left differs between the two renderings and is deliberately not
# claimed in the note: render() prints the label first, while the panel
# puts `combo` in the chip because that is the field it sizes to fit. Each of these has actually
# happened on this machine, and every one of them failed SILENTLY — which
# is the whole reason the column on the right is a command and not advice.
TROUBLE_SECTIONS = [
    ("THE SHELL", [
        ("reloaded cleanly but nothing changed",
         "tail $XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log"),
        ("which instance is live",
         "ls -t $XDG_RUNTIME_DIR/quickshell/by-id/ | head -1"),
        ("edit landed after its own reload",
         "compare last 'Configuration Loaded' to the file mtime"),
        ("Metrics.js / Motion.js edit does nothing",
         ".pragma library JS is cached -- restart the island"),
        ("an IPC call did nothing",
         "qs -p ~/.config/quickshell/tide-island-fork ipc show"),
        ("...and reported success anyway",
         "qs ipc call prints 'Function not found' and EXITS 0"),
        ("a function is missing from ipc show",
         "an untyped IpcHandler parameter is dropped silently"),
    ]),
    ("THE COMPOSITOR", [
        ("island shows the wrong workspace",
         "hyprctl activeworkspace -j | jq '{id,name}'"),
        ("...or every window at once",
         "named workspaces are NEGATIVE -- S is -1337"),
        ("a keybinding does nothing",
         "hyprctl binds -j | jq -r '.[]|\"\\(.key) \\(.dispatcher)\"'"),
        ("a scratchpad lost its window",
         "hyprctl clients -j | jq -r '.[]|\"\\(.workspace.name) \\(.class)\"'"),
        ("a listener stopped reacting",
         "ls -l $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"),
    ]),
    ("COLOUR AND FONTS", [
        ("night light does nothing",
         "qs ... ipc call nightlight status ; pacman -Q hyprsunset"),
        ("gammastep appears to work and does not",
         "gammastep -P -O 4500   # 'Zero outputs', then it hangs"),
        ("hyprsunset temperature looks wrong",
         "it reports the last value REQUESTED, not the effective one"),
        ("a screenshot shows no gamma change",
         "it cannot -- the transform is applied at scanout"),
        ("a font silently became Noto Sans CJK",
         "fc-match \"Inter Display\""),
        ("the theme did not reach everything",
         "theme-apply <theme> ; watch for THEME_APPLY_VISIBLE_DONE"),
    ]),
    ("WALLPAPER", [
        ("a theme change did not change the wallpaper",
         "theme-wallpaper list"),
        ("a theme is stuck on one image",
         "it is bound -- theme-wallpaper forget <theme>"),
        ("what is in a theme's set",
         "theme-wallpaper set <theme>"),
        ("the wallpaper daemon is not answering",
         "awww query"),
    ]),
    ("PROCESS TRAPS", [
        ("pkill -f killed the wrong thing",
         "it matches its own command line -- use pkill -x"),
        ("a pgrep -f check is always true",
         "ps -eo args | awk '/pat/ && !/awk/'"),
    ]),
]

# Where the long-form answers live. A pointer sheet rather than a copy:
# duplicating MIGRATION.md into a panel would create a second copy to keep
# true, and the first thing anyone needs is to know which file to open.
DOCS_SECTIONS = [
    ("HYPRLAND", [
        ("overview, and this troubleshooting list in full",
         "~/.config/hypr/README.md"),
        ("what every qtile feature became",
         "~/.config/hypr/MIGRATION.md"),
        ("the requested scope, and each item's status",
         "~/.config/hypr/REQUIREMENTS.md"),
        ("the audit trail -- append, never rewrite",
         "~/.config/hypr/upgread_UI_UX.md"),
        ("the visual language the shell is held to",
         "~/.config/hypr/DESIGN-SPEC.md"),
    ]),
    ("CONFIG", [
        ("keybindings and submaps", "~/.config/hypr/binds.conf"),
        ("window rules, and workspace homes", "~/.config/hypr/rules.conf"),
        ("gaps, borders, blur, animations", "~/.config/hypr/looks.conf"),
        ("written by theme-apply -- do not edit", "~/.config/hypr/colors.conf"),
        ("the shell", "~/.config/quickshell/tide-island-fork/"),
    ]),
    ("PACKAGES", [
        ("how this machine decides what is installed",
         "~/.config/arch-config/README.md"),
        ("both sessions' window-manager packages",
         "~/.config/arch-config/modules/wm.yaml"),
        ("what is installed but not declared",
         "./installScripts/wizard.sh --audit"),
        ("the gate every commit passes",
         "./installScripts/validate.sh"),
    ]),
    ("THEMES AND WALLPAPER", [
        ("apply a theme everywhere", "theme-apply <theme>"),
        ("every theme and its set size", "theme-wallpaper list"),
        ("bind the current image to a theme", "theme-wallpaper bind <theme> <img>"),
        ("hand a theme back to its set", "theme-wallpaper forget <theme>"),
        ("rebuild the per-theme sets", "ati-theme-wallpaper-fetch build --apply"),
    ]),
]


def prose_rows(sections):
    return [(title, list(rows)) for title, rows in sections]


def island_rows():
    """The island's own keymaps. See the note above on why this is a copy."""
    return [(title, list(rows)) for title, rows in ISLAND_SECTIONS]


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
    elif which == "island":
        sections = island_rows()
        title = "TIDE ISLAND KEYS"
        note = "These live in QML, not in hyprctl binds -- see cheatsheet.py."
    elif which in ("trouble", "troubleshooting"):
        sections = prose_rows(TROUBLE_SECTIONS)
        title = "TROUBLESHOOTING"
        note = "Each row: a symptom, and the command that PROVES the cause."
    elif which == "docs":
        sections = prose_rows(DOCS_SECTIONS)
        title = "DOCUMENTATION"
        note = "Where the long-form answers live."
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


def submap_keys_from_qtile(name):
    """The live bindings of one qtile CHORD, in the same shape as a submap's.

    ---- WHY THIS EXISTS ----

    The island's mode HUD (qml/island/ModeKeysLayer.qml) is the same panel in
    both sessions, and it asks this file for its rows. Under Hyprland the rows
    come from `hyprctl binds`. Under qtile there is no hyprctl, so the HUD
    came up with an empty list and the chord looked like it had no keys --
    reported as "the rofi mode popup and the media and other modes not working
    like the one in Hyprland".

    qtile can answer the identical question about its own chords, so it is
    asked, and the answer is shaped to match submap_keys_json() exactly: the
    QML never learns there are two sources.

    Names are qtile's own chord names ("Rofi-Mode", "Media-Mode"), which is
    what config.py passes to `showModeKeys` -- there is no translation table
    to drift, because both ends use the name qtile already has.

    _find_chord() is used rather than a flat scan over `keys` because chords
    nest: WallpaperPicker lives inside Rofi-Mode.
    """
    # Built as ONE expression because `qtile cmd-obj -f eval` returns the
    # value of what it evaluates; a statement would return None.
    #
    # The raw fields come back and the LABEL is composed here, in Python,
    # rather than inside the eval string: half these keys carry no `desc`
    # (Media-Mode's six are bare lazy.spawn calls), so a label has to be
    # derived from the command, and doing that inside a one-line expression
    # would be unreadable and unfixable.
    code = (
        '__import__("json").dumps('
        '[{"key": ("+".join(k.modifiers) + "+" if k.modifiers else "") + k.key,'
        '  "desc": (getattr(k, "desc", "") or getattr(k, "name", "") or ""),'
        '  "cmd": (getattr(getattr(k, "commands", [None])[0], "name", "") '
        '          if getattr(k, "commands", None) else ""),'
        '  "arg": (str(getattr(getattr(k, "commands", [None])[0], "args", ("",))[:1] or ("",))'
        '          if getattr(k, "commands", None) else "")}'
        ' for k in (lambda c: c.submappings if c else [])'
        '(__import__("sys").modules["config"]._find_chord(%r))])' % name
    )
    try:
        raw = subprocess.run(["qtile", "cmd-obj", "-o", "cmd", "-f", "eval",
                              "-a", code],
                             capture_output=True, text=True, timeout=6)
        # eval answers with its value JSON-encoded, so the payload is a JSON
        # string that itself contains JSON.
        rows = json.loads(json.loads(raw.stdout))
    except (OSError, ValueError, subprocess.SubprocessError, TypeError):
        return []

    out = []
    for row in rows:
        key = str(row.get("key") or "").strip()
        if not key:
            continue
        # qtile spells its modifiers as X11 mod names; the sheet reads better
        # with the same words the rest of this file uses.
        key = (key.replace("mod4", "SUPER").replace("mod1", "ALT")
                  .replace("control", "CTRL").replace("shift", "SHIFT"))
        action = str(row.get("desc") or "").strip()
        if not action:
            # No desc: say what the key RUNS. A bare lazy.spawn is the common
            # case (Media-Mode is six of them), and "playerctl next" is a far
            # better row than a blank one.
            arg = str(row.get("arg") or "").strip("()',[] ").strip()
            cmd = str(row.get("cmd") or "").strip()
            if cmd == "spawn" and arg:
                # Through the SAME prettifier the Hyprland HUD uses, so one
                # chord key reads identically in both sessions. It matters
                # here for the same reason it mattered there: qtile spawns
                # `bar-action tide <function>` too, and the raw string is the
                # wrapper's name plus a function nobody typed.
                action = short_label({"dispatcher": "exec", "arg": arg})
            elif cmd == "function":
                # lazy.function(...) carries a callable, and its repr is not a
                # label. A bound method still names itself usefully; a lambda
                # does not, and a row reading "<function <lambda> at 0x7f...>"
                # is worse than a row with no description -- which is also
                # exactly what qtile's own chord chip shows for these keys.
                bound = re.search(r"bound method [\w.]*?(\w+) of", arg)
                action = bound.group(1).replace("_", " ") if bound else ""
            elif cmd:
                action = ("%s %s" % (cmd, arg)).strip()
            action = action[:60]
        # A chord's own Escape/q exits are noise in a list of what the mode
        # DOES, exactly as the submap version drops its `submap reset` binds.
        if key.lower() in ("escape", "q") or action == "ungrab chord":
            continue
        out.append({"key": key, "action": action})

    # The nine group binds every chord repeats are true and are also nine of
    # the rows. Collapsed exactly as the Hyprland path collapses its
    # workspace binds, so both sessions read the same.
    digits = [r for r in out if r["key"].isdigit()]
    if len(digits) > 3:
        out = [r for r in out if not r["key"].isdigit()]
        out.append({"key": "1-9", "action": "group"})
    return out


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
    if not os.environ.get("WAYLAND_DISPLAY"):
        # X11: qtile owns the chords, and hyprctl does not exist. See
        # submap_keys_from_qtile() for why the shape is identical.
        return json.dumps({"name": name, "keys": submap_keys_from_qtile(name)})

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

    if which == "island":
        show(render(island_rows(), "TIDE ISLAND KEYS"), "island")
        return 0

    if which in SOURCES:
        filename, title = SOURCES[which]
        show(render(parsed_rows(filename), title), which)
        return 0

    print("usage: cheatsheet.py hypr|vim|fish|island", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
