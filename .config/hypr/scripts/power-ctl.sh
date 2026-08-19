#!/usr/bin/env bash
#
# power-ctl.sh — the actions behind the island's power menu.
#
# FORK/MIGRATION: this is the Hyprland side of qtile's `dm-logout -r`, which
# was bound at config.py ~6129 to mod+shift+q and again as `q` inside the
# Rofi chord. dm-logout is /usr/local/bin/dm-logout, a dmscripts rofi menu;
# its option list is transcribed here VERBATIM and in its own order:
#
#     Lock screen
#     Logout (terminate session)
#     Refresh the PC
#     Reboot
#     Shutdown
#     Suspend
#     Quit
#
# Two of the seven do NOT port as written, and both are recorded rather than
# quietly substituted:
#
#   1. LOCK. dm-logout runs "$DMLOCKER", which ~/.config/dmscripts/config
#      sets to `betterlockscreen -l`. betterlockscreen is a wrapper around
#      i3lock, which is X11-native: it grabs the X keyboard and maps an
#      override-redirect X window. On Wayland it cannot lock this session at
#      all. This session's locker is hyprlock, reached the way binds.conf
#      already reaches it at $mod SHIFT X — `loginctl lock-session`, so that
#      idle-locking and menu-locking go through one path and cannot
#      disagree.
#
#   2. REFRESH. dm-logout runs ~/.config/AtiScriptsV1/reset_PC as its single
#      "Refresh the PC" row. Read before porting it, and it is not a config
#      reload: it pkill -TERM then pkill -KILL's 20 named applications
#      (browsers, terminals, editors, Obsidian, Anki, mpv...), restarts
#      picom, runs `qtile cmd-obj -o cmd -f restart` with a
#      `pkill -HUP qtile` fallback, and finally re-runs
#      ~/.config/qtile/autostart.sh. Run as-is in a Hyprland session that
#      is: your work closed, a compositor that is not running HUPed, and
#      qtile's X11 autostart executed on top of Wayland. It would do harm
#      and could not do the thing it was for — so it is not what the
#      "refresh" row below runs.
#
#      Instead the one dm-logout row became TWO here. `refresh` runs
#      `hyprctl reload`, which binds.conf already documents at $mod SHIFT R:
#      "Hyprland reloads config without touching windows at all, which is
#      strictly better" — the light half of what reset_PC gave you.
#      `hardreset` is the actual app-killing, service-restarting reset_PC
#      behaviour, ported rather than dropped: hypr/scripts/reset-pc.sh
#      under Wayland, the genuine reset_PC still under X11. See that
#      script's header for the adaptation, step by step.
#
# The other four (logout, reboot, shutdown, suspend) are byte-for-byte what
# dm-logout runs.
#
# Every action is spelled out in one place so the panel does not have to
# carry shell strings, and so each can be checked from a terminal without
# opening the menu:
#
#     ./power-ctl.sh --list          # the actions, as JSON
#     ./power-ctl.sh --dry-run lock  # print the command, run nothing
#
set -euo pipefail

# ---------------------------------------------------------------------------
#  WHICH SESSION, because three of these seven are compositor-specific
# ---------------------------------------------------------------------------
# This file was written for Hyprland and moved with the island to the qtile
# session, where two actions were silently wrong (a third, hardreset, was
# added later and was session-keyed from the start):
#
#   lock     `loginctl lock-session` only locks anything if something is
#            LISTENING for logind's Lock signal. Hyprland has hypridle doing
#            that (autostart.conf), and the qtile session has nothing at all —
#            verified: no hypridle, no xss-lock, no xautolock, no
#            light-locker running, and `LockedHint=no` after the call. So the
#            island's "Lock screen" ran, returned 0, and left the screen
#            unlocked. Reported as "the lock screen, when I open its popup and
#            click, is not making the lock screen".
#
#            betterlockscreen is installed and is X11-native (an i3lock
#            wrapper), so under X11 it is called DIRECTLY. The header above
#            says betterlockscreen "could not port verbatim" — that is true of
#            the WAYLAND session and is why loginctl is right there; it was
#            never true of this one.
#
#   refresh  `hyprctl reload` is not a thing under qtile. qtile's own
#            equivalent, and the one its config already binds to mod+shift+r,
#            is reload_config over its IPC.
#
#   hardreset  the genuine reset_PC script under X11 — dm-logout's own
#            "Refresh the PC" target, unchanged — versus its Wayland-safe
#            rewrite, hypr/scripts/reset-pc.sh, under Hyprland.
#
# Keyed on WAYLAND_DISPLAY, the same test shell.qml and the island's QML use,
# so this cannot disagree with the shell about which session it is in.
on_x11() { [[ -z "${WAYLAND_DISPLAY:-}" ]]; }

