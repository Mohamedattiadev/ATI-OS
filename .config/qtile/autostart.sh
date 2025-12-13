#!/usr/bin/env bash

# ================================
# Qtile Autostart – Optimized Build
# ================================
# Designed for: Fast login, low CPU usage, smooth window manager startup.
# Every section is labeled and explained.

COLORSCHEME=DoomOne

# ---------------------------------------------------------
# 0. Pre-X configuration
# ---------------------------------------------------------
# If you're running inside a virtual machine, apply resolution fix.
# This runs ONLY in VM, and silently exits on normal hardware.
(systemd-detect-virt | grep -qv none && ~/.config/qtile/scripts/set_vm_resolution.sh) &

# ---------------------------------------------------------
# 1. Core environment (ESSENTIAL FAST START)
# ---------------------------------------------------------
# These should start IMMEDIATELY without delays.
# Avoid slow apps here — keep this section lightweight.

~/.screenlayout/layout.sh & # Apply monitor setup
# lxsession &
blueman-applet & # Bluetooth tray icon
picom &          # Compositor (transparency, animations)
dunst &          # Notification daemon
nm-applet &      # Network tray icon
copyq &          # Clipboard manager

# ---------------------------------------------------------
# 2. Wallpaper setup
# ---------------------------------------------------------
# Loads wallpaper without blocking the Qtile startup.

nitrogen --restore &

# ---------------------------------------------------------
# Additionals - CONKY
# ---------------------------------------------------------

### SETS CONKY STYLE BASED ON SCREEN RESOLUTION
# Checks screen resolution.  If 1080p or higher, then we use '01' conky.
# If less than 1080p (laptops?), then we use the smaller '02' conky.

# if [[ $resolutionHeight -ge 1080 ]]; then
# 	killall conky || echo "Conky not running."
# 	# sleep 2
# 	conky -c "$HOME"/.config/conky/qtile/01/"$COLORSCHEME".conf || echo "Couldn't start conky."
# elif [[ $resolutionHeight -lt 1080 ]]; then
# 	killall conky || echo "Conky not running."
# 	# sleep 2
# 	conky -c "$HOME"/.config/conky/qtile/02/"$COLORSCHEME".conf || echo "Couldn't start conky."
# else
# 	killall conky || echo "Conky not running."
# 	# sleep 2
# 	conky -c "$HOME"/.config/conky/qtile/02/"$COLORSCHEME".conf || echo "Couldn't start conky."
# fi

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
# 5. Optional Brave auto-start (comment out if you don't want it)
# ---------------------------------------------------------
# Starts Brave after system settles.

(
  sleep 8
  brave --new-window https://www.youtube.com \
    --disable-sync \
    --disable-breakpad \
    --disable-features=Translate,AutofillServerCommunication \
    --no-first-run \
    --process-per-site
) &

# ---------------------------------------------------------
# 6. Watchers / helper scripts
# ---------------------------------------------------------
# Start scripts safely after login to avoid race conditions.

(
  sleep 40
  ~/.config/qtile/scripts/keyboard_layout_watcher.sh &
  ~/.config/qtile/scripts/watch_todo_conflicts.sh &
) &

# ---------------------------------------------------------
# 7. Late utilities
# ---------------------------------------------------------
# Gromit-mpx (screen annotation tool) starts much later to avoid interfering
# with early session setup.

(
  sleep 120
  gromit-mpx &
) &

# ---------------------------------------------------------
# 8. Neovim Daemon (IMPORTANT)
# ---------------------------------------------------------
# Creates a tmux session that hosts Neovim as a server.
# Makes edits launch instantly in your environment.

# (
#   sleep 20
#   if ! tmux has-session -t nvd 2>/dev/null; then
#     tmux new-session -s nvd -d "nvim --listen /tmp/nvimsocket"
#   fi
# ) &

# Always ensure tmux session "nvd" exists, but only with a shell
if ! tmux has-session -t nvd 2>/dev/null; then
  tmux new-session -d -s nvd
fi
