#!/usr/bin/env python3
"""Audio backend for the island's audio panel — the port of qtile's AudioPopup.

The island's control centre already owns ONE thing: a slider on the default
sink. qtile's popup (25 bindings) owned everything else — which output is the
default and dragging the live streams across with it, which microphone is the
default, per-application volume and per-application routing, the card PROFILE
(A2DP vs HSP/HFP, the difference between a headset that sounds good and one
whose microphone works at all), and the output PORT (speakers vs the headphone
jack on one and the same card). None of that had a keyboard path on Hyprland,
and pavucontrol is not installed.

The split mirrors display-ctl.py: everything that knows how PipeWire's pulse
shim spells things lives HERE, where it can be run and read from a shell;
qml/audio/AudioPanel.qml is the keyboard and the pixels. The previous
generation of this feature was 2,200 lines of Python that could only be
exercised by opening a qtile popup.

Every command prints ONE line of JSON on stdout and exits 0 even when the
action failed — `{"ok": false, "status": "..."}`. A non-zero exit with a
message on stderr would be invisible: the caller is a QML Process reading
stdout, and a panel that silently does nothing is exactly the failure this
replaces.

THE TRAPS, all still true against pactl 17.0 / PipeWire 1.6 — carried over
from popups/AudioPopup.py, which found them the hard way:

* **Indices are serials and they move.** A sink's own index changed from 51 to
  249079 during that popup's testing, just from a move-sink-input: the pulse
  shim hands out monotonically increasing serials rather than PulseAudio's
  stable small integers. So sinks, sources and cards are addressed by NAME
  everywhere, and the one place an index is unavoidable (sink-inputs have no
  name) it is re-read in the same pass that consumes it.
* **`monitor_of` is None on every source, including monitors.** The documented
  way to recognise a loopback monitor matches nothing, so an unfiltered list
  shows "Monitor of Built-in Audio" beside the real microphone. Monitors are
  detected by the `.monitor` name suffix AND cross-checked against the sinks'
  own `monitor_source` field.
* **Sinks carry no card reference.** Neither the JSON nor the text output has
  the `Card:` line real PulseAudio emits, so a sink is matched to its card by
  the token their names share (`alsa_card.pci-0000_00_1f.3` ->
  `alsa_output.pci-0000_00_1f.3.analog-stereo`). For a bluez card the shared
  token is the MAC and the same trick works.
* **`profiles` is a dict, not a list** — keyed by profile name. The built-in
  card here advertises 23 and only 5 are available, so unavailable ones are
  dropped unless one of them is the ACTIVE profile.
* **Setting the default sink does not move what is already playing.** Pulse
  routes only NEW streams to it. `default-sink` therefore walks every live
  sink-input with move-sink-input afterwards, which is the entire reason
  qtile's popup existed rather than a `pactl set-default-sink` keybind.

pactl rather than wpctl throughout, deliberately. wpctl drives the hardware
keys (one number on one device, which is all they need) but has no notion of
a card profile, no port list, and addresses everything by WirePlumber node id
— a third numbering that agrees with neither of the two above.
"""

import json
import shutil
import subprocess
import sys

TIMEOUT_QUICK = 5
# A bluez profile switch renegotiates the link and genuinely takes seconds.
TIMEOUT_ACTION = 20

VOLUME_MAX = 150      # what pavucontrol's slider allows; >100% is software gain
VOLUME_UNITY = 100


# ---------------------------------------------------------------------------
# process plumbing
# ---------------------------------------------------------------------------
def run(args, timeout=TIMEOUT_QUICK):
    """Run a command, returning (ok, output). Never raises."""
    try:
        proc = subprocess.run(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=timeout,
        )
    except FileNotFoundError:
        return False, f"{args[0]} not found"
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except Exception as error:                      # pragma: no cover
        return False, str(error)
    return proc.returncode == 0, (proc.stdout or "").strip()


