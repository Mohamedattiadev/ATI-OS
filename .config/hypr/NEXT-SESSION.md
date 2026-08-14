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

**Both sessions have two bars, and they swap.** This is the big change since
this file was first written and it reframes half of it.

| | qtile (X11) | Hyprland (Wayland) |
|---|---|---|
| `island` | the Tide Island, ported to X11 | the Tide Island |
| `native` | qtile's own `bar.Bar` | the Quickshell topbar |

* `AtiScriptsV1/bar-switch` — `$mod SHIFT P`, both sessions. Owns the one rule
  that must not break: **no path may leave the session without a bar.**
* `AtiScriptsV1/bar-action` — keys follow the bar. Under the island a bind
  calls island IPC; under the topbar it runs the equivalent rofi menu. This is
  not cosmetic: bar-switch STOPS one bar to start the other, and `qs ipc call`
  against a dead config exits 0 having done nothing, so an unrouted island
  bind is a silent dead key.
* `$mod SHIFT Y` — the bar chooser, island page or rofi depending on mode.
* `$mod SHIFT Z` — swaps the topbar's own two forms (28 px chips / 40 px
  normal-user with launchers), qtile's own key for the same thing.
* `~/.cache/bar-mode` (island|native) and `~/.cache/topbar-position`
  (top|bottom). Both read by both sessions.

The topbar lives in `../quickshell/topbar` and is a REIMPLEMENTATION of
qtile's bar — inventory extracted from `qtile/config.py`'s AST, not read off
its comments. `TOPBAR-SPEC.md` is the fidelity record and lists what is
deliberately absent.

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

plus the transient text capsules (`showText`, `showTextWithIcon`,
`showClock`, the OSD `split` state).

So "switching from one popup to another" is a single assignment to
`islandState`. Both loaders are live for the duration of the crossfade, the
capsule morphs from one size to the other, and the content of the new panel
begins its own intro at the same time. **Three animations, three owners, no
coordinator.** That is the shape of the problem.

## What has ALREADY been disproven — do not retry

1. **`LARGE_MORPH_MS` 760 -> 520.** The reasoning was sound (zeta 0.8, the
   envelope is at 3% by 42% of the duration, so the rest is tail). Measured
   with a 50 fps grim burst, island RESTARTED between runs:

       LARGE_MORPH_MS = 760    settle 787 ms
       LARGE_MORPH_MS = 520    settle 801 ms

   Within noise and in the wrong direction. **The shape duration is not what
   the transition is waiting on.** Full note in `qml/common/Motion.js`.

2. **`ControlCenterLayer`'s `sliderIntroDelay`.** Also disproven; see the
   same note.

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

The user asked for "all possibilities". Enumerate and measure, do not spot
check:

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
  workspace — `hyprctl workspaces -j` says which are free. A capture that
  includes the terminal driving the test measures the terminal.
* **`.pragma library` JS is cached.** Editing `Motion.js` or `Metrics.js`
  and reloading does NOTHING. Restart the island:
  `pkill -x quickshell; setsid -f ~/.config/hypr/scripts/island.sh`
* **A failed reload keeps the OLD BUILD running** and writes no new
  `Configuration Loaded` line, so it is indistinguishable from a watcher
  that did not fire. Grep the log for `Failed to load configuration` too.
  This cost most of a session; the most common cause is `Property value set
  multiple times` from adding a property a block already sets.

---


---

# ALSO OPEN

Ordered by how much they are worth.

* **The rest of the motion matrix.** See above — the picker case is fixed, the
  other content-sized panels are not measured.
* **The 12 unchecked picker menus** against their rofi originals: documents,
  man, notes, clipboard, confedit, spellcheck, translate, pass, todo, shared,
  youtube, hub. The record menu is DONE — it grew GIF back and its rows were
  re-checked against a wf-recorder that now exists.
