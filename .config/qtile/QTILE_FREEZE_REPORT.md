# Qtile Freeze Audit + Fix Report

Full static audit of `config.py`, `popups/`, `scripts/` for main-loop blockers
that cause qtile to freeze on chord entry, keybind press, or popup use.

No live repro data was available at audit time; audit is static (grep + read).
Every fix preserves behavior, only changes execution model.

Out of scope (stable, do not touch): `AtiScriptsV1/`, `browser-theme*`,
`colors.py` mapping, `render_*` in wal-precompile.

---

## Root causes (severity ranked)

### 1. CRITICAL — startup blocks entire WM at login
- **File:** `.config/qtile/config.py:562`
- **Symptom:** `subprocess.call([...autostart.sh])` in `@hook.subscribe.startup_once`
  blocks the qtile main loop until `autostart.sh` returns. If any command in
  autostart hangs, qtile is dead at login (no bar, no keys, no chord).
- **Fix:** Replace with `subprocess.Popen(..., start_new_session=True)` —
  fire-and-forget fork. Autostart commands still run; main loop continues.

### 2. CRITICAL — Draw-Mode chord enter blocks main loop
- **File:** `.config/qtile/config.py:696` (`ensure_gromit_and_toggle`)
- **Symptom:** `enter_chord` hook for `Draw-Mode` called
  `subprocess.run(["pgrep","-x","gromit-mpx"], check=True)` synchronously.
  Chord activation stalls until pgrep returns; if system load spikes, chord
  appears frozen for 1–5s or longer.
- **Fix:** Replace with single async `qtile.spawn("sh -c '...'")` that does
  the pgrep + branch + toggle entirely inside a forked shell. Main loop
  returns instantly.

### 3. HIGH — volume keybinds block on pactl
- **File:** `.config/qtile/scripts/volume_control.py` (all subprocess.run)
- **Symptom:** Media-Mode chord calls `volume_change()` / `toggle_mute()`
  via `lazy.function`. Each calls `subprocess.run(["pactl", ...])` and
  `subprocess.run(["notify-send", ...])` **without timeout**. If PulseAudio
  stalls (frequent on suspend/resume), volume keys freeze WM.
- **Fix:** Added `_run()` helper with `timeout=2` on pactl and `timeout=1`
  on notify-send. Timeouts fail silently rather than hang.

### 4. MEDIUM — icon reset spawns thread per keypress
- **File:** `.config/qtile/config.py:641-645` (`set_icon_temporarily`)
- **Symptom:** Every terminal / launcher keypress spawned a fresh
  `threading.Thread(target=reset)` with `time.sleep(0.3)`. Not a freeze,
  but accumulates threads on rapid key mashing and racy widget updates.
- **Fix:** `qtile.call_later(0.3, ...)` — event loop scheduling, no thread.

### 5. MEDIUM — Bluetooth connect worker: no timeout + thread-unsafe UI
- **File:** `.config/qtile/popups/BluetoothPopup.py:226`
- **Symptoms:**
  - `subprocess.run(["bluetoothctl","connect", mac])` no timeout — if
    bluetoothd hangs, worker thread stuck forever.
  - `update_ui()` called directly from worker thread — qtile widget
    updates from non-main threads race → occasional draw glitches or
    crashes.
  - `get_devices()` and `disconnect` path also lacked timeouts.
- **Fixes:**
  - Added `timeout=15` on connect, `timeout=10` on disconnect,
    `timeout=5` on `bluetoothctl devices`, `timeout=3` on
    `bluetoothctl info`.
  - Wrapped `update_ui` / `refresh` calls from worker thread with
    `_QTILE.call_soon_threadsafe(...)`.

### 6. MEDIUM — WiFi connect worker: no timeout + wrong scheduler
- **File:** `.config/qtile/popups/WifiPopup.py:246`
- **Symptoms:**
  - `subprocess.run(["nmcli","dev","wifi","connect", ssid])` no timeout.
    nmcli commonly hangs 30–60s on bad credentials or unreachable AP.
  - Worker thread called `update()` directly — not thread-safe.
  - `refresh_worker` used `_QTILE.call_soon` — that variant is NOT
    thread-safe; must be `call_soon_threadsafe` when called from a
    non-main thread.
  - `get_networks()` (nmcli scan) had no timeout.
- **Fixes:**
  - `timeout=30` on connect, `timeout=10` on scan.
  - Replaced all `_QTILE.call_soon(...)` in threaded paths with
    `_QTILE.call_soon_threadsafe(...)`.

### 7. MEDIUM — Wallpaper fuzzy-search rofi blocks main loop
- **File:** `.config/qtile/popups/WallpaperPopup.py:264`
- **Symptom:** `subprocess.run(rofi, input=..., stdout=PIPE)` blocks the
  qtile main loop for the entire time the user is browsing rofi (can be
  many seconds). During this window, all other qtile input is dead.
- **Fix:** Moved rofi call into a daemon thread with `timeout=120`.
  Selection is applied back on the main loop via
  `_QTILE.call_soon_threadsafe`.

