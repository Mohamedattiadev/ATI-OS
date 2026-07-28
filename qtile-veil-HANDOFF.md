# Handoff: qtile restart veil — continue here

Paste this whole file as the opening prompt of the new session.

---

## What this is

`Super+Shift+R` used to show every window from every workspace piled on
top of each other for ~2s, then take ~12s total. A "veil" now covers that
and reports progress. It works. Four things are still open — see **TASKS**
at the bottom. Do those.

## Hard constraint (non-negotiable, learned the hard way)

**Never iterate by restarting the user's live qtile.** An earlier attempt
(fullscreen `feh` overlay) froze the desktop and crashed X. All work
happens in an isolated Xephyr sandbox. Only after it is proven there does
anything touch the real session, and even then: trigger once, screenshot,
stop. The user presses `Super+Shift+R` themselves — do not do it for them.

## Files

- `~/.config/qtile/config.py` — modified (symlinked into `~/.dotfiles`)
  - `_set_keyboard_nonblocking` (~line 165) — xmodmap monkey-patch
  - `_VEIL_*` consts (~line 811), `_veil_paths` / `_veil_stage` /
    `_veil_launch` / `_veil_signal_done` (~831–1025)
  - `_dunst` (932), `_modifiers_held` (943), `_reapply_xmodmap_when_idle` (990)
  - `_smooth_restart` (1027) — bound to `Super+Shift+R`
  - `_init_window_group_state` — startup_complete hook, emits stages
- `~/.config/qtile/scripts/qtile-restart-veil.py` — the veil (721 lines, new)
- `~/.config/qtile/config.py.bak-before-veil` — pre-veil backup (revert with `cp`)
- `~/.dotfiles/qtile-restart-animation-TODO.md` — older notes; **the
  root-cause section is still valid, the "next steps" are stale**

Nothing is committed. `git status` shows config.py modified + two untracked.

## How it works

1. `_smooth_restart` saves state, writes `veil_rects.json` (per-window
   geometry + `wm_class` + raw `_NET_WM_ICON` bytes), pauses dunst,
   launches the veil detached (`start_new_session=True` so it survives
   execv), waits for the veil to confirm it painted (`veil_ready`) **and**
   for modifiers to be released, then `qtile.restart()`.
2. Veil draws: frosted blur of the desktop + a card per window with its
   real icon, converging to a centred row; title, progress bar, stage text,
   spinner.
3. New qtile emits stages via `_veil_stage(frac, text)` →
   `~/.cache/qtile/veil_stage`. Veil polls it (real progress, not a timer).
4. `_veil_signal_done` writes `veil_done` 0.85s after startup_complete;
   veil animates out and exits. Watchdog `--max-seconds 20` regardless.

Safety: veil is override-redirect with an **empty input shape** (all input
passes through — it cannot block the user even if wedged), never grabs,
self-destructs, and `_smooth_restart` falls through to a plain
`qtile.restart()` on any exception.

## Sandbox recipe (this took a long time to get right — reuse it)

```bash
SB=~/tmp/qtile-sandbox; mkdir -p $SB/cache
# copy real config, stub autostart, redirect state caches
cp -rL ~/.config/qtile $SB/verify
#   in $SB/verify/config.py:
#     - insert `return  # SANDBOX` before the autostart.sh Popen
#     - replace the two os.path.expanduser("~/.cache/qtile/*.json")
#       with os.environ["QTILE_SB_CACHE"] + "/..."
Xephyr :1 -screen 1440x810 -ac -no-host-grab &      # NO -resizeable
TMPDIR=/tmp QTILE_SB_CACHE=$SB/cache PYTHONDONTWRITEBYTECODE=1 \
  DISPLAY=:1 qtile start -c $SB/verify/config.py -l INFO &
