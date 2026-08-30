#!/usr/bin/env bash
# nested-qml-check.sh [<shell.qml>] — load a quickshell config inside a
# THROWAWAY nested Hyprland and report whether it came up clean.
#
#   ./nested-qml-check.sh ~/.config/quickshell/topbar/redesign-e-final.qml
#   NESTED_QML_IPC='tide toggleCalendar' ./nested-qml-check.sh ~/.config/quickshell/tide-island-fork/shell.qml
#
# NESTED_QML_IPC — one IPC call per line, run against the NESTED instance
# once it is up, before the verdict is read. This is not a convenience: a
# panel behind a `PanelLoader { live: ... }` is not instantiated until it is
# opened, so a plain load says nothing at all about it. The island has
# fourteen of those loaders; "loaded clean" for shell.qml means the capsule
# is fine and every panel in the fork is still untested. Open the one you
# edited, or the check is a green light for a file that never ran.
#
# WHY THIS EXISTS
# ---------------
# Editing the live bar's QML is editing something quickshell is watching:
# the change is on screen the moment it is saved, and a bad one takes the
# bar with it in the middle of whatever you were doing. Every other test
# under this directory drives the RUNNING desktop over IPC on purpose --
# that is the right tool for behaviour. This is the one for "does this file
# even load", which must never be asked of the session you are using.
#
# Nested rather than headless, and that is not a preference. Hyprland 0.56
# is on aquamarine, where the wlroots-era `WLR_BACKENDS=headless` does
# nothing at all: it is not an unknown-variable warning, the backend simply
# fails to construct and Hyprland aborts with `CBackend::create() failed!`
# before any config is read. The Wayland backend nests inside the session
# you are already in, which works, at the cost of one small window.
#
# WHAT IT CATCHES, AND THE TWO SHAPES IT COMES IN
# -----------------------------------------------
# quickshell reports a broken config two different ways and only one of
# them is fatal, so grepping for the fatal one alone silently passes half
# of all mistakes:
#
#   * A type or parse error -- a renamed component, an unbalanced brace --
#     is an ERROR and quickshell exits (rc 255).
#   * A runtime reference error -- a property that does not exist, a typo
#     in a binding -- is only a WARN. The shell STAYS UP with that one
#     binding dead, which on a bar means a chip that silently renders
#     nothing. Both are failures here.
#
# THE DIRECTORY MATTERS
# ---------------------
# Sibling components resolve relative to the file, so a copy of just the
# one .qml into /tmp fails with "TourPopup is not a type" -- an error about
# the copy, not about the edit. Always point this at a file sitting in a
# complete directory.
set -uo pipefail

TARGET="${1:-$HOME/.config/quickshell/topbar/redesign-e-final.qml}"
SECONDS_UP="${NESTED_QML_SECONDS:-6}"

[[ -f "$TARGET" ]] || { printf 'no such file: %s\n' "$TARGET" >&2; exit 2; }
command -v Hyprland >/dev/null || { printf 'Hyprland not installed\n' >&2; exit 2; }
command -v qs >/dev/null || { printf 'quickshell (qs) not installed\n' >&2; exit 2; }
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { printf 'needs a Wayland session to nest inside\n' >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nested-qml.XXXXXX")"
NESTED_PID=""
QS_PID=""
sig=""
cleanup() {
    [[ -n "$QS_PID" ]] && kill "$QS_PID" 2>/dev/null
    [[ -n "$NESTED_PID" ]] && kill "$NESTED_PID" 2>/dev/null
    # Give it a moment to take its wayland socket with it; a nested
    # compositor left running is worse than a failed test.
    [[ -n "$NESTED_PID" ]] && { for _ in 1 2 3 4 5 6 7 8; do kill -0 "$NESTED_PID" 2>/dev/null || break; sleep 0.25; done; }
    [[ -n "$NESTED_PID" ]] && kill -9 "$NESTED_PID" 2>/dev/null
    # Hyprland does NOT remove its own $XDG_RUNTIME_DIR/hypr/<sig> directory
    # when it is killed, so every run of this script used to leave one
    # behind. That is not just litter: the next run identifies its instance
    # by diffing this directory, and a pile of corpses is exactly what makes
    # "take the newest entry" the wrong algorithm. Only ever our own sig --
    # never a glob, which could take the live session's.
    [[ -n "$sig" ]] && rm -rf "${XDG_RUNTIME_DIR:?}/hypr/${sig:?}"
    rm -rf "$WORK"
}
trap cleanup EXIT

cat > "$WORK/hypr.conf" <<'CONF'
# `debug:suppress_errors` is not cosmetic here. Without it the nested
# compositor draws Hyprland's own full-width error overlay across its
# window, with two warnings that are TRUE OF THIS SCRIPT and of nothing
# else: "you are using the .conf config format" (this throwaway config is
# .conf) and "Hyprland was started without start-hyprland" (deliberate --
# start-hyprland would try to take over the session this is nesting
# inside). Reported as "why do these popups appear in startup", which is
# exactly how they read: a black window with two red-and-yellow banners,
# indistinguishable from the real session having gone wrong. They were
# never the real session. Neither warning appears in its log.
debug { suppress_errors = true }
# The output is WAYLAND-1. Not WL-1, which is what this said first and
# which matches NOTHING -- an unmatched monitor rule is not an error in
# Hyprland, it is simply ignored, so the window came up at whatever the
# default was (329x349 at scale 2, measured) and the bar under test was
# cut off mid-strip. Explicit scale 1 for the same reason: the default
# doubled it and halved the usable width.
#
# Wide enough to hold the whole bar, short enough to be obviously a test
# artifact rather than something that looks like the desktop misbehaving.
monitor = WAYLAND-1, 1400x300@60, 0x0, 1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}
animations { enabled = false }
decoration { blur { enabled = false } }
CONF

