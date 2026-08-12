#!/usr/bin/env python3
"""above_fullscreen test suite. Pure-logic tests -- no running qtile required.

Run: python3 above_fullscreen_test.py
Exits non-zero on failure.

Covers the promotion state machine, which is the part with teeth: a promotion
that is never released is a window stuck on top of a fullscreen one with no
obvious way to shift it, and a promotion granted at the wrong moment covers a
fullscreen window that nothing was supposed to cover.
"""
from __future__ import annotations

import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import above_fullscreen as A  # noqa: E402

A.logger.setLevel(logging.CRITICAL)
logging.getLogger("libqtile").setLevel(logging.CRITICAL)

FAILS = []
PASSES = 0


def check(label, cond, detail=""):
    global PASSES
    if cond:
        PASSES += 1
        print(f"  ok   {label}")
    else:
        FAILS.append(label)
        print(f"  FAIL {label} {detail}")


class FakeGroup:
    def __init__(self, name="1"):
        self.name = name
        self.windows = []


class FakeWindow:
    def __init__(self, wid, group=None, fullscreen=False, name=None):
        self.wid = wid
        self.name = name or f"win{wid}"
        self.fullscreen = fullscreen
        self.group = group
        self.layer_raises = 0
        if group is not None:
            group.windows.append(self)

    def change_layer(self, up=True, top_bottom=False):
        self.layer_raises += 1


class FakeRoot:
    """Stands in for the X root window's stacking order, bottom-first."""

    def __init__(self, order):
        self._order = list(order)

    def query_tree(self):
        return list(self._order)


class FakeCore:
    def __init__(self, order):
        self._root = FakeRoot(order)


class FakeQtile:
    def __init__(self, order):
        self.core = FakeCore(order)


def reset():
    A._promoted.clear()
    A._reassert_pending = False
    A._started = True  # the startup gate; tested separately below
    A.qtile = _REAL_QTILE


_REAL_QTILE = A.qtile


# ------------------------------------------------------------------- promoting
print("promotion")
reset()
g = FakeGroup()
video = FakeWindow(1, g, fullscreen=True)
term = FakeWindow(2, g)
A._promote_new_window(term)
check("a window opening during fullscreen is promoted", A.is_promoted(term))
check("the fullscreen window itself is not", not A.is_promoted(video))

reset()
g = FakeGroup()
quiet = FakeWindow(3, g)
A._promote_new_window(FakeWindow(4, g))
check("nothing is promoted when nothing is fullscreen", not A._promoted)

# An app that maps already fullscreen (a game, mpv --fs) is the cover, not the
# covered -- promoting it would pin it above every later fullscreen window.
reset()
g = FakeGroup()
game = FakeWindow(5, g, fullscreen=True)
A._promote_new_window(game)
check("a window that maps already fullscreen is not promoted", not A.is_promoted(game))

reset()
A._promote_new_window(FakeWindow(6, None))
check("a window with no group is skipped, not crashed on", not A._promoted)

# ------------------------------------------------------------------- releasing
print("release")
reset()
g = FakeGroup()
video = FakeWindow(7, g, fullscreen=True)
term = FakeWindow(8, g)
A._promote_new_window(term)
A._release_when_fullscreen_ends()
check("promotion survives while the window stays fullscreen", A.is_promoted(term))

video.fullscreen = False
A._release_when_fullscreen_ends()
check("promotion is released when fullscreen ends", not A.is_promoted(term))
check("the released window is restacked back into place", term.layer_raises >= 1)

# The escape hatch the docstring promises: Mod+f twice gives a clean
# fullscreen, because re-entering starts from an empty registry.
video.fullscreen = True
A._release_when_fullscreen_ends()
check("re-entering fullscreen does not revive the promotion", not A.is_promoted(term))

