#!/usr/bin/env python3
"""Does a click restore keyboard control after a shake-drag left the shelf on
"ondemand"?  TEST TOOL, for item 1's third bullet in PROMPT-NEXT.md.

The fix that lets a second drag land (`qdropDragSession`, DynamicIslandWindow.qml)
trades away the automatic exclusive grab a shake-triggered drop used to take:
a session that has ever seen a drag stays on WlrKeyboardFocus.OnDemand for the
rest of its life, and OnDemand does not deliver a key with no prior click
(measured separately, qdrop-ondemand-key.py). `onFocusWanted: forceActiveFocus()`
is already wired in QdropLayer.qml for the search field; this checks whether a
plain click on the panel's background claims that same focus for a plain key
like Escape too.

Drives: shake-open (drag mode) -> one real drag lands -> click the panel
background -> Escape. If Escape closes it, the click restored control. Same
empty-workspace guard as the other qdrop test tools.
"""

import json
import os
import subprocess
import sys
import time

ISLAND = os.path.expanduser("~/.config/quickshell/tide-island-fork")
HERE = os.path.expanduser("~/.config/hypr/scripts/test")


def hyprctl(*args):
    return subprocess.run(["hyprctl"] + list(args),
                          capture_output=True, text=True, timeout=8).stdout


def ipc(target, *args):
    return subprocess.run(["qs", "-p", ISLAND, "ipc", "call", target] + list(args),
                          capture_output=True, text=True, timeout=8).stdout.strip()


def clients():
    return json.loads(hyprctl("clients", "-j"))


def state():
    try:
        return json.loads(ipc("tide", "state"))
    except ValueError:
        return {}


def guard(workspace):
    now = json.loads(hyprctl("activeworkspace", "-j"))["id"]
    stray = [c for c in clients()
             if c["workspace"]["id"] == workspace and "dnd-peer" not in c["class"]]
    if now != workspace or stray:
        for client in clients():
            if "dnd-peer" in client["class"]:
                hyprctl("dispatch", "closewindow", "address:" + client["address"])
        sys.exit(f"ABORTED: workspace/window guard failed (now={now}, stray={stray})")


def main():
    workspace = json.loads(hyprctl("activeworkspace", "-j"))["id"]
    stray = [c for c in clients() if c["workspace"]["id"] == workspace]
    if stray:
        sys.exit(f"workspace {workspace} is not empty — {[c['class'] for c in stray]}")

    import tempfile
    work = tempfile.mkdtemp(prefix="qdrop-click-")
    offer = os.path.join(work, "dragged.txt")
    with open(offer, "w") as h:
        h.write("qdrop-ondemand-click.py\n")

    peer = subprocess.Popen(
        [sys.executable, f"{HERE}/dnd-peer.py", offer],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(3.0)
    window = next((c for c in clients() if "dnd-peer" in c["class"]), None)
    if window is None:
        peer.kill()
        sys.exit("the peer window never appeared")

    guard(workspace)
    address = "address:" + window["address"]
    hyprctl("dispatch", "setfloating", address)
    hyprctl("dispatch", "resizewindowpixel", f"exact 420 200,{address}")
    hyprctl("dispatch", "movewindowpixel", f"exact 120 470,{address}")
    time.sleep(0.6)
    window = next((c for c in clients() if "dnd-peer" in c["class"]), window)
    px = window["at"][0] + window["size"][0] // 3
    py = window["at"][1] + window["size"][1] // 4

    guard(workspace)
    ipc("qdrop", "openForDrag")
    time.sleep(1.2)

    st = state()
    tx, ty = 1366 // 2, max(40, int(st.get("height", 200)) // 2)
    print(f"island state before drag: {st}")

    guard(workspace)
    drag = subprocess.run(
        [sys.executable, f"{HERE}/uinput-shake.py", "to",
         str(px), str(py), str(tx), str(ty)],
        capture_output=True, text=True, timeout=60)
    print(drag.stdout)
    time.sleep(1.0)
    print(f"island state after drag:  {state()}")

    # Click on the panel background — well clear of any tile, low in the
    # shelf, aiming at empty grid space rather than a row.
    click_x, click_y = tx, ty + 60
    guard(workspace)
    hyprctl("dispatch", "movecursor", f"{click_x} {click_y}")
    time.sleep(0.2)
    click = subprocess.run([sys.executable, f"{HERE}/uinput-click.py", "left"],
                           capture_output=True, text=True, timeout=15)
    print(click.stdout)

    guard(workspace)
    esc = subprocess.run([sys.executable, f"{HERE}/uinput-key.py", "escape"],
                         capture_output=True, text=True, timeout=15)
    print(esc.stdout)
    time.sleep(0.5)
    after = state()
    print(f"island state after click+escape: {after}")

    if after.get("state") == "qdrop":
        print("\nRESULT: click did NOT restore keyboard control")
        ipc("qdrop", "close")
    else:
        print("\nRESULT: click DID restore keyboard control -- escape closed the shelf")

    peer.terminate()
    try:
        peer.wait(timeout=4)
    except subprocess.TimeoutExpired:
        peer.kill()


if __name__ == "__main__":
    main()
