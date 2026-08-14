# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles`, branch `test`.

`~/.config/hypr` and `~/.config/quickshell` are stow symlinks INTO this
checkout, so editing here edits the running desktop. Quickshell hot-reloads
on save.

**Read before touching anything:** the RULES at the bottom of this file, then
`TOPBAR-SPEC.md`, then the newest audit at the end of `upgread_UI_UX.md`.
Where an audit and an older plan disagree, the audit measured it.

Commit as you go, one concern per commit, reasoning in the message the way the
existing history does. **No Co-Authored-By trailer.**

---

# WHERE THIS DESKTOP IS NOW

**Both sessions have two bars, and they swap.**

| | qtile (X11) | Hyprland (Wayland) |
|---|---|---|
| `island` | the Tide Island, ported to X11 | the Tide Island |
| `native` | qtile's own `bar.Bar` | the Quickshell topbar |

* `AtiScriptsV1/bar-switch` — `$mod SHIFT P`, both sessions. Owns the one rule
  that must not break: **no path may leave the session without a bar.**
* `AtiScriptsV1/bar-action` — keys follow the bar. Under the island a bind
  calls island IPC; under the topbar it runs the equivalent rofi menu, script
  or popup. Its `bar` target is the third shape: keys that address the BAR
  itself and mean different things on each ($alt `, $mod `, $alt Tab).
* `$mod SHIFT Y` — the bar chooser. `$mod SHIFT Z` — the topbar's two forms.
* `~/.cache/bar-mode` (island|native) and `~/.cache/topbar-position`
  (top|bottom). Both read by both sessions.

## FOUR Quickshell processes, not two

This is the change that reframes the rest, and the reason for it is one
measured fact: **Quickshell's QML scanner refuses a module path outside the
config folder, and a symlink does not get past it** — it resolves the link and
rejects the real path. So the topbar's config cannot import anything from the
island's, and the only ways to share are a second COPY or a second ENTRY
POINT. This tree knows what the copy costs (one duplicated palette made every
window border green on twenty-two themes, silently).

Hence, all resolving against `tide-island-fork/` so they see `IslandTheme`:

| entry | what it is | started by |
|---|---|---|
| `tide-island-fork/shell.qml` | the island | `scripts/island.sh` |
| `topbar/` | qtile's bar, reimplemented | `scripts/topbar.sh` |
| `tide-island-fork/treetab.qml` | the TreeTab sidebar | `scripts/topbar.sh` |
| `tide-island-fork/popups.qml` | wallpaper / network / volume, + the theme sweep | `scripts/topbar.sh` |

The last two exist because **they are SESSION surfaces, not bar widgets**. The
island's `shell.qml` hosts them when it is up; when bar-switch stops it to
start the topbar, something else has to. `bar-switch`'s `topbar_stop` stops
them again, or the island would come back to a second sidebar and a second set
of popups holding an exclusive keyboard grab.

`AtiScriptsV1/theme-animate` is the one place that decides who draws a theme
change: island, then the popups shell, then plain `theme-apply`. `theme-toggle`
and `wallpaper-set.sh` both go through it, which is what gives a wallpaper pick
the same circular reveal a theme pick has.

---

# THE ONE TASK, STILL: THE ISLAND'S MOTION

Partly answered, and the answer confirms this file's own lead — **the settle
is the CONTENT, not the shape.** Found in the user's recording, then
instrumented rather than inferred:

    t+1669  picker  h=130     <- one row, because the model was empty
    t+1820  picker  h=242     <- the truth, 151 ms later

`targetHeight` was being handed a height derived from a panel that could not
yet size itself: `pickerLoader.item` EXISTED, but its pageStack was empty
until a `--list` script answered. The loader existing and the panel knowing
its height are not the same thing. Fixed for `picker` by holding
`heightBeforeStateChange` until the page arrives — one aim, no re-aim.

**The same shape of bug is latent in every other content-sized case in that
switch** that falls back to a constant while its loader is empty. `wifi_panel`
and `bluetooth_panel` are the next most likely, being unretained; `display`
and `audio` are `retain: true` and so mostly dodge it. Not changed on
speculation — each needs its own measurement, and the probe that found this
one is three lines:

    onTargetHeightChanged: console.log("PROBE", Date.now(),
        islandContainer.islandState, Math.round(targetHeight))

Then drive the transition over IPC and read the log. The matrix of ten
transition classes further down is still the thing to work through.

