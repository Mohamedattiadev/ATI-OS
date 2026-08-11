# qtile → Hyprland migration status

Ported from `../qtile/config.py` (7,879 lines, 291 resolved bindings as
reported by `qtile cmd-obj -o cmd -f display_kb`).

Scope of this pass: **usable daily driver**. Window management, workspaces,
and every binding that did not depend on qtile's Python API or on X11.

## Numbers

Verified by diffing this config against qtile's own resolved binding table,
not by hand — see `audit.py` in the migration scratchpad.

| | count | |
|---|---|---|
| Bindings in qtile | 291 | |
| **Implemented here** | **123** | 42.3% |
| Deferred | 142 | 48.8% |
| Blocked (X11-only) | 26 | 8.9% |

Deferred breaks down as 121 popup-chord bindings, 18 root bindings, and 3
nested chord entries. Blocked is Hintium (6 root + all 19 of Hint-Mode)
plus the xmodmap reapply binding.

**Hyprland 0.56.2 is installed and has now been run.** See
"Runtime verification" below for what first login actually proved —
including one silent bug that `--verify-config` cannot catch.

## Runtime verification (first live session)

Checked against a running 0.56.2 on the 1366x768 laptop panel, single
monitor. `hyprctl configerrors` is empty and the log has no config
errors; the only `ERR` lines are aquamarine's TTY-launch backend probing
(`wl_display_connect failed`, `getCurrentCRTC: No CRTC 0`,
`Cannot commit when a page-flip is awaiting`) — all benign.

| Check | Result |
|---|---|
| keyd Caps→Alt | **works** — matched `AT Translated Set 2 keyboard`; Hyprland's `main` keyboard is `keyd-virtual-keyboard`, and 55 ALT binds are live |
| Rules engine (`class:` / `title:`) | **works** — verified by spawning against real matchers |
| Scratchpad geometry | **was broken, fixed** — see below |
| Scratchpad spawn-on-first-press | **works** — spawns once, toggles thereafter, never respawns |
| `toggle-app.sh` | **works** — all three states (spawn / stash / pull-back-and-focus) |
| hyprlock PAM | **statically sound**, live test still owed — see below |
| Autostart | all daemons up: hyprpaper, hypridle, dunst, copyq, polkit, portals, qupdate |

### The log is not at `~/.hyprland.log`

0.56 writes it per-instance under the runtime dir:

```
$XDG_RUNTIME_DIR/hypr/<instance-signature>/hyprland.log
# i.e.  ls $XDG_RUNTIME_DIR/hypr/*/hyprland.log
```

It is also ~95% libinput gesture debug spam; `grep -v DEBUG` first.

### Percentage `size` / `move` window rules are silently inert

This is the one that `--verify-config` and `hyprctl configerrors` both
miss, because the config is syntactically valid — the rules simply never
apply. Measured by spawning kitty with `size 50% 25%, move 10% 40%`
(want `683x192 @ 137,307`) on a 1366x768 monitor:

| rule form | workspace | result |
|---|---|---|
| percent | special | `1346x748 @ 10,10` — **both ignored** |
| pixel | special | `683x192 @ 137,307` — correct |
| percent | normal | `683x192 @ 342,288` — size ok, **move ignored** (centred) |
| pixel | normal | `683x192 @ 137,307` — correct |

So percentage `move` never applies, and on a special workspace
percentage `size` does not either. **`float` applies in all four cases**,
which is exactly what made this hard to see: all six scratchpads floated,
so they looked configured, but each kept full tiled size.

Fixed by moving scratchpad geometry out of `rules.conf` and into
`scripts/scratchpad.sh`, which resolves the percentages against the
*focused* monitor at spawn time and passes pixels as inline exec rules
(`[workspace special:x silent; float; size W H; move X Y]`). Hardcoding
pixels in `rules.conf` would have fixed one monitor and broken the other.

Verified after the fix: term1 and term2 land at `820x461 @ 273,77`,
exactly 60%x60% @ 20%,10%.

### Known cosmetic deviations

- **calc** lands at `820x550`, not `820x461` — qalculate-gtk enforces a
  GTK minimum height and Hyprland re-centres around it. App-imposed;
  qtile's DropDown had the same constraint. Not worth fighting.
