#!/usr/bin/env python3
"""qdrop shake detector, Wayland edition — Hyprland IPC only, no privileges.

Shake the mouse while dragging and the qdrop shelf slides in. That gesture
worked under qtile and has never worked in this session, because the thing
that implements it — ../../qtile/scripts/qdrop_watch.py — is an X11 program
and autostart.conf dropped it with the reason "replaced by special
workspaces", which was already proven wrong for qdrop.py itself.

WHY THE X11 WATCHER CANNOT SIMPLY BE STARTED HERE
-------------------------------------------------
It is the tree's own rule — an X11 tool under Hyprland succeeds and sees
nothing — and it was measured rather than assumed:

    $ xinput --test-xi2 --root          # under Hyprland
    WARNING: running xinput against an Xwayland server
    ...lists only  xwayland-pointer:1 / xwayland-relative-pointer:1
    0 RawMotion and 0 RawButton events across 5 s of real pointer motion

So gate 1 (the shake SHAPE, from RawMotion) reads nothing at all. Gate 2
(an XDND drag in flight) is just as dead for a different reason: pcmanfm-qt
runs on the Wayland backend here (QT_QPA_PLATFORM=wayland;xcb), so a native
drag never claims XdndSelection and there is no X11 protocol to observe.

WHERE THE THREE SIGNALS COME FROM INSTEAD
-----------------------------------------
1. POINTER MOTION — `cursorpos` over Hyprland's request socket, sampled at
   SAMPLE_HZ while the button is down.

   Hyprland's `.socket.sock` serves ONE REQUEST PER CONNECTION: measured, a
   second `sendall` on the same connection raises EPIPE. So the "hold one
   persistent connection" plan is not available and the loop reconnects per
   sample. That is still the cheap option by two orders of magnitude:

       reconnect + cursorpos over the socket   0.036 ms   (300 samples)
       spawning `hyprctl cursorpos`            6.02  ms   (30 samples)

   60 Hz through the socket is 2.2 ms of CPU per second of drag; 60 Hz of
   `hyprctl` would be 361 ms/s, i.e. a third of a core, which is exactly the
   kind of per-event spawning this tree already criticises elsewhere.

2. BUTTON STATE — Hyprland binds, dispatched as EVENTS, not as `exec`.

   binds.conf declares (see the qdrop block there):

       bindn   = , mouse:272, event, qdropshake:down     # + SHIFT/CTRL forms
       bindrni = , mouse:272, event, qdropshake:up

   and they arrive here on `.socket2.sock` as `custom>>qdropshake:down` /
   `custom>>qdropshake:up`. Measured on a synthesised click: `down` 2 ms
   after the press, `up` at the release. No process is spawned at all —
   `exec` would have been two `sh` spawns per click (1.80 ms each, measured)
   for the life of the session, on every click in the desktop.

   This also means the detector costs NOTHING when nothing is being dragged:
   it is blocked in select() on the event socket, and only starts sampling
   the cursor between a `down` and its `up`.

3. NOT A WINDOW MOVE — free, from Hyprland's modifier matching.

   binds.conf binds window move/resize to `bindm = $mod, mouse:272`. A bind
   declared with an empty modmask is modifier-EXACT: measured, a click with
   SUPER held produced `custom>>qdropshake:up` and NO `down` at all, because
   the release bind carries the `i` (ignore mods) flag and the press binds do
   not. So a window drag never even opens a press here, and the X11 watcher's
   `_wm_mods_held()` X-query has no counterpart to port.

   The press binds are enumerated for the modifier states a file drag can
   plausibly start in — none, SHIFT, CTRL, CTRL+SHIFT — and deliberately not
   for any state containing SUPER. The RELEASE bind is a single `i` bind so
   that it fires whatever the modifiers are doing by then: measured, a press
   made bare and released with SHIFT grabbed mid-drag still delivered `up`.

WHAT IS HONESTLY MISSING, AND WHAT IT COSTS
-------------------------------------------
The X11 watcher's gate 2 — "an actual file drag is in flight, and what it
carries looks droppable" — IS NOT REPRODUCED AND CANNOT BE. Wayland gives a
third party no view of `wl_data_device`; there is no protocol for it, and
`hyprctl`'s forty commands contain nothing about data devices or drags. What
this detector fires on is therefore the old `--any-drag` mode's condition
plus the two gates above, and the false positives that follow are real:

    shaking the pointer with button 1 held over a text area, while a
    selection is being extended                              WOULD FIRE
    shaking during a rubber-band select on a file manager    WOULD FIRE
    shaking while panning a canvas with button 1             WOULD FIRE
    shaking with nothing held                                does not fire
    shaking while dragging a window ($mod + button 1)        does not fire
    a long one-way drag with hand tremor in it               does not fire
                                                     (Axis measures from the
                                                      extremum, not the last
                                                      turn — see qdrop_watch)

That set is smaller than it looks: all three require the deliberate 2
direction reversals inside 1.2 s that REVERSALS_NEEDED/TIME_WINDOW_S ask
for, which is not a motion that happens by accident while selecting text.
It is still strictly worse than the X11 gate, and it is written down here
rather than papered over. `--dry-run` logs a would-be shake without showing
the shelf, which is how the above table was checked.

...AND THE TABLE WAS RIGHT, WHICH IS WHY THE GATES BELOW EXIST
--------------------------------------------------------------
Reported: "the drop shelf one when i select text or scroll up down it
appears". Both of the rows this file predicted WOULD FIRE, fired. With no
gate 2 available the only thing left to tighten is the SHAPE, so the shape
is now tightened in four independent ways — every one of them a property a
deliberate shake has and an accidental wiggle does not:

  1. THE CONSTANTS ARE THIS FILE'S OWN, not qdrop_watch's. They were tuned
     for RAW DEVICE DELTAS; what is fed here is the difference of two
     ACCELERATED SCREEN POSITIONS, which for the same hand movement is
     several times larger. Importing the shape and the numbers together
     therefore made this detector far MORE sensitive than the X11 one it
     was copying, on identical-looking constants. Axis reads them as module
     globals at call time, so they are overridden on the module after the
     import and the X11 watcher's own tuning is untouched.

  2. HORIZONTAL ONLY. A shake is a side-to-side gesture — it is what the
     macOS shelf this imitates means by the word, and it is what a hand
     does when it wants to say "take this". Dragging a scrollbar or a
     slider is pure VERTICAL reversal, which is the whole of the "scroll up
     down" report, and it can now never fire. qdrop_watch dropped this
     requirement deliberately, and could afford to, because its gate 2 was
     doing the filtering; there is no gate 2 here.

  3. AND THE VERTICAL TRAVEL MUST BE SMALL BESIDE IT. Horizontal-only is
     not enough on its own: a diagonal scrub reverses on x as well. Over
     the shake window the x travel has to be MIN_AXIS_RATIO times the y
     travel, which is what separates a flat sweep from a scribble.

  4. A SHAKE IS PRECEDED BY A DRAG. You cannot shake something you have not
     picked up and carried: MIN_PRESS_S and MIN_TRAVEL_PX require the
     button to have been down a moment and the pointer to have covered real
     ground before any reversal counts at all. A text selection that begins
     with a wiggle is over before either is satisfied.

AND THE FIFTH GATE, WHICH IS NOT A SHAPE AT ALL
-----------------------------------------------
Reported next, and the four above cannot catch it and should not try: "i
resize the terrmianl with cursor and opens the dropshef wtf".

`general:resize_on_border` is 1 in this config with a 15 px
`extend_border_grab_area`, so dragging a window edge is a BARE button-1 drag
-- no modifier -- and the modifier-exact trick that keeps window MOVES out
(`bindm = $mod, mouse:272`) does nothing for it. Worse, the gesture is not
merely similar to a shake, it IS one: you grab the edge and push it back and
forth to get the width right, which is horizontal, flat, well past
MIN_SEG_PX, and preceded by plenty of carrying.

So it is not separable by shape, and it does not need to be. **A resize is
not a shape, it is an OUTCOME: the window changes size.** A window move is
the same statement about position. Neither ever happens during a file drag,
and both are directly observable -- `j/activewindow` over the request socket
is 839 bytes and 0.074 ms, which is what makes it affordable on every sample
rather than on a timer a fast resize could outrun. See `Drag.note_box`.

MEASURED ON THE LIVE SESSION, both directions, driven with
scripts/test/uinput-shake.py on an empty workspace holding two windows:

    deliberate horizontal shake, mid-window     FIRES
    border drag that really resized 1005->986   refused, "compositor grab"
    the SAME border drag under --loose          FIRES        <- the control
    vertical shake (scrollbar, scroll)          quiet
    small wiggles (a text selection)            quiet
    one-way drag with tremor in it              quiet

The control row is the one that makes the others mean anything: without it
"the resize did not fire" is equally consistent with the driver having
missed, and this file has already recorded one session lost to a test that
could not fail.

WHAT THIS STILL IS NOT
----------------------
It is not "only fires while a file is in flight", which is what was asked
for and what gate 2 gave the X11 watcher. That gate cannot be rebuilt here:
Wayland gives a third party no view of `wl_data_device`, there is no
protocol for it, and `hyprctl`'s forty commands contain nothing about data
devices or drags -- checked again, not assumed. What these five gates do is
make every reported false positive impossible while leaving the deliberate
gesture working. The one shape still able to reach the shelf is a hard,
flat, sustained horizontal shake held for a third of a second over a window
that does not change size, while carrying nothing.

`--loose` restores the old behaviour, and is the CONTROL above. `--tune k=v`
overrides any one of the five numbers, so the next report can be answered
with a measurement instead of another guess.

The one route that would restore gate 2 is a Hyprland plugin (route C): the
compositor does know the drag state, and a plugin could expose it. That is a
C++ build against a moving ABI for one boolean, and it is not worth it until
the false positives are actually reported.

Reading /dev/input directly (route B) would have given both motion and
button state with no compositor involvement, and it was REJECTED on
security grounds, not technical ones: `/dev/input/event*` is `root:input`
and this user is not in `input`, so it would take a group change that lets
every process the user runs read every keystroke they type. A drop shelf is
not worth a keylogger.

THE SHAKE SHAPE IS IMPORTED, NOT COPIED
---------------------------------------
`Axis` and its four tuned constants live in qdrop_watch.py and are loaded
from there. They were tuned against a user report ("needs a hard/deliberate
shake to fire") and a second copy would be a second thing to tune. The same
argument binds.conf already makes for using qdrop.py from ../qtile/scripts
rather than copying it.

The deltas differ in kind and it does not matter: the X11 watcher feeds RAW
device deltas, this one feeds differences of accelerated screen positions.
MIN_SEG_PX is 6 px measured from the furthest point reached, and a shake
segment is 50-200 px at either end of the acceleration curve.

Flags:
  --debug     log every sample decision
  --dry-run   log the shake, do not show the shelf (false-positive counting)
  --loose     drop gates 2-5 and use qdrop_watch's constants (the old shape)
  --tune k=v  override one of MIN_SEG_PX, REVERSALS_NEEDED, TIME_WINDOW_S,
              MIN_PRESS_S, MIN_TRAVEL_PX, MIN_AXIS_RATIO
"""
import collections
import importlib.util
import json
import os
import select
import socket
import subprocess
import sys
import time