## What the island actually is, mechanically

One `PanelWindow` per screen (`DynamicIslandWindow.qml`, ~5,600 lines). Its
shape is `mainCapsule`, a single `Rectangle` whose `displayedWidth`,
`targetHeight` and `targetRadius` are animated by `Behavior`s. Every panel
is a `PanelLoader` filling that rectangle, gated on
`islandContainer.<x>LayerVisible`, which is derived from ONE string:
`islandContainer.islandState`.

There are **24 states**:

    application_launcher audio_panel bluetooth_expanded calculator calendar
    cheatsheet control_center display_panel expanded long_capsule mode_keys
    notification notification_center onboarding picker polkit_prompt
    power_menu settings split sysmon_panel theme_picker wallpaper_picker
    wifi_qr   (+ the resting states: normal, lyrics, custom)

So "switching from one popup to another" is a single assignment to
`islandState`. Both loaders are live for the duration of the crossfade, the
capsule morphs from one size to the other, and the content of the new panel
begins its own intro at the same time. **Three animations, three owners, no
coordinator.** That is the shape of the problem.

## What has ALREADY been disproven — do not retry

1. **`LARGE_MORPH_MS` 760 -> 520.** Measured with a 50 fps grim burst, island
   RESTARTED between runs: 760 -> settle 787 ms, 520 -> settle 801 ms. Within
   noise and in the wrong direction. **The shape duration is not what the
   transition is waiting on.** Full note in `qml/common/Motion.js`.

2. **`ControlCenterLayer`'s `sliderIntroDelay`.** Also disproven; same note.

3. **The out-fade being dead code.** That WAS real and is already fixed —
   `PanelLoader` (`live` vs `active`, plus `retain`) exists because binding
   `Loader.active` to the same boolean as `showCondition` destroyed the item
   before its fade-out could run, in all thirteen panels. Do not
   re-introduce a plain `Loader`.

## The lead that has not been followed

The 760/520 measurement was killed by DIFFERENCING two frames either side of
the tail rather than by measuring the tail's magnitude. That difference
said:

> at +621 ms against +990 ms the whole content block is still shifting ~8 px
> vertically and the brightness slider is still sweeping toward its value.
> Neither is the morph.

**So the settle is the CONTENT, not the shape.** Nobody has yet:

