#!/usr/bin/env python3
"""Drive every island state and every transition class, and report.  TEST TOOL.

    ./sweep-island.py              states, then transitions
    ./sweep-island.py --states     just the 24 states
    ./sweep-island.py --matrix     just the ten transition classes

WHY THIS EXISTS
---------------
NEXT-SESSION.md's standing requirement: "Every function and every case, in
both bars, driven rather than read." The island is 24 states and a
ten-row transition matrix, and until now checking one meant opening it and
looking — which is not a result, and does not scale to 24.

WHAT MADE IT POSSIBLE
---------------------
`tide state` — added alongside this file. Every other IPC on that target is
a way IN; there was no way to ask what happened. Without it a sweep can see
the capsule move and not see WHICH state it moved to, which makes
"rest -> panel" and "rest -> the wrong panel" the same measurement.

WHAT A FAILURE HERE MEANS
-------------------------
`FAIL` is "the IPC was called and the island did not end up in the state the
call names". That is a real defect. `SKIP` is a state this tool cannot reach
on its own — a polkit prompt needs a privileged action, a notification needs
a sender — and is not a defect, so it is counted separately and never
folded into the pass rate.

THE ISLAND HAS TO BE RUNNING. It does not have to be the ACTIVE bar: start
it beside the topbar with

    qs -p ~/.config/quickshell/tide-island-fork/shell.qml

and this sweep drives it without touching bar-mode. That matters because a
crash in a sweep of the active bar leaves the session with no bar at all.
"""

import argparse
import json
import subprocess
import sys
import time

# THE DIRECTORY, NOT THE ENTRY FILE, and the difference is not cosmetic.
# island.sh starts the island as `quickshell -p <DIR>` and `qs -p` keys an
# instance by the path it was GIVEN — so `-p .../shell.qml` addresses a
# different instance than the running one, and every call in this sweep would
# quietly reach nothing. The same distinction is what bar-switch's process
# matcher exists for; it is written up in NEXT-SESSION.md's RULES.
ISLAND = "~/.config/quickshell/tide-island-fork"

# (state, ipc-args, note)
#
# `rest` is not in the list because it is the thing every case returns TO,
# and it is asserted between cases instead.
STATES = [
    ("control_center", ["toggleControlCenter"], ""),
    ("notification_center", ["toggleNotificationCenter"], ""),
    ("application_launcher", ["toggleApplicationLauncher"], ""),
    ("wallpaper_picker", ["toggleWallpaperPicker"], ""),
    ("theme_picker", ["toggleThemePicker"], ""),
    ("calculator", ["toggleCalculator"], ""),
    ("calendar", ["toggleCalendar"], ""),
    ("power_menu", ["togglePowerMenu"], ""),
    ("settings", ["toggleSettings"], ""),
    ("sysmon_panel", ["toggleSysmon"], ""),
    ("wifi_panel", ["toggleWifiPanel"], ""),
    ("bluetooth_panel", ["toggleBluetoothPanel"], ""),
    ("display_panel", ["toggleDisplayPanel"], ""),
    ("audio_panel", ["toggleAudioPanel"], ""),
    ("wifi_qr", ["toggleWifiQr"], ""),
    ("cheatsheet", ["showCheatsheet", "hypr"], ""),
    ("onboarding", ["showOnboarding", "0"], ""),
    ("mode_keys", ["showModeKeys", "rofi"], ""),
    ("picker", ["showPicker", "clipboard"], "needs the backing script to answer"),
    ("custom", ["showCustom"], ""),
    # showText produces `split`, not `long_capsule`. Found by this sweep
    # failing and then reading the code rather than the name: showText ->
    # showModeIndicator -> islandState = "split". `long_capsule` is the
    # WORKSPACE capsule (showWorkspaceCapsule), which no IPC reaches — it is
    # driven below by an actual workspace switch.
    ("split", ["showText", "sweep"], "showText is the mode indicator OSD"),
]