SAMPLE_HZ = 60
SAMPLE_S = 1.0 / SAMPLE_HZ

# A press with no matching release leaves this stuck "down" forever, and
# there is one way it can happen: Hyprland only considers the ACTIVE
# submap's binds, so pressing in the default submap and entering one before
# letting go loses the release. Nothing else drops it — the release bind
# fires through modifier changes, verified. 30 s is far longer than any real
# drag and far shorter than "the rest of the session".
MAX_PRESS_S = 30.0

DEBUG = "--debug" in sys.argv
DRY_RUN = "--dry-run" in sys.argv
LOOSE = "--loose" in sys.argv

SHARED = os.path.expanduser("~/.config/qtile/scripts/qdrop_watch.py")

# ---- THIS FILE'S OWN SHAPE CONSTANTS -------------------------------------
#
# See gate 1 in the header. qdrop_watch's numbers describe RAW device
# deltas; these describe differences of ACCELERATED SCREEN POSITIONS, and
# the two are not the same units. A 6 px raw segment is a flick of the
# wrist; a 6 px screen segment is nothing at all, which is why the imported
# tuning made this fire on text selection.
#
# MIN_SEG_PX      travel back from the extremum that counts as a turn
# REVERSALS_NEEDED turns inside TIME_WINDOW_S before it is a shake
# TIME_WINDOW_S   how long those turns have to land in
MIN_SEG_PX = 45.0
REVERSALS_NEEDED = 3
TIME_WINDOW_S = 1.0

