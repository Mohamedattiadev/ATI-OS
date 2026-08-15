# Hyprland

The Wayland session. qtile/X11 remains the default and is untouched; both
are selectable at login and share theme state, so this directory is
additive rather than a replacement.

| | |
|---|---|
| Compositor | Hyprland 0.56.2 |
| Shell | Quickshell — `~/.config/quickshell/tide-island-fork` |
| Wallpaper | `awww` (the daemon; `swww` is its old name) |
| Idle / lock | `hypridle` / `hyprlock` — **nothing on a timer**, see below |
| Night light | `hyprsunset` |
| Notifications | served by the shell itself, **not** dunst |

## The files here

| File | What it holds |
|---|---|
| `hyprland.conf` | the root config; sources everything below |
| `binds.conf` | every keybinding and submap |
| `submaps.conf` | the chord modes (`media`, `cheatsheet`, …) |
| `rules.conf` | window rules, including the `workspace` home rules |
| `monitors.conf` | outputs |
| `input.conf` | keyboard/touchpad, and the keyd note about this laptop's dead Alt |
| `looks.conf` | gaps, borders, blur, animations |
| `colors.conf` | written by `theme-apply`; do not hand-edit |
| `autostart.conf` | `exec-once` |
| `hypridle.conf`, `hyprlock.conf` | idle and lock |
| `hyprglass.conf` | the liquid-glass plugin; `videoglass` is the active preset |
| `scripts/` | everything the binds call |

Scripts worth knowing by name:

| Script | What it does |
|---|---|
| `border-focus.sh` | drops window borders while an island panel is open |
| `lock-player.sh` | what is playing, for hyprlock's now-playing card |
| `cheatsheet.py` | every sheet, generated from `hyprctl binds` where it can be |
| `island-picker.py` | the generic picker's menus, including the PDF toolkit |
| `theme-list.sh` | the palette list, parsed out of `theme-apply` |
| `layout-notify.sh` | qtile's non-English layout warning, on the shared id 9001 |
| `reap-island-helpers.sh` | kills the packaged backend's orphaned watcher processes |
| `qdrop-shake.py` | shake a dragged file to open the drop shelf — see below |

And the test tools, which are how anything here gets *driven* rather than
read — `scripts/test/`:

| Tool | What it drives |
|---|---|
| `sweep-island.py` | all 24 island states and the ten transition classes |
| `sweep-topbar.py` | every chip on the topbar |
| `uinput-key.py` | key combinations, named as `hyprctl binds` names them |
| `uinput-click.py` | clicks, `scroll up\|down`, and `hover <seconds>` |
| `uinput-shake.py` | a button-1 drag with a shake in it, the three shapes a gesture must refuse, and `to <x1> <y1> <x2> <y2>` |
| `dnd-peer.py` | a window offering one URI that prints what is dropped on it — the far end of a drag test |
| `startup-notifications.sh` | every `Notify` on the bus for the first N s of a session |

`uinput-click.py hover` exists because a tooltip could not be tested at all:
it needs a real motion event over the chip and then the pointer to *stay*
there past the bar's 450 ms delay, and `hyprctl dispatch movecursor` warps
without emitting motion.

Companion documents:

* **`MIGRATION.md`** — the qtile→Hyprland record: what every qtile feature
  became, and what deliberately has no equivalent.
* **`REQUIREMENTS.md`** — the requested scope and each item's status.
* **`upgread_UI_UX.md`** — the audit trail. **Append to it; do not rewrite
  it.** Where it and an older plan disagree, the audit measured it.
* **`DESIGN-SPEC.md`** — the visual language the shell is held to.

## Everything here is a stow symlink

`~/.config/hypr` and `~/.config/quickshell` are symlinks into
`~/.dotfiles`. Editing either path edits the running desktop, and
Quickshell hot-reloads on save. There is no build step and no deploy step;
there is also no undo.

## How a theme change works

`theme-apply <theme>` is shared with the qtile session and is the only
thing that should write `colors.conf`.

1. The shell's `ThemeTransitionWindow` covers the screen with a frozen
   frame the moment a change starts.
2. `theme-apply` rewrites every consumer's colours, then sets the theme's
   wallpaper with `theme-wallpaper apply <theme> instant`.
3. It prints `THEME_APPLY_VISIBLE_DONE`.
4. The shell sweeps the cover away, revealing the new palette **and** the
   new wallpaper together.
5. `theme-apply` keeps running behind a live desktop — repacking the
   Chromium theme, restarting browsers, rebuilding the initramfs. None of
   that repaints anything on screen, which is why the marker exists.

The marker is what separates "the visible part is done" from "the script
has exited". Gating the reveal on the exit once cost five seconds of dead
screen; see the header of `ThemeTransitionWindow.qml`, which has the
measurements.

