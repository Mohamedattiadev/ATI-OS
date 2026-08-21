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
# boots, so resolve it dynamically.
#
# This used to match the literal name "AlpsPS/2 ALPS GlidePoint" -- this
# laptop's touchpad. The lookup is guarded, so on any other machine it just
# found nothing and the tuning silently never applied: scrolling felt
# different on a new PC with no error to explain why. Match on the libinput
# property instead, which every touchpad has and no mouse does.
for touchpad_id in $(xinput list --id-only 2>/dev/null); do
  xinput list-props "$touchpad_id" 2>/dev/null \
    | grep -q "libinput Scrolling Pixel Distance" || continue
  xinput set-prop "$touchpad_id" "libinput Scrolling Pixel Distance" 40 2>/dev/null
done

# ---------------------------------------------------------
# 2. Core environment (ESSENTIAL FAST START)
# ---------------------------------------------------------
# These should start IMMEDIATELY without delays.
# Avoid slow apps here — keep this section lightweight.

# Per-GPU picom flags, written by the wizard's `gpu` module from the PCI
# IDs of this machine (see step_gpu). Untracked and per-host: NVIDIA needs
# use-damage off or animations smear, Intel and AMD do not. Absent file =
# no flags, which is the correct default.
PICOM_GPU_FLAGS=""
# shellcheck source=/dev/null
[ -f "$HOME/.config/picom/gpu.env" ] && . "$HOME/.config/picom/gpu.env"

(
  # shellcheck disable=SC2086  # deliberate word splitting: flags or nothing
  picom $PICOM_GPU_FLAGS &   # Compositor (transparency, shadows, animations)
  dunst &          # Notification daemon
  # --no-agent: keep the tray icon, drop the secret-agent role. Without it
  # nm-applet answers NetworkManager's password requests, so a wrong PSK
  # typed into the WiFi popup (Mod+p n) pops nm-applet's own GTK dialog on
  # top of it. With it, the popup owns the whole flow and re-asks itself.
  nm-applet --no-agent &  # Network tray icon (no password dialogs)
  blueman-applet & # Bluetooth tray icon
  copyq &          # Clipboard manager
  eww daemon       # EWW daemon
) &

# ---------------------------------------------------------
# 2b. The bar — qtile's own, or the Tide Island
# ---------------------------------------------------------
# Which bar this session wears is a SAVED CHOICE, not a property of the
# session: ~/.cache/bar-mode is written by AtiScriptsV1/bar-switch and read by
# both this session and the Hyprland one, so picking the island in Hyprland
# and then logging into qtile lands you on the island here too.
#
# Only the PROCESS is started here. Hiding qtile's own bars is config.py's
# job and it already does it — apply_bar_mode() reads the same file and the
# startup hooks call it, so there is nothing to coordinate from out here and
# nothing that a `mod+shift+r` could undo.
#
# Ordering against dunst above is load-bearing, and island.sh has the long
# version: the island SERVES org.freedesktop.Notifications, a well-known bus
# name has exactly one owner, and dunst has a D-Bus activation file — so
# whichever takes the name first keeps it. island.sh clears dunst off the bus
# itself immediately before launching, which is why this can safely come after
# the block that starts dunst rather than having to race it.
#
# The island is deliberately NOT guarded on Wayland-ness. Quickshell picks its
# own backend, and the fork's windows were split per backend precisely so this
# works under X11 — see
# quickshell/tide-island-fork/qml/common/BackendSurface.md.
if [ "$(cat "$HOME/.cache/bar-mode" 2>/dev/null | tr -d '[:space:]')" = "island" ]; then
  "$HOME/.config/hypr/scripts/island.sh" >/dev/null 2>&1 &
else
  # ---------------------------------------------------------
  # 2c. popups.qml — resident even when qtile wears its OWN bar
  # ---------------------------------------------------------
  # Reported: "i want the hyperland theme and wallpaper chaning thing
  # animaiton and logic works the same in qtile — this is too important."
  #
  # theme-animate (~/.local/bin/theme-animate) is the shared entry point
  # every theme/wallpaper change is supposed to go through. It tries `tide
  # applyThemeAnimated <mode>` over IPC against the island first, THEN
  # against popups.qml, and only falls back to a plain, non-animated
  # theme-apply if neither answers. hypr/scripts/topbar.sh already starts
  # popups.qml for exactly this reason whenever the island is not the
  # active bar (its own comment: "started here rather than on demand...
  # resident, it answers at once") — this qtile session had no equivalent,
  # so under qtile's own bar theme-animate's probe failed both ways, every
  # time, and every theme/wallpaper change was a hard cut.
  #
  # qtile keeps its OWN popups (config.py imports WallpaperPopup,
  # BluetoothPopup, DisplayPopup — see popups/*.py) and this is not meant
  # to replace them: their keybindings still call the Python ones
  # directly, unchanged. This process exists solely so `tide
  # applyThemeAnimated` has somewhere to land; its OTHER IPC targets are
  # simply unused here, which costs nothing (an unopened Loader has no
  # window and does not poll).
  #
  # Guarded the same way topbar.sh guards it — `-p <dir>` matched by
  # EQUALITY on the argv, not `pgrep -f`, which cannot tell `-p <dir>` from
  # `-p <dir>/popups.qml` apart — so re-running this script (or logging in
  # twice without a full logout) does not stack a second instance.
  POPUPS_ENTRY="$HOME/.config/quickshell/tide-island-fork/popups.qml"
  if [ -f "$POPUPS_ENTRY" ] && ! ps -eo args= | awk -v want="$POPUPS_ENTRY" \
      '!/awk/ { for (i = 1; i < NF; i++) if ($i == "-p" && $(i + 1) == want) { found = 1 } }
       END { exit !found }'; then
    setsid -f quickshell -p "$POPUPS_ENTRY" >/dev/null 2>&1 &
  fi
