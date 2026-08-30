#!/usr/bin/env bash
# reset-pc.sh — the Hyprland side of qtile's ati-reset-pc hard reset.
#
# qtile's mod+shift+F5 runs ~/.config/AtiScriptsV1/system/ati-reset-pc: pkill -TERM
# then pkill -KILL a list of apps, wmctrl -k every remaining window,
# restart pipewire/pipewire-pulse/wireplumber/dunst/picom/warpd, restart
# qtile itself (which is qtile's bar and widgets too), and re-run
# autostart.sh.
#
# power-ctl.sh's "refresh" row already covers the LIGHT half of that — see
# its header comment — by running `hyprctl reload`, which was chosen there
# over ati-reset-pc because ati-reset-pc would do harm under Wayland: restart a
# compositor (picom) that does not exist here, and re-run an X11
# autostart.sh on top of a Wayland session. This script is the other half —
# the actual app-killing hard reset, ported rather than dropped — adapted
# wherever ati-reset-pc's steps do not carry over one for one:
#
#   apps      byte-for-byte the same list ati-reset-pc kills. None of it is
#             X11-specific, so nothing here needed changing.
#
#   windows   wmctrl does not see Wayland surfaces at all. `hyprctl clients
#             -j` + `dispatch closewindow` is the equivalent: it walks the
#             same "everything still mapped" list wmctrl -k did, without
#             touching layer-shell surfaces (the bar, hyprlock), which is
#             the behaviour actually wanted here — wmctrl -k did not touch
#             qtile's own bar either, for the same reason: a WM bar was
#             never a wmctrl-visible "window" either.
#
#   services  pipewire / pipewire-pulse / wireplumber carry over unchanged.
#             dunst and picom are DROPPED, not forgotten: dunst is no
#             longer autostarted in this session (the island owns
#             org.freedesktop.Notifications — see autostart.conf's block on
#             this), so restarting it here would make it grab the
#             notification bus name out from under the island, which
#             autostart.conf documents as the one ordering hazard this
#             setup has. picom does not exist under Hyprland — Hyprland IS
#             the compositor. warpd is dropped too: grepping this session's
#             config for it turns up nothing, so it was never part of it.
#
#   the WM    restarting qtile is also restarting qtile's own bar and
#             widgets, which is the actual point of that step — a stuck
#             tray icon or wedged widget comes back clean. This session's
#             bar is a SEPARATE process (the island or the topbar, per
#             ~/.cache/bar-mode), not part of the compositor, and
#             restarting Hyprland itself is not something a script running
#             inside the session can do short of ending it — Hyprland is
#             the display server here, not a WM riding on a separate X
#             server the way qtile rides on Xorg. So the equivalent of
#             "restart qtile" is `bar-switch restart`: it stops and
#             relaunches whichever bar is actually running, through the
#             same tested stop/start paths `bar-switch native`/`island`
#             already use — see AtiScriptsV1/bar-switch. `hyprctl reload`
#             runs after it, matching the "refresh" row and covering
#             everything reload does touch that a bar restart does not.
set -uo pipefail

notify-send "Hyprland" "⚡ Hard reset started…"

# --------------------------------------------------
# 1. Gracefully terminate known user apps (Lv1)
# --------------------------------------------------
APPS=(
  firefox brave chromium google-chrome qutebrowser
  kitty alacritty wezterm
  code zed obsidian
  telegram-desktop discord anki
  vlc mpv thunderbird
  pcmanfm-qt pcmanfm nautilus
)

for app in "${APPS[@]}"; do
  pkill -TERM -u "$USER" "$app" 2>/dev/null || true
done

sleep 2

# --------------------------------------------------
# 2. Force kill leftovers (Lv1)
# --------------------------------------------------
for app in "${APPS[@]}"; do
  pkill -KILL -u "$USER" "$app" 2>/dev/null || true
done

# --------------------------------------------------
# 3. Close *all* remaining windows — wmctrl's Wayland equivalent
# --------------------------------------------------
if command -v hyprctl >/dev/null && command -v jq >/dev/null; then
  hyprctl -j clients 2>/dev/null | jq -r '.[].address' | while read -r addr; do
    hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 || true
  done
fi

# --------------------------------------------------
# 4. Restart the services that carry over from ati-reset-pc (Lv2)
# --------------------------------------------------
SYSTEMD_SERVICES=(
  pipewire
  pipewire-pulse
  wireplumber
)

for svc in "${SYSTEMD_SERVICES[@]}"; do
  systemctl --user restart "$svc" 2>/dev/null || true
done

# --------------------------------------------------
# 5. Restart the bar — the equivalent of restarting qtile (Lv2 - THE MAGIC)
# --------------------------------------------------
bar-switch restart 2>/dev/null || true

# --------------------------------------------------
# 6. Reload Hyprland's own config — same as the "refresh" row
# --------------------------------------------------
hyprctl reload || true

# --------------------------------------------------
# 7. Final cleanup
# --------------------------------------------------
sync
notify-send "Hyprland" "✨ Hard reset complete"
