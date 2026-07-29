# Qtile config — TODO fixes

**Date reported:** 2026-07-29
**Audited:** `~/.config/qtile/config.py` (5,197 lines), `scripts/` (imported + spawned), `popups/`, `autostart.sh`
**Environment:** qtile 0.36.0, Python 3.14, X11 backend

**How this was verified:** standalone import of `config.py`; `ruff check --select F,E9` over the tree; duplicate-keybinding scan across `keys` and every `KeyChord.submappings`; live `qtile cmd-obj -o bar top -f info`; sweep of `~/.local/share/qtile/qtile.log` covering 47 recorded starts.

> **This folder is temporary.** `Fixes/` exists only to track this round of work. Once every item below is fixed and verified, delete the whole `Fixes/` directory — it is scratch, not documentation. Anything worth keeping should be moved into a code comment at the site of the fix, or into `QTILE_FREEZE_REPORT.md` / `TODO_popups.md`, before the folder goes.

Legend — **[P1]** breaks behaviour today · **[P2]** silently wrong · **[P3]** performance · **[P4]** cleanup

---

## [P1-1] Top bar draw loop crashes on ~1 start in 8

**Where:** `config.py:1598` (`_install_tooltip`), `config.py:3659` (`chip`)
**Evidence:** 6 tracebacks in `qtile.log`, always 0.6–1.6 s after startup.

```
File "libqtile/bar.py", line 440, in _resize
    fixed_total = sum(w.length for w in widgets if w.length_type != STRETCH)
File "libqtile/configurable.py", line 28, in __getattr__
    raise AttributeError(f"{cname} has no attribute: {name}")
AttributeError: FlashTextBoxWithTooltip has no attribute: length. Did you mean: '_length'?
```

**Why it happens:** `_Widget.length` is a property that calls `calculate_length()`. `TextBox.calculate_length()` reads `self.layout`, which only exists after `_configure()`. When an *unconfigured* widget is in `bar.widgets`, that inner `AttributeError` propagates out of the property, Python then falls through to `Configurable.__getattr__("length")`, and the whole bar draw dies.

The class name proves the path: `Flash…` is only applied by `chip()`, and `…WithTooltip` only by `_install_tooltip`'s runtime `__class__` swap. So the offending widget is a chip'd `TextBox` — almost certainly `main_icon_chip`.

**Suspected feeder:** see **[P4-2]** — `SmartWidgetBox._instances` holds orphan, never-configured boxes, and `SmartWidgetBox.toggle_widgets()` inserts `self.widgets` straight into `self.bar.widgets`.

**Fix plan:**
1. Guard `_install_tooltip` — skip any widget where `getattr(widget_, "configured", False)` is falsy, or that has no `.bar`.
2. Harden `SmartWidgetBox.toggle_widgets()` and `close_all()` to bail early when `self.bar` is unset.
3. Consider overriding `length` on `_ChipFlashMixin` to return `0` instead of raising when the widget is unconfigured — a defensive net so one bad widget can never take out the whole bar.
4. Reproduce first: restart qtile in a loop and watch the log, since it is only ~12 % of starts.

---

## [P1-2] `_QTILE` is undefined in WallpaperPopup

**Where:** `popups/WallpaperPopup.py:311-312`
**Reached by:** the `/` key inside the `WallpaperPicker` chord (`config.py:4012-4016`)

```python
if _QTILE is not None:
    _QTILE.call_soon_threadsafe(_apply)
```

`_QTILE` is never defined, imported, or assigned anywhere in the file — confirmed by `ruff` (`F821`) and by grep. `fuzzy_search_rofi` runs `_run_rofi` in a daemon thread, so the `NameError` is swallowed: rofi opens, you pick a wallpaper, and nothing happens.

**Fix:** capture the qtile object when the popup opens. `show_wallpaper_picker(qtile)` already receives it — store it in a module global (`global _QTILE; _QTILE = qtile`) and initialise `_QTILE = None` at module level next to the other globals (`_INDEX`, `_IMAGES`, …).

---

## [P1-3] Mod+Shift+T spawns a new Telegram every time

**Where:** `scripts/toggle_apps.py:21`, matcher at `toggle_apps.py:39-45`

```python
telegram_name_prefix = "Telegram"

def _find_window_by_class(qtile, cls):
    ...
    if wm_class and cls in wm_class:   # exact list membership, not substring
```

