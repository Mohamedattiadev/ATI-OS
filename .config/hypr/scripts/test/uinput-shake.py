#!/usr/bin/env python3
"""Synthesise a button-1 drag with a SHAKE in it.  TEST TOOL, not a feature.

    ./uinput-shake.py [swings] [amplitude_px] [axis] [--mod super|shift|ctrl]
    ./uinput-shake.py drag [distance_px]      one-way drag, no shake
    ./uinput-shake.py wiggle                  shake with NO button held
    ./uinput-shake.py to <x1> <y1> <x2> <y2>  press at 1, travel to 2, release

The third thing uinput-click.py could not do. It presses BTN_LEFT, moves the
pointer back and forth across `amplitude` pixels `swings` times, and lets go
— which is the whole of qdrop's shake gesture and therefore the only way to
test scripts/qdrop-shake.py without a human and a mouse. `hyprctl clients -j`
answers whether it worked: the qdrop window sits at a negative y when hidden
and a positive one when shown.

The three modes that are NOT a shake exist because they are the cases the
detector has to REFUSE, and a gate that has only ever been driven with the
input it should accept has not been tested:

    drag    one-way travel with the button down, plus the 1-2 px of
            integer-rounding jitter that comes free with polled screen
            coordinates -- must not fire, and is what MIN_SEG_PX measuring
            from the extremum is for
    wiggle  the same shake with nothing held -- must not fire, because the
            press bind is the only thing that opens the window
    --mod super
            the same shake under $mod, i.e. a window being flung around --
            must not fire, because the press binds are modifier-exact and
            none of them names SUPER

Inherits uinput-click.py's three traps verbatim: the compositor needs ~3 s
to bind a new uinput device, `movecursor` warps without a motion event so a
wiggle is needed first, and destroying the device can reset an active
submap. Everything else in that file's header applies here too.

The device is RELATIVE, so what reaches the compositor has been through
libinput's pointer acceleration and the amplitude on screen is not the
amplitude asked for here. That is the point -- it is the same path a hand
takes.

`to` IS THE DRAG-AND-DROP MODE, and it is closed-loop for that same reason.
An open-loop "emit dx, dy" cannot land on a target: acceleration means the
pixels asked for and the pixels travelled are different numbers, and the
error compounds over a long move. So it reads `cursorpos` back from Hyprland
after every step and steers -- in small steps, because small steps are the
flat part of the acceleration curve. It also HOVERS before releasing: a drop
target has to be told the pointer is over it before the button goes up, and
a release in the same frame as the arrival is a drop nobody accepted.

Pair it with `dnd-peer.py`, which is a window offering exactly one URI and
printing whatever is dropped on it -- the controlled other end, so that "can
you drag a file into qdrop" can be answered without synthesising a file move
across somebody's home directory.
"""
import fcntl
import os
import socket
import struct
import subprocess
import sys
import time

UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_SET_RELBIT  = 0x40045566
UI_DEV_SETUP   = 0x405c5503
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY, EV_REL = 0x00, 0x01, 0x02
REL_X, REL_Y = 0x00, 0x01
BTN_LEFT = 0x110
SYN_REPORT = 0

MODS = {"super": 125, "shift": 42, "ctrl": 29, "alt": 56}  # KEY_LEFT*

STEP_MS = 12          # one motion report every 12 ms, ~83 Hz
STEP_PX = 20          # px per report; a swing is amplitude/STEP_PX reports


def emit(fd, typ, code, val):
    os.write(fd, struct.pack("@llHHi", 0, 0, typ, code, val))


def syn(fd):
    emit(fd, EV_SYN, SYN_REPORT, 0)


def cursorpos():
    """Read the cursor back from Hyprland. One request per connection."""
    p = (f"{os.environ['XDG_RUNTIME_DIR']}/hypr/"
         f"{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket.sock")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.25)
    s.connect(p)
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


def steer(fd, tx, ty, step=8, tol=3, limit=600):
    """Walk the pointer to (tx, ty), correcting against cursorpos each step."""
    for _ in range(limit):
        x, y = cursorpos()
        dx, dy = tx - x, ty - y
        if abs(dx) <= tol and abs(dy) <= tol:
            return True
        sx = max(-step, min(step, dx))
        sy = max(-step, min(step, dy))
        if sx:
            emit(fd, EV_REL, REL_X, sx)
        if sy:
            emit(fd, EV_REL, REL_Y, sy)
        syn(fd)
        time.sleep(0.006)
    return False