## Wallpapers

`theme-wallpaper` resolves a theme to an image in four layers:

1. **override** — `~/.cache/qtile/theme-walls.json`. Picking a wallpaper
   while a theme is active *rebinds* that theme to it.
2. **set** — `~/Pictures/Wallpapers/themed/<theme>/*`, drawn at random on
   every theme change, never repeating the previous pick. **25 images per
   theme, all 21 themes.** Built by `theme-wallpaper-fetch`, which scores
   every candidate in CIELAB rather than trusting the folder it came in:
   a directory called "Nord" is not a nord wallpaper.

   Two themes cannot be served by selection and are generated instead —
   `mono-light` entirely (its background is `#ffffff` and zero of 3,875
   candidates score near it) and 7 of `matrix`'s 25. Lowering a threshold
   to fill a set would defeat the scoring.
3. **single** — `~/Pictures/Wallpapers/themed/<theme>.jpg`.
4. **nothing** — leave the wallpaper alone. A theme change must never
   blank the desktop.

The override deliberately beats the set: otherwise a deliberate pick would
survive only until the next theme change. `theme-wallpaper forget <theme>`
hands a theme back to its set.

## The panels, and the keys that open them

Every one of these is a state of the island, not a separate window, and
every one is drivable over IPC — `qs -p ~/.config/quickshell/tide-island-fork
ipc call tide <fn>`. A control with no way in from a script is a control
whose bugs only you can find.

| Key | Panel | IPC |
|---|---|---|
| `$mod SHIFT /` | docs, keymaps, troubleshooting — opens on DOCS, Tab cycles six sheets | `showCheatsheet docs` |
| `$mod SHIFT K` | the cheatsheet chord — hypr / vim / fish / island | `showCheatsheet <which>` |
| `$mod SHIFT I` | the tour. Swipe sideways for pages, up to dismiss | `showOnboarding 0` |
| `$mod SHIFT Q` | power menu, with a search field and a y/n confirmation | `togglePowerMenu` |
| `$alt 5` | calculator — drives `qalc`, live results, six-row tape | `toggleCalculator` |
| `$alt 6` / `$alt 7` | calendar / settings | `toggleCalendar`, `toggleSettings` |
| `$mod P` then `c` / `w` | theme picker / wallpaper picker | `toggleThemePicker`, `toggleWallpaperPicker` |
| `$mod P` then `v` | the PDF toolkit | `showPicker ilovepdf` |

**Search fields.** The power menu, theme picker, wallpaper picker,
cheatsheet, launcher and generic picker all use
`qml/common/PanelSearchField.qml`: always visible, always focused, letters
type. That last part is the trade — hjkl and `q` used to navigate and now
cannot, because they are letters you type into a query. Arrows and
Ctrl+HJKL/NP move instead, which is rofi's own resolution of the same
problem.

**While any panel is open** the island takes a 1 px accent ring and
`scripts/border-focus.sh` drops every window border to its inactive
colour, so there is exactly one accent on screen. It restores at shell
startup, so a crash with a panel open cannot leave the borders dimmed.

## The resting capsule, and what each mark on it means

The island at rest is a clock with four optional marks around it, left to
right:

| | Mark | There when |
|---|---|---|
| 1 | the keyboard language, `AR` / `TR` / `GE` | the layout is **not** English — and never otherwise, which is the whole point of it |
| 2 | the window-layout glyph | `layout-cycle.sh` has run once this session |
| 3 | the clock | always |
| 4 | the workspace digit | always |
| 5 | the 4-bar EQ | something is actually playing |

The capsule grows by a fixed allowance for each, so the shape changes when a
mark appears and never when its *content* changes — a two-digit workspace and
a switch from `AR` to `TR` both land inside a slot that was already reserved.
Ordering on the left is by volatility: the window layout changes on every
`$mod Tab`, the keyboard layout only when you start typing another language,
so the rarer one takes the outer slot and nothing shuffles when it appears.

## Idle: nothing happens on a timer

`hypridle` runs and has **no listeners**. The screen does not dim, does not
lock and does not switch off however long the machine sits — asked for
directly, and stated here because it is a security posture, not a default.

What still works, all of it in `hypridle.conf`'s `general` block:

| | |
|---|---|
| `$mod SHIFT X` | lock now |
| `loginctl lock-session` | the same, from anywhere |
| suspend | still locks first (`before_sleep_cmd`), and turns the display back on after |

The three listeners that were there — dim at 300 s, lock at 600, DPMS off at
900 — are kept in the file as a comment block, so putting any of them back is
a paste rather than a rediscovery.

## Two bars, and swapping between them

