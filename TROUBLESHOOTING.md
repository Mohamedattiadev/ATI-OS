# Troubleshooting

Living log of real issues hit on this setup and their fixes. Grouped by
subsystem. Each entry: **symptom → root cause → fix**.

---

## Theming

### Chrome/chromium frame stays black on wallpaper switch
- **Symptom:** brave frame retints, chrome does not.
- **Root cause:** Chrome ignores `--load-extension` for themes since v134
  unless the extension is installed through a real install path. Two
  extensions coexist (unpacked with path-hashed id + policy-installed
  with key-hashed id) and neither activates.
- **Fix (permanent, one-time):** enterprise policy force-install from a
  local `updates.xml`. `install.sh` step 23b does this: generates
  `.pem`, extracts public key into `browser-theme.key` (wal-precompile
  embeds it as `key` field in `manifest.json` so unpacked + packed ids
  match), packs `.crx`, writes updates.xml, sudo-installs
  `/etc/opt/chrome/policies/managed/wal-theme.json` +
  `/etc/chromium/policies/managed/wal-theme.json`.
- **Fix (each apply):** `theme-apply` kills chrome first, repacks
  `.crx`, purges `Preferences` stale extension entry + `Extensions/<id>/`
  cache dir, then relaunches. Chrome sees fresh policy on startup.

### Rofi menu accents wrong hue after wallpaper switch
- **Symptom:** yellow wallpaper but rofi selection shows blue/purple.
- **Root cause:** `render_rofi_rasi` mapped `selected` to `accents[3]`
  (cool-fill) or `accents[4]` (complement) — both stay non-dominant.
- **Fix:** map `selected` to `accents[1]` (dominant slot). Semantic
  slot layout: `[0]` urgent (warm), `[1]` dominant, `[2]` warm-fill,
  `[3]` cool-fill, `[4]` complement, `[5]` info/cyan.

### qtile bar shows pink accents on green wallpaper
- **Symptom:** bar widgets highlight in non-matching hue.
- **Root cause:** `colors.py._wal_palette()` mapped `colors[7]` (most
  widget refs) to complement (`color13`) instead of dominant.
- **Fix:** remap so `colors[7]` = `color10` (dominant), `colors[3]` =
  `color9` (urgent), `colors[8]` = `color14` (info).

### qutebrowser homepage clock/welcome stay cyan/blue
- **Symptom:** wallpaper hue everywhere except qb homepage.
- **Root cause:** `homepage.css` hardcoded `var(--blue)` /
  `var(--cyan)` / `var(--purple)` — those slots are non-dominant.
- **Fix:** add `--accent` (= dominant) + `--urgent` (= red) CSS vars
  via `theme-apply`, switch homepage.css elements to `var(--accent)`.

### qutebrowser theme does not refresh on wallpaper switch
- **Symptom:** wal cache updated but qb keeps old colors.
- **Root cause:** `:config-source` alone does not re-read wal cache.
- **Fix:** `theme-apply` runs `:config-source` then `:restart`
  (session persists open tabs).

