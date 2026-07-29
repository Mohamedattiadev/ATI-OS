#!/usr/bin/env python3
"""mpv_manager test suite. Pure-logic tests -- no running qtile required.

Run: python3 mpv_manager_test.py
Exits non-zero on failure.

Covers the parts that broke before or are easiest to break silently: the qtile
window API contract, the aspect fitting maths, PiP detection, state
persistence, multi-window targeting and stacking, and the toggle state machine.
"""
from __future__ import annotations

import json
import logging
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mpv_manager as M  # noqa: E402

# Several tests deliberately feed in broken input (a class with no qtile API, a
# corrupt state file), and the module logs about it as designed. Silence that so
# the pass/fail list stays readable -- the assertions, not the logs, are the test.
M.logger.setLevel(logging.CRITICAL)
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


class FakeScreen:
    def __init__(self, x=0, y=0, width=1366, height=768):
        self.x, self.y, self.width, self.height = x, y, width, height


class FakeGroup:
    def __init__(self, screen=None, name="1"):
        self.screen = screen
        self.name = name


class FakeWindow:
    """Records placements so tests can assert on the final geometry."""

    def __init__(self, wid=1, w=640, h=480, wm_class=("mpv", "mpv"), group=None):
        self.wid = wid
        self.width, self.height = w, h
        self.x = self.y = 0
        self._wm_class = list(wm_class)
        self.group = group or FakeGroup(FakeScreen())
        self.kept_above = None
        self.placements = []
        self.togroup_calls = []

    def get_wm_class(self):
        return self._wm_class

    def togroup(self, name):
        self.togroup_calls.append(name)

    def keep_above(self, enable=None):
        self.kept_above = enable

    def bring_to_front(self):
        pass

    def _enablefloating(self, x=None, y=None, w=None, h=None, new_float_state=None):
        self.x, self.y, self.width, self.height = x, y, w, h
        self.placements.append((x, y, w, h))


def make_manager(*windows, focused=None):
    """Manager tracking the given fake windows, with qtile lookups stubbed."""
    m = M.MPVManager()
    for win in windows:
        m.tracked[win.wid] = {
            "win": win,
            "aspect": win.width / win.height,
            "pip": False,
        }
    m.last_wid = windows[-1].wid if windows else None
    m._live = lambda: m.tracked
    m._persist = lambda: None
    m._focused = focused
    # target() consults qtile.current_window; emulate it without qtile
    def target():
        if m._focused is not None and m._focused.wid in m.tracked:
            return m._focused
        if m.last_wid in m.tracked:
            return m.tracked[m.last_wid]["win"]
        return next(iter(m.tracked.values()))["win"] if m.tracked else None

    m.target = target
    return m


# ---------------------------------------------------------------- API contract
print("api contract")
missing = M.check_window_api()
check("no required qtile window method missing", missing == [], f"missing={missing}")
try:
    from libqtile.backend.x11.window import Window as XWindow

    check("_enablefloating present (fast placement path)", hasattr(XWindow, "_enablefloating"))
except Exception as e:  # pragma: no cover
    check("x11 Window importable", False, str(e))
check(
    "check_window_api reports a broken API",
    M.check_window_api(window_cls=object) == list(M.REQUIRED_WINDOW_API),
)

# ------------------------------------------------------------------ aspect fit
print("aspect fitting")
for aspect, box, expected in [
    (4 / 3, (320, 768), (320, 240)),
    (16 / 9, (320, 768), (320, 180)),
    (4 / 3, (819, 384), (512, 384)),   # height-limited: clamps and rescales width
    (16 / 9, (819, 384), (683, 384)),
    (2.35, (320, 768), (320, 136)),
]:
    got = M.fit(aspect, *box)
    check(f"fit(aspect={aspect:.3f}, box={box}) == {expected}", got == expected, f"got={got}")

w, h = M.fit(4 / 3, 320, 768)
check("fitted box preserves aspect", abs((w / h) - 4 / 3) < 0.01, f"{w}x{h}")

# --------------------------------------------------------------- pip detection
print("pip detection")
check("PiP-width window detected", M.MPVManager._looks_like_pip(FakeWindow(w=M.PIP_W)))
check("normal window not detected", not M.MPVManager._looks_like_pip(FakeWindow(w=640)))
check("object without width is not a crash", not M.MPVManager._looks_like_pip(object()))

# ------------------------------------------------------------------- placement
print("placement geometry")
screen = FakeScreen()
win = FakeWindow(group=FakeGroup(screen))
m = make_manager(win)

m.tracked[win.wid]["pip"] = True
m.set_pip_mode(win)
exp = (screen.width - 320 - M.PIP_MARGIN, screen.height - 240 - M.PIP_MARGIN, 320, 240)
check(f"pip geometry == {exp}", win.placements[-1] == exp, f"got={win.placements[-1]}")
check("pip sets keep_above True", win.kept_above is True)
check("pip is a single placement", len(win.placements) == 1, f"{len(win.placements)}")

