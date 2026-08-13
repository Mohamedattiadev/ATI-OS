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
its own type registration,
/usr/lib/qt6/qml/IslandBackend/IslandBackend.qmltypes — so they are inert to
the packaged app and to the packaged config app, and survive both.

CORRECTION, measured 2026-08-12: this paragraph previously said that file
"lists exactly 39 properties". It lists 44 on tide-island 1.0.34-1. The count
was wrong; the load-bearing half of the claim — that NONE of them is a fork
key — re-checked and still true, which is why the conclusion stands. The 44
are enumerated in BACKEND_PROPERTIES below, and the miscount is the reason
they are now written down rather than described.

USER-DEFINED ROWS
-----------------
The table below is curated and deliberately short (see "WHAT EARNED A ROW
HERE"). ~/.config/tide-island/settings-extra.json extends it without editing
this script: see load_extra() for the format and the merge rules.

The thing that file cannot do is make a key MEAN anything. A row here is a
writer, not an implementation — the packaged keys work because
UserConfigBackend has a property of that name, and the `fork*` keys work
because ForkConfig.qml reads them and fork QML consumes them. A key that
neither reads is INERT: the panel will show it, the write will succeed, the
file will gain the key, and nothing will happen. That was exactly the
forkPolkitAgentEnabled situation — see the note where its row used to be —
and it is the single most likely way to be confused by this feature, so
scope="packaged" keys are checked against BACKEND_PROPERTIES and warned
about.

Usage:
    island-settings.py --list                 # descriptors + current values
    island-settings.py --set <key> <value>    # write one key, atomically
    island-settings.py --check                # validate settings-extra.json
"""

import json
import os
import shutil
import sys
import tempfile

CONFIG = os.path.expanduser("~/.config/tide-island/userconfig.json")

# The user's own rows. Beside userconfig.json rather than in the fork tree,
# because the fork tree is a vendored copy that gets diffed against upstream
# and this is personal configuration, not a fork change.
EXTRA = os.path.expanduser("~/.config/tide-island/settings-extra.json")

# Every property UserConfigBackend actually has, read out of
# /usr/lib/qt6/qml/IslandBackend/IslandBackend.qmltypes on tide-island
# 1.0.34-1. Used for ONE thing: warning when a user row claims
# scope="packaged" for a name the backend has never heard of, which is the
# inert-key trap in the module docstring.
#
# A warning and not a rejection, deliberately — this list is a snapshot of a
# packaged file and a package update that adds a key would otherwise turn a
# correct row into an error. Being out of date should cost a spurious note,
# never a working setting.
BACKEND_PROPERTIES = frozenset([
    "userConfigPath", "configError",
    "defaultWallpaperPath", "defaultTlpSudoPassword",
    "wallpaperPath", "wallpaperLibraryPath", "wallpaperPywalEnabled",
    "wallpaperCustomCommandEnabled", "wallpaperCustomCommand",
    "wallpaperTransitionType", "wallpaperTransitionStep",
    "wallpaperTransitionDuration", "wallpaperTransitionFps",
    "wallpaperTransitionAngle", "wallpaperTransitionPosition",
    "wallpaperTransitionBezier", "wallpaperTransitionWave",
    "wallpaperTransitionInvertY",
    "iconFontFamily", "textFontFamily", "heroFontFamily", "timeFontFamily",
    "clockFormat", "tlpSudoPassword", "tlpPermissionMode",
    "workspaceOverviewWindowDragButton",
    "dynamicIslandPrimaryButton", "dynamicIslandPrimaryAction",
    "dynamicIslandSecondaryButton", "dynamicIslandSecondaryAction",
    "dynamicIslandLeftSwipeItems", "disableAutoExpandOnTrackChange",
    "hoverExpandAction",
    "islandAutoHideEnabled", "islandAutoHideDelayMs",
    "islandWidth", "islandHeight", "islandExclusiveZone", "islandTopMargin",
    "islandPositionX", "islandBackgroundOpacity",
    "bodyFontSize", "titleFontSize", "iconFontSize",
])

# No "string". SettingsLayer.qml's change() has a branch for bool, enum and
# int and none for free text — there is no keyboard-entry field in this panel
# and adding one to a layer that lives under a Hyprland keyboard grab is a
# different piece of work. A string row would render, show its value, and
# ignore every keypress, which is the inert-row failure again. An enum covers
# the case where the string is one of a known few (clockFormat is one).
# "list" is an ORDERED SUBSET of `values`, and both halves of that matter.
# It exists for dynamicIslandLeftSwipeItems — the cpu/battery/ram readout —
# where the answer to "what is in the island" and the answer to "in what
# order" are the same setting. Modelling it as one boolean per item would
# have been a smaller change to this file and would have thrown the ordering
# away, which is half of what the row is for.
TYPES = ("bool", "int", "enum", "list")

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
    # There was a `forkPolkitAgentEnabled` row here, labelled "Island polkit
    # prompt", carrying a detail that began "NOT IMPLEMENTED". It is gone,
    # along with the island state, the IPC calls and the ForkConfig key it
    # nominally controlled.
    #
    # Two earlier wordings of that row are worth keeping as wrong answers.
    # The first said "DANGER. Registers this shell as the session polkit
    # agent" — a warning about a hazard that did not exist, on a control that
    # did nothing. The second, honest about being inert, still left a switch
    # on screen for a feature nobody was going to finish. The row was never
    # the problem; the half-built state behind it was, and that state could
    # be reached over IPC without touching this panel at all.
    #
    # polkit-kde-authentication-agent-1 (autostart.conf:23) is the session's
    # agent, was never displaced, and is untouched.
    {
        "key": "forkRingOsdEnabled",
        "label": "Ring OSD",
        "type": "bool",
        "default": False,
        "scope": "fork",
        "detail": "Draws volume and brightness as a circular ring in the "
                  "lower third of the screen instead of in the island's "
                  "split capsule. The island already had a ring — this moves "
                  "it off the notch, which is what a machine-wide change "
                  "should look like. Only GAUGE calls move: the mode "
                  "indicator and showText have no value to plot and stay in "
                  "the island.",
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
    {
        "key": "islandAutoHideDelayMs",
        "label": "Auto-hide delay",
        "type": "int",
        "min": 100,
        "max": 10000,
        "step": 100,
        "default": 2500,
        "scope": "packaged",
        "detail": "How long the island stays up after being summoned, before "
                  "hiding again. Bounded at 100 and 10000 here because "
                  "DynamicIslandWindow clamps it to exactly that range in two "
                  "places before handing it to autoHideHideTimer, and a row "
                  "whose limits disagree with its consumer's is a row that "
                  "reports a value the shell is not using. Inert while "
                  "Auto-hide is off, which is a property of the feature and "
                  "not a fault in the row — the same is already true of Peek "
                  "workspace when hidden.",
    },
    {
        "key": "tlpPermissionMode",
        "label": "TLP battery mode auth",
        "type": "enum",
        "values": ["ask", "password", "skip"],
        "default": "ask",
        "scope": "packaged",
        "detail": "How the control centre's battery-mode switch gets root. "
                  "`ask` runs pkexec and lets the agent prompt; `password` "
                  "uses the stored tlpSudoPassword; `skip` disables the "
                  "control entirely and the card reads 'TLP disabled'. These "
                  "are exactly the three strings ControlCenterLayer branches "
                  "on. tlpSudoPassword itself deliberately has NO row: a "
                  "settings list that renders a password back to the screen "
                  "is a worse place to keep one than the file.",
    },
    # ================================================================
    #  TYPOGRAPHY, INTERACTION AND PLACEMENT
    # ================================================================
    #
    # FORK: asked for as "a fully controlled customizable app ... to add
    # whatever I want in whatever place in the island and control anything".
    #
    # Every row below is a key that something ALREADY READS. That is the
    # whole selection rule and it is not a formality: this tree's own
    # history is a list of controls that ran a binary which did not exist,
    # wrote a state nobody polled, or drove a loader that was never
    # declared. A settings panel is the worst possible place to add another,
    # because a row that does nothing looks exactly like a row that works
    # until the moment you need it.
    #
    # So these were checked one at a time against userconfig.json and
    # against the QML that consumes them, and keys that LOOK configurable
    # but are inert were left out. Notably absent, and deliberately:
    #
    #   dynamicIslandLeftSwipeItems  — the cpu/battery/ram row. This is the
    #       one the request most obviously means, and it cannot be added
    #       yet: it is a LIST, and the schema here has bool, int and enum.
    #       A list needs a reorderable multi-select in SettingsLayer, which
    #       is a UI change rather than a row. Written up rather than faked
    #       as three booleans, which would lose the ordering that is half
    #       the point of the setting.
    #
    #   forkStatHighThreshold — the 85% at which a stat glyph turns red.
    #       Lives in SwipeCustomInfoLayer as a QML property with no
    #       userconfig key behind it, so a row would write a value nothing
    #       reads.
    {
        "key": "dynamicIslandLeftSwipeItems",
        "label": "Swipe readout",
        "type": "list",
        "values": ["cpu", "ram", "storage", "battery", "volume",
                   "brightness", "workspace", "time", "date", "cava"],
        "default": ["cpu", "battery", "ram"],
        "scope": "packaged",
        "detail": "What the island shows when you swipe left, and in what "
                  "order. The ten values are exactly the cases "
                  "IslandSystemState.buildCustomSwipeItem answers to — "
                  "anything else renders as an empty slot rather than as an "
                  "error, which is why this is a closed list and not free "
                  "text. Order is left to right. `cava` is the audio "
                  "visualiser and draws bars instead of a number; `time` and "
                  "`date` duplicate the resting clock and are offered because "
                  "the swipe row is also what shows while the clock is "
                  "covered.",
    },
    {
        "key": "bodyFontSize",
        "label": "Body text size",
        "type": "int",
        "min": 8,
        "max": 20,
        "step": 1,
        "default": 12,
        "scope": "packaged",
        "detail": "The base size for every label, status line and readout. "
                  "The resting clock renders at bodyFontSize + 1, so 12 puts "
                  "it at 13 and lands exactly on qtile's widget_defaults "
                  "fontsize 10, which is ~13px at 96dpi.",
    },
    {
        "key": "titleFontSize",
        "label": "Title text size",
        "type": "int",
        "min": 10,
        "max": 26,
        "step": 1,
        "default": 15,
        "scope": "packaged",
        "detail": "Panel headings only. Kept in ratio with body — the pair "
                  "was 20/16 in a 38px shape and is 15/12 in this one.",
    },
    {
        "key": "iconFontSize",
        "label": "Icon size",
        "type": "int",
        "min": 8,
        "max": 24,
        "step": 1,
        "default": 13,
        "scope": "packaged",
        "detail": "Nerd Font glyphs. Note the swipe row's stat pictograms "
                  "deliberately render at this + 5: a chip or a memory stick "
                  "needs ~1.5x a cap height to resolve, where a plain symbol "
                  "does not. Raising this raises both.",
    },
    {
        "key": "islandPositionX",
        "label": "Horizontal position",
        "type": "int",
        "min": 0,
        "max": 100,
        "step": 5,
        "default": 50,
        "scope": "packaged",
        "detail": "Percent across the output. 50 centres the notch. Only "
                  "meaningful in floating form — a notch is bezel and bezel "
                  "that is off-centre reads as a mistake.",
    },
    {
        "key": "hoverExpandAction",
        "label": "Hover opens",
        "type": "enum",
        "values": ["0", "1", "2"],
        "default": "0",
        "scope": "packaged",
        "detail": "What merely passing the pointer over the notch opens. "
                  "0 nothing, 1 the media player, 2 the control centre. Held "
                  "at 0 here on purpose: a panel that appears on hover also "
                  "declines the keyboard grab, because taking one on a hover "
                  "would send the next character you type to the island "
                  "instead of your window.",
    },
    {
        "key": "dynamicIslandPrimaryAction",
        "label": "Left click",
        "type": "enum",
        "values": ["toggleControlCenter", "toggleExpandedPlayer",
                   "toggleNotificationCenter", "none"],
        "default": "toggleControlCenter",
        "scope": "packaged",
        "detail": "Swapped from the packaged default on request: upstream "
                  "puts the player on button 1 and the control centre on "
                  "button 3. Written down explicitly rather than left unset, "
                  "because an unset key means the behaviour lives in a "
                  "compiled binary where nothing on this machine records it.",
    },
    {
        "key": "dynamicIslandSecondaryAction",
        "label": "Right click",
        "type": "enum",
        "values": ["toggleExpandedPlayer", "toggleControlCenter",
                   "toggleNotificationCenter", "none"],
        "default": "toggleExpandedPlayer",
        "scope": "packaged",
        "detail": "The other half of the swap above.",
    },
    {
        "key": "disableAutoExpandOnTrackChange",
        "label": "Stay collapsed on track change",
        "type": "bool",
        "default": True,
        "scope": "packaged",
        "detail": "DESIGN-SPEC.md is explicit that media must NOT expand the "
                  "shape — it swaps the content while the geometry stays put, "
                  "'a different mechanism entirely'. On means the spec's "
                  "behaviour; off restores upstream's pop-out.",
    },
    {
        "key": "islandShowWorkspaceOnAutoHide",
        "label": "Peek workspace when hidden",
        "type": "bool",
        "default": False,
        "scope": "packaged",
        "detail": "Only has an effect with Auto-hide on, which it is not by "
                  "default — so this row is inert until that one is switched, "
                  "and that is a property of the feature rather than a fault "
                  "in the row.",
    },
    {
        "key": "wallpaperPywalEnabled",
        "label": "Wallpaper drives the palette",
        "type": "bool",
        "default": False,
        "scope": "packaged",
        "detail": "OFF deliberately, and turning it on is a real hazard "
                  "rather than a preference. AtiScriptsV1/theme-apply already "
                  "owns pywal for BOTH sessions and wallpaper-sync.sh feeds "
                  "hyprpaper from the same cache. Enabling this gives two "
                  "independent things an opinion about one palette, and the "
                  "qtile session is the one that drifts.",
    },
]

def validate(row):
    """Every reason `row` is not a usable descriptor, as a list of strings.

    Run on the row AFTER merging, never on the user's fragment alone. An
    override that sets `"type": "int"` on a bool row is only wrong once you
    can see that the result has no min/max, and validating the fragment would
    have called it fine.
    """
    errors = []
    kind = row.get("type")

    if kind not in TYPES:
        errors.append("type must be one of %s, got %r" % ("/".join(TYPES), kind))
        # Nothing below can be judged without knowing the type.
        return errors

    for field in ("label", "scope"):
        if not isinstance(row.get(field), str) or not row[field]:
            errors.append("%s must be a non-empty string" % field)

    # Two values and no "user", because scope answers "which consumer reads
    # this key" and there are exactly two consumers: UserConfigBackend, and
    # fork QML via ForkConfig.qml. Where the ROW came from is a different
    # question and `source` answers it — a third scope value would put
    # provenance and consumer in one field and the panel chips them apart.
    if row.get("scope") not in ("packaged", "fork"):
        errors.append('scope must be "packaged" or "fork"')

    if kind == "int":
        for bound in ("min", "max"):
            if not isinstance(row.get(bound), int) or isinstance(row.get(bound), bool):
                errors.append("int rows need an integer %s" % bound)
        if not errors and row["min"] > row["max"]:
            errors.append("min %d is above max %d" % (row["min"], row["max"]))
        step = row.get("step", 1)
        if not isinstance(step, int) or isinstance(step, bool) or step <= 0:
            errors.append("step must be a positive integer")

    if kind in ("enum", "list"):
        values = row.get("values")
        if not isinstance(values, list) or not values:
            errors.append("%s rows need a non-empty values list" % kind)
        elif not all(isinstance(value, str) for value in values):
            errors.append("%s values must all be strings" % kind)

    # The default has to survive the same coercion a written value does,
    # because it is what --list reports for a key the file has not got yet. A
    # default outside its own min/max would show one number and write another.
    if "default" not in row:
        errors.append("no default")
    elif not errors:
        # Checked against the DECLARED type rather than pushed through
        # coerce(), because coerce is deliberately lenient — it turns the
        # string "banana" into the bool False rather than raising, since it
        # exists to parse a command line. A default is written by hand in a
        # JSON file where `false` is spellable, so it is held to the stricter
        # standard and a wrong-typed one is reported instead of absorbed.
        default = row["default"]
        if kind == "bool" and not isinstance(default, bool):
            errors.append("default must be true or false, got %r" % (default,))
        elif kind == "int":
            if not isinstance(default, int) or isinstance(default, bool):
                errors.append("default must be an integer, got %r" % (default,))
            elif not row["min"] <= default <= row["max"]:
                errors.append(
                    "default %d is outside min/max %d..%d"
                    % (default, row["min"], row["max"]))
        elif kind == "enum" and default not in row["values"]:
            errors.append("default %r is not one of values" % (default,))
        elif kind == "list":
            if not isinstance(default, list):
                errors.append("default must be a list, got %r" % (default,))
            else:
                unknown = [v for v in default if v not in row["values"]]
                if unknown:
                    errors.append("default has unknown items: %s"
                                  % ", ".join(map(repr, unknown)))
                if len(set(default)) != len(default):
                    errors.append("default repeats an item")

    return errors


def load_extra():
    """The user's rows from EXTRA, as (entries, warnings).

    FORMAT — a JSON array of descriptor objects, the same shape as the table
    above:

        [
          { "key": "islandPositionX", "label": "Horizontal position",
            "type": "int", "min": 0, "max": 100, "step": 5,
            "default": 50, "scope": "packaged",
            "detail": "Why I changed this.", "order": 75 }
        ]

    MERGE RULES
    -----------
    * A key that matches a built-in row OVERRIDES it, field by field. Fields
      the entry does not mention keep the built-in value, so `{"key":
      "islandHeight", "max": 80}` widens the range and keeps the label and
      the detail. Overriding `detail` replaces reasoning this repo wrote down
      on purpose — that is allowed, and it is why override rows are marked
      and chipped differently in the panel.
    * A key that matches nothing is a NEW row and must be complete: label,
      type, default and scope at minimum.
    * `order` places a row. Built-ins are implicitly 10, 20, 30 … in the
      order they appear above, so `"order": 75` lands between the seventh and
      eighth. Rows without one keep their natural position. Sorting is
      stable, so equal orders stay in the order given.

    `default` IS NOT A PREFERENCE. It is what the panel DISPLAYS for a key
    that userconfig.json has not got yet, so it has to be the value the
    consumer already falls back to — the backend's own default for a packaged
    key, ForkConfig.qml's for a fork one. Get it wrong and the panel opens
    reading 12 for a key the shell is actually treating as 14, with nothing
    on screen to say which is real, until the first write makes the panel
    retroactively correct. The safe way to add a row is to write the key into
    userconfig.json by hand first, at the value it already behaves as, and
    put that same value here.

    A BAD ENTRY IS SKIPPED, NOT FATAL. Same argument load() makes: the panel
    is the only place some of these keys exist, and taking all thirteen away
    because the fourteenth has a typo turns a small mistake into a broken
    shell. The warnings ride along in --list so the panel can say so.
    """
    if not os.path.exists(EXTRA):
        return [], []

    try:
        with open(EXTRA, encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as error:
        return [], ["cannot read settings-extra.json: %s" % error]
    except ValueError as error:
        return [], ["settings-extra.json is not valid JSON: %s" % error]

    # A bare array is the documented form; {"settings": [...]} is accepted so
    # that a file copied from --list output works.
    if isinstance(data, dict):
        data = data.get("settings", None)
    if not isinstance(data, list):
        return [], ["settings-extra.json must contain a JSON array of rows"]

    entries, warnings = [], []
    for index, entry in enumerate(data):
        if not isinstance(entry, dict):
            warnings.append("row %d is not an object" % index)
            continue
        key = entry.get("key")
        if not isinstance(key, str) or not key:
            warnings.append("row %d has no key" % index)
            continue
        entries.append(entry)

    return entries, warnings


def merged():
    """The full descriptor table as (rows, warnings), built-ins plus EXTRA."""
    rows = []
    for ordinal, entry in enumerate(SETTINGS, start=1):
        row = dict(entry)
        row["order"] = ordinal * 10
        row["source"] = "builtin"
        rows.append(row)

    by_key = {row["key"]: row for row in rows}
    entries, warnings = load_extra()

    for entry in entries:
        key = entry["key"]
        existing = by_key.get(key)

        if existing is not None:
            candidate = dict(existing)
            candidate.update(entry)
            candidate["source"] = "override"
        else:
            candidate = dict(entry)
            candidate.setdefault("order", 10_000 + len(rows))
            candidate["source"] = "user"

        problems = validate(candidate)
        if problems:
            warnings.append("%s: %s" % (key, "; ".join(problems)))
            continue

        # Inert-key check. Only for packaged scope: a fork key's consumer is
        # QML in the fork tree and there is no list of those to check against,
        # so claiming fork scope is taken at face value.
        if candidate["scope"] == "packaged" and key not in BACKEND_PROPERTIES:
            warnings.append(
                "%s: scope is \"packaged\" but UserConfigBackend has no such "
                "property, so writing it will do nothing" % key)

        if existing is not None:
            rows[rows.index(existing)] = candidate
            by_key[key] = candidate
        else:
            rows.append(candidate)
            by_key[key] = candidate

    rows.sort(key=lambda row: row["order"])
    return rows, warnings


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
    if kind == "list":
        # Comma-separated on the command line, because the caller is a QML
        # Process and building a JSON argv from QML is more rope than this
        # needs. An EMPTY string is a legal answer and means the empty list —
        # "show nothing in the swipe row" is a real choice, and `"".split(",")`
        # returning [""] rather than [] is exactly the kind of thing that
        # would have written one bogus item instead.
        text = str(raw).strip()
        items = [part.strip() for part in text.split(",") if part.strip()] if text else []
        unknown = [item for item in items if item not in entry["values"]]
        if unknown:
            raise ValueError("unknown items: %s" % ", ".join(unknown))
        if len(set(items)) != len(items):
            raise ValueError("an item is repeated")
        return items
    return str(raw)


def write(key, raw):
    # Built from merged(), not from the built-in table, or a user-defined row
    # would render in the panel and then reject every write against it.
    rows, _ = merged()
    entry = {row["key"]: row for row in rows}.get(key)
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
    rows, warnings = merged()
    for row in rows:
        row["value"] = data.get(row["key"], row["default"])
    return {
        "path": CONFIG,
        "extraPath": EXTRA,
        "settings": rows,
        # The panel shows these. A row silently vanishing because of a typo
        # three keys up is the failure this is here to prevent.
        "warnings": warnings,
    }


def main(argv):
    if len(argv) >= 2 and argv[1] == "--list":
        json.dump(describe(), sys.stdout)
        sys.stdout.write("\n")
        return 0

    # Writing settings-extra.json is the one part of this with no visual
    # feedback until you next open the panel, so it gets a way to be checked
    # from the shell you are editing it in.
    if len(argv) >= 2 and argv[1] == "--check":
        rows, warnings = merged()
        for warning in warnings:
            sys.stderr.write("warning: %s\n" % warning)
        counts = {}
        for row in rows:
            counts[row["source"]] = counts.get(row["source"], 0) + 1
        sys.stdout.write(
            "%d rows: %d built-in, %d overridden, %d user-defined\n"
            % (len(rows), counts.get("builtin", 0),
               counts.get("override", 0), counts.get("user", 0)))
        return 1 if warnings else 0

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

    # Sliced from "Usage:" rather than by line index, which is what this was
    # and which silently printed the wrong line the moment a mode was added.
    lines = __doc__.strip().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("Usage:"))
    sys.stderr.write("\n".join(lines[start:]) + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
