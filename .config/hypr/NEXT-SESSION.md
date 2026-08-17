# READ THIS FIRST IF YOU ARE IN A qtile SESSION

Everything below this block was written from Hyprland. A pile of work landed
for the X11 side that **has never been run under qtile** — it compiles, it is
unit-tested, and its reasoning is checked against the installed libqtile, but
nobody has watched it work. This is the list, in the order it will bite.

## Verify these four, in this order

1. **The island takes the keyboard and KEEPS it.** Open any island panel
   (`$alt SHIFT D` for the shelf) and press `q`. It should close. Then open
   it again, move the mouse across another window, and press `q` again — that
   second one is the actual fix. `bin/x11-panel-focus.sh` suspends
   `follow_mouse_focus` on grab and restores it on release.

   **If it breaks, the dangerous failure is the RESTORE**, not the grab:
   check `qtile cmd-obj -o cmd -f eval -a 'repr(self.config.follow_mouse_focus)'`
   after closing a panel. It must say `True`. If it says `False`, the panel
   left focus-follows-mouse switched off for the session — remove
   `$XDG_RUNTIME_DIR/tide-island/x11-prev-follow-mouse` and set it back by
   hand while you debug.

2. **Copying works at all.** `y` in the shelf, and the calculator's copy.
   Both went through `wl-copy`, which is inert under X11 and says nothing
   about it. They go through `qml/common/Clipboard.js` now, which picks
   `xclip` when `WAYLAND_DISPLAY` is unset. If a copy does nothing, run the
   argv by hand — the file's header has it.

3. **The theme sweep animates.** Change the theme. Under qtile it used to
   switch palette with no animation at all, because the capture was `grim`.
   It is `maim -g <w>x<h>+<x>+<y>` now. If it still does not animate, check
   that maim is installed and that the capture is not black —
   `ThemeTransitionWindow.captureCommand()` is the one function to read.

4. **The two bars now agree on colour.** This is the one you reported. Switch
   island ↔ qtile bar on any theme and the palette must not jump.
   `colors.active_palette()` reads `~/.cache/qtile/current_palette.json`
   now. If a theme looks wrong, compare that file against
   `~/.cache/tide-island/colors.json` — every slot should match, and a
   mismatch on `mode` makes it fall back to the old hardcoded preset, which
   is the drifted one.

## What was measured in Hyprland and does NOT need re-testing there

The shake gates, the notch drop target, the shelf's keys. Those are Wayland
paths and qtile has its own watcher (`qtile/scripts/qdrop_watch.py`) with a
real XDND gate — it was never the broken one.

## The bar switch, driven end to end in Hyprland

Both directions, and it is clean. Recorded because the qtile half is the
same script and should behave the same way:

    bar-switch native   island down, topbar + treetab + popups up
                        reserved 33 -> 38, two layer surfaces (1366x38
                        bar, 1366x1 exclusive-zone window)
    bar-switch island   island up, the other three stopped, reserved
                        back to 33

And the shelf routing is exactly what was asked for. Under `native`, the
island's qdrop IPC has no instance, `qdrop.sh` falls through to popups.qml,
and the STANDALONE `QdropShelf` opens — the GTK `qdrop.py` was never spawned,
which is the correct order. Under `island`, the shelf is the 25th island
state and comes out of the capsule.

---

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

# THE HEIGHT GLITCH IS FIXED, AND HOW IT WAS FOUND IS THE POINT

Kept at the top, not because there is anything left to do on it, but because
three sessions in a row got it wrong in three different ways and each wrong
answer is a method that will be reached for again.

> "fix the height of the island — the animation after closing the popup, the
> island glitches up and down still. Take a gif or video to see it, and fix."

**What it was.** The spring's overshoot is a fixed fraction of the DISTANCE
TRAVELLED — 1.54% at zeta 0.8. That is the right amount of bounce when the
thing you land on is about as big as the distance you covered, which is every
OPEN, and is why opening was never reported. Closing is the asymmetric case:
the travel is the whole panel and the destination is the 35 px notch.

Measured on `mainCapsule.height`, closing the control centre:

    +238 ms   40      still arriving
    +285 ms   31      <- 4 px BELOW the resting 35, an 11% squash
    +333 ms   31
    +382 ms   33
    +429 ms   35      recovered, ~200 ms after it first arrived

323 → 35 is 288 px of travel; 288 × 0.0154 = 4.43, so 30.6 → 31. Prediction
and measurement agree to the pixel. A 46 fps `wf-recorder` capture of the
same run shows the WIDTH doing it too: 182 → 179 at +218..+283, back to 182
by +458, which is the same 1.54% of 213 px of width travel.

**The three wrong answers, in order.**

1. **The wrong PROPERTY.** A previous session probed `onTargetHeightChanged`,
   saw no change at all on close, and concluded the report was really about
   the chord HUD. `targetHeight` is the spring's TARGET: it moves once, at
   the start, and then sits perfectly still while the ANIMATED height
   overshoots and settles. The probe could not see the defect by
   construction. **Probe the property that is drawn, not the one that is
   aimed.**