win.placements.clear()
m.tracked[win.wid]["pip"] = False
m.set_center_mode(win)
cw, ch = 512, 384
exp = ((screen.width - cw) // 2, (screen.height - ch) // 2, cw, ch)
check(f"centre geometry == {exp}", win.placements[-1] == exp, f"got={win.placements[-1]}")
check("centre clears keep_above", win.kept_above is False)
check("centre is a single placement", len(win.placements) == 1, f"{len(win.placements)}")

# second monitor: placement must use the window's screen, not screen 1
far = FakeScreen(x=1366, y=0, width=1920, height=1080)
win2 = FakeWindow(wid=2, w=1920, h=1080, group=FakeGroup(far))
m2 = make_manager(win2)
m2.tracked[2]["pip"] = True
m2.set_pip_mode(win2)
x, y, w, h = win2.placements[-1]
check("pip lands on the window's own screen", x >= far.x, f"x={x} screen.x={far.x}")
check("pip stays inside that screen", x + w <= far.x + far.width and y + h <= far.y + far.height)

# --------------------------------------------------------- multi-window target
print("multi-window targeting")
a = FakeWindow(wid=10, group=FakeGroup(screen))
b = FakeWindow(wid=11, group=FakeGroup(screen))
m = make_manager(a, b)
check("defaults to most recent", m.target() is b)
m._focused = a
check("prefers the focused mpv", m.target() is a)
m._focused = FakeWindow(wid=99)  # focused window that is not mpv
check("ignores a non-tracked focused window", m.target() is b)

m = make_manager(a, b, focused=a)
m.toggle_pip_mode()
check("toggling acts on the focused window", m.tracked[10]["pip"] is True)
check("the other window is untouched", m.tracked[11]["pip"] is False)

# ------------------------------------------------------------ multi-window pip
print("multi-window pip stacking")
a = FakeWindow(wid=10, w=640, h=480, group=FakeGroup(screen))   # 4:3 -> 240 tall
b = FakeWindow(wid=11, w=1920, h=1080, group=FakeGroup(screen))  # 16:9 -> 180 tall
m = make_manager(a, b)
m.tracked[10]["pip"] = True
m.tracked[11]["pip"] = True
m.restack_pips()
ay = a.placements[-1][1]
by = b.placements[-1][1]
check("first pip sits in the corner", ay == screen.height - 240 - M.PIP_MARGIN, f"y={ay}")
check(
    "second pip stacks above the first, no overlap",
    by + b.placements[-1][3] <= ay - M.PIP_GAP + 1,
    f"first_y={ay} second_y={by}",
)
check("both pips share the right edge", a.placements[-1][0] == b.placements[-1][0])

# closing the lower one must pull the upper one down into the free slot
b.placements.clear()
m.on_mpv_killed(a)
check("survivor moves into the freed slot", b.placements[-1][1] == screen.height - 180 - M.PIP_MARGIN,
      f"y={b.placements[-1][1] if b.placements else None}")
check("killed window is untracked", 10 not in m.tracked)

# ------------------------------------------------------------------- state I/O
print("state persistence")
with tempfile.TemporaryDirectory() as td:
    path = os.path.join(td, "sub", "mpv_state.json")
    M.save_state({7: {"pip": True, "aspect": 1.5}, 8: {"pip": False, "aspect": 1.777}}, path=path)
    got = M.load_state(path)
    check("state round-trips", got == {7: {"pip": True, "aspect": 1.5}, 8: {"pip": False, "aspect": 1.777}}, f"got={got}")
    check("no temp file left behind", not os.path.exists(path + ".tmp"))
    check("missing file returns {}", M.load_state(os.path.join(td, "nope.json")) == {})
    with open(path, "w") as fh:
        fh.write("{not json")
    check("corrupt state returns {} rather than raising", M.load_state(path) == {})
    with open(path, "w") as fh:
        json.dump([1, 2, 3], fh)
    check("non-dict state returns {}", M.load_state(path) == {})
    with open(path, "w") as fh:
        json.dump({"windows": {"5": "nonsense", "6": {"pip": True, "aspect": 1.5}}}, fh)
    check("bad entries skipped, good ones kept", M.load_state(path) == {6: {"pip": True, "aspect": 1.5}})

# --------------------------------------------------------------- state machine
print("toggle state machine")
win = FakeWindow(wid=1, group=FakeGroup(screen))
m = make_manager(win)
calls = []
m.set_pip_mode = lambda w: calls.append("pip")
m.set_center_mode = lambda w: calls.append("centre")
m.restack_pips = lambda: None

m.toggle_pip_mode()
check("centre -> pip", m.tracked[1]["pip"] and calls == ["pip"], f"calls={calls}")
m.toggle_pip_mode()
check("pip -> centre", not m.tracked[1]["pip"] and calls == ["pip", "centre"], f"calls={calls}")

# nothing tracked: must not raise
empty = M.MPVManager()
empty._live = lambda: {}
empty.target = lambda: None
empty.adopt_existing = lambda: None
empty.toggle_pip_mode()
check("no mpv window is a no-op, not a crash", empty.tracked == {})

# reapply must follow each window's own mode
a = FakeWindow(wid=10, group=FakeGroup(screen))
b = FakeWindow(wid=11, group=FakeGroup(screen))
m = make_manager(a, b)
m.tracked[10]["pip"] = True
seen = []
m.set_pip_mode = lambda w: seen.append(("pip", w.wid))
m.set_center_mode = lambda w: seen.append(("centre", w.wid))
m.reapply()
check("reapply follows per-window mode", sorted(seen) == [("centre", 11), ("pip", 10)], f"seen={seen}")

# ----------------------------------------------------------------- mpv match
print("class matching")
check("mpv matches", M._is_mpv(FakeWindow(wm_class=("mpv", "mpv"))))
check("mpvk matches", M._is_mpv(FakeWindow(wm_class=("mpvk", "mpvk"))))
check("case-insensitive", M._is_mpv(FakeWindow(wm_class=("MPV", "MPV"))))
check("alacritty does not match", not M._is_mpv(FakeWindow(wm_class=("Alacritty", "Alacritty"))))
check("empty class does not match", not M._is_mpv(FakeWindow(wm_class=())))

print()
if FAILS:
    print(f"FAILED {len(FAILS)}/{PASSES + len(FAILS)}: {', '.join(FAILS)}")
    sys.exit(1)
print(f"all {PASSES} checks passed")