* enumerated which panels move their content after the capsule has arrived,
  and why (a `Column` whose height depends on a `Process` that has not
  answered? a `preferredHeight` that lands a frame late? a `Behavior` on a
  child's `y`?);
* checked whether the capsule reaches its target BEFORE the content is laid
  out, so the content visibly re-flows inside a shape that has already
  stopped — which is exactly what "not smooth" looks like;
* looked at whether `retain: true` panels re-run their intro on every open.

Start there.

## The matrix to actually test

| From | To | Why it is its own case |
|---|---|---|
| rest | panel | the common open; capsule grows from the notch |
| panel | rest | the out-fade path that used to be dead |
| panel A | panel B | both loaders live, capsule morphs between two sizes |
| rest | text | `showText` / submap indicator; a width-only change |
| text | text | one string replacing another, same shape |
| text | panel | a transient interrupted by a real panel |
| panel | text | e.g. a volume OSD over an open control centre |
| rest | OSD (`split`) | the OSD is a different capsule shape entirely |
| panel | notification | notifications outrank; see `blocksTransientSplit` |
| any | overview | `overviewVisible` bypasses most of the state machine |

Sizes differ by up to **857 px** (`long_capsule` 156 -> wallpaper picker
1013), which is why the morph is distance-aware in the first place.

## How to measure this here, and what fails

* **`grim` bursts, PPM not PNG.** ~16 ms per 1366x120 strip, so ~50 fps is
  achievable; PNG encoding drops the sample rate below what you are
  measuring. Frame files named with an elapsed-ms suffix.
* **DIFFERENCE consecutive frames; do not count changed pixels.** A settle
  is "d(prev) reaches its noise floor", not "some pixels changed".
* **The capture region must contain nothing but the island.** Use an empty
  workspace — `hyprctl workspaces -j` says which are free.
* **`.pragma library` JS is cached.** Editing `Motion.js` or `Metrics.js`
  and reloading does NOTHING. Restart the island:
  `pkill -x quickshell; setsid -f ~/.config/hypr/scripts/island.sh`
* **A failed reload keeps the OLD BUILD running.** Grep the log for
  `Failed to load configuration` too — and see the RULES, because it can
  also stop the watcher.

---

# REPORTED AND NOT YET FIXED

Everything here came from the user in one pass at the end of the last
session. Where a cause is written down it was MEASURED during that session,
not guessed — start from the measurement, not from the symptom.

### Dead or missing controls

* ~~**The Wi-Fi QR chip does nothing.**~~ **FIXED.** The diagnosis was
  right and both callers had it: the chip in `topbar/shell.qml` ran the
  script directly and so did `bar-action`'s `toggleWifiQr`, and the script
  is a DATA PRODUCER — it writes `~/.cache/hypr/wifi-qr.png` and prints the
  path. `qml/popups/WifiQrPopup.qml` is the viewer, both callers go through
  `popups wifiqr`, and it was driven by IPC and by a synthesised click on
  the chip.
* **`$alt 5` (calculator) and `$alt 4` (display) do nothing under the
  topbar.** Both are bound and both reach `bar-action`; the NATIVE branch is
  what fails, and the display one has a precise cause worth fixing first:

      $ python3 scripts/display-ctl.py --menu
      {"ok": false, "status": "unknown subcommand --menu"}   # and EXITS 0

  bar-action's `--menu || nwg-displays` fallback therefore never fires, and
  `nwg-displays` is not installed either. The calculator's `rofi -show calc`
  needs the rofi-calc plugin, which is not installed — `/usr/lib/rofi/` is
  empty — so it falls through to `kitty -e qalc`, a terminal rather than the
  panel that was asked for. Both should become island-style popups.
* **A Bluetooth popup is missing.** The wallpaper, network and volume ones
  are built; `popups/BluetoothPopup.py` is the fourth and its chord is in
  config.py under Rofi-Mode `b` (j k g G move, ↵ connect, d disconnect,
  x remove, t power, r scan, c cancel, / search).
* **qdrop is bound but is not the island's.** `$alt SHIFT D` runs the GTK
  shelf through XWayland, which works, and the user wants it to behave and
  LOOK like the island when the island is up — same UI/UX, same surface
  language. Two sub-problems, and the second is the reported bug: while
  dragging, **the file is not under the cursor** — the drag icon is offset.

### Behaviour that differs from qtile

* **Passthrough is not qtile's.** Hyprland's is an empty submap with one
  exit key (`submaps.conf`, `$mod F12`). qtile's `_enable_passthrough` does
  three more things: it switches BAR_MODE to the bottom bar and re-applies
  it, it notifies "PASSTHROUGH MODE", and Escape does not leave — it enters
  **PASSTHROUGH-CONFIRM**, a second chord asking `y , n , ESC`, which is why
  that label exists in CHORD_CHIP_LABELS and why it is coloured urgent.
  Read `config.py:669` onwards and port the whole shape.
* **Media mode changes volume and brightness with no feedback.** The submap
  binds `wpctl set-volume` and `brightnessctl set` DIRECTLY — so do the
  hardware keys — and nothing raises an OSD. Under the island the OSD comes
  from the island watching Pipewire itself; under the topbar there is none at
  all. qtile went through `scripts/volume_control.py` and
  `brightness_control.py`, which notify. Decide where the OSD lives for the
  topbar (the popups shell is the resident process that could own it) rather
  than adding a `notify-send` to six binds.

### Glitches, each with a shape to measure

* **Every chip is SLOW.** Reported on the language chip — clicking through
  us -> ara -> tr lags visibly — and the user says the others feel the same.
  Two candidates and they are separable: the chip's own poll interval (the
  keyboard chip re-reads `hyprctl devices` every 3 s through a python
  one-liner, so a click updates the GLYPH up to 3 s later even though the
  layout changed instantly), and process-spawn latency per click. Measure
  the gap between the dispatch and the repaint before changing either.
