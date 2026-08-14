#!/usr/bin/env bash
# island.sh — launch the FORKED Tide Island instead of the packaged one.
#
# Why a fork at all
# ----------------
# Three things the user asked for cannot be reached from Tide Island's
# 45 config keys, and are therefore fork-or-nothing:
#
#   * animation speed  — there is no animation key of any kind; the
#                        capsule's morphDuration is a QML literal
#   * the notch morph  — the capsule is a plain rounded Rectangle, so
#                        square top corners and the concave flare need a
#                        real Shape path, not a property
#   * a theme picker   — the island ships a wallpaper picker and no
#                        theme picker, and `showCustom()` takes no
#                        arguments so arbitrary text cannot be pushed in
#
# Why this shape of fork
# ----------------------
# `shell.qml` imports `IslandBackend`, a compiled C++/Qt QML module. We
# cannot rebuild that without the package's whole CMake/Qt build, and we
# do not want to: the backend is the part we have no quarrel with.
#
# VERIFIED (see REQUIREMENTS.md): a QML tree living anywhere on disk can
# still `import IslandBackend`, because /usr/lib/qt6/qml is one of Qt's
# default import paths and the package installs the module there. So the
# fork is QML-only — we vendor the ~44 .qml files, patch them, and keep
# the packaged backend. `quickshell -p <dir>` accepts any directory.
#
# What is deliberately NOT vendored: bin/lyricsmpris, a 356K ELF helper.
# A binary blob in a dotfiles repo is a liability, and the packaged copy
# is the same file — so we point the backend at it via the env var the
# upstream launcher uses.
#
# Consequence to remember: `pacman -Syu` upgrading tide-island updates
# /usr/share/tide-island but NOT the fork. Diff them after an upgrade:
#
#     diff -ru /usr/share/tide-island/qml \
#              ~/.config/quickshell/tide-island-fork/qml
#
# and re-apply anything upstream changed. FORK-NOTES.md in the fork
# directory lists every patch we made, for exactly that merge.

set -euo pipefail

FORK_DIR="${TIDE_ISLAND_FORK_DIR:-$HOME/.config/quickshell/tide-island-fork}"
PKG_DIR="/usr/share/tide-island"

if [[ ! -f "$FORK_DIR/shell.qml" ]]; then
  # Fall back rather than leave the session bar-less. A missing fork means
  # stow has not run yet on a fresh machine; the packaged island is still
  # a working bar, just an unpatched one.
  echo "island.sh: no fork at $FORK_DIR — falling back to the package" >&2
  exec tide-island "$@"
fi

# The lyrics backend is looked up by absolute path at runtime, so it has to
# be handed over explicitly now that we no longer run through the packaged
# launcher that sets it.
export QUICKSHELL_LYRICS_BACKEND="${QUICKSHELL_LYRICS_BACKEND:-$PKG_DIR/bin/lyricsmpris}"

# Carried over verbatim from the packaged launcher. Quickshell uses
# jemalloc, which otherwise keeps every Loader/image high-water mark
# resident for the life of the session — and this island loads a lot of
# wallpaper thumbnails.
export MALLOC_CONF="${MALLOC_CONF:-narenas:2,background_thread:true,dirty_decay_ms:2000,muzzy_decay_ms:2000}"

# ---- CLEAR DUNST OFF THE NOTIFICATION BUS BEFORE STARTING ----
#
# The island SERVES org.freedesktop.Notifications now (see
# quickshell/tide-island-fork/qml/common/NotificationService.qml), and dunst
# is no longer in autostart.conf. That is not enough on its own, because
# dunst ships a D-Bus ACTIVATION file:
#
#     /usr/share/dbus-1/services/org.knopwob.dunst.service
#
# so the bus starts it on demand whenever a notification is sent and nobody
# owns the name. That is a feature — it is what makes notifications keep
# working with the shell down, and it is why removing dunst from autostart
# carries none of the "notifications stop system-wide" hazard the plan
# feared. Measured: with the island killed, `busctl --user list` reports the
# name as "(activatable)" and `notify-send` still succeeds.
#
# The cost is an ordering trap. A well-known bus name has ONE owner: island
# down, something notifies, dunst is activated and takes the name; the
# island then starts and cannot have it. Nothing errors. The island runs,
# draws, answers its IPC — and never receives a notification, which looks
# exactly like the feature was never built.
#
# What happens next was measured twice and came out DIFFERENTLY each time.
# Once, an island started under dunst took the name the instant dunst
# exited, i.e. it had queued. Once, killing dunst left the name unowned with
# the island still running and still not serving. Non-deterministic is worse
# than either answer, and this line removes the question rather than betting
# on which behaviour is the real one.
#
# Safe, because dunst is activatable: anything that needs it later starts it
# again by itself. Deliberately not `dunstctl close-all` or any graceful
# variant — the point is to release the NAME, and only exiting does that.
#
# Verified end to end: with dunst holding the name and no island running,
# this script produces owner=quickshell, dunst gone, in one step.
pkill -x dunst 2>/dev/null || true

# ---- THE SESSION SURFACES BELONG TO WHICHEVER SHELL IS UP ----
#
# treetab.qml and popups.qml are SESSION surfaces, not bar widgets: the island
# hosts them when it is up, and topbar.sh starts them as standalone processes
# when it is not. bar-switch's `topbar_stop` therefore stops both before
# starting the island, and NEXT-SESSION.md says why in as many words — "or the
# island would come back to a second sidebar and a second set of popups
# holding an exclusive keyboard grab".
#
# That rule lived only in bar-switch, so it held only for the ONE route that
# goes through bar-switch. Starting the island any other way — by hand, from a
# test harness, from this script — left the standalone pair running and drew
# TWO TreeTab sidebars side by side, each with its own stack list. Reported
# with a screenshot, and produced by this session's own sweep tooling, which
# tells you to start the island beside the topbar.
#
# So the invariant moves to the thing that can always enforce it: whoever
# starts the island stops them. Idempotent — nothing to stop is the common
# case — and it does NOT stop the topbar itself, because running the island
# beside the topbar deliberately IS supported (that is how a sweep avoids
# leaving the session with no bar). It is only the duplicated surfaces that
# cannot coexist.
#
# Matched on the `-p` ARGUMENT, never with `pkill -f`: two entry points live
# inside this directory, and a substring match on the directory name would
# take the island down with them. bar-switch's own matcher records the bug
# that taught this — `bar-switch island` once saw popups.qml, decided the
# island was up, stopped the topbar and left the desktop with no bar.
stop_standalone_surface() {
    local entry="$1" pid
    pid="$(ps -eo pid=,args= | awk -v want="$entry" '
        !/awk/ { for (i = 1; i < NF; i++)
                     if ($i == "-p" && $(i + 1) == want) { print $1; exit } }')"
    [[ -n "$pid" ]] || return 0
    kill "$pid" 2>/dev/null || true
}

stop_standalone_surface "$FORK_DIR/treetab.qml"
stop_standalone_surface "$FORK_DIR/popups.qml"

exec quickshell -p "$FORK_DIR" "$@"
