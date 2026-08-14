#!/usr/bin/env python3
"""Synthesise a pointer click through /dev/uinput.  TEST TOOL, not a feature.

    hyprctl dispatch movecursor <x> <y>
    ./uinput-click.py [left|middle|right]
    ./uinput-click.py scroll up|down [count]


NEXT-SESSION.md records that clicking cannot be tested here: wtype is keys
only and ydotool is not installed, so every click-driven control in this
desktop has been verified by reading rather than by pressing. It also records
that /dev/uinput IS writable and that an evdev injection "is possible if it is
worth building". It is: this is the second control whose bug could only be
found by the user because nothing could press it.

TWO THINGS THAT LOOK LIKE FAILURES AND ARE NOT
----------------------------------------------
The compositor needs ~3 s to bind a newly created uinput device. Measured:
with a 1 s settle `hyprctl devices` did not list it at all and every click
went nowhere; at 3.5 s it appears as `claude-test-pointer` under `mice` and
clicks land. A click sent before the bind is indistinguishable from a click
that was ignored, which is exactly the ambiguity this tool exists to remove.

`hyprctl dispatch movecursor` warps the cursor WITHOUT emitting a motion
event, so focus does not follow it and a surface may not have pointer focus
when the button arrives. Hence the one-pixel wiggle before the press.

SCROLLING is the same device with REL_WHEEL declared. NEXT-SESSION.md's note
that the onboarding swipe "is a couple of EV_REL/REL_WHEEL events away" was
right, and the first thing it verified was the volume chip — a widget whose
scroll behaviour qtile ships as a WIDGET default rather than in config.py, so
nothing in this repo said it existed and nothing here could press it.

REL_WHEEL and not REL_WHEEL_HI_RES: one notch is one unit, which is what a
toolkit turns into a 120-unit angleDelta. Sending only the hi-res axis makes
Qt report angleDelta 0 and the handler correctly does nothing, which looks
exactly like a scroll that was ignored.

Deliberately a RELATIVE pointer with no absolute axes. Positioning is done by
`hyprctl dispatch movecursor`, which is exact and already available; all this
has to do is press and release wherever the cursor already is. An absolute
device would need its own coordinate space and would have to agree with
Hyprland's about scaling, which is a second thing to get wrong.
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_SET_RELBIT  = 0x40045566
UI_DEV_SETUP   = 0x405c5503
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY, EV_REL = 0x00, 0x01, 0x02
REL_X, REL_Y, REL_WHEEL = 0x00, 0x01, 0x08
BTN_LEFT, BTN_MIDDLE, BTN_RIGHT = 0x110, 0x112, 0x111
SYN_REPORT = 0

BUTTONS = {"left": BTN_LEFT, "middle": BTN_MIDDLE, "right": BTN_RIGHT}


def emit(fd, typ, code, val):
    # input_event: struct timeval (2x long), __u16 type, __u16 code, __s32 value
    os.write(fd, struct.pack("@llHHi", 0, 0, typ, code, val))


def main():
    argv = sys.argv[1:]
    scroll = 0
    count = 1
    if argv and argv[0] == "scroll":
        scroll = 1 if (len(argv) > 1 and argv[1] == "up") else -1
        count = int(argv[2]) if len(argv) > 2 else 1
        button = BUTTONS["left"]
    else:
        button = BUTTONS[argv[0] if argv else "left"]

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    for b in BUTTONS.values():
        fcntl.ioctl(fd, UI_SET_KEYBIT, b)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_X)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_Y)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_WHEEL)

    # uinput_setup: input_id{bustype,vendor,product,version}, name[80], ff_effects_max
    setup = struct.pack("@HHHH80sI", 0x03, 0x1234, 0x5678, 1, b"claude-test-pointer", 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)

    # The compositor needs a moment to notice a new input device; a click sent
    # before it is bound goes nowhere and looks exactly like a click that was
    # ignored, which is the failure this whole script exists to rule out.
    time.sleep(3.5)

    # A one-pixel wiggle first: it makes the compositor deliver a motion event
    # to whatever is under the cursor, so the surface has pointer focus before
    # the button arrives.
    emit(fd, EV_REL, REL_X, 1); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.15)
    emit(fd, EV_REL, REL_X, -1); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.15)

    if scroll:
        for _ in range(count):
            emit(fd, EV_REL, REL_WHEEL, scroll); emit(fd, EV_SYN, SYN_REPORT, 0)
            time.sleep(0.12)
    else:
        emit(fd, EV_KEY, button, 1); emit(fd, EV_SYN, SYN_REPORT, 0)
        time.sleep(0.08)
        emit(fd, EV_KEY, button, 0); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.4)

    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)
    if scroll:
        print("scrolled", "up" if scroll > 0 else "down", "x%d" % count)
    else:
        print("clicked", argv[0] if argv else "left")


if __name__ == "__main__":
    main()