* **The island's height twitch — MEASURED, and it is not where the report
  puts it.** The probe was added, the island driven, and closing rofi
  produces **no `targetHeight` change at all**. What does twitch is the
  mode-keys HUD on the way IN, and only the FIRST time a given chord is
  opened in a session:

      first open of the rofi chord ($mod P)
          t+0     mode_keys  45     <- no rows yet
          t+87    mode_keys  275    <- the truth, 87 ms later
      second open of the same chord
          t+0     mode_keys  275    <- one move, no re-aim

  So it is the same class as the picker bug, and `ModeKeysLayer` already
  carries the fix: `pendingHeight` remembers each mode's height and hands it
  back while the `cheatsheet.py` fetch is in flight. Its own note accepts the
  remainder — "one open per mode per session, rather than every open" — and
  that remaining open is what gets reported. The teardown was checked too and
  is clean: 275 -> 45 -> 35 inside 3 ms, far below anything visible.

  **The obvious fix crashed the island, so it is NOT in the tree.** Persisting
  `modeKeysHeights` to `~/.cache/tide-island/mode-key-heights.json` with a
  `FileView` + `JsonAdapter` (the pattern `ApplicationLauncherLayer` uses for
  favourites) loaded cleanly — "Configuration Loaded", no QML error — and then
  the process DIED, last log line `QProcess: Destroyed while process ("pactl")
  is still running`. With `bar-mode` on island that leaves the desktop with no
  bar, which is the one rule bar-switch exists to protect. Reverted.
  If it is retried: suspect the free-form `property var heights: ({})` on the
  JsonAdapter — the launcher's precedent stores a LIST, not a map — and test
  it with the topbar as the active bar so a crash cannot take the only bar
  with it.
* **The topbar's theme sweep freezes rofi for ~0.4 s.** Picking a theme from
  the rofi picker makes the rofi window itself freeze and glitch before the
  new palette arrives. Note what the overlay does: it screenshots, freezes,
  runs theme-apply behind the frozen frame, then reveals — and rofi is still
  on screen when the shot is taken, so the frozen frame contains a rofi that
  has already exited. Look at whether `theme-toggle` should close rofi and
  settle BEFORE calling `theme-animate`.

### The bar's fidelity, and where the divergences actually live

Reported mid-session with a screenshot — "this part not behaving like the
real qtile, and the workspace a bit weird" — against the TaskList and the
GroupBox. Three defects came out of it and **not one of them was in
`config.py`**. Everything config.py sets was already reproduced. They were
all in the INSTALLED libqtile, which is the rule this tree already has and
had only ever applied to `w_volume`:

* `TaskList` carries five markup strings and `parse_text=parse_task_name`.
  The plates and the parser were both missing, which is why titles read
  `✳ Claude Code` and `No file - mpv`.
* `GroupBox.box_width` reserves `borderwidth*2` **even in `highlight_method
  ='text'`**, where no border is ever painted — 'text' passes
  `bordercolor=None`, which zeroes the border at DRAW time only. And
  `spacing` defaults to `None`, which `_configure()` resolves to `margin_x`,
  not to zero. Together that was 56 px of a 136 px widget.
* Both widgets' Button callbacks come from `__init__`, not from the config:
  clicking the focused TASK minimizes it, clicking the current GROUP goes
  back, and the GroupBox takes the wheel.

**The mouse-callback audit is now COMPLETE and clean.** Every widget
constructed in `config.py` was walked — including the ones built as
`chip(ewidget.X, …)`, where the class is a POSITIONAL argument and a scan
keyed on `Call.func` misses it, which is how a first pass here found only
two of four. `add_callbacks` merges with the user's winning per KEY, so a
config that sets some buttons still inherits the rest. The result:

    GroupBox   Button1 select_group, Button4 prev, Button5 next   FIXED
    TaskList   Button1 select_window                              FIXED
    Volume     Button1 mute, Button3 run_app, Button4/5 vol       already done
    CheckUpdates / KeyboardLayout / Mpris2                        fully overridden

Nothing else on either bar has a live default. Re-run the walk if a widget
is added.

TaskList's geometry was checked the same way and agrees:
`text + 2*(padding_side + borderwidth) + (icon_size + padding_side)` is
`text + 37` in both, with the markup's two spaces counted as text.

### The standing requirement

**Every function and every case, in both bars, driven rather than read.**
Both halves of the input synthesis exist now (`scripts/test/uinput-key.py`,
`uinput-click.py` with `scroll`), every chip has an IPC or a script entry
point, and `RMENU` is overridable in the rofi scripts. There is no control
left in this desktop that can only be tested by hand — so the next pass
should be a systematic sweep of the topbar's chips, the island's 24 states
and the ten transition classes, not a spot check.

# ALSO OPEN

Ordered by how much they are worth.

* **The rest of the motion matrix.** See above — the picker case is fixed, the
  other content-sized panels are not measured.