Telegram's real WM_CLASS is `("telegram-desktop", "TelegramDesktop")`, so `"Telegram" in [...]` is always `False`. The toggle never finds the running window, falls through to the spawn branch, and launches another instance.

Your own `Group("9")` already uses the correct string: `Match(wm_class="TelegramDesktop")` (`config.py:4547`).

**Fix:** set `telegram_name_prefix = "TelegramDesktop"`, **or** make `_find_window_by_class` case-insensitive substring like `toggle_terminal` already does:
```python
if wm_class and any(cls.lower() in c.lower() for c in wm_class):
```
The second is the better fix — it also hardens `toggle_brave`, `toggle_anki`, `toggle_obsidian`, `toggle_qutebrowser` and `toggle_file_manager` against the same class of mismatch.

Note the same 1-line-off pattern exists in the `client_killed` hooks (`toggle_apps.py:342-348`, `378-384`), which use bare `in wm_class` too.

---

## [P1-4] Mod+h / Mod+l error out in Max and TreeTab

**Where:** `config.py:3889-3890`
**Evidence:** `ERROR libqtile manager.py:process_key_event():L554 KB command error left: No such command` — twice in the log.

```python
Key([mod], "h", lazy.layout.left(),  desc="Move focus to left"),
Key([mod], "l", lazy.layout.right(), desc="Move focus to right"),
```

`left()` / `right()` exist on MonadTall, Columns and BSP — not on `Max` or `TreeTab`. Groups **2** (browsers) and **5** (brave) both default to `layout="max"`, so this fires during ordinary use.

**Fix:** add a fallback in the same Key, the way the shuffle binds at `config.py:3897-3917` already do:
```python
Key([mod], "h",
    lazy.layout.left().when(layout=["monadtall", "columns", "bsp"]),
    lazy.layout.previous().when(layout=["max", "treetab"]),
    desc="Move focus to left"),
```
(Mirror with `next()` for `l`.) Verify `previous`/`next` exist on both layouts before committing.

---

## [P1-5] `w_mpris` scrolling is silently disabled

**Where:** `config.py:2802-2803`
**Evidence:** `WARNING libqtile base.py:_configure():L554 w_mpris: You must specify a width when enabling scrolling` — on all 53 recorded starts.

```python
scroll=True,
scroll_chars=28,
# no width= → qtile refuses to enable scrolling
```

**Fix:** add an explicit `width=` (e.g. `width=220`) to the `Mpris2` chip. Note `scroll_chars` alone is not enough; qtile needs a fixed pixel width to know what to scroll within.

---

## [P2-1] `and` swallows the close call in the wallpaper chord

**Where:** `config.py:4022-4027`

```python
Key([], "q",
    lazy.function(lambda _: WallpaperPopup.close_wallpaper_picker())
    and lazy.ungrab_chord()),
```

`lazy.function(...)` is a truthy object, so `A and B` evaluates to **B only**. The `Key` receives a single command — `ungrab_chord()` — and the close call is thrown away at config-load time.

It currently *appears* to work because `ungrab_chord()` fires `leave_chord`, and `cleanup_on_leave` (`config.py:2082-2086`) closes the picker. So this is latent, not visible — but it will bite the moment that hook changes.

**Fix:** pass both as separate positional commands, which is what `Key(*commands)` is for:
```python
Key([], "q",
    lazy.function(lambda _: WallpaperPopup.close_wallpaper_picker()),
    lazy.ungrab_chord()),
```

---

## [P2-2] Two chips never get a tooltip

**Where:** `config.py:2687` (CurrentLayout chip), `config.py:2890` (CheckUpdates chip); lookup at `config.py:1753-1755`
**Evidence:** live `qtile cmd-obj -o bar top -f info` reports the widget's name as **`flashcurrentlayout`**. Log line: `[tooltips] installed=19 total=33`.

`chip()` wraps the class in `_flash_widget_class()` when `mouse_callbacks` is present, producing `FlashCurrentLayout`. qtile derives a widget's `name` from its lowercased class name when no explicit `name=` is given. So:

- `TOOLTIP_BY_NAME.get("flashcurrentlayout")` → `None`
- `TOOLTIP_BY_CLASS.get("FlashCurrentLayout")` → `None` (dict is keyed `"CurrentLayout"`)

Both entries in `TOOLTIP_BY_CLASS` are therefore dead for any chip that has click handlers.

