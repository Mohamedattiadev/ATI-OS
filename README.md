# Qtile X11 Arch Linux Dotfiles

A minimal, reproducible **Arch Linux + Qtile (X11)** configuration focused on performance, keyboard-driven workflows, and long-term maintainability.  
This repository documents both the configuration itself and the workflow used to deploy it consistently across systems.

> **Important note**  
> This setup is based on [Distrotube's](https://www.youtube.com/c/DistroTube/videos) Qtile configuration and has been extended with my own customization, workflow adjustments, and personal preferences.  
> While it follows the general structure and philosophy of the original configuration, the final implementation reflects my individual use case and design choices.

---

## 1. Assumptions

Before proceeding, ensure that your system matches the following requirements:

1. Arch Linux (clean base installation)
2. X11 only (Wayland is not supported)
3. No display manager (TTY + `startx`)
4. Package and system provisioning handled via **dcli**

Systems that do not meet these assumptions may require manual intervention.

---

## 2. Project Overview

This repository contains my personal **Qtile + X11** dotfiles.  
The setup is designed to be:

1. Declarative and reproducible
2. Easy to deploy using symbolic links
3. Independent of manual package installation steps

### Scope of this README

This document explains:

1. How to bootstrap the environment
2. How **dcli** is used for package management
3. How dotfiles are deployed
4. Required X11 configuration files
5. Qtile startup and restart workflow
6. Visual demonstrations of the system and its modes

---

## 3. dcli (Declarative Package Management)

All system packages are managed using **dcli**, allowing the entire environment to be defined declaratively.

- dcli repository:  
  https://gitlab.com/theblackdon/dcli

---

### 3.1 Optional: Installing yay / yay-bin

If `yay` is not available:

```bash
sudo pacman -S yay
```

If AUR access fails, install `yay-bin` manually:

> If `git` is not installed:
> ```bash
> sudo pacman -S git
> ```

```bash
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
```

---

### 3.2 Installing dcli

**Method 1 (AUR):**

```bash
yay -S dcli-arch-git
```

**Method 2 (Manual):**

```bash
git clone https://gitlab.com/theblackdon/dcli.git
cd dcli
sudo make install
```

Verify installation:

```bash
dcli --help
```

---

## 4. Cloning the Dotfiles Repository

Clone the dotfiles into your home directory:

```bash
git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles
cd ~/.dotfiles
```

This directory will act as the root for all managed configuration files.

---

## 5. Dotfiles Deployment

All configuration files are organized to work with **GNU Stow**.

> Currently, the repository mainly contains `.config` entries.  
> A dedicated install script will be added later to automate this step further.

```bash
./install.sh
```

---

## 6. Installing Packages via dcli

Once dcli is installed and the dotfiles are cloned:

```bash
dcli sync
```

This command installs all required packages and applies the predefined system profiles.

---

## 7. Touchpad Configuration (X11)

Touchpad behavior is configured at the Xorg level.

Create the file:

`/etc/X11/xorg.conf.d/30-touchpad.conf`

```conf
Section "InputClass"
    Identifier "Touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
EndSection
```

This enables tap-to-click functionality.

---

## 8. Xinit and Qtile Startup

Qtile is started using `startx`.

Create the file:

`~/.xinitrc`

```sh
#!/bin/sh

unset SESSION_MANAGER

setxkbmap -layout us -option
xmodmap ~/.Xmodmap

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=qtile
export XDG_SESSION_DESKTOP=qtile

systemctl --user import-environment   DISPLAY XAUTHORITY   XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP

picom &
exec qtile start
```

Start the graphical session:

```bash
exec dbus-run-session startx
```

---

## 9. Keymap Configuration

To ensure consistent Alt key behavior, create:

`~/.Xmodmap`

```bash
clear mod1
add mod1 = Alt_L Alt_R
```

This file is loaded automatically during session startup.

---

## 10. Restarting Qtile

To reload fonts and restart Qtile without logging out:

```bash
fc-cache -fv
qtile cmd-obj -o cmd -f restart
```

---

## 11. Videos

### 11.1 Main Videos (Overall System Overview)

https://github.com/user-attachments/assets/aaec7215-c595-4ba3-bc65-a355b11edf05 

https://github.com/user-attachments/assets/a7993cce-e04e-4168-9b32-b914d76539be 


--- 

### 11.2 Feature Demonstrations

https://github.com/user-attachments/assets/6990186e-336d-48d4-8330-7c8ffd0f0a81

https://github.com/user-attachments/assets/fec68105-483d-4e7f-9573-6f43291c2d39 

https://github.com/user-attachments/assets/acb09f1a-f268-4a68-ae23-819ecee27453

https://github.com/user-attachments/assets/9d8f53bb-eead-4e02-a844-3aba44fe9a34 

---






## 12. Modes

### Window Manager Modes

| Language Switcher Mode | Draw Mode | Resize Mode |
|------------------------|-----------|-------------|
| ![](/IMGS/lang.gif) | ![](/IMGS/draw.gif) | ![](/IMGS/resize.gif) |

### Utility Modes

| Rofi Mode | Cheatsheet Mode | Wallpaper Mode |
|-----------|-----------------|----------------|
| ![](/IMGS/rofi.gif) | ![](/IMGS/cheatsheet.gif) | ![](/IMGS/wallpaper.gif) |

---

## 13. Notes

1. This setup intentionally avoids display managers.
2. KDE may coexist alongside Qtile if installed.
3. Xorg uses the built-in `modesetting` driver rather than legacy GPU drivers.
