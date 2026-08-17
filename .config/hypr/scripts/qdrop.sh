#!/usr/bin/env bash
# qdrop — the drop shelf, on the workspace you are actually on.
#
# ONE entry point for both ways in: the $alt SHIFT D key in binds.conf and the
# shake gesture in qdrop-shake.py. It picks the SHELF as well as the workspace,
# and the order it tries them in is the point of the file.
#
# ---------------------------------------------------------------------------
#  1. THE QUICKSHELL SHELF, IF A SHELL IS UP
# ---------------------------------------------------------------------------
#
# quickshell/tide-island-fork/qml/qdrop/QdropShelf.qml. It is preferred and
# not merely offered, because the GTK shelf has a defect no amount of work on
# it can fix. Driven with scripts/test/dnd-peer.py:
#
#     XWayland source -> GTK shelf         drop in and drag out both work
#     WAYLAND source  -> GTK shelf         drag begins, NOTHING arrives
#     WAYLAND source  -> QUICKSHELL shelf  both directions, measured:
#                                          in  -> {"type":"file","value":…}
#                                          out -> the peer got the file URI
#
# pcmanfm-qt runs QT_QPA_PLATFORM=wayland;xcb, so the file manager you would
# actually drag from is on the side the GTK shelf cannot hear. The Quickshell
# one is a layer surface on the Wayland side, which is the whole reason it
# exists.
#
# `qs ipc call` EXITS 255 WITH NO INSTANCE and prints "Function not found"
# while still exiting 0 — the RULES record both — so the fallthrough below
# tests the exit code and nothing else. The island is tried first because it
# is the default bar; popups.qml is the same target and the same function
# names, hosted there for the sessions bar-switch has put the topbar on.
#
# ---------------------------------------------------------------------------
#  2. THE GTK SHELF, OTHERWISE
# ---------------------------------------------------------------------------
#
# Kept, not deleted, and it is a real fallback rather than a courtesy: with
# `bar-mode` on qtile's own bar there is no Quickshell process at all, and the
# GTK shelf is the only shelf there is. It also still owns `--add-text`, which
# is the CLI everything else feeds the shelf through.
#
# WHY IT NEEDS THE WORKSPACE DANCE AND THE QUICKSHELL ONE DOES NOT
#
# qdrop.py HIDES BY MOVING its window to y=-331, off the top of the screen,
# which is what makes its slide-down reveal possible. A window that is never
# unmapped is never re-placed, so it stays on the workspace its daemon was
# born on and `--show` from anywhere else reveals it where nobody is looking.
# Under qtile the script fixes this itself, through libqtile's command client;
# there is no libqtile here.
#
# Move FIRST, then show. While hidden the window is off-screen, so moving it
# is invisible and the reveal happens where you are. The other order means
# moving a window that is already sliding.
#
# NOT `windowrule = pin`, which was tried and shipped and reported broken
# within minutes: Hyprland CLAMPS a pinned window into the monitor, so the
# hidden [371, -331] became [371, 35] and the shelf sat on screen on every
# workspace with no way to hide it.
#
# A layer surface has no workspace at all, so none of this applies to the
# Quickshell shelf — which is one of the four defects that rewrite closed.
set -u

FORK="$HOME/.config/quickshell/tide-island-fork"
QDROP="$HOME/.config/qtile/scripts/qdrop.py"

# --toggle | --show | --hide  ->  toggle | open | close
#
# `open`/`close` and NOT `show`/`hide` on the IPC side: `qs ipc show` IS A
# SUBCOMMAND, so `qs ipc call qdrop show` is swallowed by the CLI, prints the
# handler's function list and EXITS 0 -- which this script would have read as
# success and never fallen through. Measured: `hide` arrived, `show` did not.
# The FLAGS keep their names, because they are qdrop.py's and every caller
# already spells them that way.
#
# `--for-drag` is the SHAKE's flag and it is not the same as `--show`. A shelf
# opened while you are carrying a file must not take an exclusive keyboard
# grab, because the grab CANCELS the in-flight Wayland drag — A/B'd on the
# same synthesised drop, everything else held constant: with the grab
# `entries 9 -> 9`, without it `9 -> 10`. The Quickshell shelf takes the
# keyboard the moment the drop lands. The GTK shelf has no such distinction,
# so the flag collapses back to --show for it.
action="${1:---toggle}"
case "${action#--}" in
    toggle)   verb="toggle" ;;
    show)     verb="open" ;;
    for-drag) verb="openForDrag" ;;
    hide)     verb="close" ;;
    *)        verb="" ;;   # --add-text and friends are the GTK shelf's alone
esac

# TWO Quickshell targets, not one, and they are different INSTANCES rather
# than two names for the same one: `qs -p <dir>` keys on the path it was
# GIVEN, so the island (the directory) and the popups shell (a file inside
# it) are addressed separately. This tree already has the rule the hard way —
# "a process matcher must compare an ARGUMENT", from the day `bar-switch
# island` mistook popups.qml for the island and left the desktop with no bar.
#
# Island first because it is the default bar. `qs ipc call` exits 255 with NO
# INSTANCE, which is what makes the chain work; it also prints "Function not
# found" and still exits 0, which is why the verbs are open/close and never
# `show`.
if [ -n "$verb" ]; then
    for target in "$FORK" "$FORK/popups.qml"; do
        if qs -p "$target" ipc call qdrop "$verb" >/dev/null 2>&1; then
            exit 0
        fi
    done
fi

ws=$(hyprctl -j activeworkspace 2>/dev/null | sed -n 's/.*"id": *\([-0-9]*\).*/\1/p' | head -1)
if [ -n "${ws:-}" ]; then
    hyprctl dispatch movetoworkspacesilent "$ws,class:^(qdrop)$" >/dev/null 2>&1
fi

# GDK_BACKEND=x11 for the reason binds.conf gives at length: qdrop.py is GTK3
# and positions itself, which Wayland does not permit a client to do.
# The GTK shelf has no drag-aware open, so --for-drag is just a show.
[ "$action" = "--for-drag" ] && set -- --show
exec env GDK_BACKEND=x11 python3 "$QDROP" "$@"