# States this tool cannot reach without arranging the world first. Listed so
# the report says so out loud rather than quietly covering 22 of 24.
UNREACHABLE = {
    "notification": "needs a notification to arrive; drive notify-send instead",
    # Not a defect and not unreachable-in-principle: normalizeRestingState
    # returns "lyrics" only `&& hasMediaSurface`, and the fork note beside it
    # says why — unconditional was what let the island rest on a "No music
    # playing" card. With nothing playing, `normal` is the CORRECT answer, so
    # asserting "lyrics" here would be a test that fails correct code.
    "lyrics": "needs a player; falls back to normal by design when there is none",
    "polkit_prompt": "needs a privileged action to raise an agent prompt",
    "expanded": "hover/gesture state, not an IPC",
    "bluetooth_expanded": "reached from inside the bluetooth panel",
}

# The ten transition classes from NEXT-SESSION.md, as (from, to) drivers.
MATRIX = [
    ("rest -> panel", None, ["toggleControlCenter"], "control_center"),
    ("panel -> rest", ["toggleControlCenter"], ["toggleControlCenter"], "normal"),
    ("panel A -> panel B", ["toggleControlCenter"], ["toggleSysmon"], "sysmon_panel"),
    # "text" is the mode indicator, and its state is `split` — see the note
    # on the STATES table.
    ("rest -> text", None, ["showText", "hello"], "split"),
    ("text -> text", ["showText", "one"], ["showText", "two"], "split"),
    ("text -> panel", ["showText", "one"], ["toggleControlCenter"], "control_center"),
    ("panel -> text", ["toggleControlCenter"], ["showText", "one"], "split"),
    ("rest -> mode_keys", None, ["showModeKeys", "rofi"], "mode_keys"),
    ("panel -> picker", ["toggleControlCenter"], ["showPicker", "clipboard"], "picker"),
    ("any -> overview", ["toggleControlCenter"], None, "overview"),
]


def ipc(target, *args, timeout=6):
    cmd = ["qs", "-p", ISLAND.replace("~", subprocess.os.path.expanduser("~")),
           "ipc", "call", target] + list(args)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    return (proc.stdout or "").strip()


def state():
    """The island's own report, or None if it is not running."""
    raw = ipc("tide", "state")
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


def rest(settle=0.45):
    """Back to the resting state, whatever we are in.

    `smartRestoreState` is not on the IPC surface, so rest is reached by
    closing what is open. showClock is the one call that always lands on a
    resting state without needing to know which state we are leaving.

    clearModeKeys IS PART OF RESTING, and leaving it out cost a false
    failure: smartRestoreState re-asserts the chord HUD whenever
    `modeKeysName` is still set —

        if (modeKeysName !== "") { showModeKeys(modeKeysName); return; }

    — which is deliberate and documented there (a volume OSD arriving inside
    a submap should go back to saying which submap you are in, not drop you
    to the clock while the chord still swallows keys). So after the
    `mode_keys` case every later "back to rest" landed on mode_keys, and the
    matrix reported `panel -> rest` as broken. The island was right; the
    sweep was not resetting the world between cases.
    """
    ipc("tide", "clearModeKeys")
    # And the mode INDICATOR, for the same reason one layer down: "a mode
    # indicator outlives the transients that interrupt it" is the note beside
    # smartRestoreState, so a showText from an earlier case survived into the
    # next one and `panel -> rest` landed on `split`. Two different pieces of
    # deliberate stickiness, both of which a sweep has to undo between cases.
    ipc("tide", "clearText")
    ipc("tide", "showClock")
    time.sleep(settle)
    ipc("overview", "close")
    time.sleep(settle)


def sweep_states(settle):
    print("\n-- the island's states --")
    passed = failed = skipped = 0

    for name, reason in sorted(UNREACHABLE.items()):
        print(f"  {name:22} SKIP   {reason}")
        skipped += 1

    for expected, args, note in STATES:
        rest(settle)
        before = state()
        ipc("tide", *args)
        time.sleep(settle)
        after = state()
        if after is None:
            print(f"  {expected:22} FAIL   island stopped answering")
            failed += 1
            continue
        got = after.get("state", "")
        if got == expected:
            print(f"  {expected:22} PASS   h={after['height']:<4} w={after['width']:<5}"
                  f" {note}")
            passed += 1
        else:
            print(f"  {expected:22} FAIL   got {got!r}"
                  f" (was {before.get('state') if before else '?'!r}) {note}")
            failed += 1

    rest(settle)
    return passed, failed, skipped


