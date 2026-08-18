#!/usr/bin/env python3
"""Does WlrKeyboardFocus.OnDemand deliver a keypress to the open shelf?  TEST TOOL.

Item 1's candidate fix moves the qdrop-armed keyboard-focus mode from
"exclusive" to "ondemand" so a second Wayland drag is not cancelled (measured
separately with qdrop-drags.py: ondemand lets both drags land, exclusive lets
only the first). This script answers the other half of that trade: does
"ondemand" still deliver a keystroke to the panel at all, since the shelf's
hjkl/ctrl+z/ctrl+d/y/s// commands need real key delivery and OnDemand is not
a guaranteed grab the way Exclusive is.

Opens the shelf by key (`qdrop open`), sends Escape through a real uinput
device, and checks whether the island's state left "qdrop" — which only
happens if the panel's own Keys handler actually received and acted on the
key. Refuses to run unless the active workspace is empty, same guard as
qdrop-drags.py.
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


def main():
    workspace = json.loads(hyprctl("activeworkspace", "-j"))["id"]
    stray = [c for c in clients() if c["workspace"]["id"] == workspace]
    if stray:
        sys.exit(f"workspace {workspace} is not empty — {[c['class'] for c in stray]}")

    ipc("qdrop", "open")
    time.sleep(1.0)

    before = state()
    print(f"before escape: {before}")
    if before.get("state") != "qdrop":
        sys.exit("shelf did not open at all — aborting before any synthetic input")

    # Re-check immediately before the synthetic key, per RULES.
    now = json.loads(hyprctl("activeworkspace", "-j"))["id"]
    stray = [c for c in clients() if c["workspace"]["id"] == now]
    if now != workspace or stray:
        sys.exit("ABORTED: workspace changed or picked up a window since the check")

    result = subprocess.run(
        [sys.executable, f"{HERE}/uinput-key.py", "escape"],
        capture_output=True, text=True, timeout=20)
    print(result.stdout)
    print(result.stderr, file=sys.stderr)

    time.sleep(0.5)
    after = state()
    print(f"after escape:  {after}")

    if after.get("state") == "qdrop":
        print("\nRESULT: escape did NOT close the shelf -- ondemand did not deliver the key")
        # Clean up so the panel is not left open.
        ipc("qdrop", "close")
    else:
        print("\nRESULT: escape DID close the shelf -- ondemand delivered the key")


if __name__ == "__main__":
    main()
