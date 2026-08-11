# Tide Island — fork notes

Vendored from **`tide-island 1.0.34-1`** (`/usr/share/tide-island`), Arch AUR.
Upstream: <https://github.com/enhaoswen/Tide-island>.

Launched by `../../hypr/scripts/island.sh`, which `autostart.conf` runs in
place of the packaged `tide-island` binary.

## What is in here, and what is not

| | |
|---|---|
| Vendored | `shell.qml`, `DynamicIslandWindow.qml`, the whole `qml/` tree |
| **Not** vendored | `bin/lyricsmpris` — a 356K ELF; the packaged copy is used via `QUICKSHELL_LYRICS_BACKEND` |
| **Not** vendored | `IslandBackend` — a compiled C++/Qt QML module, kept from the package |

The last line is the one that makes this fork cheap, and it was verified
before anything else was written: a QML tree at an arbitrary path still
resolves `import IslandBackend`, because `/usr/lib/qt6/qml` is one of Qt's
default import paths and the package installs the module there. Test used:

```
cp -r /usr/share/tide-island /tmp/vendortest
timeout 8 quickshell -p /tmp/vendortest
# → "Configuration Loaded", no "module IslandBackend is not installed"
```

Had that failed, the fallback was building the AUR tree at
`~/.config/quickshell/tide-island` with patches applied. It did not fail.

## Upgrading tide-island

`pacman -Syu` updates `/usr/share/tide-island` and leaves this tree alone,
so the fork silently goes stale — it keeps working, it just stops gaining
upstream fixes. After an upgrade:

```
diff -ru /usr/share/tide-island/qml  ~/.config/quickshell/tide-island-fork/qml
diff -u  /usr/share/tide-island/DynamicIslandWindow.qml \
         ~/.config/quickshell/tide-island-fork/DynamicIslandWindow.qml
```

Everything that shows up as ours is listed below; re-apply it on top of the
new upstream files.

Also re-check the backend ABI: `IslandBackend` is compiled against a
specific upstream QML API. If an upgrade renames a backend property, the
vendored QML breaks with a `ReferenceError` at runtime and **not** at load
time — Quickshell will still say "Configuration Loaded".

## Patches applied to upstream

Nothing yet beyond the vendoring itself. Each entry below is added by the
commit that makes the change, with the file, the upstream behaviour, and
why the spec wanted something else.

<!-- PATCH LIST -->

### `qml/common/Motion.js` (new file) + `DynamicIslandWindow.qml` — the spring

Upstream animates the capsule on `Easing.OutQuint` (geometry) and
`Easing.InOutQuad` (colour), at a hardcoded `morphDuration: 400`.
DESIGN-SPEC.md wants a generated damped-harmonic spring instead: 400 ms,
damping ratio 0.8, with **fades on a separate critically-damped curve**
because opacity is clamped 0-1 and an overshooting fade gets clipped.

`Motion.js` solves the oscillator analytically and emits it as an
`Easing.BezierSpline`. Nine `Behavior`s in `DynamicIslandWindow.qml` now
call `Motion.spring()` (geometry) or `Motion.fade()` (opacity/colour).

**The trap, which cost a crashed shell:** Qt's `BezierSpline` supports at
most **10 cubic segments**. An eleventh does not warn or fall back — it
writes past the end of a preallocated `QList` in `BezierEase::init()` and
the process takes SIGSEGV on the first animated frame. The first attempt
used 24 and killed Quickshell every launch, with the misleading trailing
message `QEventLoop: Cannot be used without QCoreApplication` (that is the
crash handler, not the cause). Bisected in an offscreen `qml6` harness:
8 and 10 fine, 11 and up SIGSEGV. See the long comment in `Motion.js`.

To keep fidelity inside 10 segments the knots are warped `t^1.8` so they
cluster on the rise and the overshoot peak rather than on the flat tail —
max deviation from the true response 4.0e-4 versus 2.9e-3 for even
spacing.

### `DynamicIslandWindow.qml` — the notch form

Upstream has one resting shape: a pill floating `islandTopMargin` below the
top edge with all four corners rounded. DESIGN-SPEC.md has two forms of the
**same** shape, and the flush one is what makes it read as a notch rather
than as a widget. `notchModeEnabled` defaults true, so the notch is now the
everyday resting appearance.

Driven by a single `notchProgress` 0..1, because the spec is explicit that
this must be "one shape morphing and not two shapes swapping. A single path
interpolated by one value" — the author's first attempt flipped two shapes
with `visible` and it "looked cheap instantly". Interpolated in two phases,
because an outline cannot be round-topped and flared at once:

