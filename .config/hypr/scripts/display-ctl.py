#!/usr/bin/env python3
"""display-ctl.py — the output-management backend for the island's display panel.

Replaces qtile's `popups/DisplayPopup.py` (28 bindings), which drove xrandr
and therefore does not survive the move to Wayland at all. This is not a
port of that file's code — none of it could be — but it is a deliberate port
of its *behaviour*, key for key, because the muscle memory is the thing
worth keeping.

WHY THIS EXISTS RATHER THAN nwg-displays / wdisplays
----------------------------------------------------
MIGRATION.md listed both as the interim stand-in and neither is installed,
so until now Hyprland had NO output management whatsoever: no way to change
resolution, scale, rotation or arrangement short of editing monitors.conf
and reloading. This closes that, and it needs no new package — `hyprctl` is
the compositor's own control socket.

The QML side (tide-island-fork/qml/display/DisplayPanel.qml) calls in here
and renders what comes back. All of the knowledge about Hyprland's monitor
syntax lives on this side, where it can be exercised from a shell.

WHAT HYPRLAND DOES DIFFERENTLY FROM XRANDR, AND WHAT THAT COST
-------------------------------------------------------------
* **There is no primary output.** xrandr's `--primary` decided where new
  windows and the primary-only bar landed; Hyprland has no such concept —
  the bar is a Quickshell `Variants` over every screen, and workspaces are
  bound to monitors individually. qtile's `p` binding therefore has nothing
  to do, so it is reassigned to SCALE, which xrandr could not do usefully
  and Wayland very much can. That is the one intentional keymap divergence.

* **Scale must divide the resolution into whole pixels.** Hyprland rejects
  a scale that leaves a fractional logical size — "Invalid scale passed to
  monitor, failed to find a clean divisor" — and it rejects it at apply
  time, not at parse time. 1366x768 at 1.25 is 1092.8 logical pixels wide,
  so it fails. `usable_scales()` below filters the offered list per output
  instead of presenting scales that will be refused.

* **A runtime `monitor` keyword does not persist, and `hyprctl reload`
  silently discards every one of them.** That is a hazard and a safety net
  at the same time. Hazard: an arrangement set up here is gone after the
  next `$mod SHIFT R`. Safety net: `hyprctl reload` is a guaranteed way back
  to monitors.conf, which is why `revert --hard` uses it.

* **Mode strings are exact.** `hyprctl monitors all -j` reports
  availableModes as e.g. "1366x768@59.99Hz"; the keyword wants
  "1366x768@59.99". The trailing "Hz" is stripped here, once, rather than in
  the QML.

THE COUNTDOWN IS NOT DECORATION
------------------------------
qtile's popup applied every risky change provisionally: capture the current
configuration first, apply, and put it back automatically unless confirmed.
That is kept, for the same reason it existed — the failure mode of a bad
mode is "the screen is black and you cannot see the thing that would undo
it", so confirm-to-apply is useless and revert-unless-confirmed is the only
shape that works. The snapshot is taken from what the compositor reports at
that moment, never from what we last asked for, so it is still right if a
hotplug changed things underneath us.

USAGE
-----
    display-ctl.py query
    display-ctl.py snapshot
    display-ctl.py restore <snapshot-json>
    display-ctl.py arrange '{"eDP-1":[0,0],"HDMI-A-1":[1366,0]}'
    display-ctl.py revert-hard
    display-ctl.py set NAME [--mode WxH@R] [--scale S] [--transform N]
                            [--pos XxY] [--mirror NAME|none]
                            [--enable | --disable]
    display-ctl.py rotate NAME | reflect NAME | cycle-scale NAME
    display-ctl.py preset internal|external|mirror|left|right|above|below
    display-ctl.py layouts
    display-ctl.py layout-save NAME | layout-delete NAME | layout-apply NAME

Every subcommand prints one JSON object on stdout and exits 0 even on a
handled failure — the panel needs to render the reason, and a non-zero exit
with a traceback on stderr is invisible to a QML `Process`.
"""

import json
import os
import re
import subprocess
import sys
import time

LAYOUT_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "hypr", "display-layouts",
)

