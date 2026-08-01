"""Display (xrandr) picker popup.

There is no autorandr on this system and arandr is a GTK window you have to
reach for with the mouse, so this is the keyboard path to the five things
anyone actually does with a second monitor: internal only, external only,
mirror, extend left, extend right -- plus resolution, refresh rate, primary
and rotation for the cases the presets don't cover.

The traps this file exists to work around:

* **A bad mode blanks the screen, and you cannot see the popup to undo it.**
  Every change that could do that is applied with a countdown: the previous
  configuration is captured as a complete xrandr command line first, and it
  is re-applied automatically unless you confirm with `y`. Auto-revert
  rather than a confirm-to-apply prompt precisely because the failure mode
  is "you can no longer see anything to press".
* **`reconfigure_screens()` is not enough when the monitor COUNT changes.**
  config.py builds its `screens` list once, at config-load time, from
  `_monitor_count()`. reconfigure_screens() re-lays-out the Screen objects
  that already exist; it does not create new ones. So plugging in a second
  monitor and calling it leaves the new output with no bar at all. A change
  in monitor count therefore goes through `reload_config()`, which re-runs
  init_screens(); geometry-only changes (resolution, position, rotation, at
  a constant count) use the cheaper reconfigure_screens().
* **xrandr's mode list is priority-ordered, and the numbers carry flags.**
  A rate of `59.99*+` means current (`*`) and preferred (`+`); the flags are
  glued to the number with no separator, so a naive float() over the line
  raises on the current mode of every output.
* **`--rate` is only valid alongside `--mode`.** Setting a refresh rate on
  its own is an xrandr usage error, so the mode picker always emits both.

Only modes xrandr itself reported are ever applied -- nothing here composes
a modeline or calls `--newmode`.
"""

import json
import os
import re
import subprocess
import threading
import time

from qtile_extras.popup import PopupRelativeLayout, PopupText
from libqtile.log_utils import logger

from popups._wal_colors import load_colors as _load_wal_colors
from popups._wal_colors import fade_in_popup, fade_out_popup
from popups._wal_colors import _mix, ensure_contrast

# =============================================================================
# GLOBAL STATE
# =============================================================================
_LAYOUT = None
_QTILE = None
_CLOSING = False

# Bumped on every open and close. Worker callbacks and timers carry the value
# they were spawned with and no-op once it no longer matches.
_SESSION = 0

_OUTPUTS = []      # [{name, connected, primary, w, h, x, y, rot, modes, ...}]
_SCREEN = ""       # the "current WxH" line, for the header

_VIEW = "outputs"  # outputs | modes | layouts | arrange
_VIEWS = ("outputs", "modes", "layouts", "arrange")
_LAYOUTS = []      # [{name, path, cmd, outputs, saved}]

# Arrange mode: a pending {name: [x, y]} map being edited with hjkl, plus
# which output is being moved. Nothing is applied until Enter, so a mistake
# costs a keypress rather than a blank screen.
_ARRANGE = None
_ARRANGE_PICK = 0
# How a moved monitor lines up on the axis it is NOT moving along:
# "start" = tops (or left edges) flush, "centre" = middles, "end" = bottoms.
_ALIGN = "start"
_ALIGNMENTS = ("start", "centre", "end")
_INDEX = {v: 0 for v in _VIEWS}
_OFFSET = {v: 0 for v in _VIEWS}

# The output whose modes the modes view is listing.
_MODE_OUTPUT = None

_STATUS = "Ready"
_STATUS_LEVEL = "idle"
_BUSY = False
_BUSY_PHASE = 0

# A change that could blank the screen: the xrandr argv that puts things back,
# plus how many seconds are left before it is applied on its own.
_REVERT_CMD = None
_REVERT_LEFT = 0

_TIMERS = []
_PROC = None
_CANCEL = threading.Event()

# =============================================================================
# CONFIG & STYLING
# =============================================================================
POPUP_W = 940
POPUP_H = 600

FONT = "JetBrainsMono Nerd Font"
ROW_SIZE = 14
HEAD_SIZE = 14
HINT_SIZE = 13
FOOT_SIZE = 14

ROWS_VISIBLE = 17
MAX_NAME_LEN = 26

DETAIL_PAD = "  "
# Measured against the cards, exactly as in AudioPopup: the details card is
# 394px and a cell is 8px at HINT_SIZE, so a 10-cell label leaves 37; the
# footer bar is 874px (109 cells) less the busy sweep and cancel suffix.
DETAIL_VALUE_LEN = 34
STATUS_MAX = 64

REFRESH_INTERVAL = 5
SPIN_INTERVAL = 0.12

# How long a risky change stays provisional. Long enough to notice a black
# screen and wait it out, short enough not to be a nuisance.
CONFIRM_SECONDS = 12

T_QUICK = 5
T_ACTION = 20

# Connector name prefixes that mean "the laptop panel". Used to decide which
# output the layout presets treat as internal.
_INTERNAL_PREFIXES = ("edp", "lvds", "dsi")

_ROTATIONS = ("normal", "left", "inverted", "right")

# Saved arrangements live outside the dotfiles tree on purpose: ~/.config
# here is a stow symlink into the git checkout, and generated per-machine
# state does not belong in a tracked repo. Not ~/.cache either -- a layout
# you named should survive a cache wipe.
LAYOUT_DIR = os.path.expanduser("~/.local/share/qtile/display-layouts")


def _load_colors():
    """The active theme palette, adjusted for text drawn on cards.

    Same correction as the other popups: the shared loader derives `muted`
    against `bg`, but this popup paints on `surface`, which is already 7% of
    the way to `fg` -- enough to put muted labels under 3:1 on every preset.
    """
    base = _load_wal_colors()
    base["line"] = _mix(base["bg"], base["fg"], 0.22)
    base["surface"] = _mix(base["bg"], base["fg"], 0.07)
    base["surface_alt"] = _mix(base["bg"], base["fg"], 0.14)

    base["highlight_bg"] = base["blue"]
    base["highlight_fg"] = base["bg"]

    surface, fg = base["surface"], base["fg"]
    for key in ("muted", "green", "red", "blue", "purple"):
        base[key] = ensure_contrast(base[key], surface, fg, minimum=3.0)

    return base


COLORS = _load_colors()

ICON_MONITOR = "\U000f0379"    # 󰍹
ICON_LAPTOP = "\U000f0322"     # 󰌢
ICON_OFF = "\U000f0377"        # 󰍷
ICON_MODE = "\U000f035f"       # 󰍟
ICON_SAVED = "\U000f0193"      # 󰆓  -- saved arrangements


# =============================================================================
# PARSING
# =============================================================================
# The rotation token sits between the geometry and the capabilities paren.
# It is matched before the literal "(", so the "normal left inverted right"
# *inside* the parens can never be mistaken for it.
_OUT_RE = re.compile(
    r"^(?P<name>\S+)\s+(?P<status>connected|disconnected)"
    r"(?P<primary>\s+primary)?"
    r"(?:\s+(?P<w>\d+)x(?P<h>\d+)\+(?P<x>-?\d+)\+(?P<y>-?\d+))?"
    r"(?P<rot>\s+(?:normal|left|inverted|right))?"
    # Reflection is spelled out in words and only present when set:
    # "X axis", "Y axis", "X and Y axis". It sits between the rotation and
    # the capabilities paren, so it has to be consumed here or the paren
    # anchor below stops matching on a reflected output.
    r"(?P<reflect>\s+(?:X and Y axis|X axis|Y axis))?"
    r"(?:\s+\()"
)

_REFLECT_WORDS = {
    "": "normal",
    "X axis": "x",
    "Y axis": "y",
    "X and Y axis": "xy",
}
_REFLECTS = ("normal", "x", "y", "xy")
_MODE_RE = re.compile(r"^\s+(?P<res>\d+x\d+)\s+(?P<rates>.+?)\s*$")
# "59.99*+" -- the flags are glued to the number with no separator.
_RATE_RE = re.compile(r"(?P<rate>\d+\.\d+)(?P<flags>[*+]*)")