- **Inter is not installed**, so every `font_family` in `hyprlock.conf`
  silently resolves to Noto Sans CJK KR (`fc-match "Inter Medium"`
  confirms). The lock clock renders in the wrong face with no warning.
  `sudo pacman -S inter-font` fixes it, and it is needed for the notch
  bar anyway — DESIGN-SPEC.md specifies Inter / Inter Display throughout.
- **qutebrowser's Wayland app_id is `org.qutebrowser.qutebrowser`**, not
  `qutebrowser`. `toggle-app.sh` matches unanchored so it works, but any
  `match:class ^(qutebrowser)$` rule added later will not fire.

### hyprlock: what is and is not verified

The lockout risk is cleared: `/etc/pam.d/hyprlock` exists and is the
packaged one (`auth include login`), resolving through
`system-login` → `system-auth`, whose stack is stock Arch:

```
auth [success=1 default=bad] pam_unix.so try_first_pass nullok
auth [default=die]           pam_faillock.so authfail
auth optional                pam_permit.so
```

`pam_permit` is only reachable *after* `pam_unix` succeeds, so there is
no always-accept path — which is precisely the failure the video author
hit with a hand-written PAM file. This config does not have his bug.

**Still owed: the live wrong-password test.** It cannot be automated —
hyprlock grabs input and Wayland forbids synthetic keystrokes — so it
needs a human at the keyboard. Do it with a watchdog so a failure is
self-recovering:

```
( sleep 60; pkill hyprlock ) & hyprlock
```

Type a wrong password, confirm it is rejected, then the real one.

## Hyprland 0.56 API changes this config had to absorb

Written against pre-0.5x documentation, corrected against the binary.
Recorded here because none of it is obvious from an error message.

| Was | Now |
|---|---|
| `windowrulev2 = ...` | `windowrule = ...` (v2 merged in, v1 name kept) |
| `windowrule = float, class:^(x)$` | `windowrule = float true, match:class ^(x)$` |
| `noblur` / `nofocus` | `no_blur true` / `no_focus true` |
| `suppressevent` / `idleinhibit` | `suppress_event` / `idle_inhibit` |
| `xwayland:1`, `fullscreen:1` | `match:xwayland true`, `match:fullscreen true` |
| `togglesplit` dispatcher | `layoutmsg, togglesplit` |
| `splitratio` dispatcher | `layoutmsg, splitratio ±n` |
| `gestures { workspace_swipe = true }` | `gesture = 3, horizontal, workspace` |
| `misc:vfr` | removed; the renderer handles it |
| `dwindle:pseudotile` | removed as an option; `pseudo` is a dispatcher |

The rule change is the big one: **every rule now needs an explicit
value, and every matcher is prefixed `match:`**. A bare `float` fails
with "invalid field float: missing a value", which does not hint that
the matcher syntax changed too. 57 rules were converted.

## What works on first boot

- All 9 workspaces, switch + move-to
- Focus/move/resize, floating, fullscreen, split toggle, layout swap
- Both monitors, focus left/right
- All 6 scratchpads (term1, term2, calc, chatgpt, whats, deepseek)
  with their original geometry
- The entire Rofi-Mode chord (20 launchers) — the cleanest port in the config
- Resize, Draw, Lang-Switch, Passthrough chords
- Media/brightness/volume hardware keys (now via wpctl + brightnessctl)
- Screenshot-to-clipboard (grim + slurp)
- Window float rules

## Before first boot: the Caps→Alt remap

**Do this or a third of the keyboard is dead.** This laptop's physical Alt
is broken; `~/.Xmodmap` remaps Caps Lock to `Alt_L`, and ~40 bindings use
ALT. xmodmap does not exist on Wayland, and xkb has no `caps:alt` option.

Use **keyd** — it remaps at the evdev layer, so one config serves both the
qtile/X11 session and Hyprland, and nothing diverges while you run both.

```
sudo pacman -S keyd
sudo tee /etc/keyd/default.conf <<'EOF'
[ids]
*

[main]
capslock = leftalt
EOF
sudo systemctl enable --now keyd
```

Verify with `sudo keyd monitor` — pressing Caps should report `leftalt`.

