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

# THE FIRST THING TO DO

**Focus mode. The user reports it does not work and I could not reproduce it.**

Everything I could check is intact, and this is the list so it is not
re-derived:

  * `focusModeChanged` IS handled — `DynamicIslandWindow.qml:4568`.
  * `shellRootController` IS assigned — `shell.qml:737` and `:827`.
  * There is exactly ONE notification entry path, `shell.qml:608` →
    `showNotificationAll`, and it IS guarded by `focusEnabled` at `shell.qml:40`.

So the chain reads correct end to end. Two candidates left, in order:

1. **Focus's only effect is suppressing the island capsule.** It does not
   silence audio, and the notification still lands in the notification
   centre. If "does not work" means "I still get notified", the code is
   behaving as written and the FEATURE is wrong, not the wiring.
2. It could not be driven from here. There is no IPC to set `focusEnabled`,
   and synthesising a keystroke into the panel is forbidden. **Add a
   `tide setFocus(bool)` IPC purely to make this testable** — that is the
   cheapest way to settle it and it is useful beyond the test.

Ask the user what they expect Focus to DO before changing behaviour.

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

3. **The two sliders show no value.** Display and Sound are bars with no
   number, so you cannot tell what level you are at.

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
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **Never synthesise keystrokes into a settings panel.**
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
