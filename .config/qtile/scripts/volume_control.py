import subprocess
import re

# Aggressive timeouts: called from qtile lazy.function on Media-Mode keys.
# pactl/notify-send hanging would freeze the WM main loop.
PACTL_TIMEOUT = 2
NOTIFY_TIMEOUT = 1


def _run(cmd, timeout, **kw):
    try:
        return subprocess.run(cmd, timeout=timeout, **kw)
    except subprocess.TimeoutExpired:
        return None


def volume_change(change):
    result = _run(
        ["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
        PACTL_TIMEOUT,
        capture_output=True,
        text=True,
    )
    if result is None:
        return

    match = re.search(r'(\d+)%', result.stdout)
    if not match:
        return

    vol = int(match.group(1))
    new_vol = max(0, min(150, vol + change))

    _run(
        ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{new_vol}%"],
        PACTL_TIMEOUT,
    )

    icon = (
        "audio-volume-muted-symbolic" if new_vol <= 0 else
        "audio-volume-low-symbolic" if new_vol < 30 else
        "audio-volume-medium-symbolic" if new_vol < 70 else
        "audio-volume-high-symbolic"
    )

    _run([
        "notify-send",
        "-a", "Volume",
        "-u", "normal",
        "-h", "string:x-dunst-stack-tag:volume",
        "-h", f"int:value:{new_vol}",
        "-i", icon,
        "Volume",
        f"{new_vol}%"
    ], NOTIFY_TIMEOUT)


def toggle_mute():
    _run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"], PACTL_TIMEOUT)
    result = _run(
        ["pactl", "get-sink-mute", "@DEFAULT_SINK@"],
        PACTL_TIMEOUT,
        capture_output=True,
        text=True,
    )
    if result is None:
        return
    muted = "yes" in result.stdout
    icon = "audio-volume-muted-symbolic" if muted else "audio-volume-high-symbolic"
    message = "Muted" if muted else "Unmuted"
    _run([
        "notify-send", "-a", "Volume", "-u", "normal",
        "-h", "string:x-dunst-stack-tag:volume", "-i", icon,
        "Volummute", message,
    ], NOTIFY_TIMEOUT)
