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
- **Inter was not installed, and nothing said so — now fixed.** Every
  `font_family` in `hyprlock.conf`, and every family DESIGN-SPEC.md
  specifies for the notch, silently resolved to Noto Sans CJK KR. There
  is no warning for this anywhere: fontconfig's job is to always return
  *a* font, so a typo'd or absent family renders in the wrong face and
  looks merely ugly rather than broken. `inter-font` is installed and
  declared in `arch-config/modules/fonts.yaml`; verified with
  `fc-match`, which now answers `Inter.ttc: "Inter" "Medium"` and
  `Inter.ttc: "Inter Display" "SemiBold"` — i.e. each family resolves to
  itself. **`fc-match` every family you name in a config**; that is the
  only way to catch this class of bug.
- **qutebrowser's Wayland app_id is `org.qutebrowser.qutebrowser`**, not
  `qutebrowser`. `toggle-app.sh` matches unanchored so it works, but any
  `match:class ^(qutebrowser)$` rule added later will not fire.

### Chords were invisible; now they announce themselves

qtile's `KeyChord` named the active mode in the bar. Hyprland submaps
give no feedback whatsoever — the compositor just starts swallowing
keys, and the only way to tell you are in one is to press something.

`scripts/submap-indicator.sh` listens on Hyprland's event socket
(`submap>>name` entering, `submap>>` leaving) and puts the mode name in
the island, where qtile's bar used to say it. It stays for exactly as
long as the mode is active: **persistent, not a toast.**

It now uses the island **directly**, via a forked `tide showText <string>`
IPC. The earlier note said this needed dunst because upstream's
`showCustom()` takes no arguments — true at the time, and no longer.
dunst remains only as a fallback for the window between login and the
island finishing its load, tried per event rather than probed once.

**A bug worth remembering, because only a never-expiring indicator can
have it.** Nothing in the system will ever remove a `-t 0` notification,
so the only thing that cleared it was this script seeing the matching
leave event. Killed mid-chord, restarted after a reload, or one dropped
event, and a permanent "ROFI-MODE" sits over a desktop that is in no
submap at all — worse than no indicator, because you believe it. Fixed
by clearing once *before* the event loop and again from a trap on EXIT
TERM INT HUP, plus an `flock` guard so there is only ever one instance.

The trap needed the loop to change shape, which is the non-obvious part:
bash defers trap handlers until the current foreground command returns,
and `reader | while read` is one command that never returns — so SIGTERM
left the process alive and the indicator on screen, reintroducing the
exact bug. Reading from a process substitution puts the interruptible
`read` builtin in the main shell instead, and the handler fires at once.

The socket is read with python3, not socat: socat is not installed here,
and adding a declared package for one `read` on a unix socket is a poor
trade when python3 is already a hard dependency.

Note for future work: Hyprland 0.56 has a per-bind `submap.reset`
property, so the paired `bind = , X, submap, reset` lines throughout
`submaps.conf` are redundant with a native feature. They are NOT a bug —
verified in `KeybindManager.cpp` that two binds on one key both fire, in
config order — just more verbose than they need to be.

### Window borders were green in every theme

The complaint that borders "don't follow the theme" was real, and the
cause was in `theme-apply`, not in Hyprland. `gen_hypr_colors()` set
`$accent` to the **green slot**, and `looks.conf` used `$accent` for
`col.active_border`. Green is green in all 20+ palettes, so switching
theme moved the border between shades of green and looked like nothing
had happened.

Three different things had been collapsed into one variable:

| role | doomone value | who wants it |
|---|---|---|
| green slot | `#98be65` | nothing — this was the bug |
| `accent_of_mode` | `#51afef` | GTK accent, qtile GroupBox, hyprlock field |
| qtile `colors[8]` (cyan) | `#46d9ff` | the focused window border |

