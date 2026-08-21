#!/usr/bin/env bash
# Shared helpers for rofi scripts. Source from other scripts:
#   source "$(dirname "$0")/rofi_common.sh"

ROFI_PALETTE_FILE="${ROFI_PALETTE_FILE:-$HOME/.config/rofi/themes/current-palette.rasi}"
ROFI_SECRETS_FILE="${ROFI_SECRETS_FILE:-$HOME/.config/secrets.env}"

# Scratch files go in a PER-USER directory, not at a fixed path in /tmp.
#
# /tmp is shared. The first account to run one of these scripts creates
# /tmp/rofi-gemini.log and /tmp/rofi-confirm.err owned by itself and mode
# 644, and for every other account on the machine the redirect into them
# then fails with EACCES. For the log that costs the error message; for
# rofi-confirm.err it costs the whole call, because a failed redirect
# means the rofi command never runs at all -- so every confirmation
# dialog on the desktop silently answered "cancel". XDG_RUNTIME_DIR is
# already per-user and mode 700; the /tmp fallback is namespaced by UID
# for the sessions that do not set it.
ROFI_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/rofi-$(id -u)}"
mkdir -p "$ROFI_RUNTIME_DIR" 2>/dev/null || true
GEMINI_LOG="${GEMINI_LOG:-$ROFI_RUNTIME_DIR/rofi-gemini.log}"

# Model fallback chain for gemini(). First one that answers wins.
#
# The old per-script lists had rotted in place: rofi_translator asked for
# gemini-1.5-flash, gemini-1.5-flash-8b and "gemini-flash-1.5-8b" (a typo
# that was never a model), rofi_anki led with "gemini-1.0-flash" (likewise
# never a model). The 1.5 family is retired, so both scripts burned three
# or four failing round trips before reaching anything live. One list,
# here, current, shortest-path-first.
# shellcheck disable=SC2034  # consumed by gemini() below and by callers
GEMINI_MODELS=("gemini-2.5-flash" "gemini-2.0-flash")

# Load API keys from a private env file of KEY=value lines.
#
# The keys used to live commented-out in /etc/environment, which is both
# world-readable and not re-read by anything qtile spawns without a full
# re-login. Nothing supplied GEMINI_API_KEY, so rofi_anki exited before
# drawing a menu and the two translators silently rendered empty synonym
# and example sections. Lines that do not parse as a shell identifier are
# skipped, so leading '#' comments are ignored for free.
load_secrets() {
    [[ -r "$ROFI_SECRETS_FILE" ]] || return 0
    local perms key val
    perms="$(stat -c '%a' "$ROFI_SECRETS_FILE" 2>/dev/null || echo 600)"
    if [[ "$perms" != 600 && "$perms" != 400 ]]; then
        notify_safe "⚠️ secrets file is not private" \
                    "chmod 600 $ROFI_SECRETS_FILE"
    fi
    while IFS='=' read -r key val; do
        key="${key#"${key%%[![:space:]]*}"}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        val="${val%\"}"; val="${val#\"}"
        val="${val%\'}"; val="${val#\'}"
        export "$key=$val"
    done < "$ROFI_SECRETS_FILE"
}

# Bail with a visible reason if a required key is missing. The old
# failure mode was a silent empty string.
require_key() {
    local name="$1"
    [[ -n "${!name:-}" ]] && return 0
    notify_safe "🔑 $name not set" "add it to $ROFI_SECRETS_FILE (chmod 600)"
    printf '%s not set — add it to %s\n' "$name" "$ROFI_SECRETS_FILE" >&2
    return 1
}

# gemini "<prompt>" -> answer text on stdout, non-zero if nothing answered.
#
# The key travels as an x-goog-api-key header rather than a ?key= query
# param so it stays out of `ps` output and any proxy logs. Failures are
# appended to $GEMINI_LOG with the API's own error message, because every
# previous version of this call discarded the reason and returned "".
gemini() {
    local prompt="$1" model payload url response text
    [[ -n "${GEMINI_API_KEY:-}" ]] || return 1
    command -v jq &>/dev/null && command -v curl &>/dev/null || return 1
    payload="$(jq -n --arg p "$prompt" '{contents:[{parts:[{text:$p}]}]}')" || return 1
    for model in "${GEMINI_MODELS[@]}"; do
        url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
        response="$(curl -sS --max-time 25 -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "x-goog-api-key: ${GEMINI_API_KEY}" \
            -d "$payload" 2>>"$GEMINI_LOG")" || continue
        text="$(printf '%s' "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)"
        if [[ -n "$text" ]]; then
            printf '%s' "$text"
            return 0
        fi
        printf '[%s] %s: %s\n' "$(date +%H:%M:%S)" "$model" \
            "$(printf '%s' "$response" | jq -rc '.error.message // .' 2>/dev/null | head -c 300)" \
            >>"$GEMINI_LOG"
    done
    return 1
}

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
        # These are the whole point of sourcing this file: rofi_todo,
        # ati-kill, rofi_shared and theme-apply all read PAL_*. Unused
        # *here* by design.
        # shellcheck disable=SC2034
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
#
# ${WAYLAND_DISPLAY:-}, not $WAYLAND_DISPLAY. Every caller of this runs
# under `set -u`, and on an X11 session WAYLAND_DISPLAY is simply not
# set -- so the bare reference aborted the whole script here. It failed
# in the worst possible way: ati-pass died the instant you pressed
# Enter on an entry, with no message, no notification and no clipboard,
# looking exactly like a keybinding that does nothing. wl-copy being
# installed is what made the test reachable at all.
copy_to_clipboard() {
    local text="$1"
    if command -v wl-copy &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
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
        -p "$prompt" ${msg:+-mesg "$msg"} -selected-row 0 2>"$ROFI_RUNTIME_DIR/rofi-confirm.err")
    local rc=$?
    # rofi failed to launch (still-running lock, no display, etc).
    # Notify the user so silent no-op is not confused with cancel.
    if [[ -z "$answer" && $rc -ne 0 ]]; then
        local err
        err="$(head -1 "$ROFI_RUNTIME_DIR/rofi-confirm.err" 2>/dev/null)"
        printf '[%s] rofi_confirm launch failed rc=%s err=%s\n' \
            "$(date +%H:%M:%S)" "$rc" "$err" >>"$ROFI_RUNTIME_DIR/rofi-confirm.log"
        notify_safe "❌ confirm dialog failed" "${err:-check $ROFI_RUNTIME_DIR/rofi-confirm.log}"
        return 1
    fi
    [[ "$answer" == "Yes" ]]
}

