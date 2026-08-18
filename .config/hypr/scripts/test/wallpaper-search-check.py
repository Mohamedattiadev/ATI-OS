#!/usr/bin/env python3
"""Type a theme name into the wallpaper picker's search and screenshot the
match count.  TEST TOOL, one-shot, for item 12's verification.

wallpaperPickerLayerVisible is on the exclusive-grab list, so synthetic
keys are safe without the workspace guard. Assumes the panel is already
open.
"""
import os
import subprocess
import sys

HERE = os.path.expanduser("~/.config/hypr/scripts/test")


def keys(sequence):
    subprocess.run([sys.executable, f"{HERE}/uinput-key.py", "--gap", "0.04"] + sequence.split(),
                   capture_output=True, text=True, timeout=40)


keys("g r u v b o x")
subprocess.run(["grim", "-o", "eDP-1", "/tmp/wp-search-gruvbox.png"], timeout=10)
print("saved")