qtile's `layout_theme` sets `border_focus = colors[8]`, which is the
cyan slot of the 9-slot palette — not the accent. So `colors.conf` now
generates a dedicated `$border_active` / `$border_inactive` pair, and
`$accent` is `accent_of_mode` (correct for hyprlock's field colour).

Verified by cycling themes against the live compositor:

| theme | border | accent |
|---|---|---|
| doomone | `46d9ff` | `51afef` |
| gruvbox | `8ec07c` | `fabd2f` |
| nord | `88c0d0` | `88c0d0` |
| dracula | `8be9fd` | `bd93f9` |

qtile uses `border_normal = colors[1]` (the light FG slot) for unfocused
windows. That is deliberately **not** mirrored — at `border_size 2` a
bright border on every unfocused window reads as noise under Hyprland's
gaps. `$border_inactive` is `$bg_alt`; swap it to `$fg` for literal
parity.

### hyprlock rejected three options without failing

`hyprctl configerrors` knows nothing about `hyprlock.conf` — hyprlock
parses it itself, at lock time, and prints to **its own stderr**, which
nothing captures during a normal lock. It reported:

```
config option <general:grace> does not exist.
config option <general:no_fade_in> does not exist.
config option <general:disable_loading_bar> does not exist.
Proceeding ignoring faulty entries
```

In 0.9.6 `grace` is a **command-line flag**, not a config option
(`hyprlock --grace 0`); the other two were removed with no replacement.
`hypridle.conf`'s `lock_cmd` now passes `--grace 0` explicitly. The
valid `general:` keys are `fail_timeout`, `fractional_scaling`,
`hide_cursor`, `ignore_empty_input`, `immediate_render`,
`screencopy_mode`, `text_trim`.

### The lock clock was drawn off-screen

Label positions were `420` and `330` px, taken from the video's 2560x1440
display. `valign = center` measures upward from the vertical centre, so
on this 1366x768 panel the date sat at 804 — 36px above the top edge,
invisible — and the clock was clipped. Nothing logs this. Both are now
percentages (`26%`, `17%`), so the layout holds on either monitor.

### hyprlock: VERIFIED, including the wrong password

Done, and it passes. The live test does not require locking your real
session — run a **nested Hyprland** as a window and lock only that:

```
Hyprland -c nested.conf          # nested.conf sets its own monitor +
                                 # exec-once = hyprlock --grace 0
WAYLAND_DISPLAY=wayland-2 wtype "wrong-password"
WAYLAND_DISPLAY=wayland-2 wtype -k Return
```

The nested compositor takes the next free socket (`wayland-2`), and
`wtype` drives it through `zwp_virtual_keyboard_manager_v1`, so
hyprlock receives real keystrokes while the outer session stays
untouched. Screenshot the nested window with `grim -g`.

Result: **rejected.** hyprlock displayed `Wrong password`, stayed
locked, and the process was still alive afterwards. Confirmed
independently of the UI by `faillock --user ati`, which recorded the
attempt with source `hyprlock` — proof PAM actually evaluated and
denied it rather than the field merely clearing.

Note `deny=3` / `unlock_time=600` are the defaults here, so three wrong
attempts lock the account for ten minutes. Reset a test's counter with
`sudo faillock --user ati --reset`.

Static analysis of the PAM stack, which the above confirms:

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

(An earlier draft of this file claimed the wrong-password test could not
be automated, on the grounds that Wayland forbids synthetic keystrokes.
That is true of the *outer* session but not of a nested compositor,
where `wtype` is an ordinary client — hence the method above. Do NOT
test by locking the real session: doing so once already cost a TTY
switch to recover.)

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

## The bar — now a notch, and forked

Tide Island is running, and the QML is vendored and patched at
`.config/quickshell/tide-island-fork/` (launched by `scripts/island.sh`).
The resting shape is the notch from DESIGN-SPEC.md: flush to the top
edge, top corners square, a 9 px concave flare each side, pure black.

Four things landed in the fork that no config key could reach — the notch
morph, a generated spring, arbitrary text, and a theme picker. Each is
written up with its traps in `tide-island-fork/FORK-NOTES.md`, which is
also the merge list for the next `pacman -Syu` of `tide-island`.

The two traps most likely to bite again:

- **Qt's `Easing.BezierSpline` takes at most 10 cubic segments.** The
  eleventh corrupts the heap and the process takes SIGSEGV on the first
  animated frame — no warning, no fallback. It killed the shell on every
  launch until it was bisected in an offscreen `qml6` harness.
- **Quickshell IPC parameters must be typed.** `function f(text: string)`
  works; `function f(text)` accepts the call and arrives `undefined`.

Four qtile bindings drove widget internals (`SmartWidgetBox` toggles,
top↔bottom bar swap). Those remain unported — they have no analogue in
this shell.

Tide-island upstream: <https://github.com/enhaoswen/Tide-island>

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