def esc(text):
    """Escape text for Pango markup.

    Connector names are tame, but xrandr error text is not -- it quotes the
    argument it did not like, and a stray "<" would make pango drop the
    whole footer line rather than the one character.
    """
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fit(text, width):
    text = str(text)
    if len(text) > width:
        text = text[: width - 1] + "…"
    return f"{text:<{width}}"


def clip(text, width):
    """Truncate with an ellipsis, WITHOUT padding -- see AudioPopup.clip."""
    text = str(text)
    return text[: width - 1] + "…" if len(text) > width else text


def parse_xrandr(text):
    """(outputs, screen line) from `xrandr --query` output."""
    outputs = []
    screen = ""
    current = None

    for line in (text or "").splitlines():
        if line.startswith("Screen "):
            match = re.search(r"current\s+(\d+)\s*x\s*(\d+)", line)
            if match:
                screen = f"{match.group(1)}x{match.group(2)}"
            continue

        if not line.startswith((" ", "\t")):
            match = _OUT_RE.match(line)
            if not match:
                continue
            g = match.groupdict()
            current = {
                "name": g["name"],
                "connected": g["status"] == "connected",
                "primary": bool(g["primary"]),
                "w": int(g["w"]) if g["w"] else 0,
                "h": int(g["h"]) if g["h"] else 0,
                "x": int(g["x"]) if g["x"] else 0,
                "y": int(g["y"]) if g["y"] else 0,
                "rot": (g["rot"] or "normal").strip(),
                "reflect": _REFLECT_WORDS.get(
                    (g["reflect"] or "").strip(), "normal"
                ),
                "modes": [],       # [{res, rate, current, preferred}]
                "cur_rate": None,
            }
            outputs.append(current)
            continue

        # Indented: a mode line belonging to the output above.
        if current is None:
            continue
        match = _MODE_RE.match(line)
        if not match:
            continue
        res = match.group("res")
        for rate_match in _RATE_RE.finditer(match.group("rates")):
            flags = rate_match.group("flags")
            entry = {
                "res": res,
                "rate": rate_match.group("rate"),
                "current": "*" in flags,
                "preferred": "+" in flags,
            }
            current["modes"].append(entry)
            if entry["current"]:
                current["cur_rate"] = entry["rate"]

    return outputs, screen


def query_outputs():
    ok, out = run(["xrandr", "--query"], T_QUICK)
    if not ok:
        return [], "", out
    outputs, screen = parse_xrandr(out)
    return outputs, screen, ""


# =============================================================================
# SMALL HELPERS
# =============================================================================
def run(cmd, timeout=T_QUICK, track=False):
    """Run a command, returning (ok, output). Never raises."""
    global _PROC

    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
    except FileNotFoundError:
        return False, f"{cmd[0]} not found"
    except Exception as e:
        logger.warning("DisplayPopup: %s failed: %s", cmd[0], e)
        return False, str(e)

    if track:
        _PROC = proc

    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode == 0, (out or "").strip()
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.communicate(timeout=5)
        except Exception:
            pass
        return False, "timed out"
    except Exception as e:
        logger.warning("DisplayPopup: %s failed: %s", cmd[0], e)
        return False, str(e)
    finally:
        if track:
            _PROC = None


def on_ui(session, fn):
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        try:
            fn()
        except Exception as e:
            logger.exception("DisplayPopup UI callback failed: %s", e)

    _QTILE.call_soon_threadsafe(_guarded)


def in_thread(fn, *args):
    threading.Thread(target=fn, args=args, daemon=True).start()


def add_timer(delay, session, fn):
    if _QTILE is None:
        return

    def _guarded():
        if session != _SESSION or _LAYOUT is None:
            return
        fn()

    _TIMERS.append(_QTILE.call_later(delay, _guarded))


def cancel_timers():
    for timer in _TIMERS:
        try:
            timer.cancel()
        except Exception:
            pass
    _TIMERS.clear()


def set_status(msg, level="idle"):
    global _STATUS, _STATUS_LEVEL
    _STATUS, _STATUS_LEVEL = msg, level


def is_internal(name):
    return (name or "").lower().startswith(_INTERNAL_PREFIXES)


def connected():
    return [o for o in _OUTPUTS if o["connected"]]


def active():
    """Connected outputs that are actually switched on (have a geometry)."""
    return [o for o in _OUTPUTS if o["connected"] and o["w"]]


def internal_output():
    return next((o for o in connected() if is_internal(o["name"])), None)


def external_output(prefer=None):
    """The external monitor a preset should act on.

    `prefer` (the selected row) wins when it is an external monitor, so with
    three outputs the presets act on the one you are pointing at rather than
    on whichever xrandr happens to list first.
    """
    if prefer is not None and prefer["connected"] and not is_internal(prefer["name"]):
        return prefer
    return next((o for o in connected() if not is_internal(o["name"])), None)


# =============================================================================
# VIEW / SELECTION
# =============================================================================
def current_items():
    if _VIEW == "arrange":
        # The arrange view draws a canvas, not rows -- but the cursor helpers
        # still need a list, and the live outputs are what Tab walks.
        return arrange_outputs()
    if _VIEW == "outputs":
        return _OUTPUTS
    if _VIEW == "modes":
        return _MODE_OUTPUT["modes"] if _MODE_OUTPUT else []
    if _VIEW == "layouts":
        return _LAYOUTS
    return []


def selected():
    items = current_items()
    idx = _INDEX.get(_VIEW, 0)
    if 0 <= idx < len(items):
        return items[idx]
    return None


def selected_output():
    """The output row, whichever view is showing."""
    if _VIEW == "modes":
        return _MODE_OUTPUT
    if _VIEW == "arrange":
        live = arrange_outputs()
        return live[_ARRANGE_PICK % len(live)] if live else None
    return selected()


def _item_key(item):
    if item is None:
        return None
    if "name" in item:
        return ("out", item["name"])
    return ("mode", item.get("res"), item.get("rate"))


def output_icon(out):
    if not out["connected"]:
        return ICON_OFF
    if is_internal(out["name"]):
        return ICON_LAPTOP
    return ICON_MONITOR


# =============================================================================
# RENDERING
# =============================================================================
def _empty_list(message):
    lines = []
    for row in range(ROWS_VISIBLE):
        lines.append(
            f'<span foreground="{COLORS["muted"]}">  {esc(message)}</span>'
            if row == ROWS_VISIBLE // 2 else ""
        )
    return "\n".join(lines)


