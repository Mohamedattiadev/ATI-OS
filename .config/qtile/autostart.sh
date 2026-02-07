#!/usr/bin/env bash

# ================================
# Qtile Autostart – Optimized Build
# ================================
# Designed for: Fast login, low CPU usage, smooth window manager startup.
# Every section is labeled and explained.

COLORSCHEME=DoomOne
# ---------------------------------------------------------
# 1. Pre-X configuration
# ---------------------------------------------------------
# If you're running inside a virtual machine, apply resolution fix.
# This runs ONLY in VM, and silently exits on normal hardware.

# (systemd-detect-virt | grep -qv none && ~/.config/qtile/scripts/set_vm_resolution.sh) &

# ---------------------------------------------------------
# 2. Core environment (ESSENTIAL FAST START)
# ---------------------------------------------------------
# These should start IMMEDIATELY without delays.
# Avoid slow apps here — keep this section lightweight.

(
  dunst &          # Notification daemon
  nm-applet &      # Network tray icon
  blueman-applet & # Bluetooth tray icon
  copyq &          # Clipboard manager
  warpd &          # waprd daemon
  eww daemon       # EWW daemon
) &

# ---------------------------------------------------------
# 3. Light background apps
# ---------------------------------------------------------
# These are harmless and quick to start.
# No sleeps needed.

kdeconnectd &            # Phone integration
pamac-tray-icon-plasma & # Update notifier

# ---------------------------------------------------------
# 4. Heavy apps (DELAYED START)
# ---------------------------------------------------------
# Start heavy programs AFTER Qtile is fully loaded.
# Delay prevents lag and fan spikes during login.

# (
# sleep 10
# kitty & # Terminal
# pcmanfm & # File manager
# ) &

# ---------------------------------------------------------
# 5. start youtube on browser
# ---------------------------------------------------------

(
  sleep 8
  # The --qt-flag disable-gpu option is required to avoid startup crashes
  # on some systems (e.g. Arch Linux on Intel iGPUs such as the Dell Latitude E7270).
  qutebrowser \
    --qt-flag disable-gpu \
    --target window \
    https://yewtu.be/
) &

# ---------------------------------------------------------
# 6. Watchers / helper scripts
# ---------------------------------------------------------
# Start scripts safely after login to avoid race conditions.

(
  sleep 40
  keyboard_layout_watcher &
  adhkar &
  battery-events &
  # ~/.config/qtile/scripts/watch_todo_conflicts.sh &
) &

# ---------------------------------------------------------
# 7. Neovim Daemon (IMPORTANT)
# ---------------------------------------------------------
# Creates a tmux session that hosts Neovim as a server.
# Makes edits launch instantly in your environment.

# Always ensure tmux session "nvd" exists, but only with a shell
if ! tmux has-session -t nvd 2>/dev/null; then
  tmux new-session -d -s nvd
fi