### qutebrowser tabs/statusbar/completion never follow wal, only the homepage does
- **Symptom:** switching wallpapers correctly retints the qb homepage
  (via `theme-apply`'s `gen_qb_css`), but the browser's own UI — tabs,
  statusbar, completion popup, hints — stays on static doom-one colors
  no matter what.
- **Root cause:** `qutebrowser/config.py` actually had **two** separate
  wal-integration attempts. The first, `_apply_wal()` (~20
  `c.colors.*` properties, the more complete one), was called at the
  top of the file — *before* `doom_one.setup(c, ...)` ran. `doom_one`
  sets ~90 `c.colors.*` properties of its own and ran second, so it
  silently clobbered every wal override `_apply_wal()` had just set.
  A second, smaller wal block further down (only hints + a handful of
  statusbar/tab colors) happened to run *after* `doom_one.setup()`, so
  it actually worked — which is exactly why *some* parts of the UI
  followed wal and others didn't.
- **Fix:** removed the duplicate/incomplete second block; moved the
  single call to `_apply_wal()` to run last (after `doom_one.setup()`
  and the `dark_mode` block), so the full ~20-property override always
  wins when `theme_mode == wal`. `:config-source` (already fired by
  `theme-apply`) re-runs the whole file, so wallpaper switches now
  retint tabs/statusbar/completion/hints/webpage-bg live, not just the
  homepage.

### nvim dashboard header stays default cyan
- **Symptom:** LazyVim Snacks dashboard header does not track palette.
- **Root cause:** `SnacksDashboardHeader` was pinned to `c.color4`
  (cool-fill) — always blueish.
- **Fix:** override to `c.color2` (dominant) plus Alpha / Startify /
  Telescope / WhichKey / NeoTree overrides in `themes.lua`.

### eww widgets (cheatsheet/onboarding/tooltip) do not follow wallpaper
- **Symptom:** eww kept doom-one colors after theme switch.
- **Root cause:** `colors.scss` was static, committed to repo.
- **Fix:** `theme-apply` rewrites `colors.scss` per palette
  (`gen_eww_scss`) with `$accent` = dominant + `$archicon` = dominant;
  fires `eww reload` after write. `colors.scss` gitignored, versioned
  template stays as `colors.scss.tmpl` (install.sh seeds first copy).

### qtile popup cheatsheets (Vim/Fish/Qtile) stuck on doom-one
- **Symptom:** popup COLORS never change.
- **Root cause:** hardcoded `COLORS = {...}` dict at module top.
- **Fix:** shared `popups/_wal_colors.load_colors()` reads wal cache
  each toggle (`COLORS.update(_load_colors())` at start of each toggle
  function). Semantic slots: green=dominant, red=urgent, blue=cool,
  purple=complement, muted=`bg`→`fg` 40% blend for readable dividers.

### New wallpaper (not in precompile cache) applies with old palette
- **Symptom:** dropped image into `~/Pictures/Wallpapers/`, selected
  via WallpaperPopup, colors did not change or used fallback.
- **Root cause:** cache miss triggered legacy live-wal path which lacks
  eww/qb regen.
- **Fix:** `theme-apply wal` now runs
  `wal-precompile --only <basename> --force` on cache miss before
  writing consumer files.

### Concurrent theme-apply races
- **Symptom:** partial consumer writes, half-tinted UI after rapid
  wallpaper switches / keybind spam.
- **Fix:** `flock -n` on `~/.cache/qtile/.theme-apply.lock`; second
  caller drops silently with a notify-send.

### `theme-apply` fails during install, before you've ever run `startx`
- **Symptom:** wizard's `themes` step fails with
  `Failed to show notification: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable`,
  even though `wal-precompile` above it clearly finished (all
  wallpapers processed, report written).
- **Root cause:** `theme-apply` runs under `set -euo pipefail` and
  ends with an unconditional `notify-send`. On a bare TTY — which is
  exactly where the installer runs before your first `startx` — there
  is no notification daemon (`dunst`) or D-Bus session for it to talk
  to, so that last line fails and takes down an otherwise-successful
  run with it.
- **Fix:** the final `notify-send "theme-apply" "Theme -> $MODE"` now
  has `2>/dev/null || true` so a missing notification service doesn't
  turn a successful theme apply into a reported failure. (The
  earlier fatal-path `notify-send` calls at lines ~99/104/120 are
  fine as-is — they're already followed by `exit 1` on a genuine
  error.)

---

## Rofi

### rofi-kill takes 10-18 seconds to open
- **Symptom:** Alt+Q (kill picker) freezes before menu appears.
- **Root cause:** bash `while read` loop iterating 280+ processes with
  6 subshells per iteration. Rofi cannot show its window until stdin
  hits EOF.
- **Fix:** rewrite as single-pass gawk pipeline. Pre-tag titles (`T\t`),
  ppid map (`P\t`), and ps rows (`R\t`) into one stream; awk builds
  in-memory lookups and emits pango rows in one pass. New total: <200ms.

### rofi-kill vertical dividers misaligned
- **Symptom:** `│` between columns shifts left on some rows.
- **Root cause:** rofi base font `FiraCode Nerd 12` resolves to Noto
  Sans (proportional) via fontconfig fallback. Different glyph widths
  in the same row throw padding off.
- **Fix:** wrap each row in `<span face="monospace">...</span>`. Pango
  substitutes a monospace family only inside rows; prompt / mesg keep
  the base proportional font so rofi UI stays consistent with other
  menus.

### rofi_common.sh not found when running rofi-kill
- **Symptom:** `rofi_common.sh: No such file or directory`.
- **Root cause:** stale copy of `rofi-kill` in `~/.local/bin` without
  its sibling `rofi_common.sh`. `~/.local/bin` precedes `/usr/local/bin`
  in `$PATH`, so the broken one wins.
- **Fix:** remove `~/.local/bin/rofi-kill` (installer uses
  `/usr/local/bin` which has the sibling). Or copy `rofi_common.sh`
  alongside every rofi-* script you place in `~/.local/bin`.

### rofi-kill kill did not actually kill the process
- **Symptom:** confirmed kill, target process still running afterwards.
- **Root cause:** `kill -15` (SIGTERM) is a request — trap-immune
  processes (own SIGTERM handler, zombie state, uninterruptible sleep)
  ignore it. Script reported success without verifying.
- **Fix:** `rofi_common.sh:kill_guaranteed` sends SIGTERM, polls
  `kill -0` up to 0.8s, escalates to SIGKILL, re-verifies. Only
  reports success if `kill -0` fails. Alt+k skips grace and goes
  straight to SIGKILL. Both call the same helper for consistency.

### rofi-kill confirm defaults to No — friction on every kill
- **Symptom:** Enter on process → arrow-down → Enter again.
- **Fix:** confirm defaults to Yes (single Enter confirms). Escape
  cancels. Users triggered the action intentionally; accidental
  double-Enter from the caller is rare.

### rofi-kill kills without asking Yes/No
- **Symptom:** hit Enter on a process, it dies immediately, no confirm.
- **Root cause:** `rofi_confirm` inherited the caller's `ROFI_THEME`
  (kill-large.rasi is huge). `-theme-str` overrides could not fully
  collapse it, so the confirm popup rendered off-screen or covered
  the pick list, making it invisible / mis-clicked.
- **Fix:** `rofi_confirm` now always uses `base.rasi` with tight
  overrides (`width: 22%`, `lines: 2`, `dynamic: false`) so the
  compact popup renders centered regardless of caller theme. Default
  `-selected-row 0` = No so accidental Enter cancels safely.

### Bash syntax error inside rofi-kill from an apostrophe
- **Symptom:** script fails to launch, `bash -n` reports "syntax
  error near unexpected token" inside the awk block.
- **Root cause:** an apostrophe (`don't`) in a comment inside the
  single-quoted awk script terminated the outer bash string. Every
  quote inside single-quoted `awk '...'` must be paired.
- **Fix:** rephrase without apostrophes (`do not`, `does not`).

### Screenshot picker (dm-satty / dm-maim) fails before the menu even shows
- **Symptom:** invoking the screenshot rofi menu does nothing /
  errors immediately, before you even get to pick a mode.
- **Root cause:** monitor detection used
  `xrandr --listactivemonitors | awk '/+/ {...}'` — a bare `+` is not
  valid ERE regex syntax (a quantifier with nothing to repeat). The
  comment even says the intent was "return only lines with +, ie
  grep", but it was never escaped. `gawk` (the default `awk` on Arch)
  rejects it outright: `awk: cmd. line:1: error: ? * + or {interval}
  not preceded by valid subpattern`. Under `set -euo pipefail` that
  kills the script before it can prompt for anything.
- **Fix:** escape it — `awk '/\+/ {...}'`. Fixed in both
  `AtiScriptsV1/dm-satty` and the sibling `dmscripts/scripts/dm-maim`
  (same copy-pasted line, same bug, in both places).

### rofi_ilovepdf silently does nothing (missing zenity / libreoffice)
- **Symptom:** the ilovepdf rofi menu never opens a file picker, or
  document→PDF conversion never happens.
- **Root cause:** `zenity` (file picker) and `libreoffice-fresh` (doc
  conversion) were used by the script but declared in **no** dcli
  module yaml — nothing would ever install them on a fresh setup.
- **Fix:** added both to `apps.yaml`.

---

## Qtile freezes

### KeyChord or widget freezes qtile main loop
- **Symptom:** WM stops responding for seconds after keybind or widget
  poll.
- **Root cause:** blocking subprocess / IO on the main event loop
  (e.g. `subprocess.run` without timeout, `pactl` blocking on server
  restart, `pacman -Qu` blocking on db lock, rofi launched with
  `check_output` blocking until popup closes).
- **Fix pattern:** move IO into `threading.Thread(daemon=True)`; apply
  UI update via `qtile.call_soon_threadsafe(...)`. Add explicit
  `timeout=N` to every subprocess call. See recent commits:
  - `AudioPopup` — pactl timeouts
  - `UpdatesPopup` — pacman -Qu/-Si off main loop, rofi in thread
  - `BluetoothPopup` / `WifiPopup` — timeouts + call_soon_threadsafe
  - `WallpaperPopup` — fuzzy rofi search off main loop
  - `volume_control` — pactl + notify-send timeouts
- **Detailed report:** `.config/qtile/QTILE_FREEZE_REPORT.md`.

---

## Qtile config

### Every app-launching keybind crashes: `'Qtile' object has no attribute 'cmd_spawn'`
- **Symptom:** browser toggles, terminal, file manager, Telegram,
  Obsidian, etc. keybinds all fail with `AttributeError: 'Qtile'
  object has no attribute 'cmd_spawn'. Did you mean: 'no_spawn'?` in
  `~/.local/share/qtile/qtile.log`.
- **Root cause:** a `pacman -Syu` upgraded `qtile` itself (0.36.0),
  which removed the old `Qtile.cmd_spawn()` method in favor of
  `Qtile.spawn()` (same signature, drop-in rename). `config.py` and
  the `scripts/*.py` helpers still called the old name — 17 call
  sites total across `config.py`, `toggle_apps.py`, `sum_app.py`,
  `collector_app.py`.
- **Fix:** mechanical rename, `qtile.cmd_spawn(` → `qtile.spawn(`,
  everywhere. Verified no other `qtile.cmd_*` pattern exists in the
  config (this was the only deprecated call).

### Newly-installed packages/config don't take effect after `reload_config`
- **Symptom:** `qtile cmd-obj -o cmd -f reload_config` runs with no
  error, but nothing visibly changes — e.g. `ModuleNotFoundError: No
  module named 'qtile_extras'` or `NameError: name 'BusType' is not
  defined` (mpris2 widget) keep appearing in the log every time you
  reload.
- **Root cause:** `reload_config` only re-imports `config.py` in the
  **already-running** qtile process — it does not restart the process
  or re-run other modules' top-level imports (e.g. `libqtile.utils`'s
  `try: import dbus_fast ... except ImportError: has_dbus = False`,
  decided once at process start and cached forever). If qtile has been
  running since before a package got installed, that package stays
  invisible to it no matter how many times you reload.
