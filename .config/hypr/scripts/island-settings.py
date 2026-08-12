#!/usr/bin/env python3
"""island-settings.py — read and write ~/.config/tide-island/userconfig.json.

WHY THIS EXISTS AT ALL
----------------------
tide-island ships a settings application, /usr/bin/tide-island-config-app.
It is a COMPILED C++/Qt binary from the pacman package `tide-island 1.0.34-1`
(`pacman -Qo /usr/bin/tide-island-config-app`), so it cannot be patched in
place, and a locally built replacement is silently overwritten by the next
`yay -Syu` — which is the same trap FORK-NOTES.md records for the vendored
QML tree, except that this one leaves no diff behind to notice.

So the settings surface is an island STATE in the fork instead
(qml/island/SettingsLayer.qml), and this script is its backend, the same way
audio-ctl.py backs the audio panel and cheatsheet.py backs the chord HUD.

THE ONE RULE: THE ANNOTATIONS MUST SURVIVE
------------------------------------------
userconfig.json is not a plain settings dump. Every divergence from upstream
carries a sibling `_key` entry explaining it — `_height` says why the island
is not the spec's 38, `_opacity` says why it is not upstream's 60, `_wallpaper`
says why pywal is off. Those comments are the only record of a dozen
decisions, and a writer that serialised its own idea of the file would delete
all of them in one save with nothing on screen to say so.

They survive because this reads the file, mutates ONE key of the parsed
object, and writes the object back. `json.load` into a dict preserves
insertion order (guaranteed since CPython 3.7) and `_`-prefixed keys are
ordinary keys to it, so both the comments and their position relative to what
they annotate come through untouched.

MEASURED, and the reason this was checked rather than assumed: the compiled
config app has ALREADY rewritten this file once. The live file is 4-space
indented with keys sorted alphabetically, while the template it came from
(userconfig.json.tmpl, which wizard.sh installs) is 2-space indented and
grouped by topic with blank lines. The blank lines and the grouping are gone.
Every `_key` annotation is still there. So the packaged app preserves unknown
keys and destroys formatting; this script preserves both, and matches the
4-space style the file is now in so that the two writers do not fight over
whitespace on alternate saves.

KEYS THE PACKAGED APP DOES NOT KNOW
-----------------------------------
`fork*` keys are read by fork QML (qml/common/ForkConfig.qml) and by nothing
else. UserConfigBackend ignores keys it has no property for — verified from
its own type registration, /usr/lib/qt6/qml/IslandBackend/IslandBackend.qmltypes,
which lists exactly 39 properties and no fork ones — so they are inert to the
packaged app and to the packaged config app, and survive both.

Usage:
    island-settings.py --list                 # descriptors + current values
    island-settings.py --set <key> <value>    # write one key, atomically
"""

import json
import os
import shutil
import sys
import tempfile

CONFIG = os.path.expanduser("~/.config/tide-island/userconfig.json")

