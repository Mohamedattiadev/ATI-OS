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

### Picking a new wallpaper doesn't retheme anything (pcmanfm/qb/eww/popups all stay stale)
- **Symptom:** selecting a wallpaper via `WallpaperPopup` (or
  `dm-setbg`) changes the desktop background image, but every themed
  consumer — GTK apps, qutebrowser, eww, qtile popups — keeps
  whatever colors it had before, as if `theme-apply` never ran.
- **Root cause:** both `WallpaperPopup.apply_wallpaper()` and
  `dm-setbg`'s `reapply_wal()` (both copies —
  `AtiScriptsV1/dm-setbg` and `dmscripts/scripts/dm-setbg`) only
  called `theme-apply wal` if `~/.cache/qtile/theme_mode` was
  *already* `wal`. If you were on any preset (doomone, dracula, ...)
  and picked a new wallpaper, nothing retheme'd — the check silently
  skipped it, since picking a wallpaper doesn't imply you were
  already in wal mode.
- **Fix:** removed the `theme_mode == "wal"` gate in all three places
  — picking a wallpaper through any of these paths now always calls
  `theme-apply wal` unconditionally, since selecting a wallpaper is
  itself an explicit "theme around this image" action.

### qutebrowser's own tabs/statusbar show a different accent than its homepage
- **Symptom:** in the same qutebrowser window, the tab bar/statusbar
  render one accent color while the homepage content (headers, clock)
  renders a visibly different one.
- **Root cause:** two independent color pipelines feeding the same
  app. `theme-apply`'s `gen_qb_css()` writes the homepage's CSS vars
  from the *semantically re-slotted* 9-slot palette
  (`~/.cache/qtile/current_palette.json` — the same source eww, nvim,
  and qtile popups all use). But qutebrowser's own `config.py`
  (`_apply_wal()`) read raw `~/.cache/wal/colors.json` `color4`
  directly for its native tabs/statusbar/completion accent — wal's
  raw color slots and theme-apply's hue-re-slotted semantic slots are
  not the same values for a given wallpaper.
- **Fix:** rewrote `_apply_wal()` to read `current_palette.json` like
  every other consumer, using its `green` slot as the accent (matching
  `gen_qb_css`'s `--accent: {green}`) so qb's native chrome and its
  homepage always agree.

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

### Folder icons never change color, regardless of preset
- **Symptom:** every other theme-apply consumer (kitty, rofi, qutebrowser,
  eww, btop, gtk accent colors, base gtk theme) retints correctly, but
  pcmanfm/nautilus folder icons stay whatever color they were on first
  install — `theme-apply`'s own log/notify shows success, no error
  anywhere.
- **Root cause:** `theme-apply` calls `papirus-folders -C <hue-match>`
  guarded by `command -v papirus-folders` — it silently no-ops the whole
  block if the binary isn't found. `papirus-icon-theme` (the icon set
  itself) was declared in `arch-config/modules/system-tools.yaml`, but
  `papirus-folders` (a separate AUR package that does the color-symlink
  swap) never was, so a machine provisioned purely via `install.sh` /
  `dcli sync` never had it.
- **Fix:** added `papirus-folders` to `system-tools.yaml` next to
  `papirus-icon-theme`. Picked up automatically by `dcli sync` — same
  AUR-via-yay path already used for `picom-ftlabs-git`,
  `whisper.cpp-git`, etc., no wizard.sh changes needed.
- **Verification:** ran `theme-apply <mode>` for all 21 modes (20
  presets + `wal`) and diffed the generated output of all 6 downstream
  consumers (btop `.theme` file + `btop.conf`, qutebrowser homepage CSS
  vars, eww `colors.scss`, the papirus folder-color symlink + gtk icon
  theme name, and `current_palette.json` as read by qtile
  popups/cheatsheets) against the exact hex values `theme-apply` itself
  defines per mode — 126 checks total, all passing after the fix above
  (including re-confirming the qutebrowser `--accent`/eww `$accent`
  slots still resolve to `green`, not a raw wal color, per the fix
  above this one). A representative sample (`mono-light`, `dracula`,
  `wal`) was additionally spot-checked visually via screenshots of
  btop, pcmanfm, and brave (full pipeline, including the browser
  extension repack/relaunch) to catch anything a file diff can't
  (stale icon cache, GTK theme not actually reloading, etc.) — all
  rendered correctly.

### Changing the wallpaper silently replaces the active preset theme
- **Symptom:** on `gruvbox` (or any preset), picking a new wallpaper —
  via the qtile wallpaper popup, `dm-setbg`, or the dmscripts
  `dm-setbg` — swapped the desktop image *and* repainted kitty, rofi,
  dunst, GTK, qutebrowser and the qtile bar into a wallpaper-derived
  palette. `~/.cache/qtile/theme_mode` flipped to `wal` and the preset
  was gone.
