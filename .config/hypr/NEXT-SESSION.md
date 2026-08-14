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
   STARTED. This is now the largest untouched ask.
3. **Animation glitches everywhere** — the notification→resting "clunk" is
   FIXED. The ~800 ms panel settle is untouched.
4. **Theme change freezes the screen** — PARTLY. The dunst restart is gone
   (it was 0.24 s spent starting a daemon this session does not run, inside
   the freeze). Measured to-marker now: median 1.04 s, min 0.91 s, n=6.
   The remaining ~1.0 s is unexplored.
5. **A fitting wallpaper per theme, applied on theme change** — **DONE.**
   See below.
6. **UI/UX up to the reference island repo's polish** — **RESOLVED, and not
   the way the ask assumed.** The reference repo IS this fork's upstream.
   Nothing to import. See below.
7. **Notification centre UI + control centre broken/icon-less rows** — the
   notification centre is REBUILT. Night light FIXED. Focus FIXED. No other
   broken control found.
8. **Migration leftovers: ilovepdf, scratchpads, the Obsidian "S" session** —
   NOT STARTED. Note `V ilovepdf` is ALREADY bound in the rofi HUD, so that
   row of the migration table is staler than it reads. Verify before porting.

Added by the user across sessions, all DONE: case-insensitive picker search,
battery in the win+` panel, the black screen corners, Focus bound to a key,
**screen recording** (wf-recorder was never installed — now declared and
verified), **the mode keymap popups** (see below).

---

# WHAT THIS SESSION DID — 6 commits, `ef8069e`..`82894ad`

**Ask #6 is answered and the answer is "there is nothing there".**
`enhaoswen/Dynamic-island-on-hyprland` is the former name of
`enhaoswen/Tide-island` — the repo this fork was vendored from. Vendored
1.0.34 against the clone's 1.0.35: one patch release apart, and the fork is
the LARGER tree (67 qml files to 57, 29 fork-only). Upstream's two changed
files were both declined with reasons in `fddcb85`. **Do not clone it again
expecting different contents.**

**Ask #5 is done, in two halves.**
`AtiScriptsV1/theme-wallpaper-gen` generates one wallpaper per theme by
gradient-mapping one of the user's own images onto a ramp built from the
theme's four colours. 21 files in `~/Pictures/Wallpapers/themed/`, 12 MB,
~40 s to regenerate. `AtiScriptsV1/theme-wallpaper` resolves and applies
them; theme-apply calls it after the visible-done marker, and
wallpaper-set.sh rebinds the current theme when you pick by hand.

Selection alone could not have worked and this is measured, not asserted:
scoring all 362 library images against all 21 themes in CIELAB, nine themes
have no acceptable match and **mono-light is off by 137.9** — 90.7 of that
on background alone, because the library is 362 dark wallpapers and
mono-light's background is `#ffffff`.

**The mode keymap popups were dead, and so was workspace-layout.sh.**
Both are socket2 listeners started by autostart.conf, both had exited, and
neither comes back. Submaps kept working because Hyprland handles the keys
itself, so the only symptom was a missing popup. Both now reconnect.

---

# THE FIRST THING TO DO

