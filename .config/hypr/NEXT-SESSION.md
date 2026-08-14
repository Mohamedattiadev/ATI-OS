# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles`, branch `test`.

`~/.config/hypr` and `~/.config/quickshell` are stow symlinks INTO this
checkout, so editing here edits the running desktop. Quickshell hot-reloads
on save.

**Read before touching anything:** the RULES section below, then
`.config/hypr/upgread_UI_UX.md` (audits at the end are the measured state,
newest last; the P0-1…P3-10 findings above them are the original plan and
most are closed or stale — where they disagree, the audit measured it).

---

# THE USER'S ORIGINAL EIGHT ASKS, AND WHERE EACH ONE STANDS

1. **rofi wording/behaviour in the quickshell popups** — DONE for screenshot,
   record, anki, brightness. Not re-checked for the other 12 menus.
2. **The island settings app (`alt+shift+7`) is ugly and unusable** — NOT
   STARTED.
3. **Animation glitches everywhere** — the notification→resting "clunk" is
   FIXED. The ~800 ms panel settle is untouched.
4. **Theme change freezes the screen** — NOT STARTED. 1.77 s, measured in an
   earlier session.
5. **A fitting wallpaper per theme, applied on theme change** — NOT STARTED.
6. **UI/UX up to the reference island repo's polish** — NOT STARTED. The user
   chose `enhaoswen/Dynamic-island-on-hyprland` (same author as the
   Tide-island upstream this forks). **Nobody has read it yet.**
7. **Notification centre UI + control centre broken/icon-less rows** — the
   notification centre is REBUILT (see below). Night light FIXED. Focus
   FIXED. No other broken control found.
8. **Migration leftovers: ilovepdf, scratchpads, the Obsidian "S" session** —
   NOT STARTED. Note `V ilovepdf` is ALREADY bound in the rofi HUD, so that
   row of the migration table is staler than it reads. Verify before porting.