- **Fix:** a full qtile restart (`qtile cmd-obj -o cmd -f restart`) —
  not just `reload_config` — whenever packages the config imports
  change. On a genuinely fresh install this doesn't come up: qtile
  only starts (via `startx`) *after* every package is already in
  place.

### Disk widget shows the wrong free space / too many decimals / wrong partition logic
- **Symptom (iterated through several related issues, same widget):**
  the number looked way too small (e.g. "4GB" when there's actually
  180+GB free); the free-space number showed a dozen decimal digits
  ("182.44448...") instead of a clean "182.4"; libqtile's `DF` widget
  can only ever show *one* partition per instance, with no way to
  reflect both `/` and `/home` when they're genuinely separate disks.
- **Root cause:** the `DF` widget was hardcoded to `partition="/"`
  with no precision specifier on its format string. On any setup
  where `/home` is a separate partition from `/` (common Arch install
  pattern), that showed root's (much smaller) free space, unrounded.
- **Fix:** replaced the `DF` widget with a custom `ewidget.GenPollText`
  chip driven by `_disk_combined_text()`. Uses `os.stat().st_dev` (not
  a free-space value comparison — too fragile, two different
  partitions could coincidentally have similar free space) to detect
  whether `/` and `/home` are actually the same filesystem:
  - **Same filesystem** (no separate `/home` partition): chip shows
    just `🖴 /12.3G`.
  - **Genuinely separate partitions**: chip shows whichever of the
    two has *more* free space (`🖴 ~181.5G` here, since home has far
    more room than root) — one number, not both, to keep the chip
    compact; the full breakdown is still one click away.
  The click-tooltip (`_disk_parts_text`, wired via
  `_make_tooltip_dynamic`) continues to list every mounted filesystem
  on hover, and the click handler (`disk_notify`) was rewritten the
  same way: compares `df --output=source` for `/` vs `/home` and
  shows a TOTAL/USED/FREE notification block for both when they're
  separate partitions, or just one block when they're not.

