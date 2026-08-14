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
This paragraph used to name rofi_anki (373 lines) and rofi_ilovepdf (1267)
together, on one argument: each is a LINEAR WIZARD over an external service
where every step's validity depends on the answers before it, so porting
either would mean "this file growing a second copy of each script's control
flow, with the original left in place as the one that still works".

**Half of that is now done, and the argument was wrong in a specific and
useful way.** A linear wizard is not the obstacle — a page stack IS a linear
wizard, and this file already runs three of them. The obstacle named was the
DUPLICATION, and duplication is avoidable: rofi_anki's eight prompts are 30
of its 373 lines and the other 343 are card logic that does not care which
window asked. So the `anki` menu below asks the eight questions and hands
the answers to `rofi_anki --answers FILE`. There is still exactly one copy
of the card logic, and the qtile session's rofi path is its default.

rofi_ilovepdf stays, and for a reason this paragraph never gave: it is a
file manager with multi-select, and the protocol below carries one id per
page. See the note above `MENUS`.

CORRECTION, and it is worth writing down because it was said three times in
one session and acted on twice: the claim "the island has no text-entry
field" is FALSE. There are five TextInputs in the tree — the cheatsheet
search, the application launcher search, two Wi-Fi password fields and one in
the expanded player. The settings panel's lack of a string editor is a
property of that panel, not of the shell, and the rofi port was scoped
smaller than it needed to be on the strength of it. The prompt mode added in
this file's second pass is the correction acted on.

THE PROTOCOL
------------
    island-picker.py --list <menu>            -> <page>
    island-picker.py --run <menu> <id> [text] -> {"ok":true}
                                              -> {"ok":true,"page":<page>}

A <page> is

    {"title": str,
     "mode":  "list" | "prompt" | "message",   (default "list")
     "items": [{"id":…, "label":…, "detail":…, "icon":…}],
     "note":  str,          prose above the list / under the prompt
     "prompt": str,         prompt mode: the placeholder
     "value": str,          prompt mode: the prefill
     "secret": bool,        prompt mode: mask the echo
     "submit": str,         prompt mode: the id that comes back with the text
     "menu":  str,          re-target the panel at another menu (see `hub`)
     "stack": "push"|"replace"|"root"}         default "push"

An item is {id, label, detail}. The panel never sees a command: it sends the
`id` back and this file decides what that means. That is deliberate — a panel
that executes strings handed to it by a script is a panel that executes
whatever anything can write into that script's output.

WHY --run CAN ANSWER WITH A PAGE, AND WHY THAT IS THE WHOLE UNLOCK
------------------------------------------------------------------
The original version of this file said, in as many words, that the menus
which PROMPT — rofi_pass, dm-recordV2, dm-spellcheck, the translator — could
not be ported because "a one-shot list is the wrong primitive for a
conversation". The premise was right and the conclusion was wrong. A
conversation is a sequence of one-shot pages, and the only thing missing was
a way for the script to say "here is the next one".

That is all `{"ok":true,"page":…}` is. The panel keeps a STACK of pages and
knows nothing about what any of them mean; Escape closes, Backspace on an
empty query pops. The script stays a pure function of (menu, id, text) —
there is still no session, no daemon and no state held in the panel.