* **Something leaks `pactl subscribe`, and it broke the audio stack.** Found
  live: 62 orphaned `pactl subscribe` processes, PPID 1, dating back two days,
  had exhausted pipewire-pulse's client limit — its journal says "too many
  client application connections: Connection refused" and EVERY pulse client
  was failing, including qtile's own AudioPopup. Killing the orphans fixed it
  immediately. **The source was not found**: nothing in this repo spawns that
  command, and it is not in `~/.local/bin`, `AtiScriptsV1` or `/usr/local/bin`
  either. Next time it recurs, catch it with the parent alive
  (`ps -eo pid,ppid,lstart,args`) rather than after it reparents.
* **The 12 unchecked picker menus** against their rofi originals: documents,
  man, notes, clipboard, confedit, spellcheck, translate, pass, todo, shared,
  youtube, hub. The record menu is DONE.
* **Live preview in the settings app** for the cheap numeric keys.
* **`hintium_mode_chip`** on both topbar forms. NOT skipped work: Hintium is
  X11-native and `binds.conf` records it as BLOCKED, so there is no mode for
  the chip to show. Here so nobody re-adds it as an omission.
* **The volume popup's three sub-views** — `p` profiles, `P` ports, `C` cards.
  Deliberately absent and NOT advertised in its hint bar; a key chip naming a
  view that does not open is worse than a shorter bar. AudioPopup.py has them
  in 2,241 lines and pavucontrol has them too.
* **Tooltips on the bottom bar's readouts.** The launchers have them; CPU and
  memory do not.
* **Scratchpads on a second monitor** — still never tested. The
  monitor-relative x/y logic in `scratchpad.sh` is verified-by-history only.
  The BARS and POPUPS are no longer in that category, though — see below.

### Two monitors and fractional scale — TESTED, not inferred

`hyprctl output create headless` makes a second output on demand, which is
what this tree has been missing to test any of this. Measured with
HEADLESS-1 1920x1080 beside eDP-1, then again at `scale 1.5`:

    topbar          one bar per screen, 1366x38 and 1920x38
                    at scale 1.5: 1280x38 — 1920/1.5 logical px, correct,
                    because a layer surface is sized in LOGICAL pixels and
                    the compositor scales it
    reserved zone   [0,38,0,0] on both screens
    popups          follow the FOCUSED monitor and centre exactly on it:
                    HEADLESS-1 -> 1366 + (1920-420)/2 = 2116
                    eDP-1      -> 2646 + (1366-940)/2 = 2859

The island, treetab and the theme overlay are all `Variants` over
`Quickshell.screens` already, so they get the same per-screen treatment the
topbar was proved to have.

**Hyprland re-lays-out the other monitors when you set one's geometry.**
eDP-1 moved from x=0 to x=2646 when HEADLESS-1 was given a scale, and a
popup at x=2859 looked misplaced until the monitor list was re-read. Read
the positions back before judging any placement on a multi-monitor session.

`ui_scale` is a separate knob from the compositor's per-monitor `scale` and
stays that way: it is qtile's `_s()` factor, per MACHINE, applied equally on
every screen. Per-monitor DPI is the compositor's job and it does it.
* **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
  ~50 ms before any animation starts.
