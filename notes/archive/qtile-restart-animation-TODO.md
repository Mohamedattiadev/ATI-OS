# Task: smooth qtile restart transition (minimize-to-center → reload → restore)

## Goal

When qtile restarts (`Super+Shift+R`, bound to `_smooth_restart` in
`.config/qtile/config.py` around line 745), all open windows briefly
render in a broken, ugly state: `qtile.restart()` does an in-place
`os.execv()` — the process image is replaced, so for a moment nothing
is managing the existing X11 windows, and once the new qtile instance
re-adopts them the layout (monadtall) hasn't been recomputed yet.
Windows sit at whatever raw geometry they last had, which reads as
everything dumped on top of each other for a frame or several — worse
with more windows open.

Desired UX (user's own words): instead of that ugly stacked flash,
shrink/minimize every open window down to a small icon, animate those
icons converging toward the center of the screen, hold through the
reload, then once qtile has finished restoring window→group/layout
state, animate everything back out to its correct restored position —
a deliberate, polished transition, not a spinner.

## What was already tried and reverted — read this before designing anything

A first attempt froze the user's live desktop and caused an actual X
server crash during testing. Full detail is in the qtile.py git
history / conversation, but the short version:

- Approach: on restart, screenshot the whole screen with `maim`, show
  it fullscreen borderless via `feh --fullscreen --borderless
  --no-menus --title qtile-restart-overlay <shot>`, `time.sleep(0.15)`
  to let it map, then call `qtile.restart()`. On `startup_complete`,
  `pkill -f` the feh process after a delay to reveal the real,
  now-correctly-laid-out desktop (relying on picom's `fading=true` for
  a soft reveal).
- It failed: `feh --fullscreen` was reported by the user as needing a
  manual `Esc` to dismiss/unfreeze, and repeated restart cycles during
  testing correlated with an actual Xorg crash (a fresh Xorg PID
  appeared afterward, and `qtile.log` had shown an
  `xcffib.ConnectionException` around the same window).
- This was tested by directly triggering `Super+Shift+R` /
  `qtile cmd-obj -o cmd -f restart` repeatedly on the user's **live,
  actively-used** desktop session — not an isolated test environment.
  That itself was the bigger mistake: rapid repeated WM restarts +
  fullscreen compositing churn on a real session is inherently risky,
  independent of whether the specific feh approach was sound.
- Everything from that attempt has been fully reverted. Current
  `_smooth_restart()` (line ~745) is back to the original, boring,
  reliable behavior: save layout/window-group state
  (`_save_layout_state()`, `_save_window_group_state()` — see their
  definitions above it), `notify-send`, `qtile.restart()`. No overlay,
  no extra windows, nothing fullscreen.

## Hard constraint for this task: do not repeat that mistake

**Never trigger `qtile.restart()` / `Super+Shift+R` / `qtile cmd-obj
-o cmd -f restart` repeatedly against the user's live session while
iterating on this.** Set up an isolated, disposable test environment
first — e.g. `Xephyr :1 -screen 1366x768` (or similar nested X server)
running a **separate** qtile instance pointed at a scratch copy of the
config (`DISPLAY=:1 qtile start -c /path/to/scratch/config.py`), with
a couple of dummy windows (`xterm`/`alacritty`) opened inside it for
visual testing. Iterate entirely inside that nested session — restart
it as many times as needed there. Only touch the user's real session
once the mechanism is proven stable in isolation, and even then,
trigger it once, confirm it visually (screenshot), and stop — don't
loop.

Also avoid, based on what's now known to be risky in this environment:
- Any *fullscreen, input-grabbing* helper window as part of the
  transition (this is likely what caused the "press Esc" freeze —
  `feh --fullscreen` behaves like an exclusive fullscreen app in some
  WM/compositor combos). If a helper window is used at all, it must be
  a normal floating window that never grabs keyboard/pointer and can
  be killed unconditionally and immediately, with no dependency on the
  user manually dismissing it.
- Rapid repeated compositor state changes (many maim screenshots +
  feh spawns + picom recompositing in quick succession) — space out
  any test iterations.

## Relevant files

- `.config/qtile/config.py` — main qtile config. Restart logic
  (`_smooth_restart`), state save/restore (`_save_layout_state`,
  `_save_window_group_state`, `_load_window_group_state`,
  `_restore_window_group_state`), and the `startup_complete` hook
  (`_init_window_group_state`, ~line 808) all live here. The restore
  hook currently calls `_restore_window_group_state` at 0.6s and 1.6s
  after `startup_complete` — that's your signal for "layout should be
  settled by ~1.6-1.9s post-restart".
- `.config/picom/picom.conf` — compositor config. `fading = true`
  with `fade-in-step`/`fade-out-step` already set; `animations` and
  the real (verified-working) `animation-for-open-window` /
  `animation-for-unmap-window` / `animation-for-transient-window` /
  `animation-stiffness-in-tag` / `animation-stiffness-tag-change` keys
  are documented there (as of this writing `animations = false` — a
  `zoom` preset was found to trigger a real recurring
  `GL_INVALID_FRAMEBUFFER_OPERATION` on this build; `slide-*` presets
  were confirmed clean). **Important**: this is `picom-ftlabs-git`,
  which does NOT support the rich match/trigger/curve "animation-rules"
  schema some other forks have — confirmed by reading its actual
  parser (`src/config_libconfig.c`) and via `strings` on the installed
  binary. Don't reintroduce that schema; it silently parses as inert
  dead config (this exact mistake was made and caught once already).
  Real supported keys only: `animations`, `animation-for-open-window`,
  `animation-for-unmap-window`, `animation-for-transient-window`,
  `animation-for-next-tag`, `animation-for-prev-tag`,
  `animation-stiffness-in-tag`, `animation-stiffness-tag-change`,
  `animation-dampening`, `animation-window-mass`,
  `animation-clamping`, `animation-exclude` (condition list, same c2
  syntax as `shadow-exclude`), and per-`wintypes.<type>.animation`
  string overrides.
- `.config/qtile/scripts/qdrop.py` — existing example of a
  GTK-driven, self-positioned overlay window in this codebase (its
  `show_animated()`/`hide_animated()`/`_slide_move()` around line
  1060+) if a custom animated helper window ends up being part of the
  design. Also a useful cautionary reference: it took several rounds
  to get its own show/hide animation glitch-free (stale GTK
  mapped-state assumptions, qtile's floating-placement re-centering
  on remap, focus not transferring after a qtile-side `togroup()` —
  all documented in inline comments there). Any new animated helper
  window for this restart transition will likely hit similar
  qtile-placement/focus pitfalls; read those comments first.

## Design directions worth considering

1. **Pure picom-side, no helper window**: use
   `animation-for-unmap-window` (e.g. `"minimize"` or `"squeeze"` —
   check these presets for the actual GL_INVALID_FRAMEBUFFER_OPERATION
   bug too, the same way `zoom` was found buggy; only `slide-*` is
   confirmed clean so far) combined with something that triggers an
   unmap-like animation for *all currently-mapped windows* right
   before restart, and `animation-for-open-window` for their reappearance.
   Problem: picom's per-window animation triggers on real map/unmap
   events, and qtile's restart doesn't necessarily unmap real windows
   (they may just get re-parented/re-laid-out without a genuine
   unmap/map cycle) — would need verification in the Xephyr sandbox
   whether this fires at all during a qtile restart, or only on
   individual window open/close.

2. **Client-side GTK helper mimicking qdrop's approach**: a script
   (daemon-style like qdrop.py) that, on restart trigger, screenshots
   *each individual window* (not the whole screen) via `maim -i
   <window-id>`, shows small floating thumbnail chips that animate
   from each window's real position toward screen-center, then on
   `startup_complete` (signaled via a file touch or a tiny local
   socket, similar to qdrop's IPC pattern) animates them back out to
   the restored positions and fades/destroys them. More complex, but
   avoids ever creating a single fullscreen grabby window — likely the
   safer shape given what went wrong last time. Needs the same care
   qdrop.py needed around never letting qtile's floating-placement
   logic re-center these helper windows (see `no_reposition_rules` /
   `Match(wm_class=...)` pattern already used for qdrop at the bottom
   of config.py's `floating_layout`).

3. **Simplest safe fallback if 1 and 2 both prove too fragile**: just
   accept the brief ugly flash but shorten it — e.g. reduce whatever
   delay exists between `execv` and the first `_restore_window_group_state`
   call, or explicitly force a `layout_all()` on every group
   immediately in an earlier hook than `startup_complete`, so the
   "everything on top of each other" window is only a few frames
   instead of up to ~1.6s. This is not the polished ask, but is much
   lower-risk and might be worth doing regardless as a first
   incremental step before attempting 1 or 2.

## RESOLVED — 2026-07-28

### Root cause (measured, not guessed)

Instrumented from *outside* qtile (so the measurement survives the
execv), recording which windows are actually mapped over time:

```
T+0.000  [g3a,g3b]                      normal desktop
T+2.783  [g1a,g2a,g2b,g2c,g3a,g3b]      <-- qtile boot scan maps EVERYTHING
T+5.439  [g2c,g3a,g3b]                  qtile starts hiding foreign windows
T+5.632  [g3a,g3b]                      settled
```

qtile's boot scan maps **every window from every group at once** and
leaves them piled for ~2.2s, then hides the foreign ones ~0.1s *before*
the `startup` hook fires. The ugly frame is entirely inside qtile's own
boot, before any config code exists. Confirmed unfixable from config:
moving the hold to `startup` doesn't help, `client_managed` never fires
for re-adopted windows, and unmapping foreign windows before execv
doesn't help (the incoming qtile maps them again).

The original "layout hasn't been recomputed yet" theory in this file was
wrong. It is not a layout-timing problem.

### Fix

`scripts/qtile-restart-veil.py` — a separate GTK process that outlives
the execv and covers the screen for the duration. `_smooth_restart()`
snapshots the window rects, launches the veil, **waits for the veil to
confirm it has painted** (a fixed delay is not enough; python+GTK
startup outruns it and the pile flashes through), then restarts.
`_veil_signal_done()` fires 1.8s after `startup_complete` and the veil
animates out and exits.

Safety, given the earlier feh incident:
- override-redirect -> WM never manages it, can never take focus
- empty input shape -> all input passes through; cannot block input
- no grabs anywhere
- `--max-seconds` watchdog self-destruct
- plain `kill` disposes of it, no handshake needed
- if anything throws, `_smooth_restart` falls through to a plain
  `qtile.restart()`

### Verified in the Xephyr sandbox

- Full sequence visually confirmed: desktop -> chips converge -> veil
  holds (**no pile visible at any point**) -> chips expand -> correct
  restored layout
- 5/5 consecutive restarts recovered correctly (group/layout/window
  count preserved), zero stray veil processes, input never blocked
- Ported config re-verified end to end in the sandbox: loads clean, full
  rects/ready/done handshake observed

### Gotchas worth keeping

- picom initially made the veil invisible; fixed by explicitly
  resizing/moving/raising the Gdk window on realize. picom.conf already
  excludes `override_redirect = true` from animations.
- `simulate_keypress` via cmd-obj does NOT reach the mod4+shift+r
  binding (modifier list arrives as a string). Call the function
  directly instead.
- Stale `__pycache__/config.cpython-*.pyc` shadows an edited config.py.
  `rm -rf __pycache__` + `PYTHONDONTWRITEBYTECODE=1`.
- qtile truncates its stdout log across execv — debug with an
  append-only file.
- qtile's restart state pickle lives at `$TMPDIR/qtile-state`. If it
  goes missing, `manager.py:171` `os.remove()` raises **uncaught** and
  qtile dies at startup with no WM. Your session has TMPDIR unset (so
  `/tmp`); the sandbox inherited `/home/ati/tmp`, which is how I hit it.

### Still open

- Veil background is hardcoded `#1e1e2e`; could read the active theme.
- Brief black frame as the veil maps; could fade in from the real
  desktop instead.
- Two unrelated real bugs found: group 3's layout drifts monadtall->max
  across restart and the 3s periodic save makes it permanent; and the
  TaskList widget throws `struct.error` (negative width into CopyArea)
  on narrow screens, spamming the log.

## Acceptance bar before touching the user's real session

- Fully working and visually verified (screenshots, not just "no
  errors in log") inside the isolated Xephyr/nested-X sandbox, with
  multiple windows open, across at least 5 consecutive restart cycles
  with no leftover/stuck processes and no input lockup.
- No fullscreen exclusive/grabbing window at any point.
- A clean, obvious kill-switch: if anything about the transition
  fails or times out, it must fall back to just completing the normal
  restart (current safe behavior) rather than leaving a stuck overlay
  or blocked input.
