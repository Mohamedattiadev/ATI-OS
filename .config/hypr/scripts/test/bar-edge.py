#!/usr/bin/env python3
"""Watch the topbar's PAINTED edges at 60 fps while popups open and close.  TEST TOOL.

    ./bar-edge.py                     drive every popup, record, report
    ./bar-edge.py --only volume       one popup
    ./bar-edge.py --keep /tmp/run     keep the video and the frames

WHY THIS EXISTS, AND WHY IT IS NOT THE INSTRUMENT THAT WAS USED BEFORE
----------------------------------------------------------------------
Reported: "the topbar still glitching when i open then close popup, its
height reduce with 2px lets say and come back to its place again."

It was driven once and not reproduced, with two probes:

    * the bar surface polled every 8 ms          -> h=38 y=0 unchanged
    * a 157-frame `grim` burst, about 39 fps     -> painted edge identical

Both are the WRONG INSTRUMENT, and the island's hover blink is the proof:
that defect turned out to be ONE FRAME, invisible to every probe until a
60 fps `wf-recorder` capture caught it. A 39 fps burst of independent
screenshots cannot see a one-frame event at all -- it samples 39 of the 60
frames the compositor drew, with gaps, and the gap is exactly where a single
bad frame hides. Polling a PROPERTY has a worse version of the same problem:
it reads what QML thinks the surface is, not what was scanned out.

So this records the strip CONTINUOUSLY at 60 and looks at every frame.

WHAT IT MEASURES, AND WHY IT IS TWO THINGS
------------------------------------------
The strongest surviving lead is that the bar's height is NOT what moves.
`topbar/shell.qml` puts the exclusive zone on a SEPARATE 1 px window -- both
real bars are `ExclusionMode.Ignore` -- so anything that perturbs the
reserved area shifts the gap UNDER the bar without the bar resizing at all.
A popup is another layer surface, and layer-shell recomputes the usable area
whenever one maps.

That would look identical to "the bar got 2 px shorter" and would leave the
bar's own geometry untouched, which is precisely what the earlier probes
found. So the video is sampled for the bar's painted edge AND the compositor
is sampled for `reserved` at the same time, on one clock:

    edge moves, reserved still      the bar really is repainting shorter
    edge moves, reserved moves      the exclusive-zone window is the cause
    neither moves                   not reproducible on this bar/position

READING THE EDGE, AND WHY IT IS NOT READ AS A COLOUR
----------------------------------------------------
The first version of this scanned each column for the row where the bar's
fill stops. It cannot work, and the frames say why: the bar's fill is
[28,30,30] and the WALLPAPER directly under it at x=40 is [26,29,30]. There
is no edge there to find. It exists at x=683, where the wallpaper is bright
-- and that is precisely the region every popup covers.

So the edge is read as MOTION instead, against a baseline built from the
quiet second before anything is driven. The wallpaper does not move, so any
row where the bar's boundary shifts changes across nearly the whole WIDTH,
while a clock tick or an EQ bar changes a handful of columns. Reporting the
fraction of columns that changed, per row, per frame, separates those two
without knowing anything about the palette or the wallpaper.

A frame is reported individually, with its index and its timestamp, because
the whole point is that the answer may be a single frame and an average
would erase it.
"""

import argparse
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

import numpy as np
from PIL import Image

HYPR_SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
SOCKET = f"{RUNTIME}/hypr/{HYPR_SIG}/.socket.sock"

POPUPS_QML = os.path.expanduser(
    "~/.config/quickshell/tide-island-fork/popups.qml")
TOPBAR_DIR = os.path.expanduser("~/.config/quickshell/topbar")

# Every popup the topbar can raise, not just the one that was tried. They have
# different heights and different loaders, and "drive EVERY popup" is the
# second half of why the first attempt found nothing.
POPUPS = [
    ("volume", ["popups", "volume"], POPUPS_QML),
    ("wallpaper", ["popups", "wallpaper"], POPUPS_QML),
    ("network", ["popups", "network"], POPUPS_QML),
    ("bluetooth", ["popups", "bluetooth"], POPUPS_QML),
    ("display", ["popups", "display"], POPUPS_QML),
    ("wifiqr", ["popups", "wifiqr"], POPUPS_QML),
    ("cheatsheet", ["popups", "cheatsheet", "hypr"], POPUPS_QML),
    # The topbar's own chips. They are not layer surfaces of their own -- they
    # expand inside the bar -- so if the twitch is layer-shell recomputing the
    # usable area, these are the CONTROL: same gesture, no new surface.
    ("systemBox", ["topbar", "toggleSystemBox"], TOPBAR_DIR),
    ("secondBox", ["topbar", "toggleSecondBox"], TOPBAR_DIR),
    ("trayBox", ["topbar", "toggleTrayBox"], TOPBAR_DIR),
]


