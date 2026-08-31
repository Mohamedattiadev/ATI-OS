# Hyprland .conf → Lua migration

**Status: not started. Blocked in by a pacman guard, deliberately.**
Written 2026-08-31, against Hyprland 0.56.2.

## Why this document exists

Every session start draws a toast:

> ⚠ You are using the .conf config format, support for which will be
> removed in Hyprland 0.57.

It is not a config error and it cannot be silenced -- the string is
hardcoded in `/usr/bin/Hyprland` and there is no option gating it.

Hyprland 0.55 replaced hyprlang (`.conf`) with a Lua config
(`~/.config/hypr/hyprland.lua`). 0.56 reads both and nags. **0.57 removes
the hyprlang parser.** On that upgrade this config stops loading and the
session comes up in safe mode: default binds, no bar, no submaps,
SUPER+Q for a terminal.

Release cadence says that is close: 0.55.0 in May 2026, 0.56.0 on
2026-07-20, 0.56.2 on 2026-08-05 -- roughly one minor every two months,
so 0.57 lands somewhere in Sept–Oct 2026.

## What is holding the line

`/etc/pacman.d/hooks/10-hyprland-lua-guard.hook` →
`.config/AtiScriptsV1/update/hyprland-lua-guard`

A PreTransaction `AbortOnFail` hook that refuses to install Hyprland
≥ 0.57 while no `hyprland.lua` exists. It fires only when hyprland is in
the transaction, and it **self-expires**: the moment `hyprland.lua` is
there, it does nothing forever.

`IgnorePkg = hyprland` was considered and rejected. Hyprland links
hyprutils, hyprlang, aquamarine and hyprgraphics, and Arch bumps their
sonames in lockstep with the compositor. Holding hyprland alone yields a
binary that cannot find its libraries -- the same dead desktop by a
quieter road. Nothing is held here; the upgrade is refused until the
config can survive it.

Override once, deliberately: `sudo touch /etc/hyprland-lua-guard.ack`.

## The part that makes this a project and not an afternoon

The config rewrite is the *small* half. Two things break outside it:

1. **`hyprctl keyword` stops existing.** Hyprland's own words:
   `"keyword can't work with non-legacy parsers. Use eval."`
   Replacement: `hyprctl eval 'hl.config({ general = { border_size = 3 } })'`

2. **Every legacy `hyprctl dispatch` becomes a Lua syntax error.** Under
   the Lua manager `dispatch` is literally a shorthand for
   `eval "return hl.dispatch(<your text>)"` (confirmed in
   `src/debug/HyprCtl.cpp`), so `hyprctl dispatch workspace 3` fails and
   must become `hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'`.

   This includes Quickshell's `Hyprland.dispatch("movetoworkspacesilent 4")`
   -- the bar sends legacy strings over the same socket path.

Nothing can be half-migrated: the compositor runs one parser or the
other, and `hyprctl reload full-reset` is what switches contexts.

## Inventory (measured, not estimated)

| Area | Size |
| --- | --- |
| `hypr/*.conf` real config lines | ~570 across 9 files: submaps 187, binds 123, rules 88, looks 82, autostart 26, input 22, hyprglass 21, colors 16, monitors 1 |
| legacy `dispatch`/`keyword` sites in scripts | ~68 (worst: `layout-cycle.sh` 9, `sum-toggle.sh` 6, `focus-move.sh` 6, `toggle-app.sh` 5, `scratchpad.sh` 5, `toggle-floating.sh` 3) |
| legacy dispatch sites in Quickshell QML | ~13 (`topbar/Workspaces.qml`, `topbar/TaskList.qml`, `topbar/redesign-e-final.qml`, `tide-island-fork/popups.qml`, `qml/common/HyprlandDispatch.qml` + its callers) |
| generators that emit hyprlang | 2: `ati-theme-apply` (writes `colors.conf` as `$var = rgb(hex)`), `ati-plugin sync` (writes `plugins.conf` as `bind =` lines) |

**Unaffected, do not touch:** `hyprlock.conf`, `hypridle.conf`,
`hyprpaper.conf`. hyprlock/hypridle/hyprpaper are separate projects and
still hyprlang. `colors.conf` therefore has to keep existing in hyprlang
form for them and for `border-focus.sh`; theme-apply will need to emit
*both* it and a Lua colours module.

**Already format-agnostic:** `cheatsheet.py` reads `hyprctl binds -j`,
not the config files. It will keep working untouched -- the one place
past-you already got this right.

## Phase order

1. **Config to Lua, not installed.** Write `hyprland.lua` plus modules
   next to the `.conf` files. Hyprland prefers `hyprland.lua` when it
   exists, so this must land only when it is ready.
2. **Validate in a nested Hyprland**, never by reloading the live one.
   Guard autostart out of the test instance (Lua can branch on
   `os.getenv`), or the nested session spawns a second bar, hypridle and
   the whole stack.