* **`islandShowWorkspaceOnAutoHide`** is an inert row — present in both
  clients, no reader anywhere (packaged backend is 1.0.34, the key is
  upstream's from 1.0.35). Do NOT "fix" it via ForkConfig; see the audit.
* **qtile with its OWN bar gets no theme sweep.** It is the one combination
  with no Quickshell process at all, so `theme-animate` falls through to
  `theme-apply`. Fixable only by giving that session a shell to draw it.
* **`CHORD_CHIP_LABELS`' lang and passthrough entries have lost their
  glyphs** — in qtile's config.py, not here. Checked at the byte level: they
  begin with three plain spaces where the others begin with a Nerd Font
  codepoint. The topbar reproduces what renders. Fixing it means editing
  config.py and both chips together.

## Input synthesis: both halves exist now

* `scripts/test/uinput-click.py` — clicks, and `scroll up|down [count]`.
* `scripts/test/uinput-key.py` — key combinations, named as `hyprctl binds`
  names them, with `--hold` for observing a submap.

Three traps, all in their headers: a uinput device takes ~3 s before the
compositor binds it; `movecursor` warps WITHOUT motion, so a one-pixel wiggle
is needed before a click; and destroying the device can reset an active
submap.

# RULES — every one of these was paid for, several twice

### Verification

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **Grep that log for `Failed to load configuration`, not only for
  `Configuration Loaded`.**
- **A failed load can also stop the FILE WATCHER.** Not just the old build
  staying up: after `TreeTabSidebarWayland is not a type`, every later edit
  produced no reload line at all and the shell served the stale build until
  the process was restarted. If edits stop having any effect, restart before
  believing anything you measure.
- **Compare the log's last "Configuration Loaded" against the file's
  mtime.** Two "measurements" this session were of a stale build — the
  triangle read 6x5 after being fixed, and the layout chip appeared not to
  reserve its width. `touch shell.qml` and re-read.
- **A verification step that cannot fail loudly is not one.**
- **`qs ipc call` prints "Function not found" and still EXITS 0.** With NO
  INSTANCE it exits 255, which is what makes a fallthrough chain work.
- **Toggle IPCs go out of phase. Prefer explicit show/hide when scripting.**
- **A control with no way in from a script is a control whose bugs can only
  be found by the user.** If a feature cannot be driven, ADD THE WAY IN —
  the IPC, or an overridable `RMENU`. That is a fix, not scaffolding.
- **`wtype` reaches CLIENTS but not the compositor's bind layer.** Use
  `uinput-key.py`.
- **If a metric is applied to two things, first run it on two things KNOWN
  to be equal.**
- **A test that fails correct code is a bug in the test.**

### Reading the UI

- **Before filing "X is missing": GREP for X and MEASURE the claim.**
- **A qtile WIDGET can carry behaviour its CONFIG never mentions.** `w_volume`
  sets no mouse_callbacks and was written up here as inert; `Volume.__init__`
  adds mute/run_app/increase/decrease itself, so an empty mouse_callbacks
  means "keep the defaults". Read the installed libqtile, not only config.py.
  **This is the general case, not a Volume quirk** — it went on to account for
  every TaskList and GroupBox defect reported this session. A widget's
  APPEARANCE comes from there too: `GroupBox.box_width` reserves
  `borderwidth*2` in a highlight mode that never draws a border, and
  `spacing=None` resolves to `margin_x`. Ask the class, not the config.
- **`add_callbacks` merges per KEY**, user over default, so a widget whose
  config sets Button1 still has the library's Button4 and Button5.
- **Walk `chip(ewidget.X, …)` too.** Most of the top bar is built by a helper
  that takes the widget class POSITIONALLY, so an AST scan keyed on the call's
  `func` sees none of them. A first pass here reported two widgets with live
  defaults where there were four.
- **Look at the image, not only the number.**
- **Private-use characters do not survive into what the model reads back.**
  Dump bytes, and write glyphs by codepoint.
- **A screenshot cannot see a gamma change.** Night light needs eyes.
- **Magnify before believing a glyph is absent.**

### Editing

- **Read the WHOLE block before adding a property to it.** "Property value
  set multiple times" fails the entire component.
- **A binding in a base component is REPLACED by an assignment at the call
  site.** So a property the caller already sets cannot also be derived in the
  base file — the derivation is silently dead. The widget box's two font
  sizes had to move to the one call site that needed them.
- **When you widen an enum or a type, grep every consumer that named its
  values as literals.**
- **One layout, one arithmetic.**
- **A layer that fills its parent is NOT filling the capsule.**
- **`.pragma library` JS is cached. Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **A background listener that connects to a socket ONCE will die silently.**
- **A "restart" that starts unconditionally is not a restart.**
- **A fix written up in one file is not a fix applied to the tree.**

### Safety

- **Never synthesise keystrokes into a settings panel.**
- **Close a panel that commits on click before leaving it on screen.**
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`, or
  `ps -eo args | awk '/pat/ && !/awk/'`.
- **A process matcher must compare an ARGUMENT, not a substring.** `$0 ~
  ("quickshell -p " dir)` was correct until two entry points appeared INSIDE
  that directory; then `bar-switch island` saw popups.qml, decided the island
  was up, stopped the topbar and left the desktop with NO BAR. Walk the
  fields, find `-p`, compare the next one for equality — which also fixes the
  second half, that a path is not a regex.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.**
- **`~/Pictures/Wallpapers` is a git repo with a remote.**
- **The user changes the theme while you work.** Re-read
  `~/.cache/qtile/theme_mode` before a test that depends on it, and restore
  what you found. A theme sweep can be tested by applying the theme that is
  ALREADY ON — the animation runs and the palette does not move.
- **Restore the session when you are done**: theme, workspace, volume,
  layout, cursor position, and any daemon you started.

### QML in this tree

- **A `Row` derives its height FROM its children.** `height: parent.height` on
  a child inside one is circular and Qt resolves it to ZERO — silently.
- **Never gate a clipper's `visible` on its own width** when that width comes
  from a Row's `implicitWidth`.
- **Guard on the OBJECT, not on the flag that says it exists.** Two bindings
  over one model are re-evaluated in an order Qt does not promise, so
  `exists` can be true while `row` is still null — a TypeError per row per
  refresh, in the log only, with the list looking correct.
- **A `PanelWindow` has no `opacity`.** Assigning one is a LOAD ERROR, not a
  no-op. Animate the content instead.
- **`signal closed()` collides with `QQuickWindow`'s own** and is dropped with
  a warning, so the handler never runs. Same class as `Palette`: check the
  base type's members before naming a signal or a singleton.
- **`Palette` is a built-in QtQuick type.**
- **Supplementary-plane Nerd Font glyphs DO render — the variable is the
  FACE.** Use `String.fromCodePoint`.
- **A glyph that is not a Nerd Font icon should not be forced through one.**
- **The island's input `mask` is not the island's surface.**

### Fonts, which are their own category now

- **A pango font string is a DESCRIPTION; a Qt `font.family` is a FAMILY.**
  `"Ubuntu Bold"` works in qtile and resolves to **Noto Sans CJK KR** in Qt.
  `fc-match` every family before believing it, and split the style out.
- **Do not ask for bold on a face that has no bold cut** — Qt synthesises one
  and draws a heavier glyph than pango does.
- **A qtile `fontsize` is PIXELS** (`set_absolute_size`, checked in the
  installed libqtile) and maps onto `font.pixelSize` directly. **A pango
  markup `size=` is POINTS.** The tray triangle's `size="15500"` is 20 px
  here, not 15 and not 11 — measured with `pango-view` and a trim to the ink,
  which is the only way to settle it.

### Shell, config and the two display servers

- **`sed -i` replaces the inode**, so a file watcher is left on an unlinked
  file. Restart the process, or write in place.
- **This machine's login shell is fish.** A command built in a variable runs
  as one argument.
- **`socat` is NOT installed.**
- **A Hyprland block opened in the middle of another closes it early.**
- **`hyprctl keyword` is not a config value, and `hyprctl reload` undoes it.**
  Every option the config does not DECLARE goes back to Hyprland's default on
  reload, so an option a script only ever sets at runtime silently reverts.
  `getoption -j` says which is which: `"set": true` is ours, `"set": false` is
  Hyprland's. This is what put a groupbar over every window in Max after a
  reload — `group:groupbar:enabled` was set by layout-cycle.sh and declared
  nowhere. Audited the rest: `general:layout`, `master:mfact` and
  `general:col` are all declared.
- **Test the code path you are shipping, not the one next to it.**
- **AN X11 TOOL UNDER HYPRLAND SUCCEEDS AND RETURNS BLACK.** maim, xrandr,
  xdotool and friends all answer through XWayland — they do not fail, they
  report the XWayland root window, which no Wayland client draws into. Every
  screenshot from the rofi menu was a valid PNG of nothing, with a
  "Screenshot Saved" notification. Split on `WAYLAND_DISPLAY`, not on
  `XDG_SESSION_TYPE`, which the display manager sets and which is absent for
  a session started any other way.
- **The three screenshot geometry formats do not agree.** maim `-g` takes
  `WxH+X+Y`, grim `-g` takes `<x>,<y> <w>x<h>`, and slurp PRINTS grim's. A
  mismatch reads as "the region option is broken" while fullscreen works.
- **A GTK app that positions itself needs `GDK_BACKEND=x11` here.** Wayland
  does not let a client place its own toplevel; XWayland does, and Hyprland
  honours it. That is all qdrop needed.
- **Hyprland gives a NAMED workspace a negative id** (S is -1337), so a
  `id > 0` test drops it along with the scratchpads — filter on the
  `special:` name prefix instead. And `workspace -1337` is not that
  workspace: a SIGNED number is a RELATIVE move. Use `workspace name:S`.
- **A layer surface is placed at y=0, over the bar's strip.** To line one up
  with the tiled windows, inset it by `reserved[1]` from `hyprctl monitors`
  plus `general:gaps_out` — read live, because the bar's zone changes with
  the bar and gaps_out is a setting.