def hypr(request):
    """One request over hyprctl's socket.

    ONE REQUEST PER CONNECTION -- a second sendall on the same connection is
    EPIPE. Reconnecting costs 0.036 ms against 6.02 ms for spawning the
    binary, which is what makes an 8 ms sampler possible at all.
    """
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(SOCKET)
        sock.sendall(request.encode())
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


def qs_call(entry, args):
    subprocess.run(["qs", "-p", entry, "ipc", "call"] + args,
                   capture_output=True, text=True, timeout=6)


class Sampler(threading.Thread):
    """`reserved` and the bar's own layer geometry, on the recording's clock."""

    def __init__(self, period=0.008):
        super().__init__(daemon=True)
        self.period = period
        self.rows = []
        self.stop_flag = threading.Event()

    def run(self):
        while not self.stop_flag.is_set():
            now = time.monotonic()
            try:
                mon = json.loads(hypr("j/monitors"))[0]
                lay = json.loads(hypr("j/layers"))
            except Exception:
                continue
            bars = []
            for _name, value in lay.items():
                for _level, surfaces in value.get("levels", {}).items():
                    for surface in surfaces:
                        if surface.get("namespace") == "quickshell":
                            bars.append((surface["y"], surface["h"]))
            self.rows.append((now, tuple(mon["reserved"]), tuple(sorted(bars))))
            time.sleep(max(0, self.period - (time.monotonic() - now)))


def require_topbar():
    """Refuse to measure whichever bar happens to be up.

    THIS GUARD IS NOT DEFENSIVE PROGRAMMING; it is here because the first run
    of this tool measured the wrong surface. The bar was switched underneath
    it mid-run -- the user is at the keyboard while this works -- and the
    "bar" it found was the island's 95 px capsule, reported a clean null, and
    would have been written up as "the topbar does not twitch". Both bars put
    a layer surface named `quickshell` at the top of the screen, so the
    namespace cannot tell them apart. The MODE file and the topbar's own IPC
    can.
    """
    try:
        with open(os.path.expanduser("~/.cache/bar-mode")) as handle:
            mode = handle.read().strip()
    except OSError:
        mode = ""
    answer = subprocess.run(["qs", "-p", TOPBAR_DIR, "ipc", "call",
                             "topbar", "status"],
                            capture_output=True, text=True, timeout=6)
    if mode != "native" or answer.returncode != 0:
        sys.exit(f"this measures the TOPBAR and the topbar is not up "
                 f"(bar-mode={mode!r}, topbar ipc exit={answer.returncode}).\n"
                 f"  bar-switch native     # and put it back afterwards")
    return mode


def bar_geometry():
    """The bar surface to watch, and the strip to record around its edges."""
    lay = json.loads(hypr("j/layers"))
    bars = []
    for _name, value in lay.items():
        for _level, surfaces in value.get("levels", {}).items():
            for surface in surfaces:
                if surface.get("namespace") == "quickshell" and surface["h"] > 4:
                    bars.append(surface)
    if not bars:
        sys.exit("no topbar layer surface found — is the topbar running? "
                 "`bar-switch native`")
    bar = max(bars, key=lambda s: s["h"])
    return bar


