# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles` (branch `test`).

**Read first:** `.config/hypr/upgread_UI_UX.md`. The audit sections at the end
are the measured state, newest last; the numbered findings above them
(P0-1 … P3-10) are the ORIGINAL plan and most are now closed or stale. Where
the plan and an audit disagree, the audit measured it.

---

# WHAT THE LAST SESSION DID

Job B — "restyle every popup" — done as P2-7 rather than beside it, because
extracting the chrome is the only moment at which changing the look is a
four-file edit instead of a twenty-file one.

**Ten surfaces are on `PanelChrome` / `PanelRow` / `PanelTabs` / `KeyHint`.**
The style lives in `qml/common/` now. Read those four files before restyling
anything — the arguments in their headers are load-bearing, especially:

  * the header register (one of two, and why it is the instrument one)
  * accent EDGE = "you are here", accent WASH = "this is true of the system",
    danger fill = "the next keystroke is irreversible"
  * `Metrics.chromeTotal()` for a panel's own height, never `chrome.chromeHeight`

Also closed: P1-6 screen corners, Phase 7 search (theme picker filter), the
Motion.js easing re-audit, the 29 hardcoded whites, and Phase 6.2's lock
screen additions.

---

# THE FIRST THING TO DO

**Re-measure the ~800 ms panel settle.** It is the best remaining lead on "the
popups feel laggy", and the control centre's layout CHANGED last session — it
gained a footer, lost 6 px of slider width and moved to shared chrome. The
previously measured symptom was:

> between +560 ms and +1080 ms the entire content block below the clock shifts
> ~17 px vertically, every open; the clock and battery row do not move.

Do not assume that is still true, and do not assume the restyle fixed it.
Measure it again the way it was measured before — 50 fps grim burst, PPM, a
capture region containing nothing but the panel, and **difference two frames**
rather than counting changed pixels.

Two hypotheses are already disproven and should not be re-tried:
`morphDurationFor` (760 vs 520 measured identical) and the slider intro gate.

---

# THEN, IN ROUGH ORDER

1. **The remaining ten surfaces.** The launcher, cheatsheet, notification
   centre, expanded player, mode-keys HUD, Wi-Fi QR, the workspace overview
   and the swipe layers have NOT been converted. Some should not be — the
   swipe layers are not panels — so this is a per-file decision, not a sweep.

2. **Font rows in the in-island panel — a DECISION, not a task.** The GTK app
   already has them. The island panel does not, because `PANEL_TYPES` in
   `island-settings.py` derives `panel` from the type and excludes `font`:
   there is no text entry under a keyboard grab. The theme picker's filter now
   makes a text-entry-free font picker possible, which would mean adding
   `font` to `PANEL_TYPES`. Worth asking the user before building.

3. **The theme change's 1.77 s freeze.** Unchanged. The remaining win is that
   `theme-apply` spends ~0.24 s restarting dunst, which is not running under
   Hyprland — but that script is in `/usr/local/bin` from AtiScriptsV1 and is
   SHARED WITH THE QTILE SESSION, so it needs a per-session guard proven on
   both.

4. **Keybind latency.** Every island binding spawns a fresh `qs ... ipc call`:
   ~50 ms round trip, measured five times, paid before any animation starts.

5. **`layout-cycle.sh` makes 7 `hyprctl` invocations per switch**, three of
   them separate `hyprctl clients -j` queries. Cache once, batch the
   dispatches.

---

# THE RULES — every one of these was paid for

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`. A failed reload keeps the
  LAST GOOD config running, so a normal-looking desktop proves nothing.
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.** Editing a
  panel you have not opened since the last restart will not trigger a reload.
- **Never synthesise keystrokes into a settings panel.** Every press that
  lands writes real config.
- **Close a panel that commits on click before leaving it on screen.** NEW,
  and it cost a theme change last session: the theme picker was left open on
  the live screen and the desktop theme changed twice from stray clicks. The
  keystroke rule above did not cover the mouse.
- **`pkill -f <pattern>` matches its own command line.** It killed the shell
  running it twice last session, once taking the island down for ~90 s because
  the restart line never ran. Use `pkill -x <name>`, or bracket the pattern.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
  This caught four failures in a row last session, one of which was hyprlock
  EXITING at the moment of lock. Note that killing hyprlock poisons the nested
  compositor's lock state permanently — each test needs a fresh one.
- **Difference two frames; do not just count changed pixels.**
- **The capture region must contain nothing but the thing under test**, and
  the console must be quiet before sampling. A measurement of the wrong region
  is as wrong as a screenshot and comes with a number attached.
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it afterwards.** It has been byte-identical at the end of
  every session so far. Keep that true. Snapshot
  `~/.cache/tide-island/colors.json` too — the theme is state as well.

---

# OPEN, UNSOLVED — do not re-derive these

- **The ~800 ms panel settle.** See above. Cause unknown; two hypotheses
  disproven.
- **The theme change's 1.77 s frozen screen.** The island's gating is already
  correct (it waits on `THEME_APPLY_VISIBLE_DONE`, not process exit). The
  remaining time is behind that marker, in a shared script.
- **The gradient's on-screen height on the lock screen** is arithmetic from a
  measured aspect ratio, not a measured distance — every nested lock
  screenshots a different desktop, so the obvious A/B is confounded.
