# Prompt — next session (Hyprland / Tide Island)

Continue the Hyprland / Tide-Island work in `~/.dotfiles`, branch `test`.

`~/.config/hypr`, `~/.config/qtile` and `~/.config/quickshell` are stow
symlinks INTO this checkout, so editing here edits the running desktop.
Quickshell hot-reloads on save — **except `.pragma library` JS files**
(`Motion.js`, `Metrics.js`, `Clipboard.js`): those are cached and do nothing
until the island is restarted. See RULES below; it cost a fully-down bar
once already.

**Read before touching anything:** the RULES at the bottom of
`hypr/NEXT-SESSION.md`, then the handoff block at the top of it, then
`quickshell/tide-island-fork/FORK-NOTES.md`. Where a doc and an older plan
disagree, the doc that carries a MEASUREMENT wins.

**Do the whole list in one pass. Do not stop to ask which item to start
with**, except where an item below explicitly says the user's wording needs
clarifying before code changes — ask then, not before. Commit as you go, one
concern per commit, reasoning in the message the way the existing history
does. **No Co-Authored-By trailer.**

The desktop is currently: Hyprland, `bar-mode=island`, and **`forkNotchMode`
is FALSE** — the notch is disabled and the island is the floating pill.

---

## WHAT THE LAST SESSION ALREADY DID — do not redo it

Six commits, each with its own measurement, newest first:

    7baeeb5  calculator: normal mode (Escape, j/k, y/Y, i, per-row copy) was
             ALREADY WORKING when actually driven with synthetic keys — see
             item 6 below for what genuinely still needs doing. Tape now
             survives a real restart, persisted to
             ~/.cache/tide-island/calculator-tape.json.
    69009d1  WorkspaceOverviewLayer's fade was the old bare NumberAnimation,
             no PauseAnimation. Fixed.
    506c1ff  NotificationCenterLayer and OnboardingLayer had NO opacity
             Behavior at all — content popped/vanished on the raw boolean.
             Fixed, same choreography as every other panel.
    4c15615  PanelChrome's top text inset (`Metrics.chromeTop()`) now follows
             the capsule's actual corner state (`notchUnround`, pushed from
             DynamicIslandWindow via `Metrics.setNotchProgress()`) instead of
             a flat constant. Verified A/B on the Wi-Fi panel: clean gap at
             notch-off, byte-identical at notch-on.
    0c42261  Item 9 (pcmanfm-qt drag offset) CLOSED. Measured: the drag
             pixmap is libfm-qt's whole ~218px cell, GTK draws no custom
             pixmap at all. Not a Hyprland bug — no compositor-side fix
             exists to make here. See PROMPT-NEXT.md's own item 9 section
             in git history (`git show 5f50cdc:.config/hypr/PROMPT-NEXT.md`)
             for the full writeup if it's needed again.
    966673b  The rofi/chord mode HUD said "bar action" 26 times — labeller
             now looks past the `bar-action` wrapper at its arguments.

New test tools, both already in `hypr/scripts/test/`:

  * `bar-edge.py` — 60fps motion-detection rig for the topbar's edge twitch
    (item 8, old numbering). One clean sweep done at the TOP bar position
    across all 10 popups/boxes: zero edge movement. The BOTTOM position was
    never successfully measured — see STANDING CONSTRAINTS below for why,
    and pick a different capture strategy (a fixed region computed from
    `bar_geometry()` BEFORE recording starts, not a fixed 1000x500 guess).
  * `qdrop-drags.py` — drives N drags into the shelf in a row and counts the
    store. Has a `guard()` called immediately before every synthetic input
    that aborts if the workspace has moved or picked up a stray window —
    added after exactly that happened mid-session. **Use this guard pattern
    for any new synthetic-input test tool**, not just this file's copy of it.

Item 9 (pcmanfm-qt) and item 3 (rofi HUD) from the previous prompt are DONE
and not in the list below. Everything else from that prompt is either
carried forward (renumbered) or superseded by fresher user reports — see
each item.

---

## HOW TO VERIFY, BECAUSE THIS IS WHERE SESSIONS KEEP GOING WRONG

Every item below is a VISUAL or TIMING defect. None of them can be settled
by reading the QML.

```
wf-recorder -o eDP-1 -g "0,0 1366x420" -r 60 -f /tmp/x.mp4
~/.config/hypr/scripts/test/hover-cycle.py 683 16 683 400 4 1.4
ffmpeg -i /tmp/x.mp4 -fps_mode passthrough f%04d.png
```

* **A single `grim` shot is a coin flip against anything sub-second.** Two
  separate misses last session: a drag pixmap (the button had already
  released by the time the shot fired) and a popup's mid-morph frame. Both
  times the fix was the same — a continuous `wf-recorder` capture scanned
  frame-by-frame against a quiet baseline, exactly like `bar-edge.py` and
  the island's hover-blink rig already do. Reach for that FIRST for anything
  that opens, closes, or moves in under a second; do not try a timed
  single-shot capture again and hope the timing lands.
* **A poll loop watching a spawned script's stdout must run it unbuffered.**
  `python3 -u`, not `python3`. Python block-buffers stdout the moment it is
  not a tty, so a marker line a poll loop is grepping for can sit unflushed
  until the process exits — which was AFTER the exact moment the loop needed
  to catch. Cost two capture attempts before the buffering was the found
  cause rather than the timing.
