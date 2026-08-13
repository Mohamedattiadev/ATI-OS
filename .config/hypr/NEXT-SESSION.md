# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles` (branch `test`).

**Read first:** `.config/hypr/upgread_UI_UX.md`. The audit sections at the end
are the measured state, newest last; the numbered findings above them
(P0-1 … P3-10) are the ORIGINAL plan and most are now closed or stale. Where
the plan and an audit disagree, the audit measured it.

---

# WHAT THE LAST SESSION DID

Nine commits, `77bf6b7`..`2317366`. All verified on screen or by measurement
except where each commit says otherwise.

* **The screenshot menu is dm-satty's again** — three steps, its wording, its
  order, the delay restored. The port had reworded every string and dropped
  the middle step.
* **The picker's filter ranks the label above the detail.** "Type c, get
  Clipboard" was losing to two rows that spelled `c` in a file path.
* **The picker was opening EMPTY for one commit** and the user caught it. See
  the rules below — it is the sharpest lesson here.
* **`record` got dm-recordV2's six rows back**, including "Screen + Audio",
  its first row, dropped silently by the port. **`anki`** got its eight prompt
  titles back. **`brightness`** stopped repeating "current: 47%" on every row.
* **Screen corners are off by default** (`forkScreenCornersEnabled`). Measured
  first: they were drawing correctly, in the theme's colour, on all four
  corners. Nothing was broken; the feature was not wanted.
* **The sysmon panel has a battery dial**, the row divides into equal columns
  instead of x=0/centre/right, and the ring dropped 86 → 72 because four
  columns at 86 is where "a bit big" came from.
* **The notification collapse is a real cross-dissolve now.** See below.
* **Night light works** — it was calling a binary that is not installed.

---

# FOCUS — CLOSED, and the answer was scope, not wiring

Resolved in `8c40699`. The wiring was never broken; Focus simply knew about
one interruption. It now suppresses every interruption the shell DRAWS and
nothing you asked for:

  suppressed  notification arriving · bluetooth device connecting ·
              the player auto-expanding on a track change
  kept        workspace capsule · volume/brightness OSDs · panels and pickers

**The shell plays no sound**, so there was never a tone here to silence. A
chime heard during Focus came from the sending application's own PulseAudio
stream and is not reachable from this process. If the user still reports
noise, that is where it is, and muting it is a per-application job.

`tide setFocus(bool)` and `tide toggleFocus` exist now. **Focus is not bound
to a key** — that was left for the user to choose. Binding it is one line in
`binds.conf`.

---

# THE FIRST THING TO DO

**The notification centre rebuild** — item 1 below. It is the biggest
remaining UI complaint and it is blocked on one cheap fact-finding step.

---

# THEN, IN ROUGH ORDER

1. **The notification centre rebuild.** Requested as "the UI is too bad" and
   it is: the delegate at `qml/island/NotificationHistory.qml:210` draws a
   title and a body and NOTHING else. No app icon, no timestamp, no urgency
   distinction — a critical notification is pixel-identical to a low one,
   even though `NotificationLayer` already has an `urgencyColor` ramp for the
   capsule. No per-item dismiss, no actions.

   **BLOCKED ON ONE FACT, resolve it first:** the delegate only ever reads
   `model.summary` and `model.body`, and `notificationModel` comes from the
   compiled `IslandBackend`. Nobody has established whether it exposes
   `appName`, `urgency`, or a timestamp AT ALL. If it does not, the rebuild
   needs a different data path and is a much larger job than it looks.

2. **Unlit quick toggles are too low-contrast.** This is the real finding
   under "Focus has no icon" — the glyph is there and correct; at 1:1, 18 px
   in `textSecondary` on an unlit plate reads as an empty square.

3. ~~The two sliders show no value.~~ **WRONG — do not "fix" this.** The
   readout exists, `ControlSliderCard.qml:129`, at `opacity: root.lit ? 1 : 0`
   — it appears while you are touching the slider and hides at rest, with the
   argument written above it: at rest the fill length IS the value, and a
   number that is always on screen is a number you stop reading. I called it
   missing from a screenshot of the resting state. That is the THIRD time
   this session I have read a deliberate resting state as an absent feature
   (the Focus glyph twice, this once). See the rule below.

4. **`↓ battery` in the control centre's key hints** advertises a section
   that was never got on screen. Verify it exists.

5. **Search on the popups that are not the picker** — control centre,
   notification centre, cheatsheet, launcher, wifi/bluetooth. The picker's
   is the model to copy.

6. **The settings app** (`alt+shift+7`, `island-settings-app.py`). Rejected as
   "terrible looking, not customisable". Reference the user chose:
   `enhaoswen/Dynamic-island-on-hyprland` — same author as the Tide-island
   upstream this is forked from. UNREAD so far.

