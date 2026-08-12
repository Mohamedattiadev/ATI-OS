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
#   2. REFRESH. dm-logout runs ~/.config/AtiScriptsV1/reset_PC. Read before
#      porting it, and it is not a config reload: it pkill -TERM then
#      pkill -KILL's 20 named applications (browsers, terminals, editors,
#      Obsidian, Anki, mpv...), restarts picom, runs
#      `qtile cmd-obj -o cmd -f restart` with a `pkill -HUP qtile` fallback,
#      and finally re-runs ~/.config/qtile/autostart.sh. In a Hyprland
#      session that is: your work closed, a compositor that is not running
#      HUPed, and qtile's X11 autostart executed on top of Wayland. It would
#      do harm and could not do the thing it was for.
#
#      The equivalent here is `hyprctl reload`, which binds.conf already
#      documents at $mod SHIFT R: "Hyprland reloads config without touching
#      windows at all, which is strictly better".
#
# The other five are byte-for-byte what dm-logout runs.
#
# Every action is spelled out in one place so the panel does not have to
# carry shell strings, and so each can be checked from a terminal without
# opening the menu:
#
#     ./power-ctl.sh --list          # the actions, as JSON
#     ./power-ctl.sh --dry-run lock  # print the command, run nothing
#
set -euo pipefail

# The command for each action, in one table. Kept as a function rather than
# an associative array so `logout` can carry its two-branch fallback without
# being a string that has to be eval'd.
command_for() {
    case "$1" in
    lock)     printf 'loginctl lock-session' ;;
    logout)
        # dm-logout's own branch, transcribed: the session id when the
        # environment has one, the seat when it does not.
        if [[ -n "${XDG_SESSION_ID:-}" ]]; then
            printf 'loginctl terminate-session %s' "$XDG_SESSION_ID"
        else
            printf 'loginctl terminate-seat seat0'
        fi
        ;;
    refresh)  printf 'hyprctl reload' ;;
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
    cat <<'JSON'
{
  "actions": [
    { "id": "lock",     "label": "Lock screen",  "confirm": false,
      "detail": "loginctl lock-session → hyprlock" },
    { "id": "logout",   "label": "Log out",      "confirm": true,
      "detail": "loginctl terminate-session" },
    { "id": "refresh",  "label": "Reload config","confirm": true,
      "detail": "hyprctl reload" },
    { "id": "reboot",   "label": "Reboot",       "confirm": true,
      "detail": "systemctl reboot" },
    { "id": "shutdown", "label": "Shut down",    "confirm": true,
      "detail": "systemctl poweroff" },
    { "id": "suspend",  "label": "Suspend",      "confirm": true,
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