# Two monitors: a fullscreen window on one group must not keep the other
# group's promotions alive.
reset()
g1, g2 = FakeGroup("1"), FakeGroup("2")
still_full = FakeWindow(9, g1, fullscreen=True)
kept = FakeWindow(10, g1)
done = FakeWindow(11, g2)
A._promote_new_window(kept)
A._promoted[done.wid] = done  # as if g2 had been fullscreen a moment ago
A._release_when_fullscreen_ends()
check("promotion on the still-fullscreen group is kept", A.is_promoted(kept))
check("promotion on the other group is released", not A.is_promoted(done))

print("closing and restart")
reset()
g = FakeGroup()
video = FakeWindow(12, g, fullscreen=True)
term = FakeWindow(13, g)
A._promote_new_window(term)
A._forget_closed_window(term)
check("closing a promoted window forgets it", not A._promoted)

# wids are recycled by the X server; a promotion must not land on whatever
# inherits the number.
reset()
g = FakeGroup()
video = FakeWindow(14, g, fullscreen=True)
term = FakeWindow(15, g)
A._promote_new_window(term)
recycled = FakeWindow(15, g)
check("a different window reusing the wid is not promoted", not A.is_promoted(recycled))

# A restart re-manages every pre-existing window through client_managed while
# the fullscreen window is still fullscreen. Without the gate, all of them get
# promoted at once and the burst of restacking that follows disturbs the
# window order the restart has just restored.
reset()
A._started = False
g = FakeGroup()
video = FakeWindow(16, g, fullscreen=True)
a, b = FakeWindow(17, g), FakeWindow(18, g)
A._promote_new_window(a)
A._promote_new_window(b)
check("the startup scan promotes nothing", not A._promoted)
check("and restacks nothing", a.layer_raises == 0 and b.layer_raises == 0)
A._enable_promotions()
check("startup_complete opens the gate", A._started)
A._promote_new_window(a)
check("a window opening after startup is promoted normally", A.is_promoted(a))

# ------------------------------------------------------------------- deferral
print("deferred re-assert")
reset()
g = FakeGroup()
video = FakeWindow(19, g, fullscreen=True)
term = FakeWindow(20, g)
A._promoted[term.wid] = term
term.layer_raises = 0
# No event loop here, so reassert_soon must fall through to doing the work
# rather than latch the flag and no-op forever after.
A.reassert_soon()
check("falls back to an immediate re-assert without a loop", term.layer_raises == 1,
      f"raises={term.layer_raises}")
check("pending flag is cleared for the next call", not A._reassert_pending)
A.reassert_soon()
check("a later call still re-asserts", term.layer_raises == 2, f"raises={term.layer_raises}")

reset()
term.layer_raises = 0
A.reassert_soon()
check("nothing is scheduled with an empty registry", term.layer_raises == 0)

# ------------------------------------------------------------- the quiet path
# The order check is what stops the hover flicker: this runs on every focus
# change, so it must send nothing when the stacking is already right.
print("order check (no needless restacking)")
reset()
g = FakeGroup()
video = FakeWindow(21, g, fullscreen=True)
term = FakeWindow(22, g)
A._promote_new_window(term)
term.layer_raises = 0

A.qtile = FakeQtile([video.wid, term.wid])  # term already on top
A.reassert()
check("no restack when the promoted window is already above", term.layer_raises == 0,
      f"raises={term.layer_raises}")

A.qtile = FakeQtile([term.wid, video.wid])  # term has sunk below
A.reassert()
check("restacks once the promoted window has sunk", term.layer_raises == 1,
      f"raises={term.layer_raises}")

# A window that left fullscreen is not "covering" anything, so a promoted
# window under it is not a problem to fix -- the release path handles it.
video.fullscreen = False
term.layer_raises = 0
A.reassert()
check("no restack when nothing is fullscreen any more", term.layer_raises == 0)

# Unreadable stack: act rather than leave a window buried.
reset()
g = FakeGroup()
video = FakeWindow(23, g, fullscreen=True)
term = FakeWindow(24, g)
A._promote_new_window(term)
term.layer_raises = 0
A.qtile = _REAL_QTILE  # no core._root to query
A.reassert()
check("restacks blind when the stack cannot be read", term.layer_raises == 1,
      f"raises={term.layer_raises}")
reset()

print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print(f"all {PASSES} checks passed")
