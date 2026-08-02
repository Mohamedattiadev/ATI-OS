#!/usr/bin/env python3
"""qdrop shake detector.

Watches xinput --test-xi2 --root for Button1-held rapid pointer-direction
reversals. Uses RAW events (not blocked by X grabs during XDND drag).
Tracks button state from RawButtonPress/Release, position deltas from
RawMotion valuators.

Two gates decide whether a wiggle counts as a shake:

1. Shape -- enough direction reversals on *either* axis inside
   TIME_WINDOW_S. Left-right, up-down and diagonal shakes all qualify:
   a diagonal shake reverses both axes at once, so whichever axis
   crosses the threshold first fires.

2. Payload -- an XDND drag must actually be in flight, and the data it
   offers must look like a file/folder/image. This is what stops a
   plain click-drag (extending a text selection, rubber-band selecting
   on the desktop, dragging a window, panning a canvas) from opening
   qdrop: none of those own the XdndSelection, so there is nothing to
   drop and nothing to show. See `dnd_payload()`.

3. Not a window move -- qtile binds window move/resize to
   Super+Button1/Button3 (`config.py` `mouse = [...]`), so a shake with
   Super held is the user throwing a window around, never a file drag.
   See `_wm_mods_held()`.

Gate 2 has a sharp edge: toolkits acquire XdndSelection when a drag
starts but do *not* disown it when the drag ends, so after the first
real file drag of a session the selection stays owned forever. Bare
ownership therefore answers "has anything ever been dragged", not "is
something being dragged now" -- which is why moving a window could pop
qdrop open. Liveness comes from XFixes instead: we subscribe to
SetSelectionOwner notifications on XdndSelection and require the
current ownership to have been claimed *after* the button went down.
Every toolkit re-acquires the selection on each drag begin, so a real
drag always re-arms it. Without XFixes the gate degrades to the old
bare-ownership test.

Because gate 2 does the false-positive filtering that the old
horizontal-dominant heuristic (MIN_DX_DY_RATIO) used to do, that
heuristic is gone -- it was the only reason up/down shakes were
ignored.

Fires `qdrop --show` on shake. Motion outside a button1 drag is ignored,
so closing the window and moving the mouse never re-triggers.

Flags:
  --debug      log every gesture decision (why a shake did/didn't fire)
  --any-drag   skip gate 2 -- fire on any Button1 shake (old behaviour)
"""
import collections
import ctypes
import ctypes.util
import os
import re
import subprocess
import sys
import threading
import time

REVERSALS_NEEDED = 2  # was 3 -- reported needing a hard/deliberate shake to fire
TIME_WINDOW_S = 1.2  # was 1.0 -- more time to land fewer required reversals
MIN_SEG_PX = 6  # was 8 -- smaller wiggles now count as a reversal segment
DEBOUNCE_S = 1.2
COOLDOWN_AFTER_RELEASE_S = 0.2

# How far *before* the button press an XdndSelection claim may land and
# still count as belonging to this drag. Covers the ordering slop
# between xinput's line reaching us and the XFixes notify reaching the
# watcher thread; anything older than this is a leftover from a
# previous drag.
CLAIM_SLACK_S = 0.3

MOD4_MASK = 1 << 6  # Super -- qtile's `mod`, used for window move/resize

QDROP = os.path.expanduser("~/.config/qtile/scripts/qdrop.py")

DEBUG = "--debug" in sys.argv
REQUIRE_DND = "--any-drag" not in sys.argv


def log(msg: str):
    print(f"[qdrop_watch] {msg}", flush=True)


def dlog(msg: str):
    if DEBUG:
        log(msg)


# --- XDND probe ---------------------------------------------------------
# During any X11 drag-and-drop the source owns the XdndSelection
# selection for the whole duration of the drag, and releases it on drop
# or cancel. Ownership is therefore an exact "is something picked up
# right now" test -- and it is readable from another process, unlike
# GDK's gdk_selection_owner_get() which only ever reports selections
# owned by the calling app.
#
# When the source offers more than 3 data types it also publishes them
# as an atom list in the XdndTypeList property on the source window; we
# read that to tell a file/folder/image drag from a pure text drag. With
# <= 3 types the list lives in the ClientMessage that only the drop
# target sees, so the property is absent -- in that case we accept the
# drag (something *is* being carried; we just can't see what).

_X11 = None
_DPY = None
_ATOMS: dict = {}
_ERR_HANDLER = None

