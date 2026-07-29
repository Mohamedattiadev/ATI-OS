#!/usr/bin/env bash

# ================================
# Qtile Autostart – Optimized Build
# ================================
# Designed for: Fast login, low CPU usage, smooth window manager startup.
# Every section is labeled and explained.

# ---------------------------------------------------------
# 1. Pre-X configuration
# ---------------------------------------------------------
# If you're running inside a virtual machine, apply resolution fix.
# This runs ONLY in VM, and silently exits on normal hardware.

# (systemd-detect-virt | grep -qv none && ~/.config/qtile/scripts/set_vm_resolution.sh) &

# Touchpad scroll speed: pixels of finger travel per scroll unit (default 15).
# Higher = slower, smoother two-finger scrolling. Device id is not stable across
# boots, so resolve it by name.
touchpad_id=$(xinput list --id-only "AlpsPS/2 ALPS GlidePoint" 2>/dev/null)
[ -n "$touchpad_id" ] && xinput set-prop "$touchpad_id" "libinput Scrolling Pixel Distance" 40 2>/dev/null

# ---------------------------------------------------------
# 2. Core environment (ESSENTIAL FAST START)
# ---------------------------------------------------------
# These should start IMMEDIATELY without delays.
# Avoid slow apps here — keep this section lightweight.

(
  picom &          # Compositor (transparency, shadows, animations)
  dunst &          # Notification daemon
  nm-applet &      # Network tray icon
  blueman-applet & # Bluetooth tray icon
  copyq &          # Clipboard manager
  warpd &          # warpd daemon
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
  # These are long-running `while true` daemons, so each one is guarded by
  # a pgrep check before being started.
  #
  # The guards are worth keeping, but the reason originally written here
  # ("autostart.sh runs again on every qtile restart") is not accurate:
  # this script is invoked from @hook.subscribe.startup_once, and qtile
  # only fires startup_once when it has no restored state -- i.e. on a
  # true first start, NOT after Mod+Shift+R. What the guards actually
  # protect against is a re-login into an existing session and manual
  # re-runs of this script; both can leave a second copy alive, which is
  # what made one layout switch pop up three notifications at once.
  pgrep -f 'keyboard_layout_watcher$' >/dev/null || keyboard_layout_watcher &
  pgrep -f 'adhkar$' >/dev/null || adhkar &
  pgrep -f 'battery-events$' >/dev/null || battery-events &
  pgrep -f 'scripts/qdrop.py$' >/dev/null || python3 ~/.config/qtile/scripts/qdrop.py &
  pgrep -f 'scripts/qupdate.py$' >/dev/null || python3 ~/.config/qtile/scripts/qupdate.py --daemon &
  pgrep -f qdrop_watch.py >/dev/null || python3 ~/.config/qtile/scripts/qdrop_watch.py &
  # Homerow hint daemon. alt+shift+f only feels instant if the imports are
  # already paid for; the client falls back to starting this on demand.
  pgrep -f 'homerow-daemon$' >/dev/null || ~/Attia-Pro/Projects/Homerow_replika/homerow-daemon &
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
