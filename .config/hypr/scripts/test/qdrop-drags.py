#!/usr/bin/env python3
"""Drive drags into the drop shelf, one after another, and count.  TEST TOOL.

    ./qdrop-drags.py --open key     shelf opened by a KEY   (takes the grab)
    ./qdrop-drags.py --open drag    shelf opened for a DRAG (waives the grab)
    ./qdrop-drags.py --drags 3      how many in a row (default 2)

WHY COUNTING TWICE IS THE WHOLE TEST
------------------------------------
Reported: "i can add to it before the dropshelf opened -- i shake and then
drag into it -- but when it is open i can not use what behind the dropshelf,
i can not drag anything again and also can not zip or copy or drag the things
off."

So the FIRST drop works and the shelf is inert afterwards. A test that drives
one drag and sees it land reproduces the half that already works. The defect
only exists in the SECOND drag, which is why this drives N and prints the
store count after each one:

    2, 3      both landed
    2, 2      the second was cancelled -- the reported bug
    1, 1      nothing lands at all, which is a different bug

THE MECHANISM IT IS AIMED AT
----------------------------
An exclusive keyboard grab CANCELS an in-flight Wayland drag; that is
measured and is written up beside `islandKeyboardFocus`. The shelf therefore
waives the grab while it is waiting for the drop it was opened to receive
(`qdropForDrag`) and takes it the moment the drop lands (`onDropLanded`).
Which means that after the first drop the grab is ON, and the current design
can hold the keyboard or accept a second drag but never both.

`--open key` and `--open drag` are the two halves of that A/B: the same
gesture with the grab on and with it off.

SAFETY
------
It refuses to run unless the active workspace is EMPTY apart from its own
peer window. A previous synthetic drag ran on the wrong workspace and put a
button press into nvim. The file it offers is written into a temp directory
of its own and nothing here ever touches a real file.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")
STORE = os.path.expanduser("~/.cache/qdrop.json")
HERE = os.path.dirname(os.path.abspath(__file__))


def ipc(target, *args):
    return subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target] + list(args),
                          capture_output=True, text=True, timeout=8).stdout.strip()


def hyprctl(*args):
    return subprocess.run(["hyprctl"] + list(args),
                          capture_output=True, text=True, timeout=8).stdout


def clients():
    return json.loads(hyprctl("clients", "-j"))


def entries():
    try:
        with open(STORE) as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return -1
    return len(data) if isinstance(data, list) else -1


def island_state():
    try:
        return json.loads(ipc("tide", "state"))
    except ValueError:
        return {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--open", dest="mode", choices=("key", "drag", "none"),
                        default="key")
    parser.add_argument("--drags", type=int, default=2)
    parser.add_argument("--hold", type=float, default=1.6)
    args = parser.parse_args()

    workspace = json.loads(hyprctl("activeworkspace", "-j"))["id"]
    others = [c for c in clients()
              if c["workspace"]["id"] == workspace and "dnd-peer" not in c["class"]]
    if others:
        sys.exit(f"workspace {workspace} is not empty — "
                 f"{[c['class'] for c in others]}. Switch to an empty one first; "
                 f"a synthetic drag over real windows is how a press landed in nvim.")

    def guard():
        """Re-checked immediately before every synthetic press.

        THE ONE CHECK AT STARTUP WAS NOT ENOUGH, AND IT WAS DRIVEN, NOT
        THEORISED: a run of this tool checked workspace 9 was empty, spent
        the next several seconds spawning the peer and opening the shelf, and
        by the time the drag actually fired the user had switched back to
        their real workspace -- the press landed in their live nvim. A single
        check at the top leaves every second after it unguarded.

        So every uinput dispatch in this file goes through here first, and
        the whole run aborts the INSTANT the workspace moves or the peer
        stops being the only thing on it, rather than firing blind.
        """
        now = json.loads(hyprctl("activeworkspace", "-j"))["id"]
        stray = [c for c in clients()
                if c["workspace"]["id"] == workspace and "dnd-peer" not in c["class"]]
        if now == workspace and not stray:
            return
        # Close whatever peer we opened before handing back control — an
        # aborted run should not leave a floating test window behind either.
        for client in clients():
            if "dnd-peer" in client["class"]:
                hyprctl("dispatch", "closewindow", "address:" + client["address"])
        if now != workspace:
            sys.exit(f"\nABORTED: active workspace moved {workspace} -> {now} "
                     f"since the run started. Not sending synthetic input to "
                     f"whatever is there now.")
        sys.exit(f"\nABORTED: workspace {workspace} picked up "
                 f"{[c['class'] for c in stray]} since the run started.")

    work = tempfile.mkdtemp(prefix="qdrop-drags-")
    offer = os.path.join(work, "dragged.txt")
    with open(offer, "w") as handle:
        handle.write("qdrop-drags.py\n")

    peer = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "dnd-peer.py"), offer],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(3.0)

    window = next((c for c in clients() if "dnd-peer" in c["class"]), None)
    if window is None:
        peer.kill()
        sys.exit("the peer window never appeared")

    # ---- THE PEER HAS TO SIT BELOW THE ISLAND'S SURFACE ----
    #
    # Tiled, the peer fills the workspace and its SOURCE label spans y 53..405.
    # The island's layer surface with the shelf open is 1366x368 — the full
    # width — so a press at y=229 is inside it and the peer never sees the
    # pointer at all. Measured exactly that way: with the grab point at y=405
    # the peer printed "pointer entered", and at y=229 it printed nothing.
    #
    # So the peer is floated and parked low. A Wayland client cannot place
    # itself; the compositor can, and addressing it by ADDRESS rather than by
    # class avoids the question of what a GTK window's app_id is.
    # `resizewindowpixel`, not `resizewindowpixelexact` — the latter answers
    # "Invalid dispatcher" and hyprctl reports that on stdout with exit 0, so
    # a caller that does not read the output sees a move that silently did
    # nothing. `exact` is the first WORD of the argument, not part of the name.
    guard()
    address = "address:" + window["address"]
    hyprctl("dispatch", "setfloating", address)
    hyprctl("dispatch", "resizewindowpixel", f"exact 420 200,{address}")
    hyprctl("dispatch", "movewindowpixel", f"exact 120 470,{address}")
    time.sleep(0.6)
    window = next((c for c in clients() if "dnd-peer" in c["class"]), window)
    # The UPPER QUARTER, and this is not arbitrary. dnd-peer packs its SOURCE
    # label above its TARGET label in a vertical box, so on a tiled window the
    # boundary between them is the vertical middle -- and pressing there put
    # the press on the drop target instead of the drag source. The peer said
    # so out loud ("pointer entered" with no "button pressed"), which is the
    # reason its header calls those three prints load-bearing.
    px = window["at"][0] + window["size"][0] // 3
    py = window["at"][1] + window["size"][1] // 4

    guard()
    if args.mode == "key":
        ipc("qdrop", "open")
    elif args.mode == "drag":
        ipc("qdrop", "openForDrag")
    time.sleep(1.2)

    state = island_state()
    # Aim at the middle of the capsule the island reports, not at a guess: the
    # shelf's height depends on how many tiles it holds.
    tx = 1366 // 2
    ty = max(40, int(state.get("height", 200)) // 2)

    print(f"open mode      {args.mode}")
    print(f"island state   {state}")
    print(f"peer at        ({px}, {py})   target ({tx}, {ty})")
    print(f"entries before {entries()}")

    counts = [entries()]
    for index in range(args.drags):
        guard()
        drag = subprocess.run(
            [sys.executable, os.path.join(HERE, "uinput-shake.py"),
             "to", str(px), str(py), str(tx), str(ty)],
            capture_output=True, text=True, timeout=60)
        # Printed, not swallowed: "GAVE UP" from the steerer and "CANCELLED"
        # from the store are the same line of output otherwise, and only one
        # of them is a defect in the shell.
        for line in drag.stdout.strip().splitlines():
            print(f"    {line.strip()}")
        time.sleep(args.hold)
        counts.append(entries())
        print(f"  drag {index + 1}: entries {counts[-2]} -> {counts[-1]}"
              f"   {'LANDED' if counts[-1] > counts[-2] else 'CANCELLED'}")

    print(f"\nentries {' -> '.join(str(c) for c in counts)}")
    peer.terminate()
    try:
        peer.wait(timeout=4)
    except subprocess.TimeoutExpired:
        peer.kill()
    print("\n-- what the peer saw --")
    print(peer.stdout.read() if peer.stdout else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