| phase | range | what moves |
|---|---|---|
| 1 | 0 → 0.5 | top corner radii → 0, capsule slides flush, overshoot grows |
| 2 | 0.5 → 1 | the concave flares grow |

`notchSkirt` is a new `Shape` sibling of `mainCapsule` carrying the
overshoot band and both flares as one `ShapePath`. It is a sibling rather
than a child because `mainCapsule` is a `Rectangle` (cannot be concave)
with `clip: true` and ~40 anchored children — painting the flares inside
would clip them, and resizing it to make room would shift every child.
Quarter arcs are cubics at kappa = 0.5523 rather than `PathArc`, which
removes any chance of a sweep-direction mistake drawing the arc the long
way round.

The top corners use Qt 6.7+ `topLeftRadius` / `topRightRadius`; `radius`
still drives the bottom pair, which the notch keeps.

Scaling, per REQUIREMENTS.md's proportion rule: the flare is 14 px in the
spec's 2560-wide measurements and is scaled by the island's own factor
(96/150) to **9 px**. The 4 px overshoot is deliberately **not** scaled —
it exists to cover the drop shadow's padding, which is an absolute pixel
count, so shrinking it would reintroduce the desktop-coloured hairline it
exists to hide.

### `qml/island/ThemePickerLayer.qml` (new file) — the theme switcher

DESIGN-SPEC.md lists a theme switcher among the island's states; upstream
has a wallpaper picker and no theme picker at all. New layer, plus a
`theme_picker` island state in `DynamicIslandWindow.qml` and a
`tide toggleThemePicker` IPC entry in `shell.qml`.

It owns no theming logic: it lists what `AtiScriptsV1/theme-apply` offers
and runs `theme-apply`. Swatches come from `hypr/scripts/theme-list.sh`,
which parses `theme-apply`'s own `resolve_palette` table rather than
carrying a copy — a second copy would drift silently, and a wrong swatch
still renders.

Needs `import Quickshell` (not just `Quickshell.Io`) for `Quickshell.env`.
Without it the panel opens empty with only a `ReferenceError: Quickshell is
not defined` in the log, which is easy to read as "the script failed".

### `DynamicIslandWindow.qml` + `IslandMprisController.qml` — resting state

Two related fixes, both about the spec's rule that the resting island is
"exactly two things: the time, and a 4-bar EQ visualiser that animates only
while music actually plays".

**The media surface leaked into the rest state.** Upstream guards the
left-hand custom surface on `hasCustomLeftItems` but leaves the right-hand
media surface ungated, so `normalizeRestingState("lyrics")` succeeded with
no player running and the island rested on a card reading the literal
string "No music playing" beside an empty album-art square. Now gated on
`hasMediaSurface` (`activePlayer !== null` — a paused track still counts, no
player does not), in three places: the normaliser, the swipe settle, and a
new `onHasMediaSurfaceChanged` that falls back to the clock when the last
player disappears.

**The EQ was only reachable by swiping.** Upstream draws cava bars inside
the lyrics row, which lives at `clampedProgress` 1. A second, smaller
4-bar instance now sits on the clock's side of the crossfade, gated on a
new `musicPlaying` flag, and the collapsed capsule widens to fit it.

### `DynamicIslandWindow.qml` + `shell.qml` — arbitrary, persistent text

Upstream can already draw text in the capsule — `showTransientCapsule` does,
and every OSD uses it — but it is transient by construction: it restarts
`autoHideTimer`, which restores the resting state a couple of seconds later.
Right for a volume bubble, wrong for a mode indicator. And the IPC that
sounds like this, `tide showCustom()`, takes **no arguments at all**: it
switches to the custom-info surface, whose content comes from the config's
own item list. There was no way to push a string in from outside.

New: `modeIndicatorActive` / `modeIndicatorText` on `islandContainer`, with
`showModeIndicator` / `clearModeIndicator`, exposed as `tide showText`,
`tide showTextWithIcon` and `tide clearText`. It renders through the
existing split/OSD text layout, so no new visual component.

`smartRestoreState` re-asserts the indicator when one is active, so a
transient OSD that interrupts it (volume pressed inside a submap) flashes
and then returns to the mode name rather than dropping to the clock while
the chord is still swallowing keys.

**Trap:** the IPC parameter must be declared with a type —
`function showText(text: string)`. Quickshell marshals IPC arguments by
declared type, and an untyped parameter is simply not passed: the call
succeeds, `text` arrives `undefined`, and the handler clears the indicator
instead of setting it.