### Language widget shows no flag icon next to "EN"/"AR"/"TR"/"DE"
- **Symptom:** blank space where a flag emoji should render next to
  the keyboard-layout code.
- **Root cause:** `KeyboardLayout`'s `display_map` uses literal flag
  emoji (regional-indicator Unicode sequences, e.g. 🇺🇸). No font on
  the system had emoji glyph coverage — `noto-fonts-emoji` was never
  declared in any dcli module.
- **Fix:** added `noto-fonts-emoji` to `fonts.yaml`.

### "X" wallpaper-picker chip only ever opens the picker, never closes it
- **Symptom:** clicking the ✖/ chip in the bar (`wallpaper_toggle`)
  while the wallpaper picker is already open doesn't close it — it
  just re-fires the same "open" action.
- **Root cause:** the chip's *icon* correctly tracked open/close state
  already (via `enter_chord`/`leave_chord` hooks calling `w.toggle()`
  on the `wallpaper_toggle` `SmartWidgetBox`) — but the `Button1`
  `mouse_callbacks` handler never checked that state. It unconditionally
  simulated the `mod+p, b` keypress sequence that opens the picker,
  every single click.
- **Fix:** added `toggle_wallpaper_picker(qtile)` — checks
  `wallpaper_toggle` widget's `box_is_open` and calls
  `close_wallpaper_mode(qtile)` when already open, otherwise does the
  original open sequence. Chip's callback now points at this instead
  of the raw open-only lambda.

### btop never gets themed — always shows default colors regardless of wallpaper/theme
- **Symptom:** every other app (kitty, rofi, gtk, dunst, eww, qb, ...)
  follows the active theme; btop stays on its stock default palette.
- **Root cause:** nothing in this setup ever generated a btop `.theme`
  file or wrote `~/.config/btop/btop.conf` — btop was simply never
  wired into `theme-apply` at all.