Where a step genuinely needs to remember something across invocations (the
spell-checker's working text, which is edited fix by fix) it is written to a
file under $XDG_RUNTIME_DIR by THIS script, never carried in the panel. An id
is still opaque to the panel either way.
"""

import html
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request


RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp/island-picker-%d" % os.getuid()
HOME = os.path.expanduser("~")


def _page(title, items=None, **extra):
    """A page, with the empty keys left out.

    Omitting empties rather than sending nulls is not cosmetic: the panel
    reads `page.mode || "list"` and `page.note || ""`, and a JSON null would
    satisfy neither the `||` nor a `!== undefined` test written later.
    """
    page = {"title": title, "items": list(items or [])}
    for key, value in extra.items():
        if value not in (None, "", False):
            page[key] = value
    return page


def _prompt(title, submit, prompt="", value="", note="", secret=False, **extra):
    return _page(title, [], mode="prompt", submit=submit, prompt=prompt,
                 value=value, note=note, secret=secret, **extra)


def _message(title, note, **extra):
    return _page(title, [], mode="message", note=note, **extra)


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


# ------------------------------------------------------------- terminal --
#
#  dmscripts' config sets DMTERM="alacritty -e", and dm-man uses it to open
#  the page it picked. Both terminals are installed here, but the Hyprland
#  session's terminal is kitty — it is what $mod Return opens and what every
#  scratchpad rule in rules.conf matches on. Opening a manpage in the OTHER
#  terminal would give it none of the session's window rules and none of its
#  theming, so kitty is preferred and alacritty is the fallback, which is
#  also what DMTERM would have given.

def _terminal():
    for candidate in ("kitty", "alacritty", "foot", "xterm"):
        if shutil.which(candidate):
            return candidate
    return ""


def _spawn(argv):
    """Detach a GUI process from this script.

    start_new_session, because this script is run by the island's picker
    panel and exits the moment --run returns. A child in the same process
    group is a child that dies with it, which for `okular somefile.pdf`
    means the viewer flashes open and vanishes.
    """
    subprocess.Popen(argv, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _notify(title, body, *extra):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", *extra, title, body],
                       capture_output=True, timeout=4)


ISLAND_FORK = os.path.join(HOME, ".config", "quickshell", "tide-island-fork")


def _island_recording(active, pid=0):
    """Tell the island a recording started or stopped.

    ---- WHY THE ISLAND HAS TO BE TOLD ----

    It cannot find out by itself. The packaged backend detects a recording two
    ways -- a dbus-monitor watch on the xdg-desktop-portal ScreenCast session,
    and a pw-mon PipeWire watch -- and wf-recorder uses wlr-screencopy
    DIRECTLY, so it announces itself on neither. Measured: wf-recorder capturing
    eDP-1 for four seconds changed nothing in the resting capsule.

    This function is the whole reason the red dot can exist for the recorder
    this desktop actually uses. The pid matters as much as the flag: the island
    watchdogs it with `kill -0`, so a recorder killed from outside clears the
    dot instead of leaving it lit forever.

    Deliberately best-effort. A failure here must never take the recording down
    with it -- `qs ipc call` also EXITS 0 when it finds nothing, which is why
    this cannot be verified from the return code anyway.
    """
    if not shutil.which("qs"):
        return
    args = ["qs", "-p", ISLAND_FORK, "ipc", "call", "recording",
            "start" if active else "stop"]
    if active:
        args.append(str(pid))
    try:
        subprocess.run(args, capture_output=True, timeout=4)
    except (OSError, subprocess.SubprocessError):
        pass


# -------------------------------------------------------------- documents --
#
#  dm-documents: `find $HOME -maxdepth 4 -iname "*.pdf"`, then open the pick
#  in $PDF_VIEWER (okular here).
#
#  The original abbreviates the path for display — Documents->Dcs,
#  Downloads->Dwn — and then REVERSES the substitution to rebuild the path it
#  opens. That round trip is why it cannot handle a PDF in a directory that
#  happens to contain the string "Pic", and it exists only because a rofi row
#  is one line of text and the path had to survive in it. Here the row
#  carries an opaque `id`, so the full path is passed through untouched and
#  the label is free to be just the filename.

def documents_list():
    home = os.path.expanduser("~")
    try:
        out = subprocess.run(
            ["find", home, "-maxdepth", "4", "-iname", "*.pdf"],
            capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return {"title": "Open document", "items": []}

    items = []
    for path in out.stdout.splitlines():
        path = path.strip()
        if not path:
            continue
        name = os.path.basename(path)
        if name.lower().endswith(".pdf"):
            name = name[:-4]
        parent = os.path.dirname(path)
        if parent.startswith(home):
            parent = "~" + parent[len(home):]
        items.append({"id": path, "label": name, "detail": parent})
    items.sort(key=lambda row: row["label"].lower())
    return {"title": "Open document", "items": items}


def documents_run(item_id):
    viewer = "okular" if shutil.which("okular") else "xdg-open"
    _spawn([viewer, item_id])


# -------------------------------------------------------------- manpages --
#
#  dm-man offers three rows — "Search manpages", "Random manpage", "Quit" —
#  and the first opens a SECOND rofi holding every page on the system.
#
#  That middle step is dropped, and deliberately: it exists because rofi's
#  list is not searchable until you have chosen to search it. This panel has
#  a filter field that is always live, so "Search manpages" would be a row
#  whose only effect is to show the list this menu already is. "Quit" goes
#  for the same reason — Escape closes the panel.
#
#  Random is not ported. It is one shuf away in a terminal and it is not a
#  thing anyone reaches for through a keybinding.

def man_list():
    try:
        out = subprocess.run(["man", "-k", "."],
                             capture_output=True, text=True, timeout=25)
    except (OSError, subprocess.SubprocessError):
        return {"title": "Manpage", "items": []}

    items = []
    for line in out.stdout.splitlines():
        # `name (section)  - description`. rsplit on " - " because a
        # description may itself contain " - " and the FIRST one is the
        # separator; split on "(" for the section because a page name cannot
        # contain a bracket but a description frequently can.
        head, _, description = line.partition(" - ")
        head = head.strip()
        if not head:
            continue
        name = head.split("(")[0].strip()
        if not name:
            continue
        items.append({
            "id": name,
            "label": head,
            "detail": description.strip(),
        })
    return {"title": "Manpage", "items": items}


def man_run(item_id):
    terminal = _terminal()
    if not terminal:
        return
    _spawn([terminal, "-e", "man", item_id] if terminal != "kitty"
           else [terminal, "man", item_id])


# ----------------------------------------------------------------- notes --
#
#  dm-note's menu is Copy / New / Delete / Quit. The first pass of this port
#  had only COPY, on the stated grounds that New needs a text field and
#  Delete needs a confirmation. Both are now here, because both are exactly
#  the shape the prompt mode and the page stack were built for.
#
#  WHERE THIS DELIBERATELY DIFFERS FROM dm-note
#  --------------------------------------------
#  dm-note opens on a four-row Copy/New/Delete/Quit menu and only THEN shows
#  the notes. Here the notes are the first thing on screen and New/Delete are
#  rows among them, because the chord is pressed to copy a note ninety-odd
#  percent of the time and a menu whose common path costs two keystrokes has
#  put its rarest actions first.
#
#  The other difference is the delete confirmation, which dm-note does not
#  have at all: it deletes on selection. A fuzzy-matched row that destroys
#  data without asking is the same failure the `processes` menu refuses
#  SIGKILL for, and the file is a plain line list with no undo.

NOTE_FILE = os.path.expanduser("~/.config/dmscripts/dmnote")


def _notes_read():
    try:
        with open(NOTE_FILE) as handle:
            return [line.rstrip("\n") for line in handle if line.strip()]
    except OSError:
        return []


def _notes_write(lines):
    os.makedirs(os.path.dirname(NOTE_FILE), exist_ok=True)
    with open(NOTE_FILE, "w") as handle:
        for line in lines:
            handle.write(line + "\n")


def notes_list():
    items = [{"id": "new", "label": "New note…",
              "detail": "type it, Enter saves"}]
    notes = _notes_read()
    for line in notes:
        items.append({"id": "copy:" + line, "label": line, "detail": ""})
    if notes:
        items.append({"id": "delmenu", "label": "Delete a note…",
                      "detail": "%d note%s" % (len(notes),
                                               "" if len(notes) == 1 else "s")})
    return _page("Notes", items)


def notes_run(item_id, text=""):
    kind, rest = _split(item_id)

    if kind == "copy":
        _copy(rest)
        _notify("Note copied", rest)
        return None

    if item_id == "new":
        return _prompt("New note", "save", prompt="the note",
                       note="One line. Saved to ~/.config/dmscripts/dmnote, "
                            "which is the same file dm-note reads.")

    if item_id == "save":
        note = text.strip()
        if not note:
            raise ValueError("nothing to save")
        notes = _notes_read()
        # dm-note's duplicate guard, ported without its sed dance: it
        # escapes [ and ] to stop grep reading the note as a regex, which is
        # a problem only because it is testing membership with a pattern
        # matcher. A list and `in` has no such problem and no such bug.
        if note in notes:
            raise ValueError("that note is already there")
        _notes_write(notes + [note])
        _notify("Note created", note)
        return _page("Notes", notes_list()["items"], stack="root")

    if item_id == "delmenu":
        return _page("Delete which?", [
            {"id": "del:" + line, "label": line, "detail": ""}
            for line in _notes_read()])

    if kind == "del":
        return _page("Delete this note?", [
            {"id": "delyes:" + rest, "label": "Delete", "detail": rest},
        ], note=rest)

    if kind == "delyes":
        notes = _notes_read()
        if rest not in notes:
            raise ValueError("that note is gone already")
        _notes_write([line for line in notes if line != rest])
        _notify("Note deleted", rest)
        return _page("Notes", notes_list()["items"], stack="root")

    raise ValueError("unknown notes step %s" % item_id)


# ------------------------------------------------------------ brightness --
#
#  rofi_light's exact ladder — 100 80 60 40 20 10 5 — and its exact action,
#  `light -S <n>` followed by a dunst-stacked notification. The stack tag is
#  copied verbatim so repeated changes replace one another in the tray
#  rather than piling up, which is the behaviour the original was tuned for.

BRIGHTNESS_STEPS = [100, 80, 60, 40, 20, 10, 5]


def brightness_list():
    current = -1
    if shutil.which("light"):
        try:
            out = subprocess.run(["light", "-G"], capture_output=True,
                                 text=True, timeout=4)
            current = int(float(out.stdout.strip() or "-1"))
        except (OSError, ValueError, subprocess.SubprocessError):
            current = -1

    items = []
    for step in BRIGHTNESS_STEPS:
        items.append({
            "id": str(step),
            "label": "%d%%" % step,
            # The current level marks the row it IS, and says nothing on the
            # others. rofi_light showed it once, as a -mesg above the list;
            # repeating "current: 47%" down every row of a list of levels is
            # the one place it cannot be read as "this row".
            "detail": "current" if current >= 0 and step == current else "",
        })
    # rofi_light's -mesg, with its capital C.
    return _page("Brightness", items,
                 note="Current: %d%%" % current if current >= 0 else "")


def brightness_run(item_id):
    if not shutil.which("light"):
        return
    subprocess.run(["light", "-S", item_id], capture_output=True, timeout=6)
    _notify("Brightness", "%s%%" % item_id,
            "-a", "Brightness",
            "-h", "string:x-dunst-stack-tag:brightness",
            "-h", "int:value:%s" % item_id,
            "-i", "display-brightness-medium-symbolic")


# ------------------------------------------------------------- clipboard --
#
#  copyq_rofi, ported. The list comes from the same `copyq eval` walk over
#  the &clipboard tab, with the same classifying glyphs (URL, path, shell
#  command, multi-line) and the same de-duplication.
#
#  ---- THE ONE BEHAVIOUR THAT COULD NOT COME ACROSS ----
#
#  The original ends with:
#
#      copyq select($idx)  ;  xdotool key --clearmodifiers ctrl+v
#
#  xdotool is X11. It talks XTEST to an X server, and under Wayland there is
#  no X server to talk to and no way for an ordinary client to synthesise a
#  keystroke into another client. The Wayland equivalent is wtype, and wtype
#  is specifically the wrong tool here: it creates and destroys a virtual
#  keyboard, and doing that while a layer-shell panel holds the keyboard
#  closes the panel — measured on this shell's own connectivity panel, and
#  already recorded in submaps.conf for the pickers.
#
#  So this port stops at `select`, which is what actually puts the entry on
#  the clipboard, and the paste is left to the user's own Ctrl+V. That is a
#  real difference from the rofi version and not an oversight: one keystroke
#  instead of zero, in exchange for the panel not fighting the compositor.
#
#  MAX is 40 rather than the original's 15. That default is a rofi
#  constraint — an unfiltered list you scroll with arrow keys stops being
#  useful somewhere around a screenful — and this panel has a live filter,
#  so the ceiling can be the useful one instead of the legible one.

CLIPBOARD_MAX = 40

# Thumbnails live under the runtime dir, like copyq_rofi's. Wiped on every
# --list: copyq indices are positional, so item 3 is a different picture
# after anything new is copied, and a stale 3.png is a preview of whatever
# used to be there.
CLIPBOARD_THUMBS = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp",
    "island-picker-thumbs")

_CLIPBOARD_JS = r"""
var TAB = "&clipboard";
var MAX = %d;
var THUMBS = "%s";
tab(TAB);
var n = Math.min(count(), MAX);
var seen = {};
for (var i = 0; i < n; i++) {
  var d = getitem(i);
  var keys = Object.keys(d);
  var pinned = false;
  for (var j = 0; j < keys.length; j++) {
    if (keys[j] == "application/x-copyq-item-pinned") pinned = true;
  }
  var label = "", dedupeKey = "", kind = "text", icon = "";

  // Ask for the PNG rather than trusting the key list. Several items here
  // carry image bytes while advertising no image/* key at all, and those
  // are exactly the rows that used to render as a file signature in the
  // label. If read() hands back a real buffer, it is an image.
  var buf = read("image/png", i);
  var isImg = (buf && buf.size && buf.size() > 24);

  if (isImg) {
    icon = THUMBS + "/" + i + ".png";
    var f = new File(icon); f.open(); f.write(buf); f.close();
    // Dimensions are NOT parsed here. copyq_rofi does it with
    // buf.mid(16,8).toString() and charCodeAt, and that is wrong for any
    // image whose width or height has a byte above 127: toString() decodes
    // the buffer as text, so 0xAD does not survive as 173. Measured — a
    // 788x429 screenshot came back as 788x65533. The file is on disk by
    // this point, so python reads the IHDR from it instead.
    label = "image";
    kind = "image";
    dedupeKey = "img:" + buf.size();
  } else {
    var raw = str(d["text/plain"] || "");
    var t = raw.replace(/[\r\n\t]/g, " ").substring(0, 220);
    if (!t.length) { label = "<empty>"; dedupeKey = "empty:" + i; }
    else {
      if (/^https?:\/\//.test(raw)) kind = "url";
      else if (/^(\/|~\/|\.\/)/.test(raw)) kind = "path";
      else if (/^\s*(git|sudo|cd|ls|npm|pnpm|yarn|cargo|python|node|pip|systemctl|docker|make|curl|wget|ssh|rsync)\s/.test(raw)) kind = "command";
      else if (raw.indexOf("\n") >= 0) kind = "multiline";
      label = t; dedupeKey = "txt:" + raw;
    }
  }
  if (seen[dedupeKey]) continue;
  seen[dedupeKey] = true;
  print(i + "\t" + (pinned ? "P" : "-") + "\t" + kind + "\t" + icon + "\t" + label + "\n");
}
""" % (CLIPBOARD_MAX, CLIPBOARD_THUMBS)

# The classifier's output, spelled for a panel instead of for a Pango
# markup row. The original prefixed a Nerd Font glyph; a word in the detail
# column survives a missing font, which a private-use codepoint does not.
_CLIPBOARD_KINDS = {
    "url": "link",
    "path": "path",
    "command": "shell command",
    "multiline": "multi-line",
    "image": "image",
    "text": "",
}


def _png_size(path):
    """(width, height) from a PNG's IHDR, or None.

    Bytes 16..24 are two big-endian uint32. Read as BYTES, which is the
    whole point — see the note in the copyq script about why doing this in
    JS produced a height of 65533 for a 429 px image.
    """
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
        if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        return (int.from_bytes(head[16:20], "big"),
                int.from_bytes(head[20:24], "big"))
    except OSError:
        return None


def _clipboard_label(text):
    """A row label that is safe to draw.

    copyq items are not tidily typed: several entries here carry PNG bytes
    in `text/plain` while exposing no `image/*` key at all, so the upstream
    `isImg` test misses them and the raw file signature lands in the label.
    Rendered, that is a row of replacement glyphs and stray control
    characters wide enough to push the panel around.

    Control characters are stripped rather than escaped, and a row that is
    mostly unprintable after that is reported as what it is instead of being
    shown as damaged text.
    """
    if text.startswith("\x89PNG") or text.startswith("\xff\xd8\xff"):
        return "binary data"
    cleaned = "".join(ch for ch in text if ch.isprintable() or ch == " ")
    stripped = cleaned.strip()
    if not stripped:
        return "<empty>"
    # More than a fifth of the characters lost to the filter means this was
    # never text; a normal string loses none.
    if len(cleaned) < len(text) * 0.8:
        return "binary data"
    return stripped


def clipboard_list():
    if not shutil.which("copyq"):
        return {"title": "Clipboard", "items": []}
    try:
        os.makedirs(CLIPBOARD_THUMBS, exist_ok=True)
        for stale in os.listdir(CLIPBOARD_THUMBS):
            if stale.endswith(".png"):
                os.unlink(os.path.join(CLIPBOARD_THUMBS, stale))
    except OSError:
        pass

    try:
        out = subprocess.run(["copyq", "eval", "-"], input=_CLIPBOARD_JS,
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return {"title": "Clipboard", "items": []}

    items = []
    for line in out.stdout.splitlines():
        parts = line.split("\t", 4)
        if len(parts) < 5:
            continue
        index, pin, kind, icon, label = parts
        if not index.strip().isdigit():
            continue
        detail = _CLIPBOARD_KINDS.get(kind, "")
        if pin == "P":
            detail = ("pinned  ·  " + detail) if detail else "pinned"
        safe = _clipboard_label(label)
        # Overrides the classifier rather than filling a gap in it. The JS
        # calls PNG bytes "multi-line" because they contain newlines, which
        # is true and useless; once the label has been recognised as binary
        # the kind it was given is simply wrong.
        if safe == "binary data":
            detail = "binary"
        row = {
            "id": index.strip(),
            "label": safe,
            "detail": detail,
        }
        # Only ever set when the file is actually on disk. A row carrying a
        # path that does not resolve gives QML a broken Image and a warning
        # per repaint.
        if icon and os.path.isfile(icon):
            row["icon"] = icon
            size = _png_size(icon)
            if size:
                row["label"] = "image %d\u00d7%d" % size
        items.append(row)
    return {"title": "Clipboard", "items": items}


def clipboard_run(item_id):
    if not shutil.which("copyq"):
        return
    # select() both raises the entry to the top of the tab and puts it on the
    # clipboard, which is the whole of what this needs to do. See the header
    # for why the xdotool paste that followed it upstream is not here.
    subprocess.run(["copyq", "eval", "-"],
                   input='tab("&clipboard"); select(%s);' % int(item_id),
                   capture_output=True, text=True, timeout=6)


# ================================================================ helpers ==
#
#  Shared by everything below the original five menus.

def _spawn_sh(script):
    """Run a shell fragment detached from this process.

    Several ports below need something to happen AFTER the panel has gone:
    slurp cannot draw its rectangle while a layer-shell surface holds the
    keyboard, and rbw's pinentry cannot take a passphrase for the same
    reason. The panel closes when --run returns, so anything that must
    outlive that has to be its own session — hence start_new_session, the
    same reasoning as _spawn's.
    """
    subprocess.Popen(["sh", "-c", script], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _copy(text):
    """Put text on the Wayland clipboard.

    wl-copy and not xclip throughout this file: the qtile session's scripts
    keep xclip because they run on X11, and an xclip that "works" under
    Hyprland is writing to the XWayland selection, which nothing native
    reads. Measured elsewhere in this port: an x11grab of the Hyprland
    session is a black frame with a cursor on it, and the selection story
    is the same story.
    """
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--", text], capture_output=True, timeout=4)
        return True
    return False


SELECTION_MAX = 200


def _selection():
    """The PRIMARY selection, as a prefill. Empty when there is none.

    Collapsed to one line and capped, which the rofi originals did not need
    to do and this does. Measured while testing: the primary selection on
    this session was a 4 KB multi-line briefing document, and a prompt field
    is a single-line TextInput — the prefill would have been four kilobytes
    of text scrolled to its end, with the cursor somewhere past the horizon.
    A prefill that has to be cleared before it can be used is worse than an
    empty field, so anything over SELECTION_MAX is treated as "that was not
    a word you meant to check".
    """
    if not shutil.which("wl-paste"):
        return ""
    try:
        out = subprocess.run(["wl-paste", "-p", "-n"],
                             capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return ""
    if out.returncode != 0:
        return ""
    text = " ".join(out.stdout.split())
    return text if len(text) <= SELECTION_MAX else ""


def _stamp():
    return time.strftime("%y%m%d-%H%M-%S")


def _http_json(url, data=None, headers=None, timeout=15):
    request = urllib.request.Request(
        url,
        data=data,
        headers=dict({"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"},
                     **(headers or {})))
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def _state_path(name):
    return os.path.join(RUNTIME, "island-picker-%s.json" % name)


def _state_write(name, value):
    try:
        with open(_state_path(name), "w") as handle:
            json.dump(value, handle)
    except OSError:
        pass


def _state_read(name):
    try:
        with open(_state_path(name)) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _split(item_id, count=2):
    """`kind:rest` → (kind, rest). rest may itself contain colons.

    Every multi-step menu below encodes its step in the id, because the id is
    the ONLY thing that crosses back from the panel and the panel is not
    allowed to hold state on the script's behalf.
    """
    parts = item_id.split(":", count - 1)
    while len(parts) < count:
        parts.append("")
    return parts


# ------------------------------------------------------------ screenshot --
#
#  dm-satty, rewritten for Wayland rather than wrapped.
#
#  The wrap was never possible: dm-satty is maim + xdotool + xrandr + xclip,
#  four X11 tools, and it asks xrandr for the monitor list. Under Hyprland
#  every one of those talks to XWayland, which is not the compositor. The
#  measurement that settles it is in the `record` note below — an X11 grab of
#  this session is a black frame — and a screenshot tool that silently
#  produces black is worse than one that is missing.
#
#  So: grim for the capture, slurp for the rectangle, hyprctl for the active
#  window's geometry, wl-copy for the clipboard. satty is unchanged; it is
#  Wayland-native already and dm-satty's --output-filename fix is kept.
#
#  WHAT WAS DROPPED, AND WHY IT CAME BACK
#  --------------------------------------
#  This port originally dropped two of dm-satty's steps, and the arguments
#  for dropping them were about the SHUTTER. Both were beside the point.
#
#  * The delay prompt (0-5 s) was dropped because the island's panel is gone
#    before grim runs anyway — see _spawn_sh's 0.4 s — so the delay had no
#    window left to hide. True, and irrelevant: a delay is also how you
#    screenshot a menu you have to open by hand, a hover state, or anything
#    that dies the moment it loses focus. And the deciding argument is not
#    even that one. Three keystrokes in a fixed order are a THING THE HANDS
#    KNOW; removing the middle one does not make the menu shorter, it makes
#    every remaining keystroke land on the wrong row. Restored, 0-5, same
#    prompt text.
#  * The per-monitor rows were dropped because this machine has one monitor.
#    Restored CONDITIONALLY: they appear only when the compositor reports
#    more than one output, which is dm-satty's behaviour on a single-head
#    machine as well (xrandr lists one, the row is the same answer as
#    "Fullscreen"). `grim -o <name>` is the capture.
#
#  THE LABELS ARE dm-satty'S, VERBATIM
#  -----------------------------------
#  "Fullscreen" / "Active window" / "Selected region" / "Fullscreen (edit
#  with satty)" / "Selected region (edit with satty)", in that order, then
#  "Delay (in seconds):" 0-5, then "File" / "Clipboard" / "Both". The page
#  titles are dm-satty's rofi PROMPTS, colon and all, for the same reason.
#  Do not improve this wording. It is an interface to a person's hands, and
#  the first port rewrote every string in it — "Save to file" for "File",
#  "Copy to clipboard" for "Clipboard", "Edit in satty" as a fourth
#  destination rather than a mode, and the area order reshuffled so that
#  "Active window" and "Selected region" swapped places.

SHOT_DIR = os.path.join(HOME, "Screenshots")
SHOT_PREFIX = "screenshot"

_SHOT_AREAS = {
    "full": "Fullscreen",
    "region": "Selected region",
    "window": "Active window",
}

#  dm-satty prompts for the delay with `seq 0 5`, and treats anything
#  non-numeric as none. There is no non-numeric row here, so 0 is the none.
_SHOT_DELAYS = range(0, 6)


def _shot_monitors():
    """Extra area rows, one per output, or [] on a single-head machine.

    dm-satty's rows are `xrandr --listactivemonitors`; these are the
    compositor's own, which is the only list that is true under Hyprland.
    """
    monitors = _hypr("monitors")
    if not isinstance(monitors, list) or len(monitors) < 2:
        return []
    rows = []
    for monitor in monitors:
        name = monitor.get("name") if isinstance(monitor, dict) else None
        if not name:
            continue
        rows.append({
            "id": "area:mon-%s:" % name,
            "label": name,
            "detail": "%sx%s at %s,%s" % (
                monitor.get("width", "?"), monitor.get("height", "?"),
                monitor.get("x", "?"), monitor.get("y", "?")),
        })
    return rows


def screenshot_list():
    active = _hypr("activewindow")
    title = (active or {}).get("title", "") if isinstance(active, dict) else ""
    satty = "annotate, then save" if shutil.which("satty") \
        else "satty is not installed"
    return _page("Take screenshot of:", [
        {"id": "area:full:", "label": "Fullscreen",
         "detail": "grim, the whole output"},
        {"id": "area:window:", "label": "Active window",
         "detail": _ellipsis(title, 80) if title else "nothing focused"},
        {"id": "area:region:", "label": "Selected region",
         "detail": "slurp draws the rectangle once this panel is gone"},
        {"id": "area:full:satty", "label": "Fullscreen (edit with satty)",
         "detail": satty},
        {"id": "area:region:satty",
         "label": "Selected region (edit with satty)", "detail": satty},
    ] + _shot_monitors())


def _shot_geometry(area):
    """The -g argument for grim, or "" for a full-output grab.

    The active window's box is read HERE, at the moment the AREA IS CHOSEN,
    and not in the spawned shell. By the time the shell runs the panel has
    closed and the focus has moved back — `hyprctl activewindow` would then
    answer with whatever the compositor refocused, which is usually the same
    window and occasionally is not. With the delay step restored the gap is
    wider still: up to five seconds, during which the user may well have
    clicked somewhere. Reading it early is what makes "Active window" mean
    the window that was active when they said "Active window".
    """
    if area != "window":
        return ""
    active = _hypr("activewindow")
    if not isinstance(active, dict):
        return ""
    at, size = active.get("at"), active.get("size")
    if not (isinstance(at, list) and isinstance(size, list)):
        return ""
    return "%d,%d %dx%d" % (at[0], at[1], size[0], size[1])


def _shot_capture(area, geometry):
    """The shell fragment that puts one PNG on stdout or in a named file.

    Returns (prefix, capture): `prefix` runs BEFORE the delay, `capture` is
    the grim invocation. They are separate because of where the delay goes
    for a region: dm-satty ran `maim -s --delay=N`, and maim takes the
    selection FIRST and delays after it, so the rectangle is drawn
    immediately and the shutter is what waits. A `sleep N; slurp` would
    invert that and make the delay useless — you would be dragging a
    rectangle over the state you were trying to give yourself time to set up.
    """
    if area == "region":
        # A cancelled slurp exits non-zero and must take the whole thing
        # down quietly — a cancelled selection is a "no thanks", not a
        # failure to report.
        return 'g=$(slurp) || exit 0; ', 'grim -g "$g"'
    if area.startswith("mon-"):
        return "", "grim -o %s" % shlex.quote(area[4:])
    if geometry:
        return "", "grim -g %s" % shlex.quote(geometry)
    return "", "grim"


def screenshot_run(item_id):
    """The three dm-satty steps, in dm-satty's order.

    `area:<area>:<edit>` → the delay page
    `delay:<area>:<edit>:<n>` → the destination page, or straight to satty
    `shot:<area>:<edit>:<n>:<dest>` → the capture

    Every step carries the whole answer forward in its id, because the id is
    the only thing that crosses back from the panel.
    """
    kind, rest = _split(item_id)

    if kind == "area":
        area, edit = _split(rest)
        # The active window's box has to be resolved NOW — see
        # _shot_geometry. It rides the id from here on.
        geometry = _shot_geometry(area).replace(":", "")
        return _page("Delay (in seconds):", [
            {"id": "delay:%s:%s:%s:%d" % (area, edit, geometry, n),
             "label": str(n),
             "detail": "no delay" if n == 0
                       else "shutter fires %d s later" % n}
            for n in _SHOT_DELAYS
        ])

    if kind == "delay":
        area, edit, geometry, delay = _split(rest, 4)
        carry = "%s:%s:%s:%s" % (area, edit, geometry, delay)
        # dm-satty prompts for the delay BEFORE branching on satty, and the
        # satty branch never reaches the Destination prompt — its
        # destination is the editor. Same shape here.
        if edit == "satty":
            return _shot_fire(area, geometry, delay, "satty")
        return _page("Destination:", [
            {"id": "shot:%s:file" % carry, "label": "File",
             "detail": SHOT_DIR},
            {"id": "shot:%s:clipboard" % carry, "label": "Clipboard",
             "detail": "wl-copy -t image/png"},
            {"id": "shot:%s:both" % carry, "label": "Both",
             "detail": "file and clipboard"},
        ])

    if kind != "shot":
        raise ValueError("unknown screenshot step %s" % item_id)

    area, edit, geometry, delay, dest = _split(rest, 5)
    return _shot_fire(area, geometry, delay, dest)


def _shot_fire(area, geometry, delay, dest):
    if dest == "satty" and not shutil.which("satty"):
        raise ValueError("satty is not installed")
    if not shutil.which("grim"):
        raise ValueError("grim is not installed")

    os.makedirs(SHOT_DIR, exist_ok=True)
    out = os.path.join(SHOT_DIR, "%s-%s%s-%s.png" % (
        SHOT_PREFIX, area, "-satty" if dest == "satty" else "", _stamp()))
    quoted_out = shlex.quote(out)

    # The region case is the reason this is a shell fragment and not an argv:
    # slurp has to run INSIDE the detached session, after the panel is gone,
    # and its output has to reach grim.
    prefix, capture = _shot_capture(area, geometry)

    if dest == "clipboard":
        body = "%s - | wl-copy -t image/png && notify-send 'Screenshot copied' 'on the clipboard'" % capture
    elif dest == "file":
        body = "%s %s && notify-send 'Screenshot saved' %s" % (
            capture, quoted_out, quoted_out)
    elif dest == "both":
        body = ("%s %s && wl-copy -t image/png < %s && "
                "notify-send 'Screenshot saved' %s") % (
            capture, quoted_out, quoted_out, quoted_out)
    elif dest == "satty":
        temp = shlex.quote(os.path.join(RUNTIME, "island-satty-%s.png" % _stamp()))
        # dm-satty's own comment records that every annotation it ever made
        # was discarded, because satty was started without --output-filename
        # and the script then moved the UNEDITED capture into place. The fix
        # is carried over rather than rediscovered.
        body = ("%s %s && satty --filename %s --output-filename %s; rm -f %s; "
                "[ -s %s ] && notify-send 'Screenshot saved' %s "
                "|| notify-send 'Screenshot discarded' 'satty closed without saving'") % (
            capture, temp, temp, quoted_out, temp, quoted_out, quoted_out)
    else:
        raise ValueError("unknown destination %s" % dest)

    # 0.4 s, not 0: slurp and the grab both have to happen after the layer
    # surface has released the keyboard and stopped being painted, or the
    # picker itself is in the screenshot. The chosen delay is added to it,
    # and lands AFTER `prefix` so that a region selection is drawn first —
    # see _shot_capture.
    try:
        wait = 0.4 + int(delay or 0)
    except ValueError:
        wait = 0.4
    _spawn_sh("%ssleep %s; %s" % (prefix, wait, body))
    return None


# ---------------------------------------------------------------- record --
#
#  dm-recordV2, and the one place in this port where the honest answer is
#  "most of this cannot work here".
#
#  THE MEASUREMENT
#  ---------------
#  dm-recordV2 captures with `ffmpeg -f x11grab -i $DISPLAY`. Run under this
#  Hyprland session and read back with PIL:
#
#      ffmpeg -f x11grab -video_size 1366x768 -i :0 -frames:v 1 out.png
#      -> 1366x768, every pixel (0,0,0) except a cursor at the top left
#
#  The XWayland root window is not a mirror of the Wayland output; it is an
#  empty root that XWayland's own clients are parented into. So screen,
#  area and GIF capture in dm-recordV2 are not "probably wrong under
#  Wayland", they produce a black video, and they have been doing so for
#  every recording made since the session moved.
#
#  WHAT THAT MEANS FOR THIS PORT
#  -----------------------------
#  The pieces that never touched X11 port straight across and are live:
#  audio (pulse) and both webcam modes (v4l2). Screen and region need a
#  Wayland capture tool — wf-recorder is the one this is written against —
#  and wf-recorder is NOT INSTALLED on this machine. Rather than hide those
#  rows, they are listed with "wf-recorder is not installed" in the detail
#  and refuse when run: a missing capability that is visible is a package
#  away, and one that is hidden is a bug report.
#
#  Neither screen path has therefore been exercised. Say so.
#
#  DROPPED: the GIF mode. Its value in dm-recordV2 is entirely the two-stage
#  capture-then-palettegen conversion (its own comment measures 29.6 MB
#  against 1.3 MB for the same six seconds), and that second stage cannot be
#  run at all without a first stage that works. Shipping an untestable
#  conversion pipeline is worse than saying the mode is gone.

RECORD_DIR = os.path.join(HOME, "Videos", "Recordings")
RECORD_PID = os.path.join(RUNTIME, "island-record.pid")

# dm-recordV2's numbers, carried over with its measurement. A GIF is captured
# to h264 first and converted on stop, never written straight out: encoding
# GIF live means every frame carries the default palette with no cross-frame
# optimisation. Measured there on a 6-second full-screen capture -- direct GIF
# 29.6 MB, capture-then-convert with a real palette 1.3 MB, same footage, 23x
# smaller for two seconds of conversion. palettegen also has to see the whole
# stream before it can emit a palette, so it cannot be part of the live
# pipeline at all: one pass buffers the entire recording and stalls.
GIF_FPS = 12
GIF_MAX_WIDTH = 900


def _gif_convert_command(source, output):
    """The second stage: h264 in, palette-optimised GIF out.

    Verbatim from dm-recordV2's convert_pending_gif, including
    stats_mode=diff and the bayer dither, because those are what buy the 23x
    and were chosen there against real footage.

    Returns a shell fragment: the conversion runs detached after the recorder
    has exited, and on failure the h264 is KEPT rather than the recording
    being lost to a bad convert.
    """
    # RAW string: the backslash before the comma is ffmpeg's own escape,
    # protecting min()'s argument separator from the filtergraph parser.
    # Written "\\," in a normal Python string it is an invalid escape that
    # works today and warns, and is scheduled to become an error.
    vf = (r"fps=%d,scale=min(iw\,%d):-2:flags=lanczos,split[s0][s1];"
          "[s0]palettegen=stats_mode=diff[p];"
          "[s1][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
          % (GIF_FPS, GIF_MAX_WIDTH))
    return (
        "if ffmpeg -nostdin -y -hide_banner -loglevel error -i %s "
        "-vf %s %s < /dev/null; then "
        "  notify-send 'GIF saved' \"$(du -h %s | cut -f1) — %s\"; rm -f %s; "
        "else "
        "  notify-send 'GIF conversion failed' 'capture kept at %s'; "
        "fi" % (
            shlex.quote(source), shlex.quote(vf), shlex.quote(output),
            shlex.quote(output), shlex.quote(os.path.basename(output)),
            shlex.quote(source), shlex.quote(source)))


def _record_active():
    """The live recording's pid, or 0. Clears a stale pidfile as it goes."""
    try:
        with open(RECORD_PID) as handle:
            pid = int(handle.read().strip())
    except (OSError, ValueError):
        return 0
    try:
        os.kill(pid, 0)
        return pid
    except OSError:
        try:
            os.unlink(RECORD_PID)
        except OSError:
            pass
        return 0


def _webcam_device():
    for index in range(0, 8):
        device = "/dev/video%d" % index
        if not os.path.exists(device):
            continue
        if shutil.which("v4l2-ctl"):
            probe = subprocess.run(["v4l2-ctl", "-d", device, "--all"],
                                   capture_output=True, text=True, timeout=6)
            if "Video Capture" not in probe.stdout:
                continue
        return device
    return ""


def record_list():
    pid = _record_active()
    if pid:
        target = _state_read("record") or {}
        return _page("Recording", [{
            "id": "stop",
            "label": "Stop recording",
            "detail": target.get("output", "pid %d" % pid),
        }], note="A recording is running. Everything else is hidden on "
                 "purpose: dm-recordV2 has the same one-way door, and a "
                 "second ffmpeg would overwrite the pidfile that stops the "
                 "first.")

    have_wf = bool(shutil.which("wf-recorder"))
    have_ff = bool(shutil.which("ffmpeg"))
    missing = "wf-recorder is not installed"
    camera = _webcam_device()
    gif_detail = ("capture h264, convert on stop — %d fps, max %d px wide"
                  % (GIF_FPS, GIF_MAX_WIDTH))
    if not have_wf:
        gif_detail = missing
    elif not have_ff:
        gif_detail = "ffmpeg is not installed (needed for the palette pass)"
    # dm-recordV2's rows, its wording, its order — and its mode 7 (GIF) is
    # BACK. The note above used to say GIF was dropped because "that second
    # stage cannot be run at all without a first stage that works", the first
    # stage being screen capture, which x11grab could not do under Hyprland.
    # wf-recorder is installed now, so the premise is gone and so is the
    # reason. Every other row is here too, including "Screen + Audio", which
    # the first port dropped without saying so — it is dm-recordV2's FIRST row
    # and the one the hand goes to.
    return _page("Select recording mode:", [
        {"id": "screen-audio", "label": "Screen + Audio (full display)",
         "detail": "wf-recorder --audio" if have_wf else missing},
        {"id": "screen", "label": "Screen Only (full display)",
         "detail": "wf-recorder, whole output" if have_wf else missing},
        {"id": "region", "label": "Screen Area (selection)",
         "detail": "wf-recorder + slurp" if have_wf else missing},
        {"id": "audio", "label": "Audio Only",
         "detail": "ffmpeg -f pulse, mp3"},
        {"id": "webcam-low", "label": "Webcam (low-res 640x480)",
         "detail": camera or "no capture device under /dev/video*"},
        {"id": "webcam-hd", "label": "Webcam (HD 1920x1080)",
         "detail": camera or "no capture device under /dev/video*"},
        {"id": "gif", "label": "Screen → GIF (full display)",
         "detail": gif_detail},
        {"id": "gif-region", "label": "Screen Area → GIF (selection)",
         "detail": gif_detail},
    ])


def record_run(item_id):
    if item_id == "stop":
        pid = _record_active()
        if not pid:
            raise ValueError("no active recording")
        # SIGINT and not SIGTERM. wf-recorder finalises the container on
        # INT; ffmpeg does so on either, and dm-recordV2's own note is that
        # a kill before the trailer is written truncates the file — three of
        # its eight recordings ended that way. Waiting is the fix, so wait.
        os.kill(pid, signal.SIGINT)
        for _ in range(300):
            try:
                os.kill(pid, 0)
            except OSError:
                break
            time.sleep(0.2)
        try:
            os.unlink(RECORD_PID)
        except OSError:
            pass
        target = _state_read("record") or {}
        # The island first: the dot is the thing the eye is on, and a
        # notification that lands before the indicator clears reads as the
        # recording still running.
        _island_recording(False)

        # A GIF is only half finished when the recorder exits. The palette
        # pass runs DETACHED and says so itself, because it takes seconds on
        # a long capture and blocking here would hold the panel open —
        # _spawn_sh exists for exactly this class of "must outlive the panel".
        gif_source = target.get("gif_source")
        if gif_source and os.path.exists(gif_source):
            _notify("Converting to GIF…", os.path.basename(target.get("output", "")))
            _spawn_sh(_gif_convert_command(gif_source, target["output"]))
            return None

        _notify("Recording stopped", target.get("output", ""))
        return None

    os.makedirs(RECORD_DIR, exist_ok=True)

    if item_id in ("gif", "gif-region"):
        if not shutil.which("wf-recorder"):
            raise ValueError("wf-recorder is not installed — see the note in "
                             "island-picker.py: x11grab records a black frame "
                             "under Hyprland, measured")
        if not shutil.which("ffmpeg"):
            raise ValueError("ffmpeg is not installed — it is the palette pass, "
                             "and without it a GIF would be 23x larger")
        output = os.path.join(RECORD_DIR, "gif-%s.gif" % _stamp())
        # The h264 intermediate lives in RUNTIME, not /tmp and not
        # RECORD_DIR: dm-recordV2's own note is that a screen capture has no
        # business sitting world-readable in /tmp for the length of the
        # recording, and RECORD_DIR is where the user's finished recordings
        # are — a stray .mp4 there looks like one of them.
        source = os.path.join(RUNTIME, "island-gif-%d.mp4" % os.getpid())
        geometry = ('-g "$(slurp)" ' if item_id == "gif-region" else "")
        # Captured at GIF_FPS rather than at full rate and decimated later:
        # the frames that would be thrown away cost encode time and disk for
        # the whole recording, and -r is the flag wf-recorder takes for it.
        command = "wf-recorder -r %d %s-f %s" % (
            GIF_FPS, geometry, shlex.quote(source))

    elif item_id in ("screen", "region", "screen-audio"):
        if not shutil.which("wf-recorder"):
            raise ValueError("wf-recorder is not installed — see the note in "
                             "island-picker.py: x11grab records a black frame "
                             "under Hyprland, measured")
        output = os.path.join(RECORD_DIR, "screen-%s-%s.mp4" % (item_id, _stamp()))
        geometry = ('-g "$(slurp)" ' if item_id == "region" else "")
        # dm-recordV2 mixes a second ffmpeg input (`-f pulse -i default`);
        # wf-recorder takes the same PulseAudio default with one flag, and
        # its own muxer keeps the two streams in step. `--audio` with no
        # device argument is the default sink's monitor, which is what
        # dm-recordV2's `-i default` resolves to as well.
        audio = "--audio " if item_id == "screen-audio" else ""
        command = "wf-recorder %s%s-f %s" % (
            audio, geometry, shlex.quote(output))
    elif item_id == "audio":
        output = os.path.join(RECORD_DIR, "audio-%s.mp3" % _stamp())
        command = ("ffmpeg -nostdin -y -f pulse -i default "
                   "-c:a libmp3lame -qscale:a 2 %s" % shlex.quote(output))
    elif item_id in ("webcam-low", "webcam-hd"):
        camera = _webcam_device()
        if not camera:
            raise ValueError("no capture-capable webcam under /dev/video*")
        size = "640x480" if item_id == "webcam-low" else "1920x1080"
        output = os.path.join(RECORD_DIR, "%s-%s.mp4" % (item_id, _stamp()))
        # -video_size before -i, which is dm-recordV2's own hard-won fix:
        # after -i it is an output option, silently dropped, and both webcam
        # modes then recorded at the camera's default while the menu labels
        # claimed otherwise.
        command = ("ffmpeg -nostdin -y -f v4l2 -video_size %s -i %s "
                   "-c:v libx264 %s" % (size, shlex.quote(camera),
                                        shlex.quote(output)))
    else:
        raise ValueError("unknown recording mode %s" % item_id)

    # The pid written is the RECORDER's, not the shell's: `exec` replaces the
    # shell so there is only ever one process, and the pid in the file is the
    # one that must be signalled. Without exec, SIGINT reaches sh and the
    # encoder keeps writing.
    _spawn_sh("exec %s < /dev/null & echo $! > %s; wait" % (
        command, shlex.quote(RECORD_PID)))
    state = {"output": output, "mode": item_id}
    if item_id in ("gif", "gif-region"):
        # Read back by the stop path, which runs the second stage.
        state["gif_source"] = source
    _state_write("record", state)

    # The pidfile is written by the detached shell, so it is NOT there yet
    # when _spawn_sh returns. Poll briefly rather than sleeping a guessed
    # constant: without a pid the island can light the dot but cannot
    # watchdog it, which is the difference between an indicator that
    # self-corrects and one that can get stuck on.
    pid = 0
    for _ in range(40):
        pid = _record_active()
        if pid:
            break
        time.sleep(0.05)
    _island_recording(True, pid)
    _notify("Recording started", output)
    return None


# ------------------------------------------------------------ confedit --
#
#  dm-confedit, which is the only menu in the chord that is a NAVIGATION:
#  two roots, then a directory tree, then a file into the editor. It is the
#  page stack's reason for existing, and it is the cheapest possible test of
#  it — the pages are pure filesystem reads with nothing to undo.
#
#  Its exclusion list comes across verbatim. The one change is `../`: the
#  panel's own Backspace pops the stack, so a row that duplicates a key the
#  panel already binds is a row that can disagree with it.

CONFEDIT_EXCLUDE = re.compile(
    r"\.(jpe?g|png|gif|webp|mp4|avi|mov|mkv|mp3|wav|ogg|flac|zip|tar|gz|rar|"
    r"7z|pdf|docx?|iso|bak|tmp|swp|swo|log|lock|db|sqlite|cache|old|bin|exe|"
    r"class|pyc|so|out|crt|pem|key)$", re.IGNORECASE)
CONFEDIT_SKIP_DIRS = {".git", ".github", "node_modules"}


def confedit_list():
    return _page("Edit a config", [
        {"id": "dir:" + os.path.join(HOME, ".config"),
         "label": "Config", "detail": "~/.config"},
        {"id": "dir:" + os.path.join(HOME, ".dotfiles"),
         "label": "Dotfiles", "detail": "~/.dotfiles"},
    ], note="Backspace goes back up.")


def _confedit_page(path):
    directories, files = [], []
    try:
        with os.scandir(path) as entries:
            for entry in entries:
                name = entry.name
                # follow_symlinks left at its default True, which is find -L:
                # ~/.config is stow-symlinked into ~/.dotfiles here, so a
                # symlink-blind walk would show the whole tree as dead ends.
                if entry.is_dir():
                    if name in CONFEDIT_SKIP_DIRS:
                        continue
                    directories.append({
                        "id": "dir:" + entry.path,
                        "label": name + "/",
                        "detail": "directory",
                    })
                elif entry.is_file() and not CONFEDIT_EXCLUDE.search(name):
                    files.append({
                        "id": "file:" + entry.path,
                        "label": name,
                        "detail": "%d bytes" % entry.stat().st_size,
                    })
    except OSError as error:
        raise ValueError(str(error))

    directories.sort(key=lambda row: row["label"].lower())
    files.sort(key=lambda row: row["label"].lower())
    shown = path[len(HOME):] and "~" + path[len(HOME):] or path
    return _page(shown, directories + files)


def confedit_run(item_id):
    kind, path = _split(item_id)
    if kind == "dir":
        return _confedit_page(path)
    if kind != "file":
        raise ValueError("unknown confedit step %s" % item_id)

    # realpath, which dm-confedit also does and for the reason it gives:
    # opening the symlink rather than the target leaves nvim guessing the
    # filetype from a name like `config` instead of the real path.
    real = os.path.realpath(path)
    terminal = _terminal()
    if not terminal:
        raise ValueError("no terminal found")
    _spawn([terminal, "nvim", real] if terminal == "kitty"
           else [terminal, "-e", "nvim", real])
    return None


# ------------------------------------------------------------ spellcheck --
#
#  dm-spellcheck, which is LanguageTool plus a rofi table. The check itself
#  ports across unchanged — same endpoint, same short-input language
#  detection through Google's detector, same back-to-front application of
#  fixes so each offset is still valid when its turn comes.
#
#  WHAT CHANGES, AND IT IS ALL RENDERING
#  ------------------------------------
#  dm-spellcheck's output is a measured monospace table in pango markup: it
#  computes column widths in east-asian-width units and pads with spaces,
#  because a rofi row is one string and the only way to make columns is to
#  build them yourself. This panel has a label and a detail column, so the
#  table is the panel's job and the markup is gone: what was a `<span
#  foreground=…>` is now the label, and what was the third column is the
#  detail. The bidi isolates go with it — they exist to stop one Arabic word
#  reversing a row that is three columns glued together, which is not what a
#  row is here.
#
#  THE WORKING TEXT IS THE ONE PIECE OF STATE IN THIS FILE
#  ------------------------------------------------------
#  Applying a fix rewrites the sentence, and the next page has to check the
#  REWRITTEN one. The panel is not allowed to hold that (it holds ids, and
#  an id is opaque to it), and an id carrying the whole sentence would grow
#  by a sentence per fix. So the working text lives in a JSON file under
#  $XDG_RUNTIME_DIR, written by this script and read by the next invocation
#  of this script. It is per-user, it dies with the session, and nothing
#  else reads it.
#
#  DROPPED: Ctrl+r "other suggestions". dm-spellcheck binds a rofi custom key
#  to re-open the current mistake with its full ranked list instead of the
#  top three. Here every mistake's row already opens its own page, and that
#  page IS the full list — the extra key had nothing left to reach.

LT_API = "https://api.languagetool.org/v2/check"
LT_DETECT_API = "https://translate.googleapis.com/translate_a/single"
LT_LANG = {
    "en": "en-US", "de": "de-DE", "pt": "pt-PT", "ca": "ca-ES",
    "fr": "fr", "es": "es", "it": "it", "nl": "nl", "ar": "ar",
    "tr": "tr", "ru": "ru", "pl": "pl", "uk": "uk", "sv": "sv",
    "da": "da", "el": "el", "fa": "fa", "ga": "ga", "ro": "ro",
    "sk": "sk", "sl": "sl", "ta": "ta", "ja": "ja", "zh": "zh-CN",
}
LT_DEFAULT = "en-US"
LT_SHORT_WORDS = 4


def _detect_language(text):
    """Google's detector, for short input only.

    dm-spellcheck's reason, kept because it is a real measurement:
    LanguageTool's own language=auto called `gelest` Dutch and `asdkjhq`
    Galician and then offered suggestions from those languages. Over four
    words it is reliable and this does not run at all.
    """
    if len(text.split()) >= LT_SHORT_WORDS:
        return "auto"
    params = urllib.parse.urlencode([
        ("client", "gtx"), ("sl", "auto"), ("tl", "en"),
        ("dj", "1"), ("dt", "t"), ("q", text)])
    try:
        return LT_LANG.get(
            _http_json("%s?%s" % (LT_DETECT_API, params)).get("src", ""),
            LT_DEFAULT)
    except Exception:  # noqa: BLE001 — detection is a nicety, not a gate
        return LT_DEFAULT


def _lt_check(text, language):
    payload = urllib.parse.urlencode({
        "text": text, "language": language, "level": "default"}).encode()
    data = _http_json(
        LT_API, data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    return data.get("matches", []), data.get("language", {}).get("name", "")


def _lt_replacements(match, limit=None):
    values = [r.get("value", "") for r in match.get("replacements", []) if r.get("value")]
    return values[:limit] if limit else values


def spellcheck_list():
    return _prompt("Spell-check", "check", prompt="word or sentence",
                   value=_selection(),
                   note="Prefilled from the primary selection, exactly as "
                        "dm-spellcheck does — the selection is a prefill, "
                        "never a decision.")


def _spellcheck_page(text):
    language = _detect_language(text)
    try:
        matches, language_name = _lt_check(text, language)
    except Exception as error:  # noqa: BLE001 — offline is the common case
        raise ValueError("LanguageTool unreachable: %s" % error)

    _state_write("spell", {"text": text, "matches": matches})

    items = [{
        "id": "copy",
        "label": text,
        "detail": "copy this and close",
    }]
    if len(matches) > 1:
        items.append({"id": "all",
                      "label": "Fix all %d mistakes" % len(matches),
                      "detail": "apply every top suggestion"})
    for index, match in enumerate(matches):
        bad = text[match["offset"]:match["offset"] + match["length"]]
        replacements = _lt_replacements(match, 3)
        best = replacements[0] if replacements else ""
        items.append({
            "id": "fix:%d" % index,
            "label": "%s  →  %s" % (bad, best) if best else bad,
            "detail": match.get("shortMessage") or match.get("message", ""),
        })

    return _page(
        "%s · %s mistake%s" % (language_name or language,
                               len(matches) or "no",
                               "" if len(matches) == 1 else "s"),
        items, stack="replace")


def spellcheck_run(item_id, text=""):
    if item_id == "check":
        if not text.strip():
            raise ValueError("nothing to check")
        return _spellcheck_page(text.strip())

    state = _state_read("spell") or {}
    working, matches = state.get("text", ""), state.get("matches", [])
    if not working:
        raise ValueError("no text in flight — start again")

    if item_id == "copy":
        _copy(working)
        _notify("Copied", working)
        return None

    if item_id == "all":
        # Back to front. Applying forwards shifts every offset after the
        # first edit, which is dm-spellcheck's note and is why it sorts.
        for match in sorted(matches, key=lambda m: m["offset"], reverse=True):
            best = _lt_replacements(match, 1)
            if best:
                working = (working[:match["offset"]] + best[0]
                           + working[match["offset"] + match["length"]:])
        return _spellcheck_page(working)

    kind, rest = _split(item_id)
    if kind == "fix":
        match = matches[int(rest)]
        options = _lt_replacements(match)
        if not options:
            raise ValueError(match.get("message", "no suggestion"))
        bad = working[match["offset"]:match["offset"] + match["length"]]
        return _page("Replace “%s” with" % bad, [
            {"id": "put:%d:%s" % (int(rest), option), "label": option,
             "detail": match.get("message", "")}
            for option in options])

    if kind == "put":
        index, replacement = _split(rest)
        match = matches[int(index)]
        working = (working[:match["offset"]] + replacement
                   + working[match["offset"] + match["length"]:])
        return _spellcheck_page(working)

    raise ValueError("unknown spellcheck step %s" % item_id)


# ------------------------------------------------------------- translate --
#
#  rofi_translator/wordreference.py is 966 lines and most of them are not
#  translation: they are a pango table renderer, a rofi theme, a Gemini
#  explanation pass, a disk cache and a spell-check detour. What the chord is
#  pressed for is the middle: hand it a word or a sentence, get the
#  translation and the alternatives back.
#
#  That middle is one endpoint — Google's translate_a/single, the same one
#  wordreference.py uses and the same one dm-spellcheck borrows for language
#  detection — and it is what is here.
#
#  KEPT ACROSS: the last target language, read from and written to
#  ~/.cache/rofi_translator/last_lang. Deliberately THE SAME FILE, not a new
#  one: the two tools should not disagree about which language you were
#  working in, and the qtile session's translator is still the one with the
#  Gemini pass.
#
#  DROPPED, and each for its own reason:
#    * the Gemini explanation and the synonym/example sections. They need
#      GEMINI_API_KEY out of ~/.config/secrets.env and they are the part of
#      that script most likely to be slow or absent; a menu that sometimes
#      takes ten seconds is a menu you stop pressing.
#    * the disk cache. It exists because the rofi run pays the round trip on
#      every redraw of the same word; this asks once per open.
#    * the spell-check detour on a no-result. `spellcheck` is its own menu
#      now and is one chord away.

TRANSLATE_API = "https://translate.googleapis.com/translate_a/single"
TRANSLATE_LAST = os.path.expanduser("~/.cache/rofi_translator/last_lang")
TRANSLATE_LANGS = {
    "en": "English", "de": "German", "ar": "Arabic", "tr": "Turkish",
    "fr": "French", "es": "Spanish", "it": "Italian", "nl": "Dutch",
    "ru": "Russian", "ja": "Japanese", "zh-CN": "Chinese",
}


def _translate_target():
    try:
        with open(TRANSLATE_LAST) as handle:
            code = handle.read().strip()
        return code if code in TRANSLATE_LANGS else "en"
    except OSError:
        return "en"


def _translate_set_target(code):
    try:
        os.makedirs(os.path.dirname(TRANSLATE_LAST), exist_ok=True)
        with open(TRANSLATE_LAST, "w") as handle:
            handle.write(code)
    except OSError:
        pass


def translate_list():
    target = _translate_target()
    return _prompt("Translate → %s" % TRANSLATE_LANGS.get(target, target),
                   "go", prompt="word or sentence", value=_selection(),
                   note="Target language is the one the qtile translator left "
                        "in ~/.cache/rofi_translator/last_lang. Enter "
                        "translates; the results page can change it.")


def _translate_page(text, target):
    params = urllib.parse.urlencode([
        ("client", "gtx"), ("sl", "auto"), ("tl", target), ("dj", "1"),
        ("dt", "t"), ("dt", "bd"), ("dt", "at"), ("q", text)])
    try:
        data = _http_json("%s?%s" % (TRANSLATE_API, params))
    except Exception as error:  # noqa: BLE001
        raise ValueError("translate endpoint unreachable: %s" % error)

    source = data.get("src", "?")
    sentences = "".join(part.get("trans", "")
                        for part in data.get("sentences", []))
    _state_write("translate", {"text": text, "target": target})

    items = [{
        "id": "copy:" + sentences,
        "label": sentences or "(no translation)",
        "detail": "%s → %s  ·  Enter copies" % (
            TRANSLATE_LANGS.get(source, source),
            TRANSLATE_LANGS.get(target, target)),
    }]

    # `dict` is the dictionary block: part of speech, then the ranked terms.
    # It is the half of wordreference.py's table that carries the actual
    # information, and the half a one-line answer throws away.
    for entry in data.get("dict", []) or []:
        pos = entry.get("pos", "")
        for term in entry.get("terms", [])[:6]:
            items.append({"id": "copy:" + term, "label": term,
                          "detail": pos or "alternative"})

    items.append({"id": "lang", "label": "Translate to…",
                  "detail": "change the target language"})
    return _page(_ellipsis(text, 60), items, stack="replace")


def translate_run(item_id, text=""):
    kind, rest = _split(item_id)

    if item_id == "go":
        if not text.strip():
            raise ValueError("nothing to translate")
        return _translate_page(text.strip(), _translate_target())

    if kind == "copy":
        _copy(rest)
        _notify("Copied", rest)
        return None

    if item_id == "lang":
        return _page("Translate to", [
            {"id": "to:" + code, "label": name, "detail": code}
            for code, name in sorted(TRANSLATE_LANGS.items(),
                                     key=lambda pair: pair[1])])

    if kind == "to":
        _translate_set_target(rest)
        state = _state_read("translate") or {}
        if not state.get("text"):
            raise ValueError("nothing in flight — start again")
        return _translate_page(state["text"], rest)

    raise ValueError("unknown translate step %s" % item_id)


# ------------------------------------------------------------------ pass --
#
#  rofi_pass, backed by Vaultwarden through rbw. The READ half is here and
#  the WRITE half is not; the split is deliberate and is spelt out below.
#
#  THE LOCKED AGENT
#  ----------------
#  rbw keeps the vault decrypted in an agent, and unlocking pops rbw's own
#  pinentry dialog. That dialog cannot be driven from behind this panel: a
#  layer-shell surface with an exclusive keyboard grab holds the keyboard,
#  so pinentry would come up focused and deaf. Rather than pretend, a locked
#  vault lists exactly one row, and running it spawns `rbw unlock` DETACHED
#  and closes the panel — which is what hands the keyboard back. Press the
#  chord again afterwards.
#
#  WHAT IS DROPPED, AND WHY EACH
#    * add / edit / delete / change-username (alt+n, alt+e, alt+x). These are
#      the parts of rofi_pass with the most careful code in them — the
#      recreate-then-remove ordering that survives a failure halfway, the
#      UUID-not-name identity that stops a duplicate becoming unreachable —
#      and reimplementing that carefully a second time, in another language,
#      against the same vault, is how the two copies drift and one of them
#      eats an entry. rofi_pass keeps them and it still runs.
#    * alt+a, type-into-the-focused-window. It is xdotool, i.e. X11. The
#      Wayland equivalent is wtype, and wtype creates and destroys a virtual
#      keyboard — which closes a layer-shell panel that holds the keyboard.
#      That is the same wall the clipboard port hit and it is written up
#      there too.
#    * the 30-second clipboard wipe. It is a background `sleep` that
#      compares the clipboard before clearing it, and this script exits the
#      moment --run returns; a detached wiper that outlives the picker and
#      then clears a clipboard the user has since refilled is worse than no
#      wiper. Named here rather than silently missing.


def _rbw(*args, **kwargs):
    return subprocess.run(["rbw", *args], capture_output=True, text=True,
                          timeout=kwargs.get("timeout", 20))


def pass_list():
    if not shutil.which("rbw"):
        return _message("Pass", "rbw is not installed.")

    if _rbw("unlocked").returncode != 0:
        return _page("Vault locked", [{
            "id": "unlock",
            "label": "Unlock the vault",
            "detail": "closes this panel so rbw's pinentry can take the keyboard",
        }], note="rbw's agent is locked. The unlock prompt is a separate "
                 "window and cannot get the keyboard while this panel holds "
                 "it, so this closes first. Press the chord again after.")

    out = _rbw("ls", "--fields", "id,name,user,folder")
    items = []
    for line in out.stdout.splitlines():
        fields = line.split("\t")
        while len(fields) < 4:
            fields.append("")
        uuid, name, user, folder = fields[:4]
        if not name:
            continue
        # Everything below addresses the entry by UUID and never by
        # name+user, which is rofi_pass's own hard-won rule: rbw permits two
        # entries with the same name and username and then refuses to act on
        # either ("multiple entries found"), so a name-keyed menu turns a
        # duplicate into an entry you can neither read nor delete.
        items.append({
            "id": "e:" + uuid,
            "label": name + ("  ·  " + user if user else ""),
            "detail": folder or "",
        })
    return _page("Pass", items)


def pass_run(item_id):
    kind, rest = _split(item_id)

    if item_id == "unlock":
        _spawn_sh("sleep 0.3; rbw unlock")
        return None

    if kind == "e":
        return _page("What from this entry?", [
            {"id": "f:password:" + rest, "label": "Copy password",
             "detail": "rbw get"},
            {"id": "f:user:" + rest, "label": "Copy username",
             "detail": "rbw ls"},
            {"id": "f:totp:" + rest, "label": "Copy TOTP code",
             "detail": "rbw code"},
            {"id": "f:uri:" + rest, "label": "Open the site",
             "detail": "the entry's first URI, in $BROWSER"},
        ])

    if kind != "f":
        raise ValueError("unknown pass step %s" % item_id)

    field, uuid = _split(rest)
    if field == "password":
        value = _rbw("get", uuid).stdout.strip()
        what = "Password"
    elif field == "totp":
        value = _rbw("code", uuid).stdout.strip()
        what = "TOTP"
    elif field == "user":
        value = ""
        for line in _rbw("ls", "--fields", "id,user").stdout.splitlines():
            parts = line.split("\t")
            if parts and parts[0] == uuid and len(parts) > 1:
                value = parts[1]
        what = "Username"
    elif field == "uri":
        uri = ""
        for line in _rbw("get", "--full", uuid).stdout.splitlines():
            if line.startswith("URI: "):
                uri = line[5:].strip()
                break
        if not uri:
            raise ValueError("entry has no website")
        _spawn([os.environ.get("BROWSER") or "xdg-open", uri])
        return None
    else:
        raise ValueError("unknown field %s" % field)

    if not value:
        raise ValueError("entry has no %s" % field)
    _copy(value)
    # The value is NEVER in the notification body. rofi_pass says "Password
    # copied" for the same reason: a dunst notification is on screen for
    # seconds and is in the notification centre afterwards.
    _notify("%s copied" % what, "from the vault")
    return None


# ------------------------------------------------------------------ todo --
#
#  rofi_todo is 652 lines: four sessions (today / future / general / done),
#  subtasks with parent-status roll-up, priorities, due dates, tag colouring,
#  a working-on marker, an edit box and a lock file. What is ported is the
#  list and the two verbs that change it — toggle done, add a task — and
#  nothing else.
#
#  This is the largest deliberate reduction in the whole port, so here is
#  the measurement behind it: ~/ATITODOS/TODOS.md, the file rofi_todo reads,
#  currently contains ZERO lines matching `^\s*- \[[ x]\]`. It is a freeform
#  numbered list. Every one of those 652 lines of session/subtask/priority
#  machinery is running over a format the file is not written in, which is
#  why this port claims only the checkbox lines: they are the part of the
#  format that is real, and a task list that shows the checkboxes and can add
#  one is a task list.
#
#  rofi_todo is untouched and the qtile session still has all of it.

TODO_FILE = os.path.join(HOME, "%sTODOS" % os.environ.get("USER", "").upper(),
                         "TODOS.md")
TODO_LINE = re.compile(r"^(\s*)- \[([ xX])\]\s*(.*)$")


def _todo_lines():
    try:
        with open(TODO_FILE) as handle:
            return handle.read().splitlines()
    except OSError:
        return []


def todo_list():
    items = [{"id": "new", "label": "New task…",
              "detail": os.path.basename(TODO_FILE)}]
    for number, line in enumerate(_todo_lines()):
        match = TODO_LINE.match(line)
        if not match:
            continue
        indent, mark, body = match.groups()
        done = mark.lower() == "x"
        items.append({
            # The LINE NUMBER is the id, and the label is what it says
            # today. rofi_todo keys on line numbers too; the difference is
            # that this list is re-read on every open, so a number is never
            # older than the panel it is showing.
            "id": "t:%d" % number,
            "label": ("✓ " if done else "☐ ") + body,
            "detail": ("done" if done else "open")
                      + ("  ·  subtask" if indent else ""),
        })
    if len(items) == 1:
        return _page("Todo", items,
                     note="No `- [ ]` lines in %s. rofi_todo reads the same "
                          "file and finds the same nothing — see the note in "
                          "island-picker.py." % TODO_FILE)
    return _page("Todo", items)


def todo_run(item_id, text=""):
    kind, rest = _split(item_id)

    if item_id == "new":
        return _prompt("New task", "add", prompt="what needs doing",
                       note="Appended to %s as `- [ ] …`." % TODO_FILE)

    if item_id == "add":
        body = text.strip()
        if not body:
            raise ValueError("nothing to add")
        os.makedirs(os.path.dirname(TODO_FILE), exist_ok=True)
        lines = _todo_lines()
        lines.append("- [ ] " + body)
        with open(TODO_FILE, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        _notify("Task added", body)
        return _page("Todo", todo_list()["items"], stack="root")

    if kind != "t":
        raise ValueError("unknown todo step %s" % item_id)

    lines = _todo_lines()
    number = int(rest)
    match = TODO_LINE.match(lines[number]) if number < len(lines) else None
    if not match:
        raise ValueError("that line is not a task any more — reopen the menu")
    indent, mark, body = match.groups()
    lines[number] = "%s- [%s] %s" % (indent, " " if mark.lower() == "x" else "x",
                                     body)
    with open(TODO_FILE, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    return _page("Todo", todo_list()["items"], stack="root")


# ---------------------------------------------------------------- shared --
#
#  rofi_shared: a markdown file of links, opened in the browser. The list, the
#  add and the delete are here.
#
#  DROPPED: the thumbnails. rofi_shared fetches a YouTube hqdefault (or a
#  microlink preview) per row into a cache and passes -show-icons, and this
#  panel CAN draw icons — the clipboard menu does. It is not here because
#  every one of those is a network fetch and the list is built synchronously
#  while the panel waits: the clipboard's thumbnails come off the local copyq
#  database in milliseconds, and a link list that pauses on the wire before
#  it paints is a list that feels broken. Cached thumbnails that rofi_shared
#  has ALREADY fetched are used, because reading them costs nothing.

SHARED_FILE = os.path.join(HOME, ".config/rofi/Todo_files/Shared_Links.md")
SHARED_THUMBS = os.path.join(RUNTIME, "link-thumbs")
SHARED_MD = re.compile(r"^\s*[-*]?\s*\[([^\]]*)\]\(([^)]+)\)")
SHARED_BARE = re.compile(r"(https?://\S+)")


def _shared_entries():
    """[(title, url)] from the markdown, whichever of the two shapes it uses."""
    entries = []
    try:
        with open(SHARED_FILE) as handle:
            lines = handle.read().splitlines()
    except OSError:
        return entries
    for line in lines:
        markdown = SHARED_MD.match(line)
        if markdown:
            entries.append((markdown.group(1).strip() or markdown.group(2),
                            markdown.group(2).strip()))
            continue
        bare = SHARED_BARE.search(line)
        if bare:
            url = bare.group(1)
            title = line.replace(url, "").strip(" -*|\t") or url
            entries.append((title, url))
    return entries


def _shared_thumb(url):
    """rofi_shared's cache path for a url: md5 of the url, .jpg."""
    import hashlib
    path = os.path.join(SHARED_THUMBS,
                        hashlib.md5(url.encode()).hexdigest() + ".jpg")
    return path if os.path.isfile(path) else ""


def shared_list():
    items = [{"id": "new", "label": "Add a link…", "detail": SHARED_FILE}]
    for title, url in _shared_entries():
        row = {"id": "open:" + url, "label": title, "detail": url}
        thumb = _shared_thumb(url)
        if thumb:
            row["icon"] = thumb
        items.append(row)
    if len(items) > 1:
        items.append({"id": "delmenu", "label": "Remove a link…",
                      "detail": "%d saved" % (len(items) - 1)})
    return _page("Shared links", items)


def shared_run(item_id, text=""):
    kind, rest = _split(item_id)

    if kind == "open":
        _spawn([os.environ.get("BROWSER") or "xdg-open", rest])
        return None

    if item_id == "new":
        return _prompt("Add a link", "save", prompt="url", value=_selection(),
                       note="Prefilled from the primary selection, which is "
                            "how a link usually arrives.")

    if item_id == "save":
        url = text.strip()
        if not url.startswith(("http://", "https://")):
            raise ValueError("that is not a URL")
        os.makedirs(os.path.dirname(SHARED_FILE), exist_ok=True)
        # Appended as markdown with the url as its own title. rofi_shared
        # derives a title by fetching the page's <title>, which is a network
        # round trip in the middle of a keystroke; its "edit title" action
        # exists precisely because that guess is often wrong.
        with open(SHARED_FILE, "a") as handle:
            handle.write("- [%s](%s)\n" % (url, url))
        _notify("Link saved", url)
        return _page("Shared links", shared_list()["items"], stack="root")

    if item_id == "delmenu":
        return _page("Remove which?", [
            {"id": "del:" + url, "label": title, "detail": url}
            for title, url in _shared_entries()])

    if kind == "del":
        try:
            with open(SHARED_FILE) as handle:
                lines = handle.read().splitlines()
        except OSError as error:
            raise ValueError(str(error))
        kept = [line for line in lines if rest not in line]
        with open(SHARED_FILE, "w") as handle:
            handle.write("\n".join(kept) + ("\n" if kept else ""))
        _notify("Link removed", rest)
        return _page("Shared links", shared_list()["items"], stack="root")

    raise ValueError("unknown shared step %s" % item_id)


# --------------------------------------------------------------- youtube --
#
#  dm-youtube: pick a channel from the dmscripts config, read its RSS feed,
#  pick a video, open it. Ported whole — it is two lists and a browser — and
#  it reads THE SAME `youtube_channels` array out of ~/.config/dmscripts/
#  config, so the two stay in step by construction rather than by discipline.
#
#  The channel-id lookup is dm-youtube's: the configured URL is a channel
#  page, and the feed needs the UC… id, which is only in the page's HTML.

YOUTUBE_CONFIG = os.path.expanduser("~/.config/dmscripts/config")
YOUTUBE_DECL = re.compile(r'^\s*youtube_channels\[([^\]]+)\]\s*=\s*"([^"]+)"')


def _youtube_channels():
    channels = []
    try:
        with open(YOUTUBE_CONFIG) as handle:
            for line in handle:
                match = YOUTUBE_DECL.match(line)
                if match:
                    channels.append((match.group(1).strip('"\''),
                                     match.group(2)))
    except OSError:
        pass
    return channels


def youtube_list():
    channels = _youtube_channels()
    if not channels:
        return _message("YouTube",
                        "No youtube_channels[…] lines in %s." % YOUTUBE_CONFIG)
    return _page("YouTube", [
        {"id": "c:" + url, "label": name, "detail": url}
        for name, url in channels])


def _fetch(url, timeout=15):
    request = urllib.request.Request(
        url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def youtube_run(item_id):
    kind, rest = _split(item_id)

    if kind == "v":
        _spawn([os.environ.get("BROWSER") or "xdg-open",
                "https://www.youtube.com/watch?v=" + rest])
        return None

    if kind != "c":
        raise ValueError("unknown youtube step %s" % item_id)

    try:
        page_html = _fetch(rest)
    except Exception as error:  # noqa: BLE001
        raise ValueError("could not read the channel page: %s" % error)
    found = re.search(r'"channelId":"(UC[\w-]+)"', page_html) \
        or re.search(r'channel_id=(UC[\w-]+)', page_html)
    if not found:
        raise ValueError("no channel id in that page")

    try:
        feed = _fetch("https://www.youtube.com/feeds/videos.xml?channel_id="
                      + found.group(1))
    except Exception as error:  # noqa: BLE001
        raise ValueError("could not read the feed: %s" % error)

    items = []
    for entry in re.findall(r"<entry>(.*?)</entry>", feed, re.S):
        video = re.search(r"<yt:videoId>([^<]+)</yt:videoId>", entry)
        title = re.search(r"<title>(.*?)</title>", entry, re.S)
        published = re.search(r"<published>([^<]+)</published>", entry)
        if not video:
            continue
        items.append({
            "id": "v:" + video.group(1),
            # unescape, not a raw slice: a feed title is XML-escaped and
            # "Rust &amp; C" in a row label is the row telling you it was
            # never decoded.
            "label": html.unescape(title.group(1).strip()) if title else video.group(1),
            "detail": (published.group(1)[:16].replace("T", " ")
                       if published else ""),
        })
    return _page("Latest videos", items)


# ------------------------------------------------------------------ anki --
#
#  rofi_anki, and the header of this file used to say it could not be ported.
#  The reason it gave was right about the shape and wrong about the
#  consequence: it IS a linear wizard over an external service where each
#  step depends on the last, and a page stack is exactly that. What the note
#  actually feared was the second half — "this file growing a second copy of
#  each script's control flow, with the original left in place as the one
#  that still works" — and that fear is answered by not copying anything.
#
#  MEASURED BEFORE DECIDING: of rofi_anki's 373 lines, the eight prompts are
#  lines 181-305. Everything else — the AnkiConnect handshake, deck
#  provisioning, the Gemini call with a translate-shell fallback, espeak-ng
#  IPA, three flavours of TTS glued together by ffmpeg, storeMediaFile,
#  the HTML assembly, addNote — is card logic that does not care which window
#  asked. So this menu asks the eight questions and hands them to
#  `rofi_anki --answers FILE`. One copy of the card logic, and the qtile
#  session keeps the rofi prompts as its default path.
#
#  WHAT THIS IS BETTER AT THAN THE ROFI ORIGINAL, rather than merely
#  elsewhere:
#    * the four yes/no audio-and-image questions were four sequential rofi
#      windows, each a two-row list. They are ONE page of four toggles here,
#      so you can see and change all four at once instead of answering blind
#      and having no way back.
#    * "Add an image?" then "paste the URL" was two steps to express one
#      fact. A URL or nothing says it once — a non-empty url IS the yes, and
#      rofi_anki derives WANT_IMAGE from it in answers mode.
#
#  WHAT IS DELIBERATELY NOT DONE HERE: the AnkiConnect wait. rofi_anki
#  already starts Anki and polls the port for 45 s, and `--list` runs
#  synchronously under the panel — a 45 s block would freeze the picker on
#  open. This probes for 2 s and says so in the note if nothing answers; the
#  real wait happens in the detached run where it costs nothing.
#
#  THE SUBMIT IS DETACHED, AND THAT IS NOT AN OPTIMISATION. Building a card
#  with spelling audio runs gtts-cli once per CHARACTER; the run is tens of
#  seconds. Holding the panel open on it would make the shell look hung, so
#  the panel closes and rofi_anki's own notify-send calls become the
#  progress report — the same ones the rofi path has always emitted.

ANKI_URL = "http://127.0.0.1:8765"

#  The three labels are rofi_anki's prompts with the "Include"/"audio?"
#  scaffolding removed, because here they are rows on a page headed "what to
#  include" rather than four separate questions. The quoted names inside them
#  -- 'Word once', 'Word Three Times', 'Spelling' -- are verbatim.
ANKI_TOGGLES = [
    ("voice_normal", "Word once", "audio of the front, spoken once"),
    ("voice_repeat", "Word Three Times", "the same clip, three times, spaced"),
    ("voice_spell", "Spelling", "letter by letter, then the whole word"),
]

ANKI_DEFAULTS = {
    "front_lang": "en", "text": "", "tags": "",
    "voice_normal": "no", "voice_repeat": "no", "voice_spell": "no",
    "image_url": "",
}


def _anki_up():
    """True when AnkiConnect answers within 2 s."""
    try:
        _http_json(ANKI_URL, data=b'{"action":"version","version":6}',
                   headers={"Content-Type": "application/json"}, timeout=2)
        return True
    except Exception:  # noqa: BLE001 — any failure means "not answering"
        return False


def _anki_state(**changes):
    state = dict(ANKI_DEFAULTS, **(_state_read("anki") or {}))
    state.update(changes)
    _state_write("anki", state)
    return state


def anki_list():
    _state_write("anki", dict(ANKI_DEFAULTS))
    note = ("Front language picks the deck: English or German.")
    if not _anki_up():
        note += ("  Anki is not answering on 127.0.0.1:8765 — it will be "
                 "started and waited for when the card is submitted.")
    return _page("Choose front language", [
        {"id": "lang:en", "label": "en (front: English)",
         "detail": "deck English · back in German"},
        {"id": "lang:de", "label": "de (front: German)",
         "detail": "deck German · back in English"},
    ], note=note)


def _anki_options_page(state):
    items = [{
        "id": "toggle:" + key,
        "label": ("● " if state.get(key) == "yes" else "○ ") + label,
        "detail": detail,
    } for key, label, detail in ANKI_TOGGLES]
    url = state.get("image_url", "")
    items.append({
        "id": "image",
        "label": ("● " if url else "○ ") + "Image",
        "detail": _ellipsis(url, 46) if url
                  else "next page asks for a URL; blank means no image",
    })
    items.append({"id": "go", "label": "Create the card",
                  "detail": "front “%s”%s" % (
                      _ellipsis(state.get("text", ""), 40),
                      " · tags " + state["tags"] if state.get("tags") else "")})
    return _page("Anki · what to include", items, stack="replace",
                 note="Enter toggles a row and stays here. "
                      "Choose “Create the card” when the four read right.")


def anki_run(item_id, text=""):
    kind, rest = _split(item_id)

    if kind == "lang":
        _anki_state(front_lang=rest)
        return _prompt("Enter word / sentence (front)", "text",
                       prompt="word or sentence for the front",
                       value=_selection(),
                       note="Prefilled from the primary selection, the same "
                            "way spellcheck and translate are.")

    if item_id == "text":
        if not text.strip():
            raise ValueError("a card needs a front")
        _anki_state(text=text.strip())
        return _prompt("Tags (space separated) — optional", "tags",
                       prompt="space separated — Enter with nothing skips",
                       note="Optional. rofi_anki splits on whitespace and "
                            "sends them as the note's tags.")

    if item_id == "tags":
        return _anki_options_page(_anki_state(tags=text.strip()))

    if kind == "toggle":
        state = _state_read("anki") or {}
        return _anki_options_page(
            _anki_state(**{rest: "no" if state.get(rest) == "yes" else "yes"}))

    if item_id == "image":
        state = _state_read("anki") or {}
        return _prompt("Paste image URL (or leave blank)", "imageurl", prompt="image URL",
                       value=state.get("image_url", ""),
                       note="Enter with nothing leaves the card without an "
                            "image. rofi_anki checks the MIME type of what "
                            "comes back and drops it if it is not an image.")

    if item_id == "imageurl":
        return _anki_options_page(_anki_state(image_url=text.strip()))

    if item_id == "go":
        state = _state_read("anki") or {}
        if not state.get("text"):
            raise ValueError("no text in flight — start again")
        script = shutil.which("rofi_anki") or os.path.join(
            HOME, ".dotfiles/.config/AtiScriptsV1/rofi_anki")
        if not os.path.exists(script):
            raise ValueError("rofi_anki not found")
        # The state file IS the answers file — the wizard's state and
        # rofi_anki's input are the same seven values, so writing a second
        # copy would only create a way for them to disagree. It lives in
        # $XDG_RUNTIME_DIR, which is 0700 and dies with the session.
        _spawn([script, "--answers", _state_path("anki")])
        _notify("Anki", "Building “%s”…" % _ellipsis(state["text"], 40))
        return None

    raise ValueError("unknown anki step %s" % item_id)


# ------------------------------------------------------------------- hub --
#
#  dm-hub launches the other dm-* scripts, and that is exactly the reason it
#  could not be ported as itself: running it from the island would spawn the
#  rofi menus this whole port exists to stop spawning. A hub whose rows open
#  rofi windows is the anti-goal with a nicer front door.
#
#  So it is ported as what it is FOR — one place that reaches every menu
#  without having to remember its letter — and its rows open the ISLAND's
#  menus. The mechanism is the page's optional `menu` key: the panel
#  re-targets itself at the named menu and the returned page becomes its
#  root. Nothing about the "the panel never sees a command" rule changes;
#  a menu name is not a command, and an unknown one produces an error page
#  rather than an exec.
#
#  The keys in the third column are the chord letters from submaps.conf, so
#  the hub teaches its own obsolescence.

HUB_ROWS = [
    ("windows", "Close a window", "$mod P, K with shift"),
    ("processes", "Kill a process", "$mod P, K"),
    ("workspaces", "Go to a workspace", "$mod P, J"),
    ("documents", "Open a PDF", "$mod P, D"),
    ("man", "Read a manpage", "$mod P, M"),
    ("notes", "Notes", "$mod P, O"),
    ("brightness", "Brightness", "$mod P, L"),
    ("clipboard", "Clipboard history", "$alt V"),
    ("screenshot", "Screenshot", "$mod P, I"),
    ("record", "Record", "$mod P, R"),
    ("spellcheck", "Spell-check", "$mod P, S"),
    ("translate", "Translate", "$mod P, E"),
    ("pass", "Passwords", "$mod P, P"),
    ("todo", "Todo", "$mod P, T"),
    ("shared", "Shared links", "$mod P, Z"),
    ("youtube", "YouTube", "$mod P, Y"),
    ("confedit", "Edit a config", "$mod P, F"),
    ("anki", "Add an Anki card", "$mod P, A"),
]


def hub_list():
    return _page("Everything", [
        {"id": name, "label": label, "detail": key}
        for name, label, key in HUB_ROWS])


def hub_run(item_id):
    entry = MENUS.get(item_id)
    if entry is None:
        raise ValueError("unknown menu %s" % item_id)
    page = entry[0]()
    page["menu"] = item_id
    page["stack"] = "root"
    return page


# -------------------------------------------------------------- ilovepdf --
#
#  THE PDF TOOLKIT, off rofi at last.
#
#  Asked for directly: "rofi ilove pdf neeed popup not using rofi ok". This
#  was also the LAST key in the rofi chord still opening rofi, and
#  submaps.conf said why it was the last:
#
#      "V's real reason is that rofi_ilovepdf is a FILE MANAGER ... The
#       picker protocol carries exactly one id back per page, so
#       multi-select cannot be expressed in it at all — porting V means
#       either building selection state into PickerLayer.qml or shipping a
#       PDF toolkit that has lost merge."
#
#  THAT CONCLUSION WAS WRONG, and in the same way this file's own header
#  records being wrong about prompting menus. One id per page is not a limit
#  when the page COMES BACK: `tog:` toggles a path in a set and returns the
#  same page re-rendered with checkmarks, exactly as the spell-checker keeps
#  its working text. The selection lives under $XDG_RUNTIME_DIR, held by
#  this script — the panel still knows nothing, still holds no state, and
#  PickerLayer.qml is not touched at all.
#
#  WHAT IS PORTED, AND WHAT IS NOT
#  -------------------------------
#  The 1,267-line toolkit is NOT reimplemented. rofi_ilovepdf grew two verbs,
#  `--list-tools` and `--exec`, and everything below drives them: the
#  conversion logic, the encryption checks, the page-range validation and the
#  output naming stay in the one place that has always owned them, and the
#  qtile session keeps the interactive script unchanged.
#
#  The one behaviour that is deliberately NOT reproduced is `order_files` —
#  rofi's multi-select returns lines in list order, so the original had to
#  offer a reordering step before a merge. Here the order is the order you
#  TICK them in, which is the thing that step existed to recover.

_PDF = "rofi_ilovepdf"
_PDF_STATE = os.path.join(RUNTIME, "island-pdf.json")


def _pdf_state(update=None):
    """Read, or merge-and-write, the wizard's state.

    A file and not a module global: every --run is a fresh process, so a
    global would be empty on the next keystroke. Same discipline the
    spell-checker uses and for the same reason.
    """
    state = {}
    try:
        with open(_PDF_STATE, "r", encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        state = {}
    if update is None:
        return state
    state.update(update)
    try:
        os.makedirs(os.path.dirname(_PDF_STATE), exist_ok=True)
        with open(_PDF_STATE, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
    except OSError:
        pass
    return state


def _pdf_tools():
    """[{label, exts, multi, asks}] from the toolkit itself.

    Read at runtime rather than copied here. A second list of tools would
    drift the first time one was added — and it would drift SILENTLY, since
    a menu row that names a tool the script does not have simply fails when
    chosen.
    """
    try:
        out = subprocess.run([_PDF, "--list-tools"],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    tools = []
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        label, exts, multi, asks = parts
        tools.append({"label": label,
                      "exts": exts.split(),
                      "multi": multi == "1",
                      "asks": int(asks or 0)})
    return tools


def _pdf_tool_by_label(label):
    for tool in _pdf_tools():
        if tool["label"] == label:
            return tool
    return None


def ilovepdf_list():
    tools = _pdf_tools()
    if not tools:
        return _message("iLovePDF",
                        "rofi_ilovepdf --list-tools returned nothing. "
                        "Check that it is on PATH and that its dependencies "
                        "are installed (it says which).")
    items = []
    for tool in tools:
        # The toolkit's labels open with a Nerd Font glyph, and it is
        # STRIPPED rather than moved to the panel's icon slot.
        #
        # The slot exists and works — PickerLayer draws a short non-path
        # `icon` in the icon font — but these particular glyphs do not
        # render. They are Material Design icons in the SUPPLEMENTARY
        # private use area (U+F022C and friends), and while the font has
        # them (`fc-list :charset=f022c` names JetBrainsMono Nerd Font) and
        # the same widget renders a BMP one (U+F002, the search magnifier)
        # in the same face, nothing paints. Shipping them would be a 28 px
        # blank column down the whole list.
        #
        # Dropping the glyph costs nothing here: every row is already a
        # sentence that says what it does.
        label = tool["label"]
        _icon, _, rest = label.partition("  ")
        detail = ", ".join(tool["exts"][:4])
        if tool["multi"]:
            detail += "  · several files"
        items.append({"id": "tool:" + label,
                      "label": rest or label,
                      "detail": detail})
    return _page("iLovePDF", items)


def _pdf_roots():
    """Where to start browsing. The toolkit's own output folder first."""
    home = os.path.expanduser("~")
    roots = [os.path.join(home, "ILovePdf_Style_Docs"),
             os.path.join(home, "Downloads"),
             os.path.join(home, "Documents"),
             os.path.join(home, "Desktop"),
             home]
    seen, out = set(), []
    for path in roots:
        if path in seen or not os.path.isdir(path):
            continue
        seen.add(path)
        out.append(path)
    return out


def _pdf_short(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path.startswith(home) else path


def _pdf_browser(state, note=""):
    """One directory: sub-folders, then the files this tool can open."""
    tool = _pdf_tool_by_label(state.get("tool", "")) or {}
    exts = set(tool.get("exts") or [])
    multi = bool(tool.get("multi"))
    picked = list(state.get("picked") or [])
    directory = state.get("dir") or ""

    items = []
    if not directory:
        for root in _pdf_roots():
            items.append({"id": "dir:" + root, "label": os.path.basename(root) or root,
                          "detail": _pdf_short(root)})
        return _page("Where are the files?", items, note=note, stack="push")

    parent = os.path.dirname(directory.rstrip("/"))
    if parent and parent != directory:
        items.append({"id": "dir:" + parent, "label": "..",
                      "detail": _pdf_short(parent)})

    try:
        entries = sorted(os.listdir(directory), key=str.lower)
    except OSError:
        entries = []

    files = []
    for name in entries:
        if name.startswith("."):
            continue
        full = os.path.join(directory, name)
        if os.path.isdir(full):
            items.append({"id": "dir:" + full, "label": name, "detail": ""})
            continue
        ext = os.path.splitext(name)[1].lstrip(".").lower()
        if ext not in exts:
            continue
        files.append((name, full))

    for name, full in files:
        if multi:
            # The tick AND the position. With merge the order is the answer,
            # not a detail — "3 of 4" is what tells you the file you are
            # about to add lands last.
            at = picked.index(full) + 1 if full in picked else 0
            items.append({"id": "tog:" + full,
                          "label": ("%d. " % at if at else "") + name,
                          "detail": "picked" if at else ""})
        else:
            items.append({"id": "file:" + full, "label": name, "detail": ""})

    if multi and picked:
        items.insert(0, {"id": "go",
                         "label": "Run on %d file%s" % (len(picked),
                                                        "" if len(picked) == 1 else "s"),
                         "detail": ", ".join(os.path.basename(p) for p in picked)[:60]})

    title = (tool.get("label", "iLovePDF").split("  ", 1)[-1]
             + "  ·  " + _pdf_short(directory))
    return _page(title, items, note=note, stack="push")


def _pdf_ask_or_run(state):
    """Collect the next answer the tool wants, or do the work."""
    tool = _pdf_tool_by_label(state.get("tool", "")) or {}
    answers = list(state.get("answers") or [])
    wanted = int(tool.get("asks") or 0)

    if len(answers) < wanted:
        label = tool.get("label", "")
        step = len(answers)
        prompts = {
            "Rotate": [("Rotate by", "90, 180 or 270", False)],
            "Extract page range": [("Keep which pages?", "2-5 · 1,3,7 · 2-z", False)],
            "Delete pages": [("Delete which pages?", "2-5 · 1,3,7 · 2-z", False)],
            "Protect with password": [("New password", "", True),
                                      ("Confirm password", "type it again", True)],
            "Remove password": [("Password", "the one that opens it", True)],
            "Watermark": [("Watermark text", "drawn across every page", False)],
            "OCR": [("Language", "tesseract code, e.g. eng", False)],
            "Resize image": [("New size", "50% · 800x600 · 1920x", False)],
        }
        chosen = None
        for key, value in prompts.items():
            if key in label:
                chosen = value
                break
        title, placeholder, secret = (chosen[step] if chosen and step < len(chosen)
                                      else ("Value", "", False))
        return _prompt(title, "ans", prompt=placeholder, secret=secret, stack="push")

    files = list(state.get("picked") or [])
    if not files:
        return _message("iLovePDF", "No file chosen.")

    env = dict(os.environ)
    # Set even when empty: the toolkit installs its non-interactive prompt
    # overrides on the variable being PRESENT, so an unset one would drop it
    # back into rofi — which is the whole thing being removed here.
    env["ILOVEPDF_ANSWERS"] = "\n".join(answers)
    try:
        out = subprocess.run([_PDF, "--exec", state.get("tool", ""), *files],
                             capture_output=True, text=True, timeout=900, env=env)
    except subprocess.TimeoutExpired:
        return _message("iLovePDF", "Timed out. OCR on a long scan can take "
                                    "minutes — it is still running.")
    except OSError as error:
        return _message("iLovePDF", str(error))

    _pdf_state({"tool": "", "picked": [], "answers": [], "dir": ""})

    if out.returncode == 2:
        return _message("iLovePDF", "Cancelled.")
    if out.returncode != 0:
        # The toolkit reports its own failures through notify-send, which is
        # where its detail is. Repeating a bare exit code here would be less
        # information, not more.
        return _message("iLovePDF",
                        "That did not work. The reason is in the "
                        "notification — usually a missing dependency, an "
                        "encrypted file, or a page range outside the file.")
    produced = out.stdout.strip().splitlines()
    where = produced[-1] if produced else ""
    return _message("Done", _pdf_short(where) if where else "Finished.")


def ilovepdf_run(item_id, text=""):
    state = _pdf_state()

    if item_id.startswith("tool:"):
        label = item_id[5:]
        state = _pdf_state({"tool": label, "picked": [], "answers": [], "dir": ""})
        return _pdf_browser(state)

    if item_id.startswith("dir:"):
        state = _pdf_state({"dir": item_id[4:]})
        return _pdf_browser(state, note="")

    if item_id.startswith("tog:"):
        path = item_id[4:]
        picked = list(state.get("picked") or [])
        # Toggling OFF removes it from the order too, so the numbers stay a
        # contiguous 1..n rather than developing gaps you cannot see.
        if path in picked:
            picked.remove(path)
        else:
            picked.append(path)
        state = _pdf_state({"picked": picked})
        # `replace`, not `push`: ticking four files must not leave four
        # copies of this page on the stack for Escape to walk back out of.
        page = _pdf_browser(state)
        page["stack"] = "replace"
        return page

    if item_id.startswith("file:"):
        state = _pdf_state({"picked": [item_id[5:]]})
        return _pdf_ask_or_run(state)

    if item_id == "go":
        return _pdf_ask_or_run(state)

    if item_id == "ans":
        answers = list(state.get("answers") or [])
        answers.append(text)
        state = _pdf_state({"answers": answers})
        return _pdf_ask_or_run(state)

    return _message("iLovePDF", "Unknown step.")


# ------------------------------------------------------------------ bars --
#
#  "Which shape do you want" — the bar chooser. Asked for as "a way or keymap
#  or something to click and ask which shape do you want, A or B, as a popup
#  for the island and as rofi for the qtile".
#
#  This is the ISLAND half. The rofi half is AtiScriptsV1/bar-chooser, and
#  bar-action picks between them by the current mode, so one key gives you the
#  chooser in whichever shell is up.
#
#  Three shapes, not two, because the qtile-style bar genuinely has two forms:
#  its 28 px top bar of chips and its 40 px bottom "normal user" bar. That is
#  qtile's own $mod SHIFT Z distinction and it belongs in the same list.
#
#  Everything here goes through bar-switch and the topbar's IPC rather than
#  writing ~/.cache/bar-mode directly: bar-switch owns the ordering rule that
#  no path may leave the session without a bar, and duplicating that here
#  would be a second owner of the one thing that must not go wrong.

BAR_STATE = os.path.join(HOME, ".cache", "bar-mode")
TOPBAR_POS = os.path.join(HOME, ".cache", "topbar-position")


def _bar_current():
    def read(path, default):
        try:
            with open(path) as fh:
                return fh.read().strip() or default
        except OSError:
            return default
    return read(BAR_STATE, "island"), read(TOPBAR_POS, "top")


def bars_list():
    mode, pos = _bar_current()
    def mark(active):
        return "  \u2713 current" if active else ""
    return _page("Which bar?", [
        {"id": "island",
         "label": "Island",
         "detail": "the capsule that becomes a panel" + mark(mode == "island")},
        {"id": "top",
         "label": "Topbar \u2014 top",
         "detail": "qtile's 28 px bar of chips"
                   + mark(mode == "native" and pos == "top")},
        {"id": "bottom",
         "label": "Topbar \u2014 bottom",
         "detail": "qtile's 40 px normal-user bar, with launchers"
                   + mark(mode == "native" and pos == "bottom")},
    ], note="The island and the topbar are separate shells and only one runs "
            "at a time. Keys follow whichever is up: rofi under the topbar, "
            "panels under the island.")


def bars_run(item_id):
    if item_id == "island":
        _spawn_sh("bar-switch island")
        return None
    if item_id in ("top", "bottom"):
        # Position FIRST, so the bar comes up already in the requested shape
        # rather than appearing and then moving. The IPC is a no-op while the
        # topbar is down, which is exactly when the file write is what counts.
        _spawn_sh(
            # %%s, not %s: this string is itself %-formatted below, and
            # printf's own placeholder was being eaten as a format slot —
            # "TypeError: not enough arguments for format string", raised only
            # on the two rows that reach this branch.
            "printf '%%s\\n' %s > %s; "
            "qs -p ~/.config/quickshell/topbar ipc call topbar %s >/dev/null 2>&1; "
            "bar-switch native"
            % (shlex.quote(item_id), shlex.quote(TOPBAR_POS), shlex.quote(item_id)))
        return None
    raise ValueError("unknown bar %s" % item_id)


MENUS = {
    "windows": (windows_list, windows_run),
    "processes": (processes_list, processes_run),
    "workspaces": (workspaces_list, workspaces_run),
    # --- ported from the rofi/dm-* menus. See each function's note for what
    #     was dropped and why; nothing here changes the original scripts,
    #     which the qtile session still uses unchanged.
    "documents": (documents_list, documents_run),
    "man": (man_list, man_run),
    "notes": (notes_list, notes_run),
    "brightness": (brightness_list, brightness_run),
    "clipboard": (clipboard_list, clipboard_run),
    # --- the second pass: the menus that needed the page stack or the
    #     prompt mode. See each function's note for what it dropped.
    "screenshot": (screenshot_list, screenshot_run),
    "record": (record_list, record_run),
    "bars": (bars_list, bars_run),
    "confedit": (confedit_list, confedit_run),
    "spellcheck": (spellcheck_list, spellcheck_run),
    "translate": (translate_list, translate_run),
    "pass": (pass_list, pass_run),
    "todo": (todo_list, todo_run),
    "shared": (shared_list, shared_run),
    "youtube": (youtube_list, youtube_run),
    # --- the third pass: a wizard, ported by moving its PROMPTS rather than
    #     its logic. See the note above `anki`.
    "anki": (anki_list, anki_run),
    # The last of the rofi chord's keys to come off rofi. See the note
    # above ilovepdf_list for why "multi-select cannot be expressed in
    # this protocol" turned out to be wrong.
    "ilovepdf": (ilovepdf_list, ilovepdf_run),
    "hub": (hub_list, hub_run),
}

#  STILL SPAWNED BY THE ROFI CHORD, ON PURPOSE
#  -------------------------------------------
#  rofi_ilovepdf ($mod P, V) is the one key in this chord that still opens a
#  rofi window, and the reason is not its length. It is a FILE MANAGER: it
#  walks directories, and `order_files` selects SEVERAL files and orders them
#  so that merge has an order to merge in. This protocol carries exactly one
#  id back per page, so multi-select cannot be expressed at all — porting it
#  means either building selection state into PickerLayer.qml or shipping a
#  PDF toolkit that has lost merge. Neither is worth it for a menu that ends
#  by opening a file manager anyway.
#
#  Outside the chord, `phone_screen` ($mod SHIFT F6) and `theme-toggle`
#  ($mod P, SHIFT C) also stay on rofi, each for a reason recorded at its
#  bind in binds.conf / submaps.conf: both must keep working with this shell
#  down, which is precisely when they are reached for.


def _call_run(function, item_id, text):
    """Call a run handler, passing the typed text only if it takes one.

    The alternative — giving every handler a `text=""` it ignores — was
    rejected because the signature is the documentation: `windows_run(id)`
    says on its face that closing a window cannot involve typing, and a
    uniform two-argument signature would take that away from all eleven
    handlers to serve the four that prompt.
    """
    import inspect
    if len(inspect.signature(function).parameters) >= 2:
        return function(item_id, text)
    return function(item_id)


def main(argv):
    if len(argv) >= 3 and argv[1] == "--list":
        entry = MENUS.get(argv[2])
        if entry is None:
            json.dump({"title": "", "items": [], "error": "unknown menu %s" % argv[2]},
                      sys.stdout)
        else:
            try:
                json.dump(entry[0](), sys.stdout)
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                json.dump({"title": argv[2], "items": [], "error": str(error)},
                          sys.stdout)
        sys.stdout.write("\n")
        return 0

    if len(argv) >= 4 and argv[1] == "--run":
        entry = MENUS.get(argv[2])
        if entry is None:
            json.dump({"ok": False, "error": "unknown menu %s" % argv[2]}, sys.stdout)
            sys.stdout.write("\n")
            return 1
        # argv[4] is the typed text, and it is ONE argument however many
        # spaces it holds. The panel sends it as a single argv element, which
        # is the same discipline the IPC layer needs and for the same reason:
        # anything that splits on whitespace loses a sentence.
        text = argv[4] if len(argv) >= 5 else ""
        try:
            page = _call_run(entry[1], argv[3], text)
        except (OSError, ValueError, KeyError, IndexError,
                subprocess.SubprocessError) as error:
            json.dump({"ok": False, "error": str(error)}, sys.stdout)
            sys.stdout.write("\n")
            return 1
        result = {"ok": True}
        if isinstance(page, dict):
            result["page"] = page
        json.dump(result, sys.stdout)
        sys.stdout.write("\n")
        return 0

    sys.stderr.write("usage: island-picker.py --list <menu> "
                     "| --run <menu> <id> [text]\n"
                     "menus: %s\n" % ", ".join(sorted(MENUS)))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