2. **The wrong LATCH.** The fix needs a curve chosen from the travel and the
   destination, and the obvious place is a `ScriptAction` at the head of the
   `Behavior`, exactly as `pendingMorphPx` is latched for the duration. It
   does not work, and the probe that shows why is worth repeating:

       LATCH  w 212 -> 174   h   0 -> 323   zeta 0.8    <- width Behavior
       TGT                        35 normal
       LATCH  w 212 -> 174   h 288 ->  35   zeta 0.9    <- height Behavior

   The width Behavior fires first and `targetHeight` still reads the OLD
   value inside it — not because the state has not changed (`baseTargetWidth`
   is already the new 174 in the same breath) but because both are bindings
   on one `islandState`, and **reading a dependent the notifier has not
   reached yet returns the stale value and does not force it.** The second
   latch is correct and one line too late: the capsule still dipped to 31,
   i.e. **the easing is read when the animation JOB is created, before the
   ScriptAction at the head of its own SequentialAnimation runs.**

3. **The wrong BINDING.** Dropping the latch and letting the Behavior read a
   live expression is worse. `easing.bezierCurve` re-evaluates every time the
   property moves — every frame — so the value standing when the NEXT job is
   created is the one from the END of the last animation, where the travel is
   zero and `springFor()` hands back the undamped default. Identical 31 px
   dip.

**What works:** a plain property set from the handler that runs BEFORE the
Behavior can fire. One exists per dimension already —
`onBaseTargetWidthChanged`, which is what assigns `displayedWidth`, and
`onTargetHeightChanged`, measured to fire between the two latches.

**The cap is `Motion.overshoot()` itself**, not a tuned number: *the bounce
may never be a larger fraction of the shape than it would be on a morph that
travelled its own length*. It falls out of the algebra that this leaves every
travel ≤ destination untouched — i.e. every open. Closes land at zeta
0.82–0.90 and never at 1.0, so a close still has a spring in it, just one
sized for the notch.

**After:** control-centre close reads `309 278 240 204 169 138 114 94 77 65
56 49 44 41 38 37 36 35 35 …` — strictly monotone, floor exactly 35, never
below. Wallpaper picker the same. Both opens still peak 4 px and 3 px past
their targets, unchanged. `sweep-island.py`: 22 states, 10 transitions, all
pass.

**And the video was right to insist on.** `wf-recorder -o eDP-1 -g "0,0
1366x120" -r 60 -f /tmp/island.mp4`, ffmpeg to frames, then measure the
capsule's edge per row — with the TOPBAR STOPPED, because both are Top-layer
surfaces at y=0 and the topbar is created second, so it draws over the island
and every capture with it up is of the wrong shape.

---

# THE TWO BARS WERE PAINTING THE SAME THEME IN DIFFERENT COLOURS

Kept at the top because it was reported as a SWITCHING bug — "color issues
when i switch from island to qtile or visversa" — and switching had nothing
to do with it. The palettes simply disagreed, permanently, so every switch
showed the jump. Measured on gruvbox, the theme standing at the time:

    slot      qtile's colors.py     the island / the topbar
    bg_alt    #000000               #1d2021
    green     #98971a               #b8bb26
    yellow    #d79921               #fabd2f
    cyan      #b8bb26               #8ec07c

Green and yellow are not shades apart — they are gruvbox's DIM set against
its BRIGHT set, an olive GroupBox beside a yellow one. Nothing was stale and
no reload would have fixed it: `qtile/colors.py`'s `_PRESETS` and
`AtiScriptsV1/theme-apply`'s `resolve_palette` are two hand-written copies of
the same twenty-two palettes, and they had drifted.

**This is the failure the rest of the desktop is already built around
avoiding**, in the one place never brought in. `topbar/BarTheme.qml` refuses
to carry a palette for exactly this reason, and this file already records the
day one duplicated palette "made every window border green on twenty-two
themes, silently".

`colors.active_palette()` now prefers `~/.cache/qtile/current_palette.json` —
theme-apply's own answer, the same numbers `gen_island_colors` writes for the
island — and falls back to the preset when the file is missing, half-written,
or names a different mode. Verified: all nine slots now identical to
`~/.cache/tide-island/colors.json`.

It fixes a second, smaller thing for free. `colors` is assigned at config.py's
module scope, so it is re-read by every `reload_config()` — which is what
`bar_switch_apply()` does coming back from the island. A palette in a
hardcoded table could not follow a theme changed while qtile's bars were
hidden; one in a file does.

**The slot order is not a guess**: `[bg, fg, bg_alt, red, green, yellow, blue,
purple, cyan]`, checked against DoomOne in colors.py and against
BarTheme.qml's mapping table, which agree. The one deliberate consequence is
that slot 2 stops being `#000000` on the dark themes; the chip plate is
derived from the background in both bars and is unaffected, and the ten other
`colors[2]` uses move by a few points of luminance.

---

# STILL OPEN, in the order worth doing

