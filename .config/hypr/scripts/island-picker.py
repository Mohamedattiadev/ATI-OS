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
#  dm-note's menu is Copy / New / Delete / Quit. Only COPY is here: it is the
#  one that is a list, and it is the one the chord is pressed for. New needs
#  a text field and Delete needs a confirmation, and both are conversations
#  rather than picks — the same reason rofi_pass and dm-spellcheck are not
#  ported. The file is unchanged either way, so dm-note keeps working for
#  the other three.

NOTE_FILE = os.path.expanduser("~/.config/dmscripts/dmnote")


def notes_list():
    try:
        with open(NOTE_FILE) as handle:
            lines = [line.rstrip("\n") for line in handle]
    except OSError:
        return {"title": "Copy note", "items": []}

    items = []
    for line in lines:
        if not line.strip():
            continue
        items.append({"id": line, "label": line, "detail": ""})
    return {"title": "Copy note", "items": items}


def notes_run(item_id):
    # wl-copy and not xclip: this is the Wayland session. The qtile session
    # keeps dm-note, which keeps using cp2cb.
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--", item_id], capture_output=True, timeout=4)
    _notify("Note copied", item_id)


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
            "detail": "current: %d%%" % current if current >= 0 else "",
        })
    return {"title": "Brightness", "items": items}


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
