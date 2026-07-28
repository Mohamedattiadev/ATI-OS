# Qtile X11 Arch Linux Dotfiles

A minimal, reproducible **Arch Linux + Qtile (X11)** configuration focused on performance, keyboard-driven workflows, and long-term maintainability.

This repository documents **both** the configuration itself and the **automated bootstrap workflow** used to deploy it consistently across systems.

> **Important note**  
> This setup is based on [Distrotube’s](https://www.youtube.com/c/DistroTube/videos) Qtile configuration and has been extended with my own customization, workflow adjustments, and personal preferences.  
> While it follows the general structure and philosophy of the original configuration, the final implementation reflects my individual use case and design choices.

---

> **Troubleshooting:** hit an issue? Check
> **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — real cases logged
> with symptom / root cause / fix (chrome not retinting, rofi-kill
> slow, qtile freezes, eww not reloading, etc.).

## 1. Assumptions

Before proceeding, ensure that your system matches the following requirements:

1. **Arch Linux** (clean base installation)
2. **X11 only** (Wayland is not supported)
3. **No display manager** (TTY + `startx`)
4. Package and system provisioning handled **declaratively via dcli**

Systems that do not meet these assumptions may require manual intervention.

---

## 2. Project Overview

This repository contains my personal **Qtile + X11** dotfiles.

The setup is designed to be:

1. Declarative and reproducible
2. Easy to deploy using symbolic links
3. Independent of manual package installation steps
4. Maintainable across reinstalls and multiple machines

### Scope of this README

This document explains:

1. The assumptions and design philosophy
2. How the system is bootstrapped
3. How packages and configuration are managed
4. How Qtile is started and maintained
5. Visual demonstrations of the system and its modes

---

## 3. dcli (Declarative Package Management)

Every pacman/AUR package on this system is declared in YAML under
`~/.dotfiles/.config/arch-config/`:

```
arch-config/
├── config.yaml                 # pointer to active host
├── hosts/ati.yaml              # enabled_modules + host packages
└── modules/
    ├── base.yaml               # dcli itself, timeshift, pacman-contrib
    ├── apps.yaml               # daily apps (brave, obsidian, ...)
    ├── wm.yaml                 # qtile-extras, picom, dunst, ...
    ├── dev.yaml                # nvim, git, fish, cargo/rust, ...
    ├── media.yaml              # pipewire stack, easyeffects, ...
    ├── fonts.yaml              # Nerd Fonts, Amiri, Cairo, ...
    ├── system-tools.yaml       # xcape, evtest, dmenu, poppler, ...
    ├── graphics.yaml           # Intel HD 520 (mesa, vulkan-intel, ...)
    ├── network.yaml            # iwd, bluez
    ├── xorg.yaml               # xinit, xinput, xev, xwallpaper
    └── python-lib.yaml         # psutil, dbus-fast, pillow, ...
```

Change a module → run `dcli sync` → system converges. `timeshift-autosnap`
takes a snapshot on every sync, so a broken update is a one-command rollback.

Upstream: https://gitlab.com/theblackdon/dcli

---

## 4. Installation (Single Command)

Assumes a **fresh Arch base install** (no DE, no display manager).

```bash
git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles \
  && cd ~/.dotfiles/installScripts \
  && ./install.sh
```

That is it. `./install.sh` fires the wizard in unattended mode:

- Auto-bootstraps `gum` via pacman (~2 s)
- Runs all 27 modules end-to-end (system pkgs · dcli sync · dotfile
  stow · themes · brave/chrome policy · piper + whisper models · …)
- Keeps `sudo` alive for the whole run (primed once, refreshed in the
  background) so long AUR builds don't silently drop package installs
  when the credential cache would otherwise expire mid-run
- Any failed module auto-skips, logs to `/tmp/wizard-<id>.err`, listed
  in final summary; `dcli sync` additionally self-verifies with a
  dry-run and retries if anything's still missing afterward

### Prefer to pick modules or preview first?

```bash
./wizard.sh                 # interactive: TUI checkbox picker
./wizard.sh --dry-run       # preview every command, touch nothing
./wizard.sh --yes           # same as ./install.sh
./wizard.sh --only=stow,themes,browser-flags   # subset
./wizard.sh --skip=whisper,piper               # skip heavy downloads
./wizard.sh --uninstall     # reverse wizard writes (safe: never
                            #   touches packages or downloaded models)
./wizard.sh --uninstall --dry-run  # preview reversals
```

Wizard renders an ASCII banner, grouped module cards (System /
Dotfiles / Themes / Browsers / Apps / Media), spinners, unicode
progress bars, and doom-emacs colored badges. On step failure it
shows a red-bordered error tail and prompts **retry · skip · quit**
(unless `--yes`, which auto-skips).

Done. One command. Bootstrap covers all 27 modules, in order:

| # | id | What |
| - | -- | ---- |
| 1  | `sanity` | Sanity checks (Arch, X11, dotfiles present) |
| 2  | `bootstrap` | Bootstrap pkgs (git, stow, xorg-server, base-devel) |
| 3  | `yay` | Build `yay-bin` from AUR if absent |
| 4  | `dcli` | Install `dcli-arch-git` |
| 5  | `stow` | Stow dotfiles into `$HOME` |
| 6  | `arch-config` | Sync `arch-config` host file to current username |
| 7  | `dcli-sync` | **`dcli sync --force`** — installs every declared pkg (self-verifies + retries) |
| 8  | `cargo` | Cargo tools (`rustup default stable` + `pomodoro-tui`) |
| 9  | `ati-scripts` | Install AtiScriptsV1 to `/usr/local/bin` |
| 10 | `touchpad` | Touchpad config (`/etc/X11/xorg.conf.d/30-touchpad.conf`) |
| 11 | `xinit` | Write `~/.xinitrc` (qtile + picom + xcape + tray + copyq) |
| 12 | `xresources` | Write `~/.Xresources` (Xcursor size 24 + Breeze theme) |
| 13 | `xmodmap` | Write `~/.Xmodmap` (Caps hold = Alt, xcape restores tap Caps) |
| 14 | `lid` | Lid close = ignore (`systemd-logind`) |
| 15 | `image-envs` | Suppress VIPS warnings + ensure `~/tmp` (fish `TMPDIR`) |
| 16 | `flatpak` | Legacy cleanup only — qdrop replaced flathub/collector |
| 17 | `piper` | Download Piper voices (EN + DE) |
| 18 | `whisper` | Download Whisper `small.en` model |
| 19 | `passwordless-sudo` | Passwordless sudo |
| 20 | `ownership` | Fix dotfiles ownership |
| 21 | `disable-dm` | Disable all display managers |
| 22 | `candy-icons` | Install candy-icons theme |
| 23 | `wallpapers` | Clone wallpaper collection |
| 24 | `speed` | System speed tweaks (`speed_boost.sh`) |
| 25 | `themes` | Theme system (pywal + palette precompile + initial doomone apply) |
| 26 | `browser-flags` | brave/chrome/chromium wal theme extension flags |
| 27 | `chrome-policy` | Chrome/chromium theme policy (sign key + enterprise force-install) |

No manual follow-up. Everything in `.config` works on first `startx`.

---

## 5. Qtile Startup & Workflow

Start X session from TTY:

```fish
startx
# or the fish function (guards against a stale /tmp/.X0-lock and
# refuses if X is already running):
letsgo
```

`letsgo` is a **fish function** (`.config/fish/config.fish`), not a shell
alias — it only exists in fish. The account's login shell is therefore set
to fish (`chsh`, wizard step `login-shell`) so the TTY matches what kitty
already forces via `shell /usr/bin/fish`. Without that, the TTY drops to
bash and `letsgo` is `command not found` — precisely when you need it,
after X has died. Revert with `chsh -s /usr/bin/bash $USER`.

Reload qtile config without logout:

```bash
qtile cmd-obj -o cmd -f reload_config
```

Full restart (needed after refactor / class changes):

```bash
qtile cmd-obj -o cmd -f restart
```

Reload fonts:

```bash
fc-cache -fv
```

---

## 6. Updating the system

`dcli` is the single update entrypoint. `timeshift-autosnap` snapshots
before every run — rollback via GRUB if something breaks.

```bash
dcli sync                # apply module changes + full system update
```

To add/remove a package: edit the appropriate `arch-config/modules/*.yaml`,
then `dcli sync`. Commit + push when the machine is verified working:

```bash
cd ~/.dotfiles
git add .config/arch-config
git commit -m "arch-config: <change>"
git push
```

---

## 7. Post-install tuning (optional, one-time)

Two interactive scripts under `installScripts/` for boot-time / runtime
trimming. Not wired into `install.sh` — they need reboot, are per-machine,
and prompt before touching anything. Idempotent (safe to rerun).

```bash
bash ~/.dotfiles/installScripts/grub_boost.sh    # kernel cmdline: nowatchdog, quiet loglevel=3, cursor off, i915 GuC
bash ~/.dotfiles/installScripts/service_trim.sh  # audit + disable heavy services (docker, postgres, tailscaled, ...)
```

Each backs up before writing. Revert instructions printed at end.

---

## 8. Theming (kitty · rofi · dunst · qtile · gtk · qutebrowser · nvim · brave · papirus folders)

Every consumer follows one selected theme. Installer step 23 seeds it end-to-end.

**22 modes.** Presets: `doomone` · `dracula` · `gruvbox` · `nord` · `tokyonight`
· `catppuccin` · `monokai` · `everforest` · `rose-pine` · `kanagawa` ·
`oxocarbon` · `onedark` · `palenight` · `nightowl` · `github-dark` ·
`ayu-mirage` · `cyberpunk-neon` · `synthwave` · `matrix` · `mono-dark` ·
`mono-light`. Plus `wal` = pywal palette from the current wallpaper.

```bash
theme-apply doomone   # any preset
theme-apply wal       # pywal from current wallpaper
theme-toggle          # rofi picker (also bound to Mod+P → c)
```

- **Picker**: `Mod + P` then `c` → rofi list with all 22 themes. Displays
  friendly names (`wal` shown as `Wallpaper`, `mono-light` as `Mono Light`,
  etc.). Current theme is marked with `●`.
- **Light-mode theme swap**: `mono-light` flips the base GTK theme to
  `Breeze` + `Papirus-Light` (dark themes stay on `Sweet-Dark` +
  `Papirus-Dark`) so pcmanfm/gtk apps render properly light-on-white.
- **Instant preemption**: rapid picker clicks kill the in-flight
  `theme-apply` and start the newer one — no more silent lock skips.

Wal mode uses a precompiled cache. `wal-precompile` walks
`~/Pictures/Wallpapers/` and produces per-image palettes at
`~/.cache/qtile/palettes/<basename>.json`. Every palette is forced to a
doomone-quality bar (WCAG AAA bg/fg, WCAG AA per-accent, hue-spread
guaranteed). See `.config/qtile/WAL_PRECOMPILE_REPORT.md`.

**New wallpapers** — drop any image into `~/Pictures/Wallpapers/` and
select it (dm-setbg / WallpaperPopup). `theme-apply wal` auto-runs
`wal-precompile --only <basename>` on cache miss so the palette is
generated before consumers write. No manual precompile step.

**Concurrency** — `theme-apply` uses `flock` on
`~/.cache/qtile/.theme-apply.lock`; rapid wallpaper switches or
keybind spam are dropped silently instead of corrupting caches.

**Coverage per apply**

| Consumer | Reload mechanism |
|---|---|
| kitty | `set-colors --all` per live socket + SIGUSR1 |
| rofi | symlink `current-palette.rasi` swap |
| dunst | render `dunstrc.tmpl` + restart |
| qtile | `restart` (detached so caller doesn't deadlock) |
| gtk 3/4 | `@import` overlay at `~/.cache/qtile/gtk-wal.css` |
| qutebrowser | homepage: inline `<style>` + `--accent` CSS var. Browser chrome (tabs/statusbar/completion/messages/prompts/downloads, 78 options): `config.py:_apply_palette()` reads `current_palette.json` — runs for **all** modes, not just `wal`. Both via `:config-source` + `:restart` |
| nvim | fs_event on `~/.cache/qtile/theme_mode` + `current_palette.json` re-sources scheme; aliased modes (matrix, mono-*, synthwave, cyberpunk-neon, palenight, github-dark, ayu-mirage, onedark, nightowl) render distinct highlights from the JSON when no dedicated plugin is installed (Snacks dashboard uses dominant hue) |
| brave | `--load-extension` reads live `manifest.json` on relaunch (id matches via embedded `key`) |
| chrome / chromium | Enterprise policy `force_installed` from local `updates.xml`; `.crx` repacked + Preferences purged each apply so install lands immediately. Extension id is derived from `browser-theme.pem` at runtime (never hardcoded — it is per-machine), and browsers relaunch via their `/usr/bin` wrapper so `*-flags.conf` (`--load-extension`) is actually applied |
| papirus folders | `papirus-folders -C <hue-match> -u` (needs the `papirus-folders` AUR pkg — declared in `arch-config/modules/system-tools.yaml`; silently no-ops, icons stay default color, if missing) |
| eww widgets | daemon killed + `setsid eww daemon` restart + reopen prior windows (previous `eww reload` left compiled scss cached) |
| qtile cheatsheets (Vim/Fish/Qtile popups) + WallpaperPicker | `popups/_wal_colors.load_colors()` reads `~/.cache/qtile/current_palette.json` first (matches active preset), falls back to `~/.cache/wal/colors.json`; muted derived from `bg`→`fg` blend for readable dividers; popup panel bg driven from `COLORS["bg"]` so mono-light renders on white |
| gtk base theme + icon theme | `settings.ini` rewritten per palette: `mono-light` → `Breeze` + `Papirus-Light`; all others → `Sweet-Dark` + `Papirus-Dark` |
| cursor | `~/.Xresources` sets `Xcursor.size: 24` + `Xcursor.theme: breeze_cursors`; loaded via `xrdb -merge` in `~/.xinitrc` |

**Qtile restart preserves layout + window→group state**: `Mod + Shift + R`
restarts qtile (needed for widget colors to repaint). MonadTall ratios +
secondary stack sizes save every 3s to `~/.cache/qtile/layout_state.json`;
window→group mapping + per-group focus order save to
`~/.cache/qtile/window_group_state.json`. Both restore on
`startup_complete` (+0.6s / +1.6s). Manually-moved windows stay in their
chosen group even though Match rules re-fire on adoption — the `client_new`
hook overrides Match assignment for any wid present in the restored map.
Window widths/heights + placement survive the restart.

**State files** (auto-created — no manual bootstrap):
- `~/.cache/qtile/theme_mode` — single-line active mode name
- `~/.cache/qtile/current_palette.json` — 9-slot palette (bg, bg_alt, fg, red, green, yellow, blue, purple, cyan) dumped on every preset + wal apply; consumed by nvim + popups
- `~/.cache/qtile/layout_state.json` — MonadTall ratios + relative_sizes per group
- `~/.cache/qtile/window_group_state.json` — wid→group map + per-group focus order
- `~/.cache/wall` — symlink to active wallpaper (writers: `dm-setbg`, `WallpaperPopup`, `wizard step_themes`)

**Palette semantics** — `wal-precompile` generates 6-slot hue-concentrated palettes:
`color1` urgent (always warm), `color2` dominant (main wallpaper hue),
`color3` warm-fill, `color4` cool-fill, `color5` complement, `color6` info/cyan.
qtile bar accents pin to `color2`; test harness at
`.config/qtile/scripts/wal-visual-test.py` validates 12 hue buckets end-to-end.

**Wallpaper vs. theme** — changing the wallpaper re-derives the palette
**only when the active mode is already `wal`**, since `wal` is the mode
that means "follow the wallpaper". On a preset (`gruvbox`, `doomone`, …)
you picked a fixed palette on purpose, so a new wallpaper swaps the
desktop image and nothing else. All three setters (`dm-setbg`, the
dmscripts `dm-setbg`, `WallpaperPopup`) check
`~/.cache/qtile/theme_mode` before invoking `theme-apply wal` on a bg
thread (so qtile stays responsive), and fail closed if that file is
unreadable. To re-theme around a new wallpaper from a preset, run
`theme-apply wal` explicitly or pick `Wallpaper` in the theme picker.

**Shared UI font** — the qtile popups (wallpaper picker, cheatsheets)
use `qtile_extras`' default `sans` family, so dunst (`Sans 10` in
`dunstrc.tmpl`) and eww (`$ui-font: sans-serif` in
`.config/eww/fonts.scss`) resolve through that same fontconfig alias
rather than naming a family. Restyle all three at once by editing
`~/.config/fontconfig/fonts.conf`; `fc-match sans` shows the winner.

**Rofi UI stack** — all `.rasi` themes import a shared `base.rasi`
(doom-one flavor, radius 12, palette-driven). Overrides are layout-only
(width, height, lines). Rofi scripts source
`.config/AtiScriptsV1/rofi_common.sh` for palette parsing, wayland-safe
clipboard, dep checks, and a compact `rofi_confirm` prompt. Notable:
`rofi-kill` shows PID + process + window title (via `wmctrl -lp` + PPID
walk for browser subprocs) in aligned columns with vertical dividers.

---

## 9. qdrop — native drop-stash

Lightweight GTK3 daemon replacing the flatpak `it.mijorus.collector`.
Slides in from top-center, stashes files/text/URLs, drag them back out anywhere.
Themed live from the active wal palette (`~/.cache/wal/colors.json`).

**Usage**

- `Alt+Shift+D` — toggle.
- **Shake** the mouse while dragging (rapid left-right, 3 reversals in 1s) → auto-shows.
- Drop file/text/URL into window → adds entry. URL text auto-detected.
- Drag an item back out → paste into any app.
- Rubber-band select on empty area. Ctrl+A / Ctrl+click. Right-click for menu.
- `Ctrl+V` paste clipboard. `Ctrl+F` search. `Del` remove. `Enter` open.
- Text/text-files → floating alacritty+nvim (`clip-view` class).
- Image files → `imv` (uses existing qtile float rule).
- Auto-hides 8s after pointer leaves (paused while dialogs/menus open).

**Files**

- `.config/qtile/scripts/qdrop.py` — daemon + IPC + widget
- `.config/qtile/scripts/qdrop_watch.py` — XInput2 raw-event shake detector
- `.config/qtile/scripts/qdrop_test.py` — 30+ pure/live tests
- Autostart entry in `autostart.sh` launches daemon + watcher at login.

**IPC** — Unix socket at `/tmp/qdrop-$UID.sock`. CLI:
`qdrop.py --show|--hide|--toggle|--add-text TXT|--reload|--status`.
Palette reload auto-triggers via mtime poll on `colors.json`.

**Resources** — 0% CPU idle. ~90 MB combined RSS.

---

## 10. qupdate — pending updates + install picker

Click the CheckUpdates chip in the top bar. Floating GTK3 daemon with two tabs:

**Updates tab**
- Lists pending pacman + AUR packages (parallel `paru -Qu` + `paru -Qua`).
- Cache-first render (`~/.cache/qupdate.json`) → instant open, revalidation
  runs in background thread.
- Per-package checkbox + `PKG`/`AUR` badge + `oldver → newver`.
- Refresh / All / None / filter.
- Footer: `Update selected` (paru -S --needed) or `Full upgrade` via
  the tool combo — defaults to **`dcli sync`** so timeshift snapshots
  + arch-config module state stay in sync.
- `Run in background` checkbox → runs without terminal, notify-send on
  success/failure, log at `/tmp/qupdate-$UID-run.log`.

**Install tab**
- Search official repos (`pacman -Ss`) + AUR (`paru -Ssa`) with 350ms
  debounce. Repo used for common queries so paru's "too many results"
  cap doesn't apply. Deduped, sorted: exact match → prefix → substring
  → repo before AUR → not-installed first → shortest name.
- Row shows name + badge + description; `installed` marker when already present.
- `Install selected` runs `paru -S --needed <pkgs>` (terminal or bg).

**Shared**
- Socket at `/tmp/qupdate-$UID.sock`. CLI:
  `qupdate.py --show|--hide|--toggle|--refresh|--status|--daemon`.
- Wal-palette themed (reads `~/.cache/qtile/current_palette.json`, polls
  mtime every 3s → auto-restyle on theme swap).
- Autostarted hidden at login. Widget Button1 sends `--toggle`.

---

## 11. Videos

### 11.1 Main Videos (System Overview)

https://github.com/user-attachments/assets/aaec7215-c595-4ba3-bc65-a355b11edf05

https://github.com/user-attachments/assets/a7993cce-e04e-4168-9b32-b914d76539be

---

### 11.2 Feature Demonstrations

https://github.com/user-attachments/assets/6990186e-336d-48d4-8330-7c8ffd0f0a81

https://github.com/user-attachments/assets/fec68105-483d-4e7f-9573-6f43291c2d39

https://github.com/user-attachments/assets/acb09f1a-f268-4a68-ae23-819ecee27453

https://github.com/user-attachments/assets/9d8f53bb-eead-4e02-a844-3aba44fe9a34

https://github.com/user-attachments/assets/0189c230-a0df-4d8f-9687-ca8e5c00ed4a


---

## 12. Modes

### Window Manager Modes

| Language Switcher   | Draw Mode           | Resize Mode           |
| ------------------- | ------------------- | --------------------- |
| ![](/IMGS/lang.gif) | ![](/IMGS/draw.gif) | ![](/IMGS/resize.gif) |

### Utility Modes

| Rofi                | Cheatsheet                | Wallpaper                |
| ------------------- | ------------------------- | ------------------------ |
| ![](/IMGS/rofi.gif) | ![](/IMGS/cheatsheet.gif) | ![](/IMGS/wallpaper.gif) |
