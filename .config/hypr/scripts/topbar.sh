#!/usr/bin/env bash
# topbar.sh — launch the Hyprland topbar, the `native` half of bar-switch.
#
# The counterpart to island.sh. That one launches the Tide Island; this one
# launches the bar that mirrors qtile's, and AtiScriptsV1/bar-switch decides
# which of the two the session is wearing.
#
# WHY THIS IS ITS OWN QUICKSHELL CONFIG AND NOT PART OF THE FORK
# --------------------------------------------------------------
# Quickshell keys its IPC socket and its instance by the CONFIG PATH, so two
# configs are two instances that can be started and stopped independently —
# which is exactly what a bar switch needs. Putting the topbar inside the
# island's tree would mean one process serving both bars, and "switch" would
# become "hide half of the shell", which is the arrangement that made the
# qtile side of this hard (see bar_switch_apply in qtile/config.py: a hidden
# bar could not be brought back without a rebuild).
#
# It also keeps the blast radius honest. The island serves
# org.freedesktop.Notifications and owns the desktop's notification story; the
# topbar owns nothing but pixels. A crash in one must not take the other with
# it, and separate processes are the only way to mean that.
#
# THE PALETTE IS SHARED ANYWAY
# ----------------------------
# Both read ~/.cache/tide-island/colors.json, which theme-apply writes. One
# `theme-apply gruvbox` retints the island, this bar and the qtile bar, and
# none of them has a private copy of the 22 palettes to drift from.

set -euo pipefail

CONFIG_DIR="${TOPBAR_CONFIG_DIR:-$HOME/.config/quickshell/topbar}"

if [[ ! -f "$CONFIG_DIR/shell.qml" ]]; then
  echo "topbar.sh: no config at $CONFIG_DIR — has stow run?" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
#  ONE MATCHER, AND THE BAR ITSELF IS SUBJECT TO IT
# ---------------------------------------------------------------------------
# This is the argv walk that bar-switch's island_pid() explains at length:
# find `-p`, compare the NEXT field for EQUALITY. Not `pgrep -f`, which
# matches this script's own command line, and not a substring, which cannot
# tell `-p <dir>` from `-p <dir>/popups.qml`.
#
# It was written out twice below — once for treetab, once for popups — and
# NOT AT ALL for the topbar. So the two second-order surfaces were idempotent
# and the bar this script exists to start was not:
#
#     $ ~/.config/hypr/scripts/topbar.sh      # a bar
#     $ ~/.config/hypr/scripts/topbar.sh      # a SECOND bar, on top of it
#     $ hyprctl monitors -j | jq '.[0].reserved'
#     [0, 76, 0, 0]                           # 38 twice
#
# Two layer surfaces at the same place, each reserving its own 38 px, and the
# only visible symptom is that every tiled window sits 38 px lower than it
# should — which reads as a layout bug, not as a duplicated process. Caught by
# hand and cleaned up by killing the extra.
#
# bar-switch never hit it because topbar_start() has its own `topbar_running`
# guard. That is exactly the shape of bug island.sh's header argues against:
# an invariant that lives in ONE caller holds only for that caller, and every
# other route in — by hand, from a keybind, from a test harness — is free to
# break it. So the check moves to the thing that can always enforce it.
entry_running() {
  # `!/awk/` excludes this awk's own command line, which contains `want`.
  ps -eo args= | awk -v want="$1" \
    '!/awk/ { for (i = 1; i < NF; i++) if ($i == "-p" && $(i + 1) == want) { found = 1 } }
     END { exit !found }'
}

# REFUSES rather than starting a second one, and exits 0 while doing it.
# "The bar you asked for is already up" is the requested state, not a failure,
# and bar-switch runs under `set -e` with a rollback on any non-zero — so
# exiting non-zero here would make an idempotent call look like a failed
# switch and roll ~/.cache/bar-mode back to the bar that is not running.
if entry_running "$CONFIG_DIR"; then
  echo "topbar.sh: a topbar is already running for $CONFIG_DIR — not starting a second" >&2
  exit 0
fi

# Carried over from island.sh for the same reason it is there: Quickshell uses
# jemalloc, which otherwise keeps every Loader/image high-water mark resident
# for the life of the session.
export MALLOC_CONF="${MALLOC_CONF:-narenas:2,background_thread:true,dirty_decay_ms:2000,muzzy_decay_ms:2000}"

# ---------------------------------------------------------------------------
#  The TreeTab sidebar, which belongs to the LAYOUT and not to either bar
# ---------------------------------------------------------------------------
# qtile's TreeTab is a real layout and works under both of its bars. Here the
# 180 px sidebar that IS the difference between treetab and max is drawn by
# the island's shell.qml, and bar-switch stops the island to start this bar —
# so under this bar treetab and max were the same thing with two names.
# Reported as "the tree layout is not working in the qtile-like bar".
#
# It is started as a SECOND ENTRY POINT into the island's own config directory
# rather than reimplemented here. That file's header records why the obvious
# alternative — importing the component into the topbar's config — is not
# possible: Quickshell's scanner refuses a module path outside the config
# folder, symlink or not.
#
# Idempotent through the shared `entry_running` above. bar-switch stops it
# when the island comes back, since the island draws its own and two would
# stack two exclusive zones.
TREETAB_ENTRY="${TREETAB_ENTRY:-$HOME/.config/quickshell/tide-island-fork/treetab.qml}"

if [[ -f "$TREETAB_ENTRY" ]] && ! entry_running "$TREETAB_ENTRY"; then
  setsid -f quickshell -p "$TREETAB_ENTRY" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
#  qtile's popups — the wallpaper picker, the network list, the mixer
# ---------------------------------------------------------------------------
# Another entry point into the island's config, for the same reason, and
# started here rather than on demand: a Quickshell start is a QML compile, so a
# popup that has to be launched before it can be shown answers its first
# keystroke several hundred milliseconds late EVERY time. Resident, it answers
# at once, and an unopened popup is an inactive Loader — no window, no polling.
POPUPS_ENTRY="${POPUPS_ENTRY:-$HOME/.config/quickshell/tide-island-fork/popups.qml}"

if [[ -f "$POPUPS_ENTRY" ]] && ! entry_running "$POPUPS_ENTRY"; then
  setsid -f quickshell -p "$POPUPS_ENTRY" >/dev/null 2>&1 || true
fi

# NOT `pkill dunst` — deliberately, and the difference from island.sh matters.
# The island SERVES notifications, so it has to clear dunst off the bus name
# before starting. This bar serves nothing: with the island down and the
# topbar up, dunst is activated on demand by the bus and draws notifications
# exactly as it did before either shell existed. Killing it here would leave
# the session with no notification daemon at all.

exec quickshell -p "$CONFIG_DIR" "$@"
