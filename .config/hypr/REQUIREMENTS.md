# Requested scope — the full list, so nothing gets lost

Standing constraint, applies to everything below:
**do not touch the qtile config.** Both sessions run in parallel.

---

## Where the 2026-08-14 list landed

A separate nine-item list was given directly by the user and is recorded
here so it is not lost between documents. The measured detail for each is
in the audit at the end of `upgread_UI_UX.md`.

| Item | Status |
| ---- | ------ |
| Per-theme wallpaper sets, random pick | **DONE.** 20 themes x 10 real photographs, scored; mono-light generated (no light wallpaper exists to find). Pushed to the user's wallpaper repo. |
| Theme + wallpaper as one animation | **DONE.** Seam 1685 ms -> 79 ms. Freeze grew ~170 ms; the trade is stated in the commit. |
| `$mod SHIFT O` / `$alt SHIFT A` on S | **DONE.** Two independent bugs, both from treating a negative workspace id as invalid. |
| Night light | **DONE.** hyprsunset installed and declared; the gammastep path deleted because it cannot work here. Needs the user's eyes to confirm the tint. |
| Onboarding flow | **DONE.** `qml/onboarding/OnboardingLayer.qml`, `$mod SHIFT I`. |
| `$mod SHIFT /` docs overlay | **DONE.** Two sheets added to the existing cheatsheet; `$mod SHIFT K` kept as an alias. |
| Documentation pass | **DONE.** `hypr/README.md` created, arch-config README corrected, audit appended. |
| The older still-open list | **NOT STARTED.** Unchanged; see the audit's closing section. |

## 0. Install Hyprland

**Status: DONE.** Hyprland 0.56.2 installed and running; keyd is active,
enabled, and confirmed bound to `AT Translated Set 2 keyboard`. See the
"Runtime verification" section of MIGRATION.md for what first login
proved.

**The one missing package is now installed.** `pacman -Q inter-font`
reports 4.1-1, and the two families that mattered resolve to the real
font rather than to a substitute: `fc-match "Inter Display"` →
`Inter.ttc: "Inter Display" "Regular"`, `fc-match "Inter Medium"` →
`Inter.ttc: "Inter" "Medium"`. That closes the silent-substitution
hazard for every `Inter` / `Inter Display` family in `hyprlock.conf` and
for every one DESIGN-SPEC.md specifies for the notch — until it was
installed they all resolved to Noto Sans CJK KR with no warning
anywhere.

**One package is still missing, and it is a different one:** `wf-recorder`.
See item 3 — the ported screen and region recording rows are present,
labelled, and refuse to run.

```
sudo pacman -S inter-font   # done
sudo pacman -S wf-recorder  # NOT done — see item 3
```

Original install command, for reference:

```
sudo pacman -S hyprland xdg-desktop-portal-hyprland \
    hyprpaper hypridle hyprlock \
    grim slurp wl-clipboard jq \
    brightnessctl playerctl \
    polkit-kde-agent qt5-wayland qt6-wayland \
    keyd
```

`keyd` is in that list deliberately — see the Caps→Alt blocker in
`MIGRATION.md`. Configure it before first boot or ~40 bindings are dead.

---

## The two videos — RESOLVED

I still cannot see video frames. But you were right that the transcripts
were reachable: both were pulled with `yt-dlp` and de-duplicated (the
rolling auto-caption overlap needs word-level trimming, not cue-level).

**4,640 words for the glass video, 5,436 for the notch video, read in full.**
Both creators narrate their design decisions with specific numbers, so the
transcripts turned out to be a better spec than screenshots would have been.

Everything extracted is in **`DESIGN-SPEC.md`** — geometry, timings, damping
ratios, font choices, and the bugs each author hit.

| | Video | Identified as |
|---|---|---|
| 1 | `nKomstQedmE` | "I Replaced My Whole Hyprland Bar With One Notch" |
| 2 | `2ZNGlPW6DM8` | "How to Get Liquid Glass on Hyprland" |

### The finding that changes the plan

**The notch shell in video 1 is not Tide-island, and has no public repo.**

> "This shell is about 7 and 1/2 thousand lines, I think, across 59 files,
> and I wrote every one of them by hand"

It is unreleased, taught only through the author's paid course. That is
exactly why you couldn't find the config. Your instinct — take Tide-island
and restyle it — is therefore the only available route, and it is a sound
one: Tide-island is also Quickshell/QML, so the concepts port even though
the code does not.

What remains genuinely unknown without frames: exact colours inside the
expanded panels, icon set, and the precise flare curve. Everything
structural is now specified.

---

## 1. Notch bar + port my popups into it

**Status: THE NOTCH IS DONE. The remaining popups are still to do.**

The resting shape is now the notch itself — flush to the top edge, top
corners square, concave flares, pure black — not a pill floating below it.
That was the last thing that made it read as a widget rather than as
bezel. Motion, arbitrary text and a theme picker all landed with it; the
audio/display/wifi/bluetooth/cheatsheet popups have not.

Tide Island is installed (AUR, `tide-island 1.0.34`) and starts from
`autostart.conf`. Hyprland is no longer bar-less.

**The invocation in the plan was wrong.** `qs -c tide-island` against a
clone in `~/.config/quickshell` cannot work: `shell.qml` imports
`IslandBackend`, a compiled C++/Qt QML module. It is a package that
installs to `/usr` and launches via `quickshell -p /usr/share/tide-island`.

An earlier revision of this file concluded from that "only the config is
ours". **That was too pessimistic, and it is now corrected** — see
"The fork" below. The compiled module is not the obstacle it looked like.

The config is ours regardless, at `~/.config/tide-island/userconfig.json`,
stowed from this repo. Its `UserConfigBackend` exposes 45
settings, and its own defaults already sit close to the spec (140x38,
`Inter Display`). Restyling to DESIGN-SPEC.md needed **no forking at
all** for the resting state:

| Spec | Setting | Verified |
|---|---|---|
| 150x38 collapsed pill | `islandWidth` 150, `islandHeight` 38 | renders |
| 11 px below top edge | `islandTopMargin` 11 | renders |
| hardcoded black, not tinted | `islandBackgroundOpacity` 100 (upstream 60) | solid black |
| clock only at rest | `islandAutoHideEnabled` false, `islandShowWorkspaceOnAutoHide` false | workspaces gone |
| media swaps content, never expands | `disableAutoExpandOnTrackChange` true | — |
| Inter / Inter Display | the four `*FontFamily` keys | resolves, not substituted |
| — | `islandExclusiveZone` 49 | reserved `[0,49,0,0]`, windows tile at y=59 |

### Sizing: qtile's numbers now win over the spec's — the user's call

**`islandHeight` is 28, not the spec's 38.** The user asked for the bar to
be "the same like qtile since was good", and qtile's was
`bar.Bar(..., 28)` with `widget_defaults` `fontsize` 10 — the known-good
daily driver for years, against a 38 measured off a stranger's 2560x1440
screen. This is a deliberate override of DESIGN-SPEC.md and it is recorded
here so nobody "fixes" it back.

The font sizes follow: the resting clock renders at `bodyFontSize + 1`, so
`bodyFontSize` 12 puts it at 13 px, which is what qtile's `fontsize` 10
comes to at 96 dpi. `islandExclusiveZone` is 38, which is also exactly what
qtile reserved (28 px bar plus its `margin` of 5 top and 5 bottom).

**Changing those four config keys reached only the fonts, and that made
things worse before it made them better.** Every other dimension in the
shell is a QML literal that `UserConfigBackend` does not expose, so the
panels kept their full-size boxes and got tiny text floating in them.
The fix is `tide-island-fork/qml/common/Metrics.js`: one `SCALE`, applied
to ~380 literals across 21 layer files, with a separate `pad()` that is
deliberately super-linear because padding scaled linearly stays cramped.
Written up in FORK-NOTES.md.

**Sizing was wrong at first, and the reason is worth keeping.** The spec's
150 px was measured off a 2560x1440 display, where it is 5.9% of screen
width. Applied literally to this 1366 px panel it becomes 11% —
proportionally almost double, and it read as oversized. `islandWidth` now
follows the spec's *proportion* rather than its pixel count: 5.9% of 1366
is 80, rounded to 96 so the 24-hour clock keeps side padding. Any spec
number taken off that video needs the same treatment.

**Several popups turned out to already exist**, unbound — found with
`qs -p /usr/share/tide-island ipc show`, which lists the island's IPC:

| IPC call | Replaces |
|---|---|
| `tide toggleWallpaperPicker` | WallpaperPopup (9 bindings) |
| `tide toggleControlCenter` | much of AudioPopup + connectivity |
| `tide toggleNotificationCenter` | — |
| `overview toggle` | the group overview the qtile bar gave at a glance |

These are now bound in `binds.conf`. The wallpaper picker also needs
`wallpaperLibraryPath` set or it opens empty saying "No wallpapers
found"; it points at `~/Pictures/Wallpapers` (362 images).

**What config could not reach — ALL FOUR NOW DONE in the fork:**