# The settings the panel offers, in the order it shows them.
#
# WHAT EARNED A ROW HERE
# ----------------------
# Two tests, both deliberately narrow. A key is here if it is either
#
#   1. something changed more than once while living with this shell, or
#   2. FORK-ONLY — a thing the packaged config app has no row for at all,
#      because those are the ones with nowhere else to go.
#
# Everything else is left to the file. A settings panel that mirrors all 39
# backend properties is a worse text editor: the file is annotated, the panel
# cannot be, and nobody edits `wallpaperTransitionBezier` from a keyboard
# grab twice.
#
# `scope` is shown in the panel and is not decoration — "fork" means the
# packaged config app cannot see this key and will not show it to you, which
# is the single most useful thing to know while looking at a row.
SETTINGS = [
    {
        "key": "forkNotchMode",
        "label": "Notch mode",
        "type": "bool",
        "default": True,
        "scope": "fork",
        "detail": "Flush to the top edge with square top corners and a concave "
                  "flare each side. Off is upstream's floating island, "
                  "islandTopMargin below the edge with all four corners round. "
                  "One shape, interpolated — DESIGN-SPEC.md's notchProgress.",
    },
    {
        "key": "forkModeKeysEnabled",
        "label": "Chord key HUD",
        "type": "bool",
        "default": True,
        "scope": "fork",
        "detail": "Entering a Hyprland submap draws that mode's keys in the "
                  "island. Off falls back to the mode NAME alone, which is what "
                  "submap-indicator.sh did before ModeKeysLayer existed.",
    },
    {
        "key": "forkRestingEqEnabled",
        "label": "Resting EQ bars",
        "type": "bool",
        "default": True,
        "scope": "fork",
        "detail": "The 4-bar cava visualiser beside the clock, which animates "
                  "only while something is actually playing. DESIGN-SPEC.md's "
                  "resting state is exactly this and the clock, nothing else.",
    },
    {
        "key": "forkThemeTransitionEnabled",
        "label": "Theme reveal animation",
        "type": "bool",
        "default": True,
        "scope": "fork",
        "detail": "Applies a theme behind a frozen screenshot with a circular "
                  "wipe (REQUIREMENTS.md item 5). Off applies theme-apply "
                  "directly, which repaints the desktop in stages.",
    },
    # NOT IMPLEMENTED, and listed anyway so the half that exists is visible
    # rather than lurking.
    #
    # The island state, its size cases and its show/clear functions were
    # written; `qml/island/PolkitPromptLayer.qml` was NOT, and nothing
    # anywhere registers a polkit agent — this key is read into
    # ForkConfig.polkitAgentEnabled and no code consumes that property. So
    # the toggle is INERT: it cannot replace the KDE agent and cannot show a
    # prompt.
    #
    # The previous wording on this row said "DANGER. Registers this shell as
    # the session polkit agent", which described behaviour that does not
    # exist — a warning about an imaginary hazard, on a control that does
    # nothing. That is worse than either a real warning or no row, because it
    # is the kind of thing a future reader trusts.
    #
    # polkit-kde-authentication-agent-1 remains the registered agent in
    # autostart.conf and is untouched. The real hazard, whenever this IS
    # built: a wrong agent means NO password prompt anywhere on the system —
    # no pkexec, no auth dialog — and it fails silently until you need one.
    # So it must be proven alongside the KDE agent before replacing it.
    {
        "key": "forkPolkitAgentEnabled",
        "label": "Island polkit prompt",
        "type": "bool",
        "default": False,
        "scope": "fork",
        "enabled": False,
        "detail": "NOT IMPLEMENTED. The panel was never written and no polkit "
                  "agent is registered by this shell, so this switch does "
                  "nothing. polkit-kde-authentication-agent-1 is still the "
                  "session's agent and is unaffected.",
    },
    {
        "key": "clockFormat",
        "label": "Clock format",
        "type": "enum",
        "values": ["12", "24"],
        "default": "24",
        "scope": "packaged",
        "detail": "24 matches hyprlock.conf's `date +%H:%M`, so the lock screen "
                  "and the notch cannot disagree. Upstream defaults to 12.",
    },
    {
        "key": "islandHeight",
        "label": "Island height",
        "type": "int",
        "min": 20,
        "max": 60,
        "step": 1,
        "default": 32,
        "scope": "packaged",
        "detail": "DESIGN-SPEC.md says 38, measured off a 2560x1440 screen. "
                  "qtile's bar was 28 and was the known-good daily driver. "
                  "Metrics.js's NOTCH_SCALE is derived from this number.",
    },
    {
        "key": "islandWidth",
        "label": "Island width",
        "type": "int",
        "min": 60,
        "max": 260,
        "step": 4,
        "default": 120,
        "scope": "packaged",
        "detail": "The COLLAPSED width, for the clock alone. The resting EQ "
                  "adds its own allowance on top while music plays.",
    },
    {
        "key": "islandTopMargin",
        "label": "Floating gap",
        "type": "int",
        "min": 0,
        "max": 40,
        "step": 1,
        "default": 11,
        "scope": "packaged",
        "detail": "The gap below the screen edge in FLOATING form only. The "
                  "notch is flush, so this is what the morph interpolates back "
                  "to when notch mode is off — it is not dead while it is on.",
    },
    {
        "key": "islandExclusiveZone",
        "label": "Reserved strip",
        "type": "int",
        "min": 0,
        "max": 80,
        "step": 1,
        "default": 33,
        "scope": "packaged",
        "detail": "How much of the top edge windows are kept out of. Below "
                  "islandHeight and windows slide under the notch.",
    },
    {
        "key": "islandBackgroundOpacity",
        "label": "Shape opacity",
        "type": "int",
        "min": 0,
        "max": 100,
        "step": 5,
        "default": 100,
        "scope": "packaged",
        "detail": "100 because the shape is imitating bezel and bezel is not "
                  "translucent. Upstream defaults to 60.",
    },
    {
        "key": "islandAutoHideEnabled",
        "label": "Auto-hide",
        "type": "bool",
        "default": False,
        "scope": "packaged",
        "detail": "Off because the spec's pill is permanently present rather "
                  "than summoned. There is no bar behind it to fall back to.",
    },
]