`$mod SHIFT P` — the same key in both sessions — swaps which bar the
desktop is wearing. `AtiScriptsV1/bar-switch` owns it, and the choice is
saved to `~/.cache/bar-mode`, which **both** sessions read at startup. Pick
a bar in Hyprland, log into qtile, and you are still on the bar you picked.

|  | qtile | Hyprland |
|---|---|---|
| `native` | qtile's own `bar.Bar` | the Quickshell topbar, `../quickshell/topbar` |
| `island` | the Tide Island, on X11 | the Tide Island |

```
bar-switch status      # mode, session, whether the island is up
bar-switch island      # or: native, toggle
```

Both directions work in both sessions. `bar-switch` still refuses rather
than leaving you bar-less: the incoming bar comes up and is checked before
the outgoing one is allowed to go away, and on Hyprland `native` refuses
outright if the topbar is not installed — which is the state of a machine
where stow has not run yet.

The topbar is a **reimplementation** of qtile's, not a port: qtile's bar is
part of qtile and cannot run under another compositor. Its inventory was
extracted from `qtile/config.py`'s AST rather than read off its comments,
and it uses qtile's own glyphs, chip decoration and palette — see
`TOPBAR-SPEC.md`, which also records what is deliberately left out and the
three Qt layout traps the build hit.

**The island under qtile is a real port, not a second copy.** It took one
change: five windows carried `WlrLayershell.*` attached properties, which do
not exist off Wayland, and an attached object that cannot be created fails
the *whole component* — so under X11 the island rendered nothing while the
log cheerfully said `Configuration Loaded`. Each is now a backend-neutral
base plus a thin per-backend wrapper. See
`quickshell/tide-island-fork/qml/common/BackendSurface.md`, which also lists
what X11 genuinely does not have (two stacking layers instead of four, no
exclusive keyboard grab, no layer-surface namespace, and no workspaces,
overview, window ring or TreeTab — all of those are Hyprland feeds).

## Troubleshooting

Every failure this desktop has actually produced has been a **silent**
one — a font that fell back, a daemon that was not running, a socket
listener that had exited, a config key nothing reads. So each entry below
is a symptom and the command that *proves* the cause, rather than a
description.

### The shell reloaded but nothing changed

A config that reloads cleanly is not a config that works.

```sh
# Find the LIVE instance. Note it registers under the ~/.config path,
# not the ~/.dotfiles one, and `qs ipc` EXITS 0 when it finds nothing.
ls -t $XDG_RUNTIME_DIR/quickshell/by-id/ | head -1
tail -20 $XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log
```

Compare the log's last `Configuration Loaded` against the file's mtime. A
`shell.qml` edit has landed *after* the reload its own earlier edit
triggered, and a measurement "proving the change did nothing" was reading
the old shell. `touch shell.qml` if in doubt.

**And grep for `Failed to load configuration`, not just for the success
line.** A reload that ERRORS leaves the previous build running and writes
no new `Configuration Loaded` at all — so the symptom is identical to a
file watcher that never fired, and every measurement after it is of the
old shell. This has cost a session: three consecutive diagnostics were
read as evidence about new code that had never loaded.

```sh
grep -E "Failed to load configuration|Configuration Loaded" \
     $XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log | tail -4
```

The most common cause is `Property value set multiple times` — QML refuses
the whole component, not the one line — which is what you get from adding
a property a block already sets. Read the entire block before adding to
it, not the few lines around your anchor.

If you edited `Metrics.js` or `Motion.js`, a reload does nothing at all:
`.pragma library` JS is cached. Restart the island.

### An IPC call does nothing and reports success

```sh
qs -p ~/.config/quickshell/tide-island-fork ipc show          # is it listed?
qs -p ~/.config/quickshell/tide-island-fork ipc call tide toggleFocus
```

Two traps, both of which look like a working call:

* `qs ipc call` prints `Function not found` and still **exits 0**.
* An `IpcHandler` function with an **untyped** parameter is dropped from
  the IPC surface silently — it does not error and does not warn, it just
  never appears in `ipc show`.

### Night light does nothing

```sh
qs -p ~/.config/quickshell/tide-island-fork ipc call nightlight status
pacman -Q hyprsunset
ps -eo pid,args | awk '/hyprsunset/ && !/awk/'
```

`gammastep` **cannot** work in this session — Hyprland 0.56.2 exposes no
`wlr-gamma-control`:

```sh
gammastep -P -O 4500     # "Zero outputs support gamma adjustment", then hangs
```

Note that `hyprctl hyprsunset temperature` reports the last temperature
*requested*, not the one in effect — after `identity` it still answers the
old value. It is not a state query. And a **screenshot cannot see a gamma
change**: `grim` samples the composited buffer while the transform is
applied at scanout. Measured, a 3000 K filter moved the captured blue mean
by 0.2%. This one needs your eyes.

### The island shows the wrong workspace, or every window at once

