#!/usr/bin/env python3
"""qdrop shake detector.

Watches xinput --test-xi2 --root for Button1-held rapid horizontal
direction reversals ("shake" while dragging). Fires qtile scratchpad toggle
for qdrop when N reversals happen within TIME_WINDOW_S.
"""
import collections
import re
import subprocess
import time

REVERSALS_NEEDED = 4         # sign flips on X
TIME_WINDOW_S = 0.7          # within this many seconds
MIN_SEG_PX = 12              # ignore jitter shorter than this
DEBOUNCE_S = 1.5
COOLDOWN_AFTER_RELEASE = 0.2

TOGGLE_CMD = [
    "qtile", "cmd-obj",
    "-o", "group", "scratchpad",
    "-f", "dropdown_toggle",
    "-a", "qdrop",
]


def log(msg: str):
    print(f"[qdrop_watch] {msg}", flush=True)


def already_visible() -> bool:
    try:
        r = subprocess.run(
            ["xdotool", "search", "--onlyvisible", "--class", "qdrop"],
            capture_output=True, text=True, timeout=1,
        )
        return bool(r.stdout.strip())
    except Exception:
        return False


def fire():
    if already_visible():
        log("shake ignored (already visible)")
        return
    subprocess.Popen(TOGGLE_CMD, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("shake -> toggled")


def main():
    proc = subprocess.Popen(
        ["xinput", "--test-xi2", "--root"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )

    button1_down = False
    last_x = 0.0
    current_sign = 0            # +1 right, -1 left, 0 unknown
    seg_start_x = 0.0
    reversal_times: collections.deque = collections.deque()
    last_fire = 0.0
    fired_for_drag = False

    ev_type = None
    detail = None
    coord_re = re.compile(r"^\s+root:\s+([\-\d.]+)\s*/\s*([\-\d.]+)")

    for line in proc.stdout:
        line = line.rstrip("\n")

        m_ev = re.match(r"^EVENT type\s+(\d+)\s+\((\w+)\)", line)
        if m_ev:
            ev_type = m_ev.group(2)
            detail = None
            continue

        m_det = re.match(r"^\s+detail:\s+(\d+)", line)
        if m_det:
            detail = int(m_det.group(1))
            continue

        m_root = coord_re.match(line)
        if not m_root:
            continue

        x = float(m_root.group(1))

        if ev_type == "ButtonPress" and detail == 1:
            button1_down = True
            last_x = x
            seg_start_x = x
            current_sign = 0
            reversal_times.clear()
            fired_for_drag = False
        elif ev_type == "ButtonRelease" and detail == 1:
            button1_down = False
            reversal_times.clear()
            time.sleep(COOLDOWN_AFTER_RELEASE)
        elif ev_type == "Motion" and button1_down and not fired_for_drag:
            dx = x - last_x
            last_x = x
            if abs(x - seg_start_x) < MIN_SEG_PX:
                continue
            new_sign = 1 if dx > 0 else -1 if dx < 0 else current_sign
            if current_sign == 0:
                current_sign = new_sign
                seg_start_x = x
            elif new_sign != 0 and new_sign != current_sign:
                # direction flip
                now = time.time()
                reversal_times.append(now)
                cutoff = now - TIME_WINDOW_S
                while reversal_times and reversal_times[0] < cutoff:
                    reversal_times.popleft()
                current_sign = new_sign
                seg_start_x = x
                if len(reversal_times) >= REVERSALS_NEEDED and now - last_fire >= DEBOUNCE_S:
                    fire()
                    last_fire = now
                    fired_for_drag = True


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
