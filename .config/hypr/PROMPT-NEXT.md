# Prompt — next session (Hyprland / Tide Island)

Continue the Hyprland / Tide-Island work in `~/.dotfiles`, branch `test`.

`~/.config/hypr`, `~/.config/qtile` and `~/.config/quickshell` are stow
symlinks INTO this checkout, so editing here edits the running desktop.
Quickshell hot-reloads on save.

**Read before touching anything:** the RULES at the bottom of
`hypr/NEXT-SESSION.md`, then the handoff block at the top of it, then
`quickshell/tide-island-fork/FORK-NOTES.md`. Where a doc and an older plan
disagree, the doc that carries a MEASUREMENT wins.

**Do the whole list in one pass. Do not stop to ask which item to start
with.** Commit as you go, one concern per commit, reasoning in the message
the way the existing history does. **No Co-Authored-By trailer.**

The desktop is currently: Hyprland, `bar-mode=island`, and **`forkNotchMode`
is FALSE** — the notch is disabled and the island is the floating pill. That
matters for item 8 and it is why item 8 exists.

---

## HOW TO VERIFY, BECAUSE THIS IS WHERE THE LAST FIVE SESSIONS WENT WRONG

Every item below is a VISUAL defect. None of them can be settled by reading
the QML, and three of them were previously "fixed" from reading and were not
fixed. The rig exists and is committed:

```
wf-recorder -o eDP-1 -g "0,0 1366x420" -r 60 -f /tmp/x.mp4
~/.config/hypr/scripts/test/hover-cycle.py 683 16 683 400 4 1.4
ffmpeg -i /tmp/x.mp4 -fps_mode passthrough f%04d.png
```

* `hover-cycle.py` warps then emits a 1 px nudge through uinput, because
  **`movecursor` warps WITHOUT a motion event and therefore never hovers.**
  It holds one uinput device open for the whole run. No buttons.
* `-fps_mode passthrough`, not `-vsync`; this ffmpeg removed `-vsync`.
* Drive panels over IPC: `qs -p ~/.config/quickshell/tide-island-fork ipc
  call <target> <fn>`. `qs ipc show` lists them.
* **Measure a property, then LOOK AT THE FRAMES.** A threshold that counts
  "is the capsule drawn" mistook the shelf's own hint chips for a blank last
  time, and looking is what turned a wrong number into the real finding.
* **Check the workspace before AND after a recording.** One run drifted to
  another workspace, put real windows under the island, and made a darkness
  test read "capsule present" when it was not. Use an empty workspace.
* **A/B or it did not happen.** Run the same gesture before and after with
  the same detector and quote both numbers.
* Never synthesise keystrokes into a live panel, and never synthesise drags
  over the user's real windows — an earlier attempt landed a press in nvim.
  Use an empty workspace with throwaway windows.

---

## THE TASK LIST

### 1. The drop shelf is unusable once it is OPEN — highest priority

Reported: *"i can add to it before the dropshelf opened — i shake and then
drag into it — but when it is open i can not use what behind the dropshelf, i
can not drag anything again and also can not zip or copy or drag the things
off. totally not working."*

So: the FIRST drop works. After that the panel is inert — no second drag in,
no drag out, no keys.

**The state machine that does this is already documented and is the place to
start.** `DynamicIslandWindow.qml`'s `islandKeyboardFocus` and
`islandContainer.qdropForDrag`:

* An exclusive keyboard grab **CANCELS an in-flight Wayland drag** — measured
  A/B, `entries 9 -> 9` with the grab against `9 -> 10` without it.
* So a shake-opened shelf sets `qdropForDrag = true` and takes NO grab.
* `onDropLanded` sets `qdropForDrag = false`, which takes the grab.

That is the trap: **after the first drop the grab is on, so every later drag
into or out of the shelf is cancelled by it — and if the grab were off
instead, the keys (`ctrl+z`, `ctrl+d`, `y`) would be dead.** The current
design can only ever have one of the two. Verify that is what is happening
before changing anything (drive two drags in a row with
`scripts/test/dnd-peer.py` + `uinput-shake.py to`, and watch
`~/.cache/qdrop.json`), then fix it properly:

* The grab must be dropped again the moment a NEW drag appears over the
  shelf — `QdropLayer`'s `onDragHovering` already fires for this and
  currently only restarts a timer.
* Dragging OUT is `Drag.active = true` on the tile (`QdropGrid.qml`); check
  whether the grab kills it too, and release the grab on drag start.
* `qdropDragGrace` is 20 s; make sure it is not what is re-arming the grab
  mid-drag.

Also fix: with the shelf open, the tiles must stay clickable and
rubber-band-selectable, and `ctrl+z` / `ctrl+d` / `y` / `s` / `/` must work.
Drive each one and say which you drove.