Added mid-session by the user, all DONE: case-insensitive picker search,
battery in the win+` panel, the black screen corners, Focus bound to a key.

---

# WHAT THE LAST SESSION DID — 18 commits, `77bf6b7`..`faa424f`

Every one verified on screen or by measurement; where something could not be
verified the commit says so.

**Pickers.** The screenshot menu is dm-satty's again — three steps, its
wording, its order, the delay step restored (the port had reworded every
string and dropped it). `record` got dm-recordV2's six rows back including
"Screen + Audio", its first row, dropped silently. `anki` got its eight
prompt titles back. The filter now ranks label above detail, so typing `c`
gives Clipboard instead of File.

**The picker shipped completely empty for one commit.** Widening `matchRank`
from two ranks to four while the bucketing loop still tested `rank === 2` /
`rank === 1`. The user found it. See RULES.

**Island.** The notification→resting collapse is a real cross-dissolve now;
it was two layers printed solid over each other because `showCondition: true`
was a literal and the out-fade was unreachable code. Screen corners are off
by default. The sysmon panel gained a battery dial and its row now divides
into equal columns.

**Control centre.** Night light works — `hyprsunset` is not installed and the
branch was a compositor test, not an availability test; gammastep is now the
fallback and is backgrounded, because under wlr-gamma-control a client that
exits takes its ramp with it. Focus now silences everything the shell draws
and is on `$alt SHIFT, N`.

**Notification centre.** Cards show sender, urgency and relative age. Full
vim motions (j/k, g/G, d/x, D, q) with a key-hint footer. The corner radius
was PROPORTIONAL TO PANEL HEIGHT — the only one of eighteen states that was —
so it grew with the notification count until the footer sat beside bare
desktop.

---

# THE FIRST THING TO DO

**Read `enhaoswen/Dynamic-island-on-hyprland`** (ask #6). It is the only ask
with a concrete reference the user chose, it is unread, and it plausibly
informs asks #2 and #7 as well. Clone it somewhere scratch and diff its
approach against this fork's — do not copy wholesale; this fork has three
sessions of measured decisions in its comments.

---

# THEN, IN ROUGH ORDER

1. **Per-theme wallpapers** (ask #5). Most tractable of the big ones and the
   biggest visible win. `hypr/scripts/wallpaper-set.sh` already routes both
   sessions through `~/.cache/wall`; `AtiScriptsV1/theme-apply` is the theme
   entry point and is SHARED WITH THE QTILE SESSION, so any change needs
   proving on both. Themes are listed by `hypr/scripts/theme-list.sh`.
   Requirement: each theme has a default wallpaper, applied on theme change,
   and a manual wallpaper choice still sticks.

2. **The settings app** (ask #2). `hypr/scripts/island-settings-app.py`, GTK4
   over the schema in `island-settings.py`. Rejected as "terrible looking,
   not customisable, not easy". The schema is fine; the presentation is the
   job.

3. **The theme change's 1.77 s freeze** (ask #4). The island's gating is
   already correct (it waits on `THEME_APPLY_VISIBLE_DONE`, not process
   exit). The remaining time is behind that marker inside `theme-apply`,
   ~0.24 s of which is restarting dunst — which is NOT RUNNING under
   Hyprland. A per-session guard there needs proving on both sessions.

4. **Scratchpads and the Obsidian "S" session** (ask #8). Walk every case:
   first launch, re-toggle, focus steal, workspace move, monitor change, app
   already open, app dead. `hypr/scripts/scratchpad.sh`, `toggle-app.sh`.

5. **Search on the popups that are not the picker** — control centre,
   notification centre, cheatsheet, launcher, wifi/bluetooth. PickerLayer's
   is the model to copy.

6. **The ~800 ms panel settle** (ask #3, remainder). Best remaining lead on
   "the popups feel laggy". Two hypotheses already disproven and NOT to be
   re-tried: `morphDurationFor` (760 vs 520 measured identical) and the
   slider intro gate. Re-measure before theorising — the control centre's
   layout has changed twice since the original measurement.

7. **The remaining picker menus vs their rofi originals** (ask #1,
   remainder). 12 unchecked: documents, man, notes, clipboard, confedit,
   spellcheck, translate, pass, todo, shared, youtube, hub. Diff each against
   its `AtiScriptsV1/` original for wording and step order.

---

# RULES — every one of these was paid for, several twice

### Verification

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **Compare the log's last "Configuration Loaded" against the file's mtime.**
  A shell.qml edit landed 6 s AFTER the reload its own earlier edit had
  triggered; the watcher never fired again, and a measurement "proving the
  change did nothing" was reading the old shell. `touch` the file if in doubt.
- **A verification step that cannot fail loudly is not one.** The check that
  "passed" the picker ran `qs ... ipc call` through a shell VARIABLE holding
  the whole command line with stderr to `/dev/null`. The shell does not
  word-split that, so the call never ran, and a blank screen was read as a
  resting island. The picker shipped opening empty.
- **`qs ipc call` prints "Function not found" and still EXITS 0.** The exit
  code is never the check; read the output.
- **Toggle IPCs go out of phase.** Two screenshots this session were of a
  CLOSED panel because a `q` in an earlier test had inverted the toggle.
  Prefer explicit show/hide over toggle when scripting, and verify the panel
  is actually up before believing the shot.
- **A control with no way in from a script is a control whose bugs can only
  be found by the user.** If a feature cannot be driven over IPC, ADD THE
  IPC — that is a fix, not scaffolding. `tide setFocus(bool)` exists because
  of this and immediately proved Focus worked.
- **`wtype` is installed** and can drive panels for real. It also revealed
  that a synthesised capital arrives with `text` "G" and NO ShiftModifier —
  check the character, not just the modifier.

### Reading the UI

- **FOUR TIMES this session a deliberate design decision was filed as a
  defect** — the Focus glyph (twice), the slider readout, the unlit tile
  contrast. All four were "I looked at a screenshot of the resting state and
  something I expected was not shouting at me". Before filing "X is missing":
  GREP for X in the component and MEASURE the claim. An absent feature has no
  code; a hidden one has a binding with a condition in it; a low-contrast one
  has a number you can compute.
- **Private-use characters do not survive into what the model reads back.** A
  grep for a Nerd Font glyph returns an empty-looking string; that is NOT
  evidence the source is empty. Dump bytes (`.encode('utf-8')`). Prefer
  `\uXXXX` escapes when writing them.
- **A screenshot cannot see a gamma change.** `grim` samples the composited
  buffer; the gamma LUT is applied at scanout. Night light needs eyes.
- **Magnify before believing a glyph is absent.**

### Editing

- **When you widen an enum, grep for every consumer that named its values as
  literals.** This is the empty-picker bug.
- **One layout, one arithmetic.** The notification centre computed its height
  in the layer while the child laid itself out top-down from its own header —
  two descriptions of one layout, and the footer landed on the desktop. Three
  attempts at "which height is the real one" failed before the actual fix,
  which was to have only one.
- **A layer that fills its parent is NOT filling the capsule.** The island
  window is `islandTopMargin + contentHeight + 6`. `parent.bottom` is not the
  panel's bottom edge.
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.**

### Safety

- **Never synthesise keystrokes into a settings panel.** Every press writes
  real config.
- **Close a panel that commits on click before leaving it on screen.** A
  stray click changed the desktop theme twice in an earlier session.
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.** It has been byte-identical at the end of every
  session so far, this one included. Keep that true.
- **The capture region must contain nothing but the thing under test.** For
  island motion, switch to an empty workspace first.
- **Difference two frames; do not just count changed pixels.**

---

# OPEN, UNSOLVED — do not re-derive

- **The ~800 ms panel settle.** Cause unknown, two hypotheses disproven.
- **The theme change's 1.77 s frozen screen.**
- **`wf-recorder` is not installed**, so every screen-recording row in the
  picker raises. The menu is honest about it in its detail column. Screen
  recording has never worked under Hyprland here — ask the user whether to
  add it to the install scripts.
- **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
  ~50 ms before any animation starts.
- **`layout-cycle.sh` makes 7 `hyprctl` invocations per switch**, three of
  them separate `hyprctl clients -j` queries.
