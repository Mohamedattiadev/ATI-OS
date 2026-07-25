#!/usr/bin/env bash
# Shared helpers for rofi scripts. Source from other scripts:
#   source "$(dirname "$0")/rofi_common.sh"

ROFI_PALETTE_FILE="${ROFI_PALETTE_FILE:-$HOME/.config/rofi/themes/current-palette.rasi}"

# Load palette from rasi into shell vars.
# Sets: PAL_BG PAL_BG_ALT PAL_FG PAL_SEL PAL_SEL1 PAL_URGENT PAL_ACTIVE
# Falls back to doom-one defaults if palette file missing/broken.
load_palette() {
    PAL_BG="#282c34"
    PAL_BG_ALT="#21242b"
    PAL_FG="#bbc2cf"
    PAL_SEL="#61afef"
    PAL_SEL1="#c678dd"
    PAL_URGENT="#e06c75"
    PAL_ACTIVE="#98c379"

    [[ -r "$ROFI_PALETTE_FILE" ]] || return 0

    local key val
    while IFS=':' read -r key val; do
        key="${key//[[:space:]]/}"
        val="${val//[[:space:]]/}"
        val="${val%;*}"
        [[ "$val" =~ ^#[0-9a-fA-F]{6}$ ]] || continue
        case "$key" in
            background)     PAL_BG="$val" ;;
            background-alt) PAL_BG_ALT="$val" ;;
            foreground)     PAL_FG="$val" ;;
            selected)       PAL_SEL="$val" ;;
            selectedone)    PAL_SEL1="$val" ;;
            urgent)         PAL_URGENT="$val" ;;
            active)         PAL_ACTIVE="$val" ;;
        esac
    done < "$ROFI_PALETTE_FILE"
}

# Clipboard: wayland → xclip → xsel → notify failure.
copy_to_clipboard() {
    local text="$1"
    if command -v wl-copy &>/dev/null && [[ -n "$WAYLAND_DISPLAY" ]]; then
        printf '%s' "$text" | wl-copy
    elif command -v xclip &>/dev/null; then
        printf '%s' "$text" | xclip -selection clipboard
    elif command -v xsel &>/dev/null; then
        printf '%s' "$text" | xsel --clipboard --input
    else
        notify_safe "Clipboard tool not found" "install wl-clipboard, xclip, or xsel"
        return 1
    fi
}

# Notify wrapper — no-op if notify-send missing.
notify_safe() {
    command -v notify-send &>/dev/null && notify-send "$@"
}

# Require deps or bail with notify.
require_cmd() {
    local missing=()
    for c in "$@"; do
        command -v "$c" &>/dev/null || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        notify_safe "Missing dependencies" "${missing[*]}"
        printf 'missing: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

# Small confirm prompt. Always uses base.rasi + tight overrides so
# it renders as a compact centered popup regardless of which caller's
# ROFI_THEME is huge (kill-large, todo-large, etc). Default selection
# = Yes so single Enter confirms.
#
# rofi is single-instance: caller's rofi must be fully released before
# this one starts. Poll pidfile up to 1s to avoid the "Rofi already
# running" race that silently returned no-answer (= treated as cancel).
rofi_confirm() {
    local prompt="${1:-Confirm?}"
    local msg="${2:-}"
    local answer i
    # Wait for any lingering rofi instance to fully exit.
    for i in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x rofi >/dev/null 2>&1 || break
        sleep 0.05
    done
    answer=$(printf 'Yes\nNo\n' | rofi -dmenu -i \
        -theme "$HOME/.config/rofi/themes/base.rasi" \
        -theme-str 'window { width: 22%; } listview { lines: 2; dynamic: false; } element { padding: 6px 12px; }' \
        -p "$prompt" ${msg:+-mesg "$msg"} -selected-row 0 2>/tmp/rofi-confirm.err)
    local rc=$?
    # rofi failed to launch (still-running lock, no display, etc).
    # Notify the user so silent no-op is not confused with cancel.
    if [[ -z "$answer" && $rc -ne 0 ]]; then
        local err="$(cat /tmp/rofi-confirm.err 2>/dev/null | head -1)"
        printf '[%s] rofi_confirm launch failed rc=%s err=%s\n' \
            "$(date +%H:%M:%S)" "$rc" "$err" >>/tmp/rofi-confirm.log
        notify_safe "❌ confirm dialog failed" "${err:-check /tmp/rofi-confirm.log}"
        return 1
    fi
    [[ "$answer" == "Yes" ]]
}

# Guaranteed kill: SIGTERM + 0.8s grace + SIGKILL if still alive.
# Second arg 'force' skips SIGTERM path. Sends both direct kill(2)
# via bash builtin (fast, no fork) and falls back to /usr/bin/kill
# for edge cases. Emits notify with actual outcome.
kill_guaranteed() {
    local pid="$1" mode="${2:-graceful}" name
    [[ "$pid" =~ ^[0-9]+$ ]] || { notify_safe "❌ Bad PID" "$pid"; return 1; }
    name="$(ps -p "$pid" -o comm= 2>/dev/null || echo unknown)"
    if [[ "$mode" == "force" ]]; then
        kill -9 "$pid" 2>/dev/null || /usr/bin/kill -9 "$pid" 2>/dev/null
    else
        kill -15 "$pid" 2>/dev/null || /usr/bin/kill -15 "$pid" 2>/dev/null
        # Poll up to 0.8s (8 * 0.1s) — SIGTERM grace period.
        local i
        for i in 1 2 3 4 5 6 7 8; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
    fi
    # Verify. Escalate to SIGKILL if still alive.
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || /usr/bin/kill -9 "$pid" 2>/dev/null
        sleep 0.15
    fi
    if kill -0 "$pid" 2>/dev/null; then
        notify_safe "❌ PID $pid ($name) refuses to die" \
                    "may need sudo — try: sudo kill -9 $pid"
        return 1
    fi
    if [[ "$mode" == "force" ]]; then
        notify_safe "☠️ SIGKILL PID $pid" "$name"
    else
        notify_safe "✅ Killed PID $pid" "$name"
    fi
    return 0
}