### 2. The same one-frame blink on the rofi-mode popup and others

The island's hover blink is FIXED (see `430ade4`): the layer surface grew at
the moment the tooltip appeared, and the first frame after a resize is drawn
before the content is laid out. `hoverTooltipWindowHeight` is now reserved
unconditionally.

**The same defect is still present on other surfaces** — reported on the rofi
mode popup, opening and closing, "and some other popups also".

Every contributor to `requestedWindowHeight` in `DynamicIslandWindow.qml` is
a candidate: `notificationCenterWindowHeight`, `capsuleWindowHeight`,
`overviewWindowHeight`, `controlCenterWindowHeight`. Record each open/close
at 60 fps, count blank frames, and apply the same answer where it fits
(reserve, do not resize) — but check each one, because a permanently
overview-sized window is not obviously free the way a 60 px tooltip was.

Note `retainedWindowHeight` already delays the SHRINK; the defect is at the
GROWTH.

### 3. The rofi mode popup says "bar action" on every row

Reported: *"when i open the rofi mode popup the text inside is only 'bar
action' — fix, write the right things."*

**Confirmed, and the cause is exact.** `~/.config/hypr/scripts/cheatsheet.py
--submap-json rofi` currently answers:

```json
{"key": "N", "action": "bar action"}, {"key": "B", "action": "bar action"},
{"key": "A", "action": "bar action"}, ... 26 of them
```

Every rofi-mode bind runs `exec, bar-action tide <function> [arg]`, and the
label function reduces an exec to its PROGRAM — so they all collapse to the
one wrapper's name. `SHIFT C` reads "theme toggle" only because it runs a
different program.

Fix in `cheatsheet.py`: the labeller must look PAST `bar-action` at its
arguments. `bar-action tide showPicker clipboard` is "clipboard",
`bar-action tide toggleCalculator` is "calculator". `describe()` already has
the equivalent special case for `qs ... ipc call` — extend that idea rather
than adding a second table. `AtiScriptsV1/bar-action`'s own case statement is
the authority for what each function means; do not write a third copy of it.

This is shared with the printed cheatsheet and with qtile's chord HUD, so fix
it once in `cheatsheet.py` and check both.

### 4. Popups open and close slowly / glitchily

Reported alongside item 2. Partly the same resize defect, partly the
"content arrives before the shape" problem.

One instance is already fixed and is the pattern: `QdropLayer` was **the only
layer in the shell with no `Motion.contentDelay()` choreography**, so its
tiles and keycap bar were drawn inside the 32 px notch for several frames.
Fixed in `430ade4`; wide-but-short frames went 3 -> 1.

**Audit every layer for the same omission:**

```
grep -L contentDelay qml/island/*.qml qml/*/*.qml
```

and give each one that draws a panel the same opacity/PauseAnimation block.
Then measure: record an open, count frames where the content is drawn inside
a shape that has not finished growing.

`NEXT-SESSION.md`'s "THE MOTION WORK SO FAR" section has the standing lead —
the settle is the CONTENT, not the shape — and a matrix of ten transition
classes that has never been worked through. Do as much of it as the
measurements support.

### 5. The wallpaper picker needs a real upgrade

Reported: *"the wallpaper popup need upgrades since its too glitch and too
bad. i want that i can use `r` for random and can move with hjkl, but when i
click `/` it do the enter to the searchbar."*

`qml/island/WallpaperPickerLayer.qml`. It already has `r` for random (see
FORK-NOTES). What it needs:

* **hjkl** as well as the arrows — `h`/`l` one thumbnail, `j`/`k` one row.
  `ThemePickerLayer.qml` already does exactly this over a grid; copy the
  shape, do not invent a second one.
* **`/` enters the search field**, and typing filters. This is the MODAL
  pattern `QdropGrid.qml` documents at length: the field is `readOnly` until
  `/`, which is what lets plain letters be motions. `PanelSearchField`'s
  header calls `readOnly` the thing that "keeps focus and inserts nothing".
* `r` keeps working, and Esc/Enter leave search back to command mode.
* Then fix the "too glitch": record it opening and closing and treat it as
  items 2 and 4.

362 images in the library, so also check the thumbnail loading path — a grid
that decodes everything on open is its own kind of glitch.

### 6. The calculator — hjkl does not work, and it needs the rest of the upgrade

Reported twice now: *"the calculator i can not move with hjkl fix and make it
upgraded."*

`qml/island/CalculatorLayer.qml` was made MODAL last session (`3aef5fd`):
insert by default, `Esc` -> normal, then `j`/`k` walk the tape, `g`/`G` its
ends, `y` yanks the result, `Y` the expression, Enter recalls, `i`/`a` resume
typing, `Esc` closes. **The normal-mode motions were never DRIVEN** — that
needs synthetic keys into a live panel — so the first job is to find out
whether they work at all and fix them if not. Likely suspects:

* the field may still be claiming keys when `readOnly` is set;
* `Keys.onPressed` on the FocusScope may never see them because focus is
  inside the field's TextInput — this is the exact bug QdropGrid's
  `focusWanted` signal exists to solve, and its comment describes the
  symptom ("the first Escape left search and the second did nothing").
* `h`/`l` do nothing at all today. Decide what they should mean on a tape —
  probably nothing, in which case say so in the hints rather than leaving
  them dead.

Then the upgrade half, which is untouched:

* **history survives a close** (today the tape is a plain property on a
  non-retained `PanelLoader`, so it dies with the panel). NEXT-SESSION.md
  records a CRASH from `FileView` + `JsonAdapter` with a free-form map — a
  LIST is the shape known to survive, and `QdropStore.qml` is a working
  precedent that sidesteps the adapter with `setText(JSON.stringify(...))`.
  Test it with the topbar as the active bar so a crash cannot take the only
  bar with it.
* a memory register;
* per-row copy from the tape (`y` on any row, not only the latest);
* qalc already does unit and base conversion (`5 km to mi`, `1 GiB to MB`,
  `0xff`) — make sure the placeholder and the hints advertise it.

### 7. NOTCH ON *and* NOTCH OFF are two layouts, and only one was ever checked

Reported: *"fix all possible issues and all cases of notch and notch disabled
like spacing or padding. for example the padding of the top part of all popup
when notch disabled is bad, needs to be a bit bigger since the radius comes
over the text. and some other popups also the top and bottom padding is
missing."*

**This is a whole-shell audit and it is the item most likely to be skimped.
Do not skim it.**

The cause of the named example is known: `Metrics.chromeTop()` is a CONSTANT,
and `PanelChrome.qml` positions the title, the status, the tabs and
`contentY` from it. With the notch ON the capsule's top corners are square
and flush, so a small top inset is right. With the notch OFF the same capsule
has ROUNDED top corners (`radius`), and the corner arc cuts into the first
line of text. `notchProgress` (0..1, in `DynamicIslandWindow.qml`) is the
value that already interpolates between the two forms — the chrome's top
inset has to follow it instead of ignoring it.

Work to do:

* Make the top inset a function of `notchProgress`, in ONE place, and let
  every panel inherit it. Do not patch individual panels.
* Then walk EVERY panel in both states and fix what is wrong. The list is
  the 25 island states in `NEXT-SESSION.md`. `scripts/test/sweep-island.py`
  already drives all of them — use it, capture each, and compare notch-on
  against notch-off side by side.
* Several panels are reported to be missing BOTTOM padding too. `PanelChrome`
  computes `contentHeight` from `root.height - contentY - gap - footerHeight`;
  check that against panels that draw their own footer and those that do not.
* Toggle the notch with the settings panel's "Notch mode" switch, which
  writes `forkNotchMode` to `~/.config/tide-island/userconfig.json`. **Back
  that file up before any test that writes, and diff it after** — it is a
  RULE and it has bitten.

---

## STANDING CONSTRAINTS

* **Never leave the session without a bar.** `bar-switch` exists to protect
  that one rule.
* **The user changes the theme while you work.** Re-read
  `~/.cache/qtile/theme_mode` before a test that depends on it and restore
  what you found.
* **Restore the session when you are done**: theme, workspace, volume,
  layout, cursor position, clipboard, and any daemon you started.
* `.pragma library` JS is CACHED — editing `Motion.js`, `Metrics.js` or
  `Clipboard.js` does nothing until the island is RESTARTED:
  `pkill -x quickshell; setsid -f ~/.config/hypr/scripts/island.sh`.
* A config that reloads cleanly is not a config that works — read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log` and grep for `error`, not
  only for `Configuration Loaded`.
* Adding a property that does not exist fails the WHOLE component, not the
  line. `font.families` is not on the QML font value type; that one took the
  island's tooltip out entirely and said so only in the log.

## WHAT IS ALREADY DONE — do not redo it

The shake gates (5 of them, 11/11 unit shapes + a live matrix with a `--loose`
control), the notch drop target, the shelf's `ctrl+z`/`ctrl+d`, the clipboard
under X11, the theme sweep under X11, qtile's focus steal, the palette
unification, pcmanfm-qt's grid width, the prayer glyph (it was
`nf-md-pulse`, a heartbeat), the tooltip's animation removal, and the island
hover blink. See `git log` — ten commits, each with its measurement.

Still open and NOT in this list: the topbar's 2 px height report (driven and
not reproduced on either bar), the pcmanfm drag offset (cause identified, not
proven), and the long tail in `NEXT-SESSION.md`.
