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

exec quickshell -p "$FORK_DIR" "$@"
