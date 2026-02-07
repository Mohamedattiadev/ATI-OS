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

## 3. dcli (Declarative Package Management) (will be used in the next step)

All system packages are managed using **dcli**, allowing the entire environment to be defined declaratively.

- dcli repository:  
  https://gitlab.com/theblackdon/dcli

Package installation, system profiles, and optional components are all handled automatically during installation.

---

## 4. Installation (Single Command)
> I assume u have a fresh installed arch linux 
The entire system is bootstrapped using a single install script.

### Step 1: Clone the repository

```bash
git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles
```

### Step 2: Run the installer

```bash
cd ~/.dotfiles/installScripts
./install.sh
```

That’s it.

The script will automatically:

- Verify system assumptions (Arch, X11, no Wayland, TTY only)
- Install base system dependencies
- Install `yay` (pacman → manual fallback)
- Install `dcli`
- Deploy dotfiles using **GNU Stow**
- Install all packages via **dcli**
- Configure X11 input (touchpad)
- Create:
  - `~/.xinitrc`
  - `~/.Xmodmap`
- Configure Qtile startup
- Disable all display managers (TTY only)
- Configure lid-close behavior
- Install themes, icons, wallpapers
- Install auxiliary tools (Collector, Piper voices, image support, scripts)
- Apply final system tweaks

No additional manual steps are required.

---

## 5. Qtile Startup & Workflow

Qtile is started using `startx`.

Start the graphical session from TTY:

```bash
exec dbus-run-session startx
```
Or u can run  my own alias :

```bash
letsgo
```

Restart Qtile and reload fonts without logging out:

```bash
fc-cache -fv
qtile cmd-obj -o cmd -f restart
```

---

## 6. Videos

### 6.1 Main Videos (System Overview)

https://github.com/user-attachments/assets/aaec7215-c595-4ba3-bc65-a355b11edf05

https://github.com/user-attachments/assets/a7993cce-e04e-4168-9b32-b914d76539be

---

### 6.2 Feature Demonstrations

https://github.com/user-attachments/assets/6990186e-336d-48d4-8330-7c8ffd0f0a81

https://github.com/user-attachments/assets/fec68105-483d-4e7f-9573-6f43291c2d39

https://github.com/user-attachments/assets/acb09f1a-f268-4a68-ae23-819ecee27453

https://github.com/user-attachments/assets/9d8f53bb-eead-4e02-a844-3aba44fe9a34

https://github.com/user-attachments/assets/0189c230-a0df-4d8f-9687-ca8e5c00ed4a


---

## 7. Modes

### Window Manager Modes

| Language Switcher   | Draw Mode           | Resize Mode           |
| ------------------- | ------------------- | --------------------- |
| ![](/IMGS/lang.gif) | ![](/IMGS/draw.gif) | ![](/IMGS/resize.gif) |

### Utility Modes

| Rofi                | Cheatsheet                | Wallpaper                |
| ------------------- | ------------------------- | ------------------------ |
| ![](/IMGS/rofi.gif) | ![](/IMGS/cheatsheet.gif) | ![](/IMGS/wallpaper.gif) |