BY_KEY = {entry["key"]: entry for entry in SETTINGS}


def load():
    """The parsed config, or {} when there is not one yet.

    A missing or unreadable file is NOT an error here. --list still has to
    answer, because a panel that shows nothing when the file is absent looks
    identical to a panel that is broken; with defaults it shows the settings
    and writing one creates the file.
    """
    try:
        with open(CONFIG, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def coerce(entry, raw):
    """Turn a command-line string into the JSON type the key expects.

    Typed rather than passed through, because the backend reads these by C++
    type: `"islandHeight": "32"` is a string where an int is expected, and the
    property comes back as 0 rather than as an error. The island then has no
    height and the failure looks like the shell not starting.
    """
    kind = entry["type"]
    if kind == "bool":
        return str(raw).strip().lower() in ("1", "true", "yes", "on")
    if kind == "int":
        value = int(float(raw))
        return max(entry["min"], min(entry["max"], value))
    if kind == "enum":
        text = str(raw)
        if text not in entry["values"]:
            raise ValueError("not one of %s" % ", ".join(entry["values"]))
        return text
    return str(raw)


def write(key, raw):
    entry = BY_KEY.get(key)
    if entry is None:
        raise ValueError("unknown key %s" % key)

    data = load()
    data[key] = coerce(entry, raw)

    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)

    # Written to a temp file in the SAME directory and renamed over the
    # original, never opened "w" in place.
    #
    # os.replace is atomic within a filesystem, so a reader can only ever see
    # the whole old file or the whole new one. That matters more here than it
    # would for most config: the fork's ForkConfig.qml WATCHES this path, so
    # a truncate-then-write would give it a real chance to parse a
    # half-written file. IslandTheme.qml already records that failure mode
    # from the other side, which is where the pattern comes from.
    #
    # indent=4 and ensure_ascii=False match what the compiled config app
    # leaves behind, so the two writers do not produce a whole-file diff on
    # alternate saves. Key ORDER is whatever load() read, so the `_key`
    # annotations stay next to what they annotate.
    directory = os.path.dirname(CONFIG)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=directory, delete=False, suffix=".tmp")
    try:
        json.dump(data, handle, indent=4, ensure_ascii=False, sort_keys=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
        handle.close()
        shutil.copymode(CONFIG, handle.name) if os.path.exists(CONFIG) else None
        os.replace(handle.name, CONFIG)
    except BaseException:
        handle.close()
        try:
            os.unlink(handle.name)
        except OSError:
            pass
        raise

    return data[key]


def describe():
    data = load()
    rows = []
    for entry in SETTINGS:
        row = dict(entry)
        row["value"] = data.get(entry["key"], entry["default"])
        rows.append(row)
    return {"path": CONFIG, "settings": rows}


def main(argv):
    if len(argv) >= 2 and argv[1] == "--list":
        json.dump(describe(), sys.stdout)
        sys.stdout.write("\n")
        return 0

    if len(argv) >= 4 and argv[1] == "--set":
        try:
            value = write(argv[2], argv[3])
        except (ValueError, OSError) as error:
            json.dump({"ok": False, "error": str(error)}, sys.stdout)
            sys.stdout.write("\n")
            return 1
        json.dump({"ok": True, "key": argv[2], "value": value}, sys.stdout)
        sys.stdout.write("\n")
        return 0

    sys.stderr.write(__doc__.strip().splitlines()[-2] + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
