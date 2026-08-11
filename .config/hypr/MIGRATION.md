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

### SUPER+P typing a literal "p" — cause identified, fix applied

Reported symptom: `$mod P` types a `p` into the focused window instead of
entering the Rofi chord. Earlier attempts could not reproduce it, because
`wtype` cannot trigger Hyprland keybinds at all — it creates and destroys a
virtual keyboard, which resets the submap, so every synthetic press looks
like a failure whether or not one exists.

**What was ruled out**, all measured against the running compositor:

| suspect | evidence |
|---|---|
| a shadowing duplicate bind | `hyprctl binds` has exactly ONE bind on modmask 64 + P, and it is `submap, rofi`. The other P binds are modmask 8 (`$alt`, clock_popup) and two inside the rofi submap at modmask 0 |
| the bind not being loaded | it is present in `hyprctl binds` after every reload |
| a non-US layout changing the keysym | `input:resolve_binds_by_sym` is **0**, so binds resolve by KEYCODE and the four configured layouts cannot affect them. All eight keyboards also report `English (US)` |
| Caps Lock as a modifier | keyd remaps Caps to `leftalt`, so it can never latch |
| NumLock as a modifier | `numlock_by_default` is 0 and both numlock LEDs read 0 |

**What actually explains it**, and it is a behavioural difference between
qtile chords and Hyprland submaps that this config had not accounted for:

qtile's chords ran with `swallow=True`, which ate **every** key while the
chord was open. Hyprland submaps do not. A key with no bind in the active
submap is passed straight through to the focused window.

Inside the `rofi` submap there was **no SUPER-modified bind of any kind**.
So SUPER+P while already in that submap matches nothing, leaks to the
client, and types a `p` — which is exactly the report. And it repeats
forever, because pressing it again does the same thing and never leaves.
This submap is also the easiest one to get stuck in: `q` is `dm-logout`
here, faithful to qtile, so `Escape` was the only exit.

**Fix: every submap's own entry combination now exits it.** `$mod P` inside
`rofi`, `$mod R` inside `resize`, `$mod SHIFT W` inside `draw`, `$mod SPACE`
inside `lang` — `passthrough` already had `$mod F12`. Each is a toggle now
and can never be the key that leaks. This is also what qtile itself did for
the modes it put on a single keystroke: Audio-Mode and Display-Mode each
rebound `alt+3` / `alt+4` to close-and-ungrab, with the comment "so alt+3
toggles".

**Honest status: the cause is not proved by reproduction, only by
elimination plus a mechanism that produces exactly the reported symptom.**
The fix is correct regardless — an entry key that does not toggle is a bug
on its own terms — but if a bare `p` still appears, the next step is to
watch the event socket while pressing the key for real:

```
socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock
# or, since socat is not installed here, scripts/submap-indicator.sh's
# python reader is the same three lines
```

A `submap>>rofi` line means the bind fired and the `p` came from somewhere
else; no line at all means the modifier is not reaching the compositor,
which points at the keyboard or the keyd layer rather than at this config.

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
| AudioPopup | 25 | **DONE** — rebuilt, see below |
| DisplayPopup | 28 | **DONE** — rebuilt, see below |
| WifiPopup + WifiQR | 14 | **DONE** — see below |
| BluetoothPopup | 12 | **done** — see below |
| WallpaperPopup | 9 | `waypaper` |
| Cheatsheets (Qtile/Vim/Fish) | 16 | **DONE** — rofi, see below |
| UpdatesPopup | — | `qupdate.py` daemon still runs |

These are the natural second phase, rebuilt as Quickshell/QML pages inside
the Tide-island bar — which is where they arguably belong anyway.

### Wi-Fi and Bluetooth were already built, and simply unbound

The island's control centre owns both lists — scan, signal strength,
connect, the lot — and they were reachable only by opening the control
centre and clicking a chevron. 26 bindings' worth of function was sitting
there with no key on it.

`tide toggleWifiPanel` / `tide toggleBluetoothPanel` open the control
centre and its sub-panel in one step, bound to **`n`** and **`b`** in the
rofi submap, which are the keys qtile's WifiPopup and BluetoothPopup had.

One implementation note that is not obvious: the two cannot be opened in
the same tick. `controlCenterLoader` is not instantiated until the island
is already in the `control_center` state, so `controlCenterLoader.item` is
still null on the line after `showControlCenter()`. Deferred by one
event-loop turn with `Qt.callLater` — enough, because the Loader is
synchronous.

**WifiQR is done too**, on **`$mod P` → `SHIFT+S`**.

qtile had it a level deeper than this config has a level: `$mod P`, then
`n` for Wifi-Mode, then `s`. Here `n` opens the island's network list
directly rather than a chord, so there is nowhere for a plain `s` to
live — and plain `s` at the rofi level is already dm-spellcheck, itself a
qtile port that keeps its key. Shifting the letter is the convention
`SHIFT+C` already set for the island's theme picker beside rofi's.