0. **THE TOPBAR LOSES ~2 px OF HEIGHT WHEN A POPUP OPENS AND CLOSES.**
   **DRIVEN IN HYPRLAND AND NOT REPRODUCED — on either bar.** The report
   stands; what follows is what it is NOT, so the next attempt starts
   somewhere new.

   *The topbar.* `bar-switch native`, then a volume popup opened and closed
   while a sampler read the compositor's own geometry every 8 ms —
   `j/layers` for the bar surface and `j/monitors` for the reserved zone.
   **One line of output**: `h=38 y=0 reservedTop=38`, unchanged for the whole
   run. Then the pixels, because a stable surface can still be painted
   wrongly: a 157-frame grim burst of `0,0 1366x60` at ~39 fps, measuring the
   bar's painted bottom edge in three columns. **Identical in every frame.**
   The popup was verified to have actually opened (`popups status` →
   `volume`) before either measurement was believed, so neither is vacuous.

   *The island.* Same method, `qdrop open` then `close`, 289 frames over 5 s,
   measuring the capsule's dark run down from y=0. Rest before: 13 px,
   steady. Rest after: 13 px, steady. The close settles
   `27 23 17 15 14 13` — strictly monotone, no undershoot, which is
   `Motion.springFor` still holding.

   So on this machine, in this session, neither bar moves. What that leaves:

   * **It may be qtile-only after all.** The report says picom fixed it
     there, and `picom.conf` now excludes the island for a measured reason
     (it ran a slide-down over a window that resizes under its own spring).
     If the Hyprland half cannot be reproduced, the honest reading is that
     the qtile fix worked and the memory of the symptom carried over.
   * **It may be a popup this did not try.** Volume was the one driven.
     Wallpaper, network, bluetooth, display and the cheatsheet all have
     different heights and different loaders.
   * **It may need the eye rather than the sampler.** 39 fps against a
     ~200 ms event can miss a single frame. `wf-recorder -r 60` over the bar
     strip is the next instrument, and the RULES already describe the
     frame-differencing method.

   Everything below was ruled out by reading, before any of the above:
   Reported fresh: "the topbar still gliching when i open then close popup
   its hight reduce with 2px lets say and come back to its place again , in
   qitle it was because picom and fixed i think , but in hyperland i dont
   know why still do".

   NOT REPRODUCED — `bar-mode` was `island` throughout the session that took
   this report, so the topbar was not running and reproducing it means a bar
   switch. What was ruled out by reading, so the next session does not spend
   the time again:

   * **It is not a spring.** The island's height glitch at the top of this
     file was `Motion.springFor` overshoot, and the shape of the complaint
     is identical — shrink, return — so it is the first thing to suspect and
     it is wrong here. `grep 'Behavior on \(height\|implicitHeight\|y\)'`
     across `topbar/*.qml` and `popups.qml` returns NOTHING. No geometry on
     either surface is animated at all.
   * **It is not the UI scale flickering to a fallback.** `Metrics.qml`
     reads `~/.cache/qtile/ui_scale` through a FileView and falls back to
     1.0; the file currently holds `1.00`, so the fallback and the real
     value are the same number and a reload cannot move anything.
     `barHeight` is `s(28)` and `marginV` is `s(5)`, i.e. a static 38.
   * **picom cannot be the cause here** even though it was under qtile.
     There is no compositing layer between Quickshell and Hyprland, so a
     matching symptom in the two sessions has two different causes and the
     qtile fix does not port.

   The strongest remaining lead is that **the bar's height is not what
   moves**. `topbar/shell.qml:931` is a SEPARATE 1 px window that owns the
   `exclusiveZone` — both real bars are `ExclusionMode.Ignore` — so anything
   that perturbs the reserved area moves the tiled windows and the gap under
   the bar without the bar itself changing size at all. A popup is another
   layer surface, and layer-shell recomputes the usable area when one maps.

   **How to settle it, and the rules that apply:** PROBE THE PROPERTY THAT
   IS DRAWN, NOT THE ONE THAT IS AIMED — read the bar window's actual height
   and the monitor's `reserved` from `hyprctl monitors -j` across the open
   and the close, not `implicitHeight`. Then a 50 fps `grim` burst in PPM
   over a strip containing the bar's bottom edge, differencing consecutive
   frames. Both halves of that method are already written down further down
   this file.

0a. **pcmanfm-qt: THE GRID'S WIDTH IS A FONT BUDGET, NOT AN ICON SIZE.**
   Reported with a screenshot: "why the file or folder or has a very bg
   space". Five columns of folders with ~218 px between them and a 32 px
   icon in the middle of each.

   Measured rather than guessed, three runs against the same folder:

       BigIconSize 32   horizontal pitch 218 px, 5 columns
       BigIconSize 64   horizontal pitch 218 px, 5 columns   <- unchanged
       QT_FONT_DPI 72   horizontal pitch ~166 px, 7 columns

   So the cell WIDTH does not depend on the icon at all — only the height
   does — and it scales almost exactly with the font (166/218 = 0.761
   against 72/96 = 0.75). libfm-qt reserves a fixed CHARACTER BUDGET for the
   label and sizes the uniform grid to it. `ShowFullNames` was the obvious
   suspect and was tested first: flipping it true → false changed nothing,
   names still render unelided.

   That leaves the font as the only lever, and it is applied where it costs
   least: `.local/share/applications/pcmanfm-qt.desktop`, a local override
   of the packaged entry with `Exec=env QT_FONT_DPI=84 pcmanfm-qt %U`.
   Scoped to this one app rather than qt6ct's global font, which every Qt
   program on the desktop reads. With `BigIconSize=48` it now draws six
   columns with bigger, clearer icons than the five it had.

   **NOTE FOR A FRESH INSTALL:** that file is the repo's first entry under
   `.local/`, not `.config/`. stow descends into an existing
   `~/.local/share/applications` and links it, so it works — but nothing
   else in this repo lives there, so it is easy to miss.

   **THE DRAG OFFSET IS PROBABLY THE SAME FACT, AND IS NOT PROVEN.** Also
   reported: "why the file not directlye under the cursor". The drag pixmap
   libfm-qt builds is the rendered ITEM, and the item is that 218 px cell
   with a 48 px icon centred in it — so the visual extends ~85 px either
   side of what you actually grabbed. Narrowing the cell narrows the offset
   by construction. It was NOT measured: the attempt drove a synthetic drag
   with `uinput-shake.py` and the workspace was not the one assumed, so the
   press landed in nvim instead of the file manager. **Do not synthesise
   drags over the user's real windows** — the earlier qdrop tests were safe
   because they ran on an empty workspace with throwaway windows, and that
   is the difference. To measure it properly: an empty workspace, a
   pcmanfm-qt window with one file, a `to` drag, and a grim capture during
   the hold.