def pactl_json(*args):
    """`pactl -f json ...` decoded, or [] on any failure.

    pactl has been seen to emit a bare `[]` for an empty list and to exit
    non-zero with a message on stderr; both arrive here as an empty list,
    which every caller reads as "nothing connected".
    """
    ok, out = run(["pactl", "-f", "json", *args])
    if not ok or not out:
        return []
    try:
        data = json.loads(out)
    except ValueError:
        return []
    return data if isinstance(data, list) else []


def emit(ok, status, **extra):
    payload = {"ok": bool(ok), "status": status}
    payload.update(extra)
    print(json.dumps(payload))
    return 0


def first_error_line(output):
    """The useful line out of a pactl failure, short enough for a status bar."""
    for line in (output or "").splitlines():
        line = line.strip()
        if line:
            return line[:90]
    return "failed"


# ---------------------------------------------------------------------------
# reading
# ---------------------------------------------------------------------------
def percent(volume):
    """Mean channel volume as an int, from pactl's per-channel volume dict.

    Every channel carries its own `value_percent` string ("65%"), and any
    balance other than dead centre means they differ — one number has to
    stand in for the pair in a list row.
    """
    if not isinstance(volume, dict) or not volume:
        return 0
    total = count = 0
    for channel in volume.values():
        if not isinstance(channel, dict):
            continue
        try:
            total += int(str(channel.get("value_percent", "0%")).rstrip("%"))
            count += 1
        except ValueError:
            continue
    return round(total / count) if count else 0


def channels(volume):
    """{channel name: percent}, so the panel can show what balance did."""
    out = {}
    if not isinstance(volume, dict):
        return out
    for name, channel in volume.items():
        if not isinstance(channel, dict):
            continue
        try:
            out[name] = int(str(channel.get("value_percent", "0%")).rstrip("%"))
        except ValueError:
            continue
    return out


def decibels(volume):
    """The first channel's dB readout, as pavucontrol shows beside the %."""
    if not isinstance(volume, dict) or not volume:
        return ""
    first = next(iter(volume.values()), None)
    return (first or {}).get("db", "") if isinstance(first, dict) else ""


def ports_of(entry):
    """The selectable ports of a device (Speakers / Headphones / Line Out).

    Highest priority first, which is the order pavucontrol uses and which puts
    the built-in speaker at the top where it belongs. Unavailable ports are
    KEPT rather than filtered: "Headphones — unplugged" is the answer to "why
    can't I pick headphones", and hiding the row leaves that unanswered.
    """
    out = []
    for port in entry.get("ports") or []:
        if not isinstance(port, dict):
            continue
        availability = port.get("availability") or ""
        out.append({
            "name": port.get("name") or "",
            "desc": port.get("description") or port.get("name") or "",
            "type": (port.get("type") or "").lower(),
            "priority": port.get("priority") or 0,
            # pactl says "not available" for a jack with nothing in it and
            # "availability unknown" for one it cannot sense — which is the
            # NORMAL state of built-in speakers, so it must not read as bad.
            "available": availability != "not available",
            "availability": availability,
        })
    out.sort(key=lambda p: -p["priority"])
    return out


def device_of(entry, kind):
    props = entry.get("properties") or {}
    volume = entry.get("volume")
    return {
        "kind": kind,                                # sink | source
        "name": entry.get("name") or "",
        "desc": entry.get("description") or entry.get("name") or "",
        "index": entry.get("index"),
        "mute": bool(entry.get("mute")),
        "vol": percent(volume),
        "db": decibels(volume),
        "balance": entry.get("balance", 0.0),
        "nchannels": len(volume or {}),
        "volChannels": channels(volume),
        "driver": entry.get("driver") or "",
        "spec": entry.get("sample_specification") or "",
        "channelMap": entry.get("channel_map") or "",
        "state": entry.get("state") or "",
        "port": entry.get("active_port") or "",
        "ports": ports_of(entry),
        "monitorSource": entry.get("monitor_source") or "",
        "bus": props.get("device.bus") or props.get("device.api") or "",
    }


