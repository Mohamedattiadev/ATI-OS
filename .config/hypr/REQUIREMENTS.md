# Requested scope — the full list, so nothing gets lost

Standing constraint, applies to everything below:
**do not touch the qtile config.** Both sessions run in parallel.

---

## 0. Install Hyprland

**Status: DONE.** Hyprland 0.56.2 installed and running; keyd is active,
enabled, and confirmed bound to `AT Translated Set 2 keyboard`. See the
"Runtime verification" section of MIGRATION.md for what first login
proved.

One package is still missing and matters for items 1 and 5:

```
sudo pacman -S inter-font
```

Without it every `Inter` / `Inter Display` family in `hyprlock.conf` —
and every one DESIGN-SPEC.md specifies for the notch — silently resolves
to Noto Sans CJK KR. `fc-match "Inter Medium"` confirms it.

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
| Wi-Fi / Bluetooth lists | `$mod P` → `n` / `b` | the island's own control centre, previously unbound |
| Wi-Fi QR | `$mod P` → `SHIFT+S` | `qml/wifi/WifiQrLayer.qml` + `hypr/scripts/wifi-qr.py` |
| Cheatsheets | `$mod SHIFT K` | `qml/cheatsheet/CheatsheetLayer.qml` + `hypr/scripts/cheatsheet.py --sheet-json`. **Was rofi "on purpose" — see below** |
| Wallpaper picker | `$mod SHIFT B` | upstream's, bound |

MIGRATION.md has the per-item evidence for each.

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
| **Polkit password prompt** | **NOT BUILT.** The state, its size cases and its show/clear functions exist; `PolkitPromptLayer.qml` does not, and **nothing registers a polkit agent** — the config key is read into `ForkConfig.polkitAgentEnabled` and no code consumes it. polkit-kde-agent is still the session's agent and is untouched |

The polkit row is the only remainder of item 1. It is also the one with
teeth: a wrong agent means NO password prompt anywhere on the system — no
pkexec, no auth dialog — failing silently until you need one. Whenever it
is built, it must run alongside polkit-kde-agent and be proven before
replacing it.

**A warning that described an imaginary hazard.** The settings row for it
previously read "DANGER. Registers this shell as the session polkit
agent", which was not true of the code at any point — the switch was
inert. It now reads NOT IMPLEMENTED and is disabled. A false warning on a
dead control is worse than no row, because it is the kind of thing a later
reader trusts.

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

With the polkit row that is **five of twelve** controls doing nothing, in a
panel whose whole justification is reaching keys the packaged app cannot.
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
`forkPolkitAgentEnabled` situation above, which is why `scope: "packaged"`
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

### Still open: the island does not yet LOOK like the video

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

Still open under this heading: the chord/mode indicator's appearance, and
per-panel composition against the spec (this pass fixed SIZE, not layout).
The control centre's Sound slider did NOT already cover audio — it is the
volume of the default sink, and qtile's popup was about everything that
is not the default. That table is in MIGRATION.md too.

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

What remains open under this item is the *rule* it states, not a script:
the cheatsheets were moved off rofi and into the island anyway (see
above), so "leave the launcher problems on rofi" now describes the
`dm-*` launcher set and nothing else.

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

## Open questions I need you to answer

1. **Screenshots of both videos**, or a description of the notch's shape,
   what it shows idle vs expanded, and how it animates. I cannot see them.
2. Is video 1 actually Tide-island, or a different shell? If different and
   you can find the repo, that changes the base.
3. hyprglass on **windows only**, or on the notch bar too? Bar glass is the
   fragile path (private Hyprland internals).
4. Keep rofi for launchers, or go all-Quickshell? My recommendation is keep
   rofi — see item 3.