0b. **THE CALCULATOR PANEL IS THIN, AND ITS KEYBOARD IS THINNER.**
   Reported: "the popup of calcoter is too dumm and poor and no vim motion
   enough for moving".

   `qml/island/CalculatorLayer.qml` today is a `PanelSearchField`, a result
   line, and a history `Repeater`. `Keys.onPressed` answers exactly ONE key
   — Escape — because the field holds the keyboard and every other keystroke
   is text. `recall(delta)` walks history and is reachable only from the
   arrows.

   **The modal problem is the same one QdropGrid solved, INVERTED, and that
   is the whole design note.** The shelf is hjkl by default and `/` enters
   the search field; a calculator cannot be, because typing an expression IS
   the primary act and `d`, `y` and `j` are all legal in one. So the default
   mode is INSERT and the second mode is normal: Escape leaves the field
   (rather than closing the panel, which is what it does now), hjkl/gg/G
   walk the history, `y` yanks the focused entry, Enter recalls it into the
   field, `i`/`a` go back to typing, and Escape from normal mode closes.
   That is vi's own precedence and it is what makes both halves reachable.
   `PanelSearchField`'s `readOnly` is the mechanism — its header describes
   it as the thing that "keeps focus and inserts nothing" — so no focus
   juggling is needed, exactly as in the shelf.

   What "poor" is probably also asking for, in the order it is worth doing:
   a history that persists across opens; unit and base conversion (`10 in
   cm`, `0xff`, `2^32`) which is what qalc is actually reached for; a memory
   register; and the result line being copyable per entry rather than only
   the latest. `copyResult()` already goes through Clipboard.js, so the
   qtile session gets all of it for free.

1. **The rest of the login notification burst.** "when i start the hyperland a
   lot of notifications appear, like 2-3 ones." ONE cause found and fixed:
   `adhkar` notified before its first sleep, so a remembrance card went out
   the instant autostart launched it. The others could not be found by
   reading, and every guess was wrong under a live bus monitor — nm-applet,
   blueman-applet and kdeconnectd are all silent on restart, nm-applet's
   `disable-connected-notifications` is already true, `battery-events`
   initialises `LAST_AC` before its loop, `qupdate --daemon` notifies on no
   startup path.

   The weakness in that test is the thing to fix, not the test: restarting a
   tray applet when the state it reports has ALREADY settled is not the same
   as starting it while the state is still arriving. **Add one line to
   `autostart.conf`, log out, log in, read the log, take the line out:**

       exec-once = ~/.config/hypr/scripts/test/startup-notifications.sh 180
       # then: ~/.cache/hypr/startup-notifications.log

2. **The rest of the motion matrix's SETTLE.** The sweep proves every
   transition lands in the right STATE; it says nothing about how it looks
   getting there. The ~800 ms panel settle is still unmeasured, and the
   content-sized cases other than `picker` still have the latent re-aim this
   file has described for five sessions. The height glitch is NOT this — it
   was the shape, and it is fixed.

