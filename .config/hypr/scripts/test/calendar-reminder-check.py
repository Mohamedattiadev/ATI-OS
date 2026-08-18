#!/usr/bin/env python3
"""Click a calendar day and type a reminder into it.  TEST TOOL, one-shot.

The calendar holds an EXCLUSIVE keyboard grab (calendarLayerVisible is on
`islandKeyboardFocus`'s exclusive list), so synthetic KEYS are safe without
the workspace guard. The CLICK is safe for a different reason: the panel is
the topmost Overlay-layer surface and this click lands inside its own
reported bounds (`tide state`'s width/height, centred on screen), so
Wayland routes it to the panel regardless of what workspace is active
underneath — there is nothing else it could hit.
"""

import json
import os
import subprocess
import sys
import time

HERE = os.path.expanduser("~/.config/hypr/scripts/test")
ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")


def ipc(target, fn, *args):
    return subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target, fn, *args],
                          capture_output=True, text=True, timeout=8).stdout.strip()


def state():
    return json.loads(ipc("tide", "state"))


def hyprctl(*args):
    return subprocess.run(["hyprctl"] + list(args),
                          capture_output=True, text=True, timeout=8).stdout


def keys(sequence):
    subprocess.run([sys.executable, f"{HERE}/uinput-key.py", "--gap", "0.04"] + sequence.split(),
                   capture_output=True, text=True, timeout=40)


def click_at(x, y):
    hyprctl("dispatch", "movecursor", f"{x} {y}")
    time.sleep(0.2)
    subprocess.run([sys.executable, f"{HERE}/uinput-click.py", "left"],
                   capture_output=True, text=True, timeout=15)


def shot(name):
    subprocess.run(["grim", "-o", "eDP-1", f"/tmp/cal-{name}.png"], timeout=10)
    print(f"saved /tmp/cal-{name}.png")


def main():
    ipc("tide", "toggleCalendar")
    time.sleep(0.8)
    st = state()
    print(f"open: {st}")
    if st.get("state") != "calendar":
        sys.exit("calendar did not open")

    w, h = st["width"], st["height"]
    cx = 1366 // 2
    left = cx - w // 2

    # Panel layout, measured off the same numbers PanelChrome/Metrics use:
    # header ~34px, weekday row ~13px, then a 7-col grid of ~25px cells
    # starting a little further down. Aim at day "20", roughly the third
    # row's third column on this month's layout, then correct visually.
    padx = int(w * 0.08)
    grid_left = left + padx
    cell = (w - 2 * padx) / 7
    # Row 3 (0-indexed row 2), column for Wed (index 2 with Sun-start).
    target_x = int(grid_left + 2 * cell + cell / 2)
    target_y = int(h * 0.62)

    click_at(target_x, target_y)
    time.sleep(0.3)
    shot("clicked")

    keys("t e s t space r e m i n d e r")
    time.sleep(0.3)
    shot("typed")

    keys("enter")
    time.sleep(0.5)
    shot("saved")

    keys("escape")  # leave the field
    time.sleep(0.3)
    keys("escape")  # close the panel
    time.sleep(0.3)
    print(f"final state: {state()}")


if __name__ == "__main__":
    main()
