#!/usr/bin/env python3
"""Synthesise a KEY COMBINATION through /dev/uinput.  TEST TOOL, not a feature.

    ./uinput-key.py super+slash
    ./uinput-key.py alt+grave --hold 3
    ./uinput-key.py super+shift+z

The companion to uinput-click.py, and it exists for the same reason: a bind
that cannot be pressed from a script is a bind whose bugs only the user can
find. Every keybinding in this desktop had been verified by reading
`hyprctl binds` — which proves a bind is REGISTERED and nothing else.

WHY NOT wtype
-------------
NEXT-SESSION.md's RULES record it: `wtype` reaches CLIENTS but not the
compositor's bind layer, because it drives the virtual-keyboard protocol
rather than a real device. A compositor keybinding is matched on the physical
key press, so `wtype` can type into a terminal and be completely unable to
press `$mod P`. /dev/uinput creates a real evdev device, which libinput picks
up and Hyprland binds like any other keyboard, so the press arrives where a
finger's would.

THREE THINGS THAT LOOK LIKE FAILURES AND ARE NOT
------------------------------------------------
The compositor needs ~3 s to bind a newly created uinput device. Same number
as uinput-click.py's, measured the same way — at 1 s `hyprctl devices` does
not list it and every press goes nowhere, which is indistinguishable from a
bind that does not exist. That is the whole ambiguity this tool removes, so
the settle is not tunable from the command line.

DESTROYING THE DEVICE RESETS AN ACTIVE SUBMAP. This is the same effect the
RULES record for wtype ("it creates and destroys a virtual keyboard, which
resets any active submap"), and it is not wtype's fault — Hyprland drops the
submap when the keyboard that entered it goes away. So a key that ENTERS a
submap looks like it did nothing if you check afterwards: the mode was
entered and then thrown away by this script exiting. Use --hold to keep the
device alive while you measure.

Keys are named as Hyprland names them (`hyprctl binds` prints `slash`,
`grave`, `TAB`), not as evdev does, so a bind can be copied out of binds.conf
and pressed without translating it.
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_DEV_SETUP   = 0x405c5503
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY = 0x00, 0x01
SYN_REPORT = 0

# evdev codes. Modifiers first, then everything a bind in this tree names.
KEYS = {
    "super": 125, "mod": 125, "meta": 125,
    "alt": 56, "shift": 42, "ctrl": 29, "control": 29,
    "escape": 1, "esc": 1, "tab": 15, "return": 28, "enter": 28,
    "space": 57, "grave": 41, "slash": 53, "backslash": 43,
    "minus": 12, "equal": 13, "comma": 51, "period": 52,
    "1": 2, "2": 3, "3": 4, "4": 5, "5": 6,
    "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
    "a": 30, "b": 48, "c": 46, "d": 32, "e": 18, "f": 33, "g": 34,
    "h": 35, "i": 23, "j": 36, "k": 37, "l": 38, "m": 50, "n": 49,
    "o": 24, "p": 25, "q": 16, "r": 19, "s": 31, "t": 20, "u": 22,
    "v": 47, "w": 17, "x": 45, "y": 21, "z": 44,
    "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64,
    "f7": 65, "f8": 66, "f9": 67, "f10": 68, "f11": 87, "f12": 88,
}

MODIFIERS = ("super", "mod", "meta", "alt", "shift", "ctrl", "control")


def emit(fd, typ, code, val):
    # input_event: struct timeval (2x long), __u16 type, __u16 code, __s32 value
    os.write(fd, struct.pack("@llHHi", 0, 0, typ, code, val))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    combo = [p.strip().lower() for p in sys.argv[1].split("+") if p.strip()]
    hold = 0.0
    if "--hold" in sys.argv:
        hold = float(sys.argv[sys.argv.index("--hold") + 1])

    unknown = [k for k in combo if k not in KEYS]
    if unknown:
        sys.exit("unknown key(s): %s" % ", ".join(unknown))

    mods = [KEYS[k] for k in combo if k in MODIFIERS]
    plain = [KEYS[k] for k in combo if k not in MODIFIERS]
    if len(plain) != 1:
        sys.exit("name exactly one non-modifier key, got %d" % len(plain))
    key = plain[0]

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    # Every code this table knows, not only the ones being pressed: a device
    # that advertises one key reads as a button, and libinput classifies it
    # accordingly. Advertising a full keyboard is what makes it bind as one.
    for code in set(KEYS.values()):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)

    # uinput_setup: input_id{bustype,vendor,product,version}, name[80], ff_effects_max
    setup = struct.pack("@HHHH80sI", 0x03, 0x1234, 0x5679, 1, b"claude-test-keyboard", 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)

    # See the header: below ~3 s the compositor has not bound the device and
    # the press is silently discarded.
    time.sleep(3.5)

    for m in mods:
        emit(fd, EV_KEY, m, 1)
    emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.05)
    emit(fd, EV_KEY, key, 1); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.08)
    emit(fd, EV_KEY, key, 0); emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.05)
    for m in reversed(mods):
        emit(fd, EV_KEY, m, 0)
    emit(fd, EV_SYN, SYN_REPORT, 0)

    print("pressed", "+".join(combo), flush=True)

    # Held OPEN, not slept on and then destroyed: destroying the device is
    # itself an event the compositor reacts to, and for a submap that reaction
    # is to leave it.
    time.sleep(max(0.4, hold))

    fcntl.ioctl(fd, UI_DEV_DESTROY)
    os.close(fd)


if __name__ == "__main__":
    main()