Once keyd is active you can delete the `xmodmap` call from the qtile
config too; keyd does the job for both sessions.

## Install

```
sudo pacman -S hyprland xdg-desktop-portal-hyprland \
    hyprpaper hypridle hyprlock \
    grim slurp wl-clipboard \
    brightnessctl playerctl \
    polkit-kde-agent qt5-wayland qt6-wayland
```

Rofi: the X11 `rofi` you have works under XWayland. `rofi-wayland` is the
native fork if you hit issues — it is a drop-in replacement.

Then symlink the config into place (it lives in the dotfiles repo):

```
ln -s ../.dotfiles/.config/hypr ~/.config/hypr
```

Log out, pick **Hyprland** at the display manager. qtile is untouched and
remains selectable — nothing here modifies the X11 session.

## Blocked, not merely unported: Hintium

`~/.local/share/hintium` is X11-native — `hintium/x11.py` plus Xlib/XTest
across `click.py`, `windows.py`, `scroll.py`, `elements.py`, `service.py`.
It reads the global window tree and synthesises pointer events. Wayland
forbids both to ordinary clients by design; this is a security boundary,
not a missing feature.

Six root bindings depend on it (`$alt` + space/c/e/j/slash, and `$alt SHIFT c`),
plus the whole Hint-Mode chord.

Options, roughly in order of effort:
- **wl-kbptr** — keyboard-driven pointer positioning, closest ready-made analogue
- **dotool / ydotool** — input synthesis via uinput; restores the click/scroll
  half but not the element detection
- **Reimplement** against Hyprland IPC (`hyprctl clients`) for windows and
  `wlr-virtual-pointer` for clicks. Element-level hinting inside apps would
  still need AT-SPI, which is patchy on Wayland.

## Deferred: the 13 popups (~99 bindings)

`../qtile/popups/*.py` are built on `qtile.extras.popup.toolkit`, which
exists only inside qtile. Their key handlers are lambdas closing over live
popup objects — they cannot be expressed as commands, so there was nothing
to translate.

| Popup | Bindings | Interim stand-in |
|---|---|---|
| AudioPopup | 25 | `pavucontrol` / rofi-pulse |
| DisplayPopup | 28 | `nwg-displays` / `wdisplays` |
| WifiPopup + WifiQR | 14 | `nmtui`, `rofi-network-manager` |
| BluetoothPopup | 12 | `blueman-manager`, `rofi-bluetooth` |
| WallpaperPopup | 9 | `waypaper` |
| Cheatsheets (Qtile/Vim/Fish) | 16 | rofi-based list, or rebuild in QML |
| UpdatesPopup | — | `qupdate.py` daemon still runs |

These are the natural second phase, rebuilt as Quickshell/QML pages inside
the Tide-island bar — which is where they arguably belong anyway.

## Deferred: app togglers (7 bindings)

`../qtile/scripts/toggle_apps.py` imports `libqtile` directly and walks
qtile's own client list. Nothing in it survives the move. Each becomes a
`hyprctl clients -j` lookup plus `dispatch focuswindow`, or is folded into
a scratchpad. They are listed commented in `binds.conf`.

## Deferred: the bar

Four bindings drove qtile widget internals (`SmartWidgetBox` toggles,
top↔bottom bar swap). They resume meaning only once Tide-island is running
and exposing IPC.

Tide-island: <https://github.com/enhaoswen/Tide-island> — clone to
`~/.config/quickshell/`, then uncomment the `qs -c tide-island` line in
`autostart.conf`.

## Deliberate behaviour changes

- `$mod SHIFT R` was `_smooth_restart` (restart preserving window state).
  Hyprland's `hyprctl reload` never touches windows, so the preservation
  machinery is unnecessary.
- `go_to_group_or_notify` notified when a group did not exist. Hyprland
  creates workspaces on demand, so the notify path was dropped.
- qtile chords were one-shot; Hyprland submaps are sticky. Every submap
  here exits explicitly on both `Escape` and `q`, matching the old
  `ungrab_chord` bindings.
- `$mod SHIFT K` remains CheatSheet-Mode (deferred), *not* "move window up",
  faithful to qtile. `binds.conf` has a commented line if you want the
  movement key instead.
