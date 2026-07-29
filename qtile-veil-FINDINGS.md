# Restart veil — measured findings (2026-07-28)

Measured in the Xephyr sandbox per `qtile-veil-HANDOFF.md` (3 windows,
picom `xrender`). The live session was never restarted. Absolute numbers
are sandbox numbers — the *shape* of the budget is what transfers, not the
totals. See "How to measure on the real machine" below.

## The restart budget, measured

Probes written to an append-only file (survives execv), one run shown;
three repeats agreed within ±0.3s.

| Phase | Cost | Owner |
| ----- | ---- | ----- |
| `_veil_launch()` — build `veil_rects.json`, write raw `_NET_WM_ICON` bytes per window, write tips, spawn | **0.675s** | ours |
| wait for veil to report painted | 0.434s | ours |
| validation config load (old process, `manager.py:301`) | 0.105s | qtile |
| execv + interpreter + `libqtile` import | **1.72s** | fixed |
| real config load (new process, `manager.py:129`) | 0.274s | qtile |
| core init + window scan → `startup_complete` | **1.20s** | qtile |
| **total** | **4.55s** | |

### CORRECTION (2026-07-28, from the user's GIF)

**The sandbox understates the real machine by ~2.5x. Do not use the table
above as their numbers.** A screen recording of a real theme-change
restart, read off the veil's own elapsed counter:

| veil timer | stage | % |
| ---------- | ----- | - |
| 0.8s | restarting window manager | 21% |
| 3.7s | restarting window manager | 22% |
| 6.7s | restarting window manager | 22% |
| 9.7s | restoring windows | 80% |

`"Restarting window manager"` is set immediately before `qtile.restart()`
and the next update comes from the *new* process, so that label's dwell
time **is** the execv → interpreter → `libqtile` import → config load →
core init → window scan span. On the real machine that is **>7s**; the
sandbox measured 3.2s for the same span.

So the handoff's "~11s" was **right for the real machine**, and my earlier
claim that it was "gone" was wrong — it was measured on 3 windows with no
real widget backends, against a 32-widget bar and a full desktop. The
sandbox is still the right place to test *behaviour*; it is not a
stand-in for their *timings*.

This also answers the handoff's open question ("ask them which stage text
sits longest") without needing to ask: it is the qtile-internal startup
phase, not anything the veil or the config does around it.
- **The config module is loaded twice per restart, and that is correct.**
  `manager.py:301` loads it in the *old* process purely to refuse the
  restart if it would not parse — the safety feature that stops a typo
  from leaving you with no WM. Same PID both times because execv preserves
  it. Combined cost is only ~0.38s; not the win it looks like.
- **The 1.0s wait ceiling is not being hit.** The veil reports ready at
  +0.434s, comfortably inside `40 × 0.025s`. An earlier guess that every
  restart burned the full ceiling was wrong — measured, not assumed.

### Where the remaining time actually is

Two thirds (2.92s) is qtile itself: interpreter + `libqtile` import
(1.72s), core init and window scan (1.20s). Neither is reachable from
config.

The addressable third is `_veil_launch()`'s **0.675s**, all of it spent in
the old process *before* anything visible happens. It serialises every
window's raw icon to a separate file on disk before spawning. That cost
scales with window count, so it is worst exactly when the veil matters
most. Next speed work belongs here, not in the veil's drawing code.

## Bugs found

### 1. dunst unpaused on a blind timer (fixed)
`_dunst(False)` fired 0.5s after `veil_done` while the veil's own fade-out
is 0.20s — a 0.3s margin, on a timer that had no knowledge of whether the
veil window still existed. dunst **queues** notifications while paused and
flushes the entire backlog the instant it unpauses, so anything that
arrived during the restart arrived all at once, and any overrun put all of
it on top of the veil.

Fixed by moving the unpause into the veil's own `finally` — the only
process that knows when its window stops existing. Verified: paused for
the veil's whole life, released in the same 0.5s sample the process exits.

### 2. dunst could stay paused forever (fixed, found while on #1)
The only `_dunst(False)` call site was inside `_veil_signal_done()`, which
only runs from the `startup_complete` hook. A restart that never reached
`startup_complete` — config error, crash, watchdog kill — left dunst
paused **permanently**, with no notifications and nothing on screen to say
why. The `finally` covers the watchdog and crash paths too; qtile keeps an
idempotent backstop at 1.5s.

## How to measure on the real machine

The handoff is right that sandbox totals should not be quoted at the user.
To get real numbers without iterating on the live session, the probe
harness is reusable: it appends `time.time()` + label to a file and
survives execv, so a **single** user-triggered `Super+Shift+R` produces the
full table above. Scripts in this session's scratchpad:
`sb-setup.sh` (build sandbox), `sb-instrument.py` (insert probes).

## The theme-change delay (user-reported, confirmed on the GIF)

Selecting a theme shows: palette swaps live → **~4s of fully visible,
un-veiled desktop** → veil appears → restart. Frames 16–23 of the
recording are the dead gap.

Cause is ordering, not slowness: `theme-apply` triggers the restart at
line ~901 of 1156. Everything before it — writing the kitty, alacritty,
GTK, qt5ct/qt6ct, rofi and dunst palettes — runs *before* the veil is
ever asked for. The user watches the whole thing happen naked.

Fix is to split the veil from the restart: a `_veil_hold()` that paints
the veil and returns, called by `theme-apply` **before** it starts writing
palettes, with the existing `_smooth_restart` reusing the already-painted
veil instead of spawning a second one. Not yet implemented.

## Not yet tested

Wallpaper change path was **not** exercised.
