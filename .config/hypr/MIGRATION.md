# qtile → Hyprland migration status

Ported from `../qtile/config.py` (7,879 lines, 291 resolved bindings as
reported by `qtile cmd-obj -o cmd -f display_kb`).

Scope of this pass: **usable daily driver**. Window management, workspaces,
and every binding that did not depend on qtile's Python API or on X11.

## Numbers

> **Read the warning under the table before quoting any percentage from
> it.** The 42.3% row is a first-pass snapshot and has been wrong for a
> long time; it is kept because the denominators are still the right ones,
> not because the status is current.

Verified by diffing this config against qtile's own resolved binding table,
not by hand — see `audit.py` in the migration scratchpad.

**The first pass, as originally measured:**

| | count | |
|---|---|---|
| Bindings in qtile | 291 | |
| Implemented at that time | 123 | 42.3% |
| Deferred | 142 | 48.8% |
| Blocked (X11-only) | 26 | 8.9% |

Deferred broke down as 121 popup-chord bindings, 18 root bindings, and 3
nested chord entries. Blocked is Hintium (6 root + all 19 of Hint-Mode)
plus the xmodmap reapply binding.

**What the running config actually carries now**, from
`hyprctl binds -j` against the live session:

| | count |
|---|---|
| **Total live binds** | **244** |
| root (no submap) | 91 |
| inside a submap | 153 |

and the submaps are `rofi` 65, `resize` 21, `cheatsheet` 20, `media` 18,
`draw` 17, `lang` 11, `passthrough` 1.

### The two tables do not divide into each other, and that is the point

244 is not "123 grown to 244 out of 291", and anyone reading it that way
gets a wrong picture of the port in both directions. They count different
things:

- **The 291 is a qtile figure** — bindings resolved out of `config.py`.
  The 244 is a *Hyprland* figure, and this config has binds qtile never
  had (the island's own panels, the submap indicators, the layout cycle).
- **The deferred 121 popup-chord bindings were not ported one-for-one.**
  They were *replaced* by panels that answer the same need with a
  different, usually smaller, key surface — the cheatsheet came off rofi
  because "what rofi actually contributed was the typing, not the window",
  and four of qtile's sixteen cheatsheet bindings existed only to move a
  viewport. A panel that needs 4 keys where qtile needed 16 is progress
  that a binding count scores as regression.
- **Some qtile bindings were deliberately dropped**, not deferred. See
  "Deliberate behaviour changes" below.

So the honest status is not a percentage. It is: **every popup in the
deferred table below is now built** (see the table's own DONE markers),
the blocked set is unchanged, and what is genuinely outstanding is listed
in `REQUIREMENTS.md`'s "The genuinely open list" and in
`upgread_UI_UX.md`'s phases 3–7. A re-run of `audit.py` mapping qtile's
291 onto today's 244 has **not** been done; until it is, no percentage in
this file should be quoted as current.

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

**This table was measured with INLINE `dispatch exec` rules, and the "size
ok" in row three does not carry to a static `windowrule` line — see
"A percentage `size` rule is inert" in the fourth round below.** The
generalisation stood unchallenged here for three rounds.

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

**That claim was an assertion when it was written. It has now been
measured**, three ways, because "the tool cannot test this" is exactly the
kind of statement that quietly stops being true:

| experiment | result |
|---|---|
| `hyprctl keyword bind "SUPER,F9,exec,touch /tmp/x"`, then `wtype -M logo -k F9` | bind present in `hyprctl binds` at modmask 64; **file never created** |
| same with an unmodified `,F8` | **never created** — so it is not the modifier |
| enter `submap rofi` by dispatcher, watch `.socket2.sock`, run any `wtype` | `submap>>rofi` … then `submap>>` **the moment wtype runs** — the reset is real and it is caused by the virtual keyboard, not by the key |
| `wtype hello` into a focused `cat > file` with no submap active | `hello` arrives intact |

So the split is precise: **`wtype` reaches CLIENTS but not the compositor's
bind layer.** That is worth knowing in both directions — it is why the audio
and display panels can be driven and verified end to end by synthesising
keys (they are ordinary Wayland clients with keyboard focus), and it is why
`$mod P` cannot be. One more detail from the same run, in case it misleads
someone later: typing `insubmap` while the `rofi` submap was active landed
`nsubmap` in the client — the leading `i` was lost to the submap-reset race,
**not** consumed by the `i` bind, which was checked by confirming `dm-satty`
never ran.

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

**Honest status, unchanged after a second attempt: the cause is not proved
by reproduction, only by elimination plus a mechanism that produces exactly
the reported symptom.** The second attempt is the table above — it closed
off synthesis as a route rather than opening one, and no other route exists
on this machine. `ydotool`/`dotool` would work, because they inject through
`uinput` and Hyprland sees a real evdev device, but that means a new declared
package and a uinput permission change to test one keystroke. keyd is already
here and is a real evdev device, but 2.6.0 has no `keyd do` — it can only
rebind a key that a finger still has to press.

**So this needs the one thing an agent cannot supply: a human pressing the
key.** If a bare `p` still appears, run the listener below and press it for
real; that single observation decides it.
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

### Multi-monitor, verified at last — on a monitor that does not exist

Everything above this line was measured on ONE 1366x768 panel, and the
file said so. The second monitor turned out not to be needed:

```
hyprctl output create headless      # HEADLESS-1, 1920x1080, lands at 1366,0
hyprctl output remove HEADLESS-1
```

That is a real output as far as the compositor, the layer-shell clients
and `grim -o HEADLESS-1` are concerned, so all of it can be screenshotted
and looked at. **It found one genuine bug, which had been sitting in the
scratchpad script since it was written.**

#### `move` in a window rule is monitor-relative, and scratchpad.sh added the origin twice

`scripts/scratchpad.sh` resolved its percentages against the focused
monitor and added `monitor.x` / `monitor.y` to the result, with a comment
explaining that x/y are global compositor coordinates. They are not.
Measured, spawning kitty as an inline exec rule with HEADLESS-1 (at
1366,0) focused:

| rule | landed at |
|---|---|
| `move 100 100` | `1466,100` — the monitor's origin is added by Hyprland |
| `move 1500 200` | `2866,200` — same |

So a caller that has already added the origin gets it twice. This was
invisible for the entire life of the script because eDP-1 is at 0,0 and
zero added twice is still zero.

**The symptom is not the one you would look for.** A doubled offset is
usually off the monitor's edge, and Hyprland then places the window
somewhere else entirely — a 60%-wide scratchpad came back exactly centred
(`1750,216` where `1750,108` was asked for), which reads as "the `move`
was ignored", i.e. as the *old* percentage bug rather than as a new one.
The x coordinate matching perfectly is arithmetic, not luck: a 60% window
at 20% from the left is centred by definition.

Fixed by dropping `.x +` / `.y +` from the jq. Verified both ways after
the change, spawning the same scratchpad with each monitor focused:

| focused | got | want |
|---|---|---|
| HEADLESS-1 (1920x1080 @ 1366,0) | `1152x648 @ 1750,108` | `1152x648 @ 1750,108` |
| eDP-1 (1366x768 @ 0,0) | `820x461 @ 273,77` | `820x461 @ 273,77` |

#### What was already right

| check | result |
|---|---|
| island on both screens | **yes** — `shell.qml` puts `DynamicIslandWindow` in a `Variants` over `Quickshell.screens`; both got a notch, both centred on their own screen, both `reserved [0,38,0,0]`, one process |
| notch size on a bigger screen | stays 96 px — it does not scale with screen width, which is right; the flare is a feature of the island, not of the screen |
| toggling a scratchpad from the *other* monitor | the special workspace follows you: the window was translated 273 → 1639, i.e. by exactly the monitor delta, keeping its position relative to the screen. It keeps the size it was spawned with (60% of eDP-1, not of HEADLESS-1) — qtile's DropDown behaved the same way and this is not worth chasing |
| DisplayPanel enumerating two outputs | both listed with modes, position, scale, rotation |
| DisplayPanel `arrange` | `h` placed HEADLESS-1 left of eDP-1; `hyprctl monitors` agreed (eDP-1 → 1920,0), the countdown ran, "no answer — reverted" put both back at 0,0 / 1366,0 |
| the bar surviving both events | 1 notch before, 2 during, 1 after; screenshotted at each step |

The headless output is worth reaching for again. It is the only way to
test this class of thing on a laptop, and the failure it found was a
comment confidently describing the opposite of the truth — which no
amount of re-reading the script would have caught.

### Second round of reported breakage — what each one actually was

Seven things were reported as broken or missing after daily use. Only one
of them was a missing feature; the rest were **collisions and defaults**,
which is worth recording because they all presented as "the key does
nothing" or "the effect is not there".

#### The class `kitty` was doing three jobs, and they fought

Reported as "the term1/term2 scratchpads and the workspace-4 terminal
sometimes conflict". They did, and the mechanism is precise:

| claimant | rule |
|---|---|
| `rules.conf` | `workspace 4, match:class ^kitty$` |
| `$mod N` | `toggle-app.sh "kitty" 4` — **unanchored** |
| `$alt 1/2` | inline `workspace special:term1` |

`hyprctl clients` returns matches unordered, and `toggle-app.sh` takes
`.[0]`. When that was a scratchpad terminal, the script's special-workspace
branch ran `movetoworkspace 4` on it — **permanently pulling the terminal
out of its own scratchpad**, with nothing to put it back. The scratchpad
then reads as empty, so the next `$alt 1` spawns a second one. Verified by
running the matcher: with a scratchpad open, `$mod N`'s regex matched both
it and the real terminal.

Fixed at both layers. The scratchpad terminals spawn `--class
scratch-term1` / `scratch-term2`, which neither `^kitty$` nor the
unanchored `kitty` matches; and `toggle-app.sh` now excludes every window
on a special workspace, because a window living there is somebody else's
dropdown and never "the app, open somewhere". The dead `special:*` branch
went with it.

#### `$mod SHIFT S` only ever opened sum.md

qtile matched it by TITLE (`Match(title="nvimsum")`); this script matches
class, and `kitty --title nvimsum` has the class `kitty`. So the regex
`nvimsum` found nothing, every press took the not-running branch, and every
press spawned another editor. Now spawned with `--class nvimsum`. Verified
by pressing it three times: workspace 4 → S → 4 → S, one window throughout.

**Superseded, and the fix above was correct about the mechanism and wrong
about the target.** `nvimsum` is a string qtile has not used since
alacritty; the window it was chasing does not exist, so making the matcher
match it only made the port internally consistent. It also opened
`~/sum.md`, which is not a file on this machine. See "`$mod SHIFT S` was
ported from a Match that has never matched" in the fourth round below.

#### The browser scratchpads were never placed at all

Reported as "chatgpt/deepseek/whatsapp should behave like the terminal
ones". They could not, and no amount of geometry fixing would have helped:

**Hyprland attaches a `dispatch exec`'s `[...]` rules to the process it
spawns.** `brave --app=...` hands the URL to the already-running brave and
exits, so the window is created by a process Hyprland never spawned and
the rules match nothing. Measured: `[workspace 8 silent] brave --app=…`
put the window on workspace **4** — the active one — full tiled size.

`scratchpad.sh` now records the window list before spawning, polls for the
new address (0.25 s ticks up to 15 s, because a cold browser profile takes
seconds and a terminal takes 200 ms), and places it by address with
dispatchers, which do not care which process made the window. Verified:
`956x614 @ 205,77`, exactly 70%x80% @ 15%,10%, on the first press, and
toggling thereafter without respawning.

Two facts found on the way: **brave ignores `--class` for `--app` windows**
— it derives one from the URL and profile, e.g.
`brave-chat.openai.com__-Chatgpt` — and that class contains the substring
`brave`, so `$mod B`'s unanchored matcher claimed the scratchpads too. It
is `^brave-browser$` now.

#### The screenshot selection made the screen unreadable

`grim -g "$(slurp)"` with a bare `slurp`: its default background is a heavy
light wash over the whole screen, so during selection the desktop goes flat
grey and you cannot see what you are aiming at — which is the entire job.
Confirmed by screenshotting mid-selection, which works because the overlay
is an ordinary layer surface.

Now `slurp -b 00000040 -s 00000000 -c ffffffff -w 2 -d`: dim to 25% black,
a **fully transparent selection** so the crop shows real pixels, and a
white border, chosen because it has to be visible over 22 palettes.

#### hyprglass was working the whole time — the terminal was opaque

Reported as "the glass terminal did not work". The plugin was loaded, the
tag was applied, and the terminal was a flat rectangle. The measurement
that settles it:

| window | alpha 1.0 → 0.65 | meaning |
|---|---|---|
| glass **enabled** | **0** pixels changed | the window is opaque no matter what |
| glass **disabled** (`+hyprglass_disabled`) | max delta **156** | alpha works fine |

And with the same terminal at `background_opacity=0.25`, the full effect
renders — lens bulge, edge refraction, chromatic fringing, specular rim.

So: **glass refracts what is BEHIND a window, and `kitty.conf` sets
`background_opacity 0.95`.** Five percent of the background is not enough
to see anything through, and the result is identical with the plugin on and
off. Nothing in `hyprglass.conf` could have fixed it.

The opacity is set at the spawn site — `$term` in `binds.conf` carries
`-o background_opacity=0.70` — rather than in `kitty.conf`, which also
serves the qtile/X11 session where there is no glass to show through it.
Every route that opens a terminal goes through `$term` for that reason.
0.70 keeps text contrast; 0.55 shows more glass and reads washed out.

The class change above had a consequence worth noting: `hyprglass.conf`'s
`match:class ^(kitty)$` silently stopped matching the scratchpads the
moment they got their own classes, so they came back translucent with no
preset at all. The rule now names every class a kitty can have here.

#### `$mod /` genuinely did nothing — Media-Mode was never ported

The only real missing feature in the list. `binds.conf` had it commented
out with the deferred popups, on the strength of a binding count of 17 —
but eleven of those are the nine workspace keys every chord repeats plus
`q` and `Escape`. The real content is six keys, and five of them are volume
and brightness.

Now live as the `media` submap. Volume and brightness go through wpctl and
brightnessctl, the same path as the hardware keys, so one key cannot draw a
different OSD than the other; the numbers are qtile's (±5, 150% ceiling).
The sixth, `mpv_manager.toggle_pip_mode`, does not port — that module
imports libqtile and drives qtile's own window objects — so the behaviour
is reimplemented in `scripts/mpv-pip.sh` with **that file's constants**
(320 px wide, 20 px margin, 12 px stacking gap, 60%x50% centre mode).

`keep_above` becomes `pin`, which also carries the window across workspace
switches — replacing mpv_manager.py's whole `follow_to_new_group()` hook.
Verified end to end: 320x180 at the bottom-right corner, followed a
workspace switch while pinned, and toggled back to `819x384 @ 273,192`,
which is 60%x50% centred exactly.

The mode audit behind it, against qtile's own `KeyChord` list: fourteen
chords, twelve live. The two that are not are **Hint-Mode** (Hintium, see
below) and PASSTHROUGH-CONFIRM's `F13`.

#### The mode indicator said WHICH mode and never WHICH KEYS

`submap-indicator.sh` put `ROFI-MODE` in the capsule and stopped there.
That answers "am I in a mode", which is the question qtile's bar answered
and the one that matters most — without it the compositor silently swallows
keys. It is not the question you have while sitting in a 26-key chord.

The island now expands into a key list on entering any submap: mode name,
`Esc`, and every binding in up to three columns, read from `hyprctl binds`
through a new `cheatsheet.py --submap-json` so it cannot drift from the
config. `qml/island/ModeKeysLayer.qml`, with the traps in FORK-NOTES.md.

The one that matters here: **the panel takes no keyboard grab.** Every
other island panel takes an exclusive one because each reads its own keys;
this one must not, because the keys belong to the submap and a grab would
swallow exactly what the panel is drawn to advertise. Verified structurally
— it appears in none of the three focus lists — rather than by a keypress,
which as established on this machine needs a human.

The name-only capsule is kept as the fallback, and there is a third: if the
island is not up at all, dunst. Each falls through to the next.

#### $mod Tab was cycling the wrong layouts

qtile's `layouts` list has exactly three entries and `$mod Tab` was
`lazy.next_layout()` over them. What was here flipped `general:layout`
between master and dwindle — two layouts, neither of which is Max, and it
dropped the two the config spends most of its time in.

`scripts/layout-cycle.sh` maps all three onto what Hyprland has:

| qtile | here | measured |
|---|---|---|
| `MonadTall(ratio=0.75)` | master + `mfact 0.75` | master pane 1005 of 1346 px = 0.747 |
| `Max(border_width=0)` | a group, groupbar **off** | 3 windows grouped, all 1346x710 |
| `TreeTab(panel_width=180)` | a group, groupbar **on** | same group, focused window 21 px shorter and offset — the bar |

Hyprland has no Max and no tabbed layout, but a GROUP is exactly "several
windows in one tile, one visible at a time", so Max and TreeTab are one
mechanism with the tab bar hidden or shown. Two traps, both measured:

- **`togglegroup` is a toggle.** Max → TreeTab wants the same group, so
  calling the grouping path twice DISBANDED it — `grouped=3` then
  `grouped=0`, with a tab bar over three ordinary tiled windows. The
  grouping step is idempotent now.
- **`keyword master:mfact` does not re-lay-out existing windows.** It set
  the default for future arrangements while `master:mfact` read back a
  correct 0.75 and the master pane stayed at 0.55. `dispatch layoutmsg
  mfact exact` is what acts on the live workspace.

What this round got right about the three layouts, and missed about where
they live: qtile's layout is a property of the GROUP, not of the session.
That half arrived in the fourth round below, as `workspace-layout.sh`.

### Third round: four reports, and two of them were the same setting

Four things reported after more daily use. Two were unrelated bugs; the
other two turned out to be **one line of config** — `decoration:blur`
reaching further than the block it is written in.

#### "Max and TreeTab switch, but I cannot reach the app underneath"

Exactly right, and the layouts were never the problem. layout-cycle.sh
builds both out of a Hyprland GROUP, and

**`movefocus` moves between TILES, and a group is one tile.**

So with three windows grouped, all four direction keys had nowhere to go
and the two windows behind the visible one were unreachable — which is the
entire point of Max and TreeTab. Measured, three windows grouped on a
headless output:

| | |
|---|---|
| `movefocus d` | focus stays on `grouptest2` — no movement at all |
| `changegroupactive f` | `grouptest2 → grouptest3` |

`changegroupactive` is what walks the stack inside a tile and nothing was
calling it. `scripts/focus-move.sh` now picks the dispatcher by asking
whether the FOCUSED WINDOW is grouped — a fact about the window, true
exactly when layout-cycle.sh has put the workspace in Max or TreeTab, and
also true for a group made by hand, which reading the layout name would
have missed.

The mapping is qtile's own, from config.py's `.when(layout=...)` pairs:
in Max and TreeTab all four keys cycle (`h`/`k` back, `l`/`j` forward);
in MonadTall they are ordinary directional focus. Verified both ways —
grouped: `2→3→1→2` forward and back; ungrouped: j/k walk the stack and
h/l cross to the master pane.

#### The screenshot selector blurred the whole screen

Reported before and "fixed" before, with four slurp flags. Those fixed the
wrong thing — a heavy light WASH — and the blur stayed, because **the blur
was never slurp's**:

**Hyprland's blur applies to layer surfaces, not just windows.** slurp's
selector is a full-screen one (`level 3, ns='selection', 1366x768`),
translucent by design, and `ignore_opacity = true` guarantees it gets
blurred regardless. A/B on the identical 460x160 crop, selector up:

| | |
|---|---|
| `layerrule = blur true` | an unreadable teal smear |
| `layerrule = blur false` | crisp, every character legible |

Two lessons, both cheap to forget: a layerrule is the fix, not a client
flag; and `layerrule = noblur, selection` is the OLD syntax — this config
is on the `match:` form, so it is `blur false, match:namespace
^(selection)$`, and the old form fails with the deeply unhelpful "invalid
field noblur: missing a value".

#### The glass terminal was frosted, not glass — and looks.conf said so

hyprglass 1.0.0 loaded, tags applied, and the terminal a soft frosted
wash. The cause was written in looks.conf months ago and never acted on:

> hyprglass replaces this entirely; it cannot run alongside native blur on
> the same windows. **When the plugin is enabled, set enabled = false here.**

The plugin was enabled. `decoration:blur:enabled` still read `int: 1`.
Both claim the same window, the gaussian pass runs, and you get frosting
where refraction should be — the plugin never had a sharp background to
bend. A/B on the same crop:

| | |
|---|---|
| blur on | the wallpaper behind the terminal is a smooth wash, no detail |
| blur off | individual cherry blossoms resolve through the window |

Note this is the SECOND time this window has been chased for the wrong
reason: the previous round found `background_opacity 0.95` and fixed it at
the spawn site. That was real and necessary, and it was not sufficient —
opacity gave the window something to see through, and native blur then
smeared it.

#### The browser scratchpads glitched; the terminals never did

Measured, cold-spawning the whatsapp one and polling every 50 ms:

| t | where |
|---|---|
| 1.20s | workspace **4** — the active one — **TILED**, 735x715 |
| 1.51s | `special:whats`, floating, 956x614 @ 205,77 |

So for ~310 ms it is a real tile on whatever workspace you are on, shoving
the layout aside before vanishing. scratchpad.sh's polling fallback cannot
do better in principle: it only ever acts AFTER the window exists, and it
exists on the wrong workspace.

A windowrule has no such limitation — it is matched as the window maps,
whoever created it, which sidesteps the whole `brave --app` problem (the
URL goes to the already-running brave, so rules attached to the spawned
process match nothing). The classes brave derives are stable and were read
off the live windows rather than guessed. After:

| t | where |
|---|---|
| 0.89s | `special:whats`, floating, straight away |
| 1.14s | 956x614 @ 205,77 — the script's pixel geometry, on a hidden workspace |

Zero frames on the active workspace. scratchpad.sh keeps the pixel
placement because percentage `size`/`move` still do not apply on a special
workspace; the difference is that it now happens where nothing can see it.

### Every dispatch the island made was silently rejected

Found by reading the shell's log while checking something unrelated, which
is the only way it was going to be found:

```
Dispatch request "hl.dsp.focus({ workspace = 3 })"
    failed with error "Invalid dispatcher"
```

`qml/common/HyprlandDispatch.qml` emits Hyprland's **Lua dispatch API** —
`hl.dsp.focus`, `hl.dsp.window.move`, `hl.dsp.window.close`. **0.56.2 does
not have it.** So clicking a workspace on the island did nothing, scrolling
the notch to change workspace did nothing, and focusing or closing a window
from the overview did nothing. All of it had never worked under this
compositor.

Nothing about it is visible from the outside: no exception, nothing drawn
wrong, no error dialog. The click simply does not land, which reads as a
dead widget rather than as a bug with a cause.

Rewritten to the classic dispatchers, each one exercised against this
compositor before being trusted. The decisive pair, run back to back:

| dispatch | result |
|---|---|
| `workspace r+1` | `ok` — workspace went 4 → 5, and back on `workspace 4` |
| `hl.dsp.focus({ workspace = 3 })` | **`Invalid dispatcher`** |

Three translation details worth keeping:

- **The workspace is no longer lua-quoted.** A classic dispatcher takes a
  bare token — `workspace 3`, `workspace special:term1`, `workspace r+1` —
  and a quoted `"special:term1"` is not a workspace Hyprland can find. The
  relative forms the notch's scroll handler uses (`r-1`/`r+1`) only work
  unquoted, which the table above is measuring.
- **`follow` picks the dispatcher, it is not a parameter.**
  `movetoworkspace` versus `movetoworkspacesilent` are two dispatchers, and
  the silent one is the one that does not drag you along.
- **A relative `movewindowpixel` needs an explicit sign.** Without a `+`
  Hyprland reads the number as absolute, so the positive case is prefixed
  rather than left to `String()`.

If this fork is ever rebased onto a Hyprland that has the Lua API, upstream's
form is the better one to restore — it is properly typed instead of string
concatenation. It is just not available here.

### The volume/brightness OSD, restyled onto the timer's ring

Asked for directly: reuse "the ring circle of the timer" for volume and
brightness. The ring was already shared — `qml/common/ProgressRing.qml`,
extracted from the OSD's inline Canvas so the display panel could use it —
so the gap was not the component but the LAYOUT it was given.

| | before | after |
|---|---|---|
| icon | text, far left | inside the ring |
| value | text beside icon | text beside ring |
| ring | 30 px, hard right | `height * 0.62`, left, `lineWidth` 4 |

The old arrangement put three things in a row and gave the smallest, most
distant slot to the ring — the one element that shows a QUANTITY without
being read. The number carried the information; the ring was decoration
beside it. The timer page (`ExpandedPlayerLayer.qml` ~798) had already
solved this with one large ring and the value centred inside, which is the
shape a radial indicator wants.

`ProgressRing` needed no changes: `centerContent` is its default property
alias and its centre slot is already sized to 62 % of the ring, so the
glyph needs no measurements of its own.

Two decisions worth keeping:

- **The ring is sized off the capsule, not a literal.** `islandHeight` is
  user-editable from the settings panel now, and a fixed 30 would overflow
  a shorter notch and float in a taller one.
- **It stays LEFT rather than moving to the timer's centre.** This capsule
  is the resting notch width, so a centred ring puts the value exactly
  where the clock lives — and a volume nudge would read as the clock
  changing.

Measured at two levels, with the volume restored to its original 0.79 both
times: 74 % and 54 % render the arc at the matching fraction with the
speaker glyph inside it.

### The media card's album art, and the handoff that made it findable

The size pass left `ExpandedPlayerLayer.qml` computing a `preferredHeight`
that nothing read. The capsule's `expanded` case was still the literal
`Metrics.px(190)`, and that literal was the last thing holding the album
art below spec:

| | |
|---|---|
| DESIGN-SPEC.md asks for | 88 px of art |
| upstream drew | 60 in source, `Metrics.px(60)` = **55 on screen** |
| the card wanted | `chrome + 88` |
| 190 left room for | **67** — so the art clamped itself down |

The art size is a `min()` against the height it is actually given, not a
flat `Metrics.px(88)`. That clamp is why nothing looked broken at any
point: a flat 88 would have drawn a card taller than the shape holding it
and the capsule's `clip: true` would have eaten the transport row — the
same failure the 190 literal's own comment records happening at 122. So
the card sat at the floor instead of overflowing, which is the polite
failure and also the invisible one.

Now `expanded` reads `expandedPlayerLoader.item.preferredHeight`, with the
literal kept as the fallback for the frame before the loader exists.
Measured: the layer surface goes 190 → 212 and the transport row renders
complete.

**Worth recording as a working practice, not just a fix.** The layer was
written by a pass that was scoped OUT of `DynamicIslandWindow.qml`, so it
could not finish the job. Rather than leaving the number wrong silently,
it clamped defensively and wrote the completion into the comment — "81 the
moment the capsule reads preferredHeight below". That sentence is what
made this a two-minute fix instead of a rediscovery.

### The two panels that were already right

`wallpaper_picker` and `application_launcher` share the literal
`Metrics.px(260)` and were the last two on the list. Both were opened and
looked at rather than assumed to be wrong by symmetry with the theme
picker, and **neither is**:

- the wallpaper picker is a **coverflow carousel** — one enlarged, named
  centre tile with dimmed neighbours running off both edges. Nothing is
  below a fold; the design is horizontal and the height is exactly one
  tile plus its caption.
- the application launcher is a **search field above one scrolling row**
  of icons. Same shape of answer: the overflow is sideways and deliberate.

The theme picker's bug was 6 rows of a GRID given the height of 4, which is
a different thing entirely from a horizontal layout that runs off the edge
on purpose. Left alone, and this note is here so the next pass does not
"fix" them into vertical lists.

### A Hyprland variable used above its definition fails SILENTLY

Found while binding the island's power menu onto qtile's `$mod SHIFT Q`,
and worth its own section because nothing reports it.

`binds.conf` defines `$qsi = qs -p ~/.config/... ipc call` at line 332,
with the other panel bindings. `$mod SHIFT Q` lives at line 48, ~280 lines
ABOVE that. Writing `bind = $mod SHIFT, Q, exec, $qsi tide togglePowerMenu`
there:

- reloads with **empty `hyprctl configerrors`**
- stores the bind with the **literal text** `$qsi tide togglePowerMenu`
- and therefore runs a command that does not exist, on a key that used to
  work

**`hyprctl binds -j` is the only place the difference is visible.** The
same variable used BELOW its definition expands normally, so a file can
contain both behaviours at once — which is exactly what happened here:

| bind | line | stored arg |
|---|---|---|
| `$alt 6` calendar | 418 | `qs -p ~/.config/... toggleCalendar` |
| `$alt 7` settings | 419 | `qs -p ~/.config/... toggleSettings` |
| `$mod SHIFT Q` power | 48 | **`$qsi tide togglePowerMenu`** |

Variables also do not cross files: `submaps.conf` cannot see `$qsi` at
all, wherever it is defined. Both power-menu bindings are written out in
full for that reason.

The general lesson is the one this file keeps relearning: a config that
reloads cleanly is not a config that works. `configerrors` being empty
proves the parser was happy, not that the binding does anything.

### The chord HUD — and a bug whose first two explanations were both wrong

`submap-indicator.sh` answered "am I in a mode" and nothing else. That was
the half that was actually missing, and it stays; but it is not the
question you have while standing inside a 26-key chord, which is "and
what are the keys". qtile got away with the name alone because its chords
were one-shot and its cheatsheet was one keystroke away. Hyprland submaps
are sticky, so you sit in them, and the cheatsheet here is itself behind a
chord.

So: `qml/island/ModeKeysLayer.qml`, the island's `mode_keys` state, driven
off the same event socket the indicator already watches. The rows are read
from the compositor — `cheatsheet.py --submap-json` over `hyprctl binds` —
for the same reason the printed sheet reads itself. **The layer takes no
keyboard focus**, which is the one thing it must get right: the keys
belong to the submap, and a grab here would swallow the very keys the
panel is drawn to advertise.

Three backends, best first, each falling through: the key panel needs the
island and a submap with bindings; the capsule needs only the island;
dunst needs neither.

#### Quickshell's IPC splits arguments on whitespace

The first version sent the rows as a second IPC argument. They never
arrived: shell quoting does not survive the split, so the rofi chord's
rows — actions reading "wifi panel", "theme picker" — arrived as **27
arguments instead of 2** and were rejected. A one-parameter call gets the
remainder joined back up, which is why `tide showText "hello world"` works
and hides the problem completely. Percent-encoding got past the argument
count and still produced empty rows, at which point the transport had cost
more than it was worth. The IPC now carries only the mode NAME, which is
one word and cannot have this problem, and the panel runs the backend
itself — the pattern every other panel here already uses.

#### One mode behind, and the two explanations that were not it

Going from one chord straight into another drew the NEW mode's name over
the OLD mode's keys. Measured, each step given two seconds to settle, so
none of this is a race with a slow `hyprctl binds`:

| shown | rendered |
|---|---|
| `lang` (from idle) | its own 4 rows — correct |
| `rofi` (while up) | **lang's 4 rows** |
| `media` (while up) | **rofi's 26 rows** |

Every FIRST press was correct and only the second one lied, which is the
worst shape this bug can have — the Loader builds the layer fresh on entry
from idle, so there is nothing stale to catch.

Two explanations were tried and **both were wrong**, which is the reason
this is written down:

1. *"`running = true` on an already-running Process is a no-op, so the
   second fetch never happened."* No. Two seconds is far longer than the
   fetch takes, and adding `running = false` first moved the numbers not
   at all.
2. *"`command` was bound to `modeName`, and QML runs a change handler
   before re-evaluating the bindings that depend on the same property, so
   the process started against the previous name."* Plausible, and also
   no: assigning `command` imperatively an instant before `running = true`
   produced the identical sequence.

What both share is a **reused `Process`, and with it a reused
`StdioCollector`** — a collector that has already finished one stream is
what hands back the previous run's text. Creating the pair fresh per fetch
removes the reuse instead of trying to sequence around it, and it is why
`command` could go back to being an ordinary binding: it is evaluated at
construction, when `modeName` is by definition already the new one.

Verified after a reboot, through the real submap path rather than the IPC:
idle 55 px → `rofi` 232 → `lang` 137 → reset 55, with `lang` showing its
own four rows immediately after rofi's twenty-six.

#### A note on testing this, learned the hard way

`hyprctl dispatch submap rofi` puts the LIVE session into that submap, and
it stays there until something resets it. Anything typed in between is fed
to the chord — a stray `c` opened the theme picker and changed the session
theme mid-measurement, which then contaminated the next three readings and
looked like a QML bug. Drive the panel through `tide showModeKeys` when
testing the panel, and reserve the real submap path for one short,
deliberate pass.

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

### Fourth round: scroll direction, the summary window, and per-workspace layouts

Three reports. The first was one inverted boolean. The other two were both
**ports built on a piece of qtile config that has been dead for years**,
and in the second case this file's own percentage matrix turned out to be
over-general.

#### Scrolling was inverted, and only on the touchpad

X11 decides what "right" means here, so it was read rather than guessed.
The whole of `/etc/X11/xorg.conf.d/30-touchpad.conf`:

```
Section "InputClass"
    Identifier "Touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
EndSection
```

One option, and it is not `NaturalScrolling` — which is absent, and whose
xf86-input-libinput default is **off**. The only other file in
`xorg.conf.d` is `00-keyboard.conf`. So qtile/X11 scrolls the traditional
way on both devices, and `input.conf` had `natural_scroll = true`.

**Two settings, not one**, which is the part that makes this easy to
half-fix. Measured before the change:

| option | before | after |
|---|---|---|
| `input:natural_scroll` (mice) | `int: 0  set: false` | `int: 0  set: true` |
| `input:touchpad:natural_scroll` | `int: 1  set: true` | `int: 0  set: true` |

The mouse was already correct — by DEFAULT, not by decision. It is written
out explicitly now anyway: an option that is right only because nobody set
it is one upstream default change away from being wrong.

`scroll_factor = 0.5` is left alone and is a deliberate deviation. X11 has
no scroll-factor knob at all (autostart.sh drove it with an `xinput
set-prop` scroll-distance loop, dropped in the port), so there is no qtile
number to match; the report was about direction, and this is speed.

#### `$mod SHIFT S` was ported from a Match that has never matched

The binding opened `~/sum.md`. **That file does not exist on this
machine.** qtile's is

```
todos_dir = ~/${USER^^}TODOS     ->  ~/ATITODOS
sum_file  = todos_dir/TODOS.md   ->  ~/ATITODOS/TODOS.md
```

— 813 bytes, syncthing-backed, and the thing the phone syncs into. So the
key opened an empty buffer at a path nothing else reads or writes.

The deeper error is that the port was routed through `toggle-app.sh` onto
workspace S, on the strength of `Group("S")`'s `Match(title="nvimsum")`
(config.py :6955). **That Match is dead config in qtile.** The window is
spawned by `scripts/sum_app.py` as

```
kitty --name sum-md --class sum-md --title sum.md \
      -e nvim -c':set nonumber norelativenumber' <file>
```

and kitty's `--title` overrides the program's own, so the title is
`sum.md` and the class is `sum-md`. Nothing has been called `nvimsum`
since alacritty was replaced by kitty — the only other mention in the file
is a commented-out Match at :6896. Group S cannot claim this window and
never has.

What actually governs it is `float_rules` (`Match(wm_class="sum-md")`),
the `_float_and_center_sum` hook, and `toggle_or_spawn_sum`'s first branch,
which does `win.togroup(qtile.current_group.name)`. **The window follows
you.** qtile's own `desc` says so: "Open or focus sum.md *globally*".

So the behaviour is: floating, centred, 55%x65% of the screen, on the
CURRENT workspace, and minimize-on-second-press. `scripts/sum-toggle.sh`
now does exactly that; `toggle-app.sh` could not, being workspace-centric
by design (go to where the app is, bounce back), which is right for
Obsidian and wrong for a global scratch buffer.

Verified end to end against the live compositor, one window throughout:

| press | result |
|---|---|
| cold | `ws=4 float=true 751x499 @308,151`, title `sum.md`, class `sum-md` |
| screenshot of it | nvim's statusline reads `ATITODOS/TODOS.md` |
| focused → press | `special:sum` |
| press | back on `4`, `751x499 @308,151`, focused |
| press ×2 more | stash, restore — geometry identical |
| moved to ws 5 by hand, press from 4 | back on `4`, active workspace unchanged |

751x499 is 55% x 65% of 1366x768 exactly. 308,151 is centred.

**Minimize becomes a special workspace.** Hyprland has none, and
`special:sum` is this config's standing answer for "present but not on
screen".

##### The branch order is load-bearing, and the first version deadlocked on it

Asking `addr == activewindow?` first made the key stash the window and
then never get it back: press 2 and press 3 both left it on `special:sum`,
measured. The cause:

**`movetoworkspacesilent` to a special workspace leaves the window as
`hyprctl activewindow`.** It is off screen, on a hidden workspace, and
still the active window — so the next press matched the focused branch and
stashed something already stashed.

qtile cannot have this bug: `qtile.current_window` is a property of the
current GROUP, so a minimized window on another group is never it. The
port of that guarantee is to ask "is it on this workspace" before "is it
focused". `toggle-app.sh` carries a note about the mirror-image mistake —
`focusHistoryID == 0`, which is global, used where `activewindow` was
wanted.

##### A percentage `size` rule is inert — and this file said it was not

The "Percentage `size` / `move` window rules are silently inert" table
above records `percent | normal | size ok, move ignored`. That was
measured with **inline `dispatch exec` rules**, and the conclusion does not
carry to a static `windowrule` line. Measured back to back, same kitty,
same workspace, 1366x768:

| form | result |
|---|---|
| `windowrule = size 55% 65%` | `735x715` — **ignored** |
| `windowrule = size 751 499` | `751x499` — applied |
| `[float; size 55% 65%] exec` | `751x499` — applied |

So the split is by RULE SITE, not only by workspace kind: percentages work
in inline exec rules and not in static windowrules. `sum-toggle.sh`
therefore resolves 55%x65% against the focused monitor and passes pixels
inline, which is the shape `scratchpad.sh` already uses — and it works for
kitty for the same reason it fails for `brave --app`: inline rules only
attach to a process Hyprland itself spawned.

`center true` DOES work as a static rule and stays, so a summary window
opened by any other route is still placed. Verified: a 735-wide window
landed at x=316, which is `(1366-735)/2`.

#### Per-workspace layouts, which qtile had and this config had none of

Every qtile Group declares its own layout and the layout follows the
group. The port had one global piece of state that whatever you last
pressed `$mod Tab` on decided for the session.

From `groups = [...]` (config.py :6851-6960):

| ws | layout | ws | layout |
|---|---|---|---|
| 1 | monadtall | 6 | monadtall |
| 2 | **max** | 7 | monadtall |
| 3 | monadtall | 8 | **max** |
| 4 | monadtall | S | **max** |
| 5 | **max** | 9 | monadtall\* |

\* Group("9") declares no layout, so qtile falls back to `layouts[0]` —
MonadTall. Not a guess: the list opens with ten commented-out layouts and
MonadTall is the first live entry.

Worth noting because it is not what a quick read suggests: **2, 5 and 8
are Max too**, not just S. Browsers, brave, and documents. qtile spells
out the reason for 8 — "a document is one thing you read at a time, and
monadtall's side column would hand half the width to whatever else
happened to be open".

##### There is no per-workspace layout to set, and the syntax that looks like there is fails silently

```
hyprctl keyword workspace "7, layout:master"   ->  ok
hyprctl configerrors                           ->  empty
```

and nothing happens. **A workspace rule accepts unknown keys and discards
them** — the same failure shape as the percentage rules above, and just as
invisible. The keys the binary actually enumerates are `monitor`,
`default`, `defaultName`, `gapsin`, `gapsout`, `border`, `bordersize`,
`rounding`, `decorate`, `shadow`, `persistent`, `on-created-empty`. There
is a `layoutopt:` prefix and it carries orientation for master/dwindle,
not a layout name.

##### So it is a daemon, and not a wrapper around the workspace keys

`scripts/workspace-layout.sh` watches the event socket — the same one
`submap-indicator.sh` reads — and calls `layout-cycle.sh apply` on
`workspacev2`, `focusedmonv2` and `openwindow`.

Wrapping `bind = $mod, 2, workspace, 2` was the obvious alternative and it
covers the keys and nothing else. Workspaces here are also reached by
`toggle-app.sh` (seven binds), by `rules.conf` filing an app onto its home
workspace, by clicking or scrolling the island, and by dispatchers run by
hand. qtile's layout followed the group down all of those, because it was
a property *of* the group. It also keeps the workspace binds as plain
dispatchers, which matters on the hottest keys in the config.

**`openwindow` is in the list on purpose.** Without it a Max workspace
stops being Max the moment a window opens on it: Hyprland tiles the
newcomer beside the group rather than into it, and you are looking at a
split screen on a workspace whose entire point is that you are not. qtile
had no such problem — Max is a layout, so it owned every window the group
received.

`layout-cycle.sh` changed shape to match: its state file became a
directory with one entry per workspace, `apply` restores the remembered
layout (falling back to the qtile table above), special workspaces are
skipped, and `ungroup_all` gained the same `grouped_count` guard
`group_all` already had — without it, every arrival on a monadtall
workspace fired a `focuswindow` + `moveoutofgroup` per window to achieve
nothing. It also saves and restores the focused window, because walking a
workspace with `focuswindow` was tolerable on a keypress and reads as the
compositor losing your place when it happens on every switch.

Verified on a headless output, so the live session's screen never moved
(`hyprctl output create headless`, three then four kitties on workspace 8):

| step | result |
|---|---|
| before switching to 8 | `grouped=0/3`, sizes `599x352 599x351 735x715` |
| `workspace 8` (qtile default: max) | `grouped=3/3`, all `1900x1027`, groupbar `int: 0` |
| a 4th window opens on 8 | `grouped=4/4` — it joined the group |
| `$mod Tab` → treetab | groupbar `int: 1`, focused window 21 px shorter |
| `$mod Tab` → monadtall | `grouped=0/4`, master `1420` of `1900` = 0.747 |
| set 8 back to max, go to 7, return to 8 | 7 reads `monadtall`, 8 still `max` and `grouped=4/4` |

The last row is the one that matters: the layout is per workspace and a
`$mod Tab` on one does not follow you to another.

**Known rough edge, not fixed:** `group:groupbar:enabled` is a global
option, so a monadtall workspace inherits whatever the last max/treetab
workspace set. It is invisible unless you have made a group by hand on a
monadtall workspace, which nothing in this config does.

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

> **This is now LIVE**, all six root bindings and the whole Hint-Mode
> chord (as the `hint` submap on `$mod SHIFT F`). The "Wayland forbids
> both by design" premise below was half right: it does forbid reading
> the window tree cold, but `hyprctl -j` answers that directly instead
> (`hintium/hypr.py`, preferred whenever `HYPRLAND_INSTANCE_SIGNATURE` is
> set) — no protocol workaround, just asking the compositor. And it
> turned out synthesising clicks needed no change at all: wlroots
> forwards XTest sent over the rootless XWayland connection into the
> real compositor seat, which affects the focused window whether it is
> XWayland or native. `hintium/x11.py`'s click/key code is untouched.
>
> A second bug turned up once that one was fixed: the overlay itself is
> a plain GTK toplevel, and xdg-shell has no equivalent of X11's DOCK
> type hint, so this tiling compositor tiled it like any other window —
> hints landed in a small tiled box instead of over the real screen.
> Fixed with `gtk-layer-shell`: the overlay is a real layer-shell surface
> now (`hintium/overlay.py`'s `init_fullscreen_layer`), which any wlroots
> compositor exempts from tiling by construction — this half is not
> Hyprland-specific at all, unlike the `hyprctl` half above.
>
> `~/.local/share/hintium` is a symlink into `~/Attia-Pro/Projects/Hintium`
> now, not a second stale clone — it used to be one, silently running
> old code every time something resolved `hintium` through PATH.
> `$HINTIUM` in `binds.conf` points at the Projects path directly. See
> that project's README (Limits) for what's still Hyprland-specific
> rather than generic Wayland — window switching chief among them — and
> for the multi-monitor caveat: a layer-shell surface belongs to one
> monitor by protocol design, untested here for lack of a second one.

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
| WallpaperPopup | 9 | **DONE** — `WallpaperPickerLayer.qml`, 362 images, not `waypaper` |
| Cheatsheets (Qtile/Vim/Fish) | 16 | **DONE** — in the island, not rofi; see below |
| UpdatesPopup | — | `qupdate.py` daemon still runs |

These are the natural second phase, rebuilt as Quickshell/QML pages inside
the Tide-island bar — which is where they arguably belong anyway.

> **The whole table is now DONE, and two of its rows were stale for
> months.** WallpaperPopup said `waypaper`; the island has shipped its own
> picker for a while, routed through `hypr/scripts/wallpaper-set.sh` so
> both sessions agree on `~/.cache/wall`. The cheatsheet row said "rofi",
> which was true of the interim and is not true now — it came off rofi
> deliberately, and that argument is written up under item 3 of
> `REQUIREMENTS.md`.
>
> The heading still says "Deferred: the 13 popups" because that is what
> this section was; treat the heading as history and the table as status.

### Wi-Fi and Bluetooth were already built, and simply unbound

The island's control centre owns both lists — scan, signal strength,
connect, the lot — and they were reachable only by opening the control
centre and clicking a chevron. 26 bindings' worth of function was sitting
there with no key on it.

`tide toggleWifiPanel` / `tide toggleBluetoothPanel` open the list, bound
to **`n`** and **`b`** in the rofi submap, which are the keys qtile's
WifiPopup and BluetoothPopup had.

That used to mean "open the control centre and then its sub-panel", and
this section carried an implementation note about how the two could not
happen in the same tick. Both are gone. The lists are island states of
their own now — `wifi_panel` and `bluetooth_panel`, loaded by
`ConnectivityPanelLayer.qml` — so pressing `n` puts a network list on
screen and nothing else. The control centre stays mounted underneath as
their data provider, invisible, because `wifiController` and the Bluetooth
adapter live there; it is no longer drawn as a side effect of asking for a
network list. Clicking the Wi-Fi or Bluetooth row inside the control
centre opens the same popup, so there is one list with two ways in.

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
edge, top corners square, a 9 px concave flare each side.

> **It is no longer "pure black", and that is a decision, not drift.**
> The island fill follows the palette — `IslandTheme.shellFill`, the
> background darkened toward black by 0.45 with an 0.08 accent mix,
> measured across four palettes. It is a direct user override of
> `DESIGN-SPEC.md`'s rule that the notch must stay `#000000`, and
> `upgread_UI_UX.md` Part 3 lists it among the things that look like
> inconsistencies and must not be "fixed" back.
>
> The resting CONTENT has also moved on from the spec, also deliberately:
> it is the layout glyph, the clock, the workspace digit and the flanking
> app pucks — not the spec's clock + 4-bar EQ.

Four things landed in the fork that no config key could reach — the notch
morph, a generated spring, arbitrary text, and a theme picker. Each is
written up with its traps in `tide-island-fork/FORK-NOTES.md`, which is
also the merge list for the next `pacman -Syu` of `tide-island`.

**That list of four is now badly out of date** — the fork has since taken
over notifications from dunst, replaced every hardcoded colour with a
derived token layer, gained a system monitor, a display panel, an
application launcher and a layout indicator, and had its theme-change
animation rebuilt twice. `FORK-NOTES.md` is still the merge list; treat
"four things" as the state at the time of writing and the git log as the
truth.

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

## The island's motion, and why it read as "too bad"

The complaint was about feel, so it was measured rather than reasoned
about: `grim` frames of a single transition, each filename carrying the
milliseconds since the IPC call that started it (`date +%s%N` taken from
*inside* the capture loop — taken outside it, the ~30–300 ms a `qs ipc
call` process takes to start makes two runs of the same transition
disagree by 130 ms, which cost one wrong conclusion before it was caught).

Closing the theme picker, **before**:

| t | what is on screen |
|---|---|
| +58 ms | capsule still ~700 px wide, the 22-tile grid **already gone**, the resting clock **already fully opaque** inside it |
| +196 ms | capsule fully collapsed to the notch |

Opening it, **before**:

| t | what is on screen |
|---|---|
| +69 ms | capsule barely wider than the notch, "Theme" header already painted and clipped by the shape's own `clip: true` |
| +138 ms | capsule near full width, still only the header |
| +272 ms | full grid |

Content was not fading in either direction. It teleported, and it
teleported at the wrong end of the morph both times.

### Cause 1 — the out-fade had never once executed

Every panel layer fades itself with `opacity: showCondition ? 1 : 0` and a
`Behavior`. Every panel was mounted by `Loader { active: <the same
boolean> }`. So the instant `showCondition` went false and queued the
fade, `active` went false in the same event-loop turn and **destroyed the
item that was about to run it**. Thirteen layers carried a carefully tuned
out-duration and all thirteen were dead code.

`qml/common/PanelLoader.qml` is the fix: `live` drives `showCondition`,
`active` is `live || <a fade-out is still in flight>`. The hold is a bounded
Timer and not `active: live || item.opacity > 0.01` — the elegant version
self-times perfectly for a layer that fades and *never unloads* one that
forgets to, which is a leak presenting as "the shell got slow".

### Cause 2 — twenty layers, twenty different clocks

Counted across the fork: **eight** distinct fade-in durations
(160/180/200/220/240/260/280/300) and **six** fade-out durations
(100/120/130/140/150/200), all on `Easing.InOutQuad`, none derived from the
400 ms the shape takes. A state change ran three clocks that disagreed —
old content, new content, and the capsule.

`Motion.js` grew a "content choreography" section: one in-duration, one
out-duration, and a 90 ms **delay** before content fades in. The delay is
the load-bearing part — it is what stops the panel being painted inside a
capsule that is still the wrong size — and it is under the ~100 ms
threshold at which a response stops feeling immediate.

### Cause 3 — the spring existed and most of the shell ignored it

`Motion.js` had solved the damped harmonic oscillator months ago and
published `spring` (ζ 0.8, geometry) and `fade` (ζ 1.0, opacity). An audit
found **66 raw `easing.type: Easing.*`** still in place. 49 were
transitions and are now converted, classified strictly by what the property
*is*:

- **spring** — `width height x y scale rotation radius`, plus the 0–1
  values that drive a *position* (`animatedGroupShift`, `pageProgress`, the
  timer bubble's `reveal`).
- **fade** — opacity and colour, plus every 0–1 value that is *clamped* the
  way opacity is: `displayedVolume`, `displayedBrightness`,
  `batteryDrawerProgress`, `animatedProgress`, `slashProgress`,
  `lyricChangeProgress`. A volume slider is not opacity, but it is bounded
  at both ends exactly like it, and a spring's 1.5 % overshoot at 100 %
  draws a fill wider than its own track for ~100 ms.

17 raw easings remain **on purpose** and are listed with their reasons at
the bottom of `Motion.js`: a looping breathe has no step response, a
hand-choreographed star pop already has its overshoot authored into the
keyframes, and the theme wipe's radius must stay monotone or the circle
re-covers the screen it just revealed.

### Cause 4 — the layer surface was sized for the target, not the overshoot

`capsuleWindowHeight` is built from `targetHeight` — the value the spring is
travelling *towards* — while a ζ 0.8 spring deliberately goes 1.54 % past
it. The old flat `+ 12` slack happened to cover the two extremes here (the
audio panel overshoots 5.1 px, the cheatsheet 6.5 px) but would have
stopped covering them the moment a panel passed ~780 px. `Motion.overshoot()`
now publishes the number and the slack is derived from it. `windowShrinkTimer`
went from a magic `1000` to `morphDuration + fadeOutDuration + 32`.

### Cause 5 — the chord HUD grew twice

Opening the `rofi` chord, **before**: at +70 ms the capsule was at full
width and **35 px tall** — the header and nothing else — and at +204 ms it
was 145 px and still growing. Two height animations for one open, because
`keys` is cleared the moment the submap name changes and `cheatsheet.py`
answers ~130 ms later, so the capsule sized itself to "zero rows" in
between. The window now remembers each submap's height across opens and
hands it back as `pendingHeight`; **after**, the box is at its final height
by +100 ms. A first-ever open of a given chord still steps — once per mode
per session rather than every time.

**After**, closing the theme picker at +73 ms is a genuine cross-dissolve:
the grid at ~25 % opacity, the clock coming up, the box mid-collapse.

## Transient OSDs no longer replace an open panel

A "Workspace 4" capsule was observed replacing the chord HUD mid-chord.
The HUD was correctly listed in `blocksTransientSplit` and it made no
difference, because **only one of the four entry points consulted that
list**. `showWorkspaceCapsule`, `showNotificationCapsule` and
`showBluetoothExpanded` each carried their own hand-written

```
if (islandState === "control_center" || islandState === "notification") return;
```

written before any of these panels existed and never extended. So a volume
OSD was blocked and a workspace switch was not — the worst possible split,
since the chords themselves bind `1-9 workspace`.

The list is now two derived properties:

- `openPanelState` — every state a person deliberately opened. Nothing
  spontaneous may replace one.
- `blocksTransientSplit` — that, plus `notification`, which is itself
  transient: an OSD must not stomp a notification, but a second
  notification legitimately replaces the first.

Measured with the HUD up: `hyprctl dispatch workspace 7` replaced it
before, survives it after; `notify-send` replaced it before, survives it
after (only dunst's own popup appears). `notification_center` was missing
from the old list entirely and is now covered too.

## Panels that were mostly empty

Three panels carried a fixed height chosen for a worst case that is not
this machine's case. Screenshotted:

| panel | was | empty | now |
|---|---|---|---|
| display | 830 × 270 | ~45 % | sizes to content, ~185 px with one output |
| audio | 870 × 310 | ~55 % | sizes to content, ~180 px with one output |
| theme picker | 760 × 267 | — | 760 × 397, **all 22 themes visible** |

The theme picker was the real bug and not a styling one: 22 themes in 4
columns is 6 rows at a 57 px cell, so the grid wanted 342 px and was given
218 — **six themes were below the fold on every open**, with a `clip: true`
GridView saying nothing about it. A picker whose whole job is "show me what
I can pick" hiding a quarter of the options is not fixable with padding.

Both self-sizing panels read their details block's height off the `Column`
rather than recomputing it from a row count, because the audio panel's
details list is between three and eight rows depending on the tab, and a
height computed from a different row count than the one drawn is a panel
that clips its own last line. Both keep a `rowsVisible: 6` ceiling, which is
where the old comment's argument for a tall panel survives — past six rows
it scrolls instead of growing.

## Chord HUD and slider styling

The HUD's rows were 19 px apart carrying 10 px type in 14 px chips —
denser than any other surface in the shell, on the one panel you read with
your hand frozen mid-chord. Rows 21 → 25, header 26 → 32, chips 15 → 19 at
radius 6, type 10 → 11, and column spacing 10 → 20 (three columns 9 px
apart read as one ragged column; the eye needs a bigger gap *between*
columns than between a chip and its own label, or the label groups with
the wrong chip).

The control centre's slider cards are `Metrics.px(76)` = 70 px tall and
were spending 20 of that on the track: a 13 px label at the top, a 20 px
bar at the bottom, and a ~25 px band of empty module colour between them
that reads as a half-drawn card. The track is now 30 px, which makes it the
body of the card the way macOS's own control-centre sliders are, and makes
the 13 px icon inside it legible. The fill's minimum width is now the track
height rather than a bare 34, so a near-zero value draws a round cap
instead of a lozenge narrower than its own corner radius.

## `r` in the wallpaper picker no longer commits

It used to jump *and* apply. A random **jump** and a random **commit** are
different tools: the jump is navigation — it is `l` pressed 200 times, and
navigation in this picker has never had a side effect — while the commit is
Enter, the only key that writes anything. Folding them together meant there
was no way to browse 362 wallpapers at random, because every look cost a
wallpaper change and, through `theme-apply`, a palette change. Verified by
`wtype r` twice with the picker open: the selection moved 0001 → … → 0183
and the picker stayed open both times. Before the change it would have
closed on the first press, which is what applying does.

## Two things about Quickshell worth writing down

- **It reloads on `.qml` changes and not on `.js` ones.** Adding a function
  to `Motion.js` and using it from QML in the same breath produced
  `TypeError: Property 'overshoot' ... is not a function` that survived
  every subsequent reload, because the QML reloaded and the library did
  not. Touching any `.qml` file clears it.
- **A failed reload is survivable.** A broken edit logs `Failed to load
  configuration` and the *previous* config keeps running, so a syntax error
  mid-session does not take the shell down. It also means "it still works"
  is not evidence that your edit loaded — check the log.

## Traps found while making the chrome follow the theme

Four things in this session looked like separate bugs and were one shape:
a setting nobody had ever written down, so a default was in force and the
default was not themed.

- **Hyprland's groupbar had never been configured.** Every option under
  `group:groupbar:` read `set: false` from `hyprctl getoption`, so the
  TreeTab tab bar ran the built-in defaults — `col.active 66ffff00`, i.e.
  **yellow at 40% alpha**, with `text_color` opaque white at `font_size 8`.
  It was the one piece of window chrome that ignored `theme-apply` on all
  21 palettes, and its titles floated unreadably over the wallpaper.
  `hyprctl getoption <key>` and its `set:` field is the way to find this
  class of bug: an unset option is invisible in the config and very loud
  on screen.

- **Hyprland's groupbar does not fill its tabs.** `col.active` /
  `col.inactive` paint ONLY the `indicator_height` strip; the tab body is
  whatever is behind the window, and the title is drawn over the gap.
  `gradients = true` does not change this and neither does a full-height
  indicator. A port that assumes qtile's filled-row model — qtile's
  TreeTab really does fill, with `active_bg` / `inactive_bg` — puts dark
  ink on the desktop and reinvents the unreadable-title bug from the other
  side. Measured with `grim`: the tab body samples the desktop colour on
  both the active and the inactive tab.

- **In `wal` mode a wallpaper change did not change the palette.** On the
  21 named themes the palette is fixed and a wallpaper change must not
  touch it, which is why this hid for so long. In `wal` the palette is
  DERIVED from the image, and `wallpaper-set.sh` recorded the wallpaper,
  pointed the daemon at it and `exec`'d away without re-running
  `theme-apply` — so every colour in both sessions stayed derived from the
  previous image until something else triggered a theme change. Window
  borders are the visible half. Fixed in `wallpaper-set.sh`, gated on the
  mode, and deliberately not in `wallpaper-sync.sh`, which is also
  `autostart.conf`'s login hook and would then regenerate the whole theme
  on every boot.

- **A staleness test has to read a field that actually moves.** The first
  attempt to prove the bug above compared `$border_active` across two
  wallpapers and found it unchanged — which looks exactly like the bug and
  is not evidence of it, because the `wal` generator emits the same first
  and last accent for both images. `$bg` varies; the accent slots may not.

- **`hyprctl getoption` on a colour returns the packed int, not a hex
  string.** `text_color` reads `4294967295`; that is `0xFFFFFFFF`. Reading
  it as a decimal and concluding "some huge number" is how the white-on-
  yellow default went unnoticed.

### And one that is not Hyprland's fault

**qtile's `font="Ubuntu Bold"` does not exist on this machine.**
`fc-match "Ubuntu Bold"` returns `NotoSansCJK-Regular.ttc` — fontconfig
substitutes a CJK face rather than failing, with nothing in any log. Any
font family carried across from `../qtile/config.py` must be `fc-match`ed
before it is trusted. `Inter Medium` and `JetBrainsMono Nerd Font` both
resolve correctly here; `Ubuntu Bold` does not, and neither does anything
else that only ever existed as a Pango description string.

The same applies to Nerd Font glyphs: `fc-list ":charset=<cp>"` proves the
codepoint is covered, which is NOT the same as the shape being legible at
11 px. Render it before shipping it.
