import subprocess

BRIGHT_TIMEOUT = 2
NOTIFY_TIMEOUT = 1


def _run(cmd, timeout, **kw):
    try:
        return subprocess.run(cmd, timeout=timeout, **kw)
    except subprocess.TimeoutExpired:
        return None


def _get_pct():
    cur = _run(["brightnessctl", "g"], BRIGHT_TIMEOUT, capture_output=True, text=True)
    mx = _run(["brightnessctl", "m"], BRIGHT_TIMEOUT, capture_output=True, text=True)
    if cur is None or mx is None:
        return None
    try:
        return round(int(cur.stdout.strip()) * 100 / int(mx.stdout.strip()))
    except (ValueError, ZeroDivisionError):
        return None


def brightness_change(delta):
    sign = "+" if delta >= 0 else "-"
    _run(["brightnessctl", "set", f"{abs(delta)}%{sign}"], BRIGHT_TIMEOUT)

    pct = _get_pct()
    if pct is None:
        return

    icon = (
        "display-brightness-off-symbolic" if pct <= 0 else
        "display-brightness-low-symbolic" if pct < 34 else
        "display-brightness-medium-symbolic" if pct < 67 else
        "display-brightness-high-symbolic"
    )

    _run([
        "notify-send",
        "-a", "Brightness",
        "-u", "normal",
        "-h", "string:x-dunst-stack-tag:brightness",
        "-h", f"int:value:{pct}",
        "-i", icon,
        "Brightness",
        f"{pct}%",
    ], NOTIFY_TIMEOUT)