**Fix (pick one):**
- **Preferred:** pass explicit `name="w_layout"` / `name="w_updates"` to those two `chip()` calls and add matching entries to `TOOLTIP_BY_NAME`. This also makes `lazy.widget["…"]` addressable.
- Alternative: strip the `Flash`/`WithTooltip` affixes before the `TOOLTIP_BY_CLASS` lookup — fragile, and it does not fix the widget's `name`.

---

## [P2-3] The wallpaper chord's `R` is actually plain `r`

**Where:** `config.py:4007-4011`

```python
Key([], "R", lazy.function(lambda _: WallpaperPopup.jump_to_random())),
```

qtile's keysym table is lowercase-normalised (verified: `"Tab" in xcbq.keysyms` → `False`, `"tab"` → `True`), and lookups are lowercased. So this binds `r`, not `Shift+R`. The chord chip label at `config.py:2762` advertises `R`, which is misleading.

**Fix:** either use `Key(["shift"], "r", …)` if Shift was intended, or change the chip label to `r`. No conflict either way — nothing else in that chord binds `r`.

---

## [P3-1] Tooltip hovers block the entire WM

**Where:** `config.py:1803-1814` (`_make_tooltip_dynamic`), consumers at `config.py:1760-1771`

`mouse_enter` is dispatched **directly on qtile's asyncio event loop**. Every dynamic tooltip does a blocking `subprocess.run` inside it, so the whole WM — keyboard, focus, bar, everything — stalls for the duration:

| Tooltip | Function | Worst case |
|---|---|---|
| `w_clock` | `_prayer_text` → `prayer_next.sh` | **6–8 s, once per day** |
| `w_disk` | `_disk_parts_text` → `_sh(timeout=1.5)` | 1.5 s |
| `w_cpu` | `_cpu_top_text` → `_sh(timeout=1.5)` | 1.5 s |
| `w_mem` | `_mem_top_text` → `_sh(timeout=1.5)` | 1.5 s |
| `w_mpris` | `_player_title_text` → 2× `playerctl` @ 0.5 s | 1.0 s |

The clock one is the worst and the least obvious. Measured: `prayer_next.sh` returns in **44 ms** when `~/.cache/qtile_prayer.json` is same-day. But the first hover after midnight takes the refresh branch, which runs `curl -fsSL --max-time 6` (`prayer_next.sh:23`), and `_prayer_text` wraps it in `subprocess.run(..., timeout=8)` (`config.py:3405-3412`). That is a hard 6–8 s freeze of the window manager, once a day, triggered by hovering the clock.

Note the `GenPollText` widgets are **fine** — `ThreadPoolText` already runs those off-loop. This is specifically the hover path.

**Fix plan:**
1. Make `_make_tooltip_dynamic` show a cached value immediately, then refresh in a `threading.Thread` and push the result back via `qtile.call_soon_threadsafe`.
2. Separately, decouple the prayer refresh from the render: have `prayer_next.sh` never do network I/O on the read path — print the cache (or nothing) and let a background timer/systemd unit do the daily `curl`.
3. Cross-check `QTILE_FREEZE_REPORT.md` — this is very likely one of the freezes already logged there.

---

## [P4-1] Three unused widget trees built on every config load

**Where:** `config.py:5062-5066`

```python
if __name__ in ["config", "__main__"]:
    screens = init_screens()
    widgets_list = init_widgets_list()        # never used
    widgets_screen1 = init_widgets_screen1()  # never used
    widgets_screen2 = init_widgets_screen2()  # never used
```

Only `screens` is read by qtile. The other three are leftovers from the DTOS template. Each call constructs a full widget tree — including a `Systray` and four `SmartWidgetBox` instances — that is never attached to a bar and never configured.

**Fix:** delete the three unused assignments. Grep first to confirm nothing else references those names.

---

## [P4-2] `SmartWidgetBox._instances` is never pruned

**Where:** `config.py:3436` (class attr), `3441` (append), `3443-3450` (`close_all`), `2177-2192` (`_all_smart_widgetboxes`)

```python
class SmartWidgetBox(ewidget.WidgetBox):
    _instances = []          # class-level, grows forever
    def __init__(self, *a, **k):
        ...
        SmartWidgetBox._instances.append(self)
```