- **The notch morph — DONE.** Flush to the top, top corners square, a 9 px
  concave flare each side (14 scaled by the island's 96/150 factor), 4 px
  overshoot clipped. One path interpolated by one value in two phases
  (un-round, then flare), per the spec's rule against swapping shapes.
  This is now the DEFAULT resting form: the floating pill is what it
  morphs back to, not the norm. `notchProgress` / `notchSkirt` in
  `DynamicIslandWindow.qml`.
- **The 400 ms / 0.8-damping spring — DONE.** `qml/common/Motion.js`
  solves the damped harmonic oscillator and emits it as an
  `Easing.BezierSpline`; nine Behaviors use it, geometry on the spring and
  opacity/colour on a critically damped curve. Measured live at the top
  row of the capsule during an expansion: reaches 94% of travel ~127 ms
  in, peaks 5 px past the settled width, and settles — a +1.6% overshoot
  against the 1.54% the maths predicts. **Qt's BezierSpline accepts at
  most 10 segments and segfaults on the eleventh**; the first attempt used
  24 and crashed the shell on every launch. See FORK-NOTES.md.
- **Arbitrary text in the island — DONE.** `tide showText <string>` /
  `tide clearText`, persistent until cleared and re-asserted after any
  transient OSD interrupts it. `submap-indicator.sh` uses it and no longer
  needs dunst.
- **A theme picker — DONE.** `ThemePickerLayer.qml`, bound as SHIFT+C in
  the rofi submap. 22 tiles each painted in the palette it applies, with
  swatches parsed out of `theme-apply` itself rather than copied.

**A theme picker is not among the island's panels** — it is now, as fork
work. `$mod P` → `c` is still the rofi `theme-toggle`, unchanged; `$mod P`
→ `SHIFT+c` opens the island's. Both drive `theme-apply` and both read
`~/.cache/qtile/theme_mode`, so they cannot disagree, and rofi keeps
working when the island is not running.

### The fork — DONE, and cheaper than the earlier note assumed

The compiled `IslandBackend` module blocks *rebuilding* Tide Island. It
does not block *replacing its QML*, and the QML is where all four
unreachable things live.

**Verified before anything was written**, because it decides the whole
approach: copy `/usr/share/tide-island` to an arbitrary path, run
`quickshell -p <that path>`, and it prints "Configuration Loaded" with no
`module IslandBackend is not installed`. `/usr/lib/qt6/qml` is one of
Qt's default import paths and the package installs the module there, so
a vendored tree at any location still imports it.

So the fork is **QML-only**:

| | |
|---|---|
| Vendored into this repo | `.config/quickshell/tide-island-fork/` — `shell.qml`, `DynamicIslandWindow.qml`, the `qml/` tree (44 files) |
| Kept from the package | `IslandBackend` (compiled), `bin/lyricsmpris` (356K ELF — a binary blob does not belong in a dotfiles repo) |
| Launched by | `hypr/scripts/island.sh` from `autostart.conf`, replacing the `tide-island` binary |

`island.sh` exports the two env vars the packaged launcher set and we
would otherwise lose (`QUICKSHELL_LYRICS_BACKEND`, the jemalloc
`MALLOC_CONF` tuning), and falls back to `exec tide-island` if the fork
is missing, so a machine where stow has not run yet still gets a bar.

**`$qsi` in `binds.conf` had to move to the fork path in the same
commit.** Quickshell keys its IPC socket by config path, so
`qs -p /usr/share/tide-island ipc call ...` against a fork instance
matches nothing and fails silently from a keybind.

The standing cost is that `pacman -Syu` updates `/usr/share/tide-island`
and leaves the fork stale. `tide-island-fork/FORK-NOTES.md` records the
vendored version (1.0.34-1), the diff commands, and every patch applied,
so the merge is mechanical.

**The popups this section once called "the long pole" are ALL DONE**, each
as a layer in the fork with a script behind it. This paragraph said
"untouched" for far longer than it was true; the list is the status:

| popup | key | where it lives |
|---|---|---|
| Display | `$alt 4` | `qml/display/DisplayPanel.qml` + `hypr/scripts/display-ctl.py` |
| Audio detail (25 bindings, the largest) | `$alt 3` | `qml/audio/AudioPanel.qml` + `hypr/scripts/audio-ctl.py` |
| Wi-Fi / Bluetooth lists | `$mod P` → `n` / `b` | **rebuilt from scratch as two separate vim-navigable panels** — `qml/connectivity/WifiPanel.qml` and `BluetoothPanel.qml`. Was the control centre with a wing unfolded off its side; see below |
| System monitor | `$mod ` `` ` `` | `qml/sysmon/` — **new, no qtile popup ancestor and not in the spec's list** — see below |
| Wi-Fi QR | `$mod P` → `SHIFT+S` | `qml/wifi/WifiQrLayer.qml` + `hypr/scripts/wifi-qr.py` |
| Cheatsheets | `$mod SHIFT K` | `qml/cheatsheet/CheatsheetLayer.qml` + `hypr/scripts/cheatsheet.py --sheet-json`. **Was rofi "on purpose" — see below** |
| Wallpaper picker | `$mod SHIFT B` | upstream's, bound |

MIGRATION.md has the per-item evidence for each.

#### The connectivity panels stopped being wings of the control centre

`$mod P` → `n` and `b` used to open the control centre with a side panel
unfolded off it. That was never what the qtile chord reached — qtile's
WifiPopup and BluetoothPopup were standalone popups — and it made the two
most-used lists in the chord the only surfaces that arrived attached to
something else. They are now two independent popups in their own right
(`ca8be05`, `5c3e9ea`), the same shape the wallpaper and theme pickers
open in, each taking the keyboard itself and doing its own navigation.

The control centre is still mounted underneath, and that is deliberate
rather than left over: it is the panels' **data provider** — the Wi-Fi
controller, the Bluetooth adapter, the pairing agent and every action
method the rows call live in `ControlCenterLayer.qml`. The binding that
keeps it alive is `wifiPanelLoader.visible || bluetoothPanelLoader.visible`
and NOT `.active`, which is a near-miss worth keeping: `retain` makes a
loader `active` forever, so the obvious spelling would have pinned the
entire control centre mounted for the life of the shell, invisibly, at
opacity zero (`0c124cf`).

Bluetooth also collapsed from several lists into **one rank-sorted list**
(`786272c`), which as a side effect fixed a device that could render twice
— once under "paired" and once under "nearby".

**One thing on the old outstanding list is now closed:**
`toggleBluetoothScan` was recorded as having no caller, meaning the panel
could display a scan it could never start. It has one:
`BluetoothPanel.qml:476`, inside `toggleScan()`, which is bound to a key at
`:544` and sets a "scanning…" / "scan stopped" status either side of it.

#### The system monitor — a key that had been pointing at nothing

qtile's `$mod` + `` ` `` was "toggle 2nd system widget box", labelled
`Updates · Disk · Volume`, with `mod2` + `` ` `` as `CPU + Memory`. Nothing
in the island answered that, so the key had been aimed at the control
centre as the nearest surface whose job is status rather than a task, and
`binds.conf` said plainly what was wrong with the substitution: no Disk and
no Updates.

`qml/sysmon/` is the content (`8a2c3c1`) and `84a32b7` is the wiring —
eleven registration sites in `DynamicIslandWindow.qml`, an IPC toggle, and
the binding. Against qtile's own label table it covers `system_widgetbox`
entirely and two thirds of the other. Volume stays in the control centre
because it is a control and not a readout; **Updates never ported at all**,
qtile's Updates-Mode being commented out in its own `config.py`, and that
remains the one label-table entry with no home anywhere.

Three dials on the shared `ProgressRing` rather than a fourth hand-rolled
Canvas, disk as a row per filesystem rather than ukishima's single figure
for `/` (on this machine `/` is 31.2 GB at 81% and `/home` is 201 GB at
91%, so one number answers the least interesting third of the question),
and both timers gated on `showCondition`. Numbers checked against `df -P`
and `free -m` in the same second and agreeing to the byte on disk.

**The wrong theory it cost, kept because it is the more useful half.** The
panel appeared to open and close itself after two to three seconds, and
increasingly elaborate probes were built for a self-closing panel. Two of
the probes were themselves wrong — `pgrep -f` matched its own pattern, and
a mean-brightness comparison over a screenshot region was measuring the
terminal behind the island rather than the panel. The panel was fine the
whole time: another agent was driving every popup transition on this same
shell, and `smartRestoreState` was faithfully restoring whatever it had
left open. The lesson generalises the one already in this repo — a
screenshot is evidence about the running process, and *a derived statistic
over a screenshot is evidence about whatever is in the crop*. Look at the
picture first.

### The cheatsheets came off rofi, and item 3's rule with them

Item 3 below says: rebuild the *interactive* popups in the shell, leave
the *launcher* problems on rofi. A cheatsheet is read-and-dismiss, so by
that rule it stayed on rofi, and `cheatsheet.py` argued the case in its own
header. The rule lost to a simpler observation — every other surface here
lives in the notch, and a rofi window over the desktop for the one chord
that explains the desktop was the odd one out.

The port is not a text dump, because **what rofi actually contributed was
the typing, not the window**. qtile spent four of CheatSheet-Mode's sixteen
bindings (`j`, `k`, `Tab`, `Shift+Tab`) moving a viewport around 129 rows;
rofi replaced all four with a search field. `CheatsheetLayer.qml` is built
around that field, and adds the one thing neither predecessor had: `k`/`v`/
`f` choose the sheet it OPENS on, and **Tab cycles all three while it is
open**, so comparing a vim binding against a WM binding no longer means
leaving the chord and re-entering it.

`cheatsheet.py hypr` still prints the rofi sheet from a terminal, off the
same two builders — one copy of the content, and one way to read these keys
that does not need the shell to be running.

**What the island still does NOT have, measured against DESIGN-SPEC.md's
own list** ("states of the one shape"):

| spec state | here |
|---|---|
| launcher | **exists, and was unbound** — `tide toggleApplicationLauncher`, now on `$mod D`. Same miss as the Wi-Fi and Bluetooth lists, found the same way with `ipc show` |
| control center | bound, `$mod SHIFT A` |
| wallpaper picker | bound, `$mod P` → `w` |
| theme switcher | bound, `$mod P` → `c` |
| calendar | **DONE**, `$alt 6` — `qml/island/CalendarLayer.qml`. No qtile ancestor at all: qtile had `widget.Clock` and no calendar popup, so this was built from the spec rather than ported |
| power menu | **DONE**, `$mod SHIFT Q` and `$mod P` → `q` — `qml/island/PowerMenuLayer.qml` over `scripts/power-ctl.sh`. Both keys were `dm-logout -r` (rofi), which is what qtile spawned |
| settings | **DONE**, `$alt 7` — `qml/island/SettingsLayer.qml`. Not in the spec's list; added because the packaged config app is a compiled binary that a `yay -Syu` would overwrite, and it cannot reach fork-only keys at all. Now **user-extensible**, see below |
| **Polkit password prompt** | **REMOVED, and that is the closed state — not a deferral.** See below. polkit-kde-agent has this job and does it correctly |

The polkit prompt was the only remainder of item 1's feature list. It is
now removed rather than outstanding, and the section below is kept in full
because the reasoning that got it there is worth more than the conclusion.

##### It was not merely missing — it was a reachable crash

**This was found by driving the IPC rather than by reading the code, and it
is the third instance of this document's recurring failure shape: something
that looks wired up and is not.** The row above used to say the layer "does
not exist", which read as a gap. A gap is inert. This was not inert.

What existed:

* `tide showPolkitPrompt` and `tide clearPolkitPrompt` were **registered on
  the live IPC**, alongside every working call.
* `shell.qml` routed both to `showPolkitPromptWindow()` /
  `clearPolkitPromptWindow()` in `DynamicIslandWindow.qml`, which set
  `islandState = "polkit_prompt"`.
* The state had a width case (`Metrics.px(430)`, with a paragraph arguing
  why a password field should be narrow), a radius case, a
  `polkitPromptLayerVisible` property, and an entry in the
  exclusive-keyboard-focus list.

What did not exist:

* `qml/island/PolkitPromptLayer.qml` — the file the comment at
  `DynamicIslandWindow.qml:2428` explicitly pointed the reader at.
* `polkitPromptLoader` — **referenced twice and declared nowhere.**

So the height case dereferenced an identifier that did not resolve, the
call threw `ReferenceError: polkitPromptLoader is not defined`, and the
island promoted itself to Overlay (level 2 → 3), grew nothing and drew
nothing — an invisible surface over fullscreen windows.

##### Why it was removed and not built

The document spent a long time weighing "build it" against "strip it", and
framed the question as a cost question: stripping is about fifteen lines,
building is real work plus the agent hazard. **That framing was wrong, and
it is worth recording as wrong**, because it treats the two options as
different amounts of the same journey. They are not on the same road at
all.

The deciding fact is one this document never stated: **the prompt was never
connected to polkit.** A polkit agent is a D-Bus service — it registers with
`org.freedesktop.PolicyKit1.Authority` and implements the
`AuthenticationAgent` interface. Nothing in the fork does either:

```
grep -rn 'AuthenticationAgent\|PolicyKit1\|RegisterAuthenticationAgent' \
     .config/quickshell/tide-island-fork/
```

returns nothing. So `PolkitPromptLayer.qml`, however well built, would have
been a password field wired to no transaction — a box you can type a
password into with nothing on the other end to answer. "Build it" was never
fifteen lines short of working; it was a D-Bus agent short of working, and
Quickshell has no binding for one.

And the job is already done. `/usr/lib/polkit-kde-authentication-agent-1`
was running when this was checked (pid 2009), started from
`hypr/autostart.conf:23`. **Checked before deciding, not after** — had
nothing been handling polkit, `sudo`-requiring GUI actions would have been
failing silently and building would have been the fix. Something was, so
building a second agent would mean unregistering a working one, whose
failure mode this document already describes: no password prompt anywhere
on the system, silently, until you need one.

##### What was removed

The IPC pair in `shell.qml`; `showPolkitPromptWindow` / 
`clearPolkitPromptWindow` and `islandContainer.showPolkitPrompt()` in
`DynamicIslandWindow.qml`; the width, height, radius, keyboard-focus and
`openPanelState` cases; the `polkitPromptLayerVisible` property; the
dangling `polkitPromptLoader` reference; `ForkConfig.polkitAgentEnabled`
and its `forkPolkitAgentEnabled` parse; the settings row in
`island-settings.py` and the two colour special-cases in `SettingsLayer.qml`
that keyed on it. Every removal site carries a comment saying what stood
there and why it is gone.

Verified after restarting the shell: `ipc show` contains **zero** polkit
entries, `ipc call tide showPolkitPrompt` answers `Function not found.`
rather than throwing, and the island stays at level 2, 1366x58. The
settings panel went from 13 rows to 12 with no warnings.

**A warning that described an imaginary hazard.** The settings row
previously read "DANGER. Registers this shell as the session polkit
agent", which was not true of the code at any point — the switch was inert.
A later wording was honest about being inert but still put a switch on
screen for a feature nobody was going to finish. The row was never the
problem; the half-built state behind it was, and that state was reachable
over IPC without touching the panel at all.

#### The ring OSD, off the notch

`forkRingOsdEnabled`. The island already *had* a ring — `OsdLayer.qml` draws
one with the shared `ProgressRing` — so this was never "build a ring", it was
"stop it being part of the notch". A strip at the top edge that grows sideways
reads as *the bar changed*; the thing being adjusted is the whole machine.

Now its own layer-shell surface, lower third, Overlay layer (a volume OSD you
cannot see in fullscreen is one that fails exactly when it is most used).

**Two things that would have broken the desktop:**

- **The input mask.** A fullscreen transparent surface with the default mask
  eats every click on the desktop for as long as it is mapped. `mask: Region {}`
  — an empty region — makes it fully click-through. Verified: with the pointer
  over the ring, `hyprctl activewindow` still reported the terminal, and the
  layer unmaps entirely once hidden.
- **`restart()`, not `start()`.** Holding a volume key fires the OSD many times
  a second, and a `Timer` already running ignores `start()` — the ring would
  vanish 1.4 s after the *first* keypress while the level was still moving.

Routing is on `progress >= 0`, which is not a proxy for "is this volume". That
one function is also how the mode indicator and every `showText` IPC reaches
the island, and those pass `-1`. Routing on whether there is **a value to
plot** is exactly the question a ring answers; the ones without a value have
nothing to draw in it.

#### The control centre, restyled from ukishima

The Display/Sound sliders were a 30 px pill with an `#eceef2` fill and a **24 px
`#f4f5f7` knob** — the brightest and largest element in a shell whose identity
is near-black imitating bezel. Replaced with ukishima's filament fader
(`components/VFader.qml`): a 2 px matte thread, a gradient fill, a small flat
tick and no knob, with the percentage readout appearing **only while touched**
— at rest the fill length *is* the value.

Two departures: **horizontal**, because theirs is four columns in a wide panel
and ours is two rows in a 385 px one (the idiom is the thread, not the axis);
and **our accent**, because their `Theme.qml` hardcodes `#c0442b` for a
single-identity shell and a fixed vermillion would be the one element ignoring
theme-apply.

The Wi-Fi/Bluetooth toggles were `StyleTokens.success`, a fixed iOS green — the
only thing in the panel ignoring the palette. Now the accent. The battery bar
keeps success/warning/danger, where the colour *is* the information.

Since then the header and the connectivity rows were restyled the same way
ukishima sets them — a hero number and two rows (`71b4c65`) — and the
panel's own morph was put on `Motion.SCALE` so it stops being the one
surface that opens on a different curve from everything else (`cfb46b5`).

##### A sixth dead control, and this one is in the control centre itself

**Found by reading the running shell's log rather than the code**, which is
how it stayed hidden: it produces a warning on a timer and nothing on
screen. The control centre's Focus / Do-Not-Disturb row shells out to
`swaync-client`:

| what | where |
|---|---|
| read the current state | `ControlCenterLayer.qml:1008` — `["swaync-client", "--get-dnd"]` |
| turn it on | `:1098` — `["swaync-client", "-dn"]` |
| turn it off | `:1112` — `["swaync-client", "-df"]` |

**`swaync-client` is not installed on this machine and never has been.**
`dunst` is the notification daemon and is the process holding
`org.freedesktop.Notifications` — PID confirmed in the process table. The
log shows the consequence repeating for as long as the panel is open:

```
WARN: Process failed to start, likely because the binary could not be
      found. Command: QList("swaync-client", "--get-dnd")
```

The read fails, so `focusEnabled` never updates from reality. The write
fails, and because `focusEnableProcess.onExited` sets
`focusEnabled = exitCode === 0`, a failure-to-start flips the row to
**off** — so the control does not even fail visibly stuck, it fails by
silently agreeing with itself. Notifications keep arriving either way.

This is exactly the class of bug this document already records twice — the
imaginary polkit warning, and the four inert `fork*` settings rows — and
it was missed both times because those audits swept the *fork's* files.
This one is upstream code the fork vendored and never checked. **The audit
question that would have caught it, and should be the standing one: for
every external binary this shell shells out to, is it installed?**

The fix, when it is time, is `dunstctl`: `dunstctl is-paused` reads it,
`dunstctl set-paused true|false` writes it. Recorded, not fixed.

#### Qt theming — verified, it works

`env = QT_QPA_PLATFORMTHEME,qt6ct` **does** reach spawned processes (dumped the
environment of a Hyprland-spawned process), and `pcmanfm-qt` renders dark with
the gruvbox palette — cream `#ebdbb2` on `#282828`. The open question from the
earlier handoff is closed.

#### ForkConfig was never instantiated — four more dead switches

**The single worst thing found so far, and it invalidated the settings panel
that was built on top of it.** `qml/common/ForkConfig.qml` was written,
documented at length, and **never instantiated anywhere in the tree**. The
only occurrences of the name were two comments in `SettingsLayer.qml`
describing what it would do. So every `fork*` key in `userconfig.json` was
inert and four of the panel's twelve rows changed nothing:

| row | what it actually did |
|---|---|
| Notch mode | nothing — `DynamicIslandWindow` kept `property bool notchModeEnabled: true`, the hardcoded literal ForkConfig existed to replace. Its comment claimed it was "toggled live over IPC (`island setNotchMode`)"; **no such IPC exists** |
| Chord key HUD | nothing — name appears nowhere outside ForkConfig.qml |
| Resting EQ bars | nothing — as above |
| Theme reveal animation | nothing — as above |

With the polkit row that was **five of twelve** controls doing nothing, in
a panel whose whole justification is reaching keys the packaged app cannot.
The polkit row has since been deleted outright with the feature behind it,
taking the count to four of twelve — deleted rather than fixed, because
there was no behaviour for it to describe.
This is the same failure this document already records once ("a warning that
described an imaginary hazard") — it was simply never checked whether the
rows *around* that one were any better.

Now wired: instantiated once in `shell.qml` (not per screen — it is a file
watcher, and one `Variants` delegate per monitor would open one FileView per
monitor on the same path), exposed as `shellRoot.forkSettings`, and consumed
at four points. `restingEqEnabled` is folded into `islandContainer.musicPlaying`
rather than into the bars, because that one property gates **both** the bars
and the 21 px `restingEqAllowance` the collapsed capsule grows by — gating
only the bars would leave a resting notch silently too wide.

**PROVEN, not assumed:** `forkNotchMode false` now redraws the resting shape
as a floating pill with four round corners and a gap below the screen edge;
`true` returns it to flush with the concave flare. Screenshotted both ways.

#### The notch was invisible in fullscreen

Reported as "in fullscreen I open `$mod P` and cannot see the notch".
Hyprland draws a fullscreen window **above the Top layer and below the
Overlay layer**, and the island sits on Top, so the chord HUD was underneath
it.

The layer promotion was a hand-written list of nine panels — and the list
*was* the bug. It named the ones somebody had hit the problem with, so the
wallpaper picker and settings panel appeared over fullscreen while the chord
HUD, cheatsheet, notifications, notification centre, control centre,
expanded player and workspace indicator did not, and every panel added later
would default to invisible with nothing to suggest why.

Replaced by the general rule: **Top while resting, Overlay while showing
anything.** Resting is the same three states the file already tests for
elsewhere — `normal`, `lyrics`, `custom`. Resting must stay on Top or the
notch would sit over fullscreen video permanently, which is the opposite
complaint. Verified both directions against a real fullscreen window: HUD
visible at layer level 3, resting back at level 2 and correctly hidden.

#### awww replaces hyprpaper (wallpaper transitions)

hyprpaper has no transition: `hyprctl hyprpaper wallpaper` swaps the buffer
between two frames, so every wallpaper change was a hard cut. `awww` — which
is what `swww` is called now, shipped as `extra/awww`, so searching for the
old name finds nothing — replaces it in `autostart.conf` and
`scripts/wallpaper-sync.sh`, driven with amanhex/ukishima's flags: type
`wave`, angle 30, wave `60,30`, fps 60, step 90. The first set at login is
deliberately `none`: there is nothing to transition FROM, so a wave would
play over a bare colour.

**MEASURED, and the reason this was worth doing:** `userconfig.json` has
carried `wallpaperTransitionType: "center"` the whole time. That is an
awww/swww parameter name, and with only hyprpaper installed it was
configuring a program that was not present — inert, and indistinguishable
from a setting that simply did not work.

`wallpaper-set.sh` → `wallpaper-sync.sh` remains the single choke point, so
the island's own picker inherits the transition without changes.

#### The island fill on a neutral theme

Reported as "always black". It was, and darkening was the wrong knob.
gruvbox's background slot is `#282828` — R, G and B **identical**, channel
spread zero. Scaling all three by any constant leaves them identical, so
every value of `darkenTowardBlack` yields a grey. The hue now comes from the
**accent** instead: `darkenTowardBlack` 0.35 → 0.45 with `accentMix` 0.08.
Measured across four palettes, spread goes from 0–12 to 14–18 at ~3 points
less luminance. Sampled from the framebuffer afterwards: `#282318`, spread
16, matching the prediction exactly.

#### One morph duration for every distance

The resting capsule gaining its EQ allowance (~40 px) and resting →
control centre (~980 px) both ran at 400 ms. A 980 px move in 400 ms covers
2.45 px/ms, which no curve makes read as mass — it reads as a jump with a
wobble, and that is most of "the animation is not smooth". `Motion.js` now
interpolates duration on distance, 400 ms below 120 px to 760 ms at 900 px.
The idea is ukishima's (its Motion singleton carries both `morph: 420` and
`shapeshift: 820`); the implementation is ours, because a two-value step
picks the wrong one at the boundary.

**The trap:** the obvious spelling, `duration:
Motion.morphDurationFor(target - displayedWidth)`, reads the property the
Behavior is animating, so the distance falls to zero mid-flight and Qt
applies a `setDuration` under the running animation. Latched in a
`ScriptAction` at the head of the Behavior instead, which runs once before
the first frame.

#### Left and right click were never configured

`dynamicIslandPrimaryButton/Action` and `dynamicIslandSecondaryButton/Action`
were all absent, so clicks ran on the compiled binary's defaults with
nothing on this machine recording what they were. They are stated outright
in the packaged config app's own source,
`/usr/lib/qt6/qml/TideIsland/Interaction.qml`: buttons `{Left:1, Middle:2,
Right:3}`, `playerAction "toggleExpandedPlayer"` on 1 and `controlAction
"toggleControlCenter"` on 3. Now written explicitly and swapped on request —
left opens the control centre, right the expanded player — with all four
exposed as panel rows so reversing it is a keypress.

#### Adding your own settings rows

`~/.config/tide-island/settings-extra.json` is a JSON array of descriptors
merged over the twelve curated rows in `island-settings.py`. A matching key
overrides that row field by field; a new key appends; `order` places it
(built-ins are implicitly 10, 20, 30 …). A template with six working rows is
`.config/tide-island/settings-extra.json.example` — `cp` it across to switch
it on. `island-settings.py --check` validates the file from a shell, and the
panel shows any problems in an amber banner along its bottom edge.

A bad row is **skipped, not fatal**, and the panel chips every row that did
not come from the script — `yours` for a new one, `edited` for an override.
That second chip is doing real work: an override may replace a `detail`, and
those details are where this repo recorded why a default is what it is, so a
row showing reasoning that is no longer the repo's has to say so.

**The trap the whole design is arranged around: a row cannot make a key
MEAN anything.** A descriptor is a writer, not an implementation. Packaged
keys work because `UserConfigBackend` has a property of that name; `fork*`
keys work because `ForkConfig.qml` reads them and fork QML consumes them. A
key neither reads is INERT — the panel shows it, the write succeeds, the
file gains the key, nothing happens. That is exactly the
`forkPolkitAgentEnabled` situation described above (that row is now gone
entirely), which is why `scope: "packaged"`
keys are checked against the backend's real property list and warned about,
and why the docstring says so twice.

**MEASURED, and a correction.** `island-settings.py` claimed
`IslandBackend.qmltypes` lists "exactly 39 properties". It lists **44** on
tide-island 1.0.34-1. The count was wrong; the load-bearing half of the
claim — that none of them is a `fork*` key — was re-checked and still holds,
so the conclusion stood. The 44 are now enumerated in the script rather than
described, which is what the miscount cost.

Two smaller things fell out of building it. `type: "string"` is **not**
supported: `SettingsLayer.qml`'s `change()` has branches for bool, enum and
int and there is no text-entry field in a panel that lives under a keyboard
grab, so a string row would render and ignore every keypress — an enum
covers the case where the string is one of a known few. And `default` is not
a preference: it is what the panel DISPLAYS for a key absent from
`userconfig.json`, so it must equal the consumer's own fallback, or the
panel opens reading 12 for a key the shell treats as 14 with nothing on
screen to say which is real.

### WAS open: the island does not yet LOOK like the video — now largely closed

Reported directly, and it is not one bug: element sizes, icon sizes and
padding across the panels, and the chord/mode indicator's appearance. The
scale factor in `qml/common/Metrics.js` made everything proportionally
smaller from a 38 px design to a 28 px bar, which is a different thing from
being designed at 28. `pad()` is already super-linear for exactly this
reason and it is not enough.

This needs looking at each panel against the spec and adjusting, not one
number changed. It is the largest thing left.

**Since written — it WAS one number, and the paragraph above had the
diagnosis backwards.** "The sizing of the element and font in all the
island is not proper" and "some elements look eaten, not full" are the
same bug, and it is the interaction of two lines in `Metrics.js`:

* `px()` shrank every container by 0.74, while
* `font()` **floored at 9**.

Below a source size of ~12 that floor did all the work — font(10), font(11)
and font(12) all returned 9. Boxes kept shrinking, the text in them stopped,
and the text ran out of its box. That is "eaten" precisely: labels clipped
at the descender or the last character. It also flattened four deliberate
type sizes into one.

The premise was the real error. 28/38 exists because qtile's BAR is 28 px
and the resting notch must match it. **No expanded panel is bound by that**
— a picker or a sheet hangs below the bar as a free-floating surface. They
were shrunk to fit a constraint that does not apply to them. Verified
before changing anything: the resting shape comes from
`userConfig.islandWidth/islandHeight`, not from Metrics, so the two are
genuinely separable and raising the panel scale cannot grow the notch.

Now: `SCALE = 0.92` for panels (a little tightening is still right for
1366x768; a quarter was not), `FONT_SCALE = 1.0` because legibility is an
absolute rather than a ratio, and `pad()`'s 1.35 boost removed — it existed
to claw back what the 0.74 took, and keeping both would double-count.
Measured: mode_keys(rofi) 191 → 232 px, cheatsheet 362 → 446 px, nothing
clipped in either.

`.pragma library` JS is **cached by the running shell** — editing Metrics.js
and reloading changes nothing, and the panel measuring the same as before is
the only symptom. The island process has to be restarted to test a change
here. That cost a wrong conclusion once already.

The rofi menus were widened in the same pass (`~/.config/rofi/themes/
base.rasi`): font 12 → 13, window padding 16 → 22, radius 12 → 18, element
padding 7/10 → 11/14, row spacing 4 → 7. A launcher tighter and
smaller-typed than everything around it reads as the odd surface. One real
bug found there: `config.rasi` asks for `icon-size: 24` and the theme forced
`20px` — a theme rule beats the configuration block, so every icon in every
menu had been drawn a fifth smaller than configured.

The control centre's Sound slider did NOT already cover audio — it is the
volume of the default sink, and qtile's popup was about everything that
is not the default. That table is in MIGRATION.md too.

#### Since that pass: the resting state was rebuilt, and it is what closed this

The paragraph above ended by saying SIZE was fixed and LAYOUT was not.
Layout is what the 35 commits since have been. The resting island is no
longer a clock in a black box — it is a composed row, and each piece of it
was argued and measured:

| what changed | commits | how it is known |
|---|---|---|
| Flank icons are real application icons, not glyphs — a dark plate, a circular clip, sized off the ring's own diagonal, padded on the timer's padding | `0e29f6d` `0230d1f` `acae9c9` `c44999e` `f49cf5a` | screenshotted at each step; the "glow" that looked like a rendering artefact turned out to be an underdamped spring (`4e04f2f`) |
| The focus ring is the countdown's ring — `OsdLayer`'s `ProgressRing`, not a round CSS-style border — and thinned to an accent rather than a frame | `4edeb81` `9d13ea4` `fdd0e60` | `93ded25` also records a Canvas bug that was hiding the rings entirely |
| Icons are filtered to the current workspace, off Hyprland toplevels | `28ac816` | — |
| Water-drop entry animation, playing once rather than on every model change | `e2cd506` `0fa0432` | the flicker behind it was the model reading the window TITLE, so any title change rebuilt the row (`94e44d0`) |
| The workspace readout stopped being a ring and became type, then moved INSIDE the capsule as real content rather than an overlay floated over it | `ead5311` `7a5a43f` `2a078a1` `4a0e2ac` `35accc4` | it now shows only on the plain resting clock |
| The capsule's corners stop finishing 340 ms before the capsule does | `0dc2480` | — |
| The resting surface is back on Top after a spell on Overlay; the kanji are gone; popups take the island's colour | `e38f549` `4965022` | verified live: `hyprctl layers -j` reports the quickshell layer at 1366x58, level 2 |

So the honest status of this heading is: **the resting state and panel
sizing are done; per-state LAYOUT against the reference video is
UNVERIFIABLE from here and always was.** I still cannot see video frames.
What was checked was DESIGN-SPEC.md, which is a transcript of the author
narrating his own numbers, and the shell now matches it everywhere the
spec gives a number. Where the spec gives only a description, this is a
judgement call that has been made and cannot be measured. Saying "still
open" would imply there is a test that has not been run; there is not.

**The chord/mode indicator's appearance — CLOSED, see the numbered list's
item 8 below for the commits and the live verification.** This note is
what item 8 there now says was stale.

#### Motion, and the panel-to-panel glitch

Reported as "going from one popup to another is laggy and glitchy", then
more precisely as "it goes up down glitch for 0.1 s". Both were the same
bug and it was in none of the places it looked like it was.

A panel is destroyed shortly after it closes, so every open constructed a
fresh one whose model was empty and which fetched asynchronously. For one
to three frames the panel was therefore real, laid out, and CONTENTLESS,
and the capsule was faithfully animating to the correct height for an
empty list before animating to the real one. Measured across all 156
ordered pairs of the thirteen panels: 71 collapsed below 60% of their
settled content mid-swap, and it is a property of the DESTINATION, not the
source. `PanelLoader` gained `retain`, applied at five sites — display,
audio, power menu, settings, theme picker. Full write-up in `0c124cf`.

**Two things deliberately left alone, on measurement rather than taste.**
Wi-Fi measured the cleanest destination in the matrix because it already
sets a "reading networks…" status, so there is nothing for retention to
fix. Bluetooth was tried WITH retain and measured no better — its empty
frame is a different bug, still undiagnosed, and it was left alone rather
than shipped with a change that buys a permanent mount and nothing else.

**Still open, and stated in the commit itself:** retention does not
survive a config reload, so the first open of each retained panel per
session still pays the empty-model frame once. Verified as still true —
`retain: true` appears at exactly five sites in `DynamicIslandWindow.qml`
and `PanelLoader.qml`'s `active` is `live || holdTimer.running || (retain
&& everLoaded)`, with `everLoaded` latched at runtime and therefore reset
by every reload.

The rest of the motion pass: the capsule radius duration (`0dc2480`), the
player's progress bar animating progress rather than width (`0a67d60`),
and the control centre's own morph following `Motion.SCALE` like
everything else (`cfb46b5`).

Original notes below.

**Was: NOT STARTED**

Base: [Tide-island](https://github.com/enhaoswen/Tide-island) — Quickshell
(QML/Qt6), targets Hyprland and niri. The video's shell is unavailable
(see above), so Tide-island is the base and gets restyled to the spec in
`DESIGN-SPEC.md`.

**The restyle target is now fully specified** — no longer blocked:

| | |
|---|---|
| Collapsed shape | 150 × 38 px pill — the entire top surface, no bar at all |
| Floating form | 11 px below top edge, all corners rounded |
| Notch form | flush, top corners square, 14 px concave flare per side |
| Morph | ONE path interpolated in two phases (un-round, then flare) — never two shapes swapping, that "looks cheap instantly" |
| Colour | hardcoded `#000000`, **not** theme-tinted |
| Overshoot | 4 px past screen top, clipped, scaling to 0 in floating form |
| Motion | real spring: 400 ms, damping 0.8 — fades on a separate critically-damped curve |
| Fonts | Inter / Inter Display (stated substitutes for SF Pro), Inter Medium body |
| Resting state | clock + 4-bar EQ only. No workspaces, tray, battery, Wi-Fi |
| Expansion | hover, or click to pin. Media/notifications swap content without expanding |