FILE_TYPE_HINTS = (
    "text/uri-list",  # files/folders from every file manager
    "x-special/gnome-copied-files",
    "application/x-kde-cutselection",
    "application/x-kde4-urilist",
    "image/",  # image/png, image/jpeg, ... dragged from browsers/editors
    "application/x-qt-image",
    "application/octet-stream",
    "xdnddirectsave0",  # XDS -- drag out of an archive/mail client
)


def _x_init() -> bool:
    """Open a private X connection; None-safe, retried lazily on failure."""
    global _X11, _DPY, _ERR_HANDLER
    if _DPY is not None:
        return True
    try:
        lib = ctypes.CDLL(ctypes.util.find_library("X11"))
        lib.XOpenDisplay.restype = ctypes.c_void_p
        lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        lib.XInternAtom.restype = ctypes.c_ulong
        lib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        lib.XGetSelectionOwner.restype = ctypes.c_ulong
        lib.XGetSelectionOwner.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        lib.XGetAtomName.restype = ctypes.c_void_p
        lib.XGetAtomName.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        lib.XGetWindowProperty.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
            ctypes.c_long, ctypes.c_long, ctypes.c_int, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte)),
        ]
        lib.XFree.argtypes = [ctypes.c_void_p]
        lib.XDefaultRootWindow.restype = ctypes.c_ulong
        lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        lib.XQueryPointer.restype = ctypes.c_int
        lib.XQueryPointer.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_uint),
        ]

        dpy = lib.XOpenDisplay(None)
        if not dpy:
            return False

        # A drag source can vanish between our XGetSelectionOwner and the
        # property read (BadWindow). Xlib's default handler would exit the
        # whole process for that, so swallow every X error instead.
        handler_t = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
        _ERR_HANDLER = handler_t(lambda _d, _e: 0)
        lib.XSetErrorHandler(_ERR_HANDLER)

        _X11, _DPY = lib, dpy
        return True
    except Exception as e:  # no libX11, no DISPLAY, ...
        dlog(f"X init failed: {e}")
        return False


def _atom(name: str) -> int:
    a = _ATOMS.get(name)
    if a is None:
        a = _X11.XInternAtom(_DPY, name.encode(), False)
        _ATOMS[name] = a
    return a


def _type_list(win: int) -> list:
    """Atom names in the source window's XdndTypeList, or [] if unset."""
    XA_ATOM = 4
    actual_type = ctypes.c_ulong()
    actual_fmt = ctypes.c_int()
    nitems = ctypes.c_ulong()
    after = ctypes.c_ulong()
    data = ctypes.POINTER(ctypes.c_ubyte)()
    rc = _X11.XGetWindowProperty(
        _DPY, win, _atom("XdndTypeList"), 0, 256, False, XA_ATOM,
        ctypes.byref(actual_type), ctypes.byref(actual_fmt),
        ctypes.byref(nitems), ctypes.byref(after), ctypes.byref(data),
    )
    if rc != 0 or not data or actual_fmt.value != 32 or nitems.value == 0:
        if data:
            _X11.XFree(data)
        return []
    atoms = ctypes.cast(data, ctypes.POINTER(ctypes.c_ulong))
    names = []
    for i in range(nitems.value):
        p = _X11.XGetAtomName(_DPY, atoms[i])
        if p:
            names.append(ctypes.string_at(p).decode("latin-1"))
            _X11.XFree(p)
    _X11.XFree(data)
    return names


def _wm_mods_held() -> bool:
    """True when Super is down -- i.e. this is a qtile window drag.

    qtile binds move to Drag([mod], "Button1") and resize to
    Drag([mod], "Button3") with mod = mod4, so Super being held while
    the pointer wiggles means a window is being flung around, not a
    file being carried.
    """
    if not _x_init():
        return False
    root = ctypes.c_ulong()
    child = ctypes.c_ulong()
    rx, ry, wx, wy = (ctypes.c_int() for _ in range(4))
    mask = ctypes.c_uint()
    ok = _X11.XQueryPointer(
        _DPY, _X11.XDefaultRootWindow(_DPY),
        ctypes.byref(root), ctypes.byref(child),
        ctypes.byref(rx), ctypes.byref(ry),
        ctypes.byref(wx), ctypes.byref(wy), ctypes.byref(mask),
    )
    return bool(ok) and bool(mask.value & MOD4_MASK)


# --- XDND liveness (XFixes) --------------------------------------------
# Bare selection ownership is sticky: sources acquire XdndSelection at
# drag begin and never disown it, so it stays owned long after the drop.
# Watching SetSelectionOwner notifications gives us the one thing
# ownership alone can't: *when* the current owner took it.

class _XFixesSelectionNotifyEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("subtype", ctypes.c_int),
        ("owner", ctypes.c_ulong),
        ("selection", ctypes.c_ulong),
        ("timestamp", ctypes.c_ulong),
        ("selection_timestamp", ctypes.c_ulong),
    ]


_XFIXES_OK = False
_CLAIM_LOCK = threading.Lock()
_CLAIM_AT = 0.0  # local clock time the current owner claimed XdndSelection


def _claim_time() -> float:
    with _CLAIM_LOCK:
        return _CLAIM_AT


def _watch_selection():
    """Record when XdndSelection changes hands. Runs on its own display."""
    global _XFIXES_OK, _CLAIM_AT
    try:
        xf = ctypes.CDLL(ctypes.util.find_library("Xfixes"))
        x11 = ctypes.CDLL(ctypes.util.find_library("X11"))
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XInternAtom.restype = ctypes.c_ulong
        x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        x11.XDefaultRootWindow.restype = ctypes.c_ulong
        x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x11.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        x11.XFlush.argtypes = [ctypes.c_void_p]
        xf.XFixesQueryExtension.argtypes = [
            ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
        xf.XFixesSelectSelectionInput.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]

        dpy = x11.XOpenDisplay(None)
        if not dpy:
            return
        ev_base, err_base = ctypes.c_int(), ctypes.c_int()
        if not xf.XFixesQueryExtension(dpy, ctypes.byref(ev_base), ctypes.byref(err_base)):
            log("XFixes unavailable -- falling back to bare ownership test")
            return
        sel = x11.XInternAtom(dpy, b"XdndSelection", False)
        SET_OWNER_MASK = 1 << 0
        xf.XFixesSelectSelectionInput(dpy, x11.XDefaultRootWindow(dpy), sel, SET_OWNER_MASK)
        x11.XFlush(dpy)
        _XFIXES_OK = True
        dlog("XFixes liveness gate armed")

        notify_type = ev_base.value  # XFixesSelectionNotify == subcode 0
        buf = (ctypes.c_char * 256)()
        while True:
            x11.XNextEvent(dpy, ctypes.byref(buf))
            ev = ctypes.cast(ctypes.byref(buf),
                             ctypes.POINTER(_XFixesSelectionNotifyEvent)).contents
            if ev.type != notify_type or ev.selection != sel:
                continue
            with _CLAIM_LOCK:
                _CLAIM_AT = time.time() if ev.owner else 0.0
            dlog(f"XdndSelection -> 0x{ev.owner:x}")
    except Exception as e:
        _XFIXES_OK = False
        dlog(f"selection watcher stopped: {e}")


def dnd_payload(press_time: "float | None" = None):
    """(dragging, why) for the drag in flight right now.

    dragging is True only when some window owns XdndSelection, took
    that ownership as part of the button press that is still in
    progress, and advertises types that look droppable into qdrop.
    Pass press_time=None to skip the liveness half of the test.
    """
    if not _x_init():
        return True, "no X probe -- gate disabled"
    owner = _X11.XGetSelectionOwner(_DPY, _atom("XdndSelection"))
    if not owner:
        return False, "no XDND drag in flight"
    if press_time is not None and _XFIXES_OK:
        claimed = _claim_time()
        if claimed < press_time - CLAIM_SLACK_S:
            age = press_time - claimed
            return False, f"XdndSelection owned since {age:.1f}s before this drag (stale)"
    types = _type_list(owner)
    if not types:
        # <= 3 offered types: list not published. Something is being
        # dragged, so accept -- this is the common case for a single
        # file dragged out of a file manager.
        return True, f"drag from 0x{owner:x} (types not published)"
    lowered = [t.lower() for t in types]
    for t in lowered:
        if any(h in t for h in FILE_TYPE_HINTS):
            return True, f"drag offers {t}"
    return False, f"drag offers only {','.join(types[:6])}"


# --- shake shape --------------------------------------------------------