3. **Sweep the call sites.** Scripts first, then the QML. A useful
   intermediate: route everything through one shim so the syntax lives in
   one file, rather than 80 inline strings.
4. **Generators.** theme-apply emits a Lua colours module alongside
   `colors.conf`; `ati-plugin sync` emits `plugins.lua` (`hl.bind(...)`).
5. Switch over, confirm the toast is gone, remove the `.conf` files in a
   separate commit so the diff stays readable.

## API mapping (from `/usr/share/hypr/stubs/hl.meta.lua` and the wiki)

The Lua API covers everything in use. `hyprctl repl`/`eval` only work
under the Lua manager, so none of this can be probed until after the
switch -- the stub file is the reference.

| hyprlang | Lua |
| --- | --- |
| `bind = $mod, Return, exec, kitty` | `hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))` |
| flags `e` / `l` / `m` / `n` / `r` / `i` | `{ repeating=, locked=, mouse=, non_consuming=, release=, ignore_mods= }` |
| `killactive` | `hl.dsp.window.close()` |
| `fullscreen, 0` | `hl.dsp.window.fullscreen({ mode = "fullscreen" })` |
| `movewindow, l` | `hl.dsp.window.move({ direction = "left" })` |
| `workspace, 4` | `hl.dsp.focus({ workspace = 4 })` |
| `movetoworkspace, 4` | `hl.dsp.window.move({ workspace = 4 })` |
| `movetoworkspacesilent, 4` | `hl.dsp.window.move({ workspace = 4, follow = false })` |
| `focusmonitor, l` | `hl.dsp.focus({ monitor = "l" })` |
| `resizeactive, -20 0` | `hl.dsp.window.resize({ x = -20, y = 0, relative = true })` |
| `layoutmsg, togglesplit` | `hl.dsp.layout("togglesplit")` |
| `submap, resize` | `hl.dsp.submap("resize")` |
| `event, qdropshake:down` | `hl.dsp.event("qdropshake:down")` |
| `exec-once = foo` | `hl.on("hyprland.start", function() hl.exec_cmd("foo") end)` |
| `env = KEY,val` | `hl.env("KEY", "val")` |
| `windowrule = float true, match:class ^(mpv)$` | `hl.window_rule({ match = { class = "^(mpv)$" }, float = true })` |
| `layerrule = animation none, ...` | `hl.layer_rule({ match = { namespace = "^(rofi)$" }, no_anim = true })` |
| `general { gaps_in = 4 }` | `hl.config({ general = { gaps_in = 4 } })` |
| `bezier = island, 0.16,1,0.3,1` | `hl.curve("island", { type = "bezier", points = {{0.16,1},{0.3,1}} })` |
| `animation = windows,1,4,island,popin 90%` | `hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "island", style = "popin 90%" })` |
| `gesture = 3, horizontal, workspace` | `hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })` |
| `monitor = , preferred, auto, 1` | `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })` |
| `source = ./looks.conf` | `require("looks")` |

### Wins available while rewriting

- `hl.define_submap(name, "reset", fn)` auto-resets after any dispatch,
  which deletes the entire `bind = , X, exec, …` + `bind = , X, submap,
  reset` doubling -- that pattern is ~90 of submaps.conf's 187 lines.
- The workspace 1–9 block repeated in five submaps becomes a `for` loop.
- `hl.bind(..., { submap_universal = true })` replaces re-declaring the
  same keys inside every submap.
- Binds take a `description`, which `hyprctl binds` and therefore
  `cheatsheet.py` can show.

### Gotchas found the hard way

- The existing `hyprglass.lua` (written ahead of time, not loaded) calls
  `hl.windowrule(...)`. **The real name is `hl.window_rule`.** Fix before
  trusting that file.
- hyprglass is installed and enabled via hyprpm. Its Lua surface
  (`hl.plugin.hyprglass`) is unverifiable until the switch, since
  `hyprctl repl` refuses to run under the hyprlang manager. Confirm the
  installed plugin build exposes it *before* deleting `hyprglass.conf`.
- Bind callbacks run on the compositor event loop: no `io.popen`, no
  sleeps, no clipboard tools inside them, or input freezes. Shell out
  with `hl.dsp.exec_cmd`.
- Window-rule `match` keys use snake_case (`float`, `no_initial_focus`,
  `idle_inhibit`, `suppress_event`), and only *named* rules can later be
  toggled with `:set_enabled()`.
- `hl.dsp.*` on its own does nothing inside a function -- it must be
  wrapped in `hl.dispatch(...)`.

## Converters

No official one exists. Third-party, for a mechanical first pass only:
`hyprconf2lua` (pip), `hyprlang2lua` (AUR), `hypr-migrate`. All leave
TODO markers, and none know about the ~80 call sites, which are the
actual work.