def render_list():
    """The list card: always exactly ROWS_VISIBLE lines, uniform cell counts."""
    if _VIEW == "arrange":
        # The canvas gets the whole list card here: this is the view where
        # the picture IS the interface, so it is drawn at the size that
        # makes a three-monitor arrangement readable.
        canvas = render_canvas(cols=54, rows=11).split("\n")
        live = arrange_outputs()
        picked = live[_ARRANGE_PICK % len(live)]["name"] if live else "—"
        head = (
            f'<span foreground="{COLORS["muted"]}">  moving </span>'
            f'<span foreground="{COLORS["highlight_bg"]}" weight="bold">'
            f'{esc(picked)}</span>'
        )
        lines = [head, ""] + ["  " + line for line in canvas]
        # Pad to a constant height so the card never reflows as monitors move.
        while len(lines) < ROWS_VISIBLE:
            lines.append("")
        return "\n".join(lines[:ROWS_VISIBLE])

    items = current_items()
    if not items:
        return _empty_list({
            "modes": "No modes for this output",
            "layouts": "No saved layouts — press s to save this one",
        }.get(_VIEW, "No outputs found"))

    pad = f'<span foreground="{COLORS["surface"]}"> </span>'
    index, offset = _INDEX.get(_VIEW, 0), _OFFSET.get(_VIEW, 0)
    lines = []

    for row in range(ROWS_VISIBLE):
        idx = offset + row
        if idx >= len(items):
            lines.append("")
            continue

        item = items[idx]

        if _VIEW == "layouts":
            # A layout matching the outputs that are live right now is the
            # one you probably want, so it is flagged rather than buried.
            here = sorted(item["outputs"]) == sorted(o["name"] for o in active())
            body = (
                f" {ICON_SAVED} {esc(fit(item['name'], 20))} "
                f"{esc(fit(', '.join(item['outputs']), 16))} "
                f"{fit('fits now' if here else '', 9)} "
            )
            highlight, strong = idx == index, here
        elif _VIEW == "modes":
            tag = "current" if item["current"] else (
                "preferred" if item["preferred"] else ""
            )
            body = (
                f" {ICON_MODE} {esc(fit(item['res'], 12))} "
                f"{esc(fit(item['rate'] + ' Hz', 10))} "
                f"{fit(tag, 10)} "
            )
            highlight, strong = idx == index, item["current"]
        else:
            if not item["connected"]:
                state = "disconnected"
            elif not item["w"]:
                state = "off"
            else:
                state = f"{item['w']}x{item['h']}+{item['x']}+{item['y']}"
            flag = "primary" if item["primary"] else ""
            body = (
                f" {output_icon(item)} {esc(fit(item['name'], 10))} "
                f"{esc(fit(state, 20))} {fit(flag, 8)} "
            )
            highlight = idx == index
            strong = item["connected"] and bool(item["w"])

        if highlight:
            lines.append(
                f"{pad}"
                f'<span background="{COLORS["highlight_bg"]}" '
                f'foreground="{COLORS["highlight_fg"]}" weight="bold">{body}</span>'
            )
        elif strong:
            lines.append(
                f'{pad}<span foreground="{COLORS["green"]}" weight="bold">{body}</span>'
            )
        elif _VIEW == "outputs" and not item["connected"]:
            lines.append(f'{pad}<span foreground="{COLORS["muted"]}">{body}</span>')
        else:
            lines.append(f'{pad}<span foreground="{COLORS["fg"]}">{body}</span>')

    return "\n".join(lines)


# =============================================================================
# ARRANGE MODE
# =============================================================================
def arrange_outputs():
    """The outputs being arranged, in a stable order."""
    return [o for o in active()]


def start_arrange():
    """a: edit the monitor positions with hjkl.

    The keyboard answer to arandr's drag-and-drop. Positions are edited in a
    scratch map and only handed to xrandr on Enter, so moving a screen the
    wrong way is free.
    """
    global _ARRANGE, _ARRANGE_PICK

    if _VIEW == "arrange":
        cancel_arrange()
        return

    live = arrange_outputs()
    if len(live) < 2:
        set_status("Arranging needs two active outputs", "idle")
        update()
        return

    _ARRANGE = {o["name"]: [o["x"], o["y"]] for o in live}
    # Start on whichever output the cursor was already on, if it is live.
    current = (selected_output() or {}).get("name")
    _ARRANGE_PICK = next(
        (i for i, o in enumerate(live) if o["name"] == current), 0
    )
    set_view("arrange")
    set_status("hjkl to move · Tab to pick · Enter to apply", "idle")
    update()


def cycle_align():
    """=: change how a moved monitor lines up across the move axis.

    Re-snaps the picked monitor immediately so the choice is visible rather
    than only taking effect on the next move.
    """
    global _ALIGN
    if _VIEW != "arrange" or not _ARRANGE:
        return
    _ALIGN = _ALIGNMENTS[(_ALIGNMENTS.index(_ALIGN) + 1) % len(_ALIGNMENTS)]
    label = {"start": "tops flush", "centre": "centres aligned",
             "end": "bottoms flush"}[_ALIGN]
    set_status(f"Align: {label}", "idle")
    update()


def cancel_arrange():
    """Leave arrange mode without applying anything."""
    global _ARRANGE
    _ARRANGE = None
    set_view("outputs")
    set_status("Arrange cancelled", "idle")
    update()


def arrange_pick(step):
    """Tab: choose which monitor hjkl moves."""
    global _ARRANGE_PICK
    if _VIEW != "arrange":
        return
    live = arrange_outputs()
    if not live:
        return
    _ARRANGE_PICK = (_ARRANGE_PICK + step) % len(live)
    update()


def _normalise(positions, sizes):
    """Shift everything so the top-left of the desktop sits at 0,0.

    X refuses a screen with a negative origin, and qtile lays its bars out
    against the resulting geometry, so a layout that drifts left of zero is
    not a cosmetic problem.
    """
    min_x = min(p[0] for p in positions.values())
    min_y = min(p[1] for p in positions.values())
    for name in positions:
        positions[name][0] -= min_x
        positions[name][1] -= min_y


def arrange_move(direction):
    """hjkl: snap the picked monitor to the far side of its nearest neighbour.

    Edge-to-edge rather than free pixel movement: xrandr will happily place
    monitors with gaps or overlaps between them, and both are miserable --
    a gap swallows the mouse, an overlap duplicates part of the desktop.
    Snapping means every arrangement this can produce is a sane one.
    """
    global _ARRANGE

    if _VIEW != "arrange" or not _ARRANGE:
        return

    live = arrange_outputs()
    if len(live) < 2:
        return
    picked = live[_ARRANGE_PICK % len(live)]
    others = [o for o in live if o["name"] != picked["name"]]
    if not others:
        return

    px, py = _ARRANGE[picked["name"]]

    # Nearest neighbour by centre distance, so with three or more screens
    # the move happens against the one you are visually next to.
    def centre(out):
        x, y = _ARRANGE[out["name"]]
        return (x + out["w"] / 2, y + out["h"] / 2)

    cx, cy = px + picked["w"] / 2, py + picked["h"] / 2
    ref = min(
        others,
        key=lambda o: (centre(o)[0] - cx) ** 2 + (centre(o)[1] - cy) ** 2,
    )
    rx, ry = _ARRANGE[ref["name"]]

    # Cross-axis alignment. Top-aligned-only was the one thing arandr could
    # do that this could not: put a 768px laptop beside a 1080px monitor and
    # their tops line up, leaving 312px of dead space along the bottom that
    # the pointer falls into. `=` cycles start / centre / end.
    def cross(pos, ref_size, own_size):
        if _ALIGN == "centre":
            return pos + (ref_size - own_size) // 2
        if _ALIGN == "end":
            return pos + ref_size - own_size
        return pos

    if direction == "left":
        target = [rx - picked["w"], cross(ry, ref["h"], picked["h"])]
    elif direction == "right":
        target = [rx + ref["w"], cross(ry, ref["h"], picked["h"])]
    elif direction == "up":
        target = [cross(rx, ref["w"], picked["w"]), ry - picked["h"]]
    else:
        target = [cross(rx, ref["w"], picked["w"]), ry + ref["h"]]

    # Snapping past the NEAREST neighbour can drop the monitor straight on
    # top of a third one -- with three screens in a row, moving the left one
    # "right of" the middle lands it exactly where the right one already is.
    # Keep sliding in the same direction, one occupied slot at a time, until
    # the target is clear. Bounded by the monitor count, so it always ends.
    def collides(box_x, box_y, other):
        ox, oy = _ARRANGE[other["name"]]
        return (box_x < ox + other["w"] and ox < box_x + picked["w"]
                and box_y < oy + other["h"] and oy < box_y + picked["h"])

    # Whatever it finally comes to rest against is what the status line must
    # name -- reporting `ref` was wrong the moment a collision pushed the
    # monitor past it onto a different neighbour.
    landed_against = ref
    for _ in range(len(live) + 1):
        hit = next((o for o in others if collides(target[0], target[1], o)), None)
        if hit is None:
            break
        landed_against = hit
        hx, hy = _ARRANGE[hit["name"]]
        if direction == "left":
            target = [hx - picked["w"], target[1]]
        elif direction == "right":
            target = [hx + hit["w"], target[1]]
        elif direction == "up":
            target = [target[0], hy - picked["h"]]
        else:
            target = [target[0], hy + hit["h"]]

    if target == [px, py]:
        # Already at that end of the row: doing nothing while announcing a
        # move is worse than saying plainly that there is nowhere to go.
        edge = {"left": "leftmost", "right": "rightmost",
                "up": "at the top", "down": "at the bottom"}[direction]
        set_status(f"{picked['name']} is already {edge}", "idle")
        update()
        return

    _ARRANGE[picked["name"]] = target
    _normalise(_ARRANGE, {o["name"]: (o["w"], o["h"]) for o in live})
    phrase = {"left": "left of", "right": "right of",
              "up": "above", "down": "below"}[direction]
    set_status(
        f"{picked['name']} {phrase} {landed_against['name']}"
        f" · Enter to apply", "idle"
    )
    update()


