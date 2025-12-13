
# scripts/volume_control.py
import subprocess

def volume_change(change):
    result = subprocess.run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"], capture_output=True, text=True)
    vol = int(result.stdout.split()[4].replace('%', ''))
    new_vol = max(0, min(150, vol + change))
    subprocess.run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{new_vol}%"])
    icon = "audio-volume-muted-symbolic" if new_vol <= 0 else "audio-volume-low-symbolic" if new_vol < 30 else "audio-volume-medium-symbolic" if new_vol < 70 else "audio-volume-high-symbolic"
    subprocess.run(["notify-send", "-a", "Volume", "-u", "normal", "-h", "string:x-dunst-stack-tag:volume", "-i", icon, "Volume", f"{new_vol}%"])

def toggle_mute():
    subprocess.run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
    result = subprocess.run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"], capture_output=True, text=True)
    muted = "yes" in result.stdout
    icon = "audio-volume-muted-symbolic" if muted else "audio-volume-high-symbolic"
    message = "Muted" if muted else "Unmuted"
    subprocess.run(["notify-send", "-a", "Volume", "-u", "normal", "-h", "string:x-dunst-stack-tag:volume", "-i", icon, "Volummute", message])
