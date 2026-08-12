#!/usr/bin/env python3
"""island-picker.py — list menus for the island's generic picker panel.

WHY THIS EXISTS
---------------
qtile's session reached ~20 rofi/dm-* menus, bound under the `$mod P` submap.
Every one of them is a separate bash script that builds a list, pipes it to
rofi, reads a line back and acts on it. They work, and they will keep
working — this does not replace them wholesale.

What it replaces is the SHAPE of the ones that are only ever "pick a row and
do the thing", because that shape already exists in this shell three times
over (the settings panel, the theme picker, the cheatsheet) and a rofi window
in the middle of a Hyprland session running a notch shell looks like what it
is: a different program.

WHAT IS NOT HERE, AND WHY
-------------------------
Menus that PROMPT — rofi_pass, dm-recordV2, dm-spellcheck, the translator —
are not ported. Not because the island cannot take text: it can, and this
file's own panel has a search field. It is that those scripts are
conversations (ask, branch, ask again), and a one-shot list is the wrong
primitive for a conversation. Wrapping them would mean reimplementing each
script's control flow in QML, which is how a port becomes a rewrite.

CORRECTION, and it is worth writing down because it was said three times in
one session and acted on twice: the claim "the island has no text-entry
field" is FALSE. There are five TextInputs in the tree — the cheatsheet
search, the application launcher search, two Wi-Fi password fields and one in
the expanded player. The settings panel's lack of a string editor is a
property of that panel, not of the shell, and the rofi port was scoped
smaller than it needed to be on the strength of it.

THE PROTOCOL
------------
    island-picker.py --list <menu>     -> {"title":..., "items":[...]}
    island-picker.py --run <menu> <id> -> {"ok":true}

An item is {id, label, detail}. The panel never sees a command: it sends the
`id` back and this file decides what that means. That is deliberate — a panel
that executes strings handed to it by a script is a panel that executes
whatever anything can write into that script's output.
"""

import json
import os
import shutil
import signal
import subprocess
import sys


def _hypr(*args):
    """hyprctl -j, parsed. [] when Hyprland is not answering."""
    try:
        out = subprocess.run(["hyprctl", "-j", *args],
                             capture_output=True, text=True, timeout=4)
        return json.loads(out.stdout) if out.returncode == 0 else []
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


# ---------------------------------------------------------------- windows --

def windows_list():
    items = []
    for client in _hypr("clients"):
        address = client.get("address") or ""
        title = (client.get("title") or "").strip()
        cls = (client.get("class") or "").strip()
        if not address or client.get("workspace", {}).get("id", 0) < 0 and not title:
            continue
        workspace = client.get("workspace", {}).get("name", "?")
        items.append({
            "id": address,
            "label": title or cls or address,
            # The class and workspace, not the pid: this menu closes a WINDOW,
            # and "which of my six terminals is this" is answered by where it
            # is, never by its pid.
            "detail": "%s  ·  workspace %s" % (cls or "?", workspace),
        })
    items.sort(key=lambda row: row["label"].lower())
    return {"title": "Close window", "items": items}


def windows_run(item_id):
    subprocess.run(["hyprctl", "dispatch", "closewindow", "address:%s" % item_id],
                   capture_output=True, timeout=4)


# --------------------------------------------------------------- processes --
#
#  ---- WHY THIS LIST JOINS AGAINST THE WINDOW LIST ----
#
#  A memory-sorted process list on a browsing machine is mostly one word
#  repeated: brave, brave, brave, brave. The command line does not rescue it
#  either, because a Chromium helper's args are
#  `--type=renderer --crashpad-handler-pid=513495 --enable-crash-reporter=…`
#  — the same string, modulo digits, for every one of them. So the list said
#  "brave (243 MB)" six times and there was no way to tell which was the
#  video, which was the mail tab, and which was safe to kill.
#
#  The missing fact is which WINDOW a process belongs to, and Hyprland knows
#  it: `hyprctl clients -j` carries a `pid` per window. A direct pid match
#  covers the process that owns the window. It does NOT cover the helpers,
#  which is most of the list — Chromium's renderers are grandchildren of the
#  browser through a zygote, and QtWebEngine's are three deep. Measured on
#  this machine:
#
#    513611 -> 513555 -> 513483(brave, owns the window)
#    516487 -> 513566 -> 513562 -> 513483
#    514293 -> 514255 -> 514253 -> 514228(qutebrowser, owns the window)
#
#  So the lookup walks /proc/<pid>/stat upward until it hits a pid that owns
#  a window, and reports the process as a helper OF that window. Depth is
#  capped and visited pids are remembered: a pid table is read
#  non-atomically and a cycle in it, however unlikely, must not hang a menu.