`scripts/wifi-qr.py` reads the SSID and the stored PSK out of
NetworkManager (`nmcli --show-secrets` works as the logged-in user for
`psk-flags=0`, which is anything saved normally — no sudo, no polkit),
builds the `WIFI:` URI that Android and iOS cameras understand, and shells
out to `qrencode`. `tide-island-fork/qml/wifi/WifiQrLayer.qml` shows it.
`qrencode` was already installed and already declared in
`arch-config/modules/wm.yaml`, so no package count moved.

Four things are deliberate and would be easy to "improve" into a code that
phones refuse:

- **Black on white, always**, on its own white card, whatever the theme is.
  Inverted codes are out of spec and many cameras reject them, and the
  white card IS the quiet zone — a dark desktop running up to the modules
  costs the decoder the margin it uses to find the symbol.
- **qrencode runs twice**: once at one pixel per module to learn the module
  count, then at an integer scale that fits the box. The panel then paints
  the result at its natural size and never stretches it. A fractional
  resample softens exactly the edges a camera needs.
- **`-8` pins byte mode.** A QR carries no ECI header, so a decoder may
  guess the charset — zbar guesses Shift-JIS and returns katakana for a
  Turkish SSID.
- **`\ ; , : "` are escaped** in the SSID and the PSK. They are the
  separators of the URI itself, so one of them unescaped truncates the
  payload and the phone joins the wrong network, or asks for a password
  that looks right.

Verified: the panel drew a 222 px symbol for `TDV-OGRENCI-KAT-1B`, which
is the active connection `nmcli` reports. There is no QR decoder on this
machine (`zbarimg` is not installed and adding a package to check one file
is a poor trade), so the render was checked structurally instead — the
final PNG was compared **module for module** against the one-pixel-per-
module probe: 37 modules at 6 px each, **0 mismatches**, quiet zone white
all round. That proves the scaling step did not distort the symbol, which
is the only step this code adds on top of qrencode.

Refusals are also messages rather than an empty box, because "not
connected to Wi-Fi", "no stored password for this network" and
"enterprise networks can't be shared by QR" have three different answers.
A profile name that does not exist is caught explicitly: every `nmcli -g`
query answers "" for it, and an empty key-mgmt reads as an OPEN network,
so a typo would otherwise produce a perfectly valid code for a network
that does not exist. Those three panels were not photographed — the
machine is connected to a WPA network and disconnecting it to take a
screenshot is not worth it — so the *rendering* of the error state is
argued, not shown; the script side of each was run and prints what the
panel displays.

The connectivity panels also caught a rescale miss worth recording: their
size comes from `connectivityDetailWidth` / `Height` on the island window,
which OVERRIDE `ConnectivityDetailShell`'s own defaults — so scaling the
defaults changed nothing at all. The names are local rather than QML's
`width`/`height`, so the mechanical pass did not see them, and the symptom
was an unscaled 318x404 network list hanging off a 310x221 control centre
at nearly twice its height.

### Cheatsheets are done, and they are rofi on purpose

REQUIREMENTS.md item 3 sets the rule — rebuild the *interactive* popups in
the shell, leave the *launcher* problems on rofi — and a cheatsheet is
firmly the second kind. It is a list you read and dismiss. rofi already
does that, under XWayland, with fuzzy search, for nothing.

`scripts/cheatsheet.py`, on qtile's `$mod SHIFT K`, with `k` / `v` / `f`.

Four of qtile's sixteen bindings (`j`, `k`, `Tab`, `Shift+Tab`) existed
only to move a viewport around 129 rows of text. They are deliberately
**not** reproduced: rofi replaces all four with typing what you are looking
for, which is strictly better than paging.

Two things worth keeping:

- **The Hyprland sheet is generated from `hyprctl binds` at the moment you
  press the key**, not from a list and not by parsing `binds.conf`. qtile's
  `QtileCheatsheet.py` carried 129 hand-maintained rows that were only as
  true as the last person to update them. Reading the compositor's own
  resolved table means the sheet cannot drift — 181 rows today, every
  submap included. It labels ALT as Caps Lock in the header, because on
  this laptop that is what ALT physically is.
- **The vim and fish sheets are parsed out of the qtile popups with `ast`,
  never imported.** `popups/VimCheatsheet.py` imports `qtile_extras` at
  module level and builds a popup as a side effect, so importing it from
  outside qtile fails and importing it from inside would draw a popup.
  `ast.literal_eval` on the single `CHEATSHEET` assignment reads the data
  and runs none of the file — one copy of the content, and
  `~/.config/qtile` stays read-only.

Verified by opening all three and reading them: 181 Hyprland rows, 89 vim,
60 fish, markup intact, search working.

