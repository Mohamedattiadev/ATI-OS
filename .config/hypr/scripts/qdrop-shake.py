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
"""
import importlib.util
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

SHARED = os.path.expanduser("~/.config/qtile/scripts/qdrop_watch.py")


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


def hypr_dir() -> str:
    rt = os.environ.get("XDG_RUNTIME_DIR")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not rt or not sig:
        log("XDG_RUNTIME_DIR or HYPRLAND_INSTANCE_SIGNATURE unset — not in a "
            "Hyprland session, nothing to watch")
        sys.exit(1)
    return f"{rt}/hypr/{sig}"


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
    subprocess.Popen(
        [SHOW, "--show"],
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
        self.axes = {"x": W.Axis("x"), "y": W.Axis("y")}

    def start(self, now: float, pos):
        self.down = True
        self.press_time = now
        self.fired = False
        self.pos = pos
        self.next_sample = now + SAMPLE_S
        for ax in self.axes.values():
            ax.reset()
        dlog(f"press at {pos}")

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
                    drag.start(now, cursorpos(req_sock))
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

        for name, d in (("x", dx), ("y", dy)):
            ax = drag.axes[name]
            if not ax.feed(float(d), now):
                continue
            if not ax.shaking():
                continue
            if now - last_fire < W.DEBOUNCE_S:
                continue
            dlog(f"{name}-shake ({len(ax.reversals)} reversals in "
                 f"{W.TIME_WINDOW_S}s)")
            fire()
            last_fire = now
            drag.fired = True
            break


def main() -> None:
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
