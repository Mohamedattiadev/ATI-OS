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

**`springFor()` — the overshoot is a fraction of the TRAVEL, and the eye
reads it against the shape it lands on.** Reported as "the island glitches up
and down after closing the popup", and it is a property of the spring rather
than a bug anywhere in the window. Measured on `mainCapsule.height` closing
the control centre: 323 → 35 is 288 px of travel, 288 × 0.0154 is 4.4 px, and
the capsule dips to **31** — an 11% squash of the 35 px notch — then takes
~200 ms to come back. Invisible on every OPEN, where a panel is bigger than
the trip to it; 11% of the notch on every CLOSE.

The cap is `overshoot()` itself and not a tuned number: *the bounce may never
be a larger fraction of the shape than it would be on a morph that travelled
its own length*. `springFor(travel, dest)` inverts the step response for the
zeta that delivers it — closed form, `zeta = k/sqrt(1+k²)` with
`k = -ln(f)/π` — quantised to 0.02 so `curve()`'s memo holds at most 11
splines. Every open comes out at the untouched 0.8; closes land at 0.82-0.90
and never at 1.0.

**The curve cannot be latched by the `Behavior`, and finding that out took
three tries.** A `ScriptAction` at the head of the Behavior is too late — the
easing is read when the animation JOB is created, before the ScriptAction
runs — and the width Behavior fires first, where `targetHeight` still reads
its OLD value because both are bindings on one `islandState` and reading a
dependent the notifier has not reached yet does not force it. A live
expression is worse: `easing.bezierCurve` re-evaluates every frame, so the
value standing when the next job is created is the one from the END of the
last animation, where the travel is zero. It has to be a plain property set
from the handler that runs *before* the Behavior can fire —
`onBaseTargetWidthChanged` for the width, `onTargetHeightChanged` for the
height.

One cap per DIMENSION, shared duration. The duration is what makes a morph
read as one shape moving; the overshoot is judged against each dimension's
own extent, which is the only thing the eye can compare it to.

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

**`notchSkirtOutline`** is a second, fill-less `Shape` at z 6 tracing the
flares' outer silhouette, so the panel border goes round the arch instead of
stopping short of it. Reported as "at the very top, left and right, there is
an arch, a radius — that ends up not having the border". Measured on an open
control centre: the shape's left edge sweeps 481 → 492 over the top nine
rows while the accent line stayed at 490 for every one of them. The straight
border was correct for the CAPSULE and blind to the SKIRT, which is a
sibling. `panelOutlineFrame` now sits inside a clip whose top margin is
`notchSkirt.f`, so its verticals begin exactly where each fillet lands
tangentially — and that margin is zero when the notch is off, leaving the
four-sided floating form untouched.

It is its own Shape at z 6 rather than a second `ShapePath` inside
`notchSkirt` because the skirt is z 4 and `mainCapsule` is z 5: sharing the
skirt's z puts the last stretch of each fillet under the capsule's fill,
measured as a four-pixel hole in the line (accent present to y=8, absent
y=9..12, resuming at y=13). An outline belongs above the fill.

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

### `qml/island/KeyboardLayoutTracker.qml` (new file) — the language readout

Requested: "the language TR, AR, EN, GE — when i switch in the islen, if not
englsih show; if englsih do not show in the islend."

A readout whose SILENCE is the feature. It takes the outer slot on the left
of the resting capsule, so the order is `code · glyph · clock · digit · EQ`,
and it is there only while the layout is not one of `silentKeys`. Switching
to Arabic therefore shows up in the island as the readout *appearing* rather
than as two letters changing somewhere nobody is looking, and the capsule
widens by `restingLangAllowance` (26 px here) to make room.

Ordering on the left is by volatility: the window-layout glyph changes on
every `$mod Tab`, the keyboard layout changes when you start typing another
language, so the rarer one takes the outer slot and the glyph beside the
clock does not move when the code appears.

The slot is FIXED at `px(22)`, like both of its neighbours, because the
capsule sizes itself from the sum and a width taken from the code's own ink
would morph the capsule on the switch from `AR` to `TR`. Measured rather than
guessed: the four codes are 17.6, 16.9, 17.2 and 17.6 px at `font(13)` in the
face fontconfig resolves for `Inter Medium`, and Qt draws them heavier than
that at DemiBold.