def apply_arrange():
    """Enter: hand the edited positions to xrandr."""
    global _ARRANGE

    if _VIEW != "arrange" or not _ARRANGE:
        return

    live = arrange_outputs()
    cmd = ["xrandr"]
    for out in live:
        x, y = _ARRANGE[out["name"]]
        cmd += [
            "--output", out["name"],
            "--mode", f"{out['w']}x{out['h']}",
            "--pos", f"{x}x{y}",
            "--rotate", out["rot"] or "normal",
            "--reflect", out.get("reflect") or "normal",
        ]
        if out["cur_rate"]:
            cmd += ["--rate", out["cur_rate"]]
        if out["primary"]:
            cmd += ["--primary"]

    _ARRANGE = None
    set_view("outputs")
    apply_xrandr(cmd, "Applying arrangement…")


def render_canvas(cols=44, rows=9):
    """A scaled map of where the monitors physically sit.

    This is the one thing arandr has that a list cannot express: with two
    screens the question is never "what resolution" but "which side is the
    external on, and are their tops aligned". Rectangles are laid out from
    the real xrandr geometry into a character grid, so the picture is the
    actual arrangement rather than an idealised left/right sketch.

    A monospace cell is roughly twice as tall as it is wide, so the vertical
    scale is halved against the horizontal one -- without that correction a
    side-by-side pair of 16:9 monitors renders as two tall columns.
    """
    live = active()
    if not live:
        return f'<span foreground="{COLORS["muted"]}">no active outputs</span>'

    # In arrange mode the picture must show the pending edit, not the state
    # xrandr still has -- otherwise hjkl appears to do nothing.
    def pos(out):
        if _ARRANGE and out["name"] in _ARRANGE:
            return _ARRANGE[out["name"]]
        return [out["x"], out["y"]]

    min_x = min(pos(o)[0] for o in live)
    min_y = min(pos(o)[1] for o in live)
    max_x = max(pos(o)[0] + o["w"] for o in live)
    max_y = max(pos(o)[1] + o["h"] for o in live)
    span_x = max(1, max_x - min_x)
    span_y = max(1, max_y - min_y)

    # One scale for both axes keeps relative sizes honest; the /2 is the
    # character aspect-ratio correction.
    scale = min((cols - 1) / span_x, (rows - 1) / (span_y / 2.0))

    grid = [[" "] * cols for _ in range(rows)]
    marks = {}

    for out in live:
        ox, oy = pos(out)
        x0 = int(round((ox - min_x) * scale))
        y0 = int(round((oy - min_y) * scale / 2.0))
        w = max(3, int(round(out["w"] * scale)))
        h = max(2, int(round(out["h"] * scale / 2.0)))
        x1 = min(cols - 1, x0 + w - 1)
        y1 = min(rows - 1, y0 + h - 1)
        if x0 >= cols or y0 >= rows:
            continue

        for x in range(x0, x1 + 1):
            grid[y0][x] = "─"
            grid[y1][x] = "─"
        for y in range(y0, y1 + 1):
            grid[y][x0] = "│"
            grid[y][x1] = "│"
        grid[y0][x0], grid[y0][x1] = "┌", "┐"
        grid[y1][x0], grid[y1][x1] = "└", "┘"

        # Label centred inside the box, clipped to what fits between the
        # borders so a long connector name cannot punch through the frame.
        label = out["name"]
        inner = x1 - x0 - 1
        if inner >= 3:
            label = label[:inner]
            ly = (y0 + y1) // 2
            lx = x0 + 1 + max(0, (inner - len(label)) // 2)
            for i, ch in enumerate(label):
                if lx + i < x1:
                    grid[ly][lx + i] = ch
            marks[(ly, lx, len(label))] = out

    if _VIEW == "arrange" and live:
        selected_name = live[_ARRANGE_PICK % len(live)]["name"]
    else:
        selected_name = (selected_output() or {}).get("name")
    lines = []
    for y, row in enumerate(grid):
        # Colour each row by whichever output owns its label, so the
        # selected monitor is obvious in the picture too.
        owner = next((o for (ly, _, _), o in marks.items() if ly == y), None)
        if owner is not None and owner["name"] == selected_name:
            colour = COLORS["highlight_bg"]
        elif owner is not None and owner["primary"]:
            colour = COLORS["green"]
        else:
            colour = COLORS["line"]
        lines.append(f'<span foreground="{colour}">{esc("".join(row).rstrip())}</span>')

    return "\n".join(lines)


def render_details():
    """Right-hand panel describing the selected row."""

    def field(label, value, colour=None):
        return (
            f'<span foreground="{COLORS["muted"]}">{label:<10}</span>'
            f'<span foreground="{colour or COLORS["fg"]}">'
            f'{esc(clip(value, DETAIL_VALUE_LEN))}</span>'
        )

    if _VIEW == "layouts":
        item = selected()
        if item is None:
            return (f'{DETAIL_PAD}<span foreground="{COLORS["muted"]}">'
                    f'No saved layouts</span>')
        here = sorted(item["outputs"]) == sorted(o["name"] for o in active())
        rows = [
            f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
            f'{esc(fit(item["name"], MAX_NAME_LEN).strip())}</span>',
            "",
            field("saved", item["saved"] or "—"),
            field("outputs", ", ".join(item["outputs"]) or "—"),
            field("matches", "yes — these outputs are live" if here else "not now",
                  COLORS["green"] if here else COLORS["muted"]),
            "",
            f'{"":<10}',
        ]
        # The exact command, wrapped by hand: it is the whole content of a
        # layout, and being able to read it is what makes this trustworthy.
        words, line = item["cmd"][1:], ""
        wrapped = []
        for word in words:
            if len(line) + len(word) + 1 > DETAIL_VALUE_LEN + 8:
                wrapped.append(line)
                line = word
            else:
                line = f"{line} {word}".strip()
        if line:
            wrapped.append(line)
        for w in wrapped[:8]:
            rows.append(f'<span foreground="{COLORS["muted"]}">{esc(w)}</span>')
        return "\n".join([""] + [DETAIL_PAD + r if r else r for r in rows])

    out = selected_output()
    if out is None:
        return f'{DETAIL_PAD}<span foreground="{COLORS["muted"]}">No output selected</span>'

    if not out["connected"]:
        state, colour = "disconnected", COLORS["muted"]
    elif not out["w"]:
        state, colour = "connected, off", COLORS["red"]
    else:
        state, colour = "active", COLORS["green"]

    rows = [
        f'<span foreground="{COLORS["fg"]}" weight="bold" size="large">'
        f'{esc(fit(out["name"], MAX_NAME_LEN).strip())}</span>',
        "",
        field("state", state, colour),
        field("primary", "yes" if out["primary"] else "no",
              COLORS["green"] if out["primary"] else COLORS["fg"]),
    ]

    if out["w"]:
        rows.append(field("mode", f"{out['w']}x{out['h']}"))
        rows.append(field("refresh", f"{out['cur_rate']} Hz" if out["cur_rate"] else "—"))
        # While arranging, this must be the PENDING position -- showing the
        # applied one put "+3840+312" next to a canvas that had already
        # moved the monitor to 0,0.
        if _ARRANGE and out["name"] in _ARRANGE:
            px, py = _ARRANGE[out["name"]]
            rows.append(field("position", f"+{px}+{py}  (pending)", COLORS["blue"]))
        else:
            rows.append(field("position", f"+{out['x']}+{out['y']}"))
        rows.append(field("rotation", out["rot"]))
        if out.get("reflect", "normal") != "normal":
            rows.append(field("reflect", out["reflect"], COLORS["blue"]))

    resolutions = []
    for mode in out["modes"]:
        if mode["res"] not in resolutions:
            resolutions.append(mode["res"])
    rows.append("")
    rows.append(field("modes", f"{len(out['modes'])} ({len(resolutions)} sizes)"))

    body = [DETAIL_PAD + r if r else r for r in rows]

    # The arrangement map goes last, where it has the width to be legible.
    #
    # The per-resolution preview that used to sit here is gone, and the
    # canvas is 5 rows rather than 7, because the card is 344px -- 19 lines
    # at HINT_SIZE -- and the fully-populated panel (rotation AND reflect on
    # a three-monitor setup) measured 417px with both. Enter opens the full
    # mode list anyway, so the preview was the duplicated half; the map
    # answers a question no list here can.
    # Not in arrange mode: the list card is already showing the same map at
    # four times the size, and the miniature only competes with it.
    if active() and _VIEW != "arrange":
        body.append(f'{DETAIL_PAD}<span foreground="{COLORS["muted"]}">layout</span>')
        body += [DETAIL_PAD + line for line in render_canvas(cols=42, rows=5).split("\n")]

    return "\n".join([""] + body)


def render_header():
    live = len(active())
    return (
        f'<span size="x-large" weight="bold" foreground="{COLORS["fg"]}">'
        f"{ICON_MONITOR}  Displays</span>\n"
        f'<span size="small" foreground="{COLORS["muted"]}">'
        f'{esc(f"{live} active · {len(connected())} connected")}</span>'
    )


def render_header_badge():
    text = _SCREEN or "unknown"
    colour = COLORS["green"] if active() else COLORS["red"]
    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{colour}" '
        f'weight="bold"> {ICON_MONITOR} {esc(clip(text, 24))} </span>'
    )