**Conflict to decide (item 4 vs item 1):** the spec says the notch shape must
stay pure black and ignore the theme, because it is imitating bezel — tint it
and "it stops being a notch and becomes a colored blob." My recommendation:
theme everything *inside* the notch, keep the shell shape black. Your call.

Work:
- Clone to `~/.config/quickshell/`, enable `qs -c tide-island` in
  `autostart.conf` (line is already there, commented)
- Restyle to the table above
- Rebuild the 13 qtile popups as QML pages inside the notch:

  | Popup | qtile bindings | Source |
  |---|---|---|
  | AudioPopup | 25 | `qtile/popups/AudioPopup.py` |
  | DisplayPopup | 28 | `qtile/popups/DisplayPopup.py` |
  | WifiPopup + WifiQR | 14 | `qtile/popups/WifiPopup.py`, `WifiQR.py` |
  | BluetoothPopup | 12 | `qtile/popups/BluetoothPopup.py` |
  | WallpaperPopup | 9 | `qtile/popups/WallpaperPopup.py` |
  | Cheatsheets (Qtile/Vim/Fish) | 16 | `qtile/popups/*Cheatsheet*.py` |
  | UpdatesPopup | — | `qtile/popups/UpdatesPopup.py` |

  Total: 104 bindings restored, plus Media-Mode's 17 = **121**.