3. ~~**qdrop's BEHAVIOUR as an island surface.**~~ **DONE — rebuilt in
   Quickshell.** `quickshell/tide-island-fork/qml/qdrop/QdropShelf.qml`, a
   PopupChrome like every other popup, hosted by shell.qml and popups.qml,
   reading and writing the same `~/.cache/qdrop.json`. A Wayland-native drag
   reaches it in both directions — measured, and it is the case the GTK shelf
   could never do. `hypr/scripts/qdrop.sh` prefers it and falls back to GTK
   when no Quickshell process is up (qtile's own bar).

   What is left on it, none of it blocking:

   * ~~The GTK shelf's richer menu is not ported.~~ **DONE** — right-click
     actions, the zip, pinning and the sort modes are all in
     `QdropGrid.qml`, plus a visual mode and a search field.

     **The two destructive keys now take CTRL** — `ctrl+z` zips, `ctrl+d`
     deletes, `Delete` still deletes bare. Asked for by name, and they are
     the only two commands on the panel that cannot be undone by pressing
     the key again, sitting on bare letters in a map you drive with your
     fingers on hjkl.

     **"the zip not working" was the zip being INVISIBLE.** The archives
     were on disk the whole time — three under `~/.cache/qdrop-zips`, one
     pair written two seconds apart, which is what pressing a key that
     appears to do nothing looks like from the outside. Every link was
     driven in an isolated Quickshell instance and every one answered: the
     Process exits 0, `onExited` fires with the pending path intact,
     `QdropStore.addValue` writes the entry. What was missing was that a new
     tile at the top of a full shelf, behind wherever the cursor already
     was, says nothing. The archive is now checked to EXIST before an entry
     claiming it is added, stderr is captured and reported instead of a bare
     "zip failed", and the cursor MOVES TO the archive and selects it — so
     it is under your hand, ready to drag back out.

   * **The shake's false positives were real, and this file predicted both
     of them.** Reported as "when i select text or scroll up down it
     appears"; `qdrop-shake.py`'s own docstring already listed
     text-selection and rubber-band shakes under WOULD FIRE. With no gate 2
     available on Wayland the only thing left is the SHAPE, and it is now
     tightened four ways, each a property a deliberate shake has and an
     accidental wiggle does not:

     1. **Its own constants.** qdrop_watch's were tuned for RAW DEVICE
        DELTAS; this feeds differences of ACCELERATED SCREEN POSITIONS,
        several times larger for the same hand movement. Importing the shape
        and the numbers together made the Wayland detector far MORE
        sensitive than the X11 one it was copying, on identical-looking
        constants. `Axis` reads them as module globals at call time, so they
        are overridden on the module after import and qtile's tuning is
        untouched.
     2. **Horizontal only.** A scrollbar or a slider is pure vertical
        reversal, which is the whole of the "scroll up down" half.
     3. **And the vertical travel must be small beside it**, or a diagonal
        scrub reverses on x as well.
     4. **A shake is preceded by a drag** — the button down a moment and the
        pointer over real ground before any reversal counts.

     **And a fifth gate, which is not a shape and could not have been.**
     Reported next: "i resize the terrmianl with cursor and opens the
     dropshef". `general:resize_on_border` is 1 here with a 15 px grab area,
     so dragging a window edge is a BARE button-1 drag — the modifier-exact
     trick that excludes window moves does nothing — and the gesture does
     not merely resemble a shake, it IS one: horizontal, flat, big
     segments, plenty of carrying. Gates 1-4 passed it correctly.

     **A resize is not a shape, it is an OUTCOME: the window changes size.**
     A move is the same statement about position. Neither happens during a
     file drag and both are observable — `j/activewindow` over the request
     socket, 839 bytes in 0.074 ms, cheap enough to sample every tick rather
     than on a timer a fast resize could outrun. Sticky for the press, so
     pausing mid-resize does not reopen the hole.

     `scripts/test/shake-shapes.py` drives `Drag.sample()`, which is the
     whole of the shipped decision — the loop calls that and nothing else —
     with eleven gesture shapes, **11/11**. The resize row uses the
     IDENTICAL pointer samples to the row that must fire, so the only thing
     separating them is the window box.

     **Then driven for real**, with `uinput-shake.py` on an empty workspace
     holding two tiled windows:

         deliberate horizontal shake, mid-window     FIRES
         border drag that really resized 1005->986   refused, "compositor grab"
         the SAME border drag under --loose          FIRES      <- the control
         vertical shake (scrollbar, scroll)          quiet
         small wiggles (a text selection)            quiet
         one-way drag with tremor in it              quiet

     The control row is what makes the rest mean anything — without it "the
     resize did not fire" is equally consistent with the driver having
     missed, and this file already records a session lost to a test that
     could not fail.

     **What it is still NOT** is "only while a file is in flight", which is
     what was asked for and what gate 2 gave the X11 watcher. Wayland gives
     a third party no view of `wl_data_device`, there is no protocol for it,
     and `hyprctl` has nothing about data devices — re-checked, not assumed.
     The one shape that can still reach the shelf is a hard, flat, sustained
     horizontal shake over a window that does not change size, carrying
     nothing.

     **The route that WOULD be exact, if this is reported again:** a thin
     always-present layer surface across the top of the screen with a
     `DropArea` on it. A DropArea sees real mime types, so "a file drag
     touched the top edge" has no false positives at all — the RULES already
     record that a Quickshell layer surface receives real Wayland drags, and
     `QdropLayer` proves it in this tree. That is a second, exact TRIGGER
     rather than a better gate on this one, and it does not need the shake
     to go away.
   * `--add-text` still goes to qdrop.py, which spawns the GTK daemon. Both
     write the same file and the shelf watches it, so they agree; nobody has
     driven them writing at the same instant.
   * The GTK shelf remains for the qtile-own-bar case, so its workspace dance
     in qdrop.sh has to stay with it.

   Original ask, kept because the second half is still the standing
   requirement: *under the island the shelf should be an island popup, in
   island UI/UX; under the qtile-like topbar it should behave exactly as real
   qtile's does.*

   The SHAKE gesture is done and is not part of this — `scripts/qdrop-shake.py`,
   with the binds in binds.conf's qdrop block. So is "it only opens on
   workspace 4", which affected the key as much as the gesture and is now
   `scripts/qdrop.sh` moving the window before the reveal. **NOT `pin`** —
   that was tried, shipped, and reported broken inside minutes: Hyprland
   clamps a pinned window into the monitor, so the hidden `[371, -331]`
   became `[371, 35]` and the shelf sat on screen on every workspace with no
   way to hide it. Every measurement that "proved" pin worked had the shelf
   VISIBLE. **Test a rule for this window in the state the window is
   actually in, which is hidden.**

   THE MEASUREMENT THAT FORCED THE REWRITE, driven with
   `scripts/test/dnd-peer.py` and `uinput-shake.py to` against the GTK shelf:

       XWayland source -> GTK shelf  drop in AND drag out both work
       Wayland source  -> GTK shelf  drag begins, NOTHING arrives
       Wayland source  -> any plain XWayland window, no qdrop involved
                                    the drop arrives carrying the X11 PRIMARY
                                    selection instead of the offered URI

   So the compositor's Wayland -> XWayland drag bridge is what is broken, not
   the shelf — and pcmanfm-qt is `QT_QPA_PLATFORM=wayland;xcb`, i.e. the file
   manager you would actually drag from sits on the wrong side of it.

   **REBUILT IN QUICKSHELL**, which was the user's call and what the
   measurements independently pointed at. Four defects closed in the one
   change: the Wayland -> XWayland drag bridge left the path entirely, the
   surface got `IslandTheme` like every other popup, a layer surface is
   placed by the compositor so nothing needs XWayland, and hiding stopped
   being "move off-screen" — the thing that made `pin` fatal.

   The model was kept and the GTK was not: same `~/.cache/qdrop.json`, same
   `{type, value, added_ts, pinned}`, newest first, `entry_badge()` and
   `entry_label()`'s answers reproduced in `QdropStore.qml`.

   Two smaller observations from the same runs, neither acted on:
   * A drag OUT leaves a 20x20 `Qdrop.py` window mapped at (-99,-99) — GTK's
     drag icon, same PID as the shelf, off-screen but in the window list.
   * The shelf auto-hides 8 s after the pointer leaves, which is shorter than
     the 3.5 s a uinput device takes to bind plus a drag; any test that drives
     two drags has to re-show between them.

4. **The 12 unchecked picker menus** against their rofi originals: documents,
   man, notes, clipboard, confedit, spellcheck, translate, pass, todo,
   shared, youtube, hub. The record menu is DONE.

5. **`bar-mode` moved on its own.** A sweep run started on `native` and ended
   on `island`. Only bar-switch and bar-chooser write that file and neither
   was called. `sweep-island.py` now reports the change; nobody has caught it
   in the act. `ps -eo pid,ppid,lstart,args` while it happens.

6. **Scratchpads on a second monitor.** The bars and popups are now tested
   across two outputs and fractional scale; `scratchpad.sh`'s monitor-relative
   x/y is still verified-by-history only, and `hyprctl output create headless`
   is how to test it.

7. **The SHADOW is the last thing that assumed the flush form.** The border
   follow-up is otherwise done: the panel outline now traces `notchSkirt`'s
   flares (`notchSkirtOutline`, z 6) and the frame's verticals start where
   each fillet lands. The overshoot band was the same object and came with
   it. The drop shadow was not checked and is drawn from the capsule's
   rectangle, so it presumably squares off where the shape flares.

8. **Live preview for the cheap numeric settings keys**, now that the
   settings app has a preview to put it in.

9. **`islandShowWorkspaceOnAutoHide`** is still an inert row. Do NOT "fix" it
   via ForkConfig; see the audit.

10. **qtile with its OWN bar gets no theme sweep** — the one combination with
    no Quickshell process at all.

11. **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
    ~50 ms before any animation starts.

12. **`parse_task_name` strips a short trailing subtitle.** Found while
    fixing the spinner, pre-existing, and the comment above it claims the
    opposite: "A real subtitle ("Chapter 3 - The Long Way Home") is left
    alone." It is not — the tail is 17 characters with no separator inside
    it, so the ` - ` rule takes it. Either the rule or the comment is wrong
    and it is a taste call which, so it is written down rather than changed.

---

# WHAT THE LAST SESSION FINISHED

Each has its own commit with the measurement in it: the island height glitch
(above); `topbar.sh` refusing a second bar; the `◐` spinner family; the
island's language readout; the topbar clock's tooltip carrying its own data;
the panel border going round the flares; the idle timers; adhkar's first
fire. Before that: the four dead controls (Wi-Fi QR, `$alt 4` display,
`$alt 5` calculator, Bluetooth); the TaskList's five markup states; the
GroupBox's `box_width`/`spacing` and its wheel; passthrough's full shape
including the confirm popup; the media-key OSD; the rofi fade over the theme
sweep; qdrop's drag offset and its surface; dialogs floating and centred; the
island's exclusive zone when notch mode is off; the vim/fish cheatsheets on
both bars; the settings app's live preview and drag-in readouts; two-monitor
and fractional-scale correctness; the chord HUD's height cache; and the
systematic sweep (`scripts/test/sweep-island.py`, `sweep-topbar.py` —
22 states, 10 transitions, 41 actions, all passing).
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

# THE MOTION WORK SO FAR (background for the task at the top)

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

# THE REPORTED LIST — NEARLY ALL FIXED, KEPT FOR ITS MEASUREMENTS

Everything below came from the user in one pass. Almost every item is
now done; the causes are kept because they are measurements, and because
each one records how the wrong answer looked before it was measured.
What is still open is listed at the top of this file, not here.

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
  The LOOK and the drag offset are both done. What is left is the behaviour,
  and item 3 at the top of this file now carries the measurement that decides
  how to do it. ~~The shake gesture~~ and ~~"it only opens on workspace 4"~~
  are both FIXED — `scripts/qdrop-shake.py` and a `pin` rule respectively.

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
* **The island's height twitch — this entry was WRONG about the main case
  and right about a second one. Both are fixed now; see the top of this
  file.** What it says below — that closing a popup produces no `targetHeight`
  change at all — is TRUE and is exactly why the conclusion drawn from it was
  wrong: `targetHeight` is the spring's target and cannot show an overshoot
  by construction. The reported glitch was the animated height undershooting
  the resting notch by 4 px, and it is fixed by `Motion.springFor()`.

  The mode-keys case below is real, was a genuinely separate defect, and is
  also fixed. Kept verbatim because the measurement is good:

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

The numbered list at the top is the one to work from; this is the long tail,
and several entries here are the same item said twice. Ordered by how much
they are worth.

* **The rest of the motion matrix.** See above — the picker case is fixed, the
  other content-sized panels are not measured.
* ~~**Something leaks `pactl subscribe`, and it broke the audio stack.**~~
  **FOUND, and it is the PACKAGED BACKEND** — the one part of tide-island the
  fork deliberately does not vendor, which is exactly why "nothing in this
  repo spawns that command" was true and led to the wrong conclusion.
  `libIslandBackend.so` carries `pactl` / `subscribe` and three
  `[SystemServices] … is not available` lines naming `dbus-monitor` twice and
  `pw-mon` once, so every shell spawns up to FOUR long-lived watchers as
  QProcess children, and a shell that is killed rather than asked to quit
  does not reap them — they reparent to init and run forever. The backend
  says so itself in the message this file already records from an unrelated
  crash: `QProcess: Destroyed while process ("pactl") is still running`.

  Measured on a session a few hours old with the island restarted a couple of
  dozen times while a fix was being driven: **104 orphaned `dbus-monitor` and
  35 orphaned `pactl subscribe`, all PPID 1.** The audio one is the leak that
  once exhausted pipewire-pulse's client limit and made every pulse client on
  the desktop fail.

  `scripts/reap-island-helpers.sh` sweeps them, called from island.sh and
  topbar.sh — the two scripts that start entry points into the island's
  config. PPID 1 is the whole matcher and is exact: a LIVE shell's helpers
  have that shell as their parent, so there is no window in which the sweep
  can take a helper away from a running island. Driven: 139 reaped, three
  live shells untouched, then kill-and-restart leaves 0 orphans and 4 owned
  helpers rather than 8.
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

## Input synthesis: all of it exists now

* `scripts/test/uinput-click.py` — clicks, and `scroll up|down [count]`.
* `scripts/test/uinput-key.py` — key combinations, named as `hyprctl binds`
  names them, with `--hold` for observing a submap.
* `scripts/test/uinput-shake.py` — a button-1 drag with a shake in it, plus
  the three shapes a gesture gate has to REFUSE (`drag` one-way with tremor,
  `wiggle` with no button, `--mod super`), plus `to <x1> <y1> <x2> <y2>`,
  which is a drag from one point to another.
* `scripts/test/dnd-peer.py` — a window that offers one URI and prints what
  is dropped on it. The controlled far end for a drag test, so drag-and-drop
  never has to be driven against somebody's real files.

Four traps now, all in their headers: a uinput device takes ~3 s before the
compositor binds it; `movecursor` warps WITHOUT motion, so a one-pixel wiggle
is needed before a click; destroying the device can reset an active submap;
and a relative device goes through pointer ACCELERATION, so travelling to a
known point has to be closed-loop against `cursorpos` — open-loop deltas
miss, and miss further the longer the move.

# RULES — every one of these was paid for, several twice

### Verification

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **PROBE THE PROPERTY THAT IS DRAWN, NOT THE ONE THAT IS AIMED.** Three
  sessions of the height glitch went into `targetHeight`, which is the
  spring's TARGET and sits still through the entire overshoot it was being
  asked about. `mainCapsule.height` is what is on screen.
- **Restarting a daemon whose state has already settled does not reproduce
  its startup behaviour.** nm-applet, blueman-applet and kdeconnectd are all
  silent when restarted into a connected session and may well not be at
  login, when the association is still arriving. If the question is "what
  happens at startup", the answer needs a startup — see
  `scripts/test/startup-notifications.sh`.
- **A CAPTURE OF THE ISLAND WITH THE TOPBAR UP IS A CAPTURE OF THE TOPBAR.**
  Both are Top-layer surfaces at y=0 and the topbar is created second, so it
  draws over the island. Stop it for the recording and start it again after;
  the island alone is still a bar, so the session is never bare.
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
  set multiple times" fails the entire component. It applies to SIGNAL
  HANDLERS too: a second `Component.onCompleted` on one object is the same
  error, so a new startup step folds into the existing handler.
- **A Behavior's `easing` is read when the animation JOB is created, BEFORE
  the ScriptAction at the head of its own SequentialAnimation.** `duration`
  is not — it tracks a property the ScriptAction latched. So the latch trick
  that works for the duration cannot choose the curve, and a live expression
  is worse: `easing.bezierCurve` re-evaluates every frame, so what stands
  when the next job starts is the value from the END of the last animation.
  A curve has to be set from a handler that runs before the Behavior fires.
- **Reading a binding the notifier has not reached yet returns the STALE
  value and does not force it.** The list-model version of this is already a
  rule below; the geometry version cost a session. Two properties bound to
  one `islandState` are re-evaluated in the order they connected, so inside
  `onBaseTargetWidthChanged` the new width is there and the new
  `targetHeight` is not.
- **A tooltip that is a LABEL and one that is DATA are different things.**
  qtile's `TOOLTIP_BY_NAME` is a fallback table, and `install_bar_tooltips()`
  swaps the clock's for a live provider. Reproducing the table and not the
  provider gives a chip that promises two numbers and shows neither. Read
  what the widget DOES with the config, which is the same rule the installed
  libqtile entry below already states.
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
- **`qs ipc show` IS A SUBCOMMAND, so an IPC function called `show` CANNOT BE
  CALLED.** `qs ipc call <target> show` is eaten by the CLI, prints the
  handler's function list, and EXITS 0 — a caller reading the exit code sees
  success and a fallthrough chain never falls through. Measured on the qdrop
  handler: `hide` arrived, `show` never did. Name them `open`/`close`, which
  is why popups.qml spells its openers `showWallpaper` and not `show`.
- **FOR `Drag.Automatic`, `Drag.active = true` IS THE START — `startDrag()`
  IS NOT.** Three states, all indistinguishable from outside the log:

      `Drag.active: false` DECLARED    nothing delivered. A declaration is a
                                       BINDING and it pins the property.
      `active = true; startDrag()`     delivered, and warned
                                       `startDrag() drag must be active`
                                       on every single drag.
      `active = true` alone            delivered, silent, and repeatable.

  So the warning was `startDrag()` finding the work already done, and the
  fix was deleting the call rather than reordering it. Qt clears `active`
  itself when the drag finishes — driven twice in a row to prove it.
- **A QUICKSHELL LAYER SURFACE CAN RECEIVE AND START REAL WAYLAND DRAGS.**
  Probed with a bare `PanelWindow` + `DropArea` before anything was built on
  it — `PROBE dropped urls=["file:///…"]` — and there was no `DropArea`
  anywhere in this tree to copy. This is what the drop shelf is built on.
- **TEST A WINDOW RULE IN THE STATE THE WINDOW IS ACTUALLY IN.** `pin` on
  qdrop was measured three ways — opens on the active workspace, follows
  7 -> 6 -> 7, position unchanged — and all three were true and all three
  had the shelf VISIBLE. The defect is in the hidden state, which is where
  that window spends almost its whole life: Hyprland CLAMPS A PINNED WINDOW
  INTO THE MONITOR, so a hidden `[371, -331]` becomes `[371, 35]` and a
  window that hides by leaving the screen can never hide again. It shipped
  and was reported within minutes.
- **A BIND CAN SEE THINGS THE IPC CANNOT, AND `event` IS HOW IT TELLS YOU.**
  Nothing in `hyprctl` reports pointer BUTTON state — forty commands, none of
  them about the pointer. A `bindn` (non-consuming) on `mouse:272` sees it,
  and the dispatcher to carry it is `event`, not `exec`: `event` writes one
  line to socket2 and spawns nothing, measured at 2 ms from press to line,
  where `exec` is two `sh` spawns (1.80 ms each) on every click in the
  session forever. Fan-out for one extra socket2 line, measured over 2000:
  quickshell 135 us, each shell listener ~85 us, and all of them dispatch on
  a prefix with no default branch so an event they do not name costs a
  `read`. This is how qdrop's shake gesture gets its button.
- **A BIND WITH AN EMPTY MODMASK IS MODIFIER-EXACT.** Measured: with SUPER
  held, a modmask-0 `bindn` on mouse:272 did not fire at all. So enumerating
  the modifier states you accept IS a gate, for free — which is what keeps
  `bindm = $mod, mouse:272, movewindow` from ever looking like a file drag.
  The `i` flag opts out of it, and belongs on the RELEASE bind so that
  letting go while holding a modifier still clears your state.
- **`hyprctl`'s request socket is ONE REQUEST PER CONNECTION.** A second
  `sendall` on the same connection is EPIPE. Reconnecting per request is
  still 0.036 ms against 6.02 ms for spawning `hyprctl`, so poll through the
  socket and never through the binary.
- **A WAYLAND DRAG DOES NOT REACH AN XWAYLAND WINDOW INTACT.** Driven
  between two windows of the same test program: the drop arrives and carries
  the X11 PRIMARY selection instead of the URI that was offered. Anything on
  XWayland — qdrop is, because it positions itself — cannot receive a drag
  from a Wayland-native app, and pcmanfm-qt is Wayland-native here.
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
