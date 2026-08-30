#!/usr/bin/env bash
# nested-shot.sh <config> <out.png> [ipc call...] — screenshot a quickshell
# config inside a throwaway nested Hyprland. Same reasoning as
# nested-qml-check.sh, but it keeps the pixels instead of the log.
set -uo pipefail
TARGET="$1"; OUT="$2"; shift 2
WORK="$(mktemp -d)"; NPID=""; QPID=""; sig=""
# The HOST's signature, saved before the nested one overwrites the variable.
HOST_SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
cleanup() {
  [[ -n "$QPID" ]] && kill "$QPID" 2>/dev/null
  [[ -n "$NPID" ]] && kill "$NPID" 2>/dev/null
  sleep 1
  [[ -n "$QPID" ]] && kill -9 "$QPID" 2>/dev/null
  [[ -n "$NPID" ]] && kill -9 "$NPID" 2>/dev/null
  [[ -n "$sig" ]] && rm -rf "${XDG_RUNTIME_DIR:?}/hypr/${sig:?}"
  rm -rf "$WORK"
}
trap cleanup EXIT
cat > "$WORK/hypr.conf" <<'CONF'
debug { suppress_errors = true }
monitor = WAYLAND-1, 1366x768@60, 0x0, 1
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}
animations { enabled = false }
decoration { blur { enabled = false } }
CONF
before="$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort)"
sb="$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | sort)"
env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland -c "$WORK/hypr.conf" >"$WORK/hypr.log" 2>&1 &
NPID=$!
for _ in $(seq 1 60); do
  sig="$(comm -13 <(printf '%s\n' "$before") <(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort) | head -1)"
  [[ -n "$sig" && -S "$XDG_RUNTIME_DIR/hypr/$sig/.socket.sock" ]] && break
  sleep 0.25
done
[[ -n "$sig" ]] || { echo "nested Hyprland never came up" >&2; exit 2; }
disp="$(basename "$(comm -13 <(printf '%s\n' "$sb") <(ls "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | sort) | head -1)")"
export WAYLAND_DISPLAY="$disp" HYPRLAND_INSTANCE_SIGNATURE="$sig"
# The `monitor =` rule in the config does NOT take on Hyprland 0.56's
# Wayland backend -- the nested output comes up at its own default
# (measured: 329x349) and the rule is silently ignored. Setting the same
# thing as a runtime keyword DOES take, so do that before anything is drawn.
# THE NESTED OUTPUT IS JUST ITS WINDOW ON THE HOST, and that is why the
# `monitor =` rule in the config appears to do nothing: the Wayland backend
# takes its size from the toplevel the host gave it, which a tiling layout
# had made 329x349. Setting the rule at runtime does not help either.
#
# So resize the WINDOW, on the host, by address -- a window this script
# created itself, which vanishes when it exits. No host config is touched
# and nothing else on the desktop moves.
if [[ -n "$HOST_SIG" ]] && command -v jq >/dev/null 2>&1; then
  for _ in 1 2 3 4 5 6 7 8; do
    addr="$(HYPRLAND_INSTANCE_SIGNATURE="$HOST_SIG" hyprctl clients -j 2>/dev/null |
            jq -r --arg p "$NPID" '.[] | select(.pid == ($p|tonumber)) | .address' | head -1)"
    [[ -n "$addr" && "$addr" != "null" ]] && break
    sleep 0.4
  done
  if [[ -n "${addr:-}" && "$addr" != "null" ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$HOST_SIG" hyprctl --batch       "dispatch setfloating address:$addr ; dispatch resizewindowpixel exact 1366 768,address:$addr ; dispatch centerwindow"       >/dev/null 2>&1
    sleep 1.2
  fi
fi
qs -p "$TARGET" >"$WORK/qs.log" 2>&1 &
QPID=$!
for _ in $(seq 1 40); do
  qs -p "$TARGET" ipc show >/dev/null 2>&1 && break
  kill -0 "$QPID" 2>/dev/null || break
  sleep 0.25
done
# A focused window, because several island entry points route through
# forFocusedWindow() and do nothing at all on an empty workspace.
kitty -e sh -c "sleep 60" >/dev/null 2>&1 & sleep 2
if (( $# )); then qs -p "$TARGET" ipc call "$@" >>"$WORK/qs.log" 2>&1; fi
sleep 2.5
grim -o WAYLAND-1 "$OUT" 2>>"$WORK/qs.log" || grim "$OUT" 2>>"$WORK/qs.log"
echo "saved $OUT"
grep -iE "^ *ERROR|ReferenceError|TypeError|is not a" "$WORK/qs.log" | head -5