# The command for each action, in one table. Kept as a function rather than
# an associative array so `logout` can carry its two-branch fallback without
# being a string that has to be eval'd.
command_for() {
    case "$1" in
    lock)
        if on_x11; then
            printf 'betterlockscreen -l'
        else
            printf 'loginctl lock-session'
        fi
        ;;
    logout)
        # dm-logout's own branch, transcribed: the session id when the
        # environment has one, the seat when it does not.
        if [[ -n "${XDG_SESSION_ID:-}" ]]; then
            printf 'loginctl terminate-session %s' "$XDG_SESSION_ID"
        else
            printf 'loginctl terminate-seat seat0'
        fi
        ;;
    refresh)
        if on_x11; then
            printf 'qtile cmd-obj -o cmd -f reload_config'
        else
            printf 'hyprctl reload'
        fi
        ;;
    hardreset)
        # The real reset_PC port — see hypr/scripts/reset-pc.sh's header for
        # why this is a separate row from `refresh` rather than what
        # `refresh` runs: reset_PC kills apps and restarts services, which
        # `hyprctl reload`/reload_config deliberately do not. X11 still has
        # the genuine article; Wayland gets its adapted twin.
        if on_x11; then
            printf '%s/AtiScriptsV1/reset_PC' "$HOME/.config"
        else
            printf '%s/hypr/scripts/reset-pc.sh' "$HOME/.config"
        fi
        ;;
    reboot)   printf 'systemctl reboot' ;;
    shutdown) printf 'systemctl poweroff' ;;
    suspend)  printf 'systemctl suspend' ;;
    *)        return 1 ;;
    esac
}

# --list exists so the panel and this script cannot drift about what the
# actions ARE, the same way ModeKeysLayer takes its rows from cheatsheet.py
# rather than carrying a copy. `confirm` is data, not styling: dm-logout
# asks "No/Yes" before refresh, logout, reboot, shutdown and suspend, and
# asks nothing before locking. That asymmetry is correct and is preserved —
# locking is the one action here that costs nothing to undo.
list_actions() {
    # Detail strings are what the panel draws under each row, so they have to
    # name the command this session will actually run -- see command_for().
    local lock_detail refresh_detail hardreset_detail
    if on_x11; then
        lock_detail='betterlockscreen -l'
        refresh_detail='qtile reload_config'
        hardreset_detail='~/.config/AtiScriptsV1/reset_PC'
    else
        lock_detail='loginctl lock-session → hyprlock'
        refresh_detail='hyprctl reload'
        hardreset_detail='~/.config/hypr/scripts/reset-pc.sh'
    fi
    # Quoted heredoc (no brace escaping), so the session-dependent fields
    # are filled in afterwards rather than expanded inline.
    cat <<'JSON' | sed -e "s|__LOCK_DETAIL__|$lock_detail|" \
                       -e "s|__REFRESH_DETAIL__|$refresh_detail|" \
                       -e "s|__HARDRESET_DETAIL__|$hardreset_detail|"
{
  "actions": [
    { "id": "lock",      "label": "Lock screen",  "confirm": false,
      "detail": "__LOCK_DETAIL__" },
    { "id": "logout",    "label": "Log out",      "confirm": true,
      "detail": "loginctl terminate-session" },
    { "id": "refresh",   "label": "Reload config","confirm": true,
      "detail": "__REFRESH_DETAIL__" },
    { "id": "hardreset", "label": "Hard reset",   "confirm": true,
      "detail": "__HARDRESET_DETAIL__" },
    { "id": "reboot",    "label": "Reboot",       "confirm": true,
      "detail": "systemctl reboot" },
    { "id": "shutdown",  "label": "Shut down",    "confirm": true,
      "detail": "systemctl poweroff" },
    { "id": "suspend",   "label": "Suspend",      "confirm": true,
      "detail": "systemctl suspend" }
  ]
}
JSON
}

main() {
    local dry_run=0
    if [[ "${1:-}" == "--list" ]]; then
        list_actions
        return 0
    fi
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run=1
        shift
    fi

    local action="${1:-}"
    local cmd
    if ! cmd="$(command_for "$action")"; then
        printf 'power-ctl: unknown action %s\n' "${action:-<none>}" >&2
        return 2
    fi

    if (( dry_run )); then
        printf '%s\n' "$cmd"
        return 0
    fi

    # No `exec`, and no background. The caller is a Quickshell Process whose
    # exit code the panel reads: `systemctl reboot` failing (polkit refuses,
    # logind is not there) has to come back as a non-zero exit rather than
    # as a menu that closed and did nothing, which is exactly how a dead
    # keybinding presents.
    # shellcheck disable=SC2086
    $cmd
}

main "$@"