# The rotation cycle, matching qtile's _ROTATIONS. Hyprland encodes rotation
# and flip in ONE integer: 0-3 are 0/90/180/270, and 4-7 are the same four
# with a horizontal flip applied first. So rotating preserves the flip bit
# and reflecting toggles it, which is why neither is a plain +1.
TRANSFORM_NAMES = {
    0: "normal", 1: "90", 2: "180", 3: "270",
    4: "flipped", 5: "flipped-90", 6: "flipped-180", 7: "flipped-270",
}

# Offered scales, filtered per output by usable_scales(). Deliberately short:
# these are the ones that produce a sane desktop, not every value Hyprland
# would technically accept.
SCALE_CHOICES = (1.0, 1.25, 1.333333, 1.5, 1.75, 2.0)

CONFIRM_SECONDS = 12


# ---------------------------------------------------------------------------
# hyprctl plumbing
# ---------------------------------------------------------------------------
def hyprctl(args, timeout=6):
    """Run hyprctl and return (ok, output). Never raises."""
    try:
        proc = subprocess.run(
            ["hyprctl"] + list(args),
            capture_output=True, text=True, timeout=timeout,
        )
    except FileNotFoundError:
        return False, "hyprctl not found"
    except subprocess.TimeoutExpired:
        return False, "hyprctl timed out"
    out = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode == 0, out.strip()


def monitors():
    """Every output the compositor knows about, disabled ones included.

    `hyprctl monitors` alone omits disabled outputs entirely, which would
    make "switch this one back on" unreachable — the row would not be in the
    list. `monitors all` is the one that includes them.
    """
    ok, out = hyprctl(["monitors", "all", "-j"])
    if not ok:
        return []
    try:
        return json.loads(out)
    except (ValueError, TypeError):
        return []


def apply_keyword(spec):
    """Apply one `monitor = ...` spec. Returns (ok, message)."""
    ok, out = hyprctl(["keyword", "monitor", spec], timeout=12)
    if ok and "ok" in out.lower():
        return True, ""
    return False, (out or "hyprctl refused the monitor keyword")


# ---------------------------------------------------------------------------
# reading the current state
# ---------------------------------------------------------------------------
def mode_string(text):
    """"1366x768@59.99Hz" -> "1366x768@59.99".

    The keyword parser does not accept the Hz suffix that the JSON reports,
    and the error it gives for one ("invalid resolution") does not hint that
    the two spellings differ.
    """
    return re.sub(r"[Hh]z\s*$", "", str(text or "")).strip()


def usable_scales(width, height):
    """Scales that divide this resolution into whole logical pixels.

    Hyprland checks this itself and refuses anything else at apply time, so
    offering an unusable scale would present a control that always errors.
    The tolerance is Hyprland's own: it accepts a rounding error under
    1/1000 of a pixel.
    """
    out = []
    for scale in SCALE_CHOICES:
        logical_w = width / scale
        logical_h = height / scale
        if (abs(logical_w - round(logical_w)) < 0.001
                and abs(logical_h - round(logical_h)) < 0.001):
            out.append(round(scale, 6))
    return out or [1.0]


def is_internal(name):
    """eDP/LVDS/DSI are the laptop panel; everything else is external.

    Same test qtile used, and it is a naming convention rather than a
    property the kernel exposes, so it is a heuristic in both places.
    """
    return bool(re.match(r"^(eDP|LVDS|DSI)", str(name or ""), re.I))


def describe(mon):
    """One output, flattened into what the panel actually draws."""
    name = mon.get("name") or ""
    width = int(mon.get("width") or 0)
    height = int(mon.get("height") or 0)
    disabled = bool(mon.get("disabled"))
    transform = int(mon.get("transform") or 0)
    modes = [mode_string(m) for m in (mon.get("availableModes") or [])]
    current = ""
    if width and height and not disabled:
        current = "%dx%d@%.2f" % (width, height, float(mon.get("refreshRate") or 0))

    return {
        "name": name,
        "description": mon.get("description") or "",
        "internal": is_internal(name),
        "enabled": not disabled,
        "width": width,
        "height": height,
        "refresh": round(float(mon.get("refreshRate") or 0), 2),
        "x": int(mon.get("x") or 0),
        "y": int(mon.get("y") or 0),
        "scale": round(float(mon.get("scale") or 1), 6),
        "transform": transform,
        "transformName": TRANSFORM_NAMES.get(transform, str(transform)),
        "flipped": transform >= 4,
        "focused": bool(mon.get("focused")),
        "mirrorOf": mon.get("mirrorOf") or "none",
        "vrr": bool(mon.get("vrr")),
        "currentMode": current,
        "modes": modes,
        "scales": usable_scales(width, height) if width and height else [1.0],
    }


