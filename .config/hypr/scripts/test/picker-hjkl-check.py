#!/usr/bin/env python3
"""Drive hjkl navigation and /-gated search on theme/wallpaper pickers.
TEST TOOL, one-shot.

Both hold exclusive keyboard grabs, so synthetic keys are safe without the
workspace guard.
"""
import os
import subprocess
import sys
import time

HERE = os.path.expanduser("~/.config/hypr/scripts/test")
ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")


def ipc(target, fn, *args):
    return subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target, fn, *args],
                          capture_output=True, text=True, timeout=8).stdout.strip()


def keys(sequence):
    subprocess.run([sys.executable, f"{HERE}/uinput-key.py", "--gap", "0.05"] + sequence.split(),
                   capture_output=True, text=True, timeout=40)


def shot(name):
    subprocess.run(["grim", "-o", "eDP-1", f"/tmp/hjkl-{name}.png"], timeout=10)
    print(f"saved /tmp/hjkl-{name}.png")


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "theme"
    toggle = "toggleThemePicker" if which == "theme" else "toggleWallpaperPicker"

    ipc("tide", toggle)
    time.sleep(1.2)
    print("state:", ipc("tide", "state"))

    # hjkl should move the cursor/carousel right away, no click needed.
    keys("l l j" if which == "theme" else "l l")
    time.sleep(0.3)
    shot(f"{which}-nav")

    # "/" enters search
    keys("slash")
    time.sleep(0.2)
    keys("g r u v")
    time.sleep(0.3)
    shot(f"{which}-search")

    # Escape leaves search, back to nav — h/l should move again
    keys("escape")
    time.sleep(0.2)
    keys("h")
    time.sleep(0.2)
    shot(f"{which}-after-escape")
    print("state:", ipc("tide", "state"))

    ipc("tide", toggle)
    time.sleep(0.4)
    print("final state:", ipc("tide", "state"))


if __name__ == "__main__":
    main()
