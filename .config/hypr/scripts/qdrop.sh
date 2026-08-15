#!/usr/bin/env bash
# qdrop, on the workspace you are actually on.
#
# Both entry points go through here — the $alt SHIFT D key in binds.conf and
# the shake gesture in qdrop-shake.py — because both had the same bug: the
# shelf opened on the workspace its DAEMON was born on, slid perfectly into
# view, and did it where nobody was looking.
#
# WHY THE WINDOW DOES NOT MOVE ON ITS OWN
#
# qdrop HIDES BY MOVING, not by unmapping: `move()` to y=-331, off the top of
# the screen, which is what makes the slide-down reveal possible at all. A
# window that is never unmapped is never re-placed, so it stays on its
# original workspace for the life of the daemon. Under qtile the script fixes
# this in code — `_sync_to_current_qtile_group()` does a hide/togroup/remap
# through libqtile's command client on every show, and `_force_qtile_focus()`
# exists only to win back the focus that remap loses. Neither runs here.
#
# WHY NOT `pin`, WHICH IS THE OBVIOUS ANSWER AND WAS TRIED
#
# `windowrule = pin` is Hyprland's "floating window on all workspaces", and
# it broke hiding outright:
#
#     hidden, unpinned      at [371, -331]    invisible
#     hidden, PINNED        at [371,   35]    on screen, every workspace
#
# 35 is not a number anything asked for — the shelf shows at 42 and hides at
# -331 — it is the top of the usable area under the bar's reserved 33.
# HYPRLAND CLAMPS A PINNED WINDOW INTO THE MONITOR, so a window whose whole
# hide mechanism is "be off-screen" can never hide again. Reported within
# minutes of it shipping, which is the correct outcome for a rule that was
# only ever tested with the shelf VISIBLE.
#
# WHAT THIS DOES INSTEAD, AND WHY THE ORDER MATTERS
#
# Move first, THEN show. While the shelf is hidden it is parked off-screen,
# so moving it is invisible — and the reveal then happens on the workspace
# you are on. Doing it the other way round means moving a window that is
# already sliding, i.e. fighting qdrop's own move() calls frame by frame for
# the length of the animation.
#
# `movetoworkspacesilent` and not `movetoworkspace`: the latter would also
# take you to the workspace, which is precisely backwards.
#
# No window yet (first use of the session, daemon not started) is not an
# error: the dispatch quietly matches nothing and qdrop.py's own auto-spawn
# opens the window on the active workspace anyway.
set -u

QDROP="$HOME/.config/qtile/scripts/qdrop.py"

ws=$(hyprctl -j activeworkspace 2>/dev/null | sed -n 's/.*"id": *\([-0-9]*\).*/\1/p' | head -1)
if [ -n "${ws:-}" ]; then
    hyprctl dispatch movetoworkspacesilent "$ws,class:^(qdrop)$" >/dev/null 2>&1
fi

# GDK_BACKEND=x11 for the reason binds.conf gives at length: qdrop.py is GTK3
# and positions itself, which Wayland does not permit a client to do.
exec env GDK_BACKEND=x11 python3 "$QDROP" "$@"
