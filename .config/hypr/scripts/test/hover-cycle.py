"""Drive hover ON/OFF over the island, repeatedly, with REAL motion events.

`hyprctl dispatch movecursor` warps without a motion event, so a warp alone
never produces the enter/leave a hover state machine reacts to. This warps and
then emits a 1 px there-and-back, and holds ONE uinput device open for the
whole run so nothing is unbound mid-sequence.

No buttons are ever pressed.

    hovercycle.py <onx> <ony> <offx> <offy> <cycles> <dwell_s>
"""
import fcntl
import os
import struct
import subprocess
import sys
import time

UI_SET_EVBIT, UI_SET_RELBIT = 0x40045564, 0x40045566
UI_DEV_SETUP, UI_DEV_CREATE, UI_DEV_DESTROY = 0x405C5503, 0x5501, 0x5502
EV_SYN, EV_REL, REL_X = 0x00, 0x02, 0x00

onx, ony, offx, offy = (int(a) for a in sys.argv[1:5])
cycles, dwell = int(sys.argv[5]), float(sys.argv[6])

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
for e in (EV_REL, EV_SYN):
    fcntl.ioctl(fd, UI_SET_EVBIT, e)
fcntl.ioctl(fd, UI_SET_RELBIT, REL_X)
fcntl.ioctl(fd, UI_DEV_SETUP,
            struct.pack("@HHHH80sI", 0x03, 0x1234, 0x567A, 1, b"claude-hover", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(3.5)


def emit(t, c, v):
    os.write(fd, struct.pack("@llHHi", 0, 0, t, c, v))


def go(x, y, label):
    subprocess.run(["hyprctl", "dispatch", "movecursor", str(x), str(y)],
                   capture_output=True)
    time.sleep(0.05)
    emit(EV_REL, REL_X, 1)
    emit(EV_SYN, 0, 0)
    time.sleep(0.05)
    emit(EV_REL, REL_X, -1)
    emit(EV_SYN, 0, 0)
    print(f"{time.time() - t0:6.2f}s  {label}", flush=True)


t0 = time.time()
for i in range(cycles):
    go(onx, ony, f"ON  #{i + 1}")
    time.sleep(dwell)
    go(offx, offy, f"OFF #{i + 1}")
    time.sleep(dwell)

fcntl.ioctl(fd, UI_DEV_DESTROY)
os.close(fd)
print(f"{time.time() - t0:6.2f}s  done", flush=True)