- **Root cause:** all three wallpaper setters called `theme-apply wal`
  unconditionally. That was a deliberate earlier change ("picking a
  wallpaper is an explicit *theme around this image* action"), but it
  conflates two separate choices. `wal` is the one mode that means
  "follow the wallpaper"; every preset is an explicit request for a
  *fixed* palette, so a wallpaper change there must not touch the
  theme.
- **Fix:** gate the `theme-apply wal` call on
  `~/.cache/qtile/theme_mode` already being `wal`, in all three
  setters:
  - `.config/AtiScriptsV1/dm-setbg` (`setbg()`)
  - `.config/dmscripts/scripts/dm-setbg` (`reapply_wal()`)
  - `.config/qtile/popups/WallpaperPopup.py` (`apply_wallpaper()`, via
    the new `current_theme_mode()` helper in `popups/_wal_colors.py`)

  The gate fails **closed** — an unreadable/missing `theme_mode` means
  "don't retheme", so a broken cache file can never overwrite a preset.
- **Note:** the wallpaper still changes in every mode; only the palette
  re-derivation is gated. To re-theme around a new wallpaper while on a
  preset, run `theme-apply wal` explicitly (or pick `wal` in the theme
  picker).

### qutebrowser keeps doom-one colors on every preset theme
- **Symptom:** switching to `gruvbox`/`dracula`/etc repainted the whole
  desktop but qutebrowser's tabs, statusbar and completion stayed
  doom-one blue. Only `wal` mode ever retinted the browser.
- **Root cause:** `.config/qutebrowser/config.py` opened `_apply_wal()`
  with `if mode != "wal": return`. But `theme-apply` dumps
  `~/.cache/qtile/current_palette.json` on **every** apply, preset
  included — the mode check was the only thing preventing presets from
  working.
- **Fix:** renamed to `_apply_palette()` and dropped the mode gate, so
  it retints from `current_palette.json` for all 21 modes. Also
  extended coverage to the groups `doom_one.setup()` hardcodes and the
  old block never overrode — `colors.messages.*` (this is what kept the
  `:adblock-update` info bar doom-one navy), `colors.prompts.*`,
  `colors.downloads.*`, `colors.statusbar.{caret,passthrough,private,
  progress,url}.*` and `colors.tabs.pinned.*` — 78 options total.
- **Accent slot:** the selected tab now uses the palette's `blue` slot
  rather than `green`. `blue` is the slot `theme-apply` also feeds to
  the GTK accent and to dunst's frame color, so qb's chrome sits in the
  same hue family as the rest of the desktop instead of inventing a
  second accent.
- **Gotcha:** `_apply_palette()` must stay *after* `doom_one.setup()`
  and after the `dark_mode` block — both set `c.colors.*` and clobber it
  otherwise. Its `except Exception: pass` also means one mistyped
  option name silently disables **all** browser theming, with no error
  anywhere. Validate names against `configdata.DATA` after editing:
  ```sh
  python3 -c "
  from qutebrowser.config import configdata; configdata.init()
  import re, os
  s = open(os.path.expanduser('~/.config/qutebrowser/config.py')).read()
  b = s.split('def _apply_palette():')[1].split(chr(10)+'# Called after')[0]
  n = set(re.findall(r'c\.((?:\w+\.)+\w+)\s*=', b))
  print('invalid:', [x for x in n if x not in configdata.DATA] or 'none')"
  ```

### dunst and eww render in a different font than the qtile popups
- **Symptom:** notifications and the eww onboarding/tooltips showed a
  monospace face, while the qtile popups right next to them (wallpaper
  picker, cheatsheets) used a proportional one.
- **Root cause:** each consumer named a *concrete family* independently
  and they drifted: dunst had `font = JetBrainsMono Nerd Font 10`, eww
  had `FiraCode Nerd Font` (tooltips) plus `JetBrainsMono NF` (18 rules
  across `cheatsheet.scss` + `onboarding.scss`). The qtile popups never
  set a font at all — `qtile_extras`' `PopupText` defaults to the
  **`sans` fontconfig alias**, which is why they alone looked different.
- **Fix:** route dunst and eww through the same alias instead of a
  family name, so all three resolve identically:
  - `.config/dunst/dunstrc.tmpl` → `font = Sans 10` (Nerd Font glyphs
    still render; pango falls back per-glyph)
  - new `.config/eww/fonts.scss` defines `$ui-font: sans-serif` (plus
    `$display-font` for the oversized cheatsheet splash title only),
    `@import`ed **first** in `eww.scss` so the variable is in scope for
    the `cheatsheet.scss` / `onboarding.scss` imports that follow
- **Where the alias resolves:** `~/.config/fontconfig/fonts.conf`. Change
  it there once to restyle qtile popups, eww and dunst together;
  `fc-match sans` shows the current winner. Note that file *prefers*
  Arimo / Tinos / Cousine, none of which are installed or declared
  (they live in `ttf-croscore`), so all three of its aliases currently
  fall through to `noto-fonts-cjk` — which **is** declared in
  `.config/arch-config/modules/fonts.yaml`, so a fresh install resolves
  the same way. Installing `ttf-croscore` would make `fonts.conf` work
  as written, at the cost of changing all three consumers at once.
- **Careful:** `~/.config/dunst/dunstrc` is *generated* by `theme-apply`
  from `dunstrc.tmpl`, and `~/.config/dunst` is a symlink into the repo,
  so the tracked `dunstrc` is overwritten on every apply. Edit the
  `.tmpl`; edits to `dunstrc` alone are lost at the next theme switch.
- **Knock-on:** the UI font is now *proportional*, so any notification
  body that aligns columns with padded spaces renders ragged. Wrap just
  that block in `<tt>` (pango monospace) rather than reverting the font —
  see `disk_notify`. Requires `markup = full`, which is set globally.
  Fixed-width `-----` separators are fine (they actually stopped wrapping
  onto a second line, since `Sans` is narrower than the old mono face).

### Disk chip popup is an unreadable wall of numbers
- **Symptom:** clicking the disk chip gave a bare TOTAL/USED/FREE list
  per filesystem, with the columns not lining up, a blank bold line above
  it, and no indication that `/` was 91% full.
- **Causes, in order of how much they hurt:**
  - No **percentage or bar** anywhere, so the one thing you actually
    open this for — "am I about to run out?" — had to be computed in your
    head from `USED` vs `TOTAL`.
  - Columns padded with literal spaces, which stopped aligning when the
    dunst font became proportional (see the entry above).
  - `notify-send ... "" "<body>"` passed an **empty summary**. dunstrc's
    `format = "<b>%s</b>\n%b"` still renders that empty `%s` as a blank
    bold line, which is where the dead space at the top came from. Always
    pass a real summary.
  - `-a success` set the *appname* to `success`, but the `[success]` rule
    in `dunstrc.tmpl` matches on **summary**, not appname — so it never
    applied and was pure noise.
- **Now:** per-filesystem percentage plus a 20-cell bar colored by
  threshold (<75 green / <90 yellow / >=90 red) and `free of total ·
  used` underneath. Colors come from `current_palette.json`, so it tracks
  the active theme, falling back to doom-one if that file is missing.
- **Which filesystem drives the alarm** — this is the subtle part.
  Escalation follows the **primary** filesystem (`/home` when it is
  separate, else `/`), *not* simply the fullest one. On a split layout
  `/` is a small system partition that sits chronically tight — here it
  is a 32G root at 91% — and letting it set the urgency meant a red
  "Disk almost full" banner on every single open. That trains you to
  ignore the banner, which destroys the value of the one signal that
  matters. `/home` therefore leads the list and sets the title.
- **`/` is not ignored**, two ways: it still renders its own red bar and
  percentage, and it escalates the whole popup once it passes
  `SYS_CRIT_PCT` (97%) — near enough to 100% to actually wedge the
  machine — with a title naming it, since the generic title no longer
  implies which filesystem is meant.
- **Titles:** `Disk usage` (normal) → `Disk filling up` (primary >=75) →
  `Disk almost full` (primary >=90, critical) → `<mount> almost full`
  (non-primary past SYS_CRIT_PCT, critical).
- **Bar math edge cases** (worth keeping if you touch it): never show an
  empty bar while any space is used, never show a full bar below 100%,
  and the two segments must always sum to exactly `BAR_WIDTH`.

### Chromium follows the palette but Chrome does not
- **Symptom:** after a theme switch Chromium showed the "Installed theme
  Wal Theme" toast and repainted, while Chrome came back in its stock
  colors every single time.
- **Two independent root causes**, either one alone is enough to break it:
  1. **Wrong extension id.** `theme-apply` hardcoded
     `EXT_ID="fommfacojlllmdogognehdgombidbpjg"`, but a Chromium
     extension id is `sha256(DER pubkey)[:32]` mapped `0-f`→`a-p` — a
     pure function of `~/.config/qtile/browser-theme.pem`, which
     `wizard.sh` generates *per machine*. `step_chrome_policy` derives
     the id correctly and writes
     `/etc/opt/chrome/policies/managed/wal-theme.json` keyed by it, but
     then the very first `theme-apply` rewrote `updates.xml` with the
     hardcoded id. Chrome's `force_installed` poll looked up its
     policy id, found no matching `<app>`, and gave up silently.
     Chromium never noticed because it gets the theme from
     `--load-extension`, not from policy.
  2. **Relaunched via the wrong binary.** `browser_bin()` mapped
     `chrome` → `/opt/google/chrome/chrome`, the bare binary.
     `~/.config/chrome-flags.conf` (which carries
     `--load-extension=…/browser-theme`) is read by the *wrapper*
     `/usr/bin/google-chrome-stable`, not by the binary. So every
     relaunch dropped the flag. Chromium's `/usr/bin/chromium` already
     is a wrapper, which is why only Chrome was affected.
- **Fix:** derive `EXT_ID` from the pem at runtime via
  `ext_id_from_pem()` (never hardcode it), and prefer the `/usr/bin`
  wrapper over the `/opt` binary in `browser_bin()`. Same hardcoded id
  was also removed from `uninstall_chrome_policy` in `wizard.sh`, where
  it had been deleting a nonexistent extension directory.
- **Landmine:** the purge loop runs `rm -rf "$base/Extensions/$EXT_ID"`.
  An empty `EXT_ID` expands that to the whole `Extensions` directory, so
  the block is now guarded on `-n "$EXT_ID"` in both files. Keep that
  guard if you touch this code.
- **Verify:**
  ```sh
  # these three must agree
  grep -o "appid='[^']*'" ~/.config/qtile/browser-theme-updates.xml
  sudo grep -o '"[a-p]\{32\}"' /etc/opt/chrome/policies/managed/wal-theme.json
  ls ~/.config/google-chrome/Default/Extensions/     # id appears after relaunch
  # and Chrome's main process must carry the flag:
  tr '\0' ' ' < /proc/$(pgrep -x chrome | head -1)/cmdline | grep -o '\-\-load-extension=[^ ]*'
  ```

### qutebrowser never restarts itself after a theme switch
- **Symptom:** `theme-apply` left qb on the old palette until it was
  restarted by hand, even though the script clearly calls `:restart` —
  and running that same command manually worked every time.
- **Root cause:** the calls lived in a `( ... ) &` subshell:
  ```sh
  ( timeout 3 qutebrowser ":config-source" 2>/dev/null
    timeout 3 qutebrowser ":restart" 2>/dev/null ) &
  ```
  The subshell inherits `set -euo pipefail` from the top of the script.
  Each qb IPC call spawns a full python client that needs ~2s when idle
  and considerably longer while qtile is restarting from this same
  script, so `timeout 3` expired routinely and returned **124** —
  and `set -e` then tore the subshell down *after* `:config-source` and
  *before* `:restart`. Standalone the call finished in 1.8s and so never
  reproduced.
- **Fix:** `|| true` on both calls so a slow/failed IPC can't abort the
  chain, realistic budgets (15s / 30s), and `setsid` so the restart
  still completes after `theme-apply` exits and survives the preemption
  `kill` that a rapid second theme switch sends.
- **Debugging tip:** `bash -x theme-apply <mode> 2>&1 | grep -A6
  qutebrowser` shows this instantly — the trace contains the
  `:config-source` line and simply has no `:restart` line after it. Any
  time a `( ... ) &` block in this script stops halfway, suspect
  inherited `set -e` plus a non-zero exit first.

### Wallpaper picker popup opens/closes with no animation
- **Cause:** it only ever had `fade_in_popup(..., duration=0.16)`, tuned
  for the small cheatsheet popups. On a 1050x680 panel that is over
  before the eye tracks it, and close had no animation at all.
- **Fix:** `_wal_colors.py` gained `fade_out_popup(layout, on_done)` and
  cubic easing (`_ease_out_cubic` in, `_ease_in_cubic` out — a linear
  opacity ramp reads as a flicker because perceived brightness is
  non-linear). The picker now fades in over 0.28s/18 steps and fades out
  before teardown.
- **Deliberately opacity-only.** Do **not** "improve" this into a slide
  or scale animation: changing a floating window's geometry while it is
  mapped is exactly what caused the qdrop mid-screen flash (qtile
  re-centers such windows), which cost a whole debugging session and is
  documented under the qtile sections. `_NET_WM_WINDOW_OPACITY` never
  touches placement.
- **Invariants if you edit this:** `on_done` must fire exactly once and
  must still fire when the window is already gone, or a popup can be
  stranded on screen forever. `_CLOSING` guards the interval between
  "fade started" and "hide() ran" so a fast re-toggle can't open a
  second picker that the pending teardown then blanks. `apply_wallpaper`
  deliberately uses `.kill()` instead of the fade — theme-apply restarts
  qtile immediately after, which would yank the animation mid-flight.
- **Verifying animations:** screenshots are useless here. Poll
  `xprop -id <win> _NET_WM_WINDOW_OPACITY` and assert the ramp is
  monotonic; the easing shows up as shrinking (in) or growing (out)
  deltas between steps.
- **Do not poll X in a tight loop to do this.** Spawning `xdotool` /
  `xprop` every ~12ms creates hundreds of short-lived X clients per
  second. Sample at >=50ms, over a single known window id, and always
  close popups you opened — orphaned popups accumulate when a test
  clears qtile's handle to them via `qtile cmd-obj -f eval`.

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

### qdrop's dropdown doesn't feel like it's sliding down, just pops open
- **Symptom:** the drop-stash window (`Alt+Shift+D`) appears/disappears
  abruptly rather than reading as a slide animation.
- **Root cause:** `Gtk.RevealerTransitionType.SLIDE_DOWN` was already
  correctly set (semantically: content slides in *from the top*,
  which is the right direction) — the actual issue was
  `REVEAL_MS = 150`, too fast at 150ms for the eye to register as
  motion rather than an instant pop.
- **Fix:** bumped to `REVEAL_MS = 260`, a more standard perceptible
  reveal duration.

### qdrop flashes at screen-center for a frame before sliding down from the top
- **Symptom:** on open (`Alt+Shift+D`), the window briefly appears in
  the middle of the screen for one frame, then jumps to the top and
  slides down as intended. The slide itself is smooth — only the
  initial flash is wrong.
- **Root cause:** `show_animated()` called `self.move(x, start_y)`
  *after* `self.show_all()`/`self.present()`. Confirmed via qtile's own
  `layout/floating.py` (`compute_client_position()`): a newly-mapped
  floating window only skips qtile's own center-on-screen placement if
  `client.has_user_set_position()` is true, which checks the X11
  `WM_NORMAL_HINTS` `USPosition`/`PPosition` flags. GTK only sets that
  hint from `move()` while the window is still unrealized — calling
  `move()` after `show_all()` (i.e. after the window is already mapped)
  just issues a plain post-map `ConfigureRequest` with no position
  hint, so qtile centers it on that first map and only *then* honors
  the reposition, producing one visible frame at screen-center before
  the jump to `start_y`.
- **Fix:** reordered `show_animated()` so `self.move(x, start_y)` runs
  *before* `self.show_all()`/`self.present()`, avoiding the center
  placement entirely instead of racing to correct it after the fact.
  Verified via `xdotool getwindowgeometry` polled every ~10-30ms across
  the whole open transition: X position is now constant from the very
  first sample (no center jump), Y moves monotonically from off-screen
  to the target. Auto-hide (the 8s inactivity timer) was separately
  confirmed to already call `hide_animated()` — not a raw `hide()` — and
  geometry-polling across that transition shows the same smooth
  monotonic slide back up off-screen before the real unmap.

### qdrop pops up while dragging to select/extend text
- **Symptom:** clicking and dragging upward inside a text field (e.g.
  to extend a selection) sometimes pops qdrop open mid-drag, with no
  keybind pressed.
- **Root cause:** `qdrop_watch.py` implements a "shake to show" gesture
  (rapid left-right pointer-direction reversals while Button1 is held,
  meant for waggling a picked-up file/text-drag the way macOS's Finder
  shelf works) by watching raw `RawMotion` X events. It only tracked
  the X-axis valuator; `MIN_SEG_PX = 8` is small enough that the
  incidental horizontal hand jitter naturally present in an almost-pure
  *vertical* drag (dragging up to extend a selection) was enough to
  rack up 3 direction reversals and satisfy the shake heuristic.
- **Fix:** now also tracks the Y-axis valuator and accumulates total
  `|dx|`/`|dy|` since the button press; a shake only fires if
  accumulated horizontal movement is at least as large as vertical
  movement (`MIN_DX_DY_RATIO = 1.0`). A real shake is horizontal-
  dominant (waggling roughly in place); a selection-extend drag is
  vertical-dominant with only incidental horizontal noise — this
  cleanly separates the two without touching reversal-detection
  sensitivity. Verified with synthetic `xdotool` pointer sequences:
  a vertical drag with small horizontal jitter no longer triggers
  qdrop; a genuine horizontal shake still does.
- **Superseded:** `MIN_DX_DY_RATIO` is gone — see the entry below. It
  was a proxy for "is the user actually carrying something"; qdrop now
  asks X that question directly, so the axis restriction it imposed
  (which also made up/down shakes impossible) is no longer needed.

### qdrop opens on any mouse drag, not just when dragging a file
- **Symptom:** shaking the mouse with Button1 held opens qdrop even when
  nothing is picked up — rubber-band selecting on the desktop, panning a
  canvas, dragging a window, scrubbing a slider. The shake gesture had
  no idea whether there was anything to drop.
- **Root cause:** `qdrop_watch.py` only ever looked at pointer *motion*.
  Motion shape alone cannot distinguish "waggling a picked-up file" from
  "waggling the pointer"; the horizontal-dominance heuristic above was a
  weak stand-in that both missed real drags (any vertical shake) and let
  non-drags through (any horizontal wiggle).
- **Fix:** the shake now has a second, independent gate — an XDND drag
  must actually be in flight before a shake can fire (`dnd_payload()`).
  Every X11 drag source takes ownership of the `XdndSelection` selection
  for the exact duration of the drag and releases it on drop or cancel,
  so `XGetSelectionOwner(XdndSelection)` is a precise "is something
  picked up right now" test. If the source advertises more than three
  data types it also publishes them in the `XdndTypeList` property on
  its own window; that list is read to require file/folder/image-ish
  content (`text/uri-list`, `image/*`, the KDE/GNOME URI flavours, XDS)
  and reject a pure `text/plain`+`STRING` drag. With ≤3 types the list
  is only in the ClientMessage the drop target sees, so the property is
  absent and the drag is accepted — something *is* being carried.
  - Probed over `ctypes`+`libX11`, not GDK: `gdk_selection_owner_get()`
    only ever reports selections owned by the *calling* process, so it
    always returns NULL for another app's drag. An X error handler is
    installed because a drag source can disappear between the owner
    lookup and the property read (`BadWindow`), which would otherwise
    take the whole watcher down with Xlib's default exit-on-error.
  - Probe runs only at the moment a shake would fire (one round trip),
    never per motion event.
- **Also fixed:** reversal counting measured `MIN_SEG_PX` from the last
  turning point, so a 1px backwards tremor during a long one-way drag
  counted as a full reversal. It now measures retrace *from the furthest
  point reached in the current direction*, which absorbs tremor.
- **Result:** shakes work on any axis — left-right, up-down, diagonal —
  because the payload gate, not the motion axis, is what rejects
  non-drags. Escape hatches: `--any-drag` restores the old
  fire-on-any-shake behaviour, `--debug` logs why each gesture did or
  did not fire.

### qdrop glitches (looks like it closes and reopens) when shaken while open
- **Symptom:** shaking with qdrop already on screen makes it flicker as
  if it were closing and immediately reopening. Same for a second
  keybind press, or any repeated `qdrop --show`.
- **Root cause:** `show_animated()` had one path for "open it" and no
  concept of "it's already open". Every SHOW ran the full reveal:
  teleport the window to `-height` (fully off-screen, one frame) and
  slide it back down to the resting position. That *is* a close and a
  reopen — just a very fast one.
- **Fix:** the transition is now a state machine over
  `_visible`/`_hiding`/`_anim_busy()`:
  - open and settled → don't move at all; `present()` + restart the
    auto-hide countdown, which is the only useful half of a repeated
    SHOW.
  - open and still revealing → let the in-flight slide finish instead of
    restarting it from the top.
  - mid-close → *reverse* the slide from wherever the window currently
    is. Previously `show_animated()` returned early whenever `_hiding`
    was set, so a shake during the close animation was silently dropped
    and the window closed anyway. `toggle()` had the matching bug in
    mirror image: it checked `_visible` first and called
    `hide_animated()`, which bails while already hiding — so a toggle
    mid-close did nothing at all.
- **Related fixes found while testing this:**
  - `_slide_move()` never cancelled a previous animation. Two overlapping
    slides left two 16ms timers alive, each calling `move()` with its own
    idea of the target — they interleave and the window vibrates. Only
    one slide may now be in flight, and a cancelled slide's `on_done` is
    dropped (so a reversed close never runs the callback that would mark
    the window invisible).
  - A HIDE landing mid-reveal snapped the window down to its resting
    place and closed from *there*. Both directions now start from the
    window's real current Y, tracked in `self._y` by a `_move()` wrapper
    (`get_position()` round-trips X and lags a frame behind the `move()`
    just issued).
  - A HIDE landing inside the 20ms first-show allocation gap was ignored
    by the pending `_begin_slide()` callback, so the window slid into
    view right after being told to go away. Deferred callbacks now carry
    an `_anim_gen` stamp and bail when superseded.
  - A redirected slide scaled its duration by remaining distance, which
    could leave 3 frames — and `_slide_move` eases *out*, so frame one
    took 70% of the travel: a snap. Floored at 6 frames (96ms).
  - SHOW while `_visible` but on a *different* qtile group would have hit
    the new "already open, do nothing" early-out and never appeared,
    since qtile unmaps off-group windows without GTK updating `_visible`.
    `_sync_to_current_qtile_group()` now runs *before* that check; it
    clears `_mapped` on a cross-group move, which drops through to the
    full remap path.
- **Verification:** `qdrop_test.py` gained a 10-section animation suite
  that drives the real `show_animated`/`hide_animated`/`toggle` and their
  GLib timers with every GTK/X/qtile call stubbed, recording each
  requested Y. That makes "does it jump / replay / vibrate?" an
  assertion (monotonicity, exact endpoints, no teleport past an
  endpoint, no timer left running) rather than something judged by eye.
  Covers: plain open/close, SHOW while open, SHOW ×5, SHOW after a group
  switch, SHOW mid-reveal, SHOW mid-close, HIDE mid-reveal, HIDE in the
  first-show gap, all three toggle states, no-op/repeat commands, and a
  hammered show/hide/toggle sequence.

### qdrop opens empty the first time, shows its items only after a reopen
- **Symptom:** the first time qdrop is opened in a session it shows the
  "Drop files or text here" empty page even though items are saved.
  Close it, open it again, and everything is there.
- **Root cause:** `Gtk.Stack.set_visible_child_name()` is silently
  ignored when the target page isn't visible yet. `__init__` loads the
  saved entries and calls `_refresh()` long before anything has been
  shown, so the switch to the "items" page did nothing and the stack's
  visible child stayed NULL. The first `show_all()` then made both pages
  visible at once, and a stack with no visible child adopts the *first*
  one added — which is "empty". The second open ran `_refresh()` again,
  by which time the pages were visible and the switch finally took.
- **Fix:** `_refresh()` now calls `child.show()` on the target page
  before `set_visible_child()`. With a visible child already selected,
  the later `show_all()` has nothing to adopt and leaves it alone.
- **Verification:** `qdrop_test.py::t_window_layout` asserts the page is
  `items` straight after `__init__` and still `items` after a
  `show_all()` — reproducible without ever mapping a window.

### qdrop's width changes when you put something in it
- **Symptom:** the window is subtly wider or narrower at different
  times — after adding items, after pinning one.
- **Root cause:** the window is `set_resizable(False)`, so GTK sizes it
  to whatever its content requests, and the header requests more than
  anything else: title + stats chips + 6 buttons. The stats chips are
  rebuilt on every content change, and their width is content-dependent
  — an extra digit in a count, or the pinned chip appearing at all
  (it's only created when `n_pin > 0`). So the header's request moved,
  and the whole window moved with it.
  - The `WIN_W = 440` in the geometry hints had nothing to do with the
    real width: the header's own minimum was already ~569px. The hint
    was simply wrong, and only harmless because qtile didn't act on it.
- **Fix:** the chip strip lives in a `FixedWidth` container (a `Gtk.Bin`
  overriding `do_get_preferred_width`) that always requests `STATS_W =
  210` — sized from the measured worst case (999 items plus a pinned
  chip = 206px), so nothing clips. The header's request is now constant
  and the trailing spacer absorbs content changes instead of the window.
  `WIN_W` is 620, above the header's real 613px minimum, so the header
  no longer binds; `_lock_width()` then pins the geometry hints to the
  first actual allocation, so the hints describe the real window
  instead of a constant it may not honour.
  - A `Gtk.ScrolledWindow` with min/max content width does the same job
    in fewer lines, but its viewport re-negotiates the *height* of what
    it holds, squeezing the chip icons below their 16px minimum and
    logging GTK size warnings on every stats update.
- **Also fixed:** the pinned-item overlay icon used `margin_top = -4`,
  `margin_end = -4`. GTK3 has no CSS-style negative margins; the 16x16
  icon was asking to be allocated 20x20, which GTK refuses with
  `adjust_size_allocation must keep allocation inside original bounds`
  logged on every pin.
- **Verification:** `t_window_layout` measures the window's requested
  width across 2 entries → 22 entries (two-digit counts) → a pinned chip
  → empty, and requires all four to be identical; it also asserts the
  header minimum still fits inside `WIN_W`, so a future font or
  icon-theme change fails the suite instead of silently resizing the
  window. Confirmed on the live daemon with `xdotool getwindowgeometry`:
  622x329 across repeated shows.

### Pasting an image from a web page into qdrop stores a link instead
- **Symptom:** copy an image in the browser, `Ctrl+V` into qdrop, and
  you get a URL entry rather than the picture.
- **Root cause:** `_paste_clipboard()` only ever asked the clipboard for
  URIs and then text. Copying an image in a browser puts the *bitmap*
  on the clipboard (`image/png` and friends) together with the page URL
  as `text/plain` — so the text branch always won. Nothing in qdrop
  ever requested the image target.
- **Fix:** paste now asks for URIs → **image** → text, in that order.
  Image data is written to `~/.cache/qdrop-images/qdrop-<stamp>.png` by
  `save_pixbuf()` and added as a normal file entry, which gets it a
  thumbnail, `imv` preview and drag-out-to-another-app for free (every
  qdrop entry is a path, a URL or text — there is no in-memory blob
  entry type).
- **Same gap on the drop path, also fixed:** the drop target list was
  uri-list + text only, so an image dragged off a web page arrived as
  the page URL. `image/png`/`jpeg`/`bmp` are now listed *first*, so GTK
  prefers the bitmap over the URL.
- **Also fixed:** a drop whose uri-list held an `http(s)` URI (common
  when dragging straight off a page) was skipped outright by the
  `uri_to_path()` check — the drop silently did nothing at all. Remote
  URIs are now kept as URL entries.
- **Housekeeping:** `prune_image_cache()` runs at daemon start and
  deletes saved images that no entry references *and* that are older
  than 30 days. `remove_entry()` deliberately does not delete the file —
  it may have been dragged somewhere else since.
- **Verification:** `qdrop_test.py::t_image_paste_drop` covers
  `save_pixbuf` (including two saves in the same second), paste of an
  image, paste of text-only (still a URL entry), drop of raw image data,
  drop of a remote URI, drop of a local file, and the three prune cases.
  It drives a private selection atom rather than the real clipboard, so
  running the suite doesn't clobber what you have copied. Additionally
  confirmed against a genuine cross-process X selection owned by another
  GTK process (the in-process clipboard path is short-circuited by GTK
  and so proves less): qdrop negotiated `image/png` off it, wrote the
  file, and it decoded back at the right dimensions.

### SmartWidgetBox chip-list cascade-flash animation (CPU/Mem, updates/disk/volume groups)
- **Symptom:** N/A — this documents verification of an animation added
  in the same pass as the qdrop fixes above, not a bug.
- **What it does:** `SmartWidgetBox._animate_reveal()` staggers a
  brief brighten-then-fade flash (`i * 0.07s` stagger, `0.18s` flash)
  across each child widget's `_flash_deco` when the box opens, so the
  revealed chips (e.g. CPU/Memory under the `system_widgetbox` toggle,
  or updates/disk/volume under `2nd_system_widgetbox`) read as popping
  in one after another instead of appearing all at once.
- **Verification:** confirmed via `qtile cmd-obj -o bar top -f info`
  (ground truth for what's actually in `bar.widgets`, far more reliable
  than reading rendered glyphs off a screenshot) that clicking the
  toggle correctly inserts/removes the real child widgets with live
  content. The flash itself was confirmed via a timestamped screenshot
  burst: frames taken while a child's flash window is still active show
  a visibly lighter pill background than frames taken after its revert
  fires, at the expected timing boundary. No errors in
  `~/.local/share/qtile/qtile.log` across repeated open/close cycles.

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
- **SUPERSEDED — the tap-Caps fallback was dropped on purpose.** The
  current `.Xmodmap` (and `step_xmodmap`) is back to a bare
  `keycode 66 = Alt_L`, and nothing starts `xcape` any more — it is not
  in `.xinitrc` and not in `autostart.sh`. Reason: with Alt dead in
  hardware, Caps is the *only* working Alt, and a tap-to-Caps-Lock
  fallback on the modifier you press hundreds of times an hour fires by
  accident far more often than it is wanted. There is now no way to
  toggle Caps Lock from the keyboard, which is the intended trade.
  The `xcape` package is still declared in `system-tools.yaml` but is
  vestigial. Keep this entry: if anyone re-adds the fallback, the
  `keycode 66 = Alt_L Caps_Lock Alt_L Caps_Lock` line above is the fix
  they will need again.

### `adhkar` reminders behave oddly / bash-isms silently misfire
- **Symptom:** the `adhkar` notifier autostarted by `autostart.sh` runs,
  but anything bash-specific in it is unreliable. No error is printed
  anywhere you would look.
- **Root cause:** the file began with a **blank line before `#!/bin/bash`**.
  A shebang is only honoured on byte 0 of the file; with a leading
  newline the kernel returns `ENOEXEC`, and the parent shell falls back
  to running the script with `/bin/sh`. So it was being interpreted by
  `sh`, not `bash`, despite the shebang sitting right there in line 2.
- **Fix:** removed the leading blank line. `shellcheck` catches this as
  `SC1128` — it is worth running across the tree after bulk edits:
  ```sh
  git ls-files -z | xargs -0 grep -lI '^#!.*bash' | xargs shellcheck -S error
  ```

### Login runs a "command not found" in the background on every session
- **Symptom:** nothing visibly wrong, but `autostart.sh` was spawning
  `pamac-tray-icon-plasma &` on every login and it always failed.
- **Root cause:** `pamac-tray-icon-plasma` is a **Manjaro** package. It
  has never been installed on this Arch box and is not declared in
  `arch-config`. It was the update notifier back when this config was
  first adapted, and survived the move. Because it was backgrounded with
  `&`, the failure went to a stderr nobody reads and never affected exit
  status.
- **Fix:** removed. The update notifier is now `qupdate.py --daemon`,
  started in the qtile-owned block further down the same file.
- **General lesson:** an unguarded command in `autostart.sh` fails
  silently. Anything optional belongs behind
  `command -v <cmd> >/dev/null && <cmd> &`, which is the pattern the rest
  of that file already uses.

### Qtile RAM climbs every time a popup is opened and closed
- **Symptom:** memory used by the qtile process only ever goes up. Opening
  and closing the wallpaper picker or a cheatsheet ten times costs tens of
  MB that never comes back. Nothing looks wrong on screen.
- **Root cause:** the popups closed with `layout.hide()`. `hide()` only
  **unmaps the X window** — the window, its cairo drawer and every
  control's pango layout stay allocated. Every `show_*` path in this repo
  builds a **brand new** `PopupRelativeLayout`, so the old one is
  orphaned, not reused: ~3MB of ARGB surface per wallpaper-picker close
  (1120×680), ~2.7MB per cheatsheet, ~2.2MB per WiFi/Bluetooth close.
  It was measured as five live 940×600 popups in one running qtile.
- **Fix:** `layout.kill()` on every teardown path. `apply_wallpaper()`
  already did this on its own exit; the rest now match.
- **Rule of thumb:** `hide()` is only correct when the *same* layout
  object is shown again later. If the show path constructs a new layout,
  the close path must `kill()`.

### Entries at the bottom of a cheatsheet column are missing, and nothing errors
- **Symptom:** a cheatsheet popup is missing the last few entries of its
  longest section. No exception, no log line — the entries are right there
  in `CHEATSHEET`, they just are not on screen. Adding one more makes a
  different one disappear.
- **Root cause:** `PopupText` **neither clips nor wraps to its `height`.**
  The `height` you pass only positions the control; text longer than that
  keeps drawing downward, over whatever is below it, until the popup
  *window* edge cuts it off. All three cheatsheets carried the same
  copy-pasted 4×3 grid of equal `0.25`-height cells, and every section in
  every one of them overflowed its cell. Where there was empty space
  below, the overflow was invisible; where there was not, the window
  cropped it:
  - **Qtile** — the ROFI MODE column ended **101px below the bottom
    edge**; its last four entries had never rendered.
  - **Vim** — `Screenshots` and `Exit / Save` lost 28px each, `Markdown`
    4px, and `LSP` ran into the footer.
  - **Fish** — `Danger Zone` ran 32px past the footer.

  Every column in Vim and Fish was also ~40px wider than its cell, so all
  of them wrapped as well, which made them taller still.
- **Fix:** `popups/_cheatsheet_grid.py` — one shared layout module, since
  the copy-paste is what let one bug become three. Cards stack top to
  bottom, each placed at the height the ones above it actually need, and
  a column is closed when the next section will not fit. Sections are
  placed **first fit** rather than strictly in sequence: filling one
  column at a time left a card-sized hole under any section that missed
  the bottom of its column by a few pixels.
- **Sizes are exact, not estimated.** The face is monospace, so a card is
  `(2 + rows) × LINE_PX` tall and `(2 + cols) × CHAR_PX` wide and that is
  the end of it. `LINE_PX` / `CHAR_PX` are pango extents at `BODY_SIZE`,
  so **changing `BODY_SIZE` without re-measuring them invalidates every
  position.** It is also why `font=` and `fontsize=` are passed explicitly
  to every `PopupText` — inheriting the defaults would do exactly that.
- **When there is genuinely too much, it paginates.** 90 qtile bindings do
  not fit one 1366×768 screen at a readable size, and the old answer to
  that was a 9pt sheet with its bottom rows off the edge. `Tab` inside
  `Mod+Shift+K` turns the page.
- **Check a change without a running qtile** — this is what `validate.sh`
  runs, and it names the card and the fix:
  ```sh
  cd ~/.config/qtile && python3 -m popups._cheatsheet_grid
  ```
  It fails on four separate things, all of which have actually happened:
  text wider or taller than its card, a card past the footer or the popup
  edge, a **row clipped** (`z 'file/folderna…` is not a thing you can
  type), and a **glyph the font does not have**.

### Cheatsheet columns do not line up / the popups render in a CJK face
- **Symptom:** the key column in a cheatsheet is ragged instead of flush
  right, or the whole popup renders in a font that is visibly not the one
  the rest of the desktop uses.
- **Root cause:** `PopupText`'s default font is **`sans`**, and on this
  machine `fc-match sans` answers **Noto Sans CJK KR**. Same trap as
  242b8ff, which fixed it for rofi and not for these. It is also
  proportional, so no amount of space-padding will align a column in it.
- **Fix:** every cheatsheet control names `_cheatsheet_grid.FONT`
  (`JetBrainsMono Nerd Font`) explicitly. The right-aligned key column
  only works because every glyph is exactly `CHAR_PX` wide.
- **A missing *glyph* has the same effect as a missing font**, and is
  harder to spot: pango silently falls back for that one character, at
  that other font's width, and the row it is in stops lining up. `↵`
  (U+21B5) is the obvious symbol for Enter and **is not in
  JetBrainsMono**; `⏎` (U+23CE) is. The selftest checks every glyph the
  popups draw — headers and footers included, which is where a hardcoded
  `↵` slipped past a cards-only version of the check.
  ```sh
  fc-match "JetBrainsMono Nerd Font"      # is the family even installed
  ```

### Popup labels are washed out / unreadable on some themes
- **Symptom:** on nord, rose-pine and the other presets, the `muted`
  labels inside a popup card are barely legible, and one accent (nord's
  red, rose-pine's green) sits at roughly the same brightness as the card
  behind it. The same colours are perfectly readable in the terminal.
- **Root cause:** the shared loader derives `muted` against `bg`, but the
  popups paint text on `surface` — a card blended 7% of the way toward
  `fg`. That is enough to drop those colours under a 3:1 contrast ratio
  against what they are actually drawn on. Themes are chosen for how they
  look in a terminal, where text sits on `bg`.
- **Fix:** `ensure_contrast()` in `popups/_wal_colors.py`. It nudges a
  colour toward the palette's **foreground** until it clears the ratio,
  and returns it untouched when it already passes — so themes with
  healthy contrast keep their exact accents. Mixing toward `fg` always
  moves *away* from the surface, which is why it works unchanged on light
  presets (mono-light) as well as dark ones.
- **Do not apply it to block fills.** `highlight_bg` is the selection
  block, not text; adjusting it would drift the theme's accent for no
  gain.

---

## Network & Bluetooth

### Fresh install: WiFi/Bluetooth popups say the daemon is not running
- **Symptom:** on a machine installed from this repo, `Mod+P` then `n`
  or `b` opens the popup and immediately errors — `NetworkManager is not
  running`, or an empty Bluetooth list that never fills. `nm-applet` and
  `blueman-applet` are visible in the tray and do nothing. On the machine
  this repo was developed on, everything works.
- **Root cause:** **declaring a package installs a binary, not a running
  daemon.** `networkmanager` and `bluez` are declared (network.yaml) and
  dcli installs them, but nothing enabled the units. They are enabled on
  the development machine only because **archinstall** did it — which is
  exactly the kind of difference a package audit cannot see.
- **Fix:** the wizard's `radios` module (`step_radios`, runs after
  `dcli-sync`) enables `NetworkManager.service` and `bluetooth.service`.
  Idempotent — prints "already enabled" and changes nothing on a
  configured machine.
  ```sh
  ./wizard.sh --yes --only=radios       # on an already-installed box
  systemctl is-enabled NetworkManager.service bluetooth.service
  ```
- **Its uninstaller is a deliberate no-op.** Disabling NetworkManager to
  "reverse" an install leaves a machine with no network and no GUI to fix
  it with. Turn either off by hand, or with `service_trim.sh`.
- **Watch out for `service_trim.sh`.** It offers to disable
  `bluetooth.service`; say yes and the `Mod+P b` picker goes dead with no
  other symptom.

### Typing a WiFi password pops nm-applet's own GTK dialog on top of the popup
- **Symptom:** the WiFi popup asks for a password via rofi, you get it
  wrong, and a **second** password prompt appears — a GTK one, from
  nm-applet, stealing focus over a popup that is mid-flow.
- **Root cause:** `nm-applet` registers itself as NetworkManager's
  **secret agent** by default. When `nmcli` fails to authenticate, NM asks
  the registered agent for the secret, and the agent is a GUI dialog.
- **Fix:** `nm-applet --no-agent` in both start paths
  (`.config/qtile/autostart.sh` and the `.xinitrc` the wizard writes). It
  keeps the tray icon and drops the secret-agent role, so the popup owns
  the whole flow and re-asks itself.

### A network stays marked "saved" with a password that can never work
- **Symptom:** you fat-finger a PSK, the connect fails, and the network
  now shows as saved. Pressing Enter on it fails instantly forever. Retry
  a few times and `nmcli connection show` has `SSID`, `SSID 1`, `SSID 2`
  sitting beside each other.
- **Root cause:** `nmcli dev wifi connect <ssid> password <psk>` **writes
  the profile before it knows the key is rejected**, and adds a new one
  (suffixed) on each attempt rather than correcting the existing one.
- **Fix:** `connect()` in `popups/WifiPopup.py` re-keys the existing
  profile (`connection modify … wifi-sec.psk`) instead of adding beside
  it, deletes anything an attempt saved that was not there before, and
  re-asks up to `MAX_PASSWORD_TRIES` with the try count in the footer.
  `connect_hidden()` has the same trap and the same cleanup.
- **Clean up profiles left by an older build:**
  ```sh
  nmcli -t -f NAME connection show | grep -E ' [0-9]+$'
  nmcli connection delete id 'SSID 1'
  ```

### Connecting to an out-of-range network or device hangs forever
- **Symptom:** the busy bar spins and never stops. Escape closes the
  popup but the worker is still running; the status is stuck on
  "Connecting…" the next time it opens.
- **Root cause:** two separate ones with the same shape.
  `bluetoothctl connect <mac>` against a device that is out of range
  **never returns** — no timeout of its own, no error. `nmcli` can sit for
  a long time on a marginal AP.
- **Fix:** every command carries a timeout and is killed when it expires,
  and the handle of whatever slow action is in flight is published so `c`
  can kill it by hand. In WiFi that offer is advertised **in the footer
  while busy**, not as a permanent hint chip — that bar is already at
  808px of its 874px.

### Bluetooth list fills up, then empties itself a few seconds later
- **Symptom:** scan finds devices, they render, and then most of them
  vanish while the popup is still open.
- **Root cause:** **bluez forgets unpaired devices as soon as discovery
  stops.** A scan-then-list design therefore shows a list with a
  half-life.
- **Fix:** discovery runs as a child process for as long as the popup is
  open, and is killed on close — including from `cleanup_on_leave()`, so
  leaving the chord with Escape stops it too. Without that path the radio
  keeps discovering forever after the popup is gone.
- **Related bluez traps in the same file:** `bluetoothctl devices` embeds
  **ANSI colour escapes even when its output is piped** (every line is
  stripped before parsing), and `info <mac>` costs one process per
  device — so the list is built from the four cheap
  `devices [Paired|Connected|Trusted]` queries and `info` is only asked
  for the paired rows and the selected one.

### The QR code from the WiFi popup will not scan
- **Symptom:** `s` on a saved network draws a code, and the phone camera
  ignores it.
- **Root cause:** almost always one of two things. **Inverted codes**
  (light modules on a dark background) are out of spec and plenty of
  cameras refuse them — which is why the code is rendered black on white
  on its own white card whatever the desktop theme is. **Fractional
  scaling** blurs the module edges the decoder needs, which is why
  `qrencode` is run twice: once at one pixel per module to learn the
  symbol size, then again at an integer scale that fills the card.
- **If it draws "qrencode not found"** the package is missing —
  `qrencode`, declared in `modules/wm.yaml`.
- **If it says the network is not saved**, there is no stored PSK to
  encode. Connect to it once first.

---

## Voice dictation

### Mic sounds/transcribes like distorted noise, or dictation randomly gets much worse than a previous session
- **Symptom:** `voice_dictate`/`voice_dictate_live` transcribe garbage, or
  transcription quality visibly regresses between sessions with nothing
  else changed. A raw capture (`arecord -f S16_LE -r 48000 -c 2 test.wav`,
  played back or checked with `sox test.wav -n stat`) shows amplitude
  pinned near ±1.0 and a mean/midline far from 0 instead of near-silent
  ambient noise.
- **Root cause:** two ALSA mixer controls stack for the internal mic —
  `Capture` (0-63) and `Internal Mic Boost` (0-3) — and both defaulting
  to 100% is ~60dB of combined gain, enough to saturate/clip the signal
  into constant distorted noise even in a quiet room. `alsactl store`
  alone doesn't make a fix stick: **WirePlumber** (the PipeWire session
  manager) applies its own default ALSA levels to hardware nodes on every
  session start, silently overriding whatever `alsactl restore` set
  moments earlier.
- **Fix:** `amixer -c 0 sset 'Internal Mic Boost' 0` and
  `amixer -c 0 sset Capture 75%`, then make it durable —
  `fix-mic-gain.service` (`.config/systemd/user/`, `After=wireplumber.service`,
  waits 3s for WirePlumber's own init before reasserting) covers this;
  the wizard's `mic-gain` module enables it. If dictation quality
  regresses again after a fresh install/reboot, check
  `systemctl --user is-enabled fix-mic-gain.service` first before
  suspecting anything else.
- **Verification methodology trap:** testing capture level with
  `timeout N arecord ... ; sox file -n stat` gave wildly wrong readings
  (amplitude pinned, huge DC offset) even on a properly-configured mic —
  `timeout`'s SIGTERM can cut `arecord` off before it finalizes the WAV
  header, corrupting the read. Use `arecord ... & PID=$!; sleep N;
  kill -INT "$PID"; wait "$PID"` instead — SIGINT gives it a chance to
  close the file properly.

### `voice_dictate` (batch dictation) or any `whisper-cli` call feels much slower than it should
- **Symptom:** transcribing even a few seconds of audio takes 10+
  seconds. `whisper-cli ... 2>&1 | grep 'encode time'` shows several
  seconds to tens of seconds for a short clip.
- **Root cause:** the `whisper.cpp-git` AUR package's `PKGBUILD` builds
  with `-D CMAKE_BUILD_TYPE=None` — no optimization flags at all, no
  `-march=native`. Measured on one machine: 28s to encode 2s of audio
  with the pacman-built `whisper-cli`, vs 2.1s with a `Release` build of
  the identical source/model — a ~13x slowdown, present in every binary
  the package ships (`whisper-cli`, `whisper-server`, ...). It also
  doesn't build `whisper-stream` at all (needs `-DWHISPER_SDL2=ON`,
  which the `PKGBUILD` doesn't pass), which `voice_dictate_live` depends
  on.
- **Fix:** the wizard's `whisper-fast` module builds Release binaries
  from the same AUR-cached source and shadows the slow system ones via
  `/usr/local/bin` (already earlier in `$PATH`) + `/usr/local/lib/whisper-cpp`
  (registered through `/etc/ld.so.conf.d`, so they keep working even if
  the yay build cache is later cleared). Full writeup + manual steps:
  `.config/AtiScriptsV1/patches/README.md`.
- **Verify it actually took:** `ldd $(which whisper-cli)` should resolve
  to `/usr/local/lib/whisper-cpp/*`, not `/usr/lib/*`.

### `voice_dictate_live` (live dictation) prints/types things you never said
- **Symptom:** repeated phrases ("I'm sorry about the other one." several
  times in a row), stray `[BLANK_AUDIO]`/`[inaudible]`/`*singing*` tags,
  or a whole sentence duplicated back-to-back.
- **Root cause:** `whisper-stream`'s `--step 0` (VAD sliding-window) mode
  is upstream-documented as "a very naive example" — it never clears its
  audio ring buffer, so every brief pause re-transcribes the whole
  recording so far (or a slid window once you've talked past `--length`)
  and prints that as a new block; greedy decoding on longer/messier audio
  is also prone to genuine repetition-loop hallucinations. Typing each
  block verbatim (the obvious approach) surfaces all of this directly.
- **Fix:** already handled by `voice_dictate_live_typer.py` (word-level
  append-only diffing against the previous block, bracket/asterisk tag
  stripping, a repetition-loop collapse pass, `-bs 3` beam search instead
  of greedy decoding) — nothing to do unless a *new* shape of this shows
  up. If one does: paste the exact broken output and trace which specific
  mechanism produced it (growing/sliding merge, tail revision, decoder
  loop, hallucinated filler are the ones covered so far) — treat it as a
  new, specific case rather than assuming it's already covered.

---

## Testing on a fresh Arch VM

`installScripts/vm-test.sh` automates the setup around this:

```bash
./vm-test.sh --check    # preflight only, creates nothing — run this first
./vm-test.sh --smoke    # ~2 min headless boot: proves qemu/KVM/ISO/disk work
./vm-test.sh            # preflight, fetch + verify ISO, make disk, boot
./vm-test.sh --clean    # delete the VM disk and ISO
```

`--smoke` is the cheap confidence check. It boots the ISO headless with a
2 GB guest and a 240s cap, captures the whole boot over a serial console,
and asserts the VM reached the network target and `archiso login:`. Two
minutes to learn that qemu, KVM, the ISO and the disk are all sound,
before committing to a multi-hour install. It asserts on the boot log
rather than qemu's exit status, because the guest sits at the login
prompt forever and `timeout` always kills it.

To capture serial output it boots the ISO's kernel directly
(`-kernel`/`-initrd`) so `console=ttyS0` can be appended — booting the
cdrom normally produces nothing to assert on. The `archisolabel` is read
off the ISO with `blkid` rather than hardcoded: it carries the release
date (`ARCH_YYYYMM`) and changes monthly.

`--smoke` vets its own 2 GB guest, not the 4 GB install budget. Demanding
the full budget made it unrunnable on exactly the hosts it exists to
help. Override the install size with `VM_RAM_MB=3072 ./vm-test.sh` on a
tight machine.

The preflight is the part worth having. It refuses with the specific
number that failed — qemu missing, `/dev/kvm` not writable, not enough
`MemAvailable` for a 4 GB guest plus host headroom, not enough disk —
rather than letting you discover it at module 21 of 32 with a 500 MB
download in flight. On an 8 GB laptop with a browser open it will (and
should) tell you to come back when the machine is idle.

It deliberately does **not** automate `archinstall`: that step is
interactive by design, and a script that silently picks the wrong disk on
a two-disk machine is worse than no script. Everything either side of it
is automated. It boots UEFI when `edk2-ovmf` is present, and says so when
it cannot — on a BIOS guest the `boot-fallback` module is untestable,
because systemd-boot entries are the whole point of it.

The manual path below is what the script does, if you would rather drive
it yourself:

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
Wizard prints the green-bordered "Installation Complete · ✔ 32 ok · ⚠ 0
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

### New wizard module silently never runs (`_reg` is not enough)
- **Symptom:** you add `_reg <id> ... "step_<id>"`, `bash -n` passes, the
  function is obviously defined — and the module simply never appears in
  the picker or the run. No error, no warning, nothing to grep for.
- **Root cause:** `_reg()` only populates the `MOD_TITLE` / `MOD_GROUP` /
  `MOD_DESC` / `MOD_CMD` lookup maps. What the wizard actually *iterates*
  is the hand-maintained `MOD_ORDER=( ... )` array just above the `_reg`
  block. An id missing from `MOD_ORDER` is invisible: `--yes` does
  `PICKED_IDS=("${MOD_ORDER[@]}")`, and the picker builds its options from
  the same array.
- **Uninstall is a third, separate registry.** Defining
  `uninstall_<name>()` does nothing on its own — there is no
  dash-to-underscore auto-dispatch. You must also add
  `UMOD_CMD[<id>]="uninstall_<name>"` to the explicit table.
- **So adding one module means editing four places:**
  1. `MOD_ORDER` — position determines run order (e.g. anything needing
     fish/packages must come after `dcli-sync`)
  2. `_reg <id> "<title>" <group> "<desc>" "step_<name>"`
  3. `step_<name>() { ... }`
  4. `UMOD_CMD[<id>]="uninstall_<name>"` + the `uninstall_<name>()` body
- **Verify both directions before committing** — the dry-runs are cheap
  and would have caught this immediately:
  ```sh
  ./wizard.sh --dry-run --yes           | grep -i '<your module title>'
  ./wizard.sh --uninstall --dry-run --yes | grep -i '<your module title>'
  ```
  Also confirm the step is *idempotent*: re-running the wizard on a
  configured machine must print "already …" and change nothing.
- **Step 4 is now enforced at startup.** The wizard checks every
  `MOD_ORDER` id has a `UMOD_CMD` entry and exits 2 with
  `BUG: module(s) with no uninstaller: <ids>` before doing any work.
  It used to be discovered mid-uninstall — see the next entry.
- **There is no longer a fifth place.** `--help` used to carry a
  hand-typed copy of the module id list; it is now generated from
  `MOD_ORDER` at runtime and cannot drift.

### `--uninstall` aborts ~90% through with `UMOD_CMD[$id]: unbound variable`
- **Symptom:** `./wizard.sh --uninstall` reverses 28 modules, then dies:
  `wizard.sh: line 1173: UMOD_CMD[$id]: unbound variable`. Exit is
  non-zero, no summary card, and the last four modules are never
  reversed — so the machine is left in a half-uninstalled state that
  neither a re-run nor a re-install obviously repairs.
- **Root cause:** `dark-mode` and `browser-memory` were added to
  `MOD_ORDER` and `_reg` when they shipped, but no `UMOD_CMD` entry and
  no `uninstall_*` body were written for them. Install mode never touches
  `UMOD_CMD`, so all the install dry-runs passed and the gap sat there
  unnoticed. Under `set -u` the first missing key is a hard crash, and it
  lands at the *worst* moment: after the reversals that already ran.
- **Why it hid for so long:** `--uninstall` is the one path nobody runs
  on a working machine. `./wizard.sh --yes --dry-run` exercised 32/32
  modules and reported success the entire time.
- **Fix:** added `uninstall_dark_mode` (`gsettings reset` — back to "no
  preference", not a forced light theme, which would be a different
  opinion rather than a reversal) and `uninstall_browser_memory`
  (removes only our `50-memory-saver.json`, never the shared
  `policies/managed/` directories). Plus the startup guard above, so the
  next module that forgets an uninstaller fails in the first second
  instead of at 90%.
- **Regression test:** `./wizard.sh --uninstall --yes --dry-run` must end
  on `✔ 32 ok   ⚠ 0 not run   ✖ 0 failed`. Run it whenever you touch
  `MOD_ORDER`.

### `--only=pacman-guard` on a fresh box breaks every pacman transaction
- **Symptom:** after running just the `pacman-guard` module, *every*
  `pacman`, `yay`, `paru` and `dcli` operation aborts before it starts.
  Including the one that would install the fix.
- **Root cause:** `00-preflight.hook` is `AbortOnFail` and its `Exec=`
  points at `/usr/local/bin/pacman-preflight`, which is symlinked into
  place by a *different* module (`ati-scripts`). A missing `Exec=` target
  is a hook failure, and a failing `AbortOnFail` PreTransaction hook
  cancels the transaction. A full `./install.sh` is safe because
  `ati-scripts` runs first, but a targeted `--only` run was not.
- **Fix:** `step_pacman_guard` now **refuses** — it checks for an
  executable `/usr/local/bin/pacman-preflight` and returns 1 with
  instructions before installing the hook, rather than warning and
  installing it anyway. A warning is the wrong severity when the failure
  mode locks you out of the package manager.
- **If you already hit it:** `sudo rm /etc/pacman.d/hooks/00-preflight.hook`
  restores pacman, then re-run
  `./wizard.sh --yes --only=ati-scripts,pacman-guard` in that order.

### `--help` claims a module id is invalid when it works fine
- **Symptom:** `./wizard.sh --help` does not list `dark-mode` or
  `browser-memory`, but `--only=dark-mode` runs correctly.
- **Root cause:** the id list in the help heredoc was a hand-maintained
  copy of `MOD_ORDER` and had not been updated when those two modules
  landed. It also printed a stray `set -Eeuo pipefail` line, because the
  header was extracted with a fixed `sed -n '2,15p'` range that had
  drifted past the end of the comment block.
- **Fix:** `--help` is deferred until after `MOD_ORDER` is defined and now
  prints the array itself, with a count. It cannot go stale again.

### Per-module logs would have all collapsed into one `/tmp/wizard-.log`
- **Symptom:** latent, not live — the filenames were correct on this
  machine, by luck.
- **Root cause:** `local id="$1" logf="/tmp/wizard-$id.log"` does **not**
  let `logf` see the `id` assigned beside it. Bash expands the whole
  `local` line against the *enclosing* scope first:
  ```sh
  f(){ local id="$1" logf="/tmp/wizard-$id.log"; echo "$logf"; }
  f mymodule    # → /tmp/wizard-.log
  ```
  It produced correct names only because `page_execute`'s `for id in
  "${PICKED_IDS[@]}"` loop variable was not `local`, so the caller's value
  leaked in and happened to be the right one. Scope that loop variable —
  an obvious tidy-up — and every module's log silently collapses into one
  file while the UI keeps telling you to `tail /tmp/wizard-<id>.err`.
- **Fix:** split into two statements (`local id="$1"` then `local logf=…`)
  in both `_run_module` and `_show_error_tail`, and made `page_execute`'s
  `id` local so nothing depends on the leak any more. Verified: a run of
  `--only=sanity,touchpad,lid` produces three separate
  `/tmp/wizard-<id>.log` files and no `/tmp/wizard-.log`.
- **shellcheck catches this as SC2318** — it is why the sweep was worth
  running past error level.

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

### Packages the desktop needs that were never actually declared
- **Symptom:** none on this machine — which is the point. They were
  present only as *transitive dependencies* of something else, so a
  fresh install happened to work and nothing ever flagged them.
- **How to find them:** resolve every binary the configs invoke back to
  its owning package, then diff against the declared set:
  ```sh
  # for each command referenced in .config/ and installScripts/
  pacman -Qoq "$(command -v <cmd>)"
  # ...and check it appears under .config/arch-config/modules/
  ```
- **`qtile` itself was not declared.** It was installed only because
  `qtile-extras` depends on it. That dependency is entirely upstream's
  to change; if it were ever relaxed, `dcli sync` would have had no
  reason to keep the window manager installed. Now declared explicitly
  in `wm.yaml`.
- **`xorg-xsetroot` was missing outright.** `.xinitrc` sets the root
  cursor with `command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name
  left_ptr`. The guard meant no error — the cursor just silently stayed
  the default X11 "X" over the root window on a fresh install. Now
  declared in `xorg.yaml`.
- **Deliberately left undeclared:** `xsel` (only a third-tier clipboard
  fallback behind `wl-clipboard` and `xclip`, both declared) and
  `sqlite` (guaranteed by half the declared graphical stack). Guarded
  optional fallbacks do not need declaring; unguarded calls do.

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

## Session startup (TTY → X)

Everything here is about the wall of text `letsgo` prints between the TTY
and qtile appearing. One line of it was a real error; the rest is noise
that looks alarming and is not. They are grouped so you can match what is
on screen against what matters.

### Legacy: AT-SPI environment variables in `/etc/environment`
- **Context:** older revisions of this repo's README told you to add these
  to `/etc/environment` so GTK and Qt apps would expose their widget tree
  over AT-SPI:
  ```bash
  ACCESSIBILITY_ENABLED=1
  GTK_MODULES=gail:atk-bridge
  OOO_FORCE_DESKTOP=gnome
  GNOME_ACCESSIBILITY=1
  QT_ACCESSIBILITY=1
  QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
  ```
  (The old instructions had a typo — `sudo vim /etc/enviromen`. Use
  `sudoedit /etc/environment`.)
- **Status:** not set by the wizard, and not required for what most people
  want AT-SPI for here. homerow hints **browser** content via
  `--force-renderer-accessibility` in `brave-flags.conf`, which is a
  per-browser flag and needs none of the above.
- **When you still want them:** if you want homerow to hint native GTK/Qt
  applications rather than just web pages. They are a system-wide
  behaviour change with a memory cost in every toolkit app, which is why
  they are opt-in rather than part of `install.sh`.
- **Recorded here because the README that documented them was rewritten**,
  and `main` was the last place they survived. Their absence from the
  current README is not evidence they never mattered.
- See also `.config/espanso/Readme.md`, which needs its own (unrelated)
  set of `/etc/environment` entries.

### `xauth: (stdin):2: unknown command "<32 hex chars>"` right after `letsgo`
- **Symptom:** the very first line after `letsgo`, before the Xorg banner.
  X still starts and the session is fine.
- **Root cause:** duplicate cookies in `~/.Xauthority`. Every unclean X
  exit leaves its `MIT-MAGIC-COOKIE-1` entry behind and startx adds a
  fresh one on top, so entries for this display accumulate — `xauth list`
  showed three for `Ati:0` here. startx then does:
  ```sh
  authcookie=$(xauth list "$displayname" | sed -n '...')
  "$xauth" -q -f "$xserverauthfile" << EOF
  add :$dummy . $authcookie
  EOF
  ```
  With more than one entry `$authcookie` is multi-line, so the second and
  third cookies land on their own lines *inside the here-doc*, where xauth
  reads them as commands. Hence "unknown command", and hence the line
  number: `(stdin):2` is literally the second line of that here-doc.
- **Fix:** `letsgo` now clears stale entries before calling startx, the
  same way it already cleared a stale `/tmp/.X0-lock`. It is safe there
  because `letsgo` has already established that Xorg is not running, so
  nothing needs the old cookies and startx writes exactly one.
- **To clear it by hand** (only with X *not* running — removing the live
  display's cookie stops new clients connecting):
  ```sh
  xauth remove :0 "$(uname -n):0" "$(uname -n)/unix:0"
  ```
  `uname -n`, not `hostname`: `hostname` lives in `inetutils`, which is
  not installed here.

### `WARNING:libqtile:Key spec duplicated, overriding previous: <Key ([], Escape)>`
- **Symptom:** two of these on every qtile start and every reload.
- **Root cause:** self-inflicted, and previously on purpose.
  `KeyChord.__init__` appends its own bare `Key([], "Escape")` to every
  chord's submappings. It lands last, so `grab_chord()` grabs it last and
  it overwrote ours in `keys_map` — leaving Escape with zero commands,
  which is why the passthrough confirm popup never opened. The original
  fix appended a *second* Escape on top so ours was grabbed last. That
  worked, but left two specs, and qtile logs a warning per chord.
- **Fix:** `_set_chord_escape()` now strips qtile's auto-added Escape
  first and then appends ours. Same "ours is last" guarantee, exactly one
  spec, no warning. Verified against the real `libqtile.config` classes:
  one Escape, it is the last submapping, it carries a command, and
  re-applying it (as a reload does) stays at one.
- **Do not "fix" this by simply deleting the append.** That restores the
  original bug — Escape ends up with no commands and the confirm popup
  silently stops working.

### Bar fails to draw: `AttributeError: TextBox has no attribute: length`
- **Symptom:** intermittent. The bar does not render at all on some
  starts — 6 of 47 in one sample — and `qtile.log` shows:
  ```
  bar.py:440 in _resize -> sum(w.length for w in widgets ...)
  AttributeError: TextBox has no attribute: length
  ```
- **Root cause, and why the message lies.** `Bar._resize()` sums `length`
  over *every* widget, so one bad widget aborts the whole draw. Upstream
  `_Widget.length` looks like it is already guarded, but the `try` only
  wraps `calculate_length()`:
  ```python
  @property
  def length(self):
      if self.length_type == bar.CALCULATED:      # ← outside the try
          try:
              return int(self.calculate_length())
          except Exception:
              logger.exception(f"... widget {self.name} length")   # ← self.name!
              return 0
      return self._length                          # ← outside the try
  ```
  On a widget that has not been `_configure()`d, `self.bar` is missing, so
  `calculate_length()` raises — then the handler formats `self.name`,
  which is *also* missing, and that AttributeError escapes the property.
  An AttributeError escaping a property makes Python fall back to
  `Configurable.__getattr__`, which reports the **property** as missing.
  Hence "has no attribute: length" when `length` plainly exists, and the
  real culprit (`bar`, `name`) never appears in the message.
- **Why `_SafeLengthMixin` did not cover it:** that mixin only applies to
  chips built through `_derive()`. The bar also holds plain
  `widget.TextBox` (8 of them), Spacer and Systray instances.
- **Fix:** `_guard_widget_length()` wraps `_Widget.length` itself, so
  every widget degrades to 0 width instead of killing the draw. It logs
  with `type(self).__name__` rather than `self.name`, since `self.name` is
  one of the attributes that can be missing. It is idempotent — a config
  reload re-imports the module, and without the `_length_guarded` flag
  each reload would wrap the previous wrapper.
- **Verified** against real libqtile with a deliberately half-built
  widget: before, `sum(w.length ...)` aborts; after, it returns 0 and the
  bar draws. The setter still works (`_Widget.__init__` assigns
  `self.length`), and healthy widgets are unaffected.
- **This is a symptom, not the disease.** An unconfigured widget should
  not reach `bar.widgets` at all — see the orphan widget-tree cleanup and
  the SmartWidgetBox guards. The guard just means a mistake costs you one
  chip instead of the entire bar.

### What qtile.log looks like on a clean restart
After `Mod+Shift+R`, `~/.local/share/qtile/qtile.log` should contain
**zero ERROR lines** and only these warnings. Anything else is new.

- `Restarting Qtile with os.execv(...)` and `Starting Qtile 0.36.0 from …`
  — qtile's own lifecycle messages. It logs them at warning level itself;
  they mean the restart worked.
- `No icon found for application "" (None) switch to text mode` ×5 —
  one per `widget.LaunchBar` entry. The `progs` list uses Nerd Font glyphs
  as the icon field, so libqtile's `setup_images()` looks for an icon file
  by that name, does not find one, and falls back to drawing it as text.
  Text *is* the intended rendering — the glyph is the icon. Unavoidable
  with `LaunchBar` short of shipping real icon files, and harmless.
- `[tooltips] installed=N total=M` — **used to** appear here at warning
  level. It is a routine tally (only widgets we define tooltips for get
  one, so N < M is normal), now logged at debug. If you are looking for
  it, run qtile with debug logging. Genuine failures still warn, with
  `tooltip install failed for <widget>: <error>`.

If you see `WARNING libqtile:Key spec duplicated ... <Key ([], Escape)>`,
that fix has been reverted — see the entry above.

### xkbcomp warnings: unresolved `XF86…` keysyms, `<FK23>`/`<FK24>` redefined
- **Symptom:** a large block of `Could not resolve keysym
  XF86ElectronicPrivacyScreenOn` / `XF86ActionOnSelection` /
  `XF86ContextualQuery`, plus `Multiple symbols for level 1/group 1 on key
  <FK23>` and `Using F23, ignoring XF86TouchpadOff`.
- **Root cause:** not ours, and not a misconfiguration. `xkeyboard-config`
  ships symbol names newer than the keysym table `xkbcomp` was built
  against, so the compiler cannot resolve them. Every Arch machine running
  X prints this.
- **Fix:** none needed. X itself says so on the next line: *"Errors from
  xkbcomp are not fatal to the X server."* The affected keysyms are for
  hardware this laptop does not have (privacy screen, contextual-query
  keys). Ignore.

### `rofi_anki`: the EN piper voice is downloaded but never used
- **Symptom:** none visible — flagged by a lint sweep, not by a failure.
- **Root cause:** `rofi_anki` declares `SPELL_ENGINE="piper" # or "gtts"`
  and `PIPER_VOICE_EN=...`, but nothing reads either. The engine is
  hardcoded per language: English goes through `gtts-cli`, German through
  piper. So setting `SPELL_ENGINE="gtts"` does nothing, and the wizard's
  `piper` module downloads `en_US-ryan-high.onnx` (~30 MB) for a code path
  that never runs.
- **Status:** annotated in place, deliberately *not* rewired — switching
  which engine speaks your flashcards is a preference, not a lint fix.
  Decide one of: wire `SPELL_ENGINE` up, switch English to piper, or drop
  the unused voice from the `piper` module.

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

## Tmux

### tmux plugins do nothing — no resurrect/continuum auto-save, `vim-tmux-navigator`'s `C-h/j/k/l` don't move panes
- **Symptom:** `.tmux.conf` lists five `@plugin` entries and binds
  `prefix C-s` / `prefix C-r` to tmux-resurrect's save/restore scripts,
  but none of it works — sessions never restore after a reboot, manual
  save/restore does nothing, and `C-h/j/k/l` don't move between
  panes/vim splits the way vim-tmux-navigator is supposed to make them.
- **Root cause:** TPM (the plugin manager) was never actually
  bootstrapped — `~/.tmux/plugins/` didn't exist at all. `run
  '<path>/tpm/tpm'` on a missing path is a silent no-op in tmux, not an
  error, so this had no visible symptom beyond "the plugins just don't
  do anything." Compounding it, the resurrect key binds and the `run`
  line both pointed at `~/.config/tmux/.tmux/plugins/...`, a path that
  was never right to begin with (the correct, TPM-conventional location
  is `~/.tmux/plugins/...`).
- **Fix:** fixed the paths in `.tmux.conf` to `~/.tmux/plugins/...`,
  then one-time bootstrapped TPM:
  ```
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  ~/.tmux/plugins/tpm/bin/install_plugins
  ```
  This isn't wired into `wizard.sh` — a fresh install needs this run
  once by hand (or `prefix I` from inside tmux, TPM's normal install
  keybind, once `~/.tmux/plugins/tpm` exists).

### The number in the top-left of the tmux status bar never changes
- **Symptom:** `status-left` always shows `0`, no matter how many
  windows are opened or closed.
- **Root cause:** it was rendering `#S` (session *name*), not a window
  count. tmux auto-names an unnamed session by number starting at 0,
  and the fish `tmux` wrapper always creates sessions unnamed
  (`command tmux`, no `-s`) — with normally only one session alive at a
  time, that name is always "0". It genuinely never changes; it isn't
  stuck, it's just the wrong field for "does this move as I work."
- **Fix:** `status-left` now shows `#I` (current window index) instead,
  which increments/decrements as windows open and close — verified via
  `tmux display-message -F '#{E:#{status-left}}'` before/after
  `new-window`.

### tmux panes open in zsh instead of fish
- **Symptom:** occasionally a pane starts in zsh (Debian/Arch's default
  new-user zsh prompt) instead of fish, even though fish is the
  configured login shell.
- **Root cause:** tmux's default new-pane shell is whatever `$SHELL`
  was in the environment of the process that started the tmux
  *server* — if that first launch happened from something with a
  different `$SHELL` (a script, `su`, a cron job), every pane in that
  server inherits it, not just the one process.
- **Fix:** `.tmux.conf` now sets `default-shell` explicitly:
  `set -g default-shell /usr/bin/fish`.

---

## Adding new cases

Append entries here as you hit them. Keep the same tri-format
**Symptom / Root cause / Fix** so grep-through stays uniform.

### Qt apps (Telegram etc) render white on the dark desktop
- **Symptom:** GTK apps followed the theme, but Telegram and other Qt
  programs came up light/white regardless of mode.
- **Root cause:** Qt does not read the GTK theme. With no
  `QT_QPA_PLATFORMTHEME` set — and no qt5ct/qt6ct installed — Qt falls
  back to its own built-in palette, which is light. Nothing in the theme
  pipeline was ever reaching Qt at all.
- **Fix:** `.xinitrc` (generated by `wizard.sh:step_xinit`) exports
  `QT_QPA_PLATFORMTHEME=qt6ct`, and `theme-apply`'s `gen_qt_colors()`
  writes a matching palette into `~/.config/qt6ct/colors/current.conf`
  (and the qt5ct equivalent) on every apply, so Qt tracks all 21 modes
  like every other consumer. `qt6ct`/`qt5ct` declared in `wm.yaml`.
- **The palette file is positional.** qt6ct expects exactly **21**
  comma-separated colors in QPalette role order (WindowText, Button,
  Light, Midlight, Dark, Mid, Text, BrightText, ButtonText, Base, Window,
  Shadow, Highlight, HighlightedText, Link, LinkVisited, AlternateBase,
  NoRole, ToolTipBase, ToolTipText, PlaceholderText). A wrong count is
  **silently ignored** — apps just stay light, with no error. Check with:
  `head -2 ~/.config/qt6ct/colors/current.conf | tail -1 | tr ',' '\n' | wc -l`
- **Requires a fresh X session** — `QT_QPA_PLATFORMTHEME` is read at app
  start and exported from `.xinitrc`, so already-running apps and apps
  launched from a shell that predates the change keep the old palette.
- **WhatsApp is not a Qt app** — it is a Brave web app
  (`--app=https://web.whatsapp.com`, wm_class `sp-whatsapp`), so this
  does not affect it. Page content there follows the desktop's
  `prefers-color-scheme` preference (see the force-dark case below) plus
  WhatsApp Web's own in-app dark setting.

### Websites render as "bad dark" — washed out, glowing text, wrecked gradients
- **Symptom:** dark mode is on everywhere, but *page content* looks wrong
  rather than merely dark. On Canva the headline gradient turned into
  glowing neon purple on near-black, icons lost contrast, and panel
  backgrounds went muddy. Sites that have no dark theme of their own
  looked fine. Only the sites with a **good** dark theme looked bad.
- **Root cause:** two different mechanisms were fighting, and the wrong
  one was winning.

  | | what it is | who designed the colors |
  |---|---|---|
  | "normal dark" | site ships CSS behind `@media (prefers-color-scheme: dark)` | the site's designers |
  | "bad dark" | `--enable-features=WebContentsForceDark` — Chromium re-tints already-rendered pixels | nobody; it is a blind transform |

  All three `*-flags.conf` carried `--enable-features=WebContentsForceDark`.
  It was added because **web pages were coming up white**: with no desktop
  colour-scheme preference set, xdg-desktop-portal reported
  `org.freedesktop.appearance color-scheme = 0` ("no preference"), and
  Chromium — which reads exactly that key — told every site
  `prefers-color-scheme: light`. So every site served its light stylesheet,
  and force-dark was bolted on to compensate.

  On a site with a real dark theme that compounds: the site is *already*
  dark and force-dark darkens and inverts it a second time. Saturated
  accents (Canva's gradient headline) get pushed past their intended
  luminance and bloom; mid-greys collapse toward each other and contrast
  dies. GTK3/GTK4 `settings.ini` both had `gtk-application-prefer-dark-theme`
  set, which is why the *browser UI* looked right the whole time — that
  setting never reaches web content.
- **Fix:** advertise the preference properly and delete the workaround.
  - New `dark-mode` module in `wizard.sh` runs
    `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`,
    then **verifies through the portal** — if `xdg-desktop-portal-gtk` is
    missing, the gsettings write succeeds while browsers still see light,
    which is a silent failure that looks identical to the original bug.
  - `--enable-features=WebContentsForceDark` removed from
    `brave-flags.conf`, `chrome-flags.conf`, `chromium-flags.conf`.
  - `step_browser_flags` is now **authoritative rather than additive**: it
    strips the flag from existing installs instead of only appending what
    is missing, so an already-provisioned machine actually picks the fix up.
    It resolves stow symlinks first and skips anything pointing into
    `~/.dotfiles` — `sed -i` on a symlink replaces the link with a regular
    file and quietly detaches the machine from the repo.
- **Verify:**
  ```bash
  busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme
  # v u 0  -> no preference (sites serve light)
  # v u 1  -> prefer dark    (sites serve their own dark theme)   <- want this
  ```
  Browsers must be **fully restarted** to re-read `*-flags.conf`.
- **For a site with genuinely no dark theme:** turn force-dark on for that
  one site from the page menu. Do not put the flag back globally.

### Random tabs die with "Aw, Snap! Error code 61696"
- **Symptom:** a tab goes blank white with Chromium's crash page. Not tied
  to any one site; happens more the longer the session runs and the more
  Brave profile windows are open.
- **Root cause:** not a browser bug — the machine ran out of memory and
  `earlyoom` killed the renderer. The journal names the victim outright:
  ```console
  $ journalctl -b -u earlyoom | grep -i 'low memory' -A1
  mem avail: 457 of 4605 MiB (9.93%), swap free: 0 of 3911 MiB (0.00%)
  low memory! at or below SIGTERM limits: mem 10.00%, swap 10.00%
  sending SIGTERM to process 1444313 uid 1000 "brave": oom_score 887,
    ... cmdline "/opt/brave-bin/brave --type=renderer ..."
  ```
  Note `swap free: 0 of 3911 MiB` — **zram was 100% full**. earlyoom did
  the right thing (without it the whole X session would have frozen), and
  Chromium reports a SIGTERM'd renderer as `Aw, Snap!`. Chrome sets
  `oom_score_adj 300` on renderers precisely so they are chosen before
  qtile or the terminal, which is why tabs die and the desktop survives.

  Three things stacked up on an 8G laptop:
  1. `speed_boost.sh` sized zram at `min(ram / 2, 4096)` → only 3.8G, and
     it skipped reconfiguration whenever a `[zram0]` section already
     existed, so no existing machine would ever have grown it.
  2. `vm.swappiness` was left at the kernel default of 60, which is tuned
     for swap-on-disk. With zram, swapping costs a memcpy plus a zstd
     round-trip, so 60 leaves a cheap resource idle while the machine
     starves.
  3. **The scratchpads were each a whole separate browser.** This turned out
     to be the largest single cause, and the one that made the WhatsApp
     dropdown in particular useless. See the next case.
- **Fix:**
  - `speed_boost.sh` section 1 now sizes zram at `min(ram, 8192)` and
    **rewrites the config when the content differs** rather than skipping
    on the presence of a `[zram0]` header. zram is compressed RAM, not
    disk: at zstd's ~3:1 on browser heap, a 7.6G device costs ~2.5G of real
    RAM when full while absorbing ~7.6G of anonymous pages.
  - New `speed_boost.sh` section 2 writes `/etc/sysctl.d/99-zram.conf`:
    `vm.swappiness=180`, `vm.page-cluster=0`,
    `vm.watermark_boost_factor=0`, `vm.watermark_scale_factor=125` — the
    set Fedora ships with zram.
  - `--process-per-site` added to all three `*-flags.conf`: same-site tabs
    share one renderer instead of one process each. Cross-site isolation is
    unaffected (Site Isolation still applies). Trade-off: one renderer
    crash now takes every tab of that site with it.
- **The zram resize needs a reboot.** `systemd-daemon-reload` will not
  resize a swap device that is already in use, so `swapon --show` keeps
  reporting the old size until the next boot.
- **If it still happens after all of the above**, drop
  `--force-renderer-accessibility` from `brave-flags.conf` — its own
  comment flags the per-tab cost. That disables homerow's link hinting in
  the browser, which is why it is the last resort rather than the first.
- **Verify:**
  ```bash
  swapon --show                          # zram0 size should now be ~= RAM
  sysctl vm.swappiness vm.page-cluster   # 180 / 0
  journalctl -b -u earlyoom | grep -ci 'low memory'   # should stay at 0
  ```

### The WhatsApp / ChatGPT / DeepSeek scratchpad shows "Aw, Snap!" constantly
- **Symptom:** the browser scratchpads (`Mod2+8/9/0`) crash far more often
  than ordinary tabs — often "Aw, Snap!" immediately on open, sometimes
  rendering as a transparent crash page over whatever is behind them.
- **Root cause:** `--user-data-dir` is not "a profile", it is **a whole
  separate browser**, and the scratchpads used one each. A separate
  user-data-dir cannot share anything with the main instance, so each
  dropdown spawned its own supporting stack just to render one page:
  ```console
  $ ps -eo args | grep 'brave-profiles/whatsapp' | grep -oE '\-\-type=[a-z-]+' | sort | uniq -c
        1 --type=gpu-process
        1 --type=renderer      # <- the only one doing real work
        2 --type=utility       # network service + storage service
        3 --type=zygote
  ```
  Measured on an 8G laptop — four independent Brave stacks:

  | instance | RSS | procs |
  |---|---|---|
  | main | 2331 MB | 26 |
  | whatsapp | 842 MB | 8 |
  | deepseek | 807 MB | 9 |
  | chatgpt | 689 MB | 9 |

  **4.6G of 7.6G**, roughly 350MB per scratchpad of pure duplicated
  infrastructure. That is what kept the machine at the earlyoom threshold,
  and since Chrome tags renderers `oom_score_adj 300` the scratchpad
  renderers were the first thing killed. The config comment always *said*
  "one browser engine for all" — `--user-data-dir` is the flag that
  prevented it.
- **Fix:** `config.py` scratchpads now use `--profile-directory="Whatsapp"`
  (etc.) instead of `--user-data-dir=…/brave-profiles/whatsapp`. Separate
  profiles — separate logins, cookies and sessions — living inside the one
  running instance, sharing its gpu-process, network service and zygote.
  Each dropdown now costs one renderer.
- **`--class` does NOT survive this — match on the URL host instead.**
  This is the part that bites, and it produces a second, separate symptom:
  the dropdowns open as ordinary **tiled** windows in monadtall instead of
  floating scratchpads.

  When brave is already running, the new invocation is forwarded over the
  singleton socket and the window is created by the **original** browser
  process, which uses its own class. `--class` is simply lost:
  ```console
  $ xprop WM_CLASS        # on the whatsapp dropdown
  WM_CLASS(STRING) = "web.whatsapp.com", "Brave-browser"
  #                   ^ URL-derived instance   ^ NOT sp-whatsapp
  ```
  So `Match(wm_class="sp-whatsapp")` never fires, the window is not
  adopted by the ScratchPad, and it tiles like any other window.

  The instance field is URL-derived and stable, so match on that:
  ```python
  match=Match(wm_instance_class="web.whatsapp.com")   # chat.openai.com, chat.deepseek.com
  ```
  `compare()` maps `wm_instance_class` to `wm_class[0]` — exactly the
  URL-derived field — where a plain `wm_class` rule is tested against every
  field of the pair. Both work here; the instance form documents the
  intent. Ordinary brave windows are `("brave-browser", "Brave-browser")`,
  so these rules cannot swallow a normal browser window.

  `--class`/`--name` were dropped from the commands rather than left in as
  flags that only apply on a cold start (when the scratchpad is what
  launches brave). Matching the host is correct in **both** cases, which is
  precisely what `--class` is not.
- **Two traps if you test this yourself.** Both produce a false "the class
  survives" result:
  1. A `data:` URL has no host, so Chromium derives the instance name from
     the URL text and falls back to `"Brave-browser"` for the class. Test
     with the real `https://` app URL.
  2. If the profile does not exist yet, the invocation may **start** a
     browser process rather than forward to one — and `--class` does apply
     in that case. Confirm you actually forwarded before drawing a
     conclusion:
     ```bash
     pgrep -af 'profile-directory=Whatsapp'   # no lingering process => forwarded
     ```
- **Verify the fix took, rather than eyeballing the window:**
  ```bash
  qtile cmd-obj -o group scratchpad -f dropdown_info -a whats
  # want: a populated "window" object with "floating": true
  ```
- **One-time migration cost:** the old sessions under
  `~/.config/qtile/brave-profiles/` are not carried over — re-scan the
  WhatsApp QR and sign in to ChatGPT/DeepSeek once. Once the new profiles
  work, reclaim the disk with
  `rm -rf ~/.config/qtile/brave-profiles`.
- **Flags that silently stopped applying.** The scratchpads used to pass
  `--disable-background-networking`, `--disable-component-update`,
  `--disable-breakpad`, `--disable-sync`, `--no-first-run`. Those configure
  a **browser process at startup**; these commands now join an
  already-running one, so they became no-ops and were removed rather than
  left in as dead code. To keep that behaviour, put them in
  `~/.config/brave-flags.conf`, which applies to the single instance that
  does start.
- **Trade-off accepted:** the scratchpads now share a crash domain with the
  main browser — killing Brave takes them with it. On a RAM-constrained
  machine that is a better deal than 1GB of duplicated processes.

### Reducing memory usage on an 8G machine — what actually moves the needle
Measured on this laptop (7.6G total). Ordered by payoff, so stop when you
have enough back.

```console
$ ps -eo rss,comm --sort=-rss | awk 'NR>1{s[$2]+=$1;n[$2]++} END{for(k in s) printf "%8.0f MB %3d %s\n",s[k]/1024,n[k],k}' | sort -rn | head
    3947 MB  21  brave
     992 MB   3  claude
     580 MB   1  next-server
     334 MB   1  firefox
     310 MB   1  dockerd
     266 MB   4  kitty
```

1. **Brave, and specifically its renderers** — 2933MB of that 3947MB was 13
   renderer processes serving 6 windows. Two fixes are already in the repo:
   - `--process-per-site` in `*-flags.conf` (same-site tabs share a renderer)
   - the `browser-memory` module, which installs
     `50-memory-saver.json` as a managed policy to
     `/etc/brave/policies/managed`, `/etc/chromium/policies/managed` and
     `/etc/opt/chrome/policies/managed`. It discards idle tabs outright.

   Memory Saver is a **preference**, not a flag — a line in `*-flags.conf`
   cannot set it, and toggling it in Settings is lost on a profile reset.
   Policy is the only durable way to ship it.

   `TabDiscardingExceptions` is part of the same file and matters as much as
   the saving: a discarded tab stops executing, so anything holding a socket
   to notify you goes silent. WhatsApp Web is why the list exists.
   Verify at `brave://policy` — all entries should read **OK**, and an
   unknown-policy warning means that key was ignored, not that the file was
   rejected.
2. **Scratchpads as profiles, not separate browsers** — see the WhatsApp
   scratchpad case above. Worth ~730MB and 29 processes here.
3. **zram sizing + swappiness** — `speed_boost.sh`. Does not reduce usage,
   but roughly doubles the headroom before earlyoom starts killing tabs.
4. **Services you don't need every boot** — `docker.service` +
   `containerd.service` measured 356MB resident, and docker is
   `enabled` at boot by default. `service_trim.sh` prompts per service and
   is reversible; Docker starts on demand with
   `sudo systemctl start docker` when you actually need it.
5. **`--force-renderer-accessibility`** in `brave-flags.conf` — an AT-SPI
   tree per tab, so its cost scales with renderer count. Listed last
   deliberately: removing it disables homerow's link hinting in the browser,
   which is a real feature loss rather than free savings. Try everything
   above first.

Not worth chasing: `claude`, `next-server` and `node` are actual work, and
running firefox/qutebrowser alongside brave is a session choice, not
something the dotfiles should decide.

### Tray icons are invisible but still clickable
- **Symptom:** after toggling the systray widgetbox (△), the tray icons
  render as blank space — but clicking that space still activates them.
  Intermittent.
- **Root cause:** tray icons are not painted by the bar. Each is a
  separate XEmbed **client** window owned by its application.
  `WidgetBox.toggle_widgets()` hides them on close and relies on
  `Systray.draw()` calling `icon.unhide()` to bring them back, but
  `draw()` also binds each icon's background to the systray drawer's
  pixmap:
  ```python
  icon.window.set_attribute(backpixmap=self.drawer.pixmap)
  ```
  That pixmap is reallocated when the widget is removed from and
  re-inserted into the bar. The icons therefore come back mapped and
  correctly positioned — hence still clickable — while painting from a
  stale pixmap, which reads as invisible. It is intermittent because it
  depends on whether the client happens to receive an expose event and
  redraw itself anyway.
- **Fix:** `SmartWidgetBox.toggle()` schedules `_repaint_systray()`,
  which re-runs the hide → draw → unhide + `_XEMBED_EMBEDDED_NOTIFY`
  handshake against the current pixmap once the bar has settled.
- **Duck-typed on `tray_icons`**, not `isinstance(Systray)`:
  `qtile_extras` subclasses the libqtile widget, so an isinstance check
  against either import is fragile. Also wrapped in try/except — a
  cosmetic repaint must never break the toggle itself.

### A layout switch (or any watcher popup) fires several times at once
- **Symptom:** one keyboard-layout change produced three stacked
  notifications. Also made an edited watcher script look like it had not
  changed at all, since old copies were still running.
- **Root cause:** `autostart.sh` runs again on **every qtile restart**,
  and `keyboard_layout_watcher`, `adhkar` and `battery-events` were
  started with no guard — unlike the python daemons directly below them,
  which all use `pgrep … ||`. Every restart therefore left another copy
  running. Three keyboard watchers and six `battery-events` processes
  were live before this was noticed.
- **Fix:** the same `pgrep -f '<name>$' >/dev/null || <name> &` guard on
  all three.
- **Check for it:** `pgrep -cf 'keyboard_layout_watcher$'` — anything
  above 1 means duplicates. Same for any other `while true` script.
- **Gotcha when editing a watcher:** the running process keeps executing
  the *old* file. Restart it (`pkill -f '<name>$'` then relaunch) or the
  fix appears to do nothing. This is what made the dunst `stack-tag` fix
  look broken when it was already correct.
- **Notification dedup:** repeat popups from the same source carry
  `-h string:x-dunst-stack-tag:<tag>` so a new one replaces the previous
  instead of stacking. Used by `keyboard_layout_watcher`,
  `battery_notify` and `clock_popup`. It only dedups within one sender —
  it cannot save you from duplicate daemons.

### A stray drag reorders the workspace icons and apps open in the wrong group
- **Symptom:** workspace icons in the bar occasionally swap places, and
  afterwards apps open in the wrong workspace.
- **Root cause:** `GroupBox` ships with `disable_drag=False`, so
  drag-and-drop of group names is enabled by default.
  `button_release()` ends a drag with
  `group.switch_groups(self.clicked.name)`, which **swaps the two
  groups**. A slight sideways movement while clicking is enough.
- **Why it is destructive, not cosmetic:** every group carries
  `matches=[]` rules binding apps to it (browsers → 2, files → 3,
  editors → 4, chrome → 6). Swapping two groups repoints those bindings,
  so apps keep opening in the wrong place with nothing on screen
  explaining why.
- **Fix:** `disable_drag=True` on **both** GroupBoxes — the main bar and
  the `normal_user_bar` helper. Setting it on only one leaves that bar
  destructive.
- **Side effect:** clicking the already-active group now toggles back to
  the previous group (`toggle` defaults True, and `go_to_group` only
  reaches that branch when `disable_drag` is set). Set `toggle=False` if
  you want the old inert behaviour.
- **Verify:** script the gesture rather than trusting a hand test —
  `xdotool mousemove <x1> 17 mousedown 1; xdotool mousemove <x2> 17;
  xdotool mouseup 1` — then compare `qtile cmd-obj -o cmd -f get_groups`
  before and after.

### Battery chip popup
- Was an inline `notify-send "Battery Status" "$(acpi | cut -d, -f2-)"`
  in `config.py`, printing a raw fragment like `" 100%"` — leading space,
  no context, no sense of whether the number is good or bad. Now
  `AtiScriptsV1/battery_notify`, matching `disk_notify`: percentage, a
  bar coloured by level, charge state and an ETA.
- **Reads sysfs directly** (`/sys/class/power_supply/BAT*`) instead of
  parsing `acpi(1)` — no extra package, and no locale-dependent text to
  scrape.
- **ETA landmine:** at `Full` the draw drops to ~0, and dividing by a
  near-zero rate printed `"4323h 00m remaining"`. The ETA is now computed
  only while actively `Charging`/`Discharging`, and anything over 24h is
  discarded as the same noise in a less obvious form.
- Escalates to critical urgency only when **below 15% AND not charging** —
  a low battery that is already on the charger is not a problem.

---

## System updates

### An update broke the system badly enough to need a reinstall
- **Symptom:** a `pacman -Syu` left libraries missing and the system
  unbootable; snapshots were no help and the machine had to be
  reinstalled from scratch.
- **Root cause — not an Arch bug, a disk-space accident.** A full upgrade
  downloads into `/var/cache/pacman/pkg` and then unpacks into `/usr`,
  so it needs room for **both at once**. If `/` fills part-way through a
  transaction, a package's old files have already been removed and the
  new ones were never written: libraries vanish mid-upgrade and the
  system stops booting.
- **Why it happened here:** Timeshift defaulted to
  `backup_device_uuid` = the **root partition itself**, so 12G of
  snapshots sat on the same 32G `/` they were protecting, leaving 2.7G
  free. That is self-defeating twice over:
  1. the snapshots consume exactly the headroom upgrades need, and
  2. when `/` is damaged the snapshots are damaged with it — which is
     why recovery meant a reinstall rather than a restore.
- **Fix (done on this machine 2026-07-28):** snapshots were relocated to
  `/home` (`/dev/sda3`), taking `/` from **91% used / 2.7G free** to
  **54% / 14G free**. Procedure, if it must be redone: `rsync -aHAX`
  (the `-H` matters — timeshift hardlinks unchanged files between
  snapshots, and losing that multiplies disk use per snapshot) to the
  new location, verify file counts match and a dry-run re-sync reports
  zero differences, repoint `backup_device_uuid` in
  `/etc/timeshift/timeshift.json` at the new partition's UUID, confirm
  `timeshift --list` still shows the snapshots, and only then delete the
  original. Never delete first.
- **Snapshots must live on a different filesystem** (`/home`, or better
  an external disk). Check with:
  ```sh
  findmnt -no SOURCE --target /timeshift
  findmnt -no SOURCE --target /
  # these must NOT be the same device
  ```
- **Use `safe-update`** instead of a bare `pacman -Syu`. Every step is a
  refusal point and nothing is mutated until the last one: space
  preflight (≥6G) → `archlinux-keyring` → `informant` news gate →
  verified snapshot → `pacman -Syuw` download-only → re-check space →
  `pacman -Su`.
- **Why that order:** keyring before `-Syu` (a stale keyring fails every
  signature check, and the tempting "fix" is disabling sig checks, which
  is far worse than the problem); download-only before install (a
  network failure or full disk during download is harmless and
  resumable); re-check space after download because the download itself
  consumed some.
- **The snapshot is verified, not assumed** — `safe-update` counts
  snapshots before and after rather than trusting timeshift's exit code.
  An unverified backup is worse than none, because you act as though you
  have one.

### Recovering from a broken upgrade
- **System still boots:** `sudo downgrade <package>` rolls back a single
  bad package from the pacman cache without a full restore. This is why
  the cache should not be aggressively cleared — `paccache -rk1` keeps
  one previous version of everything, which is the rollback material.
- **System does not boot / dynamic linking broken:** this is what
  `pacman-static` is for. It is statically linked, so it still runs when
  a `glibc` or `libstdc++` upgrade has broken every dynamically linked
  binary on the system — including normal `pacman`, which is exactly
  when you need it most. Boot the Arch ISO, `arch-chroot`, then use
  `pacman-static` to repair or roll back.
- **ext4 has no bootable snapshots.** Timeshift in rsync mode restores
  through a live USB; it cannot boot into a previous state the way
  btrfs + snapper + grub-btrfs can. Worth knowing *before* you need it.
- **Never `pacman -Sy <pkg>`.** Partial upgrades are the other classic
  way to break an Arch system: refreshing the database without upgrading
  installed packages leaves libraries and their dependents at mismatched
  versions. Always `-Syu`.

### "Is install.sh guaranteed to work?"
- No, and no honest process can claim that. What is verifiable:
  `./wizard.sh --dry-run --yes` proves every module is **reachable,
  correctly ordered, and idempotent** (28/28 ok). It cannot prove that
  AUR builds compile, that upstream URLs still resolve, or that a
  package has not been renamed — those depend on the world outside the
  repo on the day you run it.
- The only real proof is a fresh-VM run; see "Testing on a fresh Arch VM"
  above. Treat the dry-run as a structural check, not a guarantee.

### The update safety net — what runs, and where each piece lives
Three layers, deliberately at different levels so no single failure
removes all protection.

**1. pacman hook — `/etc/pacman.d/hooks/00-preflight.hook`**
Runs `PreTransaction` on *every* Install/Upgrade, whatever launched it:
dcli, yay, paru, or bare `pacman`. `AbortOnFail` stops the transaction
before a single file is written. Refuses under 3G free on `/`.
- **Why not just a dcli hook:** dcli is third-party. If its config format
  changes, or `update_hooks` is dropped, a dcli-only guard stops working
  **silently** — and you find out at the moment it was supposed to save
  you. A pacman hook has no wrapper to bypass and no third-party format
  to drift.
- Installed by wizard module `pacman-guard`. The script itself
  (`AtiScriptsV1/pacman-preflight`) is symlinked by `ati-scripts`, so
  `pacman-guard` must run **after** it in `MOD_ORDER`.

**2. dcli pre_update — `arch-config/scripts/pre-update.sh`**
Richer checks, but only on `dcli update`. Blocks on: <6G free,
snapshots on the root device, `pacman -Dk` inconsistency. Warns on:
soname bump + AUR packages, unread Arch news, unmerged `.pacnew`, thin
pacman cache, high-impact packages.

**3. dcli post_update — `arch-config/scripts/post-update.sh`**
Runs after. Scans AUR packages for unresolved libraries, and on a hit
pushes the exact `yay -S --rebuild …` command to a dunst popup **and the
clipboard** via `post-update-notify`, because a fix you must retype from
scrollback is a fix that does not get applied. Also flags kernel
mismatch (reboot) and new `.pacnew` files.

### Recovery ladder, in the order to try it
1. **App misbehaves, system fine** → `sudo downgrade <pkg>`. Needs the
   pacman cache, which is why it must not be over-trimmed.
2. **AUR app won't start** ("cannot open shared object file") → the
   post-update hook already gave you the rebuild command.
3. **System won't boot** → pick **"Arch Linux (LTS fallback)"** at the
   boot menu and repair from a working system. This is why `linux-lts` is
   declared in `base.yaml`.
4. **LTS fallback drops to an emergency shell** → pick **"Arch Linux (LTS
   rescue - all modules)"**. Same kernel, but its initramfs was built
   without the `autodetect` hook, so it carries every module rather than
   only those probed when the image was generated. Boots slower, costs
   ~205MB on the ESP, and comes up when the trimmed image cannot.
5. **Fallback kernel also fails** → Arch ISO, `arch-chroot`, then
   `pacman-static` — statically linked, so it still runs when a `glibc`
   upgrade has broken every dynamically linked binary including `pacman`.
6. **Unrepairable** → Timeshift restore. Snapshots live on `/home`
   (`/dev/sda3`), so they survive a dead root.

### Bootloader: this machine uses systemd-boot, not GRUB
- Easy to get wrong: `grub` is installed and `/boot/grub/grub.cfg`
  exists, but `efibootmgr` shows `BootCurrent` →
  `\EFI\systemd\systemd-bootx64.efi`. Running `grub-mkconfig` appears to
  succeed and changes nothing that boots.
- Entries live in `/boot/loader/entries/*.conf`. Verify with
  `bootctl list`, never by reading `grub.cfg`.
- The primary entry is a **Unified Kernel Image**
  (`/EFI/Linux/arch-linux.efi`) with its cmdline baked in — which is why
  `arch.conf`'s `options` line can carry a stale PARTUUID and still boot.
  **Take kernel options from `/proc/cmdline`**, which is authoritative,
  not from `arch.conf`.
- `linux-lts` produces no UKI, so its entries are plain type-1 entries
  with `linux` + `initrd` lines.
- `loader.conf` shipped with `#timeout 3` commented out, which suppresses
  the menu entirely. A fallback entry you cannot select is not a
  fallback; the wizard appends `timeout 5` if no real timeout is set.

### The two LTS entries, and who writes them
Wizard module **`boot-fallback`** (runs after `pacman-guard`) writes both,
after `dcli-sync` has installed `linux-lts`:

| Entry | Initramfs | When you want it |
|---|---|---|
| `arch-lts.conf` — *Arch Linux (LTS fallback)* | `initramfs-linux-lts.img`, autodetect-trimmed, ~18MB | a bad `linux` upgrade |
| `arch-lts-fallback.conf` — *Arch Linux (LTS rescue - all modules)* | `initramfs-linux-lts-fallback.img`, no autodetect, ~205MB | the trimmed image is missing a driver |

- The rescue image only exists because the module adds `fallback` to
  `PRESETS` in `/etc/mkinitcpio.d/linux-lts.preset` (Arch ships
  `PRESETS=('default')` for LTS) and reruns `mkinitcpio -p linux-lts`. The
  preset is edited **in place**, not overwritten — pacman owns that file
  and an overwrite means a `.pacnew` on every `linux-lts` upgrade.
- **The module generates the entries, it does not copy them.** Boot
  entries are machine-specific: `root=` comes from `/proc/cmdline` (the
  authoritative source — see above), the microcode `initrd` line is only
  emitted for the `intel-ucode.img`/`amd-ucode.img` that actually exists,
  and the ESP comes from `bootctl --print-esp-path`. The copies in
  `arch-config/boot/` are *this machine's* snapshot, kept for reference
  and diffing — deploying them verbatim elsewhere gives you an entry that
  looks correct in the menu and fails at the moment you need it.
- **Check the ESP has room.** The rescue image is ~205MB on a typical
  1GB `/boot`; `df -h /boot` before, and expect `mkinitcpio` to fail
  loudly rather than silently truncate if it does not fit.
- Verify with `bootctl list` — all four (UKI, `arch.conf`, and the two LTS
  entries) should appear. `(not reported/new)` next to an entry just means
  it has not been booted yet, not that it is broken.
- ⚠️ **Not yet boot-tested on this machine.** Everything short of a reboot
  has been validated: `bootctl list` shows both entries, and `ext4`,
  `ahci` and `sd_mod` are built **into** the LTS kernel (`CONFIG_*=y`), so
  the trimmed image having fewer modules cannot cost us the root device.
  Actually confirming it boots requires a reboot.

### Reload shows every window piled up, or takes ~10s (the restart veil)
`Super+Shift+R` used to show every window from every workspace stacked on
top of each other for ~2s. A "veil" (`qtile/scripts/qtile-restart-veil.py`,
launched by `config.py`'s `_smooth_restart`) covers the transition and
reports real progress.

- **The pile is inside qtile's own boot**, between its window scan and the
  `startup` hook — measured, no config-level code is alive then. It cannot
  be fixed from config, which is why the veil is a **separate process**
  (it has to survive the `execv`).
- **The veil needs `python-gobject`.** Without it `_veil_launch()` returns
  False and `_smooth_restart` falls through to a plain `qtile.restart()` —
  the pile comes back and nothing tells you why. Declared in
  `python-lib.yaml`.
- **Notifications landing on top of the veil.** Two mechanisms, both
  needed. qtile pauses dunst before restarting, and the veil *unpauses it
  itself* from a `finally` when its window actually goes away — dunst
  **queues** while paused and flushes the entire backlog the instant it
  unpauses, so unpausing on a timer dumped everything onto the veil.
  Separately, the veil keeps itself topmost by reacting to
  `SubstructureNotify` on the root window: X has no always-on-top flag it
  enforces for override-redirect windows, so re-raising is the only
  mechanism, and a 16ms poll left a hole any window could appear through.
- **If dunst ever goes permanently silent after a failed reload**, this is
  the first thing to check: `dunstctl is-paused`. `dunstctl set-paused
  false` fixes it. The `finally` covers the crash and watchdog paths so it
  should not happen, and qtile keeps an idempotent backstop at 1.5s.
- **Changing theme feels laggy before the veil appears.** `theme-apply`
  calls `_veil_hold()` as its first act so the veil is up *before* it
  writes ~10 app palettes. Without that you watch ~4s of colours swapping
  on a naked desktop, then a loading screen.
- **The ~7s is qtile, not the veil.** Read the veil's own elapsed counter:
  "restarting window manager" sits at 21–22% for the whole span, and that
  label is set immediately before `qtile.restart()` with the next update
  coming from the *new* process. So it is execv + interpreter + `libqtile`
  import + config load + 32-widget bar + window scan. Making the veil
  simpler saves nothing — it is a separate process animating in parallel.
- **Never iterate on this by restarting the live session.** An early
  attempt (fullscreen `feh` overlay) froze the desktop and crashed X. Use
  the Xephyr sandbox; recipe in `qtile-veil-HANDOFF.md`. Note the sandbox
  understates real timings by ~2.5x — good for behaviour, useless for
  numbers.