fi

# ---------------------------------------------------------
# 3. Light background apps
# ---------------------------------------------------------
# These are harmless and quick to start.
# No sleeps needed.

kdeconnectd & # Phone integration
# polkitd runs as a system service but has no way to ask the user anything on
# its own -- that is an authentication agent's job, and a bare qtile session
# ships none. Without this, mounting an internal partition from pcmanfm-qt's
# Places pane is refused with no password prompt and no error.
lxqt-policykit-agent &
# pamac-tray-icon-plasma was the update notifier here. It is a Manjaro
# package, has never been installed on this Arch box, and was failing
# silently into the background on every login. The update notifier is
# now qupdate.py --daemon, started in the qtile-owned block below.

# ---------------------------------------------------------
# 4. Heavy apps (DELAYED START)
# ---------------------------------------------------------
# Start heavy programs AFTER Qtile is fully loaded.
# Delay prevents lag and fan spikes during login.

# (
# sleep 10
# kitty & # Terminal
# pcmanfm-qt & # File manager
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
  pgrep -f 'ati-keyboard-layout-watcher$' >/dev/null || ati-keyboard-layout-watcher &
  pgrep -f 'adhkar$' >/dev/null || adhkar &
  pgrep -f 'battery-events$' >/dev/null || battery-events &
  pgrep -f 'scripts/qdrop.py$' >/dev/null || python3 ~/.config/qtile/scripts/qdrop.py &
  pgrep -f 'scripts/qupdate.py$' >/dev/null || python3 ~/.config/qtile/scripts/qupdate.py --daemon &
  pgrep -f qdrop_watch.py >/dev/null || python3 ~/.config/qtile/scripts/qdrop_watch.py &
  # hintium hint daemon. alt+shift+f only feels instant if the imports are
  # already paid for; the client falls back to starting this on demand.
  #
  # Resolved through PATH, like every other line here, rather than named as a
  # checkout path: the wizard symlinks the entry points into /usr/local/bin,
  # and the hardcoded path this used to carry broke the moment the project
  # directory was renamed -- silently, because a `&`-backgrounded command that
  # does not exist says nothing to anyone.
  pgrep -f 'hintium-daemon$' >/dev/null || hintium-daemon &
  # ~/.config/qtile/scripts/watch_todo_conflicts.sh &
) &

# ---------------------------------------------------------
# 6b. First-run onboarding tour
# ---------------------------------------------------------
# No-op unless wizard.sh armed it, so this costs one file test on every
# other login. It does its own waiting for the eww daemon started in
# section 2 -- backgrounded here so a slow daemon never holds up the rest
# of autostart.
#
# Absolute path fallback: on a very first login the ati-scripts step may
# not have symlinked into /usr/local/bin yet (or PATH is not populated for
# a non-interactive shell), and this is precisely the login that has a
# tour to show.
(
  if command -v onboarding-first-run >/dev/null 2>&1; then
    onboarding-first-run
  else
    "$HOME/.config/AtiScriptsV1/onboarding-first-run"
  fi
) &

# ---------------------------------------------------------
# 6c. Boot splash catch-up
# ---------------------------------------------------------
# theme-apply hands the boot screen to `boot-splash autosync`, which waits
# out a debounce before rerunning mkinitcpio. That waiting call is a
# backgrounded child of theme-apply and the only thing that knows a sync is
# owed -- so a reboot inside the window loses it silently and permanently.
# Which is the normal case, not the unlucky one: you change the theme, then
# reboot to look at the new boot screen.
#
# `catchup` re-derives the same question from disk (what the initramfs was
# built from vs what the palette says now) instead of remembering it, so a
# lost sync costs one login rather than being lost for good. It is two file
# reads and an exit when the boot screen is already current, which is every
# login but the one after a theme change.
(
  command -v boot-splash >/dev/null 2>&1 && boot-splash catchup
) >/dev/null 2>&1 &

# ---------------------------------------------------------
# 7. Neovim Daemon (IMPORTANT)
# ---------------------------------------------------------
# Creates a tmux session that hosts Neovim as a server.
# Makes edits launch instantly in your environment.

# Always ensure tmux session "nvd" exists, but only with a shell
if ! tmux has-session -t nvd 2>/dev/null; then
  tmux new-session -d -s nvd
fi