def _key(label):
    return (
        f'<span background="{COLORS["surface_alt"]}" foreground="{COLORS["fg"]}" '
        f'weight="bold"> {label} </span>'
    )


def render_hints():
    """The hint bar -- measured against its 874px, not guessed."""
    gap = f'<span foreground="{COLORS["line"]}"> </span>'
    # This bar is 874px and nothing clips a control -- an overflowing one
    # spills over the cards below. Measured every time it changes: the
    # obvious labels came to 904px, and adding the arrange chip took it to
    # 952px. "laptop"/"primary" are abbreviated, and the Esc chip is gone
    # rather than mangling more words -- Escape behaves identically in every
    # popup here, and the tabs row directly underneath still says "q close".
    # The placement keys are NOT here. "hlud place" fitted the width but told
    # you nothing -- four letters welded together is not a hint. They moved to
    # the tabs row below, which had 314px spare and can spell them out, and
    # the space that bought is spent un-abbreviating everything else.
    pairs = [
        ("jk", "move"),
        ("↵", "modes"),
        ("i", "laptop"),
        ("e", "external"),
        ("m", "mirror"),
        ("a", "arrange"),
        ("p", "primary"),
        ("t", "rotate"),
        ("f", "flip"),
        ("v", "saved"),
    ]
    return gap.join(
        f'{_key(k)}<span foreground="{COLORS["muted"]}"> {desc}</span>'
        for k, desc in pairs
    )


def render_tabs():
    """Which view is showing, plus the layout presets as a reminder."""
    if _VIEW == "modes" and _MODE_OUTPUT:
        label = f"Modes — {_MODE_OUTPUT['name']}"
    elif _VIEW == "layouts":
        label = "Saved layouts"
    elif _VIEW == "arrange":
        label = "Arrange"
    else:
        label = "Outputs"

    extra = {
        # The modes view gets its own line: the placement keys are
        # meaningless while picking a resolution, and its label ("Modes —
        # DisplayPort-1") is long enough that the outputs string overflowed
        # the bar by 100px.
        "modes": "   ↵ apply   Backspace back   r refresh   q close",
        "layouts": "   ↵ restore   s save   x delete   v back",
        "arrange": ("   hjkl move   Tab pick   = align: "
                    + {"start": "tops", "centre": "centres",
                       "end": "bottoms"}[_ALIGN]
                    + "   ↵ apply   Esc cancel"),
    }.get(_VIEW,
          "   put external:  h left   l right   u above   d below"
          "      o on/off   s save   r refresh   q close")
    return (
        f'<span background="{COLORS["highlight_bg"]}" '
        f'foreground="{COLORS["highlight_fg"]}" weight="bold"> {esc(clip(label, 30))} </span>'
        f'<span foreground="{COLORS["muted"]}">{esc(extra)}</span>'
    )


def render_footer():
    colour = {
        "busy": COLORS["blue"],
        "ok": COLORS["green"],
        "error": COLORS["red"],
    }.get(_STATUS_LEVEL, COLORS["muted"])

    prefix = suffix = ""

    if _REVERT_CMD is not None:
        # The countdown owns the footer while it runs: it is the only thing
        # on screen telling you the change is provisional, and on a screen
        # that just went black it is also the thing you are waiting out.
        return (
            f'<span foreground="{COLORS["red"]}" weight="bold">'
            f'  Keep this? </span>'
            f'{_key("y")}<span foreground="{COLORS["muted"]}"> keep </span>'
            f'{_key("c")}<span foreground="{COLORS["muted"]}"> revert now </span>'
            f'<span foreground="{COLORS["fg"]}" weight="bold">'
            f'   reverting in {_REVERT_LEFT}s</span>'
        )

    if _BUSY:
        track, window = 24, 4
        pos = _BUSY_PHASE % (track + window)
        cells = [
            (COLORS["blue"] if pos - window < i <= pos else COLORS["line"])
            for i in range(track)
        ]
        prefix = "".join(f'<span foreground="{c}">━</span>' for c in cells) + "   "
        suffix = f'<span foreground="{COLORS["muted"]}">   ·   c to stop</span>'

    return (
        f'{prefix}<span foreground="{colour}" weight="bold">'
        f'{esc(clip(_STATUS, STATUS_MAX))}</span>{suffix}'
    )


def update_footer():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(footer=render_footer())


def update():
    if _LAYOUT is None:
        return
    _LAYOUT.update_controls(
        header=render_header(),
        badge=render_header_badge(),
        tabs=render_tabs(),
        outputs=render_list(),
        details=render_details(),
        footer=render_footer(),
    )


# =============================================================================
# REFRESH
# =============================================================================
def refresh(loud=False, reason=None):
    global _BUSY

    session = _SESSION
    if loud:
        _BUSY = True
        set_status(reason or "Reading outputs…", "busy")
        spin(session)
        update()

    def worker():
        outputs, screen, err = query_outputs()

        def apply():
            global _OUTPUTS, _SCREEN, _BUSY, _MODE_OUTPUT

            keep = _item_key(selected())
            _OUTPUTS, _SCREEN = outputs, screen

            # Re-bind the modes view to the refreshed output, or leave it if
            # that output was unplugged while we were looking at it.
            if _MODE_OUTPUT is not None:
                _MODE_OUTPUT = next(
                    (o for o in _OUTPUTS if o["name"] == _MODE_OUTPUT["name"]), None
                )
                if _MODE_OUTPUT is None and _VIEW == "modes":
                    set_view("outputs")

            items = current_items()
            if keep is not None:
                match = next(
                    (i for i, it in enumerate(items) if _item_key(it) == keep), None
                )
                if match is not None:
                    _INDEX[_VIEW] = match
            clamp_index()
            ensure_visible()

            if loud:
                _BUSY = False
                if err:
                    set_status(_xrandr_error(err), "error")
                else:
                    set_status(
                        f"{len(active())} active · {len(connected())} connected", "ok"
                    )
            update()

        on_ui(session, apply)

    in_thread(worker)


