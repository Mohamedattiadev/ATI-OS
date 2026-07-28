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

### What this corrects in the handoff

- **The "~11s unattributed" is gone.** Total is now ~4.5s in the same
  sandbox. That figure predated the xmodmap fix; do not keep chasing it.
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

## Not yet tested

Theme change and wallpaper change paths were **not** exercised. Only the
reload/restart path was measured and fixed.