def _ppid(pid):
    """Parent of `pid`, 0 if it cannot be read.

    Split on the LAST ')' rather than by whitespace: field 2 is the comm and
    it is neither quoted nor escaped, so a process named `foo bar)baz` — any
    user can make one — shifts every field after it if parsed naively.
    """
    try:
        with open("/proc/%d/stat" % pid) as handle:
            return int(handle.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def _window_owners():
    """pid -> [(title, class, workspace)], one entry per window it owns."""
    owners = {}
    for client in _hypr("clients"):
        pid = client.get("pid")
        if not isinstance(pid, int) or pid <= 0:
            continue
        owners.setdefault(pid, []).append((
            (client.get("title") or "").strip(),
            (client.get("class") or "").strip(),
            str(client.get("workspace", {}).get("name", "?")),
        ))
    return owners


def _owning_window(pid, owners, max_depth=12):
    """(title, class, workspace, hops) for the nearest window-owning ancestor.

    hops == 0 means this process owns the window itself. None when nothing
    in the ancestry owns one — a daemon, a compiler, a shell.
    """
    current, hops, seen = pid, 0, set()
    while current > 1 and hops <= max_depth and current not in seen:
        seen.add(current)
        windows = owners.get(current)
        if windows:
            title, cls, workspace = windows[0]
            if len(windows) > 1:
                title = "%s  (+%d more)" % (title, len(windows) - 1)
            return title, cls, workspace, hops
        current = _ppid(current)
        hops += 1
    return None


def _helper_role(args):
    """Chromium/QtWebEngine `--type=` value, e.g. renderer, gpu-process."""
    for token in args.split():
        if token.startswith("--type="):
            return token.split("=", 1)[1]
    return ""


def _ellipsis(text, limit):
    text = text.strip()
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


def processes_list():
    """Top processes by RSS.

    Sorted by memory and not by CPU, which is what rofi-kill does too: a
    runaway process is nearly always the one holding the memory, and CPU
    ordering churns between the moment the list is drawn and the moment you
    read it.
    """
    try:
        out = subprocess.run(
            ["ps", "-eo", "pid=,rss=,comm=,args=", "--sort=-rss"],
            capture_output=True, text=True, timeout=6)
    except (OSError, subprocess.SubprocessError):
        return {"title": "Kill process", "items": []}

    owners = _window_owners()
    items = []
    own = os.getpid()
    for line in out.stdout.splitlines()[:40]:
        parts = line.split(None, 3)
        if len(parts) < 3:
            continue
        pid, rss, comm = parts[0], parts[1], parts[2]
        args = parts[3] if len(parts) > 3 else ""
        try:
            pid_i, rss_i = int(pid), int(rss)
        except ValueError:
            continue
        if pid_i == own:
            continue

        megabytes = rss_i // 1024
        window = _owning_window(pid_i, owners)

        if window is None:
            # Nothing in the ancestry has a window: a daemon or a build. The
            # command line is the only identifying thing there is.
            label = "%d MB  ·  %s" % (megabytes, comm)
            detail = _ellipsis(args or comm, 150)
        else:
            title, cls, workspace, hops = window
            role = _helper_role(args)
            if hops == 0:
                label = "%d MB  ·  %s — %s" % (megabytes, comm, _ellipsis(title, 46))
                detail = "window: %s  ·  %s  ·  workspace %s" % (title, cls or "?", workspace)
            else:
                # The helper case, and the one this join exists for. Naming
                # the role as well as the window is what separates the four
                # renderers of one browser from its gpu process.
                label = "%d MB  ·  %s%s — %s" % (
                    megabytes,
                    comm,
                    " (%s)" % role if role else "",
                    _ellipsis(title, 42))
                detail = "%s for: %s  ·  %s  ·  workspace %s" % (
                    role or "helper", title, cls or "?", workspace)

        items.append({
            "id": str(pid_i),
            "label": label,
            "detail": detail,
        })
    return {"title": "Kill process", "items": items}


def processes_run(item_id):
    # SIGTERM, never SIGKILL. This list is reached by a keypress from a
    # picker; SIGKILL from a fuzzy-matched row is how you lose an editor's
    # unsaved buffer to a typo. Anything that ignores TERM is a job for a
    # deliberate `kill -9`, not for a menu.
    os.kill(int(item_id), signal.SIGTERM)


# ------------------------------------------------------------- workspaces --

def workspaces_list():
    items = []
    for workspace in _hypr("workspaces"):
        wid = workspace.get("id")
        if wid is None or wid < 0:
            continue
        items.append({
            "id": str(wid),
            "label": str(workspace.get("name", wid)),
            "detail": "%d window%s" % (workspace.get("windows", 0),
                                       "" if workspace.get("windows", 0) == 1 else "s"),
        })
    items.sort(key=lambda row: int(row["id"]))
    return {"title": "Go to workspace", "items": items}


def workspaces_run(item_id):
    subprocess.run(["hyprctl", "dispatch", "workspace", item_id],
                   capture_output=True, timeout=4)


MENUS = {
    "windows": (windows_list, windows_run),
    "processes": (processes_list, processes_run),
    "workspaces": (workspaces_list, workspaces_run),
}


def main(argv):
    if len(argv) >= 3 and argv[1] == "--list":
        entry = MENUS.get(argv[2])
        if entry is None:
            json.dump({"title": "", "items": [], "error": "unknown menu %s" % argv[2]},
                      sys.stdout)
        else:
            json.dump(entry[0](), sys.stdout)
        sys.stdout.write("\n")
        return 0

    if len(argv) >= 4 and argv[1] == "--run":
        entry = MENUS.get(argv[2])
        if entry is None:
            json.dump({"ok": False, "error": "unknown menu %s" % argv[2]}, sys.stdout)
            sys.stdout.write("\n")
            return 1
        try:
            entry[1](argv[3])
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            json.dump({"ok": False, "error": str(error)}, sys.stdout)
            sys.stdout.write("\n")
            return 1
        json.dump({"ok": True}, sys.stdout)
        sys.stdout.write("\n")
        return 0

    sys.stderr.write("usage: island-picker.py --list <menu> | --run <menu> <id>\n"
                     "menus: %s\n" % ", ".join(sorted(MENUS)))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