def changed_fraction(frame, baseline, threshold=18):
    """Per row, the fraction of columns that differ from the baseline.

    Sum-of-channels distance and a deliberately low threshold: a 2 px shift
    of the bar's edge over a dark wallpaper is a small colour step, and the
    thing that makes it unambiguous is not its size but the fact that it
    happens across the whole width at once.
    """
    delta = np.abs(frame.astype(np.int16) - baseline).sum(axis=2) > threshold
    return delta.mean(axis=1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="",
                        help="drive one popup by name")
    parser.add_argument("--hold", type=float, default=1.1,
                        help="seconds a popup stays open (default 1.1)")
    parser.add_argument("--keep", default="",
                        help="directory to keep the video and frames in")
    args = parser.parse_args()

    if not os.path.exists(SOCKET):
        sys.exit("no Hyprland socket — this is a Wayland-only test")

    require_topbar()
    bar = bar_geometry()
    # A strip that contains BOTH edges of the bar plus room below it, so a
    # bar that moves and a bar that shrinks are distinguishable.
    top = max(0, bar["y"] - 8)
    height = bar["h"] + 32
    region = f"0,{top} {bar['w']}x{height}"
    inside = max(2, bar["y"] - top + bar["h"] // 2)

    work = args.keep or tempfile.mkdtemp(prefix="bar-edge-")
    os.makedirs(work, exist_ok=True)
    video = os.path.join(work, "bar.mp4")

    drives = [p for p in POPUPS if not args.only or p[0] == args.only]
    if not drives:
        sys.exit(f"no popup named {args.only!r}")

    print(f"bar   y={bar['y']} h={bar['h']} w={bar['w']}  namespace={bar['namespace']}")
    print(f"strip {region}   (bar interior sampled at strip row {inside})")
    print(f"work  {work}")

    recorder = subprocess.Popen(
        ["wf-recorder", "-g", region, "-r", "60", "-f", video, "-c", "libx264",
         "-p", "crf=0", "-p", "preset=ultrafast", "-y"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    # From the SPAWN, not from the end of the settle: the capture contains
    # those two seconds and dividing by the driving time alone reported 87 fps
    # on a 60 Hz panel, which is a number that would have to be explained.
    recording_started = time.monotonic()
    time.sleep(2.0)          # wf-recorder needs a moment before it is capturing
    if recorder.poll() is not None:
        sys.exit("wf-recorder exited immediately:\n"
                 + recorder.stderr.read().decode(errors="replace"))

    sampler = Sampler()
    sampler.start()
    t0 = time.monotonic()
    timeline = []

    time.sleep(1.0)          # a second of nothing, as the baseline
    for name, call, entry in drives:
        timeline.append((time.monotonic() - t0, f"{name} open"))
        qs_call(entry, call)
        time.sleep(args.hold)
        timeline.append((time.monotonic() - t0, f"{name} close"))
        qs_call(entry, call)
        time.sleep(args.hold)
    time.sleep(0.6)

    sampler.stop_flag.set()
    sampler.join(timeout=2)
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=20)
    recorded_seconds = time.monotonic() - recording_started

    frames_dir = os.path.join(work, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    # -fps_mode passthrough, NOT -vsync: this ffmpeg removed -vsync, and
    # anything that resamples would invent or drop the very frame we are
    # hunting for.
    subprocess.run(["ffmpeg", "-loglevel", "error", "-i", video,
                    "-fps_mode", "passthrough",
                    os.path.join(frames_dir, "f%05d.png")], check=True)

    files = sorted(os.listdir(frames_dir))
    if not files:
        sys.exit("no frames came out of the capture")

    stack = np.stack([np.asarray(Image.open(os.path.join(frames_dir, name))
                                 .convert("RGB")) for name in files])
    print(f"\nframes {len(files)}  "
          f"({len(files) / max(1e-9, recorded_seconds):.1f} fps over the capture)")

    # The baseline is the MEDIAN of the quiet second, not its first frame: a
    # median cannot be poisoned by one frame that already carries the defect,
    # and a mean would smear a moving edge into a gradient nothing matches.
    quiet = min(len(files) - 1, int(60 * 0.9))
    baseline = np.median(stack[:quiet], axis=0)

    rows = np.array([changed_fraction(frame, baseline) for frame in stack])

    # The band the bar's own edge lives in. Rows above it are bar CONTENT --
    # a clock, an EQ -- and rows well below it are popup territory.
    edge_band = slice(max(0, bar["y"] - top + bar["h"] - 6),
                      min(height, bar["y"] - top + bar["h"] + 6))
    print(f"-- rows {edge_band.start}..{edge_band.stop - 1} of the strip "
          f"(the bar's bottom edge sits at {bar['y'] - top + bar['h']}) --")

    WIDE = 0.5      # more than half the width changed: the SHAPE moved
    suspects = []
    for index in range(len(files)):
        band = rows[index, edge_band]
        if band.max() > WIDE:
            suspects.append((index, float(band.max()),
                             int(np.argmax(band)) + edge_band.start))

    if suspects:
        print(f"\n-- {len(suspects)} frames where >50% of the width changed "
              f"in the edge band --")
        for index, fraction, row in suspects[:60]:
            print(f"  frame {index:5} (~{index / 60.0:6.2f}s)  row {row}  "
                  f"{fraction * 100:5.1f}% of the width   "
                  f"{frames_dir}/f{index + 1:05d}.png")
    else:
        print("\nno frame moves the edge band across the width. "
              f"Widest single-row change: {rows[:, edge_band].max() * 100:.1f}%.")

    # Said out loud even when nothing trips, because "the bar content animated"
    # is the answer that makes a null result trustworthy rather than suspicious.
    content = rows[:, :edge_band.start].max() if edge_band.start else np.zeros(1)
    print(f"  (bar CONTENT rows peaked at {np.max(content) * 100:.1f}% of the width, "
          f"so the capture did see the popups happen)")

    print("\n-- the compositor, on the same clock --")
    reserved = {row[1] for row in sampler.rows}
    surfaces = {row[2] for row in sampler.rows}
    print(f"  samples {len(sampler.rows)}")
    print(f"  reserved values seen: {sorted(reserved)}")
    print(f"  bar surface (y,h) sets seen: {sorted(surfaces)}")

    print("\n-- what was driven --")
    for when, what in timeline:
        print(f"  {when:6.2f}s  {what}")

    if not args.keep:
        print(f"\n(frames left in {work}; pass --keep DIR to choose the location)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