def travel(fd, axis, total, sign):
    """Move `total` px along `axis` in STEP_PX reports."""
    moved = 0
    while moved < total:
        step = min(STEP_PX, total - moved)
        emit(fd, EV_REL, axis, sign * step)
        syn(fd)
        moved += step
        time.sleep(STEP_MS / 1000.0)


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    mod = None
    if "--mod" in sys.argv:
        mod = MODS[sys.argv[sys.argv.index("--mod") + 1]]

    mode = "shake"
    if argv and argv[0] in ("drag", "wiggle", "to"):
        mode = argv.pop(0)

    if mode == "to":
        x1, y1, x2, y2 = (int(a) for a in argv[:4])
        subprocess.run(["hyprctl", "dispatch", "movecursor", str(x1), str(y1)],
                       capture_output=True)
        time.sleep(0.25)

    swings = int(argv[0]) if len(argv) > 0 and mode != "to" else 4
    amp = int(argv[1]) if len(argv) > 1 and mode != "to" else 140
    axis = REL_Y if (mode != "to" and len(argv) > 2
                     and argv[2] in ("y", "vertical")) else REL_X

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    for e in (EV_KEY, EV_REL, EV_SYN):
        fcntl.ioctl(fd, UI_SET_EVBIT, e)
    for k in (BTN_LEFT, *MODS.values()):
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    for r in (REL_X, REL_Y):
        fcntl.ioctl(fd, UI_SET_RELBIT, r)
    fcntl.ioctl(fd, UI_DEV_SETUP, struct.pack(
        "@HHHH80sI", 0x03, 0x1234, 0x5678, 1, b"claude-test-pointer", 0))
    fcntl.ioctl(fd, UI_DEV_CREATE)

    # See uinput-click.py: a click sent before the compositor has bound the
    # device is indistinguishable from a click that was ignored.
    time.sleep(3.5)

    # The wiggle that gives whatever is under the cursor pointer focus.
    emit(fd, EV_REL, REL_X, 1); syn(fd); time.sleep(0.15)
    emit(fd, EV_REL, REL_X, -1); syn(fd); time.sleep(0.15)

    try:
        if mod is not None:
            emit(fd, EV_KEY, mod, 1); syn(fd); time.sleep(0.2)
        if mode != "wiggle":
            emit(fd, EV_KEY, BTN_LEFT, 1); syn(fd)
            time.sleep(0.12)

        if mode == "to":
            # Past the toolkit's drag threshold first, in one clear move, so
            # the source knows a drag has begun and not a click.
            for _ in range(4):
                emit(fd, EV_REL, REL_X, 6); syn(fd)
                time.sleep(0.02)
            ok = steer(fd, x2, y2)
            got = cursorpos()
            print(f"  steered to {got}, wanted ({x2}, {y2}), "
                  f"{'on target' if ok else 'GAVE UP'}")
            # The target has to see the pointer over it before the release.
            time.sleep(0.6)
        elif mode == "drag":
            # One way, with a 1 px retrace every other report -- the tremor
            # that must be absorbed rather than counted.
            for i in range(swings * 8):
                emit(fd, EV_REL, axis, STEP_PX)
                if i % 2:
                    emit(fd, EV_REL, axis, -1)
                syn(fd)
                time.sleep(STEP_MS / 1000.0)
        else:
            sign = 1
            for _ in range(swings):
                travel(fd, axis, amp, sign)
                sign = -sign
                time.sleep(0.02)
    finally:
        if mode != "wiggle":
            emit(fd, EV_KEY, BTN_LEFT, 0); syn(fd)
        if mod is not None:
            emit(fd, EV_KEY, mod, 0); syn(fd)
        time.sleep(0.4)
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)

    if mode == "to":
        print(f"to: ({x1}, {y1}) -> ({x2}, {y2}), button 1 held throughout")
    else:
        print(f"{mode}: {swings} swings of {amp}px on "
              f"{'y' if axis == REL_Y else 'x'}"
              + (f", mod={sys.argv[sys.argv.index('--mod') + 1]}" if mod else ""))


if __name__ == "__main__":
    main()