**The settings app (ask #2).** It is the biggest ask with nothing done to
it, the user's words were "terrible looking, not customisable, not easy",
and every other big item is now either finished or has a measured next step.

`hypr/scripts/island-settings-app.py`, GTK4 over the schema in
`island-settings.py`. The schema is fine; the presentation is the job.
Phase 8 in `upgread_UI_UX.md` already specifies it — read that before
designing anything new.

---

# THEN, IN ROUGH ORDER

1. **Scratchpads and the Obsidian "S" session** (ask #8). Walk every case:
   first launch, re-toggle, focus steal, workspace move, monitor change, app
   already open, app dead. `hypr/scripts/scratchpad.sh`, `toggle-app.sh`.

2. **The rest of the theme-change freeze** (ask #4, remainder). ~1.0 s left
   to the marker. The dunst win is taken; nothing else has been profiled.
   Instrument the blocks between the start and `THEME_APPLY_VISIBLE_DONE`
   before changing anything — the same way the dunst cost was confirmed.

3. **Search on the popups that are not the picker** — control centre,
   notification centre, cheatsheet, launcher, wifi/bluetooth. PickerLayer's
   is the model. NOT the wallpaper picker: it has type-to-jump already, and
   upstream's filter was declined with reasons (`fddcb85`).

4. **The ~800 ms panel settle** (ask #3, remainder). Two hypotheses already
   disproven and NOT to be re-tried: `morphDurationFor` (760 vs 520 measured
   identical) and the slider intro gate. Re-measure before theorising.

5. **The remaining picker menus vs their rofi originals** (ask #1,
   remainder). 12 unchecked: documents, man, notes, clipboard, confedit,
   spellcheck, translate, pass, todo, shared, youtube, hub. **Recheck the
   record menu first** — its six rows were written against a wf-recorder
   that did not exist, and now it does, so they can finally be run.

6. **`islandShowWorkspaceOnAutoHide`** — the one thing in upstream 1.0.35
   worth taking, and only if auto-hide is a mode the user actually runs.

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
- **Toggle IPCs go out of phase.** Prefer explicit show/hide over toggle when
  scripting, and verify the panel is actually up before believing the shot.
- **A control with no way in from a script is a control whose bugs can only
  be found by the user.** If a feature cannot be driven over IPC, ADD THE
  IPC — that is a fix, not scaffolding.
- **`wtype` is installed** and can drive panels for real. A synthesised
  capital arrives with `text` "G" and NO ShiftModifier — check the character,
  not just the modifier.
- **If a metric is applied to two things, first run it on two things KNOWN
  to be equal.** `magick X -colorspace Gray -format %[fx:mean]` reads ~30
  points HIGH on a colour image, because Gray is linear in memory and
  gamma-encoded on disk. Converting an image and measuring it must equal
  measuring the converted file; here it did not, and the gap looked exactly
  like a 70%→40% darkening. A plausible cause was found for the artifact and
  a working implementation was replaced on the strength of it. The
  replacement was better anyway, which is the only reason this cost nothing.

### Reading the UI

- **FOUR TIMES in one session a deliberate design decision was filed as a
  defect** — the Focus glyph (twice), the slider readout, the unlit tile
  contrast. Before filing "X is missing": GREP for X in the component and
  MEASURE the claim.
- **Private-use characters do not survive into what the model reads back.** A
  grep for a Nerd Font glyph returns an empty-looking string; that is NOT
  evidence the source is empty. Dump bytes. Prefer `\uXXXX` when writing.
- **A screenshot cannot see a gamma change.** `grim` samples the composited
  buffer; the gamma LUT is applied at scanout. Night light needs eyes.
- **Magnify before believing a glyph is absent.**
- **Look at the image, not only at the number.** The wallpaper generator
  passed every luminance check while putting LAVENDER TREES in mono-light, a
  theme whose palette is greys plus one navy. Only the contact sheet showed
  it. Nothing numeric was going to.

### Editing

- **When you widen an enum, grep for every consumer that named its values as
  literals.** This is the empty-picker bug.
- **One layout, one arithmetic.** Two descriptions of one layout put the
  notification centre's footer on the desktop.
- **A layer that fills its parent is NOT filling the capsule.** The island
  window is `islandTopMargin + contentHeight + 6`.
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **A background listener that connects to a socket ONCE will die silently
  and stay dead.** `submap-indicator.sh` and `workspace-layout.sh` were both
  found dead mid-session; the only autostart entries still up were the two
  with a `pgrep -x ... ||` re-check behind them. Distinguish "the read ended"
  (reconnect) from "the socket FILE is gone" (Hyprland left). Collapsing
  those two into one condition is what killed both.
- **A "restart" that starts unconditionally is not a restart.** theme-apply
  killed dunst, slept 0.2 s and started it on a session where dunst does not
  run and the island owns `org.freedesktop.Notifications`. `pkill -x` exits 0
  only if it signalled something, which makes it both the kill and the test.

### Safety

- **Never synthesise keystrokes into a settings panel.** Every press writes
  real config.
- **Close a panel that commits on click before leaving it on screen.** A
  stray click changed the desktop theme twice in an earlier session.
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`. This
  also defeats `pgrep -f` CHECKS — `pgrep -af '[s]ubmap-indicator'` still
  self-matched, because the surrounding command line contained the literal
  string. Use `ps -eo args | awk '/pat/ && !/awk/'`, or test the lock file.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.** Byte-identical at the end of every session so
  far, this one included (`dff1139b…`). Keep that true.
- **The capture region must contain nothing but the thing under test.** For
  island motion, switch to an empty workspace first — `hyprctl workspaces -j`
  will tell you which ones are free.
- **Difference two frames; do not just count changed pixels.**
- **The user changes the theme while you work.** `theme_mode` read
  `synthwave` early in this session and `mono-dark` an hour later, with no
  theme picker opened. Re-read it before a test that depends on it, and
  restore what you found rather than what you assumed.

---

# OPEN, UNSOLVED — do not re-derive

- **The ~800 ms panel settle.** Cause unknown, two hypotheses disproven.
- **The theme change's remaining ~1.0 s.** The dunst 0.24 s is taken; the
  rest has never been profiled block by block.
- **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
  ~50 ms before any animation starts.
- **`layout-cycle.sh` makes 7 `hyprctl` invocations per switch**, three of
  them separate `hyprctl clients -j` queries.
- **What killed the two socket listeners.** Not recovered. Nothing in the
  repo kills either one. They now survive a dropped read, but a `kill` from
  outside still ends them for the session, and nothing notices.