- Keep the original keymaps exactly (chord entry keys are reserved and
  commented in `binds.conf`)

Effort: weeks. This is the long pole of the whole migration.

---

## 2. Liquid glass

**Status: INSTALLED, ENABLED AND LOADED.**

```
hyprpm add https://github.com/hyprnux/hyprglass   # builds vs local headers
hyprpm enable hyprglass
```

`hyprctl plugin list` reports hyprglass 1.0.0; `hyprctl configerrors` is
empty; every setting reads back correctly, including `tint_color` as
`0x282C3440` — doomone's `$glass_tint`, so the glass follows the theme.

**`hyprglass.conf` had to be rewritten against the real plugin.** It was
transcribed from the video's narration before the plugin existed here,
and four things in it were wrong in ways that fail silently:

| Was | Actually |
|---|---|
| `preset = apple` | key is `default_preset`, and **there is no `apple` preset** — built-ins are `high_contrast`, `subtle`, `clear`, `glass` |
| `layers_enabled`, `mask_threshold` | not top-level keys; layers is a nested block, thresholds are per-namespace |
| `edge_thickness = 0.18` | documented range is 0.0–0.15 |
| `tag hyprglass_theme_light` | needs the leading `+` |

The video's "just run the Apple preset" names a *look*, not a shipped
preset, so the config now **defines** an `apple` preset with the video's
restraint values and sets `default_preset = apple`. This matters
mechanically, not just cosmetically: preset values outrank global ones
(preset chain → theme override → global → default), so tuning left loose
in the block would have been silently overridden.