First consumer is `hypr/scripts/submap-indicator.sh`, which no longer needs
dunst.

### `qml/common/Metrics.js` (new file) + every layer — one scale factor

The island was resized from DESIGN-SPEC.md's 38 px notch to qtile's 28 px
bar height, on the user's explicit call: qtile's bar was the known-good
daily driver for years and the spec's 38 was measured off a stranger's
2560x1440 screen. See REQUIREMENTS.md item 1.

**Changing `userconfig.json` did that and nothing else, and the result was
worse than leaving it alone.** `islandHeight` and the three font sizes are
the only dimensions `UserConfigBackend` exposes; every other number in this
shell — panel widths, tile sizes, grid spacing, thumbnail sizes, album art,
internal padding, corner radii — is a literal in QML the config cannot
reach. So the theme picker kept its full-size panel and tile boxes and got
9 px labels inside them, which reads as broken rather than as smaller.

`Metrics.js` holds `SCALE = ISLAND_HEIGHT / DESIGN_HEIGHT` (28/38) and three
helpers, and ~380 literals across 21 layer files now go through them:

| helper | for | note |
|---|---|---|
| `px(n)` | structural lengths | rounded, never below 1 — a hairline must not scale itself away |
| `pad(n)` | internal padding | `SCALE * 1.35`, deliberately **not** linear |
| `font(n)` | type sizes | floored at 9 px |

`pad()` is the one that is not a plain ratio, and it is the whole answer to
"the padding should be better, more". Scaling margins by 0.74 alongside the
shape preserves the ratio and therefore preserves the cramped look — the
box gets smaller and the content stays jammed against its edges. Content is
bounded below by glyph height, which stops scaling long before the shape
does, so the space around it has to be given back explicitly.

It is a literal rather than read from `UserConfig`, because a
`.pragma library` JS file has no QML context and cannot see the config
singleton, and initialising it from QML at startup would make every layer's
layout depend on load order — the kind of bug that presents as "the panel is
the right size on the second open". SCALE and `islandHeight` are two halves
of one decision and the derivation is written next to both.

**The trap, found by looking rather than by arithmetic:** the theme picker's
tile delegate insets itself by `tileSpacing / 2` on every side, so a tile's
usable height is `cellHeight - tileSpacing`, not `cellHeight`. The first
scaled pass put the label and the swatch chips in the same 34 px and they
overlapped — the chips sat on the label's descenders. Nothing warns; both
elements render happily on top of each other. In-tile margins use `px` and
not `pad` for the same reason: inside a 46 px tile, generous padding is
taken directly out of the two things that need the room.

### `qml/audio/AudioPanel.qml` (new file) — qtile's AudioPopup

Upstream's control centre has one Sound slider, on the default sink. This
is the other seven-eighths of qtile's popup — output and microphone
selection, per-app volume and routing, card profiles, ports — on qtile's
own `$alt 3`. New `audio_panel` island state, a Loader beside the display
panel's, and a `tide toggleAudioPanel` IPC entry. The pactl side is
`hypr/scripts/audio-ctl.py`; see MIGRATION.md for what it restores.

**The trap, and it is a general one about this shell's `var` models:**
mutating a field of a plain JS object that a `ListView` delegate is
showing changes nothing on screen. There is no notifier — the property
still points at the same array, and the same object. The first version set
`item.vol = target` on a volume keypress and the details column updated
while the list row kept the old number and the bar did not move, which
reads as "the write failed" rather than as "the view did not refresh".
`patchSelected()` copies the row, copies the array, and assigns the
property back. At these list sizes (single digits) copying is free, and it
is the only change QML actually sees.

Two smaller ones, both already paid for:

- The bar and the readout must not read `modelData.vol` unguarded. Ports,
  profiles and cards are rows with no volume at all, and their delegates
  still evaluate those bindings before `visible: false` hides them —
  `undefined / 150` is NaN, and a NaN width warns every frame.
- `islandContainer.audioPanelLayerVisible` is spelled through its id in
  the `focus:` binding where its neighbours are bare names. Quickshell
  hot-reloads on write, so a save landing between a fork property's use
  and its declaration compiles a component that really is missing it, and
  the log fills with `ReferenceError` from a binding that is correct.

## Pre-existing upstream warning, not ours

```
WARN scene: @qml/island/BluetoothConnectionTracker.qml[153:-1]:
  ReferenceError: root is not defined
```

Present when running `/usr/share/tide-island` unmodified. Left alone so the
diff against upstream stays honest.
