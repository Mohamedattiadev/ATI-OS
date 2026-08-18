#!/usr/bin/env python3
"""Record a panel's open at 60fps and check whether content paints before
the capsule's own shape has finished growing.  TEST TOOL, item 2.

    ./panel-glitch-frames.py theme_picker toggleThemePicker
    ./panel-glitch-frames.py wallpaper_picker toggleWallpaperPicker
    ./panel-glitch-frames.py wifi_panel toggleWifiPanel wifi
    ./panel-glitch-frames.py cheatsheet showCheatsheet vim

METHOD
------
`bar-edge.py`'s technique, adapted: record the capsule's growth region
continuously at 60 fps (no single-shot grim, no timed guess — see
NEXT-SESSION.md's rules on why), extract every frame as PPM, and difference
consecutive frames in two separate bands:

    SHAPE band   the outer few px ring of the capsule's bounding box —
                 where the growing/morphing OUTLINE itself paints
    CONTENT band the interior, inset from the shape band — where the
                 panel's own content (text, chips, grid) paints

If the shape band's motion settles (drops to near the quiet baseline) at
frame N, and the content band is STILL changing well past frame N by more
than a couple of frames, that is content painting inside an already-final
shape, which is fine (a normal fade/intro). If content changes STOP at or
before the shape settles, or a large content jump happens exactly at the
frame the shape is still moving, that is the race item 2 describes.

This is a coarse instrument, not a diagnosis — it locates which panels are
worth a closer look, per PROMPT-NEXT.md item 2's own admission that a
mechanical class check is not the same as a timing check.
"""

import json
import subprocess
import sys
import time
import os

ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")
REGION = "0,0 1366x420"


def ipc(target, fn, *args):
    return subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target, fn] + list(args),
                          capture_output=True, text=True, timeout=8).stdout.strip()


def state():
    try:
        return json.loads(ipc("tide", "state"))
    except ValueError:
        return {}


def record(path, seconds, action):
    proc = subprocess.Popen(
        ["wf-recorder", "-o", "eDP-1", "-g", REGION, "-r", "60", "-f", path],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    action()
    time.sleep(seconds)
    proc.send_signal(subprocess.signal.SIGINT)
    proc.wait(timeout=10)


def extract(video, outdir):
    os.makedirs(outdir, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-i", video, "-fps_mode", "passthrough",
                    os.path.join(outdir, "f%04d.ppm")],
                   capture_output=True, timeout=60)
    frames = sorted(f for f in os.listdir(outdir) if f.endswith(".ppm"))
    return [os.path.join(outdir, f) for f in frames]


def load_ppm(path):
    with open(path, "rb") as f:
        magic = f.readline()
        dims = f.readline()
        while dims.startswith(b"#"):
            dims = f.readline()
        w, h = map(int, dims.split())
        maxval = f.readline()
        data = f.read(w * h * 3)
    return w, h, data


def band_motion(frames, x0, y0, x1, y1):
    """Fraction of pixels in the box that changed vs the previous frame."""
    out = []
    prev = None
    for path in frames:
        w, h, data = load_ppm(path)
        box = []
        for y in range(max(0, y0), min(h, y1)):
            row_start = y * w * 3
            box.append(data[row_start + x0 * 3: row_start + x1 * 3])
        cur = b"".join(box)
        if prev is not None and len(prev) == len(cur):
            changed = sum(1 for i in range(0, len(cur), 3)
                          if abs(cur[i] - prev[i]) > 12
                          or abs(cur[i + 1] - prev[i + 1]) > 12
                          or abs(cur[i + 2] - prev[i + 2]) > 12)
            out.append(changed / (len(cur) / 3))
        else:
            out.append(0.0)
        prev = cur
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(f"usage: {sys.argv[0]} <state-name> <ipc-fn> [ipc-arg]")
    state_name, fn = sys.argv[1], sys.argv[2]
    fn_args = sys.argv[3:]

    before = state()
    if before.get("state") not in ("normal", "lyrics", "custom"):
        sys.exit(f"panel not resting before the run ({before}) — "
                 f"close it by hand first, this tool does not guess a close IPC name")
    print(f"state before: {before}")

    work = f"/tmp/panel-glitch-{state_name}"
    os.makedirs(work, exist_ok=True)
    video = f"{work}/open.mp4"

    record(video, 2.0, lambda: ipc("tide", fn, *fn_args))
    after = state()
    print(f"state after open: {after}")

    frames = extract(video, f"{work}/frames")
    print(f"{len(frames)} frames extracted")
    if len(frames) < 10:
        sys.exit("too few frames — capture likely failed")

    w, h = after.get("width", 300), after.get("height", 100)
    cx = 1366 // 2
    x0, x1 = max(0, cx - w // 2 - 4), min(1366, cx + w // 2 + 4)
    y0, y1 = 0, min(420, h + 8)

    shape_ring = 4
    shape_motion = band_motion(frames, x0, y0, x1, y0 + shape_ring)
    inner_x0, inner_x1 = x0 + 20, x1 - 20
    inner_y0, inner_y1 = y0 + shape_ring + 6, y1 - 6
    content_motion = band_motion(frames, max(x0, inner_x0), inner_y0,
                                  min(x1, inner_x1), max(inner_y0 + 1, inner_y1))

    print("\nframe  shape%  content%")
    for i, (s, c) in enumerate(zip(shape_motion, content_motion)):
        print(f"{i:4d}   {s*100:5.1f}   {c*100:5.1f}")

    def settle_frame(series, floor=0.02, quiet_run=8):
        """End of the FIRST contiguous active streak, not the last active
        frame anywhere in the clip — a late isolated blip (a clock tick, an
        EQ bar) is not the open settling and must not be read as one."""
        active_until = 0
        quiet = 0
        started = False
        for i, v in enumerate(series):
            if v > floor:
                started = True
                active_until = i
                quiet = 0
            elif started:
                quiet += 1
                if quiet >= quiet_run:
                    break
        return active_until

    shape_settle = settle_frame(shape_motion)
    content_settle = settle_frame(content_motion)
    print(f"\nshape settles at frame {shape_settle}, content at frame {content_settle}")
    if content_settle > shape_settle + 2:
        print("CONTENT MOVES AFTER SHAPE SETTLES — likely a normal intro fade, not a race")
    elif content_settle <= shape_settle:
        print("CONTENT SETTLES AT/BEFORE SHAPE — no visible race in this band")
    else:
        print("CLOSE — inspect frames around", shape_settle, "-", content_settle, "by eye")

    # close it, leave the session tidy — the same call toggles it shut,
    # verified by hand: toggleThemePicker open, then toggleThemePicker
    # again reads back "normal".
    ipc("tide", fn, *fn_args)
    time.sleep(0.3)
    print(f"state after close: {state()}")


if __name__ == "__main__":
    main()
