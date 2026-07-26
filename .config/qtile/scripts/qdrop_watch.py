#!/usr/bin/env python3
"""qdrop shake detector.

Watches xinput --test-xi2 --root for Button1-held rapid horizontal direction
reversals. Uses RAW events (not blocked by X grabs during XDND drag).
Tracks button state from RawButtonPress/Release, position deltas from
RawMotion valuators.

Fires `qdrop --show` on shake. Motion outside a button1 drag is ignored,
so closing the window and moving the mouse never re-triggers.
"""
import collections
import os
import re
import subprocess
import sys
import time

REVERSALS_NEEDED = 3
TIME_WINDOW_S = 1.0
MIN_SEG_PX = 8
DEBOUNCE_S = 1.2
COOLDOWN_AFTER_RELEASE_S = 0.2

QDROP = os.path.expanduser("~/.config/qtile/scripts/qdrop.py")


def log(msg: str):
    print(f"[qdrop_watch] {msg}", flush=True)


def fire():
    subprocess.Popen(
        [sys.executable, QDROP, "--show"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    log("shake -> show")


def main():
    proc = subprocess.Popen(
        ["xinput", "--test-xi2", "--root"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )

    ev_re = re.compile(r"^EVENT type\s+\d+\s+\((\w+)\)")
    detail_re = re.compile(r"^\s+detail:\s+(\d+)")
    axis_re = re.compile(r"^\s+0:\s+([\-\d.]+)")

    ev_type = None
    detail = None

    button1_down = False
    integrated_x = 0.0
    seg_start_x = 0.0
    current_sign = 0
    reversal_times: collections.deque = collections.deque()
    last_fire = 0.0
    fired_for_drag = False

    for line in proc.stdout:
        if not line:
            continue
        c0 = line[0]
        if c0 == "E":
            m = ev_re.match(line)
            if m:
                ev_type = m.group(1)
                detail = None
            continue
        if c0 != " " and c0 != "\t":
            continue

        if ev_type in ("RawButtonPress", "RawButtonRelease"):
            m = detail_re.match(line)
            if m:
                detail = int(m.group(1))
                if detail == 1:
                    if ev_type == "RawButtonPress":
                        button1_down = True
                        integrated_x = 0.0
                        seg_start_x = 0.0
                        current_sign = 0
                        reversal_times.clear()
                        fired_for_drag = False
                    else:
                        button1_down = False
                        time.sleep(COOLDOWN_AFTER_RELEASE_S)
            continue

        if ev_type != "RawMotion" or not button1_down or fired_for_drag:
            continue

        m = axis_re.match(line)
        if not m:
            continue

        dx = float(m.group(1))
        if dx == 0:
            continue
        integrated_x += dx
        if abs(integrated_x - seg_start_x) < MIN_SEG_PX:
            continue

        new_sign = 1 if dx > 0 else -1
        if current_sign == 0:
            current_sign = new_sign
            seg_start_x = integrated_x
            continue

        if new_sign != current_sign:
            now = time.time()
            reversal_times.append(now)
            cutoff = now - TIME_WINDOW_S
            while reversal_times and reversal_times[0] < cutoff:
                reversal_times.popleft()
            current_sign = new_sign
            seg_start_x = integrated_x
            if len(reversal_times) >= REVERSALS_NEEDED and now - last_fire >= DEBOUNCE_S:
                fire()
                last_fire = now
                fired_for_drag = True


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