The tracker is a **second copy** of the topbar's layout logic and has to be —
Quickshell's QML scanner refuses a module path outside the config folder, so
the two trees cannot share a component. Event-driven off Hyprland's
`activelayout` with the poll demoted to a 30 s re-sync, and gated on
`HYPRLAND_INSTANCE_SIGNATURE` so it never loads under qtile, where there is
no event socket and `hyprctl` answers nothing.

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

### `qml/wifi/WifiQrLayer.qml` (new file) — the Wi-Fi QR

qtile's `popups/WifiQR.py`, on `$mod P` → `SHIFT+S`. New `wifi_qr` island
state, its own Loader, and a `tide toggleWifiQr` IPC entry. All of the nmcli
and qrencode work is in `hypr/scripts/wifi-qr.py`; this layer only shows what
that produced.

Two things in it are not style choices:

- **The symbol is painted at its natural pixel size.** The script is told how
  much room there is, picks an integer scale that fits, and reports the exact
  pixel count back; the `Image` is set to that. Letting QML stretch it to the
  card resamples the modules at a fractional ratio and softens exactly the
  edges a phone camera needs in poor light.
- **`cache: false` on the Image.** The path never changes
  (`~/.cache/hypr/wifi-qr.png`), so Qt's image cache is free to serve the
  PREVIOUS network's code after a reconnect: right size, right white card,
  wrong network, and nothing on screen to say so.

### `qml/island/ModeKeysLayer.qml` (new file) — the chord heads-up display

Reported as "when I open a mode — rofi, media — the island's UI is not
good". It was a name in a capsule, `ROFI-MODE`, and nothing else.

The name is the half qtile's bar answered and it genuinely matters: without
it the compositor silently starts swallowing keys and there is no way to
tell you are in a submap. But it is not the question you have while
standing in a 26-key chord. qtile got away with it because its chords were
one-shot and its cheatsheet was one keystroke away; Hyprland submaps are
sticky, so you sit in them, and the cheatsheet here is itself behind a
chord.

New `mode_keys` island state, its own Loader, `tide showModeKeys` /
`tide clearModeKeys`, driven by `hypr/scripts/submap-indicator.sh` off the
same event socket it already watched. Rows come from `hyprctl binds` at the
moment the submap is entered, via a new `cheatsheet.py --submap-json` —
which reuses that file's single `describe()` so the panel and the printed
sheet can never label a binding differently.

**This layer takes NO keyboard focus, and that is the whole design.** Every
other panel in this shell (theme picker, display, audio) takes an exclusive
grab because each reads its own keys. This one must do the exact opposite:
the keys belong to the compositor's submap, and a grab here would swallow
the very keys the panel is drawn to advertise — it would appear and the
mode would stop working. So it is deliberately absent from
`WlrLayershell.keyboardFocus`, from `islandContainer`'s `focus:` list, and
from the Overlay-layer list. It is in `blocksTransientSplit` only, so a
volume OSD cannot replace it mid-chord.

**The trap, and it cost the whole first implementation: Quickshell's IPC
splits arguments on whitespace, and shell quoting does not survive it.**
A ONE-parameter call gets the remainder joined back together, which is why
`tide showText "hello world"` works and hides the problem completely. A
TWO-parameter call does not: sending the rows as a JSON blob whose actions
read "wifi panel" and "theme picker" arrived as **27 arguments instead of
2** and was rejected with `Too many arguments provided`. Percent-encoding
got past the argument count and still produced an empty grid.

The fix is not a better encoding — it is not sending the data. The IPC
carries only the mode name, which is one word and cannot have the problem,
and the panel runs the backend itself. That is also what every other panel
here already does (`ThemePickerLayer` runs `theme-list.sh`, `DisplayPanel`
runs `display-ctl.py`), so it is one less thing that is special.

Two smaller notes:

- **Column count follows row count** — three columns above 12 rows, two
  above 5, one below. `rofi` has 26 rows and `lang` has 4, and four rows in
  three columns is one row of three plus a widow.