def stream_of(entry, target_key):
    props = entry.get("properties") or {}
    volume = entry.get("volume")
    name = (
        props.get("application.name")
        or props.get("application.process.binary")
        or props.get("node.name")
        or "stream"
    )
    return {
        "index": entry.get("index"),
        "app": name,
        "media": props.get("media.name") or "",
        # Whatever index the device had IN THIS SAME pactl pass. Resolved to a
        # name below and never compared against anything read later.
        "target": entry.get(target_key),
        "targetName": "",
        "mute": bool(entry.get("mute")),
        "vol": percent(volume),
        "db": decibels(volume),
        "corked": bool(entry.get("corked")),
    }


def profile_note(profile_name):
    """Plain-language warning for the bluez profiles that trade off.

    This is the whole reason profile switching is worth a key: a headset
    connected as a headset (HSP/HFP) sounds like a telephone, and one
    connected as A2DP has no working microphone. Neither the profile name nor
    its description ("Handsfree Head Unit") says so.
    """
    low = (profile_name or "").lower()
    if "a2dp" in low:
        return "hi-fi, no mic"
    if any(token in low for token in ("headset", "handsfree", "hfp", "hsp")):
        return "mic, low quality"
    if low == "off":
        return "device disabled"
    return ""


def read_cards():
    cards = []
    for entry in pactl_json("list", "cards"):
        active = entry.get("active_profile") or ""
        raw = entry.get("profiles")
        profiles = []
        if isinstance(raw, dict):
            for key, value in raw.items():
                value = value if isinstance(value, dict) else {}
                available = bool(value.get("available", True))
                if not available and key != active:
                    continue
                profiles.append({
                    "name": key,
                    "desc": value.get("description") or key,
                    "available": available,
                    "priority": value.get("priority") or 0,
                    "sinks": value.get("sinks", 0),
                    "sources": value.get("sources", 0),
                    "note": profile_note(key),
                })
        profiles.sort(key=lambda p: -p["priority"])
        props = entry.get("properties") or {}
        active_desc = next(
            (p["desc"] for p in profiles if p["name"] == active), active
        )
        cards.append({
            "name": entry.get("name") or "",
            "index": entry.get("index"),
            "desc": props.get("device.description") or entry.get("name") or "",
            "active": active,
            "activeDesc": active_desc,
            "note": profile_note(active),
            "profiles": profiles,
        })
    return cards


def card_token(card_name):
    """The part of a card name that also appears in its devices' names.

    `alsa_card.pci-0000_00_1f.3` -> `pci-0000_00_1f.3`, which is exactly the
    substring `alsa_output.pci-0000_00_1f.3.analog-stereo` carries. A
    heuristic because pactl offers nothing better — see the module docstring.
    """
    _, _, token = (card_name or "").partition(".")
    return token


def attach_cards(devices, cards):
    for device in devices:
        device["card"] = ""
        device["cardDesc"] = ""
        device["profile"] = ""
        device["profileDesc"] = ""
        device["profileNote"] = ""
        for card in cards:
            token = card_token(card["name"])
            if token and token in device["name"]:
                device["card"] = card["name"]
                device["cardDesc"] = card["desc"]
                device["profile"] = card["active"]
                device["profileDesc"] = card["activeDesc"]
                device["profileNote"] = card["note"]
                break