* **Live preview in the settings app** for the cheap numeric keys (sizes,
  opacity, position). The one Phase 8 item never built.
* **`hintium_mode_chip`** on both topbar forms. NOT work that was skipped:
  Hintium is X11-native and `binds.conf` records it as BLOCKED, so there is no
  mode for the chip to show. It is here so nobody re-adds it as an omission.
* **Tooltips on the bottom bar's readouts.** The launchers have them; the CPU
  and memory readouts there do not.
* **Scratchpads on a second monitor** — never tested. The monitor-relative
  x/y logic is verified-by-history only.
* **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
  ~50 ms before any animation starts. Worth measuring inside the motion task.
* **`islandShowWorkspaceOnAutoHide`** is an inert row — present in both
  clients, no reader anywhere (packaged backend is 1.0.34, the key is
  upstream's from 1.0.35). Goes live on a package upgrade. Do NOT "fix" it
  via ForkConfig; see the audit for the collision that causes.
* **What killed the two socket listeners** was never recovered. They
  reconnect on a dropped read now, but a `kill` still ends them silently.
* **`onedark` and `palenight`** are the only palettes under AAA for body text
  (6.57:1 and 6.11:1; AA is 4.5:1). Both are the upstream projects' own
  values, so changing them makes them not-onedark. Recorded, not a defect.

## Now testable, and was not

**Clicks can be synthesised.** `scripts/test/uinput-click.py` creates a uinput
pointer and clicks wherever `hyprctl dispatch movecursor` put the cursor. It
is what proved the window-ring fix. Two traps in its header: a uinput device
takes ~3 s before the compositor binds it (at 1 s every click silently goes
nowhere), and `movecursor` warps WITHOUT emitting motion, so a one-pixel
wiggle is needed before the button or the surface may not have pointer focus.

The onboarding SWIPE is therefore no longer blocked on tooling — it is a
couple of `EV_REL`/`REL_WHEEL` events away.

# RULES — every one of these was paid for, several twice

### Verification

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **Grep that log for `Failed to load configuration`, not only for
  `Configuration Loaded`.** A failed reload keeps the previous build alive
  and writes neither line, so three consecutive "measurements" can all be of
  a stale shell.
- **Compare the log's last "Configuration Loaded" against the file's
  mtime.** `touch shell.qml` if in doubt.
- **A verification step that cannot fail loudly is not one.**
- **`qs ipc call` prints "Function not found" and still EXITS 0.**
- **Toggle IPCs go out of phase. Prefer explicit show/hide when scripting.**
- **A control with no way in from a script is a control whose bugs can only
  be found by the user.** If a feature cannot be driven over IPC, ADD THE
  IPC — that is a fix, not scaffolding.
- **`wtype` reaches CLIENTS but not the compositor's bind layer.** It
  creates and destroys a virtual keyboard, which resets any active submap.
  A synthesised capital arrives with `text` "G" and NO ShiftModifier.
- **If a metric is applied to two things, first run it on two things KNOWN
  to be equal.** `magick X -colorspace Gray -format %[fx:mean]` reads ~30
  points HIGH on a colour image.
- **A test that fails correct code is a bug in the test.**

### Reading the UI

- **Before filing "X is missing": GREP for X and MEASURE the claim.** Four
  deliberate design decisions were filed as defects in a single session.
- **Look at the image, not only the number.** Every luminance check passed
  while mono-light had lavender trees. Only a contact sheet showed it.
- **Private-use characters do not survive into what the model reads back.**
  A grep for a Nerd Font glyph returns an empty-looking string. Dump bytes,
  and write glyphs by codepoint (`String.fromCharCode`, `printf '\uXXXX'`).
- **A screenshot cannot see a gamma change.** Night light needs eyes.
- **Magnify before believing a glyph is absent.**

### Editing

- **Read the WHOLE block before adding a property to it.** "Property value
  set multiple times" fails the entire component, not the one line, and the
  shell then keeps serving the last good build.
- **When you widen an enum or a type, grep every consumer that named its
  values as literals.**
- **One layout, one arithmetic.**
- **A layer that fills its parent is NOT filling the capsule.**
- **`.pragma library` JS is cached. Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **A background listener that connects to a socket ONCE will die silently
  and stay dead.**
- **A "restart" that starts unconditionally is not a restart.** `pkill -x`
  exits 0 only if it signalled something.
- **A fix written up in one file is not a fix applied to the tree.** The
  theme-transition cover bug had its entire post-mortem sitting in
  `ScreenCornersWindow.qml`, with the same numbers, unapplied.

### Safety

- **Never synthesise keystrokes into a settings panel.** Every press writes
  real config.
- **Close a panel that commits on click before leaving it on screen.**
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`, or
  `ps -eo args | awk '/pat/ && !/awk/'`.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
  Note the nested one is HEADLESS here: you can `grim` it via its own
  `WAYLAND_DISPLAY`, but nothing can click into it.
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.**
- **`~/Pictures/Wallpapers` is a git repo with a remote.** Anything written
  there is a change to the user's published repository.
- **The user changes the theme while you work.** Re-read
  `~/.cache/qtile/theme_mode` before a test that depends on it, and restore
  what you found rather than what you assumed.
- **Restore the session when you are done**: theme, workspace, volume, and
  any window you spawned.

### QML in this tree

- **A `Row` derives its height FROM its children.** `height: parent.height` on
  a child inside one is circular and Qt resolves it to ZERO — silently, with
  every binding looking correct. Cost four debugging rounds: the workspaces,
  the tray, the widget-box contents, and the bottom bar's launchers. Give the
  Row an explicit height and take the child's from the component root.
- **Never gate a clipper's `visible` on its own width** when that width comes
  from a Row's `implicitWidth`. The Row counts only VISIBLE children, and a
  child of an invisible parent is not visible — the cycle deadlocks at zero.
- **`Palette` is a built-in QtQuick type.** Naming a singleton that makes every
  colour resolve to `[undefined]` with no error naming the clash.
- **Supplementary-plane Nerd Font glyphs DO render — the variable is the
  FACE.** They work in `Symbols Nerd Font`. Use `String.fromCodePoint`;
  `fromCharCode` takes a UTF-16 code unit and truncates above U+FFFF.
- **A glyph that is not a Nerd Font icon should not be forced through one.**
  U+2716 and U+25B3 are ordinary characters; Ubuntu lacks both, and Qt and
  pango then fall back DIFFERENTLY. Ask `fc-match -s "<font>:charset=XXXX"`
  and name fontconfig's own first choice.
- **The island's input `mask` is not the island's surface.** Anything drawn
  outside the capsule — the window rings — receives no input until a Region
  is added for it. A MouseArea there is dead and looks correct.

### Shell and config

- **`sed -i` replaces the inode**, so Quickshell's file watcher is left on an
  unlinked file and the shell keeps serving the old build. Three "the change
  did nothing" readings came from that. Restart the process, or write in place.
- **This machine's login shell is fish.** `VAR="a b"; $VAR` does NOT
  word-split, so a command built in a variable runs as one argument and fails
  in a way that reads like the command being wrong.
- **`socat` is NOT installed.** A listener written against it starts, takes its
  lock, reads nothing and exits quiet. `workspace-layout.sh` and
  `float-extra.sh` both use a small python socket reader instead.
- **A Hyprland block opened in the middle of another closes it early** and
  silently reparents everything after it. Hyprland DOES report this one —
  `hyprctl configerrors` named `cursor:natural_scroll` — unlike the
  variable-order trap, which stays empty.
- **Test the code path you are shipping, not the one next to it.** The bar
  picker's `--list` was verified and its `--run` was not; `--run` raised on
  every row that mattered. Listing a menu and running it are different code.
