#!/usr/bin/env python3
"""Drive the calculator's new item-6 features and screenshot each step.
TEST TOOL, one-shot, not meant to be reused.

Calculator holds an EXCLUSIVE keyboard grab whenever it is open (see
`islandKeyboardFocus` in DynamicIslandWindow.qml), which is the one case
RULES exempts from the workspace guard — the grab makes it physically
impossible for a synthetic key to reach anything else.

uinput-key.py's KEYS table has no backspace, so this closes and reopens the
panel between phases (`tide toggleCalculator`, which the layer's own
onShowConditionChanged clears the box on) rather than trying to clear text
with keys that do not exist.
"""

import os
import subprocess
import sys
import time

HERE = os.path.expanduser("~/.config/hypr/scripts/test")
ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")


def keys(sequence):
    subprocess.run([sys.executable, f"{HERE}/uinput-key.py", "--gap", "0.05"] + sequence.split(),
                   capture_output=True, text=True, timeout=40)


def ipc(target, fn, *args):
    subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target, fn, *args],
                   capture_output=True, text=True, timeout=8)


def shot(name):
    subprocess.run(["grim", "-o", "eDP-1", f"/tmp/calc-{name}.png"], timeout=10)
    print(f"saved /tmp/calc-{name}.png")


def reopen():
    ipc("tide", "toggleCalculator")
    time.sleep(0.4)
    ipc("tide", "toggleCalculator")
    time.sleep(0.8)


def main():
    reopen()
    # f r o b n i c a t e shift+9 3 shift+0  ->  "frobnicate(3)"
    keys("f r o b n i c a t e shift+9 3 shift+0")
    time.sleep(1.0)
    shot("trap")

    reopen()
    keys("1 2")
    time.sleep(0.6)
    shot("before-store")

    keys("escape")  # -> normal mode
    time.sleep(0.3)
    keys("m")  # store 12 into memory
    time.sleep(0.3)
    shot("stored")

    keys("shift+m")  # recall -> insert mode, box = "12"
    time.sleep(0.3)
    shot("after-recall")

    keys("escape")  # -> normal mode again (box has content -> normal mode works)
    time.sleep(0.3)
    keys("h h")  # cursor left twice
    time.sleep(0.2)
    shot("cursor-hh")


if __name__ == "__main__":
    main()