DISPLAY=:1 picom --config ~/.config/picom/picom.conf --backend xrender &
```

### Sandbox gotchas that will waste hours if you forget

- **picom `glx` does not render the veil under Xephyr** (no GPU → software
  GL). It binds a pixmap and silently never paints. `--backend xrender`
  works. This is a sandbox artifact — glx is fine on the user's real
  hardware (their recordings show the veil).
- **`simulate_keypress` does NOT reach the `mod4+shift+r` binding** (the
  modifier list arrives as a string). Trigger with:
  `qtile cmd-obj -o cmd -f eval -a '__import__("sys").modules["config"]._smooth_restart(self)'`
- **Stale `__pycache__/config.cpython-*.pyc` shadows an edited config.py.**
  `rm -rf __pycache__` + `PYTHONDONTWRITEBYTECODE=1`, or you will test old
  code and not realise it.
- **qtile truncates its stdout log across execv** — debug with an
  append-only file, not the redirect.
- `xdotool keydown super` in Xephyr **sticks**. It then reports modifiers
  held forever and burns the restart wait budget. Clear with
  `DISPLAY=:1 xdotool keyup Super_L Super_R Shift_L Shift_R Control_L Control_R Alt_L Alt_R`.
- `maim` has **no ppm support** (benchmarking it measures the error path).
  For frame capture use ffmpeg: `ffmpeg -f x11grab -framerate 30 -video_size WxH -i :1 -t N -c:v libx264 -preset ultrafast -qp 0 out.mp4`
  then extract frames. maim PNG is ~148ms/frame at 1440x810 — far too slow
  to see a 200ms animation.
- `pkill -f <pattern>` **matches your own shell** and kills the session.
  Use `ps -eo pid,args --no-headers | awk '/pat/ && !/awk/ {print $1}'`.
- `montage` silently splits into `name-0.png`, `name-1.png` when inputs
  exceed the tile count.
- qtile's restart state pickle lives at `$TMPDIR/qtile-state`. If it goes
  missing, `manager.py:171` `os.remove()` raises **uncaught** and qtile
  dies with no WM. User's TMPDIR is unset (`/tmp`); export `TMPDIR=/tmp`
  in the sandbox or you will hit it.

## Root cause, measured (do not re-derive)

Instrumented from outside qtile (survives execv), recording which windows
are mapped over time:

```
T+0.000  [g3a,g3b]                    normal desktop
T+2.783  [g1a,g2a,g2b,g2c,g3a,g3b]    <- qtile's boot scan maps EVERYTHING
T+5.439  [g2c,g3a,g3b]                qtile starts hiding foreign windows
T+5.632  [g3a,g3b]                    settled
```

The pile is **inside qtile's own boot**, between its window scan and the
`startup` hook — no config-level code is alive then. Proven unfixable from
config: moving the hold to `startup` doesn't help, `client_managed` never
fires for re-adopted windows, and unmapping foreign windows before execv
doesn't help (the incoming qtile re-maps them). Hence a separate process.

The old TODO's "layout hasn't been recomputed yet" theory is **wrong**.

## Already fixed (don't redo)

- Foreign-group window pile — masked by the veil
- Wallpaper decode blocking first paint ~2s — replaced with an in-process
  screen-grab blur (downscale→upscale), ~ms
- Icons: theme lookup by `wm_class` missed apps (qutebrowser showed "Q").
  Now reads `_NET_WM_ICON` off each window; qtile decodes it to
  premultiplied BGRA which is byte-identical to cairo ARGB32
- Theme: was reading `~/.cache/wal/colors.json`, which is only correct in
  `wal` mode. Now calls `colors.active_palette()` (reads
  `~/.cache/qtile/theme_mode`). Verified against dracula
- Stray diagonal line from text to spinner: `cr.save()/restore()` does
  **not** restore the path, so `move_to` from text left a current point and
  the next `arc()` connected to it. Fixed with explicit `cr.new_path()`
- dunst notifications landing on the veil — dunst paused during, plus
  qtile's own "Reloaded" toast removed
- **xmodmap stall (the big one):** `libqtile/widget/keyboardlayout.py:71`
  runs `xmodmap ~/.Xmodmap` via blocking `check_output`. `~/.Xmodmap` does
  `clear mod1` / `add mod1` (Caps→Alt; there is no `caps:alt` XKB option,
  so it must stay). xmodmap refuses to rewrite the modifier map while a
  modifier is held and retries 2→4→8→16→32s. The restart keybind is
  Super+Shift+**R**, so Super is always down. Measured 5 stalls ≈ 15s of
  dead startup. Now monkey-patched to fire-and-forget +
  `_reapply_xmodmap_when_idle()`. Stalls now 0.
- `_modifiers_held()` went through three versions: pointer modifier mask
  (wrong — reported idle while stalling), any-pressed-key (wrong — typing
  would delay restart), now **modifier keycodes only** via
  `GetModifierMapping` + `QueryKeymap`. Keep this version.

## Open measurement problem

With all the above fixed and 0 xmodmap stalls, the sandbox still shows
~11s between `qtile.restart()` and the `startup` hook. But:
- the config **module** executes in 0.13s
- **no widget** `_configure` exceeds 20ms
- restart → new process reaching config measured 4.46s in one run

So ~10s is unattributed and may be a sandbox artifact (nested X, software
xrender compositing, no GPU). The user's own recording was ~12s *total
including* the xmodmap stalls, so their real baseline is faster than the
sandbox's. **Do not claim a speed number for their machine without
measuring on their machine.** The cheapest way to find the real culprit:
ask them which stage text sits longest during a real restart.

---

# TASKS

## STATUS 2026-07-28 — tasks 2, 3, 4 done; 1 still open

Verified in the Xephyr sandbox with a real `_smooth_restart` trigger.
The user's live session was never restarted.

- **2 (restyle) — done.** Root cause of "too AI looking" was that every
  surface was mixed from white/black, so a gruvbox desktop still produced
  a grey veil. Now: `accent`=colors[7] and `accent2`=colors[8] (what the
  bar itself uses), all neutrals derived from the palette, Ubuntu Mono
  throughout, tracked-out caps title, 1px hairline cards with no drop
  shadow or gloss gradient, flat square progress bar, blinking block
  cursor instead of the spinner ring. `surface` is derived from colors[0]
  rather than colors[2] — gruvbox sets colors[2] to pure #000000, which
  punched black holes where the cards were.
- **3 (theme-apply) — done.** `qtile.smooth_restart` attached in
  `_attach_live_swap`; theme-apply now probes for it and calls it.
  **The probe is load-bearing:** smooth_restart ends in execv, so the IPC
  connection always dies mid-call and a naive "call it, fall back on
  error" would fire a second restart every single time.
- **4 (rotating tips) — done.** `_veil_tips()` samples `qtile.config.keys`
  at launch, writes `veil_tips.json`, veil crossfades one every 2.6s.
  Digit keys are filtered out — the ~18 per-group bindings otherwise
  swamp a sample of five.
### Second pass (same day), after user review of the restyle

- Backdrop was a 0.38 tint **plus** a 0.55 vignette — together they buried
  the blur and the veil read as a black screen. Now one 0.25 scrim, no
  vignette. Verified by running the wallpaper through both scaling
  pipelines offline (`blur_old.png` / `blur_new.png`).
- **Beware the sandbox here:** Xephyr's root is black and `feh` does not
  stick without a WM, so the veil *always* looks black-backed in the
  sandbox no matter what the scrim is. Don't "fix" that again — test the
  blur offline against a real image instead.
- Text sizes were set for a screenshot, not a screen: title 13.5→21,
  status 11.5→15.5, tips 11.5→14.5, bar 2→3px. Subtitle line removed.
- **Left/right swap bug (user-reported) fixed.** Slots are handed out in
  list order, but the list arrives in qtile's `group.windows` order —
  focus/stack order, not screen order. A right-hand window could get the
  left slot and the cards crossed over. `self.rects` is now sorted by
  `(x, y)` before slots are assigned.
- Motion added so the hold is not static: staggered card bob, and a
  sweep travelling inside the *completed* part of the bar (it never fakes
  progress).
- Empty group now draws three pulsing placeholder squares instead of
  leaving the middle blank under a floating progress bar.
- Dead time at the end of the restart cut ~0.9s: `_VEIL_SIGNAL_DELAY`
  0.85→0.40, `_RESTORE_PASS_1` 0.30→0.14, `_RESTORE_PASS_2` 0.70→0.34.

- **1 (speed) — still open, and still the top complaint.** See below.
  Note the previous session already established the remaining hold is
  qtile loading this config (4,533 lines, 32 bar widgets); the next step
  is profiling that, not more veil work.

## 1. Speed
Still the top complaint. Everything cheap is done. Next honest step is to
find where the ~10s actually goes — ideally by having the user report
which stage label sits longest, then attacking that phase. Consider adding
finer-grained `_veil_stage()` calls inside qtile's startup path to bisect
it. Do not guess.

## 2. "Too AI looking" — restyle to match their qtile
Current look: centred title "Reloading qtile", subtitle "N windows ·
workspace X", row of rounded cards with icons, gradient progress bar,
spinner. The user finds it generic. Make it feel native to *their* setup.
Their bar fonts: `Ubuntu Mono` and `JetBrainsMono Nerd Font` (TaskList).
`mod = mod4` (Super), `mod2 = mod1` (Alt, via Caps). Palette comes from
`colors.active_palette()` — indices: 0=bg 1=fg 2=bg-alt 3=red 4=green
5=orange 6=blue 7=magenta 8=cyan. Ask them for a reference/screenshot of
the aesthetic they want rather than guessing again.

## 3. theme-apply doesn't use the veil
`~/.config/AtiScriptsV1/theme-apply` line ~869:
```bash
setsid -f bash -c 'qtile cmd-obj -o cmd -f restart' >/dev/null 2>&1 </dev/null || true
```
This calls qtile's **raw** `restart`, bypassing `_smooth_restart`, so
changing theme reloads with no veil. Fix by following the pattern the
config already uses for `apply_palette_live` (see `_attach_live_swap`,
`@hook.subscribe.startup_complete`): attach
`qtile.smooth_restart = lambda: _smooth_restart(qtile)` and have
theme-apply call
`qtile cmd-obj -o cmd -f eval -a 'str(self.smooth_restart())'`.
**This edits a file outside ~/.config/qtile — confirm with the user first.**

## 4. Rotating keybind tips (was mid-implementation, nothing written yet)
User wants 3–4 proper sentences cycling in the middle while it loads, e.g.
"Super + F — toggle fullscreen", so the wait isn't boring.

Use **their real bindings**, not invented ones. `qtile.config.keys` entries
have `.modifiers`, `.key`, `.desc`. 78 have descriptions. Plan:
- in `_veil_launch`, sample ~4 keys that have a `desc`, format
  `mod4`→`Super`, `mod1`→`Alt`, `shift`→`Shift`, `control`→`Ctrl`,
  write them into the rects/tips JSON
- veil rotates one every ~2.5s with a crossfade

Real examples from their config (verified):
```
Super + F              toggle fullscreen
Super + T              toggle floating
Super + Tab            Toggle between layouts
Super + Shift + C      Kill focused window
Super + Shift + Return Run Launcher
Super + Space          Move window focus to other window
Alt + N                CopyQ clipboard rofi picker
Super + Shift + Z      Toggle Top ↔ Bottom bar
```

Filter out anything unhelpful mid-restart (e.g. the restart bind itself).
