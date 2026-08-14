# Hyprland

The Wayland session. qtile/X11 remains the default and is untouched; both
are selectable at login and share theme state, so this directory is
additive rather than a replacement.

| | |
|---|---|
| Compositor | Hyprland 0.56.2 |
| Shell | Quickshell — `~/.config/quickshell/tide-island-fork` |
| Wallpaper | `awww` (the daemon; `swww` is its old name) |
| Idle / lock | `hypridle` / `hyprlock` |
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
| `scripts/` | everything the binds call |

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
   every theme change, never repeating the previous pick.
3. **single** — `~/Pictures/Wallpapers/themed/<theme>.jpg`.
4. **nothing** — leave the wallpaper alone. A theme change must never
   blank the desktop.

The override deliberately beats the set: otherwise a deliberate pick would
survive only until the next theme change. `theme-wallpaper forget <theme>`
hands a theme back to its set.

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

### A background listener stopped reacting

A listener that connects to a socket **once** dies silently and stays
dead. Distinguish the two cases:

```sh
ls -l $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
ps -eo pid,args | awk '/socket2|listener/ && !/awk/'
```

"The read ended" should reconnect; "the socket **file** is gone" means the
compositor left and the listener should exit.

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