### DisplayPopup is done, and it was the urgent one

Not because it is the largest, but because it was the only one with **no
working fallback**. The table above named nwg-displays and wdisplays as the
stand-in and neither is installed, so between the migration and now this
machine had no way to change resolution, scale, rotation or arrangement
except by editing `monitors.conf` and reloading.

`scripts/display-ctl.py` is the backend and knows everything about
Hyprland's monitor syntax; `tide-island-fork/qml/display/DisplayPanel.qml`
is the keyboard and the pixels. The split is deliberate — the backend can
be exercised from a shell, where the previous generation of this feature
was 2,000 lines of Python that could only be run by opening a popup.

Bound to **`$alt 4`**, qtile's own key. It is not a submap: qtile needed a
KeyChord because its popup could not take keyboard focus at all, whereas
this is a layer surface with an exclusive grab that reads its own keys.

Verified against the live panel — the countdown in both directions being
the one that matters, since it is the only thing standing between a bad
mode and a screen you cannot see to fix:

| action | result |
|---|---|
| Enter on 47.99 Hz | applied; header shows "reverting in 11s — y to keep, c to revert" |
| wait it out | back at 59.987 Hz, "no answer — reverted" |
| Enter, then `y` | stayed at 47.99 Hz, "kept" |
| `v`, Enter on a saved layout | restored, through the same countdown |
| `set --disable` on the only output | refused |
| `preset external` with no external | refused |

### AudioPopup is done, and the control centre was not already doing it

The easy conclusion — "the island's control centre has a Sound slider, so
audio is covered" — was wrong, and it is worth writing down why, because
it is the same shape of mistake as the Wi-Fi one two sections up in
reverse. That slider is the volume of the **default sink**. qtile's popup
was about which device the default *is*, and about everything that is not
the default:

| qtile did | reachable before | now |
|---|---|---|
| pick the output **and drag the playing streams onto it** | no | Enter in `outputs` |
| pick the default microphone | no | Enter in `mics` |
| per-application volume / mute | no | `playback`, `h`/`l`/`m` |
| route ONE app to another device | no | Enter on a stream → `move to…` |
| what is recording right now | no | `recording` |
| card **profile** (A2DP ↔ HSP/HFP) | no | `p`, or `C` for every card |
| output **port** (speakers ↔ headphone jack) | no | `Shift+P` |
| volume above 100% | no | to 150%, red past unity |

`pavucontrol` is not installed on this machine, so the stand-in the table
above named did not exist either.

`scripts/audio-ctl.py` is the backend and
`tide-island-fork/qml/audio/AudioPanel.qml` is the keyboard and the
pixels — the same split as the display panel, and for the same reason.
Bound to **`$alt 3`**, qtile's own key. Not a submap: it is a layer
surface with an exclusive grab, so its keys cannot leak.

**The one thing `pactl set-default-sink` will not do is the reason this
exists.** Pulse routes only *new* streams to a new default, so switching
output while music plays leaves the music on the old device. `default-sink`
re-reads the sink-input list and moves every one of them, and the status
line reports the count.

Four pactl traps are carried over from the qtile file rather than
rediscovered; they are documented at the top of `audio-ctl.py`. The one
most likely to bite a future change: **indices are PipeWire serials and
they move** (a sink's own index changed from 51 to 249079 just from a
stream move), so everything is addressed by name and the one thing that
cannot be — a sink-input — is re-read in the pass that uses it.

Verified against the live daemon, by driving the panel and reading `pactl`
back afterwards:

| action | result |
|---|---|
| `h` on a playing stream | row, bar and details all moved to 85%; `pactl` agreed |
| `m` | `mute: True` in `pactl`, "mute" in red on the row |
| Enter on the output | `output: … · output set · moved 1 stream` |
| `p`, Enter on Analog Stereo Output | `active_profile` became `output:analog-stereo`; `k`+Enter put Duplex back |
| `Shift+P`, Enter on Headphones | refused: "Headphones has nothing plugged in" |
| `b` `b` | balance `-0.2`, channels 79/63; `0` re-centred |
| Enter on a stream → Enter | `move to…`, cursor already on the current device |

**`wtype` DOES drive this panel**, which is worth knowing after the
SUPER+P work concluded the opposite about keybinds. The distinction is
that a submap is compositor state that a virtual keyboard's arrival and
departure resets, whereas this panel is an ordinary Wayland client with
keyboard focus — synthetic keys reach it exactly like real ones. Only the
`$alt 3` that opens it cannot be synthesised; that was checked with
`hyprctl binds` instead.

**Not ported, deliberately:** qtile's `_slider()` box-drawing bar (this
draws a real rectangle) and the busy sweep animation in its footer (the
status line says what is happening, and pactl reports no progress to
animate, so the sweep was a fiction).

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