# The new instance is identified by DIFFING the instance directory, not by
# taking the newest entry: a crashed nested run leaves its directory behind,
# so "newest" can name a corpse.
before="$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort)"
sockets_before="$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | sort)"

env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland -c "$WORK/hypr.conf" >"$WORK/hypr.log" 2>&1 &
NESTED_PID=$!

sig=""
for _ in $(seq 1 60); do
    sig="$(comm -13 <(printf '%s\n' "$before") <(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort) | head -1)"
    [[ -n "$sig" && -S "$XDG_RUNTIME_DIR/hypr/$sig/.socket.sock" ]] && break
    kill -0 "$NESTED_PID" 2>/dev/null || break
    sleep 0.25
done
if [[ -z "$sig" ]]; then
    printf 'nested Hyprland never came up:\n' >&2
    tail -5 "$WORK/hypr.log" >&2
    exit 2
fi

disp="$(comm -13 <(printf '%s\n' "$sockets_before") <(ls "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | sort) | head -1)"
disp="$(basename "${disp:-}")"
[[ -n "$disp" ]] || { printf 'could not identify the nested wayland socket\n' >&2; exit 2; }

if [[ -z "${NESTED_QML_IPC:-}" ]]; then
    timeout "$SECONDS_UP" env WAYLAND_DISPLAY="$disp" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
        qs -p "$TARGET" >"$WORK/qs.log" 2>&1
    rc=$?
else
    # Driven mode. quickshell goes to the BACKGROUND so there is something
    # to talk to; `timeout` in front of it would have been the same process
    # this needs to outlive the calls.
    env WAYLAND_DISPLAY="$disp" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
        qs -p "$TARGET" >"$WORK/qs.log" 2>&1 &
    QS_PID=$!

    # `ipc show` is the readiness probe: the socket exists only once the
    # config has loaded far enough to serve it, which is precisely the point
    # at which a call will not be dropped.
    ready=0
    for _ in $(seq 1 40); do
        kill -0 "$QS_PID" 2>/dev/null || break
        if env WAYLAND_DISPLAY="$disp" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
             qs -p "$TARGET" ipc show >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.25
    done
    if (( ready == 0 )); then
        printf 'FAIL  %s — never served IPC to drive it with\n' "$TARGET"
        tail -10 "$WORK/qs.log"
        exit 1
    fi

    while IFS= read -r call; do
        [[ -z "${call// }" ]] && continue
        # shellcheck disable=SC2086  # deliberate: the line IS the argv
        env WAYLAND_DISPLAY="$disp" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
            qs -p "$TARGET" ipc call $call >>"$WORK/qs.log" 2>&1
        # Panels open behind an animation and instantiate on the way in;
        # reading the log before that has finished is reading it too early.
        sleep 1.5
    done <<<"$NESTED_QML_IPC"

    sleep 1
    # Same verdict the foreground path encodes in rc=124: still up after
    # everything it was asked to do is the pass.
    if kill -0 "$QS_PID" 2>/dev/null; then rc=124; else wait "$QS_PID"; rc=$?; fi
    kill "$QS_PID" 2>/dev/null
    QS_PID=""
fi

# Strip the SGR colour codes quickshell emits, or the greps below never
# match a highlighted "ERROR".
sed -i 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log"

fatal="$(grep -c '^ *ERROR' "$WORK/qs.log")"
# Runtime binding failures. Only these WARN classes -- a plain WARN from
# quickshell is routine (missing optional services, and so on) and failing
# on every one of them would make this script useless.
runtime="$(grep -cE 'ReferenceError|TypeError|SyntaxError|Unable to assign|Cannot assign|is not a (type|function)' "$WORK/qs.log")"

if (( fatal > 0 || runtime > 0 )); then
    printf 'FAIL  %s\n' "$TARGET"
    grep -nE '^ *ERROR|ReferenceError|TypeError|SyntaxError|Unable to assign|Cannot assign|is not a (type|function)' "$WORK/qs.log" | head -20
    exit 1
fi
if (( rc != 124 && rc != 0 )); then
    printf 'FAIL  %s — quickshell exited rc=%s without staying up\n' "$TARGET" "$rc"
    tail -10 "$WORK/qs.log"
    exit 1
fi

printf 'ok    %s — loaded clean in a nested Hyprland (%ss)\n' "$TARGET" "$SECONDS_UP"