def spin(session):
    def tick():
        global _BUSY_PHASE
        if not _BUSY:
            return
        _BUSY_PHASE += 1
        update_footer()
        add_timer(SPIN_INTERVAL, session, tick)

    add_timer(SPIN_INTERVAL, session, tick)


def schedule_refresh(session):
    def tick():
        # Never re-read underneath a pending confirmation: the refresh would
        # move the cursor and repaint the footer the countdown owns.
        if not _BUSY and _REVERT_CMD is None and _ARRANGE is None:
            refresh(loud=False)
        schedule_refresh(session)

    add_timer(REFRESH_INTERVAL, session, tick)


# =============================================================================
# APPLYING
# =============================================================================
def _xrandr_error(output):
    for line in (output or "").splitlines():
        line = line.strip()
        if line:
            return line[:70]
    return "xrandr failed"


def restore_command():
    """A complete xrandr argv that reproduces the CURRENT configuration.

    Built from what xrandr just reported rather than remembered from the
    last apply, so it is correct even if something else (a hotplug, a
    display manager) changed the layout underneath the popup.
    """
    cmd = ["xrandr"]
    for out in _OUTPUTS:
        if not out["connected"]:
            continue
        cmd += ["--output", out["name"]]
        if not out["w"]:
            cmd += ["--off"]
            continue
        cmd += [
            "--mode", f"{out['w']}x{out['h']}",
            "--pos", f"{out['x']}x{out['y']}",
            "--rotate", out["rot"] or "normal",
            # Reflection has to be restated too: without it, reverting a
            # change would silently un-flip a screen that was flipped
            # before the popup ever touched it.
            "--reflect", out.get("reflect") or "normal",
        ]
        if out["cur_rate"]:
            # --rate is only accepted next to --mode, which it always is here.
            cmd += ["--rate", out["cur_rate"]]
        if out["primary"]:
            cmd += ["--primary"]
    return cmd


def load_layouts():
    """Every saved arrangement, newest first.

    A layout is just the xrandr argv that reproduces it, which is the same
    thing restore_command() builds -- so saving is "remember the current
    restore command" and applying is "run it".
    """
    out = []
    try:
        names = sorted(os.listdir(LAYOUT_DIR))
    except OSError:
        return out

    for filename in names:
        if not filename.endswith(".json"):
            continue
        path = os.path.join(LAYOUT_DIR, filename)
        try:
            with open(path) as f:
                data = json.load(f)
            cmd = data["cmd"]
            if not isinstance(cmd, list) or not cmd or cmd[0] != "xrandr":
                continue
            out.append({
                "name": data.get("name") or filename[:-5],
                "path": path,
                "cmd": [str(c) for c in cmd],
                "outputs": data.get("outputs") or [],
                "saved": data.get("saved") or "",
            })
        except Exception as e:
            logger.warning("DisplayPopup: bad layout %s: %s", path, e)
    out.sort(key=lambda item: item["saved"], reverse=True)
    return out


def save_layout(name):
    """Write the current arrangement out under `name`."""
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", name).strip("-") or "layout"
    path = os.path.join(LAYOUT_DIR, f"{slug}.json")
    payload = {
        "name": name,
        "cmd": restore_command(),
        "outputs": [o["name"] for o in active()],
        "saved": time.strftime("%Y-%m-%d %H:%M"),
    }
    os.makedirs(LAYOUT_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp, path)   # atomic: never leave a half-written layout behind
    return path


def _monitor_count():
    """Post-RandR monitor count -- the same question config.py asks.

    The count line is *searched for*, not assumed to be the first line:
    run() folds stderr into stdout, and xrandr is happy to emit warnings
    ("Failed to get size of gamma for output ...") ahead of its real output.
    Taking line 0 blindly parsed the warning instead, returned None, and
    made every count change look like "unknown" -- which falls back to
    reconfigure_screens() and leaves a newly-plugged monitor with no bar.
    Caught by running against a real two-monitor X server.
    """
    ok, out = run(["xrandr", "--listmonitors"], T_QUICK)
    if not ok:
        return None
    for line in (out or "").splitlines():
        line = line.strip()
        if not line.startswith("Monitors:"):
            continue
        try:
            return int(line.split(":", 1)[1].strip())
        except (ValueError, IndexError):
            return None
    return None


def _resync_qtile(before, after):
    """Tell qtile the screens moved.

    reconfigure_screens() re-lays-out the Screen objects that exist. It
    cannot create one, and config.py fixes how many exist when it builds
    `screens` from _monitor_count() at load time -- so a change in the
    number of monitors needs a full reload_config() or the new output gets
    no bar at all.
    """
    if _QTILE is None:
        return
    try:
        if before is not None and after is not None and before != after:
            _QTILE.reload_config()
        else:
            _QTILE.reconfigure_screens()
    except Exception as e:
        logger.warning("DisplayPopup: could not resync qtile screens: %s", e)


def apply_xrandr(cmd, message, risky=True):
    """Run an xrandr command, then resync qtile and arm the revert countdown.

    `risky` is False only for changes that cannot cost you the ability to
    see the screen (setting primary), which are applied outright.
    """
    global _BUSY, _REVERT_CMD, _REVERT_LEFT

    if _BUSY or _REVERT_CMD is not None:
        return

    session = _SESSION
    revert = restore_command() if risky else None
    before = _monitor_count()

    _CANCEL.clear()
    _BUSY = True
    set_status(message, "busy")
    spin(session)
    update()

    def worker():
        ok, out = run(cmd, T_ACTION, track=True)
        if _CANCEL.is_set():
            return
        after = _monitor_count() if ok else before

        def done():
            global _BUSY, _REVERT_CMD, _REVERT_LEFT
            _BUSY = False
            if not ok:
                set_status(_xrandr_error(out), "error")
                update()
                refresh(loud=False)
                return

            _resync_qtile(before, after)

            if revert is None:
                set_status(message.rstrip("…") + " — done", "ok")
                update()
                refresh(loud=False)
                return

            _REVERT_CMD = revert
            _REVERT_LEFT = CONFIRM_SECONDS
            update()
            countdown(session)
            refresh(loud=False)

        on_ui(session, done)

    in_thread(worker)


def countdown(session):
    """Tick the revert timer once a second until it is answered or expires."""
    def tick():
        global _REVERT_LEFT
        if _REVERT_CMD is None:
            return
        _REVERT_LEFT -= 1
        if _REVERT_LEFT <= 0:
            do_revert("No answer — reverted")
            return
        update_footer()
        add_timer(1, session, tick)

    add_timer(1, session, tick)


def do_revert(message):
    """Put the previous configuration back."""
    global _REVERT_CMD, _REVERT_LEFT

    cmd, _REVERT_CMD = _REVERT_CMD, None
    _REVERT_LEFT = 0
    if cmd is None:
        return

    session = _SESSION
    before = _monitor_count()

    def worker():
        ok, out = run(cmd, T_ACTION)
        after = _monitor_count() if ok else before

        # The screen resync is NOT routed through on_ui: close() reverts a
        # pending change and then immediately bumps the session, which would
        # drop this callback and leave qtile laid out for a configuration
        # that no longer exists. The revert must resync whether or not the
        # popup outlives it.
        if _QTILE is not None:
            _QTILE.call_soon_threadsafe(lambda: _resync_qtile(before, after))

        def done():
            set_status(message if ok else f"Revert failed: {_xrandr_error(out)}",
                       "idle" if ok else "error")
            update()
            refresh(loud=False)

        on_ui(session, done)

    in_thread(worker)