- **Fix:** `gen_btop_theme()` (new, mirrors `gen_gtk_css`/
  `gen_eww_scss`'s pattern) maps the 9-slot palette onto btop's ~40
  `theme[...]` keys — direct assignment for solid colors (bg/fg/boxes),
  and a light→dark HLS gradient per hue for the 3-stop meter colors
  (cpu/mem/temp/net/etc, each using a different accent as its base
  hue). Writes `~/.config/btop/themes/wal-theme.theme` and points
  `btop.conf`'s `color_theme` at it. Wired into `gen_all_theme_css`
  alongside the other consumers. No live-reload — btop has no signal
  API for it, so it picks up the new theme on its *next* launch, same
  as how brave/chrome are handled (relaunch, not hot-reload).

### Touchpad tap-to-click doesn't work right after the wizard finishes
- **Symptom:** `/etc/X11/xorg.conf.d/30-touchpad.conf` exists and
  looks correct, `xinput list` shows the touchpad, but tapping doesn't
  register as a click.
- **Root cause:** same stale-session pattern as the qtile-extras/
  dbus-fast/.Xmodmap entries above, just for X itself this time. X
  only reads `xorg.conf.d/*.conf` at server startup — if X was already
  running before the wizard wrote that file (e.g. you started the
  install from an existing desktop session instead of a bare TTY),
  the running X server never sees it. `xinput list-props <id>` shows
  `libinput Tapping Enabled: 0` even though the conf file says `on`.
- **Fix:** none needed in the installer — a genuinely fresh install
  runs from a bare TTY *before* the first `startx`, so this can't
  happen there; the config is already in place before X ever reads
  it. If you hit this because you installed from a live session, log
  out to TTY and run `startx` fresh, or apply it live without
  restarting: `xinput set-prop <id> "libinput Tapping Enabled" 1`
  (find `<id>` via `xinput list`).

### Triangle chip (systray box) never shows the nightlight lamp icon
- **Symptom:** opening the `△` systray widgetbox never shows the
  nightlight toggle, even though `w_nightlight` is defined inside it.
- **Root cause:** neither `gammastep` nor `redshift` was installed —
  undeclared in any dcli module (same class of gap as `anki`/
  `playerctl`/etc. earlier). `_nightlight_text()` returns `""` when
  neither binary exists, and the widget is a `HideablePollText`,
  which fully hides itself (zero width, no draw) on empty text. Not a
  logic bug — the widget was working exactly as designed, just for a
  binary that didn't exist.
- **Fix:** added `gammastep` to `system-tools.yaml` (the code already
  prefers it over `redshift` when both are present).

### Triangle chip (systray) is always empty
- **Symptom:** the system tray never shows any icons, regardless of
  what's installed.
- **Root cause:** `Systray()` is a passive widget — it only displays
  icons for applications that actively register themselves via the
  tray protocol. Nothing was autostarting any tray-capable app.
  `blueman-applet` and `nm-applet` were both already installed but
  neither was referenced anywhere in `.xinitrc`.
- **Fix:** added `command -v blueman-applet >/dev/null 2>&1 &&
  blueman-applet &` and the equivalent for `nm-applet` to `.xinitrc`
  (both in `step_xinit`'s heredoc in `wizard.sh`, and the live
  `~/.xinitrc`), right after the `picom` autostart block.

### `copyq_rofi` shows no clipboard history
- **Symptom:** the copyq rofi picker opens but there's nothing to
  pick — no history at all, even after copying things.
- **Root cause:** `copyq` was never autostarted anywhere. Its
  background server is what actually monitors and records clipboard
  changes; without it running continuously, there's nothing for
  `copyq_rofi`'s `copyq eval` calls to query.
- **Fix:** added `command -v copyq >/dev/null 2>&1 && copyq
  --start-server &` to the same `.xinitrc` autostart block.
  `--start-server` runs it headless (tracks clipboard, tray icon) —
  doesn't pop its window open on every login.

### Alt key (the Caps-as-Alt workaround) doesn't work — xcape refuses to start
- **Context:** this laptop's physical Alt key is broken in hardware
  (documented in `config.py`: `mod = "mod4"  # ... Alt broken on
  hardware`) — that's *why* `.Xmodmap` remaps Caps Lock to send
  `Alt_L`, with `xcape` restoring a quick-tap-for-real-Caps-Lock
  fallback. Not something introduced today.
- **Symptom:** `xcape -e 'Alt_L=Caps_Lock'` fails outright:
  `WARNING: No keycode found for keysym Caps_Lock (0xffe5) in mapping
  Alt_L. Ignoring this mapping. / Failed to parse_mapping`. Since it
  never starts, holding Caps still works as a raw Alt modifier (that
  part's a direct keycode remap, independent of xcape), but tapping
  Caps no longer gives you an actual Caps Lock toggle at all.
- **Root cause:** `.Xmodmap`'s `keycode 66 = Alt_L` replaces *every*
  level of that key's symbol table with `Alt_L` — the `Caps_Lock`
  keysym stops existing anywhere in the current keymap. `xcape` needs
  to synthesize a real keycode press for its tap-target, and can't
  find one for a keysym that's been completely removed from the map.
- **Fix:** `keycode 66 = Alt_L Caps_Lock Alt_L Caps_Lock` — keeps
  `Alt_L` as the primary (unshifted) symbol so nothing about normal
  Alt-modifier behavior changes, but adds `Caps_Lock` back as an
  inert level-2 (shifted) symbol purely so xcape has a valid keycode
  to target. Confirmed inert: the `Lock` modifier group is `clear`ed
  separately and nothing rebinds it, so this never actually toggles
  caps lock as a modifier — it only exists for xcape's internal
  lookup. Fixed in both the live `~/.Xmodmap` and `step_xmodmap`'s
  heredoc in `wizard.sh`.

---

## Testing on a fresh Arch VM

Before trusting `./install.sh` on your primary machine, run it on a
throw-away VM. Fastest reliable path:

```bash
# 1. Download Arch ISO (~1 GB)
curl -LO https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso

# 2. Boot in your GUI hypervisor of choice — separate window, own RAM.
#    - GNOME Boxes / virt-manager / VirtualBox / QEMU GUI
#    - Suggest: 4 GB RAM · 20 GB disk · 2 vCPU
#    - Enable UEFI, virtio disk
#    - Boot from ISO

# 3. Inside VM: unattended base install
loadkeys us
archinstall   # follow prompts: minimal, user with sudo, mirror region

# 4. Reboot into installed system, log in as your user
git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles
cd ~/.dotfiles/installScripts
./install.sh
```

**Why a real hypervisor, not nspawn/docker on your daily machine:**
running the full wizard (dcli sync ~5 min pacman, piper 60 MB curl,
whisper 500 MB curl, wallpapers 500 MB git clone, chrome policy sudo
writes) concurrently with your normal workload can saturate disk / RAM
and freeze the host. A separate VM with its own resource ceiling
never contends with your session.

**Success criteria at end:**
Wizard prints the green-bordered "Installation Complete · ✔ 26 ok · ⚠ 0
not run · ✖ 0 failed" card. Logout, `startx`, and qtile + wal theme
should come up cleanly.

## Wizard / Installer

### `gum: command not found` on fresh Arch
- **Symptom:** wizard.sh prints error, exits.
- **Root cause:** wizard depends on `gum` for the TUI; not in base.
- **Fix:** wizard auto-runs `sudo pacman -S --needed --noconfirm gum`
  on first launch. If that fails (offline / mirror down), install
  manually then re-run: `sudo pacman -S gum && ./wizard.sh`.

### Module fails, wizard offers retry / skip / quit
- **Symptom:** step shows `✖ failed (attempt N)` + red tail-box.
- **Where to look:** `/tmp/wizard-<id>.log` (stdout) and
  `/tmp/wizard-<id>.err` (stderr). Wizard displays last 5 error lines
  inline; full logs on disk.
- **Fix by choice:**
  - `retry` — re-runs the same step (fixes transient network/db lock)
  - `skip · continue` — marks as failed, continues; failed list shown
    in final summary card
  - `quit installer` — aborts, prints partial summary (ok / skipped / failed)

### Preselected modules render mixed `✓` and `•` in picker
- **Root cause:** gum `--selected` takes CSV; module descriptions
  containing literal commas broke the parse — some items matched, some
  did not.
- **Fix:** all module descriptions use `·` as separator, never commas.

### `install.sh` behaves differently than before
- **Fact:** `install.sh` is now a 4-line alias for `wizard.sh --yes`.
- **Reason:** single-installer refactor — one code path to maintain.
  Everything install.sh used to do is now in `wizard.sh`'s `step_*`
  functions.

### Wizard crashes with `unbound variable` while reviewing modules
- **Symptom:** `wizard.sh: line NNN: MOD_GROUP[$id]: unbound variable`
  right after the module-review screen renders.
- **Root cause:** a module id was left in `MOD_ORDER` (and, for
  uninstall, `UMOD_CMD`) but its `_reg id "Title" Group "Desc" cmd`
  metadata line was deleted — e.g. `flatpak` lost its `_reg` line when
  the flatpak+Collector install step was replaced by qdrop, but the id
  stayed in `MOD_ORDER` on purpose so `--uninstall` can still clean up
  leftover flatpak installs from before qdrop existed. `set -u` turns
  the missing `MOD_TITLE`/`MOD_GROUP`/`MOD_DESC` lookup into a hard
  crash instead of a blank field.
- **Fix:** every id in `MOD_ORDER` must have a matching `_reg` line.
  If a module's *install* step is retired but the id must stay for
  `--uninstall` cleanup, keep `_reg` with a no-op `MOD_CMD` (see
  `step_flatpak` — install mode just prints "nothing to install").

### Wizard dies mid-run instead of showing a failed step
- **Symptom:** wizard exits entirely with
  `wizard.sh: internal bash error (rc=1) at line NNN` instead of the
  normal red "✖ failed" card + retry/skip/quit prompt.
- **Root cause:** `_show_error_tail()` builds its preview with
  `tail -5 "$errf" | grep -v '^\s*$' | head -5`. `grep -v` returns exit
  status 1 whenever every line is filtered out (e.g. the failed
  module's stderr file is empty or all-blank). Under
  `set -Eeuo pipefail`, that trips the top-level `ERR` trap and kills
  the whole wizard — right when it's trying to report a failure, which
  is the worst possible moment.
- **Fix:** append `|| true` to both `tail_content=$(...)` assignments
  in `_show_error_tail` so a quiet/empty log falls through to the
  "(no output captured)" message instead of aborting the installer.

### Wizard dies while seeding the default wallpaper
- **Symptom:** wizard exits during the `themes` step (or earlier) with
  an `internal bash error` pointing at the `find "$HOME/Pictures/..."`
  line inside `step_themes`.
- **Root cause:** that `find` isn't wrapped in the dry-run-safe `run()`
  helper, so it executes for real even under `--dry-run`. If
  `~/Pictures/Wallpapers` doesn't exist yet — deselected `wallpapers`
  module, failed clone, or a dry run where nothing was actually cloned
  — `find` on a missing directory returns non-zero, and `pipefail` +
  `set -e` turns that into a fatal error.
- **Fix:** append `|| true` to the `first=$(find ... | sort | head -1)`
  assignment so a missing wallpapers directory just skips the
  default-wallpaper seed instead of crashing.

### `sudo` password rejected repeatedly even though it's correct
- **Symptom:** `Sorry, try again` on every attempt, including a
  password you're 100% sure is right.
- **Root cause 1 (most common):** the installer was started through a
  wrapper that has no real interactive terminal attached (Claude
  Code's tool sandbox, a `stdin < /dev/null` invocation, etc.). `sudo`
  can't read a password at all in that context and fails instantly —
  `journalctl` shows `pam_unix(sudo:auth): conversation failed` /
  `auth could not identify password`, not a normal "incorrect
  password" line.
- **Root cause 2 (the trap):** enough of those no-tty failures in a
  row trips `pam_faillock`, which **temporarily locks the account**.
  Every attempt after that — even the correct password, typed in a
  real terminal — gets rejected until the lock clears.
- **Diagnose:** `journalctl --since "10 min ago" | grep -i "sudo\|pam_unix\|faillock"`.
  `pam_faillock(sudo:auth): ... temporarily locked` confirms the lockout.
- **Fix:** always run `./install.sh` / `./wizard.sh` from a real
  terminal emulator, never through an automation/tool bridge that
  doesn't attach a tty. If already locked out, `faillock`'s tally
  lives in `/run/faillock` (tmpfs) — a `reboot` clears it instantly.
  Without rebooting: `faillock --user <you>` to check, then
  `faillock --user <you> --reset` from a session that still has valid
  root (or wait out `unlock_time` in `/etc/security/faillock.conf`).

### Long steps (e.g. `dcli sync`) look frozen with no output
- **Symptom:** progress bar sits at one step for minutes with nothing
  on screen, indistinguishable from a hang.
- **Root cause:** `_run_module()` redirected the module's entire
  stdout/stderr straight into `/tmp/wizard-<id>.log`/`.err` and only
  printed it on failure — a genuinely slow step (package sync, AUR
  build, big download) looked identical to a stuck one.
- **Fix:** `_run_module()` now runs the step in the background and
  redraws a spinner + the last line it actually wrote (from either
  stream) roughly every 0.12s, so real progress — package names,
  download status, clone output — is visible live instead of hidden
  until the step finishes or fails.

### `sudo` credential cache expires mid-run — silent package-install failures

- **Symptom:** wizard reports a step (e.g. `Speed tweaks`) as
  `✖ failed` with `sudo: timed out reading password` near the end of
  a long run. Worse: `dcli sync` itself can report `✔ ok` while
  individual AUR packages that finished building (`makepkg` prints
  `Finished making: X`) never actually get installed — the final
  `sudo pacman -U` install-after-build step failed silently and
  nothing surfaced it.
- **Root cause:** `sudo`'s credential cache (~15 min default) doesn't
  survive a long AUR build phase (30-60+ min is normal for a big
  `dcli sync`). Whichever `sudo` call happens to fire after the cache
  expires fails; if nobody's watching the terminal at that exact
  moment, it's never answered. `yay`/`dcli` don't necessarily fail the
  whole run over one lost install, so the step can still read as
  successful overall.
- **Fix:** `main()` now calls `_start_sudo_keepalive` right after
  preflight — primes `sudo -v` once with a clean prompt, then
  refreshes it in the background every 60s for the entire run (cleaned
  up via an `EXIT` trap). `step_dcli_sync` additionally re-checks with
  `dcli sync --dry-run` after the main sync and retries (bounded, 2x)
  if anything's still pending, so even a rare gap self-heals instead
  of silently shipping a half-installed system.
- **If you hit this on an already-finished install:** run
  `dcli sync --dry-run` to see what's actually still missing (compare
  against what you'd expect), then `dcli sync --force` to catch it up.

## Install / Bootstrap

### `dcli sync` fails on fresh Arch
- **Fix:** run `installScripts/install.sh` first; it bootstraps yay,
  installs `dcli-arch-git`, then calls `dcli sync`.

### `dcli sync` step hangs / silently cancels — packages never installed
- **Symptom:** step shows the package list then
  `Apply these changes? [y/N] Cancelled`, or the whole wizard appears
  to hang for many minutes with no visible progress at that step.
- **Root cause:** `dcli sync` prompts for interactive confirmation by
  default (`[y/N]`, defaulting to **No**). `wizard.sh`'s own `--yes`
  only skips the wizard's *own* prompts — it never reached into
  `dcli`'s. Pressing Enter (or the wizard having no tty at all)
  answered "No", so **zero packages were installed** even though the
  step didn't clearly say so up front. A separate `sudo mandb` chained
  after it could also fail on a system without `man-db` installed,
  masking the real (bigger) problem underneath.
- **Fix:** `step_dcli_sync` now runs `dcli sync --force` (skips the
  confirmation prompt) and guards the `mandb` call with
  `command -v mandb` so a missing `man-db` package doesn't fail the
  step either.

### `dcli sync` reports "✓ Packages synced successfully" while packages are still missing
- **Symptom:** this has now shown up for **three separate, unrelated
  root causes** — always with the same misleading green "success"
  message printed regardless of what actually happened above it.
  Always verify with `dcli sync --dry-run` after any large sync if
  something downstream seems to be missing a binary; don't trust the
  success message alone.
  1. **sudo credential timeout mid-build** — see the wizard.sh
     sudo-keepalive entry above. Packages show `Finished making: X`
     but never actually get `pacman -U`'d.
  2. **A hard package conflict blocks the entire batch** — e.g. `yay`
     vs `yay-bin` (see next entry): *every* package in that sync
     round fails to install, not just the conflicting one, because
     it's one `pacman -U` transaction.
  3. **A build-time tool failure inside one package's `prepare()`**
     — e.g. the `rustup` default-toolchain issue (see below) breaks
     every cargo-based AUR package, but only those specific packages
     fail; everything else in the batch still installs fine.
- **Takeaway:** `dcli sync`'s own success/failure reporting cannot be
  trusted at face value for a large sync with AUR packages. `wizard.sh`
  now self-verifies (`step_dcli_sync`'s dry-run + retry, see above),
  but if you ever run `dcli sync` by hand, get in the habit of a
  follow-up `dcli sync --dry-run` to confirm the summary matches
  reality.

### `yay` and `yay-bin` conflict — blocks the *entire* package sync, not just yay
- **Symptom:** a big `dcli sync --force` builds every declared AUR
  package successfully, then the final batch install fails outright:
  `:: yay-13.0.1-1 and yay-bin-13.0.1-1 are in conflict. Remove
  yay-bin? [y/N]` → `error: unresolvable package conflicts detected`.
  Since it's one pacman transaction, **nothing** in that sync round
  gets installed — not just yay.
- **Root cause:** `wizard.sh`'s own bootstrap (`step_yay`) deliberately
  builds `yay-bin` (prebuilt, no compile-time chicken-and-egg problem
  before any AUR helper exists yet) — but `base.yaml` separately
  declared plain `yay` (built from source). Same binary, two different
  AUR packages, pacman refuses to have both.
- **Fix:** `base.yaml` now declares `yay-bin`, matching what
  `step_yay` already bootstraps, instead of the conflicting `yay`.

### cargo-based AUR packages (paru, didyoumean) and `cargo install` both fail: "rustup could not choose a version of cargo to run"
- **Symptom:** `error: rustup could not choose a version of cargo to
  run, because one wasn't specified explicitly, and no default is
  configured.` — during a `paru`/`didyoumean` AUR build (`==> ERROR: A
  failure occurred in prepare().`), and separately, `wizard.sh`'s own
  `step_cargo` (`cargo install pomodoro-tui`) silently "succeeds"
  (its `command -v cargo && run ... || _WARN "skip"` fallback quietly
  swallows the failure) without actually installing anything.
- **Root cause:** `rustup` installs the `stable` toolchain but never
  activates it as the *default* — `rustup show` reports "no active
  toolchain" even though `stable` is present. Every `cargo`/`rustup`
  invocation needs a default set, whether it's `wizard.sh`'s own
  `cargo install` or `makepkg` building a Rust-based AUR package.
- **Fix:** `step_cargo` now runs `rustup default stable` (idempotent,
  safe every run) before attempting `cargo install pomodoro-tui`. This
  also fixes AUR builds of `paru`/`didyoumean`/any other cargo-based
  package for the rest of the same session, since it's a persistent
  per-user rustup setting, not scoped to the wizard step.

### Declared package name doesn't exist: `shell-color-scripts`
- **Symptom:** `dcli sync --dry-run` shows `shell-color-scripts` as
  pending forever; a real sync reports `-> No AUR package found for
  shell-color-scripts`.
- **Root cause:** the actual AUR package is named
  `shell-color-scripts-git` (with the `-git` suffix) — the declared
  name in `system-tools.yaml` was just wrong, unrelated to any of the
  sudo/rustup/conflict issues above.
- **Fix:** corrected to `shell-color-scripts-git`.

### AUR helper (yay) step fails after a previous failed/interrupted run
- **Symptom:** `fatal: destination path 'yay-bin' already exists and is
  not an empty directory.`, then the `dcli` step fails too with
  `yay: command not found` since it never got built.
- **Root cause:** `step_yay` clones into `/tmp/yay-bin` but never
  cleans up a partial clone left behind by an earlier failed/aborted
  run (e.g. sudo failing mid-build) — not actually idempotent despite
  the wizard's "re-run — steps are idempotent" promise on interrupt.
- **Fix:** `step_yay` now runs `rm -rf /tmp/yay-bin` immediately
  before cloning, so a stale partial clone from a previous attempt
  never blocks a fresh one.

### AtiScriptsV1 install skips subdirectories
- **Symptom:** helper libraries under `AtiScriptsV1/` subdirs missing
  in `/usr/local/bin/`.
- **Fix:** installer now skips directories rather than trying to
  `sudo cp -r`. Only regular files in the top level are installed.

### Chrome policy directory does not exist on first run
- **Symptom:** `install.sh` step 23b fails writing
  `/etc/opt/chrome/policies/managed/wal-theme.json` (path missing).
- **Fix:** step 23b now `sudo mkdir -p` both
  `/etc/opt/chrome/policies/managed` and
  `/etc/chromium/policies/managed` before writing.

---

## Symlink / stow

### `~/.config/eww/colors.scss` git-diff churn
- **Symptom:** committed file constantly modified after wallpaper
  switch since it lives under a stow-symlinked dir.
- **Fix:** gitignore `colors.scss`, ship `colors.scss.tmpl` as
  versioned template. install.sh copies tmpl → colors.scss on first
  run; `theme-apply` overwrites thereafter.

### Homepage.html diff on every apply
- **Symptom:** `homepage.html` shows dirty after every wallpaper
  switch even though structure did not change.
- **Root cause:** inline `BEGIN-THEME-VARS`/`END-THEME-VARS` block
  gets rewritten with new hex codes per palette.
- **Fix:** tracked file, minor churn accepted (block is small).
  Do not `git add` the file unless you intended to change structure.

---

## Fish shell

### Fish startup errors: `Unknown command: colorscript`, `mktemp: failed to create file via template '~/tmp/.psub.XXXXXX'`, Rust panic `Broken pipe`, `source: missing filename argument`
- **Symptom:** a wall of errors on every new fish shell / terminal —
  `colorscript` not found, a `mktemp` failure referencing
  `~/tmp/.psub.XXXXXX`, a Rust panic about a broken pipe, and `source:
  missing filename argument or input redirection`. `starship`'s
  prompt and `pyenv`'s shims silently don't work either.
- **Root cause (two independent bugs, same symptom cluster):**
  1. `colorscript` is provided by the `shell-color-scripts` package
     (config.fish calls it unconditionally on startup) — if it's not
     installed yet, that's the "Unknown command" error, nothing more.
  2. `fish_variables` (versioned, stowed) pins a universal variable
     `TMPDIR:/home/ati/tmp` — but that directory was never created.
     Both `starship init fish | source` and `pyenv init - | psub`
     depend on fish's `psub` (process substitution), which needs
     `mktemp` to succeed against `$TMPDIR`. When it can't create the
     temp file there, `psub` produces nothing, `source` gets no
     input and complains about a missing filename, and whichever Rust
     binary was writing into that now-dead pipe (`starship`) panics
     with a broken-pipe error on its own stdout write. None of this
     is a starship or pyenv bug — both work fine once `~/tmp` exists.
- **Fix:** `step_image_envs` in `wizard.sh` now also runs
  `mkdir -p $HOME/tmp` (colocated with the other tiny one-off
  `$HOME` setup tweaks it already does). `shell-color-scripts` install
  is handled by a normal `dcli sync`.
- **Note on `TMPDIR`:** this whole dotfiles repo hardcodes `/home/ati`
  paths throughout (not written to be portable across usernames), so
  the fix here is "make sure the directory exists," not "make the
  path dynamic" — consistent with the rest of the codebase's actual
  design, not a gap worth closing on its own.

---

## Adding new cases

Append entries here as you hit them. Keep the same tri-format
**Symptom / Root cause / Fix** so grep-through stays uniform.