# ---- GATE 4: a shake is preceded by a drag -------------------------------
# The button has to have been down this long, and the pointer to have
# covered this much ground, before any reversal is counted. Neither is true
# of the first moments of a text selection.
MIN_PRESS_S = 0.30
MIN_TRAVEL_PX = 140.0

# ---- GATE 3: flat, not scribbled -----------------------------------------
# Summed |dx| must be this many times summed |dy| across the shake window.
MIN_AXIS_RATIO = 2.5


def _apply_tuning(argv):
    """`--tune k=v` for every number above. See the header's last line."""
    g = globals()
    for i, a in enumerate(argv):
        if a != "--tune" or i + 1 >= len(argv):
            continue
        key, _, val = argv[i + 1].partition("=")
        if key not in ("MIN_SEG_PX", "REVERSALS_NEEDED", "TIME_WINDOW_S",
                       "MIN_PRESS_S", "MIN_TRAVEL_PX", "MIN_AXIS_RATIO"):
            log(f"--tune: unknown key {key!r}, ignored")
            continue
        g[key] = int(val) if key == "REVERSALS_NEEDED" else float(val)
        log(f"--tune {key}={g[key]}")


def log(msg: str):
    print(f"[qdrop-shake] {msg}", flush=True)


def dlog(msg: str):
    if DEBUG:
        log(msg)