def keep():
    """y: accept a provisional change."""
    global _REVERT_CMD, _REVERT_LEFT
    if _REVERT_CMD is None:
        return
    _REVERT_CMD = None
    _REVERT_LEFT = 0
    set_status("Kept", "ok")
    update()
    refresh(loud=False)


def cancel():
    """c: revert a pending change, or abort an xrandr that is hanging."""
    global _BUSY

    if _REVERT_CMD is not None:
        do_revert("Reverted")
        return

    if not _BUSY:
        set_status("Nothing to cancel", "idle")
        update()
        return

    _CANCEL.set()
    proc = _PROC
    if proc is not None:
        try:
            proc.kill()
        except Exception:
            pass

    _BUSY = False
    set_status("Cancelled", "idle")
    update()
    refresh(loud=False)


# =============================================================================
# ACTIONS
# =============================================================================
def _preset(kind):
    """Build the xrandr argv for a one-key layout, or (None, reason)."""
    internal = internal_output()
    external = external_output(selected_output())

    if kind == "internal":
        if internal is None:
            return None, "No internal panel found"
        cmd = ["xrandr", "--output", internal["name"], "--auto", "--primary"]
        for out in connected():
            if out["name"] != internal["name"]:
                cmd += ["--output", out["name"], "--off"]
        return cmd, f"Laptop only ({internal['name']})…"

    if kind == "external":
        if external is None:
            return None, "No external monitor connected"
        cmd = ["xrandr", "--output", external["name"], "--auto", "--primary"]
        for out in connected():
            if out["name"] != external["name"]:
                cmd += ["--output", out["name"], "--off"]
        return cmd, f"External only ({external['name']})…"

    if internal is None or external is None:
        return None, "Needs the laptop panel and one external monitor"

    if kind == "mirror":
        return (
            ["xrandr",
             "--output", internal["name"], "--auto", "--primary",
             "--output", external["name"], "--auto",
             "--same-as", internal["name"]],
            f"Mirroring onto {external['name']}…",
        )

    side = {
        "left": "--left-of",
        "right": "--right-of",
        "above": "--above",
        "below": "--below",
    }[kind]
    return (
        ["xrandr",
         "--output", internal["name"], "--auto", "--primary",
         "--output", external["name"], "--auto", side, internal["name"]],
        f"{external['name']} {kind} {internal['name']}…",
    )


def preset(kind):
    cmd, message = _preset(kind)
    if cmd is None:
        set_status(message, "error")
        update()
        return
    apply_xrandr(cmd, message)


def show_layouts():
    """v: the saved-arrangement list."""
    global _LAYOUTS
    if _VIEW == "layouts":
        set_view("outputs")
        return
    _LAYOUTS = load_layouts()
    set_view("layouts")
    update()


def save_current():
    """s: remember this arrangement under a name typed into rofi.

    rofi rather than an in-popup text field for the same reason the wifi
    popup delegates passwords to it: a PopupText control cannot do text
    entry, clipboard paste or keyboard layouts.
    """
    global _LAYOUTS

    if _BUSY or _REVERT_CMD is not None:
        return
    if not active():
        set_status("Nothing active to save", "error")
        update()
        return

    session = _SESSION
    default = "-".join(o["name"] for o in active())

    def worker():
        try:
            proc = subprocess.run(
                ["rofi", "-dmenu", "-l", "0", "-p", "Layout name",
                 "-theme-str",
                 "window { width: 42%; }"
                 " inputbar { children: [prompt, entry]; padding: 12px;"
                 " spacing: 12px; }"],
                input=default, stdout=subprocess.PIPE, text=True, timeout=180,
            )
            name = proc.stdout.strip() if proc.returncode == 0 else ""
        except Exception as e:
            logger.warning("DisplayPopup: rofi prompt failed: %s", e)
            return
        if not name:
            return

        try:
            save_layout(name)
            message, level = f"Saved layout “{name}”", "ok"
        except Exception as e:
            logger.warning("DisplayPopup: could not save layout: %s", e)
            message, level = f"Could not save: {e}", "error"

        def done():
            global _LAYOUTS
            _LAYOUTS = load_layouts()
            set_status(message, level)
            update()

        on_ui(session, done)

    in_thread(worker)


def delete_layout():
    """x (in the layouts view): forget a saved arrangement."""
    global _LAYOUTS

    if _VIEW != "layouts":
        return
    item = selected()
    if item is None:
        return
    try:
        os.remove(item["path"])
        set_status(f"Deleted “{item['name']}”", "idle")
    except OSError as e:
        set_status(f"Could not delete: {e}", "error")
    _LAYOUTS = load_layouts()
    clamp_index()
    ensure_visible()
    update()


def activate():
    """Enter: open the mode list, apply a mode, or restore a saved layout."""
    if _VIEW == "arrange":
        apply_arrange()
        return

    if _VIEW == "layouts":
        item = selected()
        if item is None:
            return
        # Applied through the same countdown as anything else: a layout
        # saved when a monitor was plugged in will blank the screen if it is
        # replayed once that monitor is gone.
        apply_xrandr(list(item["cmd"]), f"Restoring “{item['name']}”…")
        return

    if _VIEW == "outputs":
        show_modes()
        return

    mode = selected()
    out = _MODE_OUTPUT
    if mode is None or out is None:
        return
    apply_xrandr(
        # --rate only alongside --mode; xrandr rejects it on its own.
        ["xrandr", "--output", out["name"],
         "--mode", mode["res"], "--rate", mode["rate"]],
        f"{out['name']} → {mode['res']} @ {mode['rate']}Hz…",
    )


def show_modes():
    """Open the resolution / refresh list for the selected output."""
    global _MODE_OUTPUT

    out = selected()
    if out is None:
        return
    if not out["connected"]:
        set_status(f"{out['name']} is not connected", "idle")
        update()
        return
    if not out["modes"]:
        set_status(f"{out['name']} reports no modes", "idle")
        update()
        return

    _MODE_OUTPUT = out
    set_view("modes")
    current = next((i for i, m in enumerate(out["modes"]) if m["current"]), 0)
    _INDEX["modes"] = current
    ensure_visible()
    update()


def toggle_output():
    """o: switch the selected output on (at its preferred mode) or off."""
    out = selected_output()
    if out is None:
        return
    if not out["connected"]:
        set_status(f"{out['name']} is not connected", "idle")
        update()
        return

    if out["w"]:
        if len(active()) <= 1:
            # Turning off the only live output leaves nothing to look at,
            # and no way to see the popup that would turn it back on.
            set_status("That is the only active output", "error")
            update()
            return
        apply_xrandr(["xrandr", "--output", out["name"], "--off"],
                     f"Switching {out['name']} off…")
    else:
        apply_xrandr(["xrandr", "--output", out["name"], "--auto"],
                     f"Switching {out['name']} on…")


def set_primary():
    """p: make the selected output primary.

    Not risky: it moves where new windows and the primary-only bar land, and
    cannot leave the screen blank, so it skips the countdown.
    """
    out = selected_output()
    if out is None:
        return
    if not out["connected"] or not out["w"]:
        set_status(f"{out['name']} is not active", "idle")
        update()
        return
    apply_xrandr(["xrandr", "--output", out["name"], "--primary"],
                 f"{out['name']} is primary…", risky=False)


def reflect():
    """f: cycle the selected output's reflection (arandr's Outputs ▸ Reflect).

    Genuinely useful for a projector bouncing off a mirror, and impossible to
    reach from a keyboard before this.
    """
    out = selected_output()
    if out is None:
        return
    if not out["connected"] or not out["w"]:
        set_status(f"{out['name']} is not active", "idle")
        update()
        return
    try:
        nxt = _REFLECTS[(_REFLECTS.index(out.get("reflect", "normal")) + 1)
                        % len(_REFLECTS)]
    except ValueError:
        nxt = "normal"
    apply_xrandr(["xrandr", "--output", out["name"], "--reflect", nxt],
                 f"Reflecting {out['name']} {nxt}…")