* **`.pragma library` JS is CACHED.** Editing `Motion.js`, `Metrics.js` or
  `Clipboard.js` does nothing until the island is RESTARTED:
  `pkill -x quickshell; setsid -f ~/.config/hypr/scripts/island.sh`. Verify
  the restart itself loaded clean (`Configuration Loaded` in
  `$XDG_RUNTIME_DIR/quickshell/by-id/<newest>/log.log`, no `ERROR`) AND that
  a layer surface actually exists (`hyprctl layers -j`) before doing
  anything else — a QML syntax error here takes the WHOLE bar down with no
  fallback, measured directly last session (a duplicate
  `Component.onCompleted` on one object; two edits to the same object in one
  sitting, easy to do without noticing).
* **An Edit tool write does not always trigger the file watcher.** Measured
  once: an edit to `WorkspaceOverviewLayer.qml` produced no "Reloading
  configuration" log line at all, and a plain `touch` on the same file
  immediately after DID trigger one. If a change does not show up after
  editing, `touch` the file before concluding anything else is wrong —
  absence of the reload line is not proof the shell is still running the
  old version, but it is also not proof it picked up the new one either.
* **Check the workspace IMMEDIATELY before every synthetic mouse or
  keyboard event, not once at the top of a test.** The user is at the
  keyboard while a test tool runs; several seconds of setup (uinput device
  bind alone is ~3.5s) is enough time for them to switch away. A drag fired
  on the wrong workspace once and landed a press+drag inside the user's live
  nvim (harmless — no keystrokes, just a visual-mode selection — but it
  should never have been possible). `qdrop-drags.py`'s `guard()` is the
  pattern: re-check, and abort rather than proceed, immediately before the
  input fires. Keyboard-only tests into a panel that holds an EXCLUSIVE
  keyboard grab are the one exception that does not need this — the grab
  makes it physically impossible for the keys to reach anything else, which
  is how the calculator's normal mode got driven safely.
* **`hyprctl dispatch resizewindowpixel` / `movewindowpixel`, not the
  `...pixelexact` spelling.** The `exact` form answers `"Invalid
  dispatcher"` on stdout with exit 0, so a caller that does not read the
  output sees a silent no-op. `exact` is the first WORD of the argument
  string, not part of the dispatcher's name:
  `resizewindowpixel "exact 420 200,address:0x...`.
* **`PanelLoader`'s `retain: true` means an ordinary close/reopen is not a
  test of anything persisted to disk.** The calculator keeps its item
  mounted across a close specifically so the tape survives — which means
  verifying a NEW disk-persistence path needs a REAL restart
  (`pkill -x quickshell` + `island.sh`), not a close/reopen, or the test
  passes by never having exercised the code path it claims to.