def _load_shared():
    """Import qdrop_watch.py by path for Axis and the tuned constants.

    It is a script, not a package, and it is in the qtile tree — which is
    where it belongs, because the shape it describes is not Hyprland's. It
    has no import-time side effects: the X connection it opens is lazy and
    nothing here ever asks for it.
    """
    spec = importlib.util.spec_from_file_location("qdrop_watch", SHARED)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {SHARED}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


W = _load_shared()


def _retune_shared() -> None:
    """Give `Axis` this file's constants instead of the X11 watcher's.

    Axis.feed() reads MIN_SEG_PX and TIME_WINDOW_S as MODULE GLOBALS on
    every call, and shaking() reads REVERSALS_NEEDED the same way, so
    assigning them on the imported module is enough — no subclass, no
    parameter threading, and qdrop_watch's own values are untouched for the
    qtile session that imports it normally. See gate 1 in the header for why
    they must differ at all.
    """
    if LOOSE:
        log("--loose: keeping qdrop_watch's constants and dropping gates 2-5")
        return
    W.MIN_SEG_PX = MIN_SEG_PX
    W.REVERSALS_NEEDED = REVERSALS_NEEDED
    W.TIME_WINDOW_S = TIME_WINDOW_S
    dlog(f"shape: seg>={MIN_SEG_PX}px x{REVERSALS_NEEDED} in {TIME_WINDOW_S}s, "
         f"press>={MIN_PRESS_S}s, travel>={MIN_TRAVEL_PX}px, "
         f"x:y>={MIN_AXIS_RATIO}")


def hypr_dir() -> str:
    rt = os.environ.get("XDG_RUNTIME_DIR")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not rt or not sig:
        log("XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE unset — not in a "
            "Hyprland session, nothing to watch")
        sys.exit(1)
    return f"{rt}/hypr/{sig}"