def rotate():
    """t: cycle the selected output's rotation."""
    out = selected_output()
    if out is None:
        return
    if not out["connected"] or not out["w"]:
        set_status(f"{out['name']} is not active", "idle")
        update()
        return
    try:
        nxt = _ROTATIONS[(_ROTATIONS.index(out["rot"]) + 1) % len(_ROTATIONS)]
    except ValueError:
        nxt = "normal"
    apply_xrandr(["xrandr", "--output", out["name"], "--rotate", nxt],
                 f"Rotating {out['name']} {nxt}…")


# =============================================================================
# NAVIGATION
# =============================================================================
def clamp_index():
    items = current_items()
    _INDEX[_VIEW] = max(0, min(_INDEX.get(_VIEW, 0), max(0, len(items) - 1)))


def ensure_visible():
    items = current_items()
    index = _INDEX.get(_VIEW, 0)
    offset = _OFFSET.get(_VIEW, 0)
    if index < offset:
        offset = index
    elif index >= offset + ROWS_VISIBLE:
        offset = index - ROWS_VISIBLE + 1
    _OFFSET[_VIEW] = max(0, min(offset, max(0, len(items) - ROWS_VISIBLE)))


def move(step):
    if _LAYOUT is None or not current_items():
        return
    _INDEX[_VIEW] = max(0, min(len(current_items()) - 1, _INDEX.get(_VIEW, 0) + step))
    ensure_visible()
    update()


def jump(where):
    if _LAYOUT is None or not current_items():
        return
    _INDEX[_VIEW] = 0 if where == "top" else len(current_items()) - 1
    ensure_visible()
    update()


def set_view(view):
    global _VIEW, _MODE_OUTPUT
    if view not in _VIEWS:
        return
    if view == "modes" and _MODE_OUTPUT is None:
        return
    if view == "arrange" and _ARRANGE is None:
        return
    if view != "modes":
        _MODE_OUTPUT = None
    _VIEW = view
    clamp_index()
    ensure_visible()
    if _LAYOUT is not None:
        update()


# =============================================================================
# KEY DISPATCH
# =============================================================================
# hjkl mean different things depending on the view, and the chord binds one
# key to one function -- so the branching lives here rather than being
# duplicated across four lambdas in config.py.
def nav(step):
    """j / k: walk the list, or move the picked monitor vertically."""
    if _VIEW == "arrange":
        arrange_move("down" if step > 0 else "up")
        return
    move(step)


def place(direction):
    """h / l: place the external monitor, or move the picked one sideways."""
    if _VIEW == "arrange":
        arrange_move(direction)
        return
    preset(direction)


def pick_next(step=1):
    """Tab: choose which monitor arrange mode moves."""
    if _VIEW == "arrange":
        arrange_pick(step)


def back():
    """Leave a sub-view without leaving the popup."""
    if _VIEW == "arrange":
        cancel_arrange()
        return
    if _VIEW in ("modes", "layouts"):
        set_view("outputs")


# =============================================================================
# POPUP CONTROL
# =============================================================================
def show(qtile):
    global _LAYOUT, _QTILE, _SESSION, _VIEW, _MODE_OUTPUT, _OUTPUTS, _LAYOUTS
    global _ARRANGE
    global _BUSY, _BUSY_PHASE, _REVERT_CMD, _REVERT_LEFT

    _QTILE = qtile
    if _LAYOUT is not None or _CLOSING:
        return

    COLORS.update(_load_colors())

    _SESSION += 1
    session = _SESSION
    _VIEW = "outputs"
    _MODE_OUTPUT = None
    _ARRANGE = None
    _OUTPUTS = []
    _LAYOUTS = load_layouts()
    _BUSY = False
    _BUSY_PHASE = 0
    _REVERT_CMD = None
    _REVERT_LEFT = 0
    for view in _VIEWS:
        _INDEX[view] = _OFFSET[view] = 0
    set_status("Reading outputs…", "busy")

    head_y, head_h = 24 / POPUP_H, 54 / POPUP_H
    hint_y, hint_h = 88 / POPUP_H, 30 / POPUP_H
    tabs_y, tabs_h = 126 / POPUP_H, 26 / POPUP_H
    body_y, body_h = 162 / POPUP_H, 350 / POPUP_H
    foot_y, foot_h = 524 / POPUP_H, 54 / POPUP_H

    controls = [
        PopupText(
            text=render_header(), markup=True, font=FONT, fontsize=HEAD_SIZE,
            pos_x=0.03, pos_y=head_y, width=0.45, height=head_h,
            h_align="left", v_align="middle", name="header",
        ),
        PopupText(
            text=render_header_badge(), markup=True, font=FONT, fontsize=HINT_SIZE,
            pos_x=0.5, pos_y=head_y, width=0.47, height=head_h,
            h_align="right", v_align="middle", name="badge",
        ),
        PopupText(
            text=render_hints(), markup=True, font=FONT, fontsize=HINT_SIZE,
            background=COLORS["surface"], highlight_radius=8,
            pos_x=0.03, pos_y=hint_y, width=0.94, height=hint_h,
            h_align="center", v_align="middle", name="hints",
        ),
        PopupText(
            text=render_tabs(), markup=True, font=FONT, fontsize=HINT_SIZE,
            pos_x=0.03, pos_y=tabs_y, width=0.94, height=tabs_h,
            h_align="center", v_align="middle", name="tabs",
        ),
        PopupText(
            text=render_list(), markup=True, font=FONT, fontsize=ROW_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.03, pos_y=body_y, width=0.499, height=body_h,
            h_align="left", v_align="middle", name="outputs",
        ),
        PopupText(
            text=render_details(), markup=True, font=FONT, fontsize=HINT_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.5452, pos_y=body_y, width=0.4238, height=body_h,
            h_align="left", v_align="top", name="details",
        ),
        PopupText(
            text=render_footer(), markup=True, font=FONT, fontsize=FOOT_SIZE,
            background=COLORS["surface"], highlight_radius=10,
            pos_x=0.03, pos_y=foot_y, width=0.94, height=foot_h,
            h_align="center", v_align="middle", name="footer",
        ),
    ]

    _LAYOUT = PopupRelativeLayout(
        qtile,
        width=POPUP_W,
        height=POPUP_H,
        background=COLORS["bg"] + "F2",
        border=COLORS["surface_alt"],
        border_width=2,
        close_on_click=False,
        controls=controls,
    )

    _LAYOUT.show(centered=True)
    fade_in_popup(_LAYOUT, duration=0.24, steps=16)

    refresh(loud=True, reason="Reading outputs…")
    schedule_refresh(session)


def close(qtile=None):
    global _LAYOUT, _CLOSING, _SESSION, _BUSY, _MODE_OUTPUT, _ARRANGE

    if _LAYOUT is None or _CLOSING:
        return

    # A provisional change must never outlive the popup: closing with a
    # countdown running would leave a possibly-unusable layout in place with
    # nothing left on screen to revert it.
    if _REVERT_CMD is not None:
        do_revert("Reverted on close")

    layout = _LAYOUT
    _CLOSING = True
    _SESSION += 1
    _BUSY = False
    _MODE_OUTPUT = None
    _ARRANGE = None
    cancel_timers()
    _LAYOUT = None

    def teardown():
        global _CLOSING
        try:
            # kill(), not hide(): hide() only unmaps the X window and leaves
            # the cairo drawer and pango layouts allocated while show()
            # builds a fresh layout every time.
            layout.kill()
        except Exception:
            pass
        _CLOSING = False

    fade_out_popup(layout, teardown)


def toggle(qtile):
    if _CLOSING:
        return
    if _LAYOUT is not None:
        close(qtile)
    else:
        show(qtile)