### 8. HIGH — AudioPopup pactl freezes on every refresh
- **File:** `.config/qtile/popups/AudioPopup.py` (`get_audio`, `select`)
- **Symptom:** `refresh()` reschedules itself every 5s via
  `qtile.call_later` and runs 4 blocking `pactl` `subprocess.run` calls
  each cycle. Any PulseAudio stall (post-suspend, sink switch,
  bluetooth handshake) would freeze qtile for the duration of the
  stall.
- **Fix:** timeouts on `pactl list sinks/sources` (3s),
  `get-default-sink/source` (2s), and `set-default-sink/source` (2s).
  Failures log-and-noop; refresh loop stays alive.

### 9. HIGH — UpdatesPopup pacman freezes WM on open + every keypress
- **File:** `.config/qtile/popups/UpdatesPopup.py`
- **Symptoms:**
  - `load_updates()` ran `pacman -Qu` synchronously on the main loop
    when the popup opened. pacman commonly blocks on db lock during
    background sync — WM froze for the full lock duration.
  - `render_info()` ran `pacman -Si` on every navigation keypress with
    no timeout. Slow disk / stale mirrors → per-keypress freeze.
  - `rofi_search` blocked main loop while user browsed rofi (same
    pattern as WallpaperPopup fuzzy search).
- **Fixes:**
  - `pacman -Qu`: `timeout=15` + moved to daemon thread on popup show;
    UI applies via `call_soon_threadsafe` when ready.
  - `pacman -Si`: `timeout=5`.
  - `rofi_search`: moved into daemon thread with `timeout=120`;
    selection applied via `call_soon_threadsafe`.

---

## Not fixed (assessed safe)

- All `lazy.spawn(...)` keybinds — non-blocking by design (async fork).
- `WallpaperPopup.apply_wallpaper._bg`: already threaded + `timeout=10`
  on xwallpaper; `theme-apply` via `Popen` fire-and-forget.
- `WifiPopup.refresh_worker` structure (thread + call_soon_threadsafe
  after fix) is the correct pattern.
- qtile-extras widgets (`CPU`, `Memory`, `Battery`, `Volume`, `Clock`,
  `Systray`, `GroupBox`, `TaskList`, etc.) — internal async polling.
- `CheatSheet-Mode` / `Mouse-Mode` / `Lang-Switch` chord hooks: only
  cheap operations (popup show, `qtile.spawn`).
- Nested KeyChord (WallpaperPicker inside Rofi-Mode): escape handling
  intact.

---

## Regression tests

Reproduce these after reload (`Mod4+Ctrl+r` or restart qtile) to
verify no regression.

### Theming (must still work — not touched by these edits)
1. `theme-apply wal` — bar retints from wallpaper palette. ✅ expected.
2. Change wallpaper via WallpaperPicker — brave / chrome / qutebrowser
   retint. ✅ expected.

### Freeze fixes
| # | Action | Expected |
|---|--------|----------|
| 1 | Log in (autostart runs) | Bar appears immediately, keys responsive. If any autostart cmd hangs, qtile still usable. |
| 2 | `Mod4+Shift+w` (Draw-Mode) with gromit-mpx **not** running | Chord enters instantly, notify-send fires, gromit toggles ~0.3s later. |
| 3 | Same, with gromit-mpx already running | Chord enters instantly, draw toggles immediately. |
| 4 | Media-Mode (`Mod4+/`) volume up/down while pulseaudio is briefly stalled (e.g. right after `systemctl --user restart pipewire`) | Keys don't freeze WM; volume update may silently fail during stall but WM stays responsive. |
| 5 | Open launcher (`Mod4+d`), mash it 10× fast | Icon flips + resets cleanly, no thread leak (`ps -eLf | grep qtile | wc -l` stable). |
| 6 | Bluetooth popup: connect to a device that will fail (out of range) | Popup shows progress, then "Timeout connecting to …" ≤15s. WM never freezes. |
| 7 | Wifi popup: connect to an unreachable SSID | Popup shows progress, then "Timeout connecting to …" ≤30s. WM never freezes. |
| 8 | Wallpaper picker → fuzzy-search rofi. Open rofi, wait 5s, dismiss. | WM stays responsive while rofi is open (mouse / other keys work). Selection applies after dismissal. |
| 9 | Open Audio popup, unplug + replug a bluetooth sink mid-refresh | Refresh survives; status may briefly show error but popup + WM stay responsive. |
| 10 | Open Updates popup while `sudo pacman -Sy` is running in another term (db locked) | Popup opens instantly with empty list; updates populate once pacman -Qu returns (up to 15s). WM never freezes. |
| 11 | Updates popup → `/` (rofi search). Open rofi, wait, dismiss. | WM responsive during rofi browse. Selection navigates to package on dismiss. |

### Chord release
After each chord, press `Escape` — chord must exit and normal keys
resume. If any chord ever "sticks", the fix for that chord did not land
correctly.

---

## Files changed

```
.config/qtile/config.py
.config/qtile/popups/AudioPopup.py
.config/qtile/popups/BluetoothPopup.py
.config/qtile/popups/UpdatesPopup.py
.config/qtile/popups/WallpaperPopup.py
.config/qtile/popups/WifiPopup.py
.config/qtile/scripts/volume_control.py
```

All Python bytecode-compiles clean.