class Axis:
    """Direction-reversal counter for one pointer axis."""

    def __init__(self, name: str):
        self.name = name
        self.reset()

    def reset(self):
        self.integrated = 0.0
        self.extreme = 0.0  # furthest point reached in the current direction
        self.sign = 0
        self.reversals: collections.deque = collections.deque()

    def feed(self, d: float, now: float) -> bool:
        """Add a delta; True when this delta completed a fresh reversal.

        A reversal needs MIN_SEG_PX of travel *back from the furthest
        point reached so far*, not just MIN_SEG_PX since the last turn.
        Measuring from the extremum is what makes a long one-way drag
        with a little hand tremor in it count as zero reversals: the 1px
        backwards flicks never retrace far enough, so they are absorbed.
        """
        if d == 0:
            return False
        self.integrated += d
        if self.sign == 0:
            if abs(self.integrated - self.extreme) >= MIN_SEG_PX:
                self.sign = 1 if self.integrated > self.extreme else -1
                self.extreme = self.integrated
            return False
        if (self.integrated - self.extreme) * self.sign > 0:
            self.extreme = self.integrated  # still going the same way
            return False
        if (self.extreme - self.integrated) * self.sign < MIN_SEG_PX:
            return False  # jitter, not a turn
        self.sign = -self.sign
        self.extreme = self.integrated
        self.reversals.append(now)
        cutoff = now - TIME_WINDOW_S
        while self.reversals and self.reversals[0] < cutoff:
            self.reversals.popleft()
        return True

    def shaking(self) -> bool:
        return len(self.reversals) >= REVERSALS_NEEDED


SCREENSHOT_TOOLS = ("satty", "flameshot", "spectacle", "gnome-screenshot",
                    "shotwell", "maim", "scrot", "grim", "slurp", "gm")


def _screenshot_active() -> bool:
    for name in SCREENSHOT_TOOLS:
        try:
            r = subprocess.run(["pgrep", "-x", name], capture_output=True, timeout=1)
            if r.returncode == 0:
                return True
        except Exception:
            continue
    return False


def fire():
    if _screenshot_active():
        log("screenshot tool active — shake ignored")
        return
    subprocess.Popen(
        [sys.executable, QDROP, "--show"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    log("shake -> show")


def main():
    threading.Thread(target=_watch_selection, daemon=True).start()
    time.sleep(0.2)  # let the watcher subscribe before the first drag

    proc = subprocess.Popen(
        ["xinput", "--test-xi2", "--root"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )

    ev_re = re.compile(r"^EVENT type\s+\d+\s+\((\w+)\)")
    detail_re = re.compile(r"^\s+detail:\s+(\d+)")
    axis_re = re.compile(r"^\s+([01]):\s+([\-\d.]+)")

    ev_type = None
    button1_down = False
    axes = {"0": Axis("x"), "1": Axis("y")}
    last_fire = 0.0
    fired_for_drag = False
    press_time = 0.0
    wm_drag = False  # Super was down at press -> qtile window move/resize

    for line in proc.stdout:
        if not line:
            continue
        c0 = line[0]
        if c0 == "E":
            m = ev_re.match(line)
            if m:
                ev_type = m.group(1)
            continue
        if c0 != " " and c0 != "\t":
            continue

        if ev_type in ("RawButtonPress", "RawButtonRelease"):
            m = detail_re.match(line)
            if m and int(m.group(1)) == 1:
                if ev_type == "RawButtonPress":
                    button1_down = True
                    fired_for_drag = False
                    press_time = time.time()
                    wm_drag = _wm_mods_held()
                    if wm_drag:
                        dlog("press with Super held -- window drag, ignoring")
                    for ax in axes.values():
                        ax.reset()
                else:
                    button1_down = False
                    time.sleep(COOLDOWN_AFTER_RELEASE_S)
            continue

        if ev_type != "RawMotion" or not button1_down or fired_for_drag or wm_drag:
            continue

        m = axis_re.match(line)
        if not m:
            continue
        ax = axes[m.group(1)]
        now = time.time()
        if not ax.feed(float(m.group(2)), now):
            continue
        if not ax.shaking():
            continue
        if now - last_fire < DEBOUNCE_S:
            continue

        if REQUIRE_DND:
            if _wm_mods_held():
                # Super grabbed mid-drag: still a window move, not a drop.
                dlog(f"{ax.name}-shake: Super held, window drag")
                ax.reversals.clear()
                continue
            dragging, why = dnd_payload(press_time)
            dlog(f"{ax.name}-shake ({len(ax.reversals)} reversals): {why}")
            if not dragging:
                # Not a real pick-up. Drop the counted reversals so the
                # same wiggle doesn't re-probe X on every motion event,
                # but keep watching -- the user may still pick something
                # up later in the same button press.
                ax.reversals.clear()
                continue
        else:
            dlog(f"{ax.name}-shake ({len(ax.reversals)} reversals): gate disabled")

        fire()
        last_fire = now
        fired_for_drag = True


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
