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
# ROFI_THEME is huge (kill-large, todo-large, etc). Selected row 0
# = No, so accidental Enter cancels safely.
rofi_confirm() {
    local prompt="${1:-Confirm?}"
    local msg="${2:-}"
    local answer
    answer=$(printf 'No\nYes\n' | rofi -dmenu -i \
        -theme "$HOME/.config/rofi/themes/base.rasi" \
        -theme-str 'window { width: 22%; } listview { lines: 2; dynamic: false; } element { padding: 6px 12px; }' \
        -p "$prompt" ${msg:+-mesg "$msg"} -selected-row 0)
    [[ "$answer" == "Yes" ]]
}