def sweep_workspace_capsule(settle):
    """long_capsule, driven the only way it can be: by switching workspace.

    No IPC reaches showWorkspaceCapsule — it is called from the workspace
    event — so this is the one case in the sweep that drives the COMPOSITOR
    and then asks the island what it did.
    """
    print("\n-- the workspace capsule --")
    rest(settle)
    before = subprocess.run(["hyprctl", "activeworkspace", "-j"],
                            capture_output=True, text=True).stdout
    try:
        origin = json.loads(before)["id"]
    except Exception:
        print("  long_capsule           SKIP   could not read the active workspace")
        return 0, 0, 1

    target = 3 if origin != 3 else 2
    subprocess.run(["hyprctl", "dispatch", "workspace", str(target)],
                   capture_output=True)
    time.sleep(settle)
    after = state()
    got = (after or {}).get("state", "?")
    # Put the user back before reporting, so a failure cannot also leave the
    # session on the wrong workspace.
    subprocess.run(["hyprctl", "dispatch", "workspace", str(origin)],
                   capture_output=True)
    time.sleep(settle)
    rest(settle)

    if got == "long_capsule":
        print(f"  long_capsule           PASS   h={after['height']:<4} w={after['width']:<5}"
              f" (workspace {origin} -> {target} -> {origin})")
        return 1, 0, 0
    print(f"  long_capsule           FAIL   expected 'long_capsule', got {got!r}")
    return 0, 1, 0


def sweep_matrix(settle):
    print("\n-- the ten transition classes --")
    passed = failed = 0
    for label, setup, drive, expected in MATRIX:
        rest(settle)
        if setup:
            ipc("tide", *setup)
            time.sleep(settle)
        before = state()

        if expected == "overview":
            ipc("overview", "open")
            time.sleep(settle)
            after = state()
            ok = bool(after and after.get("overview"))
            got = "overview" if ok else (after or {}).get("state", "?")
            ipc("overview", "close")
        else:
            ipc("tide", *drive)
            time.sleep(settle)
            after = state()
            got = (after or {}).get("state", "?")
            ok = got == expected

        if ok:
            size = f"h={after['height']:<4} w={after['width']:<5}" if after else ""
            print(f"  {label:22} PASS   {before.get('state','?') if before else '?'}"
                  f" -> {got:<20} {size}")
            passed += 1
        else:
            print(f"  {label:22} FAIL   expected {expected!r}, got {got!r}")
            failed += 1
    rest(settle)
    return passed, failed


def bar_mode():
    try:
        with open(subprocess.os.path.expanduser("~/.cache/bar-mode")) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--states", action="store_true")
    parser.add_argument("--matrix", action="store_true")
    parser.add_argument("--settle", type=float, default=0.45,
                        help="seconds to wait after each drive (default 0.45)")
    args = parser.parse_args()

    if state() is None:
        sys.exit("the island is not running — start it with:\n"
                 f"  qs -p {ISLAND}")

    # A SWEEP MUST GIVE THE DESKTOP BACK. Recorded here and checked at the
    # end: a run of this tool once ended with ~/.cache/bar-mode reading
    # `island` when it had started at `native`, which left the session
    # wearing a different bar than the user chose. Whatever moved it, a test
    # that can change which bar you are running is a test that has to say so.
    mode_before = bar_mode()

    do_states = args.states or not args.matrix
    do_matrix = args.matrix or not args.states

    p = f = s = mp = mf = 0
    if do_states:
        p, f, s = sweep_states(args.settle)
        wp, wf, ws = sweep_workspace_capsule(args.settle)
        p, f, s = p + wp, f + wf, s + ws
    if do_matrix:
        mp, mf = sweep_matrix(args.settle)

    mode_after = bar_mode()
    if mode_after != mode_before:
        print(f"\n  !! bar-mode moved {mode_before!r} -> {mode_after!r} during this run."
              f"\n     Put it back with:  bar-switch {mode_before}")

    print("\n-- totals --")
    if do_states:
        print(f"  states       {p} pass, {f} fail, {s} skipped (not reachable from a script)")
    if do_matrix:
        print(f"  transitions  {mp} pass, {mf} fail")
    return 1 if (f or mf) else 0


if __name__ == "__main__":
    sys.exit(main())