- **The nine workspace binds every chord repeats are collapsed to one
  `1-9` row.** They are true, and they were also nine of the twenty rows,
  crowding out the keys that are specific to the mode.

### Navigation: Tab means "next section", and the cursors wrap

Four files, one complaint — "the vim motions don't work well and there
should be a Tab to go to the next thing".

**`DisplayPanel.qml`** had `Tab` bound to `move(1)`, i.e. a second `j`. It
was the only key on the panel that did nothing another key already did,
while the four views were reachable only through four unrelated letters.
Tab now cycles the sections, which is what it already meant in
`AudioPanel.qml` — the two panels were inconsistent with each other, and
the audio one was right. Shift+Tab goes back. In arrange view Tab keeps
cycling which output is being dragged, since that is the only thing to step
through there.

Entering `modes` by Tab has to set `modeOutput`, which until now was only
ever set by pressing Return on an output row. Without that the list is
empty and the details column says "no output selected" — which reads as the
panel having lost the monitor rather than as the view needing a subject.

**`move()` wraps in both panels.** vim clamps, and clamping is right in a
buffer; these lists are two to five rows long, and `j` stopping dead at the
second row of a two-output list reads as a dead key. `g`/`G` still go to
the ends.

**`ThemePickerLayer.qml`** answered only to arrow keys — the one panel in
this shell that did not read hjkl. It is a grid, so `h`/`l` step one tile
and `j`/`k` step one row (`columns` tiles), which is what the arrows
already did. Verified live: from `gruvbox` (index 3), `l l j` landed on
`kanagawa` (index 9), i.e. +1 +1 +4.

**`WallpaperPickerLayer.qml`** gained `r` for a random wallpaper. With 362
images in the library, `h`/`l` one thumbnail at a time is not a way to
reach most of them. It moves the cursor and then applies, rather than
applying blind, so the picker still shows you what you got; it re-rolls if
the draw lands on the current index.

## The motion pass — new file `qml/common/PanelLoader.qml`, 24 files touched

The largest single patch in the fork and the one most likely to conflict on
the next `pacman -Syu`, because it touches nearly every layer file.

**New file.** `qml/common/PanelLoader.qml` — a Loader whose `active` lags
its `live` by the fade-out duration. Upstream's `Loader { active: <the same
boolean that drives showCondition> }` destroys the layer in the same
event-loop turn that queues its fade-out, so **the out-fade in all thirteen
panel layers had never executed**. Thirteen call sites in
`DynamicIslandWindow.qml` changed from `Loader { active: X }` to
`PanelLoader { live: X }`.

**`Motion.js`** gained `fadeInDuration` / `fadeOutDuration` / `contentDelay`
(one choreography replacing eight in-durations and six out-durations across
20 layers) and `overshoot()` (published so containers can budget for the
spring going past its target).

**49 raw `easing.type: Easing.*` converted** to `Easing.BezierSpline` +
`Motion.spring()` or `Motion.fade()`, classified by whether the property is
a position or a clamped 0–1 quantity. 17 remain deliberately, listed at the
bottom of `Motion.js`.

**Three panels became content-sized** (`display_panel`, `audio_panel`,
`theme_picker` in the `targetHeight` switch), each reading a
`preferredHeight` off its layer. The theme picker's fixed height had been
hiding six of 22 themes below the fold.

`r` in the wallpaper picker no longer applies — see the section above,
which is now out of date on that one point and correct on the rest.

Two traps found the hard way and worth carrying forward:

- Rewriting these blocks mechanically, watch for the **one-line**
  `NumberAnimation { duration: 180; easing.type: ... }` form. A
  line-oriented substitution deletes the whole animation and QML then
  refuses `Behavior` with `Cannot assign to non-existent property "easing"`.
- **Quickshell does not reload on `.js` changes**, only `.qml`. A new
  function in `Motion.js` used from QML in the same breath throws
  `TypeError: ... is not a function` and keeps throwing until some `.qml`
  file is touched.

## Pre-existing upstream warning, not ours

```
WARN scene: @qml/island/BluetoothConnectionTracker.qml[153:-1]:
  ReferenceError: root is not defined
```

Present when running `/usr/share/tide-island` unmodified. Left alone so the
diff against upstream stays honest.