**Native blur stays on.** The old claim that blur must be globally
disabled was wrong: `manage_window_blur` (default on) sets `noblur` per
glassed window, so native blur keeps serving everything else. The real
constraint is `blur:new_optimizations`, already false.

**Layers (bar glass) stay OFF** — that answers open question 3 as
"windows only". Empty `namespaces` means *all* layers, not none, and
layer support hooks Hyprland's private render pipeline.

**Not captured by the package audit.** hyprpm plugins are not pacman
packages, so `wizard.sh --audit` cannot see hyprglass and a fresh
machine will not get it. Re-run the two commands above after a rebuild,
and `hyprpm update` after **every** Hyprland upgrade — the plugin is ABI
locked and silently refuses to load against a mismatched compositor.
`autostart.conf` runs `hyprpm reload -n`, because the enabled flag
persists but does not load the plugin into a fresh compositor.

Original notes below.

**Was: CONFIG WRITTEN — `hyprglass.conf` + `hyprglass.lua`, awaiting install**

Written from the video's own settings and warnings. Already handled:

- **Apple preset** as the base, per the author's explicit recommendation
  ("just run the Apple preset, whitelist your bar, tag off MPV, and you're
  done"). The plugin defaults are already near Apple's look.
- **The `new_optimizations` bug is pre-fixed** — `looks.conf` had it `true`,
  which is the precise cause of "glass vanishes when you release a dragged
  window". Now `false`, with the reason in a comment.
- **The empty-whitelist trap** documented at the config site: an exclude-only
  config leaves the whitelist empty, and an empty whitelist glasses *every*
  layer on the system.
- **`mask_threshold` set to 0.05, not the 0.001 default**, so widget drop
  shadows don't grow glass rectangles around their shadow boxes.
- **`layers_enabled = false`** for now — the author tried 0.3 and 0.7 on his
  own Quickshell surfaces and ended up excluding them entirely.
- Per-window tags: glass off for mpv and fullscreen, light theme for
  browsers, high-contrast for kitty.

Still needs you: `hyprctl version` before install. Current release targets
**Hyprland 0.56**; on 0.55 take the **v0.6.4** release instead.

The mechanism behind video 2 is the **hyprglass** plugin
(<https://github.com/hyprnux/hyprglass>) — not a config setting. It models
windows as convex glass slabs: frosted multi-pass blur, edge refraction
via UV displacement, chromatic aberration, centre dome lens magnification,
Fresnel edge glow, specular highlights, adaptive tone mapping.

```
hyprpm add https://github.com/hyprnux/hyprglass
hyprpm enable hyprglass
```

Three things to know before committing:

1. **It cannot run alongside Hyprland's built-in blur on the same windows.**
   `looks.conf` currently enables `decoration:blur`. That has to come off
   for any window hyprglass handles.
2. **It is ABI-locked to your Hyprland version.** The plugin compares its
   build-time signature against the running compositor; a Hyprland update
   can break it until rebuilt. `hyprpm update` after every Hyprland upgrade.
3. **Layer-surface glass (bars, docks) hooks private Hyprland internals**
   and is off by default. Applying glass to the notch bar is exactly that
   case — expect it to be the fragile part.

Alternatives if the plugin proves too brittle: `hyprpm` fork
[liquid-glass-plugin-hyprpm](https://github.com/purple-lines/liquid-glass-plugin-hyprpm),
or approximating with native blur + opacity, which gets frosting but not
refraction or the lens effect.

---

## 3. All my scripts, same keymaps, same behaviour

**Status: PARTIALLY DONE**

Already ported (they never touched the WM): `brightness_control.py`,
`volume_control.py`, `mpv_manager.py`, `prayer_next.sh`, `fx_rates.sh`,
`sum_app.py`, `screenshot-area.sh` (→ grim+slurp), and the whole
Rofi-Mode launcher set — 20 dmscripts/rofi tools, transferred verbatim.

Since written, the "still to do" list has emptied:
- **App togglers (7)** — DONE. `scripts/toggle-app.sh` is the generic
  rewrite that was called for: `hyprctl clients -j` lookup, focus if
  present, spawn if not. All seven are bound (`$toggle` in binds.conf).
  Two bugs found in daily use and fixed there: an unanchored matcher
  claimed windows belonging to the scratchpads, and any window on a
  special workspace is now excluded outright.
- **`sum.md` toggle (1)** — DONE, `$mod SHIFT S`. It only ever *opened*
  until the class was fixed: qtile matched on TITLE, this script matches
  on class, and `kitty --title nvimsum` has the class `kitty`.
- **`qdrop.py` / `qdrop_watch.py`** — superseded by special workspaces.

**The rule this item states has now lost almost entirely, and that is a
change of policy, not a slip.** It said: rebuild the *interactive* popups
in the shell, leave the *launcher* problems on rofi. The cheatsheets went
first, for the reason argued above. Then the rest of the chord followed
(`c42cfac`, `9981bf5`, and the clipboard in `8d788ba` / `bc87691`).

The simpler observation that beat the rule twice is the same one both
times: every other surface on this desktop lives in the notch, and a rofi
window over the desktop is the odd one out. What rofi actually contributed
was *the typing, not the window* — so a picker with a search field keeps
everything rofi was good for.

`$mod P` is now the island's `PickerLayer` on every key but one — it was
two until `rofi_anki` moved as well, see below. The four
list-shaped menus went first; the other ten needed the panel to grow **a
page stack and a prompt mode**, because they are not single lists — a
screenshot asks "where does it go", a spell-check asks for a sentence and
then which mistake to fix, and `dm-confedit` is a directory walk. The
panel holds a stack of opaque pages and `hypr/scripts/island-picker.py`
decides what each id means. The panel is never handed a command: the
script returns rows of `{id, label, detail}` and takes an `id` back,
because a picker that executes strings supplied by a script executes
whatever can write to that script.

**Three ports drop something real, and all three say so at the site:**
`dm-recordV2`'s screen capture (below), `rofi_pass`'s write half, and
`rofi_todo`'s sessions. The rofi originals are untouched on disk and the
qtile session still uses every one of them.

##### What still opens a rofi window under Hyprland — the count was wrong

`rofi_anki` (`$mod P` → `a`) and `rofi_ilovepdf` (`$mod P` → `v`) are the
deliberate exceptions, and `binds.conf` calls them "the only two keys in
this chord that are still rofi". Within the chord that is true. **As a
statement about the session it is not**, and cross-referencing
`hyprctl binds -j` against every script in `.config/AtiScriptsV1/` found
the others:

| bind | script | rofi? |
|---|---|---|
| `$mod P` → `a` | `rofi_anki` | **no longer — PORTED, see below** |
| `$mod P` → `v` | `rofi_ilovepdf` | yes — deliberate, a file-picker/page-range/OCR pipeline |
| `$mod P` → `SHIFT c` | `theme-toggle` | yes — deliberate and documented; it is the qtile session's picker and it keeps working when the island is down |
| **`$mod SHIFT F6`** | **`phone_screen`** | **yes, and undocumented anywhere.** Its QR/pairing path calls `require_cmd qrencode rofi` and pipes into `rofi -dmenu -i -format f` against `~/.config/rofi/themes/base.rasi` |

`phone_screen` is a fourth rofi surface that nothing recorded. It is not
obviously wrong — it is a wizard like the other two deliberate ones, and
by that reasoning it belongs with them rather than in the picker. But it
was never *decided*, and "the only two" has been stated in `binds.conf`
and in this file while a third was one keypress away. **Open: decide it
explicitly and correct the claim in `binds.conf` either way.**

##### `rofi_anki` is ported, and the reason it was "unportable" was avoidable

Asked for directly — "anki and some other things still as rofi, change
them" — so the four routes above were revisited one at a time rather than
ported wholesale. Only one moved.

`island-picker.py` had argued rofi_anki could not be ported because it is a
linear wizard where each step depends on the last, so porting it "would
mean this file growing a second copy of each script's control flow, with
the original left in place as the one that still works". **The first half
is not an obstacle and the second half is not forced.** A page stack IS a
linear wizard — this file already runs three — and the duplication the note
feared is avoidable by moving the PROMPTS instead of the logic.

Counted rather than recalled: rofi_anki's eight prompts are lines 181–305
of 373. The other 343 — the AnkiConnect handshake and 45 s poll,
`createDeck`, the model check, Gemini with a translate-shell fallback,
espeak-ng IPA, three flavours of TTS concatenated by ffmpeg,
`storeMediaFile`, the HTML assembly, `addNote` — do not care which window
asked the questions.

So `rofi_anki` gained `--answers FILE`, the picker's `anki` menu asks the
eight questions and hands them over, and there is still exactly one copy of
the card logic. The default invocation is unchanged, so the qtile session
keeps the rofi prompts.

Two places the port is better rather than merely elsewhere: the four yes/no
audio-and-image questions were four sequential rofi windows answered blind
with no way back, and are one page of four toggles now; and "Add an image?"
followed by "paste the URL" said one thing in two steps, so a non-empty URL
is the yes.

Measured against a live AnkiConnect: every step driven through the
protocol, `go` produced a real note (Front `Fahrrad`, Back carrying the IPA
and the translation), deleted afterwards. Against the running shell:
`showPicker anki` promoted the island to level 3 and grew it 58 → 206 px,
screenshotted; `configerrors` empty; the bind reads back fully expanded
from `hyprctl binds -j`.

**The other three stay, and each for its own reason — not for one policy.**

| route | why it stays |
|---|---|
| `rofi_ilovepdf` (`$mod P` → `v`) | it is a **file manager**, not a wizard. `order_files` selects SEVERAL files and orders them so merge has an order to merge in, and the picker protocol carries exactly one id back per page. Porting it means building selection state into `PickerLayer.qml` or shipping a PDF toolkit that has lost merge |
| `theme-toggle` (`$mod P` → `SHIFT c`) | `c` is already the island's theme picker on the same chord. This one exists to keep working when the island is down, and it is the qtile session's picker |
| `phone_screen` (`$mod SHIFT F6`) | decided above and unchanged |

The standing policy in this item — "rofi keeps the `dm-*` launchers" — was
treated as rebuttable and it lost once and held twice. What decided each
case was not launcher-versus-popup but whether the picker's one-id-per-page
protocol can express the interaction, and whether the route has to survive
the shell being down.

Method note, because the claim had gone unchecked for several sessions:
seven `AtiScriptsV1` scripts are reachable from a Hyprland bind at all —
`clock_popup`, `phone_screen`, `rofi_anki`, `rofi_ilovepdf`,
`theme-toggle`, `ati-voice-dictate`, `ati-voice-dictate-live`. `clock_popup`
mentions rofi only in comments. Everything else in that directory is
qtile's, or is called by another script, and cannot be reached from this
session.

##### Screen capture: the X11 tools, and what actually replaced them

The outstanding list has been carrying "`dm-satty` uses `maim`/`xdotool`/
`xclip` — X11 tools that produce BLACK output under Wayland". That is
still true of the file, and it is now **irrelevant to this session**:
`dm-satty` is not reachable from any Hyprland bind. It was not wrapped, it
was rewritten. `$mod P` → `i` opens the picker's screenshot menu, which is
`grim` for the capture, `slurp` for the rectangle, `hyprctl` for the active
window's geometry, `wl-copy` for the clipboard, and satty unchanged
because satty is Wayland-native already. `Print` on its own is a direct
`grim -g "$(slurp …)" | wl-copy`. Both verified present in
`hyprctl binds -j` with the command fully expanded.

`dm-satty` stays on disk because the qtile session still uses it. The
correct record is that it is X11-only *and unreachable from here*, not
that it is a Hyprland bug waiting to bite.

**`wf-recorder` is genuinely missing, and this one is unresolved.**
`command -v wf-recorder` finds nothing. `$mod P` → `r` opens the record
menu, which lists its rows with the detail "wf-recorder is not installed"
rather than hiding them, and refuses on selection with the same message
pointing at the note in `island-picker.py`. That is the right failure
shape — visible, explained, not silent — but it means `dm-recordV2`'s
screen and region recording is the one qtile capability with no working
equivalent in this session. `sudo pacman -S wf-recorder` closes it. The
same X11 root cause is what made `ffmpeg -f x11grab` record black video.

Also verified while sweeping: **no keybind points at a binary or script
that does not exist.** Every `exec` in `hyprctl binds -j` resolves, and
every script in `hypr/scripts/` is referenced by something — several only
by QML, which is why a grep of `binds.conf` alone under-reports them.

On the popup-vs-menu question you raised: **rofi already works on Wayland**
under XWayland, and every one of your `dm-*` scripts runs unchanged. So
there is no forced rewrite. The Wayland-native equivalents are **wofi**
(closest to rofi) or **fuzzel** (faster, actively maintained) — worth
switching only if XWayland rofi misbehaves.

Preference: rebuild the *interactive* popups (audio, display, wifi,
bluetooth, wallpaper) as Quickshell pages per item 1, and leave the
*launcher* scripts on rofi. Launchers are a list-and-pick problem rofi
already solves well; the popups are stateful controls that genuinely
benefit from being in the notch.

---

## 4. System-wide theming

**Status: DONE and verified live.**

`gen_hypr_colors()` is in `theme-apply` (line ~398) and wired into
`gen_all_theme_css()`. Verified in a running session: `theme-apply
doomone` regenerated `~/.config/hypr/colors.conf` with the doomone
palette and the live border colour became `ff98be65` (doomone green)
without a restart. `hyprctl configerrors` stayed clean.

Both guards work as designed — it returns early if `~/.config/hypr` is
absent, and only shells out to `hyprctl reload` when
`HYPRLAND_INSTANCE_SIGNATURE` is set, so running it from the qtile/X11
session is unaffected.

Note: `~/.cache/qtile/theme_mode` said `doomone` while `colors.conf`
still held catppuccin values — the two had drifted. Re-applying doomone
reconciled them. The shared state file does keep both sessions in sync,
but only for themes applied *after* the Hyprland target existed.

**The Quickshell/QML target is now DONE too.** `gen_island_colors()` sits
beside `gen_hypr_colors()` in `gen_all_theme_css()` and writes
`~/.cache/tide-island/colors.json`; the island watches that path and
repaints live. JSON rather than Hyprland's `$name = rgb(hex)` form because
the consumer is QML — the palette is still generated once, from the same
nine arguments, in the same call.

This is what makes the island's background follow the theme, which is a
**deliberate reversal of DESIGN-SPEC.md** on the user's explicit
instruction. Written up under "Colour — hardcoded black" in that file,
including why the fill is the background slot blended 35% toward black
rather than the raw palette colour.

**Two traps, both of which failed silently and both of which are the same
mistake in different clothes: something that looks wired up and is not.**

1. `theme-apply` wrote the file with `mv` from a temp file — the correct
   pattern almost everywhere, and wrong here. Quickshell's `FileView` is a
   `QFileSystemWatcher` underneath, and that watches the **inode**. An
   atomic rename leaves the watch pointing at the unlinked old file and
   `onFileChanged` never fires again. It is written in place instead; the
   reasoning and the torn-read trade are recorded at the call site.
2. In the QML, the `FileView` was first declared as the value of a property
   on a bare `QtObject`. It constructs, reports nothing, and never fires
   either signal. It has to be an ordinary child in the object tree — which
   is why `IslandTheme.qml` is an invisible `Item`, the same shape
   `WallpaperThumbnailCache.qml` already used.

Both presented identically: the island keeping its fallback palette while
every other target repainted, i.e. exactly "the theme is not wired up".

Remaining under this item: nothing.

Original notes below.

**Was: NOT STARTED — but far cheaper than expected**

`~/.dotfiles/.config/AtiScriptsV1/theme-apply` is 1,660 lines and already
does the hard part: **20+ named themes** (doomone, dracula, gruvbox, nord,
tokyonight, catppuccin, monokai, everforest, rose-pine, kanagawa,
oxocarbon, cyberpunk-neon, synthwave, matrix, mono-dark, mono-light,
nightowl, onedark, palenight, github-dark) plus a `wal` mode driven by
pywal, fanned out to kitty, alacritty, rofi, dunst, eww, brave,
qutebrowser, btop, GTK, Qt, and glow.

**Almost all of it is WM-independent.** It is a bash script writing config
files. The only parts that need touching:

- Add a Hyprland target to `gen_all_theme_css()` that writes
  `~/.cache/wal/colors-hyprland.conf` (border colours, shadow tint) and
  calls `hyprctl reload`. `looks.conf` already has the `source =` line
  for it, commented.
- Add a Quickshell/QML target once the notch bar exists.
- Replace the `qtile cmd-obj` calls with `hyprctl` equivalents — guarded
  on which session is live, so the same script keeps serving qtile.
- `theme-toggle` is rofi-based and works as-is.

The `STATE_FILE` at `~/.cache/qtile/theme_mode` is shared, so both
sessions stay in sync on the current theme for free.

Effort: one day, not one week. This is the highest value-per-hour item
on the list.

---

## 5. Circular theme-change animation

**Status: DONE.** `tide-island-fork/qml/theme/ThemeTransitionWindow.qml`,
one `PanelWindow` per screen, driven from `shell.qml`'s
`startThemeTransition()` and exposed as `tide applyThemeAnimated <theme>`.
The island's theme picker goes through it; the rofi `theme-toggle` can be
pointed at the same IPC whenever you want the animation there too.

All five of the video author's traps are implemented and named at the site
— JPEG q85, the 700 ms safety timer, one boolean for both directions, the
90 ms warm-up, and barely-above-zero opacity while idle.

Two things learned building it that the spec does not mention:

- **The picker cannot own the animation.** It is a `Loader` that unloads
  when the island leaves the picker state, and the first thing a theme
  change does is close the picker — so an animation owned by its trigger is
  destroyed on frame one. It lives in `shellRoot`.
- **The animation must own the apply.** `theme-apply` runs *underneath* the
  frozen frame, after the capture. Letting the picker also run it repaints
  the desktop before the screenshot and there is nothing left to reveal.

`OpacityMask { invert: true }` from `Qt5Compat.GraphicalEffects` is the
whole mechanism: a growing black circle in the mask becomes a growing hole
in the frozen frame. Verified in a standalone `qml6` window before it went
anywhere near the shell — centre transparent, corners opaque source —
because a mistake here paints an opaque sheet over the entire desktop.

**Verifying it needs a trick, and the trick is worth writing down.** The
reveal is invisible to a screenshot under normal conditions, and that is
correct behaviour, not a bug: outside the hole you see a frozen picture of
the desktop and inside it you see the live desktop, and for the first half
second those are the same image. Force them apart — swap the wallpaper the
instant the overlay's layer surface appears — and the circle becomes the
only place the new wallpaper shows. Measured: the
`quickshell-theme-transition` layer is up for ~600 ms, matching capture +
90 ms + 620 ms, and a frame grabbed right after it appears still shows the
OLD wallpaper that hyprpaper had already been told to replace.

### Except that it had never once animated, and the trick above is why

**Everything above this line was true and the feature still did not
exist.** `9574390`. The measurement that "proved" it — the layer being up
for ~600 ms — proved the overlay was *mapped*, which it was. It did not
prove the overlay had anything in it, and it did not.

The `Image` was bound to `capturePath`, which is assigned at the TOP of
`begin()`, because grim has to be told where to write before it is
started. So the Image was pointed, **by construction**, at a file
guaranteed not to exist yet. Qt opened it immediately, failed, and a
failed `Image` does not retry when the file later appears. The animation
then ran its full course masking an image that was never there, which is
invisible. The theme still changed, so the whole thing read as "the theme
just switches" — and nobody could describe what the theme change looked
like because it looked like nothing.

The only trace was one line per theme change in the log:

```
Cannot open: file:///tmp/tide-theme-transition-1786567236546.jpg
```

The fix is a second property. `frozenSource` is assigned in
`beginReveal()`, which only runs once grim has exited 0, and the `Image`
reads that with an explicit empty-string guard. **Re-verified this
session**: driving `tide applyThemeAnimated` against the live shell and
reading only the log lines produced afterwards emits no `Cannot open`
warning at all. (The one `file://undefined` still visible further up that
log is at `ThemeTransitionWindow.qml[280:9]`; the guard now sits at 292,
so that line predates the current file and is history, not a live fault.)

This is the fourth entry in this document's running list of *things that
looked wired up and were not* — after the false polkit warning, the
never-instantiated `ForkConfig`, and the `FileView` on a bare `QtObject` —
and it is the most instructive, because unlike the others it had a
measurement behind it. The measurement was of the wrong thing.

### And the gesture was wrong too — it is a wipe now, not a circle

The circle came from Aylur's Marble Shell. **A wallpaper change on this
machine is not a circle.** `hypr/scripts/wallpaper-sync.sh` drives awww
with `--transition-type wave --transition-angle 30`, so what every
wallpaper change here has trained the eye on is a front crossing the
screen at 30 degrees. The ask was for the theme change to animate "like
the wallpaper changing", and it now is the same gesture: a rotated
rectangle sweeping along its own local axis.

**Measured rather than eyeballed, and the first attempt to measure it was
garbage.** Fitting the frozen/revealed boundary gave 6.5 degrees —
nonsense, because only ~13% of the screen differs between two dark themes,
so the fit was tracking the browser's page content rather than the front.
The right instrument is the band of pixels that changes between
CONSECUTIVE frames, which is exactly the strip the front swept. Its
principal axis came out at **120.0 ± 0.4 degrees over 18 consecutive
intervals**, with the cloud up to 21× longer than it is wide. A front
travelling along a 30-degree axis is a line at 30+90 = 120, so the angle
is right to within half a degree.

Two things the file records at their sites because getting them wrong is
subtle rather than loud:

- **The transform order is load-bearing.** `Translate` is listed FIRST so
  the rotation applies to already-translated geometry and the net motion
  is along the ROTATED axis. Listing `Rotation` first gives a shape that
  sits at an angle while sliding horizontally — a different and much worse
  effect, and one that would have measured as a front angle not matching
  its direction of travel, which is precisely what the 120 degrees rules
  out.
- **Easing went from `InOutQuad` to `Linear`.** A circle's area grows as
  r², so easing its radius is what stops the middle feeling like a burst.
  A straight front already covers area at a constant rate, and easing it
  makes the front visibly accelerate and brake, which awww does not do.

**Not reproduced, and open:** awww's `--transition-wave "60,30"` gives its
front a 60 px period, 30 px amplitude sine edge. A sine edge in QML needs
either a `ShaderEffect`, which wants a precompiled `.qsb` and therefore a
build step this config does not have, or a `Canvas`, which does not paint
while its item is invisible — and this mask is `visible: false` by
construction. At 60 px period on a 1366 px screen the ripple is fine
detail and the angle is what carries the resemblance. A `Repeater` of ~260
thin slices is the fallback and is noted in the file.

Original notes below.

**Was: NOT STARTED**

Source: [Aylur/dotfiles](https://github.com/Aylur/dotfiles) → the shell is
**[Marble Shell](https://github.com/Aylur/marble-shell)**, built on **AGS**
(Aylur's GTK Shell), GTK4 + layer shell, targeting Hyprland.

**Architectural conflict to be aware of:** Marble Shell is AGS/GTK4/TypeScript;
Tide-island is Quickshell/QML. There is no copy-paste path between them.
The animation has to be reimplemented, not ported.

That is fine, because the technique is standard: a full-screen layer-shell
overlay, screenshot of the pre-change desktop, then a circular mask
expanding from the centre to reveal the newly-themed desktop underneath.
In QML that is an `OpacityMask` with an animated radial gradient, or a
`ShaderEffect` — both well-trodden.

**The notch video hands us the implementation details for free** — its lock
screen does exactly this capture-freeze-blur trick, and the author names
every trap:

- **JPEG quality 85, never PNG.** PNG encoding at 2560×1440 plus a second
  monitor cost him ~850 ms. The image gets blurred four frames later, so
  every JPEG artifact is annihilated before your eye reaches it. "Lossless
  is worthless when the very thing you do is destroy the detail on purpose."
- **Safety timer.** If the screenshot tool hangs or is missing, proceed
  anyway after 700 ms. Fail closed, never wait on a screenshot.
- **One boolean drives both directions**, so the animation is symmetric —
  two code paths gave him a black flash in and a lingering frame out.
- **90 ms delay before animating**, so the heavy first frame (decode +
  blur shader compile) finishes before anything needs to move smoothly.
- **Hidden elements sit at barely-above-zero opacity, not zero**, because Qt
  skips buffer allocation on fully transparent items — then they warm up
  during that 90 ms. Exception: go to true zero on the way out, or you catch
  a blurred ghost frame.

Sequence:
1. `grim` captures the current screen (JPEG q85)
2. Overlay layer displays the capture, fullscreen, above everything
3. `theme-apply` runs underneath (item 4)
4. Circular mask animates outward from centre; the old screenshot is what
   gets erased, revealing the retheme
5. Overlay destroys itself

Depends on: item 1 (needs the Quickshell shell to live in) and item 4
(needs the retheme to trigger it around).

---

## What is actually left — audited against the tree and the running shell

Written because the sections above are a reasoned record and not a status
board, and after 35 commits in one session nobody could answer "what is
left" by reading them. **Nothing in this section is taken from what the
document said.** Each row was established by one of: `grep` over the tree,
`hyprctl binds -j` (the only truth for a keybind — an empty
`hyprctl configerrors` never catches a bind that stored a literal `$var`),
`qs -p … ipc show` cross-referenced against every bind, driving the IPC and
reading a `grim` capture, reading the shell's own log, or `pacman -Q`.

Where a thing could not be verified, it says so and says why, rather than
being filed as either done or open.

### Items 0–5, at the top level

| item | status | evidence |
|---|---|---|
| 0. Install Hyprland | **done** | running 0.56.2; keyd bound; `inter-font` now installed and `fc-match` resolves both families to the real font |
| 1. Notch + popups | **done**, and the one outstanding item is now closed by removal rather than by building — see the polkit section | every panel in the spec's state list is bound and opens; verified against `ipc show` and `hyprctl binds -j` |
| 2. Liquid glass | **done** | `hyprctl plugin list` reports hyprglass 1.0.0 loaded; `configerrors` empty |
| 3. Scripts / keymaps | **partial** — one missing package, one undecided rofi surface | see below |
| 4. System-wide theming | **done for what it claims, and it claims less than a reader assumes** — see the caveat below | `theme-apply` drives borders and the island fill live; measured |
| 5. Circular theme animation | **done, and it is no longer circular** | re-verified live this session: no `Cannot open` warning, front angle measured at 120.0 ± 0.4° |

### The genuinely open list

Ordered by how much it costs to be wrong about, not by size.

**1. ~~The polkit prompt is half-shipped and throws.~~ CLOSED — removed.**
It was a live IPC call that put the island into a stateless Overlay limbo
and logged `ReferenceError: polkitPromptLoader is not defined`. Removed
rather than built, because the prompt was never wired to polkit's D-Bus
agent interface at all and polkit-kde-agent was already running and
working. Full write-up under item 1.

**2. ~~The control centre's Focus / DND row does nothing.~~ CLOSED, twice
over.** `dunstctl` landed first, then went moot: the island now SERVES
`org.freedesktop.Notifications` itself and `dunst` is out of
`autostart.conf`, so the row reads `shellRoot.focusEnabled` directly —
no subprocess, nothing to fail. See `ControlCenterLayer.qml`'s
"SILENT IS THE ISLAND'S OWN STATE NOW" comment for the full three-version
history.

**3. ~~`wf-recorder` is not installed.~~ CLOSED — installed** (`0.6.0-2`)
and wired into `island-picker.py`'s recording path (`_island_recording()`).

**4. ~~`phone_screen` (`$mod SHIFT F6`) opens a rofi window~~ CLOSED —
decided and the claim corrected.** It does open one, through
`rofi -dmenu -i -format f` in `AtiScriptsV1/phone_screen`, and
`binds.conf`'s note that the only rofi routes left were "the two wizards
named in submaps.conf" was wrong by one. Three routes, not two; the note
now says so, and the bind carries a pointer to it. It **stays** on rofi,
under item 3's standing policy that rofi keeps the list-and-pick problems
it already solves: an mDNS device list that appears, is picked from once
and goes away is the purest example of that shape in the tree, and porting
it into the island would cost the one property that makes it useful — it
works with the island down, which is exactly when you are most likely to
be attaching a phone to a laptop to find out what is wrong.

**5. Two clocks, ~10 px apart, whenever music is playing. NOT REPRODUCED,
and the mechanism this item gave is wrong.** Left open, but re-scoped, so
the next attempt does not start from the same false premise.

What the item said is half true. `SwipeLyricsLayer.qml` does draw its
clock at `x: shiftedTimeX` (`timeX` minus `animatedGroupShift`, the offset
that keeps the clock/workspace/EQ cluster optically centred) and
`SwipeCustomInfoLayer.qml` does draw its clock at plain `x: timeX` with no
group-shift concept at all. The conclusion — "both are gated on
`timeText !== "" && showSecondaryText`, so with music up both are visible"
— does not follow, because the gate that decides it is not on either
`Text`. It is `customSwipeVisible` / `lyricsSwipeVisible` in
`DynamicIslandWindow.qml`, driving two separate `Loader`s, and those two
conditions are complementary: one wants `swipeTransitionProgress < 0` and
the other `>= 0`, one wants `splitOriginSide === "left"` and the other
`"right"`, and in the one state that could satisfy both (`long_capsule`)
`showSecondaryText` is false on whichever side the workspace came from.
**`musicPlaying` appears in neither condition**, so music cannot be what
mounts both.

Measured, not argued:

- At rest the island renders **one** clock. Framebuffer capture, with
  `lyricsSwipeLoader` as the live one.
- An instrumented build logging whenever both `Loader`s reported `active`
  fired 5 times in 10 swipes, always at `state=normal`, `p ≈ +0.010` —
  the instant the swipe crosses zero. That is a binding-evaluation
  ordering artefact inside a single frame, not two painted clocks: the
  render happens after bindings settle.

What would settle it is a real MPRIS player, and this machine cannot
provide one — `mpv` has no mpris script installed and nothing else
registers on the bus. If the doubled clock is seen again, capture a
**frame**, and suspect `animatedGroupShift` animating while the layer that
owns it is being torn down. The `Text` gates are innocent. The reasoning
is also written at the site, above `expandedLayerVisible`, so the next
reader of the code meets it before the next reader of this file does.

**6. `PanelLoader.retain` does not survive a config reload**, so the first
open of each retained panel per session still pays one empty-model frame.
Stated in `0c124cf` and re-verified: `everLoaded` is latched at runtime, so
a reload resets it. Five panels affected.

**7. Bluetooth's empty first frame is a different, undiagnosed bug.**
`retain` was tried on it and measured no better (0.07–0.26 ink either way),
so it was correctly left alone. Its rows come from the control centre via
`provider` and it has a 400 ms `settleTimer` of its own; one of those is
the cause and neither has been ruled out.

**Re-checked 2026-08-20: still genuinely undiagnosable on this machine, not
re-diagnosed.** `bluetoothctl devices` / `devices Paired` / `devices
Connected` all come back empty — this machine has zero known Bluetooth
peers, paired or in range, same as when this item was first written. The
"empty first frame" the item describes is a transition (blank, then rows
appear as bluez answers) — with nothing that will ever populate here,
there is no transition to capture, so the settleTimer-vs-provider-timing
question cannot be settled without a real device to pair or bring in
range. `root.currentItems` (BluetoothPanel.qml:168) is a plain binding
over `root.devices`, not a latch — unlike the status-text bug this item
sits beside, so the mechanism most likely to cause a STUCK empty list is
already ruled out by reading; what would remain is a genuine one-frame
render-before-provider-arrives flash, which needs the same device to be
present to see. Next session with a phone or earbuds nearby: pair one,
close the panel, reopen it, and watch whether the row appears immediately
or a frame late.

**8. ~~The chord/mode indicator's appearance.~~ CLOSED — stale, this was
already built out.** `edbf6ec` (the chord HUD itself: header, mode name,
Esc hint, a 1/2/3-column key-chip grid sized by row count) plus two later
token/colour passes (`96738de`, `8ec2912`) already gave it the same
`IslandTheme.*` treatment as every other panel. Verified live 2026-08-20:
`tide showModeKeys lang` renders a clean styled HUD, key chips and action
labels legible and consistent with the rest of the shell — not the
underdesigned surface this item describes. This note predates that work.

**9. awww's sine-edged wave front — BUILT 2026-08-20, not visually
verified.** The `~260-slice Repeater` this item itself proposed as the
fallback, built against real numbers: awww's own `--transition-wave
"60,30"` flag (60 px period, 30 px amplitude), already recorded verbatim
in this file's own comment — this was not a guess, the spec was sitting
in the tree the whole time.

Purely additive: `wavefront` (`ThemeTransitionWindow.qml`) went from a
plain `Rectangle` to an `Item` with the *identical* width/height/transform
(the translate+rotate math that was already measured angle-accurate to
half a degree — untouched, not re-derived), holding a `Repeater` of thin
slices whose width is `sweepLength + 30·sin(2π·y/60)`. Nothing about the
proven geometry changes; the wave only adds content inside the same
already-correct bounding box. Loads clean — `Reloading configuration...
Configuration Loaded`, no QML errors — and a live `hyprctl dispatch` /
`tide state` smoke test after touching it read normally.

**What was NOT achieved: seeing it.** Tried `grim` bursts (up to 20
frames at 25ms) and `wf-recorder` at 60fps across five different real
theme changes (gruvbox→dracula→catppuccin→everforest→kanagawa, both
`island` and `native` bar modes) — every capture showed the wallpaper/
colours already fully settled to the new theme with no sweep frame ever
caught, front OR back. Ruled out qsipc as the cause: called
`applyThemeAnimated` with bare `qs` directly (not qsipc) and got the
identical no-visible-sweep result — both clients hit the exact same
server-side handler, so this is not something introduced by the keybind-
latency work either. Since the SAME tooling could not catch the
pre-existing straight-edge sweep any better than the wavy one, the honest
read is a capture-tooling limitation (the 620ms transition completing
faster than these tools' effective startup+capture latency), not a
regression from this change — but that is inference, not verification.
**Next session with working capture: drive `theme-animate <mode>` and
confirm the front is visible at all before judging whether the wave reads
correctly.** Session state was restored after every test (theme back to
`gruvbox`, bar-mode back to `native`).

**10. ~~Updates has no home anywhere.~~ CLOSED — by abandonment, which is
the honest disposition rather than a dodge.** qtile's
`2nd_system_widgetbox` label was `Updates · Disk · Volume`; the sysmon
panel covers Disk, the control centre covers Volume, and Updates never
ported. The reason it never ported is that **there was nothing to port**:
qtile's own Updates-Mode is commented out in its `config.py`, so the
feature was already dead in the session being migrated from. Porting it
would not be finishing the migration, it would be building something new
and calling it parity. Recorded here so the label table stops reading as
two-thirds ported with no explanation, and so nobody re-opens it as a gap.

### Superseded / abandoned, so they stop being counted as open

| | why |
|---|---|
| `dm-satty`'s X11 tools | **superseded.** Rewritten, not wrapped: the picker's screenshot menu is grim + slurp + hyprctl + wl-copy + satty. `dm-satty` is unreachable from any Hyprland bind and stays on disk for the qtile session |
| `qdrop.py` / `qdrop_watch.py` | **superseded** by special workspaces |
| "leave the launcher problems on rofi" | **superseded as policy.** The chord is the island's picker on every key but ONE (`v`, rofi_ilovepdf), plus `theme-toggle` and `phone_screen`. `rofi_anki` was the last wizard to move, and what decided it was not the launcher/popup split at all — see item 3 |
| Per-state layout vs the reference video | **abandoned as a test, not as work.** I cannot see video frames and never could. DESIGN-SPEC.md — a transcript of the author narrating his own numbers — is matched everywhere it gives a number. Where it gives only a description this is a judgement call that has been made. Calling it "open" implies an unrun test; there is none |

### Could not verify, and why

- **Anything requiring a real keypress.** `wtype` sends to the focused
  surface, not through compositor bindings, and there is no `ydotool`
  here. Every binding in this document is verified through
  `hyprctl binds -j` — modmask, key, submap and the fully expanded
  command — and by executing the dispatcher or IPC call directly. The
  physical keystroke itself is unverified for all of them. `hyprctl
  binds -j` was swept for unexpanded `$` variables, which is the failure
  `configerrors` does not catch: two hits, both false positives (a `$` regex
  anchor in a `toggle-app.sh` matcher, and a `$(slurp …)` command
  substitution on `Print`).
- **The reference video's appearance.** As above.
- **Whether the ~10 px clock gap is exactly 10 px.** The code path is
  proven; the number is the original report's and was not re-measured,
  because doing so means driving music through the live shell.

### A caveat on item 4 that its own section does not carry

Item 4 says theming is "DONE and verified live", and for what it covers
that is true. It covers less than a reader assumes: the shell *fill* and
the window borders. `upgread_UI_UX.md` counted the rest — 115 distinct raw
hex literals across 33 files at 288 sites, plus 112 uses of `StyleTokens`,
whose 55 properties are read out of `IslandBackend.qmltypes` as
`isReadonly: true` **and** `isPropertyConstant: true`, i.e. C++ constants
in a package binary that no amount of QML makes follow gruvbox. So there
are at least two different "accents" on screen at any moment. Item 4 is
done as scoped; the scope is narrow, and that is a design finding rather
than a bug.

---

## `upgread_UI_UX.md` — commit it, standalone, and link it from here

It is currently untracked. **Recommendation: `git add` it as-is, do not
fold it into this file, and do not delete it.** Reasons, in order:

1. **It is a different question.** This file asks *does the feature
   exist*. That file asks *does this read as one designed system*. Both
   are legitimate and the answers do not interleave — folding 487 lines of
   design-system analysis into a scope document would destroy the one
   thing this file is good at, which is being the record of what was asked
   for and what happened to it.
2. **Its measurements re-verified.** Spot-checked this session:
   `DynamicIslandWindow.qml` is still 4,897 lines; the tree is still 61
   QML/JS files and 28,127 lines; `grep -i corner` still finds no screen
   corners; `dunst` still owns `org.freedesktop.Notifications`. One number
   has moved and in the wrong direction — it counted **six** raw `Loader`s
   in `DynamicIslandWindow.qml` and there are now **seven** (lines 86,
   3871, 3902, 3951, 3969, 3991, 4582), against 20 `PanelLoader`s. Its
   P1-4 finding is not going stale, it is growing.
3. **It found things this file had not**, and they are cheap and real: the
   `IslandTheme.qml` comment that contradicts MIGRATION.md item 4 (it says
   `theme-apply` renames atomically; MIGRATION records that the rename was
   *removed* because `FileView` watches the inode — the code is right, the
   comment is stale), and MIGRATION.md's own headline table still reading
   123 of 291 bindings at 42.3% when `hyprctl binds -j` reports **244**
   live. Both re-confirmed this session. Anyone reading that percentage as
   status gets a wrong picture of the whole port.
4. **Untracked is the one state it must not stay in.** It is the only
   written record of several measurements that cost real time to take —
   the 288 hex literals, the 55 constant `StyleTokens`, the MouseArea/Keys
   split across every panel — and none of them are recoverable from the
   code without redoing the counting.

The one edit it needs: its opening says items 1–5 are "closed except the
polkit prompt". That was true when written, then became an understatement
(the prompt was not absent, it threw), and is now simply stale — the
prompt was removed, so items 1–5 really are closed. A one-line pointer
from there to this file's polkit section is enough.

---

## Dependency order

```
0. Install + keyd          ← nothing works before this
      │
      ├── 4. Theming (Hyprland target)      ← cheapest, do early
      │
      └── 1. Tide-island notch
             ├── 1b. Popups as QML pages    ← the long pole, 121 bindings
             ├── 5. Theme animation          ← needs 1 and 4
             └── 2. hyprglass                ← independent, but conflicts
                                                with blur in looks.conf
3. Scripts — partly done, rest is independent of all the above
```

---

## Open questions — three of the original four are now answered

1. ~~**Screenshots of both videos.**~~ **Answered by other means.** Both
   transcripts were pulled with `yt-dlp` and read in full, and everything
   structural is in DESIGN-SPEC.md. I still cannot see frames, and that is
   now a permanent condition of this project rather than a pending request
   — see "abandoned as a test, not as work" above.
2. ~~Is video 1 actually Tide-island?~~ **Answered: no.** It is an
   unreleased 7,500-line shell with no public repo, taught only through
   the author's paid course. Restyling Tide Island was therefore the only
   available route and remains the right one.
3. ~~hyprglass on windows only, or the bar too?~~ **Answered: windows
   only.** Layers stay off — layer support hooks Hyprland's private render
   pipeline, and an empty `namespaces` means *all* layers rather than none.
4. ~~Keep rofi for launchers?~~ **Answered, and the answer reversed.** The
   recommendation was to keep rofi; the chord is now the island's picker on
   every key but one, for the reason argued under item 3 — and that reason
   turned out not to be the launcher/popup split it was framed as. Rofi
   remains installed and every `dm-*` script works unchanged, which is what
   makes the reversal safe.

### Still needing a decision from you

1. **`phone_screen`'s rofi window** — leave it as a third deliberate
   wizard, or port it? Either is defensible; what is not defensible is
   `binds.conf` claiming there are two.
2. **Notifications: island or dunst?** Both draw every notification right
   now, in two design languages, at the same moment. `upgread_UI_UX.md`
   P0-1 has the proof and Phase 2 has the plan; it is the only choice in
   that plan that throws finished work away whichever way it goes.
3. **Screen corners** — DESIGN-SPEC.md specifies them, nothing draws them,
   and the notch's whole argument is that it is bezel. But they are also
   permanent furniture over every fullscreen video.
4. ~~**The polkit half-ship**~~ — **decided: removed.** The question was
   posed as fifteen lines of stripping versus building
   `PolkitPromptLayer.qml`. That was a false choice; building was never
   fifteen lines short of working, it was a whole D-Bus agent short. See
   item 1.