def snapshot_specs():
    """A list of `monitor` specs that reproduces the CURRENT configuration.

    The analogue of qtile's restore_command(), and built the same way and
    for the same reason: read it back out of the compositor now rather than
    remembering what we last asked for, so a hotplug or a reload that
    happened while the panel was open cannot make the revert wrong.
    """
    specs = []
    for mon in monitors():
        name = mon.get("name")
        if not name:
            continue
        if mon.get("disabled"):
            specs.append("%s,disable" % name)
            continue
        spec = "%s,%dx%d@%.2f,%dx%d,%s" % (
            name,
            int(mon.get("width") or 0), int(mon.get("height") or 0),
            float(mon.get("refreshRate") or 60),
            int(mon.get("x") or 0), int(mon.get("y") or 0),
            trim_scale(float(mon.get("scale") or 1)),
        )
        spec += ",transform,%d" % int(mon.get("transform") or 0)
        mirror = mon.get("mirrorOf") or "none"
        if mirror and mirror != "none":
            spec += ",mirror,%s" % mirror
        specs.append(spec)
    return specs


def trim_scale(value):
    """Scale as Hyprland wants it: "1", not "1.0"; "1.5", not "1.500000"."""
    text = ("%.6f" % float(value)).rstrip("0").rstrip(".")
    return text or "1"


# ---------------------------------------------------------------------------
# building a spec for one output
# ---------------------------------------------------------------------------
def find(name):
    for mon in monitors():
        if mon.get("name") == name:
            return mon
    return None


def spec_for(mon, mode=None, scale=None, transform=None,
             pos=None, mirror=None, enable=None):
    """The monitor keyword line for `mon` with the given overrides applied.

    Every field is restated on every apply, never just the one being
    changed. `hyprctl keyword monitor` replaces an output's whole rule
    rather than merging into it, so a spec that omits the position silently
    re-runs auto-placement — which looks like "changing the refresh rate
    moved my monitor", and took a while to recognise as being this.
    """
    name = mon.get("name")

    if enable is False:
        return "%s,disable" % name

    current_mode = "%dx%d@%.2f" % (
        int(mon.get("width") or 0), int(mon.get("height") or 0),
        float(mon.get("refreshRate") or 60),
    )
    if mon.get("disabled") or not mon.get("width"):
        # Coming back from disabled there is no current mode to restate, so
        # fall back to `preferred`, which is what monitors.conf's catch-all
        # gives every output anyway.
        current_mode = "preferred"

    use_mode = mode or current_mode
    use_scale = trim_scale(scale if scale is not None else (mon.get("scale") or 1))
    use_transform = transform if transform is not None else int(mon.get("transform") or 0)
    if pos is not None:
        use_pos = pos
    elif mon.get("disabled"):
        use_pos = "auto"
    else:
        use_pos = "%dx%d" % (int(mon.get("x") or 0), int(mon.get("y") or 0))

    spec = "%s,%s,%s,%s,transform,%d" % (name, use_mode, use_pos, use_scale, use_transform)

    use_mirror = mirror if mirror is not None else (mon.get("mirrorOf") or "none")
    if use_mirror and use_mirror != "none":
        spec += ",mirror,%s" % use_mirror
    return spec


