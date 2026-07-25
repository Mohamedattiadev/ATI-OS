# Qtile X11 Arch Linux Dotfiles

A minimal, reproducible **Arch Linux + Qtile (X11)** configuration focused on performance, keyboard-driven workflows, and long-term maintainability.

This repository documents **both** the configuration itself and the **automated bootstrap workflow** used to deploy it consistently across systems.

> **Important note**  
> This setup is based on [Distrotube’s](https://www.youtube.com/c/DistroTube/videos) Qtile configuration and has been extended with my own customization, workflow adjustments, and personal preferences.  
> While it follows the general structure and philosophy of the original configuration, the final implementation reflects my individual use case and design choices.

---

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

### Step 1: Clone

```bash
git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles
```

### Step 2: Run the installer

```bash
cd ~/.dotfiles/installScripts
./install.sh
```

Done. One command. Bootstrap covers:

| Step | What                                                          |
| ---- | ------------------------------------------------------------- |
| 1    | Sanity checks (Arch, X11, dotfiles present)                   |
| 2    | Bootstrap pkgs (git, stow, xorg-server, base-devel)           |
| 3    | Build `yay` from AUR if absent                                |
| 4    | Install `dcli-arch-git`                                       |
| 5    | Stow dotfiles into `$HOME`                                    |
| 6    | Sync `arch-config` host file to current username              |
| 7    | **`dcli sync`** — installs every declared pkg + flatpak       |
| 8    | Cargo tools (`pomodoro-tui`)                                  |
| 9    | Install AtiScriptsV1 to `/usr/local/bin`                      |
| 10   | Touchpad config (`/etc/X11/xorg.conf.d/30-touchpad.conf`)     |
| 11   | Write `~/.xinitrc` (starts qtile + picom + xcape)             |
| 12   | Write `~/.Xmodmap` (Caps hold = Alt, xcape restores tap Caps) |
| 13   | Lid close = ignore (`systemd-logind`)                         |
| 14   | Suppress VIPS warnings (kitty+nvim image support)             |
| 15   | Flatpak + Collector                                           |
| 16   | Download Piper voices (EN + DE)                               |
| 17   | Passwordless sudo                                             |
| 18   | Fix dotfiles ownership                                        |
| 19   | Disable all display managers                                  |
| 20   | Install candy-icons theme                                     |
| 21   | Clone wallpaper collection                                    |
| 22   | System speed tweaks (`speed_boost.sh`)                        |
| 23   | Theme system (pywal + palette precompile + brave-flags + init)|
| 23b  | Chrome/chromium theme policy (sign key + enterprise force-install) |

No manual follow-up. Everything in `.config` works on first `startx`.

---

## 5. Qtile Startup & Workflow

Start X session from TTY:

```bash
startx
# or the alias:
letsgo
```

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

**Modes:** `doomone` · `dracula` · `gruvbox` · `nord` · `tokyonight` · `catppuccin` · `wal`

```bash
theme-apply doomone   # any preset
theme-apply wal       # pywal from current wallpaper
theme-toggle          # cycle to next preset
```

Wal mode uses a precompiled cache. `wal-precompile` walks
`~/Pictures/Wallpapers/` and produces per-image palettes at
`~/.cache/qtile/palettes/<basename>.json`. Every palette is forced to a
doomone-quality bar (WCAG AAA bg/fg, WCAG AA per-accent, hue-spread
guaranteed). See `.config/qtile/WAL_PRECOMPILE_REPORT.md`.

**Coverage per apply**

| Consumer | Reload mechanism |
|---|---|
| kitty | `set-colors --all` per live socket + SIGUSR1 |
| rofi | symlink `current-palette.rasi` swap |
| dunst | render `dunstrc.tmpl` + restart |
| qtile | `restart` (detached so caller doesn't deadlock) |
| gtk 3/4 | `@import` overlay at `~/.cache/qtile/gtk-wal.css` |
| qutebrowser | inline `<style>` + `--accent` CSS var, `:config-source` + `:restart` |
| nvim | fs_event on `~/.cache/qtile/theme_mode` re-sources scheme (Snacks dashboard uses dominant hue) |
| brave | `--load-extension` reads live `manifest.json` on relaunch (id matches via embedded `key`) |
| chrome / chromium | Enterprise policy `force_installed` from local `updates.xml`; `.crx` repacked + Preferences purged each apply so install lands immediately |
| papirus folders | `papirus-folders -C <hue-match> -u` |

**Palette semantics** — `wal-precompile` generates 6-slot hue-concentrated palettes:
`color1` urgent (always warm), `color2` dominant (main wallpaper hue),
`color3` warm-fill, `color4` cool-fill, `color5` complement, `color6` info/cyan.
qtile bar accents pin to `color2`; test harness at
`.config/qtile/scripts/wal-visual-test.py` validates 12 hue buckets end-to-end.

Wallpaper change auto-reapplies wal mode (`dm-setbg` + `WallpaperPopup`
both invoke `theme-apply wal` on a bg thread so qtile stays responsive).

**Rofi UI stack** — all `.rasi` themes import a shared `base.rasi`
(doom-one flavor, radius 12, palette-driven). Overrides are layout-only
(width, height, lines). Rofi scripts source
`.config/AtiScriptsV1/rofi_common.sh` for palette parsing, wayland-safe
clipboard, dep checks, and a compact `rofi_confirm` prompt. Notable:
`rofi-kill` shows PID + process + window title (via `wmctrl -lp` + PPID
walk for browser subprocs) in aligned columns with vertical dividers.

---

## 9. Videos

### 9.1 Main Videos (System Overview)

https://github.com/user-attachments/assets/aaec7215-c595-4ba3-bc65-a355b11edf05

https://github.com/user-attachments/assets/a7993cce-e04e-4168-9b32-b914d76539be

---

### 9.2 Feature Demonstrations

https://github.com/user-attachments/assets/6990186e-336d-48d4-8330-7c8ffd0f0a81

https://github.com/user-attachments/assets/fec68105-483d-4e7f-9573-6f43291c2d39

https://github.com/user-attachments/assets/acb09f1a-f268-4a68-ae23-819ecee27453

https://github.com/user-attachments/assets/9d8f53bb-eead-4e02-a844-3aba44fe9a34

https://github.com/user-attachments/assets/0189c230-a0df-4d8f-9687-ca8e5c00ed4a


---

## 10. Modes

### Window Manager Modes

| Language Switcher   | Draw Mode           | Resize Mode           |
| ------------------- | ------------------- | --------------------- |
| ![](/IMGS/lang.gif) | ![](/IMGS/draw.gif) | ![](/IMGS/resize.gif) |

### Utility Modes

| Rofi                | Cheatsheet                | Wallpaper                |
| ------------------- | ------------------------- | ------------------------ |
| ![](/IMGS/rofi.gif) | ![](/IMGS/cheatsheet.gif) | ![](/IMGS/wallpaper.gif) |