```sh
hyprctl activeworkspace -j | jq '{id, name}'
hyprctl workspaces -j | jq -r '.[] | "\(.id) \(.name)"'
```

Named workspaces have **negative** ids — `S` is `-1337` — and so do
special workspaces (`special:term1` is `-97`). Any code that treats
"`< 1`" as invalid drops every named workspace; that was exactly the
`$mod SHIFT O` bug. `0` is the only invalid id, and special workspaces are
excluded by their `special:` name prefix rather than by sign.

### A keybinding does nothing

Ask the compositor, not the config file:

```sh
hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key) -> \(.dispatcher) \(.arg)"' | grep -i <key>
```

If the bind is listed, the script it calls is what failed — run that
script by hand. `hyprctl` dispatchers report success even when the thing
they dispatched did nothing.

### A scratchpad lost its window

```sh
hyprctl clients -j | jq -r '.[] | "\(.workspace.name) \(.class)"'
```

If a scratchpad terminal is sitting on a numbered workspace it was dragged
there. `toggle-app.sh` excludes `special:` windows from its matcher for
exactly this reason; anything new that matches windows by class needs the
same exclusion.

### The drop shelf: what works, and the one thing that does not

`$alt SHIFT D` opens it; shaking the pointer while dragging opens it too
(`scripts/qdrop-shake.py`, with the binds and the whole argument in
binds.conf's qdrop block). It is `pin`ned in rules.conf, so it opens on
whatever workspace you are on rather than the one its daemon was born on.

The gesture's button state comes from Hyprland binds dispatching `event`,
which is worth knowing because it is the general trick: **a bind can see
things `hyprctl` cannot, and `event` reports it to socket2 without spawning
anything.** Nothing in the IPC reports pointer buttons.

```sh
ps -eo pid,args | awk '/qdrop-shake/ && !/awk/'      # the detector
hyprctl binds | grep -A6 qdropshake                  # the five binds
python3 ~/.config/hypr/scripts/qdrop-shake.py --debug --dry-run
```

`--dry-run` logs a shake without opening the shelf, which is how to check a
false positive without a window appearing over your work.

**Dragging a file in from a Wayland-native app does not work, and that is
the compositor, not the shelf.** Driven with `scripts/test/dnd-peer.py`:
an XWayland source drops in and drags out correctly, a Wayland source's drag
starts and never arrives, and the same Wayland drag into a plain XWayland
window arrives carrying the X11 PRIMARY selection instead of the URI that was
offered. pcmanfm-qt runs `QT_QPA_PLATFORM=wayland;xcb`, so it is on the wrong
side of that. The fix is to make the shelf a native Wayland surface placed by
the compositor, which is the same change as making it look like the island —
see NEXT-SESSION.md item 3.

### A background listener stopped reacting

A listener that connects to a socket **once** dies silently and stays
dead. Distinguish the two cases:

```sh
ls -l $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
ps -eo pid,args | awk '/socket2|listener/ && !/awk/'
```

"The read ended" should reconnect; "the socket **file** is gone" means the
compositor left and the listener should exit.

### Audio stops working, or the bus feels slow

The packaged backend spawns up to four long-lived watchers per shell — a
`pactl subscribe`, two `dbus-monitor`s and a `pw-mon` — and does **not** reap
them when the shell is killed rather than asked to quit. They reparent to
init and accumulate for the life of the session.

```sh
ps -eo ppid=,args= | awk '$1 == 1 && (/dbus-monitor/ || /pactl/ || /pw-mon/)' | wc -l
```

104 `dbus-monitor` and 35 `pactl subscribe` is a real reading off this
machine. The audio one is the one that bites: enough of them exhausts
pipewire-pulse's client limit and *every* pulse client on the desktop starts
failing with "too many client application connections".

`scripts/reap-island-helpers.sh` clears them, and both `island.sh` and
`topbar.sh` run it before starting anything. PPID 1 is the whole matcher — a
live shell's helpers have that shell as their parent — so it cannot take one
away from a running island.

### A font silently became Noto Sans CJK

Family names fall back without any warning at all.

```sh
fc-match "Inter Display"      # must resolve to Inter, not a substitute
```

`installScripts/validate.sh` checks every family named by every config
against what `fc-match` actually returns.

### `pgrep`/`pkill` matching the wrong thing

`pkill -f <pattern>` matches its **own** command line. Use `pkill -x`.
This defeats `pgrep -f` checks too, including the `[b]racket` trick, when
the surrounding command line contains the literal string:

```sh
ps -eo args | awk '/pattern/ && !/awk/'      # this works
```

### Before filing anything as broken

Grep for it and measure it first. Four deliberate design decisions were
filed as defects in a single session. `hyprctl` and the shell's own log
will answer most questions faster than reading the code will.
