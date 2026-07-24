import os
import subprocess

from libqtile import hook, qtile
from qtile_extras.widget.decorations import RectDecoration

from popups.QtileCheatsheet import show_qtile_cheatsheet, close_qtile_cheatsheet
from popups.VimCheatsheet import close_vim_cheatsheet
from popups.FishCheatsheet import close_fish_kitty_cheatsheet
from popups.WallpaperPopup import show_wallpaper_picker, close_wallpaper_picker

from lib import state
from lib.constants import CHORD_CHIP_COLORS, colorsW
from lib.helpers import apply_bar_mode, ensure_gromit_and_toggle, _disable_passthrough, _enable_passthrough


@hook.subscribe.startup_complete
def apply_bar_on_startup():
    qtile.call_later(0.1, apply_bar_mode)


@hook.subscribe.startup
def apply_bar_on_reload_startup():
    qtile.call_later(0.05, apply_bar_mode)


@hook.subscribe.screens_reconfigured
def apply_bar_on_reconfigure():
    apply_bar_mode()


@hook.subscribe.startup_once
def start_once():
    home = os.path.expanduser("~")
    subprocess.call([home + "/.config/qtile/autostart.sh"])


@hook.subscribe.enter_chord
def remember_chord(chord_name):
    state.ACTIVE_CHORD = chord_name


@hook.subscribe.enter_chord
def auto_enable_warpd(chord_name):
    if chord_name == "Mouse-Mode":
        qtile.spawn("warpd --normal")


@hook.subscribe.enter_chord
def auto_enable_draw(chord_name):
    if chord_name == "Draw-Mode":
        ensure_gromit_and_toggle(qtile)


@hook.subscribe.enter_chord
def auto_enable_cheatsheet(chord_name):
    if chord_name == "CheatSheet-Mode":
        show_qtile_cheatsheet(qtile)


@hook.subscribe.enter_chord
def auto_enable_wallpaper_picker(chord_name):
    if chord_name == "WallpaperPicker":
        show_wallpaper_picker(qtile)
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and not w.box_is_open:
            w.toggle()


@hook.subscribe.leave_chord
def cleanup_on_leave():
    if state.ACTIVE_CHORD == "Draw-Mode":
        qtile.spawn("gromit-mpx -v")

    elif state.ACTIVE_CHORD == "CheatSheet-Mode":
        close_qtile_cheatsheet()
        close_vim_cheatsheet()
        close_fish_kitty_cheatsheet()

    elif state.ACTIVE_CHORD == "WallpaperPicker":
        close_wallpaper_picker()
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and w.box_is_open:
            w.toggle()

    elif state.ACTIVE_CHORD == "PASSTHROUGH":
        _disable_passthrough(qtile)

    state.ACTIVE_CHORD = None


@hook.subscribe.enter_chord
def chord_chip_enter(chord_name):
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            setattr(deco, "colour", CHORD_CHIP_COLORS.get(chord_name, colorsW[2]))

    if w.bar:
        w.bar.draw()


@hook.subscribe.leave_chord
def chord_chip_leave():
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            setattr(deco, "colour", colorsW[2])

    w.bar.draw()


@hook.subscribe.enter_chord
def auto_enable_passthrough(chord_name):
    if chord_name == "PASSTHROUGH":
        _enable_passthrough(qtile)