Consequences:
- The orphan boxes from **[P4-1]** are registered permanently.
- Every `reload_config` appends a whole new generation while the previous one stays, with `.bar` pointing at a dead `Bar` object.
- `close_widgetboxes_on_chord` / `restore_widgetboxes_on_chord_leave` / `close_all()` iterate the list and call `toggle()` on boxes that have no usable bar. The exceptions are swallowed by `try/except`, so it is invisible — but `toggle_widgets()` inserts `self.widgets` directly into `self.bar.widgets`, which is a credible route for **[P1-1]**.

**Fix:** register only configured instances (append from `_configure`, not `__init__`), or clear the list at the top of each config load, or hold weak references. Also add an explicit `if not getattr(self, "bar", None): return` guard in `toggle_widgets()` and `close_all()`.

---

## [P4-3] A new class object per widget, per tooltip install

**Where:** `config.py:1603`

```python
new_cls = type(cls.__name__ + "WithTooltip", (cls, TooltipMixin), {})
```

`_flash_widget_class` caches its generated classes (`config.py:3648-3656`); `_install_tooltip` does not. `install_bar_tooltips` runs at least twice per startup (`startup_complete + 0.3 s` and `startup + 2.0 s`) and again 0.1 s after **every** `SmartWidgetBox.toggle()` (`config.py:3458`).

**Fix:** add a module-level cache keyed on the base class, mirroring `_flash_widget_cache`.

---

## [P4-4] Cosmetic / dead code

| Item | Where | Note |
|---|---|---|
| LaunchBar icon warnings | `config.py:2456-2467` | Nerd Font glyphs sit in the *icon* field; qtile logs `No icon found for application` ×5 on every start, then falls back to text — which is the desired look. Silence it by passing a real icon name or an empty icon and relying on `text`. |
| Dead `COLORSCHEME` | `autostart.sh:9` | `COLORSCHEME=DoomOne` is never read. Delete. |
| Dead `toggle_google_chrome` | `toggle_apps.py:194-223` | Fully implemented, never imported by `config.py`. Wire it up or drop it. |
| Wrong comment | `autostart.sh:82-87` | Claims autostart "runs again on every qtile restart". It is on `@hook.subscribe.startup_once`, which does **not** fire after a restart (qtile restores `self._state`). The `pgrep` guards are harmless, but the stated rationale is wrong. |
| ruff nits | `scripts/qdrop.py:1704`, `scripts/wal-visual-test.py:10,111` | Unused local `vp`; unused `math` import; f-string with no placeholders. |

---

## Checked and found clean

- `config.py` imports standalone without error; syntax valid.
- **No duplicate top-level keybindings.** The 61 `Key spec duplicated: <Key ([], Escape)>` warnings are qtile's own auto-appended Escape colliding with the explicit ones — a behaviour the config already documents and deliberately works around at `config.py:4441-4451`. Not a bug.
- `scripts/stt_script.sh` does not exist, but its only reference (`config.py:3744`) is commented out.
- `ERROR ... couldn't find \`f=$(mktemp\`` appears twice, both at 17:34 on 2026-07-28 — before `scripts/screenshot-area.sh` was created at 17:33. Stale, already fixed by the current `SCREENSHOT_AREA_CMD`.
- Integer keycodes in the `Lang-Switch` chord (`config.py:4266-4269`) are valid — `Key.__init__` is typed `key: str | int`.
- `volume_control.py`, `brightness_control.py`, `sum_app.py`, `screenshot-area.sh` — no issues found. All subprocess calls are timeout-bounded.

---

## Suggested order of work

1. **[P1-2]**, **[P1-3]**, **[P1-5]**, **[P2-1]**, **[P2-2]** — small, contained, individually verifiable.
2. **[P1-4]** — needs a quick check of which commands `Max` / `TreeTab` actually expose.
3. **[P3-1]** — highest real-world payoff; the once-a-day 8 s freeze is the worst symptom in this list.
4. **[P4-1]** + **[P4-2]** — do together; they are likely the feeder for **[P1-1]**.
5. **[P1-1]** — attempt reproduction *after* 4, since fixing the orphan instances may resolve it outright.
6. **Delete `Fixes/`.** Once every item above is fixed and verified, remove this directory:
   ```sh
   git rm -r ~/.config/qtile/Fixes
   ```
   Migrate anything still worth keeping first — a short comment at the fix site beats a stale checklist, and the freeze work from **[P3-1]** belongs in `QTILE_FREEZE_REPORT.md`.