def hypr_request(req_sock: str, cmd: bytes):
    """One request over Hyprland's request socket, or None.

    Hyprland closes the socket after answering — a second send on the same
    connection is EPIPE — so this is not a leak of connections, it is the
    protocol. Measured at 0.074 ms per round trip, which is what makes
    sampling it at 60 Hz reasonable at all: `hyprctl` is 6.02 ms.
    """
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.25)
        s.connect(req_sock)
        s.sendall(cmd)
        buf = b""
        while True:
            c = s.recv(65536)
            if not c:
                break
            buf += c
        s.close()
        return buf
    except Exception as e:
        dlog(f"request {cmd!r} failed: {e}")
        return None


def window_box(req_sock: str):
    """The focused window's (x, y, w, h), or None. See GATE 5.

    `j/activewindow` is 839 bytes here and answers in 0.074 ms, so this is
    sampled on the same tick as the cursor rather than on a slower timer —
    a resize has to be caught before three reversals accumulate, and a
    timer that is slower than the gesture is a gate that sometimes works.
    """
    raw = hypr_request(req_sock, b"j/activewindow")
    if not raw:
        return None
    try:
        w = json.loads(raw)
        at, size = w.get("at"), w.get("size")
        if not at or not size:
            return None
        return (int(at[0]), int(at[1]), int(size[0]), int(size[1]))
    except Exception:
        return None


def cursorpos(req_sock: str):
    """(x, y) from Hyprland, or None. One connection per request, by design.

    Hyprland closes the request socket after answering — a second send on
    the same connection is EPIPE — so this is not a leak of connections, it
    is the protocol.
    """
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.25)
        s.connect(req_sock)
        s.sendall(b"cursorpos")
        buf = b""
        while True:
            c = s.recv(64)
            if not c:
                break
            buf += c
        s.close()
        x, _, y = buf.partition(b",")
        return int(x), int(y)
    except Exception as e:
        dlog(f"cursorpos failed: {e}")
        return None


SHOW = os.path.expanduser("~/.config/hypr/scripts/qdrop.sh")