def read_all():
    sinks = [device_of(entry, "sink") for entry in pactl_json("list", "sinks")]

    # Real capture devices only. See the module docstring: monitor_of is None
    # on everything, so the two checks that DO work are the .monitor suffix
    # and the set of monitor_source names the sinks themselves point at.
    monitors = {s["monitorSource"] for s in sinks if s["monitorSource"]}
    sources = []
    for entry in pactl_json("list", "sources"):
        device = device_of(entry, "source")
        if device["name"].endswith(".monitor") or device["name"] in monitors:
            continue
        sources.append(device)

    playback = [stream_of(e, "sink") for e in pactl_json("list", "sink-inputs")]
    recording = [stream_of(e, "source") for e in pactl_json("list", "source-outputs")]
    cards = read_cards()

    attach_cards(sinks, cards)
    attach_cards(sources, cards)

    # Resolve every stream's target index to a name HERE, in the same pass
    # that read both — an index carried across a refresh names a different
    # device, or none.
    by_index = {d["index"]: d for d in sinks}
    for stream in playback:
        target = by_index.get(stream["target"])
        stream["targetName"] = target["desc"] if target else ""
        stream["targetId"] = target["name"] if target else ""
    by_index = {d["index"]: d for d in sources}
    for stream in recording:
        target = by_index.get(stream["target"])
        stream["targetName"] = target["desc"] if target else ""
        stream["targetId"] = target["name"] if target else ""

    ok_sink, default_sink = run(["pactl", "get-default-sink"])
    ok_source, default_source = run(["pactl", "get-default-source"])

    return {
        "outputs": sinks,
        "inputs": sources,
        "playback": playback,
        "recording": recording,
        "cards": cards,
        "defaultSink": default_sink.strip() if ok_sink else "",
        "defaultSource": default_source.strip() if ok_source else "",
        "volumeMax": VOLUME_MAX,
        "volumeUnity": VOLUME_UNITY,
    }


# ---------------------------------------------------------------------------
# commands
# ---------------------------------------------------------------------------
# Scope -> the pactl verbs that address that kind of thing. A table rather
# than four if-chains: every one of these had to be written out three times in
# the qtile popup (volume, mute, move) and a mismatched pair is silent —
# `set-sink-volume` against a sink-input index happily changes a DIFFERENT
# device, because the index is valid in both namespaces.
SCOPES = {
    "sink": {"volume": "set-sink-volume", "mute": "set-sink-mute", "by": "name"},
    "source": {"volume": "set-source-volume", "mute": "set-source-mute", "by": "name"},
    "sink-input": {
        "volume": "set-sink-input-volume", "mute": "set-sink-input-mute",
        "move": "move-sink-input", "by": "index",
    },
    "source-output": {
        "volume": "set-source-output-volume", "mute": "set-source-output-mute",
        "move": "move-source-output", "by": "index",
    },
}


def cmd_query(_args):
    print(json.dumps(read_all()))
    return 0


def cmd_volume(args):
    """volume <scope> <id> <percent> — absolute, never pactl's relative +5%.

    Relative steps compound with whatever the last refresh has not shown yet,
    so a held key overshoots by however many presses are in flight.
    """
    if len(args) < 3 or args[0] not in SCOPES:
        return emit(False, "usage: volume <sink|source|sink-input|source-output> <id> <percent>")
    scope, ident, value = args[0], args[1], args[2]
    try:
        target = max(0, min(VOLUME_MAX, int(float(value))))
    except ValueError:
        return emit(False, f"not a percentage: {value}")
    ok, out = run(["pactl", SCOPES[scope]["volume"], ident, f"{target}%"])
    return emit(ok, f"{target}%" if ok else first_error_line(out), volume=target)


def cmd_mute(args):
    if len(args) < 2 or args[0] not in SCOPES:
        return emit(False, "usage: mute <scope> <id> [toggle|1|0]")
    state = args[2] if len(args) > 2 else "toggle"
    ok, out = run(["pactl", SCOPES[args[0]]["mute"], args[1], state])
    return emit(ok, "mute " + state if ok else first_error_line(out))


def cmd_balance(args):
    """balance <sink|source> <name> <volume%> <balance-1..1>

    pactl has no balance setter, so this writes the two channel volumes
    directly. Stereo only: there is nothing to pan on a mono microphone and a
    surround map needs more than two values. The left/right mapping is
    PulseAudio's own, so the value read back matches what was set.
    """
    if len(args) < 4 or args[0] not in ("sink", "source"):
        return emit(False, "usage: balance <sink|source> <name> <volume> <balance>")
    try:
        volume = max(0, min(VOLUME_MAX, int(float(args[2]))))
        balance = max(-1.0, min(1.0, float(args[3])))
    except ValueError:
        return emit(False, "balance takes numbers")
    left = round(volume * (1 - max(0.0, balance)))
    right = round(volume * (1 + min(0.0, balance)))
    ok, out = run(["pactl", SCOPES[args[0]]["volume"], args[1],
                   f"{left}%", f"{right}%"])
    return emit(ok, f"balance {left}/{right}" if ok else first_error_line(out))