# Single-line text entry: ask a question, read one answer.
#
#   answer="$(rofi_input "New title" "https://example.com" "$old_title")"
#
# Use this instead of a bare `rofi -dmenu` whenever there is no list to
# choose from. rofi reserves room for a listview even when stdin is
# empty -- 15 rows by default -- so a prompt that shows nothing but a
# text field came out 683x766 on a 768px screen: a full-height window
# that is one input box and an acre of black. Collapsing lines to 0
# gives 683x140, measured.
#
# Args: prompt [mesg] [prefilled text]
rofi_input() {
    local prompt="${1:-Input}" mesg="${2:-}" prefill="${3:-}"
    printf '' | rofi -dmenu -i \
        -p "$prompt" \
        -theme "$HOME/.config/rofi/themes/base.rasi" \
        -theme-str 'listview { lines: 0; }' \
        ${mesg:+-mesg "$mesg"} \
        ${prefill:+-filter "$prefill"}
}

# Same as rofi_input, but the typing is masked. For secrets only.
#
# rofi's -password hides the characters; it does NOT stop the value
# appearing in this process's argv, so the answer must be read from
# stdout (as here) and never passed to anything as a command argument.
rofi_input_secret() {
    local prompt="${1:-Password}" mesg="${2:-}"
    printf '' | rofi -dmenu -i -password \
        -p "$prompt" \
        -theme "$HOME/.config/rofi/themes/base.rasi" \
        -theme-str 'listview { lines: 0; }' \
        ${mesg:+-mesg "$mesg"}
}

# Standard hint line for the -mesg footer.
#
# Every rofi menu here had grown its own idea of what the strip under the
# prompt is for. ati-kill and rofi_todo listed keybindings in bold;
# rofi_light showed a value; rofi_docs explained navigation; theme-toggle
# and ui-scale-toggle had no footer at all, so the two menus that CHANGE
# THE WHOLE DESKTOP were also the two that said nothing about what Enter
# was about to do. Same markup, same separator, same order everywhere now:
# actions first, then context.
#
#   rofi_hint "↵ apply" "Esc cancels" "22 palettes"
#     ->  <b>↵</b> apply  ·  <b>Esc</b> cancels  ·  22 palettes
#
# A leading token of the form "KEY text" gets its key emboldened; anything
# without a recognised key prefix is passed through as plain context.
rofi_hint() {
    local out="" part key rest
    for part in "$@"; do
        [[ -z "$part" ]] && continue
        key="${part%% *}"
        rest="${part#* }"
        case "$key" in
            ↵|Esc|Tab|Alt+*|Ctrl+*|Shift+*|Super+*)
                part="<b>${key}</b> ${rest}" ;;
        esac
        [[ -n "$out" ]] && out+="  ·  "
        out+="$part"
    done
    printf '%s' "$out"
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
        # shellcheck disable=SC2034  # loop counter; body polls, does not read i
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