def fire():
    """Show the shelf. Same guard the X11 watcher has.

    Through qdrop.sh, not straight at qdrop.py, so the shake and the
    $alt SHIFT D key agree about which workspace the shelf belongs on —
    that wrapper moves it to the active one while it is still parked
    off-screen. It also owns GDK_BACKEND=x11 for both callers.
    """
    if W._screenshot_active():
        log("screenshot tool active — shake ignored")
        return
    if DRY_RUN:
        log("shake -> show (DRY RUN, nothing shown)")
        return
    # --for-drag, not --show. You are HOLDING something: a shelf that takes
    # an exclusive keyboard grab on the way up cancels the drag it exists to
    # receive. Measured, A/B, on the same synthesised drop — with the grab
    # `entries 9 -> 9`, without it `9 -> 10`. The shelf takes the keyboard
    # the moment the drop lands.
    subprocess.Popen(
        [SHOW, "--for-drag"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    log("shake -> show")


class Drag:
    """One button-1 press, from `down` to `up`."""

    def __init__(self):
        self.down = False
        self.press_time = 0.0
        self.fired = False
        self.pos = None
        self.next_sample = 0.0
        self.travel = 0.0
        # (t, |dx|, |dy|) for the last TIME_WINDOW_S, which is what gate 3
        # measures its ratio over. Anything older cannot be part of the
        # shake that is being judged.
        self.recent: collections.deque = collections.deque()
        # GATE 5. The focused window's box when the button went down, and
        # whether it has moved since. See the note on `note_box`.
        self.box = None
        self.grabbed = False
        self.axes = {"x": W.Axis("x"), "y": W.Axis("y")}

    def start(self, now: float, pos, box=None):
        self.down = True
        self.press_time = now
        self.fired = False
        self.pos = pos
        self.next_sample = now + SAMPLE_S
        self.travel = 0.0
        self.recent.clear()
        # Taken AT THE PRESS and not on the first motion sample, so the
        # baseline is the geometry from before any grab could have moved it.
        # The bind fires on the press and the resize has not happened yet, so
        # this is the pre-grab rectangle by construction.
        self.box = box
        self.grabbed = False
        for ax in self.axes.values():
            ax.reset()
        dlog(f"press at {pos}")

    # ---- GATE 5: A FILE DRAG DOES NOT RESIZE ANYTHING --------------------
    #
    # Reported, and it is the one the four shape gates could not have
    # caught: "i resize the terrmianl with cursor and opens the dropshef".
    #
    # `general:resize_on_border` is 1 in this config with a 15 px
    # `extend_border_grab_area`, so dragging a window edge is a BARE
    # button-1 drag — no modifier — which means the modifier-exact trick
    # that keeps `$mod`-drags out (a window MOVE is `bindm = $mod,
    # mouse:272`) does nothing here. And the gesture is a dead ringer for a
    # shake: you grab an edge and push it back and forth to get the width
    # right, which is horizontal, flat, well past MIN_SEG_PX, and preceded
    # by plenty of carrying. It passed all four gates because it genuinely
    # has all four properties.
    #
    # So it is not separable by SHAPE and it does not need to be. A resize
    # is not a shape, it is an OUTCOME: the window changes size. A window
    # move is the same statement about position. Neither ever happens during
    # a file drag, and both are directly observable — `j/activewindow` over
    # the request socket, 839 bytes and 0.074 ms, which is why this can be
    # asked on every sample rather than on a timer that a fast resize could
    # outrun.
    #
    # STICKY for the whole press, deliberately. The alternative — refuse
    # only while the geometry is actively moving — reopens the hole the
    # moment you pause mid-resize, which is exactly when you would wiggle.
    #
    # The failure direction is the safe one. If a window retiles during a
    # real file drag (something opened, a workspace changed) this refuses a
    # shake that was legitimate, and the key and the shelf's other entry
    # points all still work. A false NEGATIVE costs a keystroke; a false
    # positive is a panel over your work, which is the report.
    def note_box(self, box) -> None:
        if box is None or self.grabbed:
            return
        if self.box is None:
            self.box = box
            return
        if box != self.box:
            self.grabbed = True
            dlog(f"compositor grab: window {self.box} -> {box}")

    def feed(self, now: float, dx: float, dy: float) -> None:
        """Accumulate the gate-3 and gate-4 evidence for one sample."""
        self.travel += abs(dx) + abs(dy)
        self.recent.append((now, abs(dx), abs(dy)))
        cutoff = now - TIME_WINDOW_S
        while self.recent and self.recent[0][0] < cutoff:
            self.recent.popleft()

    def carried(self, now: float) -> bool:
        """GATE 4 — has this press been a drag yet, at all?"""
        return (now - self.press_time >= MIN_PRESS_S
                and self.travel >= MIN_TRAVEL_PX)

    def flat(self) -> bool:
        """GATE 3 — is the recent motion side-to-side rather than scribbled?"""
        sx = sum(r[1] for r in self.recent)
        sy = sum(r[2] for r in self.recent)
        # A perfectly horizontal sweep has sy == 0, and a ratio against zero
        # is not a comparison — it is the best possible case, so say so.
        return sy <= 0.0 or sx >= MIN_AXIS_RATIO * sy

    # ---- THE WHOLE DECISION, IN ONE PLACE SO IT CAN BE DRIVEN -------------
    #
    # This used to be inline in run()'s loop, where the only way to exercise
    # it was to shake a real mouse inside a real Hyprland session — i.e. the
    # gates could only be tuned by the person reporting the bug. It is a
    # method now, and `scripts/test/shake-shapes.py` feeds it recorded
    # gesture shapes; the loop below calls exactly this and nothing else, so
    # a passing test is a statement about the shipped path.
    #
    # Returns "" for "not a shake", or a reason string when it IS one.
    # `box` is the focused window's rectangle for this tick, or None when it
    # could not be read — see note_box().
    def sample(self, now: float, dx: float, dy: float, box=None) -> str:
        self.note_box(box)
        self.feed(now, dx, dy)

        # GATE 5, checked before any shape work: this press is a compositor
        # resize or move, and no amount of the right shape makes it a drag.
        if self.grabbed and not LOOSE:
            return ""

        # GATE 2 — horizontal only, unless --loose. A scrollbar or a slider
        # is pure vertical reversal, and that was half the bug report.
        axes = (("x", dx), ("y", dy)) if LOOSE else (("x", dx),)

        for name, d in axes:
            ax = self.axes[name]
            if not ax.feed(float(d), now):
                continue
            if not ax.shaking():
                continue
            # Checked HERE and not earlier, so --debug says which gate
            # refused a gesture that otherwise had the right number of
            # turns in it. A gate that rejects silently cannot be tuned.
            if not LOOSE and not self.carried(now):
                dlog(f"{name}-shake refused: not carried yet "
                     f"({now - self.press_time:.2f}s, {self.travel:.0f}px)")
                continue
            if not LOOSE and not self.flat():
                sx = sum(r[1] for r in self.recent)
                sy = sum(r[2] for r in self.recent)
                dlog(f"{name}-shake refused: not flat "
                     f"(x {sx:.0f} vs y {sy:.0f}px)")
                continue
            return (f"{name}-shake ({len(ax.reversals)} reversals in "
                    f"{TIME_WINDOW_S}s)")
        return ""

    def stop(self, why: str):
        if self.down:
            dlog(f"release ({why}) after {time.time() - self.press_time:.2f}s")
        self.down = False
        self.pos = None


def run(sock2_path: str, req_sock: str) -> None:
    """One connection's worth of watching. Returns when the socket ends."""
    ev = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    ev.connect(sock2_path)
    log("watching (button state from Hyprland binds, motion from cursorpos)")

    drag = Drag()
    last_fire = 0.0
    buf = b""

    while True:
        timeout = max(0.0, drag.next_sample - time.time()) if drag.down else None
        r, _, _ = select.select([ev], [], [], timeout)
        now = time.time()

        if r:
            chunk = ev.recv(4096)
            if not chunk:
                return  # Hyprland closed it; caller reconnects
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                s = line.decode("utf-8", "replace")
                if s == "custom>>qdropshake:down":
                    drag.start(now, cursorpos(req_sock),
                               window_box(req_sock))
                elif s == "custom>>qdropshake:up":
                    drag.stop("bind")

        if not drag.down:
            continue

        # The one way a press outlives its release. See MAX_PRESS_S.
        if now - drag.press_time > MAX_PRESS_S:
            drag.stop("watchdog — no release inside %.0fs" % MAX_PRESS_S)
            log("press with no release for %.0fs — assuming it ended "
                "(a submap swallowed it?)" % MAX_PRESS_S)
            continue

        if now < drag.next_sample:
            continue
        drag.next_sample = now + SAMPLE_S

        pos = cursorpos(req_sock)
        if pos is None:
            continue
        if drag.pos is None:
            drag.pos = pos
            continue
        dx, dy = pos[0] - drag.pos[0], pos[1] - drag.pos[1]
        drag.pos = pos
        if drag.fired or (dx == 0 and dy == 0):
            continue

        why = drag.sample(now, dx, dy, window_box(req_sock))
        if not why:
            continue
        # The debounce stays out here, in the loop, because it is about this
        # PROCESS's firing history and not about the shape of one gesture —
        # which is the same reason the test can drive sample() without it.
        if now - last_fire < W.DEBOUNCE_S:
            continue
        dlog(why)
        fire()
        last_fire = now
        drag.fired = True


def main() -> None:
    _apply_tuning(sys.argv)
    _retune_shared()
    d = hypr_dir()
    sock2_path, req_sock = f"{d}/.socket2.sock", f"{d}/.socket.sock"

    # "A background listener that connects to a socket ONCE will die
    # silently" is a rule in this tree, and the three shell listeners
    # beside this one all carry the same reconnect loop. The socket FILE
    # going away is Hyprland going away; anything else is worth retrying.
    reconnects = 0
    while os.path.exists(sock2_path):
        try:
            run(sock2_path, req_sock)
        except OSError as e:
            log(f"event socket error: {e}")
        if not os.path.exists(sock2_path):
            break
        reconnects += 1
        log(f"event socket read ended, reconnecting (attempt {reconnects})")
        time.sleep(1 if reconnects <= 5 else 5)
    log("Hyprland's event socket is gone — exiting")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