* **A workspace-8-style isolated test window may not open where you
  dispatched it.** `pcmanfm-qt -n <dir>` opens on whatever workspace the
  package's DAEMON's first window already lives on, ignoring the caller's
  active workspace — measured landing a throwaway test window next to the
  user's real one on workspace 3. `hyprctl dispatch movetoworkspacesilent
  "<ws>,address:<addr>"` right after spawn, then verify with `hyprctl
  clients -j` that the workspace is single-occupant before any synthetic
  input.
* **hyprlock is tested in a NESTED Hyprland, never by locking the running
  session.** Item 6 below puts hyprlock in scope for the first time — this
  rule has not had to fire yet this project, but it exists precisely for
  this.
* **A/B or it did not happen.** Run the same gesture before and after with
  the same detector and quote both numbers.
* **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after** — write through `os.replace()` the way
  `island-settings.py` does, not a truncate.
* **Restore the session when you are done**: theme, workspace, volume,
  layout, bar-mode, cursor position, clipboard, and any daemon you started.

---

## THE TASK LIST

Numbered fresh — this is not the previous session's numbering. The user's
own words are quoted verbatim where the report itself is the spec; do not
silently reinterpret them.

### 1. The drop shelf's second drag — still broken, carried over as-is

Reported: *"i can add to it before the dropshelf opened — i shake and then
drag into it — but when it is open i can not use what behind the dropshelf,
i can not drag anything again."* Highest priority last session and still
unresolved.

**Diagnosed exactly, fix attempted, fix confirmed insufficient — do not
re-derive the diagnosis, start from where this left off.**

The mechanism: `DynamicIslandWindow.qml`'s `islandKeyboardFocus` computed
property takes an EXCLUSIVE keyboard grab whenever the shelf is visible and
`!qdropForDrag`. An exclusive grab cancels an in-flight Wayland drag —
measured A/B, `entries 9 -> 9` with the grab against `9 -> 10` without it.
`showQdrop(forDrag)` sets `qdropForDrag = true` only for the FIRST,
shake-triggered drag; `onDropLanded` (in the `QdropLayer` instance around
`DynamicIslandWindow.qml:6510`) sets it back to `false` once that drop
lands, which re-arms the grab — and nothing dropped it again for a SECOND
drag.

**The attempted fix**, already tried and REVERTED because it did not work:
wire `QdropLayer`'s `onDragHovering` (fires from `QdropGrid`'s own
`dragOutStarted`/`dragOutFinished` signals, which had to be added — see
`QdropGrid.qml`'s `Drag.onActiveChanged` and the `tile.Drag.active = true`
call site around line 848) to ALSO set `qdropForDrag = true`, so the grab
drops again the moment a new drag is detected. Verified with `qdrop-drags.py
--open drag --drags 2`: the FIRST drag still lands (unchanged), but the
SECOND is still cancelled — `entries 1 -> 2 -> 2`, not `1 -> 2 -> 3`.

**What that rules out and what is left to try:** the grab's RESTING value at
the moment the second drag begins hovering is not the whole story, because
setting it to non-exclusive still did not save the drag. Candidates,
untested:

* The keyboard-focus MODE TRANSITION itself — not just landing on
  `"none"`/`"ondemand"` — may be what disrupts an already-in-flight OS-level
  drag, independent of direction. Test: drop the grab BEFORE the second drag
  begins (e.g. the instant the shelf regains focus after the first drop)
  rather than reactively on `dragHovering`, and see if a grab that is
  already at rest (never toggled mid-drag) behaves differently from one that
  flips during the drag.
* `DropArea.onEntered` firing is downstream of the compositor's own
  drag-delivery decision — if Hyprland decided to cancel the drag before
  delivery, `onEntered` might simply never fire for the second drag at all,
  which would look identical to "the signal fired but did not help." Check
  with a log line inside `onDragHovering` itself (not inferred from the
  store count) whether it fires at all on drag 2.
* Also fix, once dragging works: with the shelf open, tiles must stay
  clickable/rubber-band-selectable, and `ctrl+z`/`ctrl+d`/`y`/`s`/`/` must
  keep working — this was never re-verified after the grab logic changed.

Test rig: `hypr/scripts/test/qdrop-drags.py --open key|drag --drags N`,
already hardened with a `guard()` — see HOW TO VERIFY.

### 2. Popups still glitch on open/close, partially fixed

Reported: *"still after some popup some glitching happening it fixed with
some and some not."*

The mechanical half of this (a panel with no fade Behavior at all) is done
— see the three commits above. What is NOT done is the frame-level audit the
old item 4 called for and never got: recording an open/close at 60fps and
counting frames where content is drawn inside a shape that has not finished
growing, panel by panel. `grep -L contentDelay` finding "this file never
mentions the word" only proves the mechanical bug class is absent — it does
not prove the TIMING (how long the delay is, whether it matches the actual
morph duration in every case) is right, and it is exactly the kind of thing
that "fixed some, not all" describes.

Adapt `bar-edge.py`'s technique (already proven this session): record a
region around the capsule at 60fps through an open and a close, diff against
a quiet baseline, and report the frame range where content-area pixels
change while the capsule's own outline is still resizing. Do this for
several panels the user has NOT already implicitly confirmed fixed — start
with ones item 4-old never got individual attention: theme picker, wallpaper
picker, the connectivity panels (Wi-Fi/Bluetooth), and the cheatsheet (see
item 8 below, which is likely the same root cause with a display problem
layered on top).

### 3. Animation timing — big popups feel slow/inconsistent

Reported: *"whne i open popup big like rofi or other a bit slowness
happenes i want all the time timing of anmaiton stable and same and smooth
fast no glitching anytime."*

This reads as a DIFFERENT complaint from item 2: not "a frame glitches" but
"the whole open feels slow, and it should feel the same every time." Two
places to look, in order:

1. `Motion.js`'s `springFor(travel, dest)` — the overshoot/duration curve is
   explicitly a function of how far the shape travels (`travel`) — a bigger
   panel (further from the resting capsule) may be getting measurably more
   settle time than a small one, which would read as "some popups are
   slower" even though nothing is broken. Measure `morphDuration()` and the
   actual on-screen open time for a small panel (calculator) against a big
   one (cheatsheet, wallpaper picker) with the same wf-recorder technique,
   and quote both numbers before changing anything.
2. `contentDelay()` — if this is a flat constant, a panel whose SHAPE
   animation legitimately takes longer (a bigger travel) may have content
   painting in before the shape finishes anyway, which is the shape/content
   race item 2 is also about. The fix, if this is the cause, is coupling the
   delay to the actual morph duration for that specific transition rather
   than a single flat number — verify this against measurement before
   assuming it.

Do not tune numbers by feel. This project's whole discipline is measuring
first — see the `springFor()` note in `FORK-NOTES.md` for how the LAST
tuning pass in this exact function was done, and match that rigor.

### 4. Padding — some popups still have the radius over the text

Reported: *"the padding of top and bottom of all the popups since some
popups the rounded radius are on or above the text."*

**Read this carefully before starting: last session's fix in `PanelChrome`'s
`chromeTop()` (see commit `4c15615`) is the ISLAND's chrome only —
`bar-mode=island`.** It does NOT touch `qml/popups/PopupChrome.qml`, which
is a COMPLETELY SEPARATE component with its own fixed `radius:
PopupMetrics.s(14)` and a hardcoded `head_y=28` — used for every popup
under `bar-mode=native` (the qtile-style topbar): wallpaper, network,
volume, display, wifiqr, cheatsheet. If the user is testing under
`bar-mode=native`, or switches between the two, "some popups still have it"
may simply mean "the ones on the OTHER chrome that was never touched." Check
which bar-mode the report was made under before assuming the fix regressed
— it is more likely it was never in scope for these surfaces at all.

Two halves, both open:

* **Audit `PopupChrome.qml` for the identical defect** `PanelChrome` had:
  does it have a fixed-radius, fixed-form popup (no notch morph — it never
  changes shape), in which case the fix might be simpler — a single
  constant top inset increase, verified the same A/B way, rather than a
  `notchProgress`-driven interpolation, since this surface has no notch
  concept at all.
  * **The 12 unchecked picker menus** `NEXT-SESSION.md`'s "still open" list
    already named are on this same chrome and have never been walked.
* **The BOTTOM padding half, on the ISLAND side, still entirely open** —
  this is old item 7's other half and was explicitly left undone last
  session. `PanelChrome.contentHeight` is `root.height - contentY - gap -
  footerHeight`; audit this against panels that draw their OWN footer
  (search for `footerExtraHeight` usage) versus the ones that rely purely on
  `KeyHint`'s built-in footer — the doc's own suspicion was that a
  custom-footer panel might be double-counting or under-counting relative to
  `PanelChrome`'s assumption.

Use `scripts/test/sweep-island.py` to drive every state in both notch forms
for the island half; for the `PopupChrome` half there is no equivalent sweep
tool yet — `popups.qml`'s IPC targets (`qs -p
~/.config/quickshell/tide-island-fork/popups.qml ipc show`) are the way in,
one call per popup, same as `bar-edge.py` already drives them.

### 5. Wallpaper picker — upgrade, fix the glitch, fix the size

Reported: *"the wallpaper popups need upgrade in ui+ux and its glitching
while opening and popup too big fix."*

Three parts, and the first is carried over UNSTARTED from last session's
list (never got to it):

* **hjkl + `/`-gated search**, exactly as `ThemePickerLayer.qml` already
  does over a grid — copy that shape rather than inventing a second one.
  `h`/`l` one thumbnail, `j`/`k` one row, `/` enters search (the field is
  `readOnly` until then, same `PanelSearchField` pattern the calculator and
  the shelf both use), `r` keeps working for random, Esc/Enter leave search
  back to command mode.
* **The glitch on open** — likely two candidates, both testable with item
  2's recording technique: the same content/shape race as everything else
  in item 2, OR (the doc's own standing suspicion) 362 images decoding
  synchronously on open. Check `WallpaperThumbnailCache.qml` for whether
  thumbnail decode is async and cached, or blocking the first paint.
* **"too big" — measure it.** Compare `WallpaperPickerLayer`'s
  `preferredHeight`/width against the screen (1366x768) and against what
  the OTHER grid panels (theme picker, application launcher) use for the
  same 6-column-ish layout. If it is filling most of the screen where a
  peer panel is not, that is the concrete thing to shrink — likely the tile
  size or the row count shown before scrolling, not a global scale change.

### 6. The calculator — needs clarification, then a real feature, not a bug fix

Reported: *"the calcloter still not good i can write any letter `i` for
exmaple which means nothing ,so make a spaceifc latters or simplers ref
person can write and i wnat hjkl to move left right up down etc."*

**Read item 6 in the previous PROMPT-NEXT.md's own transcript first** — last
session drove EVERY normal-mode key with synthetic input (Escape, j/k, g/G,
y, Y, i/a, Escape-Escape) and every one of them worked exactly as designed,
confirmed with grim captures showing the tape cursor actually move. So this
is not a re-diagnosis; it is new, different feedback, and the two halves of
it need different handling:

* **"i can write any letter i which means nothing"** — likely about INSERT
  mode, where the field is a free-text `TextInput` and anything typeable
  reaches `qalc`, including letters that are not valid unit names and
  produce a confusing answer or `qalc`'s own "resolves an unknown identifier
  as a UNIT" trap (documented at the top of `CalculatorLayer.qml` — e.g.
  `frobnicate(3)` returns a confident nonsense unit rather than erroring).
  **Ask the user which they mean** if the session is attended: restrict
  typing to a smaller character set (digits, operators, a fixed list of
  known unit abbreviations), or clearer on-screen feedback when qalc's
  answer is a unit-trap nonsense result rather than a real one — those are
  different features. **If unattended, build the feedback half** (it is
  strictly additive, reversible, and helps regardless of which reading is
  right — e.g. visibly flag a result when the expression contained a bare
  unrecognised word qalc silently turned into a unit) and say in the commit
  that the character-restriction reading was left for the user to confirm.
* **"i want hjkl to move left right up down etc"** — an explicit re-ask
  after last session's normal-mode audit concluded h/l have no natural
  meaning on a 1-D tape and left them unbound. The user wants them bound
  anyway. The natural meaning for h/l that j/k does not already cover:
  **character-wise cursor movement inside the CURRENT expression**, vim-style,
  while in normal mode — h/l move the text cursor left/right in the (still
  visible, not-yet-committed) expression rather than navigating the tape.
  This is a real feature to design and add, not a bug: decide whether h/l
  in normal mode edit the box's cursor position (requiring a switch back to
  a focused-but-not-fully-insert state) or do something else, implement it,
  and update the hint bar (`chrome.hints` in `CalculatorLayer.qml`) to
  advertise whatever they end up doing — the hints currently correctly say
  nothing about h/l, which stops being correct the moment they do something.

Remaining upgrade item from the original list, still open: **a memory
register** (store/recall a value, e.g. `M+`/`MR`-style). Not investigated at
all yet.

### 7. Docs and cheatsheet — too small, model them on qtile's own

Reported: *"the documention and cheat ones are so small and can not seen and
hard i think can we make them more like the one in qtile? but as popups?"*

The REFERENCE design the user is pointing at is qtile's own cheatsheet
popups — read `~/.config/qtile/popups/QtileCheatsheet.py`,
`VimCheatsheet.py` and `FishCheatsheet.py` for their sizing, font size and
layout before touching the island's version, since "more like the one in
qtile" is a concrete, comparable spec sitting right there rather than a
vague preference.

The island's own cheatsheet is `qml/cheatsheet/CheatsheetLayer.qml` (583
lines) for `bar-mode=island`, and `qml/popups/CheatsheetPopup.qml` (442
lines) for `bar-mode=native` — **two separate files, likely both need the
same treatment**, the same split as item 4. `cheatsheet.py --sheet-json`
is what both read their ROWS from (unchanged, still correct per item 3's
fix last session) — this item is about the CONTAINER's size and type scale,
not the data.

### 8. Theme popup, and a cluster of other surfaces — glitch reports needing triage

Reported: *"the theme popup when opens a glitch happens also the man popup
u also lock one, reording, barr swithchig ppoup. and the documentions and
cheets"* [sic — transcribed verbatim; "reording" almost certainly means
"recording", "man popup" is unclear and worth confirming with the user].

Five surfaces named, of very different kinds — **triage each before
assuming it is the same bug as item 2**:

* **Theme picker** — `ThemePickerLayer.qml`. Likely the same content/shape
  race as item 2; measure with the same recording technique before assuming
  so.
* **"the man popup"** — unclear. Possibly "main popup" (which one — control
  centre? the resting capsule itself?), possibly a mis-transcription of
  something else. **Ask the user to clarify which surface this names** if
  the session is attended. If unattended, skip this one specific sub-item
  rather than guessing which surface it is and fixing the wrong thing — it
  is one line item out of eight and not worth spending unattended time
  guessing at; leave a note in the summary that it needs a name.
* **The lock screen (hyprlock)** — `hypr/hyprlock.conf`. Not previously in
  scope for this project's visual-glitch work at all. **Test in a NESTED
  Hyprland — see HOW TO VERIFY — never by locking the actual running
  session.**
* **Recording** — `qml/island/RecordingIndicator.qml`. Check what
  "glitching" means here specifically; this is a small always-on-top
  indicator, not a panel with a shape morph, so item 2's cause may not
  apply and the defect could be something else entirely (position,
  z-order, a stale binding).
* **The bar-switching popup** — this is `AtiScriptsV1/bar-chooser`, a plain
  **rofi** menu (`rofi -dmenu -i -p "Which bar?"`), not part of the
  Quickshell tree at all. A "glitch" here is either a rofi theming/config
  issue (`~/.config/rofi/` or whatever `bar-chooser` passes on its `rofi`
  invocation) or a timing issue in the script itself — start by reading
  `bar-chooser` end to end, since this is a much smaller, simpler surface
  than everything else on this list.

### 9. Calendar — clicking a day should let you add a reminder

Reported: *"calender when i click on the day i can add reminder or
somthing."*

A real feature, not a bug: `qml/island/CalendarLayer.qml`'s day cells
currently have only `onEntered` (hover moves `root.cursor` to that day,
around line 519) — there is no `onClicked` at all, and `markedDays` (a
plain `{day: bool}` map, around line 107) only marks days, it does not hold
any text. Needs, in order:

* A click handler on the day cell (`MouseArea` already there for hover —
  add `onClicked`).
* Somewhere to show/edit a reminder's text for the clicked day — a small
  inline field or a second small panel state, the caller's call; look at how
  the calculator's `PanelSearchField` or the shelf's inline editing is done
  for the pattern this shell already uses rather than inventing a dialog
  primitive.
* Storage: a `{ "YYYY-MM-DD": "reminder text" }` map persisted the same way
  item 6 already established for the calculator's tape — `FileView` +
  `setText(JSON.stringify(...))`, NOT a `JsonAdapter` (see the calculator
  commit for why). A new cache file,
  `~/.cache/tide-island/calendar-reminders.json`, following the same
  `~/.cache/tide-island/` convention `colors.json` and the calculator's tape
  already use.
* `markedDays` should probably become "has a reminder" once this exists,
  rather than being a separate concept — check what currently FEEDS
  `markedDays` before deciding whether to merge or keep them separate.

### 10. Control centre — drop battery, add the music player, go minimal

Reported: *"make the control center contain the music player, no need for
battery thing, and making its ui ux like the mac one — the display and
sound one and wifi and other buttons — and i think making it with toggle
on/off (0===)(===0) will be better and when i click on it opens the network
or bluetooth thing, control center should be more minimal and simpler."*

A substantial redesign of `qml/controlcenter/ControlCenterLayer.qml`, not a
small fix. Three changes, and they should probably be three commits:

* **Remove the battery mode drawer.** It is deeply built in — a whole drag
  gesture, TLP integration, a settling animation
  (`batteryDrawerOpen`/`batteryDrawerDragging`/`batteryModeIndex` and
  friends, roughly lines 73-360). Read what depends on it elsewhere
  (`controlCenterExtraHeight`, `controlCenterMaximumExtraHeight` feed the
  capsule's sizing in `DynamicIslandWindow.qml`) before deleting — removing
  the drawer changes how tall this panel is allowed to get.
* **Add the music player.** Do not build a new one — `ExpandedPlayerLayer.qml`
  and `IslandMprisController.qml` already do this for the hover-expanded
  player; reuse or embed that, the same way this fork's own convention is
  "one body, N frames" (see `QdropGrid.qml`'s header for why that pattern
  exists, and copy it rather than writing a second MPRIS reader).
  `PlayerControlButton.qml` is the existing transport-button component.
* **Toggle-switch style for Wi-Fi/Bluetooth/etc, macOS-style.** The
  "(0===)(===0)" in the report is the user drawing a slider toggle in text —
  a switch that shows on/off AND, on click, opens the fuller panel
  (network/Bluetooth) rather than the toggle being the only affordance.
  `ControlSliderCard.qml` is the closest existing component (used for
  brightness/volume sliders currently) — check whether it can grow a
  boolean/toggle mode or whether a sibling component is cleaner. This is a
  visual-language decision as much as a code one; screenshot the current
  cards, mock the toggle shape, and confirm the shape reads as a toggle
  before wiring the click-opens-panel behaviour on top of it.
* **Follow-on, once the player is in the control centre:** *"since u will
  add the player to control center no need for the click right one which
  opens the player make it open the calendar the right click ok."* Right-
  click on the island's capsule currently opens the expanded player — this
  is `userConfig.dynamicIslandSecondaryAction`, a PACKAGED-backend config
  value (`~/.config/tide-island/userconfig.json`), currently
  `"toggleExpandedPlayer"`. Two changes, not one: (1) the value needs to
  become something like `"toggleCalendar"`, and (2)
  `handleConfiguredClickAction()` in `DynamicIslandWindow.qml` (the switch
  starting around line 2739) does not have a `case` for it yet — it has
  `toggleExpandedPlayer`/`openExpandedPlayer`/`closeExpandedPlayer` and
  `toggleNotificationCenter`/`open.../close...` pairs for other panels, but
  no calendar equivalent; `showCalendar()` already exists
  (`islandContainer.showCalendar()`, called from `toggleCalendarWindow()`
  around line 1695) as the function to call. Add the `case`, following the
  exact shape the existing ones use, then change the config value and back
  up/diff `userconfig.json` the way every other write to it in this project
  does.

"More minimal and simpler" is the design goal driving all three — resist
adding new individual toggles beyond what is asked for, this is a
subtraction task first (battery out) and a consolidation task second
(sliders in one visual language).

### 11. The island should show an active border while a notification is up

Reported: *"when notification appears the island should be with border
active."*

There is already a border-state mechanism to extend rather than invent a
second one: `mainCapsule`'s `border.color: outlineColor` (around line 5499,
`Behavior on border.color` at 5368) and the separate
`borderFocusProcess`/`onOpenPanelStateChanged` machinery (line 1354, 2234)
that dims OTHER windows' borders while a panel is open. Check whether
`outlineColor` already has a state for "something needs attention" or only
for "focused" — the notification case wants the capsule's own outline to
change (probably to `IslandTheme.accent` or a dedicated notification colour)
for as long as an unread/new notification exists, which is a different
lifecycle than a panel being open (a notification can arrive while the
capsule is RESTING, closed). `NotificationService.qml` / `NotificationLayer.qml`
own the arrival event this needs to key off; wire a
`hasUnseenNotification`-shaped property from there into `mainCapsule`'s
border colour expression rather than duplicating the notification-tracking
logic.

### 12. Wallpapers — rename by theme fit so search finds all matches, then commit BOTH repos

Reported: *"i want the images which fit the theme i want to rename them with
the themename and then_number so when i search for them and write gruvbox
for example it shows me all fitting ones, and update commit the wallpaper
repo after that and commit here also."*

**Read before renaming anything — the mapping this needs already exists,
twice, in two different shapes:**

* `~/.cache/qtile/theme-walls.json` — `{ "gruvbox": "<one path>", ... }`,
  one wallpaper per theme, and several of those paths are already files in
  the FLAT pool (`~/Pictures/Wallpapers/0004.jpg` for `gruvbox`, for
  example) — no theme name in the filename at all today.
* `~/.cache/qtile/theme-wall-last.json` — same shape, and several of ITS
  paths point at `~/Pictures/Wallpapers/themed/<theme>/fetched-NN.jpg`, a
  PER-THEME SUBDIRECTORY that already groups images by theme, just not by
  filename.

**`WallpaperPickerLayer.qml`'s search is over `userConfig.wallpaperLibraryPath`
— check what that resolves to first.** If it is the flat
`~/Pictures/Wallpapers/` directory only (not the `themed/` subdirectories),
then a search for "gruvbox" cannot find `themed/gruvbox/fetched-11.jpg` no
matter how it is named, because the picker never lists that directory at
all — in which case the fix is not a rename, it is either widening the
picker to also list `themed/*/`, or copying/renaming the themed images INTO
the flat pool. Confirm which before doing either.

**This repo (`~/Pictures/Wallpapers`) has a REMOTE — this is not a local
scratch rename.** Use `git mv` for every rename so history follows the file
rather than showing a delete+add, and there is a RULE already on record
(`NEXT-SESSION.md`'s RULES) warning this repo needs care. Once files move:

* `theme-walls.json` and `theme-wall-last.json` (and anything else in
  `~/.cache/qtile/` or `~/.cache/tide-island/` holding an absolute path into
  this repo) now point at names that no longer exist — these are CACHE
  files, probably fine to regenerate, but check whether anything treats
  their absence as an error before assuming that.
* Commit the wallpaper repo first (the rename), THEN commit here in
  `~/.dotfiles` if anything in this tree references specific wallpaper
  filenames (grep for `.jpg`/`.png` literals under `.config/` before
  assuming nothing does) — "commit here also" in the report means this
  second commit, not a duplicate of the first.

### 13. Island Settings (alt+7) — smaller, a real toggle, and not centre-screen

Reported: *"make this setting when open a bit smaller height and width and
make it toggleble and the one with alt+7 make it appears as popup like the
other popups not appearing in middle of the screen fix this."* (Screenshot
attached showing the current centred `Island Settings` panel with its
Preview pane and chip grid.)

**This is a direct reversal of a PAST explicit request, and the code says so
— read `DynamicIslandWindow.qml`'s `detachedPanelActive`/`detachProgress`
section (around line 780-815) before changing it.** The comment block there
records the original ask verbatim: *"the size of the island setting should
be centered and float and a bit smaller when it opens"* — this is exactly
why settings is the one state that gets the DETACHED, screen-centred form
instead of the normal notch-anchored morph every other panel uses. The user
is now asking for the opposite. That is a legitimate change of mind, not a
contradiction to resolve by picking one — implement the NEW request, but
say explicitly in the commit message that this reverses the earlier
decision on record, with both quotes, so a future session does not "fix"
it back.

Two changes, and they may turn out to be the same root cause:

* **"appears in the middle of the screen" -> make it a normal popup.**
  Remove settings from whatever makes `detachedPanelActive` true (currently
  `islandContainer.islandState === "settings"`), so `detachProgress` stays 0
  for this state and it inherits the ordinary notch-anchored morph
  every other panel gets — same family as control centre, wallpaper picker,
  etc. Verify with `sweep-island.py` and a screenshot that it now opens from
  the capsule like its neighbours.
* **"a bit smaller height and width"** — measure the CURRENT size
  (`sweep-island.py --states` already reports `h=`/`w=` for `settings`) and
  compare against a neighbouring panel like the theme picker before picking
  a target; do not guess a number.
* **"make it toggleble"** — `toggleSettingsWindow()`
  (`DynamicIslandWindow.qml` ~line 1771) and the `tide toggleSettings` IPC
  it is wired to (`shell.qml` ~line 998) ALREADY implement close-if-open
  toggle logic at the state-machine level. Drive it twice in a row over IPC
  (`qs ipc call tide toggleSettings` / `toggleSettings` again) and watch
  what actually happens before assuming this needs new logic — it is quite
  possible the DETACHED form above is what makes toggling feel broken (a
  modal-feeling centred dialog reads as "not a toggle" even when the state
  machine underneath is one), in which case fixing the popup-form half
  fixes this one too, and the fix here is confirming that rather than
  writing new toggle logic that already exists.

### 14. Workspace switching is blocked while any island popup is open — CLOSED

Reported: *"when it is open the shelf i can not switch to another workspace
also some other popups the same fix."*

**CLOSED, commit `6c05996`.** The real cause was one level deeper than the
write-up below assumed while it was still open: not keyboard routing, but
Hyprland itself refusing `workspace N` outright — even via a bare `hyprctl
dispatch workspace 8` with no keyboard involved — for as long as anything
holds `WlrKeyboardFocus.Exclusive`. Fix: both hosts (island's
DynamicIslandWindow/IslandWindowWayland, and native popups' shared
PopupChrome, which QdropShelf overrides for its drag case) now drop
Exclusive to OnDemand only for exactly as long as Super is physically held
(Key_Meta press/release, 600ms Timer as a safety net), rather than for the
popup's whole time open. Verified live on the island host: real `super+8`
switched workspace with the shelf open, and hjkl still moved the shelf's
selection with no click needed afterward, so the earlier "instant keys"
fix is not regressed. The native-popup host mirrors the same mechanism but
was not exercised live — bar mode was island at the time and switching it
just to test would have meant flipping the user's whole panel setup out
from under them mid-session. Worth a quick live A/B under native mode next
time it's up anyway, same rig as below.

The original write-up, kept for the reasoning trail:

**MEASURED, not guessed — and it is one shared bug, not one per popup.**
Opened the shelf (`qs -p ~/.config/quickshell/tide-island-fork ipc call
qdrop open`), confirmed it visually open, then pressed a real synthetic
`super+8` (`uinput-key.py super+8` — a genuine evdev device, not `wtype`).
`hyprctl activeworkspace -j` stayed on the workspace it started on; the
switch never happened. `hyprctl binds` confirms `SUPER,8` is an ordinary,
unflagged global bind (`modmask: 64`, `submap: ""`, `dispatcher: workspace`)
— nothing about it should require the shelf's cooperation. The bare `8`
did not reach the shelf either: it leaked into an unrelated window that
still happened to hold focus, meaning the key was consumed/rerouted
somewhere in the compositor's focus handling rather than being matched
against the bind table at all.

**Where this lives, and why "some other popups the same" is expected
rather than a coincidence:** every popup that sets `islandKeyboardFocus` to
`"exclusive"` shares ONE mapping, in `IslandWindowWayland.qml`:

    WlrLayershell.layer: island.islandRestingSurface ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: … "exclusive" -> WlrKeyboardFocus.Exclusive …

The `"exclusive"` list itself is in `DynamicIslandWindow.qml` around lines
545-616 — it is the shelf, calendar, cheatsheet, calculator, theme picker,
wallpaper picker, wifi/bluetooth detail panels, the generic picker,
settings, power menu, onboarding, application launcher, and the
display/audio/sysmon panels and wifi QR. Any popup on that list is
`WlrLayer.Overlay` + `WlrKeyboardFocus.Exclusive` while open, and that
combination is the current best suspect for swallowing the global bind —
test that theory directly (see below) rather than assuming which half is
guilty.

**The obvious fix (drop to `WlrLayer.Top` while open) is not free — this
was already tried once.** `islandRestingSurface`'s own comment in
`DynamicIslandWindow.qml` records that Top-while-open was reverted because
it let fullscreen windows cover the popup. Re-testing that trade needs the
same rigor: A/B with a fullscreen window present AND a workspace-switch
keypress, not just one or the other.

**Candidates to measure next session, in order:**

1. Try `WlrKeyboardFocus.OnDemand` instead of `Exclusive` while keeping
   `WlrLayer.Overlay`, and re-run the exact `super+8` test above. OnDemand
   is already used successfully elsewhere in this file for the
   shake-triggered shelf drag (`qdropDragSession`, same file, the branch
   right below the exclusive list) — same precedent, different symptom.
   Same caveat applies here too: OnDemand is not a guaranteed grab, so
   confirm hjkl/search-field typing still reaches the popup before calling
   this a fix, not just that the workspace switch now works.
2. If OnDemand does not restore the bind either, this may be a genuine
   Hyprland-level behavior of `WlrLayer.Overlay` + `WlrKeyboardFocus.Exclusive`
   rather than anything this repo's QML controls — isolate it with a
   minimal non-Quickshell layer-shell client (`layer-shell-qt` demo, or
   `wlr-layer-shell` example) set to the same layer/focus combo, before
   concluding it needs an upstream Hyprland report instead of a local fix.

**Verify with the `guard()` pattern** (`NEXT-SESSION.md` RULES,
`qdrop-drags.py`'s copy) before any synthetic keypress here — this item's
own repro needs a popup open AND a real key event, which is exactly the
combination that has gone wrong mid-test before in this project when the
user changed workspace or theme underneath a running test.

---

## STANDING CONSTRAINTS

* **Never leave the session without a bar.** `bar-switch` exists to protect
  that one rule. After any `.pragma library` restart, verify with `hyprctl
  layers -j` before doing anything else — do not trust the log alone.
* **The user changes the theme and switches workspaces while you work.**
  Re-read `~/.cache/qtile/theme_mode` before a test that depends on it, and
  re-check the active workspace immediately before every synthetic input —
  see HOW TO VERIFY.
* **Restore the session when you are done**: theme, workspace, volume,
  layout, bar-mode, cursor position, clipboard, and any daemon you started.
* `.pragma library` JS is CACHED — see HOW TO VERIFY.
* A config that reloads cleanly is not a config that works — read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log` and grep for `error`, not
  only for `Configuration Loaded`.
* Adding a property that does not exist fails the WHOLE component, not the
  line. Two `Component.onCompleted` on one object does the same — check for
  an EXISTING handler before adding a new one to any object, not just
  properties.
* **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.**

## WHAT IS ALREADY DONE — do not redo it

Everything in "WHAT THE LAST SESSION ALREADY DID" above, plus everything the
session before that already closed: the shake gates, the notch drop target,
the shelf's `ctrl+z`/`ctrl+d`, the clipboard under X11, the theme sweep
under X11, qtile's focus steal, the palette unification, pcmanfm-qt's grid
width AND its drag-pixmap diagnosis (item 9, closed), the prayer glyph, the
tooltip's animation removal, the island hover blink, the rofi/chord mode
HUD's labels, the topbar edge twitch at the TOP bar position (measured
clean), the calculator's persistence and normal-mode keys (measured
working). See `git log` — every commit carries its own measurement.

Still open and NOT rewritten above because nothing changed about them: the
login notification burst (needs a real logout), the topbar edge twitch at
the BOTTOM position (attempted, capture geometry bug, never got a clean
measurement — see the bar-edge.py note in "WHAT THE LAST SESSION ALREADY
DID"), scratchpads on a second monitor, the drop shadow still assuming the
flush form, live preview for the cheap numeric settings keys, keybind
latency (~50 ms of `qs ipc call` before any animation starts), and
`parse_task_name`'s short-subtitle strip.

---

## IF THE SESSION RUNS SHORT

Item 1 (the shelf) is the highest-priority carryover and the user has now
reported it more than once across two sessions. Item 4's `PopupChrome` half
and item 8's clarification-needed items are cheap to at least TRIAGE even if
not fully fixed. Items 6 and 8 name a clarifying question each ("the man
popup", and which of two readings of the insert-mode complaint is meant) —
**ask them if the session is attended; if it is running unattended and
nobody answers, do not stall on it.** Pick the more conservative/reversible
reading, say so explicitly in the commit message and in the final summary
("assumed X because Y; revisit if wrong"), and keep going through the rest
of the list rather than blocking the whole session on one open question.
Item 12 (wallpaper renaming) touches a git repo with a remote and should be
done carefully rather than rushed if time is short — a half-renamed
wallpaper repo is worse than an unstarted one. Item 13's three sub-parts may
collapse to one fix (see its note on why "toggleble" might just be a
side-effect of the centred form) — try the popup-form change first and
re-test toggling before writing separate logic for it. Do items 2, 3 and 5's
glitch half only as far as measurement supports, and say plainly in the
summary what was measured, what was fixed, and what is still open —
including
anything that could not be driven and why.
