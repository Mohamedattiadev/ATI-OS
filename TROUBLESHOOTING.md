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

## Install / Bootstrap

### `dcli sync` fails on fresh Arch
- **Fix:** run `installScripts/install.sh` first; it bootstraps yay,
  installs `dcli-arch-git`, then calls `dcli sync`.

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

## Adding new cases

Append entries here as you hit them. Keep the same tri-format
**Symptom / Root cause / Fix** so grep-through stays uniform.
