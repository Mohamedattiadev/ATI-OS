#!/usr/bin/env python3
"""Drive the topbar's own state machine, and check every action it can take.

    ./sweep-topbar.py

WHY THIS SHAPE
--------------
The island's sweep can ask `tide state` what happened. The topbar has no
equivalent for its CHIPS — they are click handlers, and a click needs a
screen position — so this covers the two things that can be checked without
aiming a pointer, and says so rather than pretending to cover more:

  1. THE BAR'S OWN STATE: position top/bottom/toggle and the three widget
     boxes, driven over IPC and read back over IPC.

  2. EVERY ACTION ati-bar-action CAN TAKE. That table is the topbar's action
     surface — every chip and every key under this bar ends up in it — and
     its failure mode is a command that is not there. That is not
     hypothetical: `display-ctl.py --menu` was dead code guarding an
     uninstalled `nwg-displays`, and neither half announced itself, because
     a missing command and a working one both exit quietly.

WHAT IS NOT COVERED, and is left to the eye or to a click test: whether a
chip is in the right PLACE, and what it looks like.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
TOPBAR = f"{HOME}/.config/quickshell/topbar"
POPUPS = f"{HOME}/.config/quickshell/tide-island-fork/popups.qml"
BAR_ACTION = f"{HOME}/.config/AtiScriptsV1/bar/ati-bar-action"


def ipc(path, target, *args):
    try:
        proc = subprocess.run(["qs", "-p", path, "ipc", "call", target] + list(args),
                              capture_output=True, text=True, timeout=6)
    except subprocess.TimeoutExpired:
        return ""
    return (proc.stdout or "").strip()


def sweep_bar_state():
    print("\n-- the bar's own state --")
    passed = failed = 0

    origin = ipc(TOPBAR, "topbar", "status")
    if not origin:
        print("  the topbar is not running — skipping its IPC")
        return 0, 0

    for want in ("bottom", "top"):
        ipc(TOPBAR, "topbar", want)
        time.sleep(0.5)
        got = ipc(TOPBAR, "topbar", "status")
        ok = got == want
        print(f"  position {want:<8} {'PASS' if ok else 'FAIL'}   status={got!r}")
        passed, failed = (passed + 1, failed) if ok else (passed, failed + 1)

    # Back to where it was found, before the boxes are touched.
    ipc(TOPBAR, "topbar", origin)
    time.sleep(0.4)

    for box, show, hide in (("tray", "showTrayBox", "hideTrayBox"),
                            ("system", "showSystemBox", "hideSystemBox"),
                            ("second", "showSecondBox", "hideSecondBox")):
        ipc(TOPBAR, "topbar", show)
        time.sleep(0.35)
        opened = ipc(TOPBAR, "topbar", "boxes")
        ipc(TOPBAR, "topbar", hide)
        time.sleep(0.35)
        closed = ipc(TOPBAR, "topbar", "boxes")
        # `boxes()` answers "system=false second=false tray=true", so a
        # substring test for the box's NAME is true in both states — the
        # first version of this check passed the open string and the closed
        # one identically and reported three false failures. Compare the
        # assignment.
        ok = f"{box}=true" in opened and f"{box}=false" in closed
        print(f"  {box + ' box':<17} {'PASS' if ok else 'FAIL'}"
              f"   open={opened!r} closed={closed!r}")
        passed, failed = (passed + 1, failed) if ok else (passed, failed + 1)

    restored = ipc(TOPBAR, "topbar", "status")
    print(f"  restored to {restored!r} (was {origin!r})")
    return passed, failed


def bar_action_commands():
    """Every command the native branch of ati-bar-action can run.

    Parsed out of the script rather than duplicated here: a copy would drift
    the first time a row is added, and the whole point is to catch a row that
    names something absent.
    """
    text = open(BAR_ACTION, encoding="utf-8").read()
    body = text.split("native — the qtile-style topbar is up", 1)[-1]

    found = []
    for line in body.splitlines():
        line = line.strip()
        if line.startswith("#") or ")" not in line:
            continue
        match = re.match(r'^(.+?)\)\s+(run|run_sh|run_popup|run_popup_arg)\s+(.*?);;', line)
        if not match:
            continue
        key, kind, rest = match.group(1), match.group(2), match.group(3).strip()
        found.append((key.strip('"'), kind, rest))
    return found


def first_word(rest):
    rest = rest.strip()
    if rest.startswith(("'", '"')):
        quote = rest[0]
        end = rest.find(quote, 1)
        rest = rest[1:end] if end > 0 else rest[1:]
    for token in rest.split():
        if "=" in token and not token.startswith("/"):
            continue          # env assignments like GTK_THEME=...
        if token in ("env", "exec", "sh", "-c"):
            continue
        return token.strip("'\"")
    return ""


def sweep_actions():
    print("\n-- every action ati-bar-action can take (native branch) --")
    passed = failed = 0
    popup_names = set()

    for key, kind, rest in bar_action_commands():
        if kind in ("run_popup", "run_popup_arg"):
            name = rest.split()[0]
            popup_names.add(name)
            print(f"  {key:<28} popup   {name}")
            passed += 1
            continue

        command = first_word(rest)
        if not command:
            print(f"  {key:<28} FAIL    could not parse a command from {rest!r}")
            failed += 1
            continue
        target = command if command.startswith("/") else shutil.which(command)
        if command.startswith("$"):
            print(f"  {key:<28} SKIP    variable command {command}")
            continue
        if target:
            print(f"  {key:<28} PASS    {command}")
            passed += 1
        else:
            print(f"  {key:<28} FAIL    {command} IS NOT ON PATH")
            failed += 1

    # The popups the table names must actually exist in the popups shell, or
    # the key is the same silent nothing display-ctl --menu was.
    if popup_names:
        print("\n-- the popups those rows name --")
        for name in sorted(popup_names):
            before = ipc(POPUPS, "popups", "status")
            # The IPC name is NOT derivable from the popup's name, and
            # guessing produced two false failures: the wifi QR's is
            # `showWifiQr` with a capital Q, and the cheatsheet's takes an
            # argument so it is `cheatsheet <which>` rather than a show*.
            # Spelt out against popups.qml.
            show = {
                "wallpaper": ("showWallpaper",),
                "network": ("showNetwork",),
                "volume": ("showVolume",),
                "wifiqr": ("showWifiQr",),
                "display": ("showDisplay",),
                "bluetooth": ("showBluetooth",),
                "cheatsheet": ("cheatsheet", "hypr"),
            }.get(name)
            if show is None:
                print(f"  {name:<28} SKIP    no IPC known for this popup")
                continue
            out = ipc(POPUPS, "popups", *show)
            time.sleep(1.2)
            got = ipc(POPUPS, "popups", "status")
            ipc(POPUPS, "popups", "close")
            time.sleep(0.4)
            ok = got == name
            print(f"  {name:<28} {'PASS' if ok else 'FAIL'}   status={got!r}")
            passed, failed = (passed + 1, failed) if ok else (passed, failed + 1)

    return passed, failed


def main():
    p1, f1 = sweep_bar_state()
    p2, f2 = sweep_actions()
    print("\n-- totals --")
    print(f"  bar state   {p1} pass, {f1} fail")
    print(f"  actions     {p2} pass, {f2} fail")
    return 1 if (f1 or f2) else 0


if __name__ == "__main__":
    sys.exit(main())