# ---------------------------------------------------------------------------
# saved layouts
# ---------------------------------------------------------------------------
def load_layouts():
    """Every saved arrangement, newest first.

    A layout is the list of monitor specs that reproduces it — the same
    thing snapshot_specs() builds — so saving is "remember the snapshot"
    and applying is "replay it".
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
            with open(path) as handle:
                data = json.load(handle)
            specs = data.get("specs")
            if not isinstance(specs, list) or not specs:
                continue
            out.append({
                "name": data.get("name") or filename[:-5],
                "path": path,
                "specs": [str(s) for s in specs],
                "outputs": data.get("outputs") or [],
                "saved": data.get("saved") or "",
            })
        except (OSError, ValueError):
            # A corrupt layout file is skipped rather than fatal: one bad
            # file must not make the whole list unreadable.
            continue
    out.sort(key=lambda item: item["saved"], reverse=True)
    return out


def slugify(name):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", str(name)).strip("-") or "layout"


def save_layout(name):
    specs = snapshot_specs()
    if not specs:
        return {"ok": False, "status": "nothing to save — no outputs reported"}
    path = os.path.join(LAYOUT_DIR, slugify(name) + ".json")
    payload = {
        "name": name,
        "specs": specs,
        "outputs": [m.get("name") for m in monitors() if not m.get("disabled")],
        "saved": time.strftime("%Y-%m-%d %H:%M"),
    }
    os.makedirs(LAYOUT_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(payload, handle, indent=2)
    # Atomic, so an interrupted save never leaves a half-written layout that
    # load_layouts() would then have to defend against.
    os.replace(tmp, path)
    return {"ok": True, "status": "saved %s" % name, "path": path}


# ---------------------------------------------------------------------------
# presets — qtile's five one-key layouts
# ---------------------------------------------------------------------------
def internal_output(mons):
    for mon in mons:
        if is_internal(mon.get("name")):
            return mon
    return mons[0] if mons else None


def external_output(mons, prefer=None):
    externals = [m for m in mons if not is_internal(m.get("name"))]
    if prefer:
        for mon in externals:
            if mon.get("name") == prefer:
                return mon
    return externals[0] if externals else None


def preset(kind, prefer=None):
    mons = monitors()
    if not mons:
        return {"ok": False, "status": "no outputs reported"}

    internal = internal_output(mons)
    external = external_output(mons, prefer)

    if kind == "internal":
        if internal is None:
            return {"ok": False, "status": "no internal panel found"}
        specs = [spec_for(internal, pos="0x0", mirror="none", enable=True)]
        specs += ["%s,disable" % m.get("name") for m in mons
                  if m.get("name") != internal.get("name")]
        return {"ok": True, "specs": specs,
                "status": "laptop only (%s)" % internal.get("name")}

    if kind == "external":
        if external is None:
            return {"ok": False, "status": "no external monitor connected"}
        specs = [spec_for(external, pos="0x0", mirror="none", enable=True)]
        specs += ["%s,disable" % m.get("name") for m in mons
                  if m.get("name") != external.get("name")]
        return {"ok": True, "specs": specs,
                "status": "external only (%s)" % external.get("name")}

    if internal is None or external is None or internal is external:
        return {"ok": False,
                "status": "needs the laptop panel and one external monitor"}

    if kind == "mirror":
        # Hyprland mirrors by making one output a `mirror` of another rather
        # than by placing them at the same origin, which is xrandr's
        # --same-as. The mirrored output takes the source's framebuffer, so
        # its own mode is largely advisory.
        return {
            "ok": True,
            "specs": [
                spec_for(internal, pos="0x0", mirror="none", enable=True),
                spec_for(external, mirror=internal.get("name"), enable=True),
            ],
            "status": "mirroring onto %s" % external.get("name"),
        }

    # Extend. Positions are computed in LOGICAL pixels — width/scale — not in
    # the physical pixel counts the JSON reports. Getting this wrong on a
    # scaled monitor leaves a gap or an overlap between the two desktops that
    # nothing reports and that you only notice when the pointer sticks.
    iw = int(int(internal.get("width") or 0) / float(internal.get("scale") or 1))
    ih = int(int(internal.get("height") or 0) / float(internal.get("scale") or 1))
    ew = int(int(external.get("width") or 0) / float(external.get("scale") or 1))
    eh = int(int(external.get("height") or 0) / float(external.get("scale") or 1))

    places = {
        "right": ("0x0", "%dx0" % iw),
        "left": ("%dx0" % ew, "0x0"),
        "below": ("0x0", "0x%d" % ih),
        "above": ("0x%d" % eh, "0x0"),
    }
    if kind not in places:
        return {"ok": False, "status": "unknown preset %s" % kind}
    internal_pos, external_pos = places[kind]

    return {
        "ok": True,
        "specs": [
            spec_for(internal, pos=internal_pos, mirror="none", enable=True),
            spec_for(external, pos=external_pos, mirror="none", enable=True),
        ],
        "status": "%s %s %s" % (external.get("name"), kind, internal.get("name")),
    }


# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
def apply_specs(specs):
    """Apply a list of monitor specs, stopping at the first refusal.

    Disables are applied LAST. Ordering matters: turning an output off
    before the one that replaces it is on leaves a moment with no enabled
    output at all, and Hyprland handles that by refusing — so a
    preset that lists the disable first fails for a reason that has nothing
    to do with what you asked for.
    """
    enables = [s for s in specs if not s.endswith(",disable")]
    disables = [s for s in specs if s.endswith(",disable")]
    for spec in enables + disables:
        ok, message = apply_keyword(spec)
        if not ok:
            return False, "%s — %s" % (spec.split(",")[0], message.splitlines()[0])
    return True, ""


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def cmd_query():
    mons = monitors()
    return emit({
        "ok": True,
        "outputs": [describe(m) for m in mons],
        "layouts": load_layouts(),
        "confirmSeconds": CONFIRM_SECONDS,
    })


def cmd_snapshot():
    return emit({"ok": True, "specs": snapshot_specs()})


def cmd_restore(raw):
    try:
        specs = json.loads(raw)
    except (ValueError, TypeError):
        return emit({"ok": False, "status": "restore: not valid JSON"})
    if not isinstance(specs, list) or not specs:
        return emit({"ok": False, "status": "restore: empty snapshot"})
    ok, message = apply_specs([str(s) for s in specs])
    return emit({"ok": ok, "status": "restored" if ok else message})


def cmd_arrange(raw):
    """Apply a whole {name: [x, y]} map in one go.

    Arranging is the one operation that MUST land as a unit. Moving monitors
    one keyword at a time walks through intermediate layouts that overlap,
    and Hyprland reacts to each one — windows and workspaces get shuffled
    twice for a single logical change, and if the second call fails you are
    left in a layout that was never asked for and that the snapshot does not
    describe either.
    """
    try:
        positions = json.loads(raw)
    except (ValueError, TypeError):
        return emit({"ok": False, "status": "arrange: not valid JSON"})
    if not isinstance(positions, dict) or not positions:
        return emit({"ok": False, "status": "arrange: nothing to place"})

    specs = []
    for mon in monitors():
        name = mon.get("name")
        if name in positions and not mon.get("disabled"):
            at = positions[name]
            specs.append(spec_for(mon, pos="%dx%d" % (int(at[0]), int(at[1]))))
    if not specs:
        return emit({"ok": False, "status": "arrange: no matching outputs"})
    ok, message = apply_specs(specs)
    return emit({"ok": ok, "status": message or "arranged"})


def cmd_revert_hard():
    """The last resort: throw away every runtime keyword and re-read the config.

    `hyprctl reload` discards runtime `monitor` keywords wholesale, which is
    normally the annoying half of their being non-persistent and here is
    exactly the escape hatch — it puts monitors.conf back no matter what
    state the panel managed to get the outputs into.
    """
    ok, message = hyprctl(["reload"], timeout=15)
    return emit({"ok": ok,
                 "status": "reloaded monitors.conf" if ok else message})


def parse_set(argv):
    name = argv[0]
    opts = {}
    index = 1
    while index < len(argv):
        flag = argv[index]
        if flag == "--enable":
            opts["enable"] = True
        elif flag == "--disable":
            opts["enable"] = False
        elif flag in ("--mode", "--scale", "--transform", "--pos", "--mirror"):
            index += 1
            if index >= len(argv):
                return name, opts, "%s needs a value" % flag
            opts[flag[2:]] = argv[index]
        else:
            return name, opts, "unknown option %s" % flag
        index += 1
    return name, opts, None


def cmd_set(argv):
    name, opts, error = parse_set(argv)
    if error:
        return emit({"ok": False, "status": error})
    mon = find(name)
    if mon is None:
        return emit({"ok": False, "status": "no output named %s" % name})

    if opts.get("enable") is False and len(
            [m for m in monitors() if not m.get("disabled")]) <= 1:
        # qtile refused this for the reason that matters: turning off the
        # only live output leaves nothing to look at, and no way to see the
        # panel that would turn it back on.
        return emit({"ok": False, "status": "that is the only active output"})

    spec = spec_for(
        mon,
        mode=opts.get("mode"),
        scale=float(opts["scale"]) if "scale" in opts else None,
        transform=int(opts["transform"]) if "transform" in opts else None,
        pos=opts.get("pos"),
        mirror=opts.get("mirror"),
        enable=opts.get("enable"),
    )
    ok, message = apply_specs([spec])
    return emit({"ok": ok, "status": message or "applied", "spec": spec})


def cmd_rotate(name):
    mon = find(name)
    if mon is None:
        return emit({"ok": False, "status": "no output named %s" % name})
    transform = int(mon.get("transform") or 0)
    flip = 4 if transform >= 4 else 0
    nxt = flip + ((transform - flip + 1) % 4)
    ok, message = apply_specs([spec_for(mon, transform=nxt)])
    return emit({"ok": ok,
                 "status": message or ("rotated %s %s"
                                       % (name, TRANSFORM_NAMES.get(nxt, nxt)))})


def cmd_reflect(name):
    mon = find(name)
    if mon is None:
        return emit({"ok": False, "status": "no output named %s" % name})
    transform = int(mon.get("transform") or 0)
    nxt = transform - 4 if transform >= 4 else transform + 4
    ok, message = apply_specs([spec_for(mon, transform=nxt)])
    return emit({"ok": ok,
                 "status": message or ("flipped %s %s"
                                       % (name, TRANSFORM_NAMES.get(nxt, nxt)))})


def cmd_cycle_scale(name):
    mon = find(name)
    if mon is None:
        return emit({"ok": False, "status": "no output named %s" % name})
    choices = usable_scales(int(mon.get("width") or 0), int(mon.get("height") or 0))
    current = round(float(mon.get("scale") or 1), 6)
    try:
        nxt = choices[(choices.index(current) + 1) % len(choices)]
    except ValueError:
        nxt = choices[0]
    ok, message = apply_specs([spec_for(mon, scale=nxt)])
    return emit({"ok": ok,
                 "status": message or ("%s at %sx" % (name, trim_scale(nxt)))})


def cmd_preset(kind, prefer=None):
    result = preset(kind, prefer)
    if not result.get("ok"):
        return emit(result)
    ok, message = apply_specs(result["specs"])
    return emit({"ok": ok, "status": message or result["status"]})


def cmd_layout_apply(name):
    for layout in load_layouts():
        if layout["name"] == name:
            ok, message = apply_specs(layout["specs"])
            return emit({"ok": ok, "status": message or ("applied %s" % name)})
    return emit({"ok": False, "status": "no saved layout named %s" % name})


def cmd_layout_delete(name):
    for layout in load_layouts():
        if layout["name"] == name:
            try:
                os.remove(layout["path"])
            except OSError as error:
                return emit({"ok": False, "status": str(error)})
            return emit({"ok": True, "status": "deleted %s" % name})
    return emit({"ok": False, "status": "no saved layout named %s" % name})


def main(argv):
    if not argv:
        return emit({"ok": False, "status": "no subcommand"})
    command, rest = argv[0], argv[1:]

    if command == "query":
        return cmd_query()
    if command == "snapshot":
        return cmd_snapshot()
    if command == "restore":
        return cmd_restore(rest[0] if rest else "")
    if command == "arrange":
        return cmd_arrange(rest[0] if rest else "")
    if command == "revert-hard":
        return cmd_revert_hard()
    if command == "set":
        return cmd_set(rest) if rest else emit(
            {"ok": False, "status": "set needs an output name"})
    if command in ("rotate", "reflect", "cycle-scale"):
        if not rest:
            return emit({"ok": False, "status": "%s needs an output name" % command})
        return {"rotate": cmd_rotate,
                "reflect": cmd_reflect,
                "cycle-scale": cmd_cycle_scale}[command](rest[0])
    if command == "preset":
        if not rest:
            return emit({"ok": False, "status": "preset needs a kind"})
        return cmd_preset(rest[0], rest[1] if len(rest) > 1 else None)
    if command == "layouts":
        return emit({"ok": True, "layouts": load_layouts()})
    if command == "layout-save":
        return emit(save_layout(rest[0] if rest else "layout"))
    if command == "layout-delete":
        return cmd_layout_delete(rest[0] if rest else "")
    if command == "layout-apply":
        return cmd_layout_apply(rest[0] if rest else "")

    return emit({"ok": False, "status": "unknown subcommand %s" % command})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