7. **Per-theme wallpapers.** Every theme gets a fitting default, applied on
   theme change, with manual changes still free.

8. **The theme change's 1.77 s freeze.** Unchanged. See the old notes.

9. **Scratchpads and the Obsidian "S" session** — every case.
   `ilovepdf` is ALREADY bound (`V` in the rofi HUD), so that row of the
   migration table is staler than it looks. Verify before porting.

---

# THE RULES — every one of these was paid for

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **Compare the log's last "Configuration Loaded" against the file's mtime.**
  NEW. A shell.qml edit landed 6 s AFTER the reload its own earlier edit had
  triggered, the watcher never fired again, and a measurement "proving the
  change did nothing" was measuring the old shell. `touch` the file if in
  doubt.
- **A verification step that cannot fail loudly is not one.** NEW, and it
  cost a shipped bug. The check that "proved" the picker still worked ran
  `qs ... ipc call` through a shell VARIABLE holding the whole command line,
  with stderr to `/dev/null`. The shell does not word-split that, so the call
  never ran, and an unchanged screen was read as "resting island" instead of
  "my command failed". The picker shipped opening completely empty.
- **When you widen an enum, grep for every consumer that named its values as
  literals.** Same bug: `matchRank` grew from two ranks to four and the
  bucketing loop still tested `rank === 2` / `rank === 1`, so everything
  ranked higher fell through both tests and vanished.
- **Private-use characters do not survive into what you read back.** NEW.
  A grep for a Nerd Font glyph returns an empty-looking string; that is NOT
  evidence the source is empty. Dump bytes (`.encode('utf-8')`) before
  concluding a glyph is missing — I concluded it twice and was wrong both
  times. Prefer `\uXXXX` escapes when writing them.
- **A screenshot cannot see a gamma change.** NEW. `grim` samples the
  composited buffer; the gamma LUT is applied at scanout. A tinted screen and
  an untinted one are byte-identical to grim. Night light needs eyes.
- **Magnify before believing a glyph is absent.** An 18 px icon in a muted
  colour reads as a blank tile in a 1:1 screenshot.
- **A screenshot shows one STATE, not the feature.** NEW, and it caught me
  three times in one session: the Focus bell (present, faint), and the
  slider readouts (present, revealed on touch). Before filing "X is
  missing", grep for X in the component — this shell hides things on
  purpose and writes down why. An absent feature has no code; a hidden one
  has a binding with a condition in it.
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **Never synthesise keystrokes into a settings panel.** Corollary, learned
  on Focus: a control with no way in from a script is a control whose bugs
  can only be found by the user. If a feature cannot be driven over IPC,
  ADD THE IPC — that is a fix, not scaffolding.
- **`qs ipc call` prints "Function not found" and still EXITS 0.** So the
  exit code is not the check; read the output. Same shape as the
  shell-variable trap above.
- **Close a panel that commits on click before leaving it on screen.**
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
- **Difference two frames; do not just count changed pixels.**
- **The capture region must contain nothing but the thing under test.** For
  island motion, switch to an empty workspace first.
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it afterwards.** Still byte-identical at the end of every
  session so far, this one included.

---

# OPEN, UNSOLVED — do not re-derive these

- **Focus mode.** See above. Wiring verified intact; not reproduced.
- **The ~800 ms panel settle.** NOT re-measured this session. Still the best
  remaining lead on "the popups feel laggy". Two hypotheses already disproven
  (`morphDurationFor`, the slider intro gate).
- **The theme change's 1.77 s frozen screen.** Unchanged. The island's gating
  is correct; the remaining time is behind `THEME_APPLY_VISIBLE_DONE` in a
  script shared with the qtile session.
- **`wf-recorder` is not installed**, so every screen-recording row raises.
  The menu is honest about it in its detail column. Screen recording has
  never worked under Hyprland here.
- **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
  ~50 ms before any animation starts.
- **`layout-cycle.sh` makes 7 `hyprctl` invocations per switch.**

---

# THE NOTIFICATION COLLAPSE, for the record

The user's "it clunks going back to the clock" was NOT the morph. The
geometry eases continuously the whole way with no stall. What was on screen
was the notification text and the clock **both fully opaque, superimposed**,
then a cut — because `showCondition: true` was a literal, so the layer's
out-fade was unreachable and PanelLoader's hold displayed a solid layer
instead of a fading one. This is P1-4's bug, which was found and fixed for
the WORKSPACE layer; its correction claimed the remaining literals were all
swipe layers that must not cross-fade, and the notification layer was swept
up with them incorrectly.

Second, smaller: `clearTransientCapsule()` empties summary and body while
the layer is still alive, so the last thing you saw of a message was the
placeholder "New notification" replacing it — and since that string drives
the width, the capsule re-measured mid-collapse. The value is latched now.
