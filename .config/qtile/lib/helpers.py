import subprocess
import threading
import time

from libqtile import qtile
from libqtile.config import Key
from libqtile.lazy import lazy

from popups.QtileCheatsheet import close_qtile_cheatsheet
from popups.VimCheatsheet import close_vim_cheatsheet
from popups.FishCheatsheet import close_fish_kitty_cheatsheet
from popups.WallpaperPopup import close_wallpaper_picker

from lib import state
from lib.constants import ARCH_ICON_MAIN, NON_EN_NOTIFY_ID, myTerm


# ---- passthrough ----

def _enable_passthrough(qtile):
    qtile.spawn("notify-send 'PASSTHROUGH MODE'")
    qtile.ungrab_keys()


def _disable_passthrough(qtile):
    qtile.spawn("notify-send 'NORMAL MODE'")
    qtile.grab_keys()


@lazy.function
def passthrough_on(qtile):
    _enable_passthrough(qtile)


@lazy.function
def passthrough_off(qtile):
    _disable_passthrough(qtile)


# ---- bar mode ----

def apply_bar_mode():
    for s in qtile.screens:
        if state.BAR_MODE == "top":
            if s.bottom and s.bottom.is_show():
                s.bottom.show(False)
            if s.top and not s.top.is_show():
                s.top.show(True)
        else:
            if s.top and s.top.is_show():
                s.top.show(False)
            if s.bottom and not s.bottom.is_show():
                s.bottom.show(True)


@lazy.function
def toggle_top_bottom_exclusive(qtile):
    screen = qtile.current_screen
    top = screen.top
    bottom = screen.bottom

    if not top or not bottom:
        return

    if state.BAR_MODE == "top":
        state.BAR_MODE = "bottom"
    else:
        state.BAR_MODE = "top"

    apply_bar_mode()


# ---- non-EN layout warning ----

def show_layout_warning(qtile, layout):
    layout_name = layout.upper()
    qtile.spawn(
        "notify-send "
        f"-r {NON_EN_NOTIFY_ID} "
        "-u critical "
        "-t 0 "
        '"Non-English Layout Active" '
        f'"Current layout: {layout_name}\n'
        "Many shortcuts may not work.\n"
        'Switch to EN (US) to use all shortcuts."'
    )


def hide_layout_warning(qtile):
    qtile.spawn(f'notify-send -r {NON_EN_NOTIFY_ID} -t 1 "" ""')


# ---- group navigation ----

@lazy.function
def go_to_group_or_notify(qtile, group_name):
    current = qtile.current_group.name
    if current == group_name:
        qtile.spawn(
            f'notify-send -u normal -t 5000  "Qtile" "You are already in workspace {group_name}"'
        )
    else:
        qtile.groups_map[group_name].toscreen()


def group_keys():
    return [
        Key(
            [],
            str(i),
            go_to_group_or_notify(str(i)),
            desc=f"Switch to group {i}",
        )
        for i in range(1, 10)
    ]


# ---- widget helpers ----

def toggle_onboarding(qtile):
    w = qtile.widgets_map.get("tooltip_widgetbox")
    if not w:
        return

    if w.box_is_open:
        qtile.cmd_spawn("eww close onboarding-welcome")
        w.toggle()
    else:
        qtile.cmd_spawn("eww open onboarding-welcome")
        w.toggle()


def set_icon_temporarily(qtile, icon, cmd):
    w = qtile.widgets_map.get("main_icon_chip")
    if not w:
        return

    w.update(icon)
    qtile.cmd_spawn(cmd)

    def reset():
        time.sleep(0.3)
        w.update(ARCH_ICON_MAIN)

    threading.Thread(target=reset, daemon=True).start()


def open_terminal(qtile):
    set_icon_temporarily(qtile, "󰞷", myTerm)


def open_launcher(qtile):
    set_icon_temporarily(
        qtile,
        "󰍉",
        "rofi -show drun -show-icons",
    )


# ---- gromit / cheatsheet / wallpaper mode exit ----

def ensure_gromit_and_toggle(qtile):
    try:
        subprocess.run(
            ["pgrep", "-x", "gromit-mpx"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        qtile.spawn("gromit-mpx -t")
    except subprocess.CalledProcessError:
        qtile.spawn(
            "notify-send -u normal -t 4000 "
            '"Gromit MPX" "Gromit was not running — starting it now…"'
        )
        qtile.spawn("gromit-mpx")
        qtile.call_later(0.3, lambda: qtile.spawn("gromit-mpx -t"))


def exit_cheatsheet_mode(qtile):
    close_qtile_cheatsheet()
    close_vim_cheatsheet()
    close_fish_kitty_cheatsheet()
    qtile.ungrab_chord()


def close_wallpaper_mode(qtile):
    close_wallpaper_picker()
    qtile.ungrab_chord()

    w = qtile.widgets_map.get("wallpaper_toggle")
    if w and w.box_is_open:
        w.toggle()