def cmd_move(args):
    """move <sink-input|source-output> <index> <device-name>"""
    if len(args) < 3 or args[0] not in ("sink-input", "source-output"):
        return emit(False, "usage: move <sink-input|source-output> <index> <device>")
    ok, out = run(["pactl", SCOPES[args[0]]["move"], args[1], args[2]])
    return emit(ok, "moved" if ok else first_error_line(out))


def cmd_default_sink(args):
    """default-sink <name> — and DRAG THE LIVE STREAMS ACROSS.

    Pulse routes only new streams to a new default, so switching output while
    music plays leaves the music on the old device. That gap is the entire
    reason qtile's popup existed instead of a keybind on set-default-sink.

    The sink-input list is re-read here rather than taken from the caller's
    last query: indices are serials, and a stream that started or was
    renumbered since would be moved by the wrong number, or missed.
    """
    if not args:
        return emit(False, "usage: default-sink <name>")
    name = args[0]
    ok, out = run(["pactl", "set-default-sink", name])
    if not ok:
        return emit(False, first_error_line(out))

    moved = failed = 0
    for entry in pactl_json("list", "sink-inputs"):
        index = entry.get("index")
        if index is None:
            continue
        good, _ = run(["pactl", "move-sink-input", str(index), name])
        if good:
            moved += 1
        else:
            # A stream that ended between the list and the move is the common
            # case and is not worth reporting as an error.
            failed += 1

    if moved:
        status = f"output set · moved {moved} stream{'s' if moved != 1 else ''}"
    elif failed:
        status = f"output set · {failed} stream(s) would not move"
    else:
        status = "output set"
    return emit(True, status, moved=moved)


def cmd_default_source(args):
    if not args:
        return emit(False, "usage: default-source <name>")
    ok, out = run(["pactl", "set-default-source", args[0]])
    return emit(ok, "microphone set" if ok else first_error_line(out))


def cmd_card_profile(args):
    """card-profile <card> <profile> — the slow one, hence TIMEOUT_ACTION."""
    if len(args) < 2:
        return emit(False, "usage: card-profile <card> <profile>")
    ok, out = run(["pactl", "set-card-profile", args[0], args[1]], TIMEOUT_ACTION)
    return emit(ok, "profile set" if ok else first_error_line(out))


def cmd_port(args):
    """port <sink|source> <device> <port>

    Refuses an unplugged port rather than passing it through. pactl ACCEPTS
    the switch, returns success, and routes the audio to a jack with nothing
    in it — which is indistinguishable from broken sound.
    """
    if len(args) < 3 or args[0] not in ("sink", "source"):
        return emit(False, "usage: port <sink|source> <device> <port>")
    kind, device, port = args
    setter = "set-sink-port" if kind == "sink" else "set-source-port"
    ok, out = run(["pactl", setter, device, port])
    return emit(ok, "port set" if ok else first_error_line(out))


COMMANDS = {
    "query": cmd_query,
    "volume": cmd_volume,
    "mute": cmd_mute,
    "balance": cmd_balance,
    "move": cmd_move,
    "default-sink": cmd_default_sink,
    "default-source": cmd_default_source,
    "card-profile": cmd_card_profile,
    "port": cmd_port,
}


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(json.dumps({"ok": False, "status": "commands: " + " ".join(COMMANDS)}))
        return 0
    if shutil.which("pactl") is None:
        # Said once, clearly, instead of nine identical "pactl not found"
        # lines from nine different verbs.
        return emit(False, "pactl is not installed")
    command = COMMANDS.get(argv[1])
    if command is None:
        return emit(False, f"unknown command: {argv[1]}")
    return command(argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
