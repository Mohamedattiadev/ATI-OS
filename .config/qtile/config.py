# Copyright (c) 2010 Aldo Cortesi
# Copyright (c) 2010, 2014 dequis
# Copyright (c) 2012 Randall Ma
# Copyright (c) 2012-2014 Tycho Andersen
# Copyright (c) 2012 Craig Barnes
# Copyright (c) 2013 horsik
# Copyright (c) 2013 Tao Sauvage
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ╔──────────────────────────────────╗
# │░▄█▄█▄░▀█▀░█▄█░█▀█░█▀█░█▀▄░▀█▀░█▀▀│
# │░▄█▄█▄░░█░░█░█░█▀▀░█░█░█▀▄░░█░░▀▀█│
# │░░▀░▀░░▀▀▀░▀░▀░▀░░░▀▀▀░▀░▀░░▀░░▀▀▀│
# ╚──────────────────────────────────╝


import os
import subprocess
import time
import threading
from libqtile import bar, hook, layout, qtile, widget
from qtile_extras.widget.decorations import RectDecoration
from qtile_extras import widget as ewidget
from scripts.volume_control import volume_change, toggle_mute

# from scripts.float_windows import ( float_satty, float_edit_nvim, float_imv, float_feh, float_link_preview)
from scripts.mpv_manager import mpv_manager
from scripts.toggle_apps import (
    toggle_qutebrowser,
    toggle_obsidian,
    toggle_anki,
    toggle_telegram,
    toggle_terminal,
    toggle_file_manager,
    toggle_brave,
)
from scripts.sum_app import toggle_or_spawn_sum
from libqtile.config import (
    Click,
    Drag,
    Group,
    Key,
    KeyChord,
    Match,
    Screen,
    DropDown,
    ScratchPad,
)
from libqtile.lazy import lazy

from popups.VimCheatsheet import toggle_vim_cheatsheet, close_vim_cheatsheet
from popups.FishCheatsheet import (
    toggle_fish_kitty_cheatsheet,
    close_fish_kitty_cheatsheet,
)
from popups.QtileCheatsheet import (
    toggle_cheatsheet,
    close_qtile_cheatsheet,
    show_qtile_cheatsheet,
)

from popups import WallpaperPopup
from popups.WallpaperPopup import (
    show_wallpaper_picker,
    close_wallpaper_picker,
)
import colors as color_schemes
import logging

# ╔──────────────────────────────────────────╗
# │░▄█▄█▄░█░█░█▀█░█▀▄░▀█▀░█▀█░█▀▄░█░░░█▀▀░█▀▀│
# │░▄█▄█▄░▀▄▀░█▀█░█▀▄░░█░░█▀█░█▀▄░█░░░█▀▀░▀▀█│
# │░░▀░▀░░░▀░░▀░▀░▀░▀░▀▀▀░▀░▀░▀▀░░▀▀▀░▀▀▀░▀▀▀│
# ╚──────────────────────────────────────────╝


logging.basicConfig(level=logging.ERROR)
colorsW = [
    ["#282c34", "#282c34"],  # bg
    ["#bbc2cf", "#bbc2cf"],  # fg
    ["#1c1f24", "#1c1f24"],  # color01
    ["#ff6c6b", "#ff6c6b"],  # color02
    ["#98be65", "#98be65"],  # color03
    ["#da8548", "#da8548"],  # color04
    ["#51afef", "#51afef"],  # color05
    ["#c678dd", "#c678dd"],  # color06
    ["#46d9ff", "#46d9ff"],  # color15
]

ARCH_ICON_MAIN = "󰕰"

DEFAULT_CHIP_COLOR = colorsW[2]

os.environ["GTK_IM_MODULE"] = "none"
os.environ["QT_IM_MODULE"] = "none"
os.environ["XMODIFIERS"] = ""

mod = "mod1"  # Sets mod key to ALT
mod2 = "mod4"  # Sets mod key to WINDOWS
myTerm = "kitty"  # My terminal of choice
my2ndTerm = "alacritty"  # My terminal of choice
myFullScreenTerm = "kitty --start-as=fullscreen"
# sum_file = os.path.expanduser("~/ATITODOS/TODOS.md")
home = os.path.expanduser("~")


user = (os.environ.get("USER") or os.environ.get("LOGNAME") or "").upper()

todos_dir = os.path.expanduser(f"~/{user}TODOS")
sum_file = os.path.join(todos_dir, "TODOS.md")


ACTIVE_CHORD = None

NON_EN_NOTIFY_ID = 9001


colors: list[list[str]] = color_schemes.DoomOne

# NOTE:
### COLORSCHEME ###
# Colors are defined in a separate 'colors.py' file.
# There 10 colorschemes available to choose from:
#
# colors = colors.DoomOne
# colors = colors.Dracula
# colors = colors.GruvboxDark
# colors = colors.MonokaiPro
# colors = colors.Nord
# colors = colors.OceanicNext
# colors = colors.Palenight
# colors = colors.SolarizedDark
# colors = colors.SolarizedLight
# colors = colors.TomorrowNight


CHORD_CHIP_COLORS = {
    "Resize-Mode": colorsW[5],  # orange
    "Rofi-Mode": colorsW[6],  # blue
    "Media-Mode": colorsW[4],  # cyan
    "Scratch-Mode": colorsW[8],
    "Draw-Mode": colorsW[3],
    "Mouse-Mode": colorsW[7],
    "Lang-Switch": colorsW[1],
    "CheatSheet-Mode": colorsW[3],
    "WallpaperPicker": colorsW[3],
}

# ╔──────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█│
# │░░▀░▀░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀│
# ╚──────────────────────────────────────────╝

# ------------------------------------------------------------
# 0-  Function for the autostart.sh script  (runs on startup)
# -----------------------------------------------------------


@hook.subscribe.startup_once
def start_once():
    home = os.path.expanduser("~")
    subprocess.call([home + "/.config/qtile/autostart.sh"])


# -------------------------------------------------
# 1- Function for Not En Layout
# -------------------------------------------------


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


# ---------------------------------------------------
# 2- Function for Going to the same group and notify
# ---------------------------------------------------


@lazy.function
def go_to_group_or_notify(qtile, group_name):
    current = qtile.current_group.name

    if current == group_name:
        qtile.spawn(
            f'notify-send -u normal -t 5000  "Qtile" "You are already in workspace {group_name}"'
        )
    else:
        qtile.groups_map[group_name].toscreen()


# ---------------------------------------------------
# 3- Function for tooltip_widgetbox
# ---------------------------------------------------


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


# ----------------------------------------------
# 4- Function for setting icon temporarily  "󰕰"
# ---------------------------------------------


def set_icon_temporarily(qtile, icon, cmd):
    w = qtile.widgets_map.get("main_icon_chip")
    if not w:
        return

    # update icon immediately
    w.update(icon)

    # spawn app
    qtile.cmd_spawn(cmd)

    # reset icon shortly after
    def reset():
        time.sleep(0.3)  # small delay so user sees the icon
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


# ╔────────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▄█░█▀█░█▀▄░█▀▀░█▀▀░░░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█░█░█░█░█░█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀░░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀│
# ╚────────────────────────────────────────────────────────────────╝


# -----------------------------------------------
# 5- Function to remember which mode we are in
# ----------------------------------------------


@hook.subscribe.enter_chord
def remember_chord(chord_name):
    global ACTIVE_CHORD
    ACTIVE_CHORD = chord_name


# --------------------------------------------------------------
# 6- Function to auto launch warpd when "Mouse-Mode" is active
# --------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_warpd(chord_name):
    if chord_name == "Mouse-Mode":
        qtile.spawn("warpd --normal")


# ---------------------------------------------------------------------------------------
# 7- Function to lanuch gromit-mpx when "Draw-Mode" if not lunched and then activate it
# ---------------------------------------------------------------------------------------


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

        # wait a bit, then toggle draw
        qtile.call_later(0.3, lambda: qtile.spawn("gromit-mpx -t"))


@hook.subscribe.enter_chord
def auto_enable_draw(chord_name):
    if chord_name == "Draw-Mode":
        ensure_gromit_and_toggle(qtile)


# --------------------------------------------------------------------------------------------------------
# 8- Function to auto lanuch the CheatSheet when it's mode activated, Function to exit the CheatSheet mode
# --------------------------------------------------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_cheatsheet(chord_name):
    if chord_name == "CheatSheet-Mode":
        show_qtile_cheatsheet(qtile)


def exit_cheatsheet_mode(qtile):
    close_qtile_cheatsheet()
    close_vim_cheatsheet()
    close_fish_kitty_cheatsheet()
    qtile.ungrab_chord()


# -----------------------------------------------------------------------------------------------------
# 9- Function to auto lanuch the WallpaperPicker when it's mode activated , Function to close wallpaper
# -----------------------------------------------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_wallpaper_picker(chord_name):
    if chord_name == "WallpaperPicker":
        show_wallpaper_picker(qtile)
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and not w.box_is_open:
            w.toggle()


def close_wallpaper_mode(qtile):
    close_wallpaper_picker()
    qtile.ungrab_chord()

    w = qtile.widgets_map.get("wallpaper_toggle")
    if w and w.box_is_open:
        w.toggle()


# ----------------------------------------------------------------
# 10- Function to cleanup and close all apps of the modes  on leave
# ----------------------------------------------------------------


@hook.subscribe.leave_chord
def cleanup_on_leave():
    global ACTIVE_CHORD

    if ACTIVE_CHORD == "Draw-Mode":
        qtile.spawn("gromit-mpx -v")

    elif ACTIVE_CHORD == "CheatSheet-Mode":
        close_qtile_cheatsheet()
        close_vim_cheatsheet()
        close_fish_kitty_cheatsheet()

    elif ACTIVE_CHORD == "WallpaperPicker":
        close_wallpaper_picker()
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and w.box_is_open:
            w.toggle()
    ACTIVE_CHORD = None


# -------------------------------------------------------------------------------
# 11- Function to group keys while we are inside the modes with (1,2,3....9)
# -------------------------------------------------------------------------------


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


# ---------------------------------------------------
# 12- function to change the color of the chord chip
# --------------------------------------------------


@hook.subscribe.enter_chord
def chord_chip_enter(chord_name):
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            # deco.colour = CHORD_CHIP_COLORS.get(chord_name, colorsW[2])
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
            # deco.colour = colorsW[2]  # default chip color
            setattr(deco, "colour", colorsW[2])

    w.bar.draw()


# ╔───────────────────────────────────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▄█░█▀█░█▀▄░█▀▀░█▀▀░░░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░│
# │░▄█▄█▄░█░█░█░█░█░█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀░░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────────────────────────────────────╝


# -----------------------------------
# 12- Function to set keyboard layout
# -----------------------------------


def set_kb(layout):
    @lazy.function
    def _set(qtile):
        qtile.spawn(f"setxkbmap {layout}")

        w = qtile.widgets_map.get("w_lang")
        if w:
            w.backend.set_keyboard(layout, w.option)

        if layout != "us":
            show_layout_warning(qtile, layout)
        else:
            hide_layout_warning(qtile)

        qtile.ungrab_chord()

    return _set


# -------------------------------
# 12- Function to parse task name
# -------------------------------


def parse_task_name(text):
    REMOVE = [
        # Browsers
        " - Mozilla Firefox",
        " - Firefox",
        " - Chromium",
        " - Google Chrome",
        " - Brave",
        " - Microsoft Edge",
        " - Vivaldi",
        " - Opera",
        # LibreOffice
        " — LibreOffice Writer",
        " — LibreOffice Calc",
        " — LibreOffice Impress",
        # Editors / IDEs
        " - Visual Studio Code",
        " - Code",
        " - VS Code",
        " — Visual Studio Code",
        " - Sublime Text",
        " - Atom",
        " - IntelliJ IDEA",
        " - PyCharm",
        # Terminals
        " — Alacritty",
        " — Kitty",
        " — WezTerm",
        " — GNOME Terminal",
        " - Konsole",
        # Media
        " - VLC media player",
        " - MPV",
        " — Spotify",
        " - YouTube",
        # System / DE noise
        "Built-in Widgets —",
        " — Settings",
        " — Preferences",
        " — System Settings",
        # Generic separators
        " — ",
        " - ",
    ]

    for s in REMOVE:
        text = text.replace(s, "")

    return text


# ╔─────────────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░│
# │░▄█▄█▄░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░│
# │░░▀░▀░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░▀░░▀░░▀░│
# ╚─────────────────────────────────────────────────────────────────────╝


# ╔────────────────────────────────╗
# │░▄█▄█▄░▀█▀░█▀█░█▀█░░░█▀▄░█▀█░█▀▄│
# │░▄█▄█▄░░█░░█░█░█▀▀░░░█▀▄░█▀█░█▀▄│
# │░░▀░▀░░░▀░░▀▀▀░▀░░░░░▀▀░░▀░▀░▀░▀│
# ╚────────────────────────────────╝


# -----------------------------------------------------------------------
# 1- the groupbox (the workspaces 1,2,3...etc) , IN the MIDDLE of the bar
# -----------------------------------------------------------------------
def groupbox_widget():
    return chip(
        ewidget.GroupBox,
        fontsize=10,
        margin_y=2,
        margin_x=8,
        padding_y=2,
        padding_x=8,
        borderwidth=4,
        active=colors[8],
        inactive=colors[1],
        highlight_color=colors[2],
        highlight_method="text",
        this_current_screen_border=colors[7],
        this_screen_border=colors[4],
        other_current_screen_border=colors[7],
        other_screen_border=colors[4],
        hide_unused=True,
    )


# -----------------------------------------------------------------------------
# 2- the left side widgets (the main icon , the current layout , the apps list)
# -----------------------------------------------------------------------------


def left_side_widgets():
    return [
        # main Icon Chip
        chip(
            ewidget.TextBox,
            name="main_icon_chip",
            text=ARCH_ICON_MAIN,
            fontsize=15,
            padding=11,
            foreground=colors[7],
            mouse_callbacks={
                "Button1": lazy.function(open_terminal),  # left click
                "Button3": lazy.function(open_launcher),  # right click
            },
        ),
        # Current Layout
        chip(
            ewidget.CurrentLayout,
            padding=18,
            foreground=colors[3],
        ),
        # separator |
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=3,
            fontsize=14,
        ),
        # task list
        widget.TaskList(
            font="JetBrainsMono Nerd Font",
            fontsize=11,
            # icons
            icon_size=16,
            markup=True,
            # markup styles
            markup_normal="",
            markup_focused='<span weight="bold">F {}</span>',
            markup_floating='<span foreground="#da8548">V {}</span>',
            markup_focused_floating='<span weight="bold" foreground="#ffaa00">VF {}</span>',
            markup_minimized='<span foreground="#ff6c6b">↓ {}</span>',
            max_title_width=200,
            padding_x=3,
            padding_y=2,
            margin_x=3,
            margin_y=4,
            spacing=2,
            parse_text=parse_task_name,
            window_name_location_offset=1,
            window_name_location="left",
            foreground=colors[1],
            background=None,
            highlight_method="text",
            border=colors[7],
            borderwidth=0,
            txt_minimized="↓  ",
            stretch=False,
        ),
    ]


# -----------------------------------------------------------------------------
# 3- the right side widgets (the tooltip , the system widgets , the wallpapers)
# -----------------------------------------------------------------------------


def right_side_widgets():
    return [
        # tooltip_widgetbox
        chip(
            ewidget.WidgetBox,
            name="tooltip_widgetbox",
            widgets=[],
            padding=11,
            fontsize=13,
            text_closed="󰌶",
            text_open="󰌵",
            close_button_location="right",
            start_opened=False,
            foreground=colors[1],
            mouse_callbacks={
                "Button1": lazy.function(toggle_onboarding),
            },
        ),
        chip(
            ewidget.WidgetBox,
            name="system_widgetbox",
            fontsize=14,
            padding=10,
            close_button_location="right",
            start_opened=False,
            text_closed="󰖯",
            text_open="󰖰",
            widgets=[
                # CPU
                chip(
                    ewidget.CPU,
                    name="w_cpu",
                    _hide_on_chord=True,
                    format="  {load_percent}%",
                    fontsize=10,
                    padding=11,
                    foreground=colors[5],
                    mouse_callbacks={
                        "Button1": lambda: qtile.cmd_spawn(
                            "env GTK_THEME=Adwaita:dark missioncenter"
                        )
                    },
                ),
                # Memory
                chip(
                    ewidget.Memory,
                    name="w_mem",
                    format="{MemUsed: .0f}{mm}",
                    fmt="🖥  {} ",
                    fontsize=10,
                    padding=11,
                    foreground=colors[8],
                    mouse_callbacks={
                        "Button1": lambda: qtile.cmd_spawn(
                            myFullScreenTerm + " -e btop"
                        )
                    },
                ),
                # Battery
                chip(
                    ewidget.Battery,
                    name="w_battery",
                    format="  {char}{percent:2.0%}",
                    fontsize=10,
                    padding=12,
                    foreground=colors[6],
                    low_foreground=colors[3],
                    low_percentage=0.2,
                    charge_char=" ↑ ",
                    discharge_char=" ↓ ",
                    full_char="✔ ",
                    show_percentage=True,
                    show_short_text=False,
                    mouse_callbacks={
                        "Button1": lambda: qtile.cmd_spawn(
                            '/bin/sh -c \'notify-send "Battery Status" "$(acpi | cut -d "," -f 2-)"\''
                        )
                    },
                ),
            ],
            foreground=colors[7],
        ),
        # wallpaper_toggle widgetbox
        chip(
            ewidget.WidgetBox,
            name="wallpaper_toggle",
            widgets=[],
            padding=11,
            fontsize=12,
            text_closed="✖",
            text_open="󰍜",
            close_button_location="right",
            start_opened=False,
            foreground=colors[8],
            mouse_callbacks={
                "Button1": lazy.spawn("sh -c 'xdotool key Alt_L+p sleep 0.05 key b'")
            },
        ),
        chip(
            ewidget.WidgetBox,
            name="2nd_system_widgetbox",
            fontsize=14,
            padding=10,
            close_button_location="right",
            start_opened=False,
            text_closed="󰤂",
            text_open="󰁂",
            widgets=[
                chip(
                    ewidget.CheckUpdates,
                    padding=11,
                ),
                # Disk
                chip(
                    ewidget.DF,
                    name="w_disk",
                    update_interval=60,
                    partition="/",
                    format="{uf}{m}",
                    fmt="🖴  {}",
                    fontsize=10,
                    padding=11,
                    visible_on_warn=False,
                    foreground=colors[1],
                    mouse_callbacks={"Button1": lambda: qtile.spawn("disk_notify")},
                ),
                # Volume
                chip(
                    ewidget.Volume,
                    name="w_volume",
                    fmt="🕫  {}",
                    padding=11,
                    foreground=colors[7],
                ),
            ],
            foreground=colors[5],
        ),
        # Chord (Modes) Chip
        chip(
            ewidget.Chord,
            name="chord_chip",
            fmt=" {} ",
            padding=11,
            foreground=colors[2],
            background=None,
            name_transform=lambda name: {
                "Resize-Mode": "󰩨   RESIZE : H, J, N",
                "Rofi-Mode": "󰍉   ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h ",
                "Media-Mode": "󰕾   MEDIA : J , K , P , M ",
                "Scratch-Mode": "󰈆   SCRATCH",
                "Draw-Mode": "󰏫   DRAW : w , c , z , r , v ",
                "Mouse-Mode": "󰍽   MOUSE : n , f , g , e , r , m ",
                "Lang-Switch": "   LANG : a , e , t , d ",
                "CheatSheet-Mode": "󰆍   CHEATSHEET : k , v , f ",
                "WallpaperPicker": "󰸉   WALLPAPERS : / , h , j , k ,l , R , ENTER ",
            }.get(name, name.upper()),
        ),
        # Keyboard layout
        chip(
            ewidget.KeyboardLayout,
            name="w_lang",
            configured_keyboards=["us", "ara", "tr", "de"],
            display_map={
                "us": "🇺🇸 EN",
                "ara": "🇸🇦 AR",
                "tr": "🇹🇷 TR",
                "de": "🇩🇪 DE",
            },
            fmt="{}",
            padding=11,
            foreground=colors[4],
        ),
        # Clock
        chip(
            ewidget.Clock,
            format=" %a, %b %d - %H:%M",
            padding=11,
            foreground=colors[8],
            mouse_callbacks={"Button1": lambda: qtile.spawn("clock_popup")},
        ),
        # system tray widgetbox
        chip(
            ewidget.WidgetBox,
            name="systray_widgetbox",
            fontsize=11,
            padding=11,
            text_closed="△",
            text_open="",
            start_opened=False,
            close_button_location="right",
            widgets=[
                ewidget.Systray(
                    icon_size=14,
                    padding=6,
                    hide_crash=True,
                ),
            ],
            foreground=colors[4],
        ),
    ]


# ╔─────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░▀█▀░█▀█░█▀█░░░█▀▄░█▀█░█▀▄░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░░█░░█░█░█▀▀░░░█▀▄░█▀█░█▀▄░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░░▀░░▀▀▀░▀░░░░░▀▀░░▀░▀░▀░▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚─────────────────────────────────────────────────────────────╝


# ╔──────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░▀█▀░█▀█│
# │░▄█▄█▄░█░░░█▀█░░█░░█▀▀│
# │░░▀░▀░░▀▀▀░▀░▀░▀▀▀░▀░░│
# ╚──────────────────────╝

# ╭───────╮
# ╰───────╯
# this is the chip shape ("pill shape")


def chip(WCls, chip_color=None, **kwargs):
    deco = [
        RectDecoration(
            colour=chip_color if chip_color is not None else DEFAULT_CHIP_COLOR,
            radius=11,
            filled=True,
            padding_x=3,
            padding_y=2,
            # NOTE:  if u want just a border, u can use this
            # filled=False,
            # line_width=1.5,
            # line_colour= colorsW[8]
        )
    ]

    if "decorations" in kwargs and kwargs["decorations"]:
        kwargs["decorations"] = list(kwargs["decorations"]) + deco
    else:
        kwargs["decorations"] = deco

    w = WCls(**kwargs)

    return w


# ╔───────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░▀█▀░█▀█░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█░░░█▀█░░█░░█▀▀░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀▀▀░▀░▀░▀▀▀░▀░░░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────╝


# ╔──────────────────────────────────╗
# │░▄█▄█▄░█░█░█▀▀░█░█░█▄█░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█▀▄░█▀▀░░█░░█░█░█▀█░█▀▀░▀▀█│
# │░░▀░▀░░▀░▀░▀▀▀░░▀░░▀░▀░▀░▀░▀░░░▀▀▀│
# ╚──────────────────────────────────╝


keys = [
    # FIX: try to make a speach to text app
    # ---------------------
    # Key([mod], "s", lazy.spawn("bash -c \"notify-send '🎤 STT' 'Speak now…' && ~/.config/qtile/scripts/stt_script.sh\"")),
    # --- Open todo manager ---
    # --- Toggle system widget box ---
    Key(
        [mod2],
        "tab",
        lazy.widget["systray_widgetbox"].toggle(),
        desc="Toggle systry widget box",
    ),
    Key(
        [mod2],
        "grave",
        lazy.widget["system_widgetbox"].toggle(),
        desc="Toggle system widget box",
    ),
    Key(
        [mod],
        "grave",
        lazy.widget["2nd_system_widgetbox"].toggle(),
        desc="Toggle 2nd system widget box",
    ),
    # --- remap the alt key ---
    Key(
        [mod2, "shift"],
        "r",
        lazy.spawn(
            'sh -c \'xmodmap ~/.Xmodmap && notify-send "Qtile" "Alt keymap reapplied"\''
        ),
        desc="Reapply Alt keymap safely",
    ),
    # --- toggle sum.md nvim  ---
    Key(
        [mod2, "shift"],
        "s",
        lazy.function(lambda qtile: toggle_or_spawn_sum(qtile, my2ndTerm, sum_file)),
        desc="Open or focus sum.md globally",
    ),
    # ---zen-mode---
    Key(
        [mod, "shift"], "z", lazy.hide_show_bar(position="top"), desc="Toggle Zen Mode"
    ),
    # ---today & week: plans-todos popup---
    Key(
        [mod2],
        "p",
        lazy.spawn("clock_popup"),
        desc="clock popup (today & week: plans-todos)",
    ),
    # ---close notifications---
    Key([mod2], "n", lazy.spawn("dunstctl close")),
    # ---gptscript-inline---
    # FIX:  was working but now not......
    # Key(
    #     [mod],
    #     "g",
    #     lazy.spawn(
    #         "fish -c 'xdotool key ctrl+a ctrl+x; ~/.config/GptScript/gpt_inline_auto.py'"
    #     ),
    #     desc="gpt inline script (/gpt ,/mail, /sum)",
    # ),
    # ---toggle obsidian session---
    Key(
        [mod2, "shift"],
        "o",
        toggle_obsidian(),
        desc="Open Obsidian to draw (u should have exclidraw in obsidian)",
    ),
    # ---toggle telegram  session---
    Key([mod2, "shift"], "t", toggle_telegram(), desc="toggle telegram session"),
    # ---toggle sum.md nvim session---
    # Key([mod2, "shift"], "s",toggle_sum(),desc="toggle sum.md nvim session"),
    # ---toggle anki app session---
    Key([mod2, "shift"], "a", toggle_anki(), desc="toggle anki app session"),
    # ---toggle qutebrowser app session---
    Key(
        [mod],
        "v",
        toggle_qutebrowser(),
        desc="toggle qutebrowser session (video+others",
    ),
    # --- toggle terminal app session ---
    Key([mod], "n", toggle_terminal(), desc="toggle terminal session"),
    # --- toggle file manager app session ---
    Key([mod], "m", toggle_file_manager(), desc="toggle filemanager session"),
    # --- toggle brave app session ---
    Key([mod], "b", toggle_brave(), desc="toggle brave session(browsing)"),
    # ---open termianl---
    Key([mod], "Return", lazy.spawn(myTerm), desc="Terminal"),
    # ---open rofi---
    Key(
        [mod, "shift"],
        "Return",
        lazy.spawn("rofi -show drun -show-icons"),
        desc="Run Launcher",
    ),
    # ---toggle between layouts---
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    # ---kill focused window---
    Key([mod, "shift"], "c", lazy.window.kill(), desc="Kill focused window"),
    # ---reload the qtile config with notification and without---
    Key(
        [mod, "shift"],
        "r",
        lazy.function(
            lambda qtile: (
                qtile.reload_config(),
                qtile.spawn(
                    "notify-send -u critical -i dialog-ok-symbolic  'success' ' Qtile Config : Successfully reloaded!'"
                ),
            )
        ),
        desc="Reload the config",
    ),
    # --- logout menu ---
    Key([mod, "shift"], "q", lazy.spawn("dm-logout -r"), desc="Logout menu"),
    # --- spawn a command using a prompt widget ---
    Key([mod], "r", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),
    # Switch between windows
    # Some layouts like 'monadtall' only need to use j/k to move
    # through the stack, but other layouts like 'columns' will
    # require all four directions h/j/k/l to move around.
    # --- Move focus to left, right, down, up ---
    Key([mod], "h", lazy.layout.left(), desc="Move focus to left"),
    Key([mod], "l", lazy.layout.right(), desc="Move focus to right"),
    Key([mod], "j", lazy.layout.down(), desc="Move focus down"),
    Key([mod], "k", lazy.layout.up(), desc="Move focus up"),
    # Key([mod], "space", lazy.layout.next(), desc="Move window focus to other window"),
    # Move windows between left/right columns or move up/down in current stack.
    # Moving out of range in Columns layout will create new column.
    # --- Move window to the left,right,down,up in treetab ---
    Key(
        [mod, "shift"],
        "h",
        lazy.layout.shuffle_left(),
        lazy.layout.move_left().when(layout=["treetab"]),
        desc="Move window to the left/move tab left in treetab",
    ),
    Key(
        [mod, "shift"],
        "l",
        lazy.layout.shuffle_right(),
        lazy.layout.move_right().when(layout=["treetab"]),
        desc="Move window to the right/move tab right in treetab",
    ),
    Key(
        [mod, "shift"],
        "j",
        lazy.layout.shuffle_down(),
        lazy.layout.section_down().when(layout=["treetab"]),
        desc="Move window down/move down a section in treetab",
    ),
    Key(
        [mod, "shift"],
        "k",
        lazy.layout.shuffle_up(),
        lazy.layout.section_up().when(layout=["treetab"]),
        desc="Move window downup/move up a section in treetab",
    ),
    # Toggle between split and unsplit sides of stack.
    # Split = all windows displayed
    # Unsplit = 1 window displayed, like Max layout, but still with
    # multiple stack panes
    # --- Toggle between split and unsplit sides of stack ---
    Key(
        [mod, "shift"],
        "space",
        lazy.layout.toggle_split(),
        desc="Toggle between split and unsplit sides of stack",
    ),
    # Grow windows up, down, left, right.  Only works in certain layouts.
    # Works in 'bsp' and 'columns' layout.
    # --- Grow window up, down, left, right columns layout ---
    # NOTE: I don't use this anymore
    # Key([mod, "control"], "h", lazy.layout.grow_left(), desc="Grow window to the left"),
    # Key(
    #     [mod, "control"], "l", lazy.layout.grow_right(), desc="Grow window to the right"
    # ),
    # Key([mod, "control"], "j", lazy.layout.grow_down(), desc="Grow window down"),
    # Key([mod, "control"], "k", lazy.layout.grow_up(), desc="Grow window up"),
    # --- Toggle between min and max sizes ---
    Key([mod], "x", lazy.layout.maximize(), desc="Toggle between min and max sizes"),
    # --- toggle floating ---
    Key([mod], "t", lazy.window.toggle_floating(), desc="toggle floating"),
    # --- toggle fullscreen ---
    Key([mod], "f", lazy.window.toggle_fullscreen(), desc="toggle fullscreen"),
    # Switch focus of monitors
    # --- Move focus to next/prev monitor ---
    Key([mod], "period", lazy.next_screen(), desc="Move focus to next monitor"),
    Key([mod], "comma", lazy.prev_screen(), desc="Move focus to prev monitor"),
    # ╔──────────────────────────╗
    # │░▄█▄█▄░█▄█░█▀█░█▀▄░█▀▀░█▀▀│
    # │░▄█▄█▄░█░█░█░█░█░█░█▀▀░▀▀█│
    # │░░▀░▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀│
    # ╚──────────────────────────╝
    # --- Rofi MODE ---
    KeyChord(
        [mod],
        "p",
        [
            # NOTE : these commanted scripts are available u can use them , but i am not anymore
            # Key([], "a", lazy.spawn("dm-sounds -r"), desc='Choose ambient sound'),
            # Key([], "o", lazy.spawn("emacsclient --eval '(emacs-everywhere)'"), desc='Open emacs edit field'),
            # Key([], "c", lazy.spawn("dtos-colorscheme"), desc='Choose color scheme'),
            # Key([], "e", lazy.spawn("dm-confedit"), desc='Choose a config file to edit'),
            # Key([], "o", lazy.spawn("dm-bookman -r"), desc='Browser bookmarks'),
            # Key([], "p", lazy.spawn('passmenu -p "Pass: "'), desc="pass menu"),
            # Key([], "u", lazy.spawn("dm-music -r"), desc='Toggle music mpc/mpd')
            # Key([], "r", lazy.spawn("dm-record -r"), desc='record'),
            # Key([], "s", lazy.spawn("dm-websearch -r"), desc='Search various engines'),
            # Key([], "w", lazy.spawn("dm-wifi -r"), desc="Search wifi"),
            # --- Translate text ---
            # FIX: this is %70 working
            Key(
                [],
                "e",
                lazy.spawn(
                    "python3 /home/ati/.config/rofi_translator/wordreference.py"
                ),
                desc="Translate text",
            ),
            # --- add anki note ---
            # FIX: this is %50 working
            Key([], "a", lazy.spawn("rofi_anki"), desc="add anki note"),
            # --- Close all notifications ---
            Key(
                [],
                "x",
                lazy.spawn("dunstctl close-all"),
                desc="Close all notifications",
            ),
            # --- List all dmscripts ---
            Key([], "h", lazy.spawn("dm-hub -r"), desc="List all dmscripts"),
            # --- Choose a config file to edit ---
            Key(
                [], "f", lazy.spawn("dm-confedit"), desc="Choose a config file to edit"
            ),
            # --- choose shared link-preview ---
            Key([], "z", lazy.spawn("rofi_shared"), desc="shared link-preview"),
            # --- a Special mode for "Wallpaper Picker" ---
            # --- Wallpaper MODE ---
            KeyChord(
                [],
                "b",
                [
                    # NAVIGATE LEFT / RIGHT
                    Key([], "h", lazy.function(lambda _: WallpaperPopup.move(0, -1))),
                    Key([], "l", lazy.function(lambda _: WallpaperPopup.move(0, 1))),
                    Key(
                        [],
                        "R",
                        lazy.function(lambda _: WallpaperPopup.jump_to_random()),
                    ),
                    Key(
                        [],
                        "slash",
                        lazy.function(lambda _: WallpaperPopup.fuzzy_search_rofi()),
                    ),
                    # NAVIGATE DOWN / UP
                    Key([], "j", lazy.function(lambda _: WallpaperPopup.move(1, 0))),
                    Key([], "k", lazy.function(lambda _: WallpaperPopup.move(-1, 0))),
                    # ACTIONS
                    Key([], "Return", lazy.function(lambda _: WallpaperPopup.apply(_))),
                    Key(
                        [],
                        "q",
                        lazy.function(lambda _: WallpaperPopup.close_wallpaper_picker())
                        and lazy.ungrab_chord(),
                    ),
                    Key(
                        [],
                        "Escape",
                        lazy.function(
                            lambda _: WallpaperPopup.close_wallpaper_picker()
                        ),
                    ),
                ],
                mode=True,
                name="WallpaperPicker",
                desc="Wallpaper picker mode",
            ),
            # --- show documents ---
            Key([], "d", lazy.spawn("dm-documents -r"), desc="Show documents"),
            # make a screenshot of today's todos
            Key(
                [],
                "c",
                lazy.spawn("fish -c 'screenshot_todos_today'"),
                desc="Screenshot today's todos",
            ),
            # --- Take a screenshot v2 of dm-maim ---
            Key(
                [], "i", lazy.spawn("dm-satty"), desc="Take a screenshot v2 of dm-maim"
            ),
            # --- Kill processes ---
            Key([], "k", lazy.spawn("rofi-kill"), desc="Kill processes "),
            # --- View manpages ---
            Key([], "m", lazy.spawn("dm-man -r"), desc="View manpages"),
            # --- Store and copy notes ---
            Key([], "n", lazy.spawn("dm-note -r"), desc="Store and copy notes"),
            # --- rofi password menu ---
            Key([], "p", lazy.spawn("rofi-pass"), desc="Password menu"),
            # --- youtube menu ---
            Key(
                [],
                "y",
                lazy.spawn("dm-youtube -r"),
                desc="youtube menu",
            ),
            # --- logout menu ---
            Key([], "q", lazy.spawn("dm-logout -r"), desc="Logout menu"),
            # --- record  Version2 ---
            Key([], "r", lazy.spawn("dm-recordV2"), desc="record"),
            # ---  Spell check menu ---
            Key([], "s", lazy.spawn("dm-spellcheck -r"), desc="Spell check menu"),
            # --- Search weather ---
            Key([], "w", lazy.spawn("dm-weather -r"), desc="Search weather"),
            # --- Open todo manager ---
            Key([], "t", lazy.spawn("rofi_todo"), desc="Open todo manager"),
            # --- screen light ---
            Key([], "l", lazy.spawn("rofi_light"), desc="screen light"),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
        ],
        name="Rofi-Mode",
        swallow=True,
    ),
    # --- Media MODE ---
    KeyChord(
        [mod],
        "slash",
        [
            Key(["shift"], "j", lazy.function(lambda _: volume_change(-5))),
            Key(["shift"], "k", lazy.function(lambda _: volume_change(5))),
            Key(["shift"], "m", lazy.function(lambda _: toggle_mute())),
            Key(["shift"], "p", lazy.function(mpv_manager.toggle_pip_mode)),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
            Key([], "q", lazy.ungrab_chord()),
            Key([], "Escape", lazy.ungrab_chord()),
        ],
        name="Media-Mode",
        mode=True,
        swallow=True,
    ),
    # --- Resize MODE ---
    KeyChord(
        [mod2],
        "r",
        [
            # NOTE : not useing this anymore
            # # BSP / Columns (directional)
            # Key(
            #     [],
            #     "h",
            #     lazy.layout.grow_left().when(layout=["bsp", "columns"]),
            # ),
            # Key(
            #     [],
            #     "l",
            #     lazy.layout.grow_right().when(layout=["bsp", "columns"]),
            # ),
            # Key(
            #     [],
            #     "j",
            #     lazy.layout.grow_down().when(layout=["bsp", "columns"]),
            # ),
            # Key(
            #     [],
            #     "k",
            #     lazy.layout.grow_up().when(layout=["bsp", "columns"]),
            # ),
            # MonadTall / MonadWide (ratio-based)
            Key(
                ["shift"],
                "h",
                lazy.layout.shrink().when(layout=["monadtall", "monadwide"]),
            ),
            Key(
                ["shift"],
                "l",
                lazy.layout.grow().when(layout=["monadtall", "monadwide"]),
            ),
            Key(["shift"], "n", lazy.layout.reset()),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
            Key([], "q", lazy.ungrab_chord()),
            Key([], "Escape", lazy.ungrab_chord()),
        ],
        name="Resize-Mode",
        mode=True,
        swallow=True,
    ),
    # --- Scratch Mode ---
    # NOTE: it is working but i think it is not perfect using normal : win+12345....890 is better
    # BUT I WILL BE USING THEM FOR FUTURE SECONDARY APPS (NOT FOR PRIMARY APPS LIKE CHATGPT,WHATSAPP..etc)
    # Slack , OSB, Discord zoom , .....etc
    # KeyChord(
    #     [mod2],
    #     "s",
    #     [
    #         Key([], "1", lazy.group["scratchpad"].dropdown_toggle("term1")),
    #         Key([], "2", lazy.group["scratchpad"].dropdown_toggle("term2")),
    #         Key([], "3", lazy.group["scratchpad"].dropdown_toggle("mixer")),
    #         Key([], "4", lazy.group["scratchpad"].dropdown_toggle("2ndScreen")),
    #         Key([], "5", lazy.group["scratchpad"].dropdown_toggle("calc")),
    #         Key([], "8", lazy.group["scratchpad"].dropdown_toggle("whats")),
    #         Key([], "9", lazy.group["scratchpad"].dropdown_toggle("deepseek")),
    #         Key([], "0", lazy.group["scratchpad"].dropdown_toggle("chatgpt")),
    #         Key([], "q", lazy.ungrab_chord()),
    #         Key([], "Escape", lazy.ungrab_chord()),
    #     ],
    #     name="Scratch-Mode",
    #     mode=True,
    #     swallow=True
    # ),
    # --- Draw Mode ---
    KeyChord(
        [mod2, "shift"],
        "w",
        [
            Key([], "w", lazy.spawn("gromit-mpx -t"), desc="Gromit: toggle draw"),
            Key([], "c", lazy.spawn("gromit-mpx -c"), desc="Gromit: clear "),
            Key([], "z", lazy.spawn("gromit-mpx -z"), desc="Gromit: undo "),
            Key([], "r", lazy.spawn("gromit-mpx -y"), desc="Gromit: redo "),
            Key([], "v", lazy.spawn("gromit-mpx -v"), desc="Gromit: toggle visibility"),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
            Key([], "q", lazy.ungrab_chord()),
            Key([], "Escape", lazy.ungrab_chord()),
        ],
        name="Draw-Mode",
        mode=True,
        swallow=True,
    ),
    # --- Mouse Mode ---
    KeyChord(
        [mod2],
        "f",
        [
            Key([], "f", lazy.spawn("warpd --hint")),
            Key([], "n", lazy.spawn("warpd --normal")),
            # Key([], "g", lazy.spawn("warpd --grid")),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
            Key([], "q", lazy.ungrab_chord()),
            Key([], "Escape", lazy.ungrab_chord()),
            # fast scroll (gg / G equivalents)
            Key(
                [],
                "t",
                lazy.spawn("xdotool click --repeat 150 --delay 2 4"),
                desc="scroll up fast",
            ),
            Key(
                [],
                "b",
                lazy.spawn("xdotool click --repeat 150 --delay 2 5"),
                desc="scroll down fast",
            ),
        ],
        name="Mouse-Mode",
        mode=True,
        swallow=True,
    ),
    # --- Language switch MODE ---
    KeyChord(
        [mod2],
        "space",
        [
            Key([], 26, set_kb("us")),  # e
            Key([], 38, set_kb("ara")),  # a
            Key([], 28, set_kb("tr")),  # t
            Key([], 40, set_kb("de")),  # d
            Key([], "Escape", lazy.ungrab_chord()),
            Key([], "q", lazy.ungrab_chord()),
        ],
        name="Lang-Switch",
        mode=True,
        swallow=True,
    ),
    # --- Cheatsheet MODE ---
    KeyChord(
        [mod2, "shift"],
        "k",
        [
            Key(
                [],
                "k",
                lazy.function(toggle_cheatsheet),
                desc="Show cheatsheet",
            ),
            Key(
                [],
                "v",
                lazy.function(toggle_vim_cheatsheet),
                desc="Test popup widget scrolling",
            ),
            Key(
                [],
                "f",
                lazy.function(toggle_fish_kitty_cheatsheet),
                desc="Test popup widget scrolling",
            ),
            # NOTE:  workspace switching inside the modes ("by using 1,2,3,4,5,6,7,8,9,0")
            *group_keys(),
            Key(
                [],
                "q",
                lazy.function(exit_cheatsheet_mode),
                desc="Exit cheatsheet mode",
            ),
        ],
        name="CheatSheet-Mode",
        mode=True,
        swallow=True,
    ),
    # ╔───────────────────────────────────────────────────────╗
    # │░▄█▄█▄░█▄█░█▀█░█▀▄░█▀▀░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
    # │░▄█▄█▄░█░█░█░█░█░█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
    # │░░▀░▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
    # ╚───────────────────────────────────────────────────────╝
]

# ╔───────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█░█░█▀▀░█░█░█▄█░█▀█░█▀█░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█▀▄░█▀▀░░█░░█░█░█▀█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀░▀░▀▀▀░░▀░░▀░▀░▀░▀░▀░░░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────────╝


# ╔──────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▄░█▀█░█░█░█▀█░█▀▀│
# │░▄█▄█▄░█░█░█▀▄░█░█░█░█░█▀▀░▀▀█│
# │░░▀░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░░░▀▀▀│
# ╚──────────────────────────────╝


groups = [
    Group(
        "1",
        label="",
        matches=[
            Match(wm_class="ticktick"),
        ],
        layout="monadtall",
    ),
    Group(
        "2",
        label="",
        matches=[
            Match(wm_class="qutebrowser"),
            Match(wm_class="zen-browser"),
            Match(wm_class="vlc"),
            Match(wm_class="ops"),
            Match(wm_class="firefox"),
        ],
        layout="max",
    ),
    Group(
        "3",
        label="",
        matches=[Match(wm_class="org.gnome.Nautilus"), Match(wm_class="pcmanfm")],
        layout="monadtall",
    ),
    Group(
        "4",
        label="",
        matches=[
            Match(wm_class="code"),
            Match(wm_class="dev.zed.Zed"),
            Match(wm_class="kitty"),
            # Match(
            #     wm_class="alacritty",
            #     title=re.compile(r"^(?!.*(nvimsum|edit-field)).*$"),
            # ),
            Match(wm_class="cursor"),
        ],
        layout="monadtall",
    ),
    Group(
        "5",
        label="",
        matches=[
            Match(wm_class="brave"),
            Match(wm_class="brave-browser"),
        ],
        layout="max",
    ),
    Group(
        "6", label="👁", matches=[Match(wm_class="google-chrome")], layout="monadtall"
    ),
    Group("7", label="7", layout="monadtall"),
    Group("8", label="8", layout="monadtall"),
    Group(
        "S",
        layout="max",
        matches=[
            Match(wm_class="Anki"),
            Match(wm_class="obsidian"),
            Match(title="nvimsum"),
        ],
    ),
    Group(
        "9",
        label="",
        matches=[
            Match(wm_class="thunderbird"),
            Match(wm_class="TelegramDesktop"),
            Match(wm_class="discord"),
        ],
    ),
]


# -------------------------------------------------------
# this is  a special  WorkSpace  for  Obsidian  and  Anki
# -------------------------------------------------------

for i in groups:
    if i.name == "S":
        continue

    keys.extend(
        [
            Key(
                [mod],
                i.name,
                go_to_group_or_notify(i.name),
                desc=f"Switch to group {i.name}",
            ),
            Key(
                [mod, "shift"],
                i.name,
                lazy.window.togroup(i.name),
                desc="Move focused window to group {}".format(i.name),
            ),
        ]
    )


# ╔───────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▄░█▀█░█░█░█▀█░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█░█░█▀▄░█░█░█░█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░░░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────╝


# ╔──────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▀░█▀▄░█▀█░▀█▀░█▀▀░█░█░█▀█░█▀█░█▀▄░█▀▀│
# │░▄█▄█▄░▀▀█░█░░░█▀▄░█▀█░░█░░█░░░█▀█░█▀▀░█▀█░█░█░▀▀█│
# │░░▀░▀░░▀▀▀░▀▀▀░▀░▀░▀░▀░░▀░░▀▀▀░▀░▀░▀░░░▀░▀░▀▀░░▀▀▀│
# ╚──────────────────────────────────────────────────╝

# --------------------------------------------------------------------------------------------------------------
### NOTE: the width, height and x y opacity are just for the positioning it vary , you can change it as you want
# --------------------------------------------------------------------------------------------------------------
#
groups.append(
    ScratchPad(
        "scratchpad",
        [
            DropDown(
                "term1",
                "kitty",
                width=0.6,
                height=0.6,
                x=0.2,
                y=0.1,
                opacity=1,
            ),
            DropDown(
                "2ndScreen",
                "arandr",
                width=0.6,
                height=0.6,
                x=0.2,
                y=0.1,
                opacity=1,
            ),
            DropDown(
                "term2",
                "kitty",
                width=0.6,
                height=0.6,
                x=0.2,
                y=0.1,
                opacity=1,
            ),
            DropDown(
                "mixer",
                "env GTK_THEME=Adwaita:dark pavucontrol",
                width=0.4,
                height=0.6,
                x=0.3,
                y=0.1,
                opacity=1,
            ),
            DropDown(
                "calc",
                "env GTK_THEME=Adwaita:dark qalculate-gtk",
                width=0.6,
                height=0.6,
                x=0.2,
                y=0.1,
                opacity=1,
            ),
            DropDown(
                "collector",
                "flatpak run it.mijorus.collector",
                match=Match(wm_class="collector"),
                x=0.725,
                y=0.67,
                opacity=1.0,
                on_focus_lost_hide=False,
            ),
            ### NOTE:for chatgpt & deepseek & whatsapp i decided to use brave browser by using one browser engine for all, i  used separate profiles for
            ### each browser and it will be in the ~/.config/qtile/brave-profiles
            ### by using some flags i can disable some features like sync, background networking, component update, etc which will make it faster and reduce
            ### the memory usage ,cpu usage and battery usage
            DropDown(
                "chatgpt",
                f"brave --user-data-dir={os.path.expanduser('~')}/.config/qtile/brave-profiles/chatgpt "
                "--class=sp-chatgpt --name=sp-chatgpt "
                "--app=https://chat.openai.com "
                "--disable-background-networking "
                "--disable-component-update "
                "--disable-breakpad "
                "--disable-sync "
                "--no-first-run ",
                match=Match(wm_class="sp-chatgpt"),
                width=0.7,
                height=0.8,
                x=0.15,
                y=0.1,
                opacity=1,
                on_focus_lost_hide=False,
            ),
            DropDown(
                "deepseek",
                f"brave --user-data-dir={os.path.expanduser('~')}/.config/qtile/brave-profiles/deepseek "
                "--class=sp-deepseek --name=sp-deepseek --app=https://chat.deepseek.com "
                "--disable-background-networking "
                "--disable-component-update "
                "--disable-breakpad "
                "--disable-sync "
                "--no-first-run",
                match=Match(wm_class="sp-deepseek"),
                width=0.7,
                height=0.8,
                x=0.15,
                y=0.1,
                opacity=0.95,
                on_focus_lost_hide=False,
            ),
            DropDown(
                "whats",
                f"brave --user-data-dir={os.path.expanduser('~')}/.config/qtile/brave-profiles/whatsapp "
                "--class=sp-whatsapp --name=sp-whatsapp "
                "--app=https://web.whatsapp.com "
                "--disable-background-networking "
                "--disable-component-update "
                "--disable-breakpad "
                "--disable-sync "
                "--no-first-run ",
                match=Match(wm_class="sp-whatsapp"),
                width=0.7,
                height=0.8,
                x=0.15,
                y=0.1,
                opacity=0.95,
                on_focus_lost_hide=False,
            ),
        ],
    )
)

keys.extend(
    [
        Key(["mod4"], "1", lazy.group["scratchpad"].dropdown_toggle("term1")),
        Key(["mod4"], "2", lazy.group["scratchpad"].dropdown_toggle("term2")),
        Key(["mod4"], "3", lazy.group["scratchpad"].dropdown_toggle("mixer")),
        Key(["mod4"], "4", lazy.group["scratchpad"].dropdown_toggle("2ndScreen")),
        Key(["mod4"], "5", lazy.group["scratchpad"].dropdown_toggle("calc")),
        Key(["mod4"], "8", lazy.group["scratchpad"].dropdown_toggle("whats")),
        Key(["mod4"], "9", lazy.group["scratchpad"].dropdown_toggle("deepseek")),
        Key(["mod4"], "0", lazy.group["scratchpad"].dropdown_toggle("chatgpt")),
        Key(
            ["mod4", "shift"],
            "d",
            lazy.group["scratchpad"].dropdown_toggle("collector"),
        ),
    ]
)


# ╔───────────────────────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▀░█▀▄░█▀█░▀█▀░█▀▀░█░█░█▀█░█▀█░█▀▄░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░▀▀█░█░░░█▀▄░█▀█░░█░░█░░░█▀█░█▀▀░█▀█░█░█░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀▀▀░▀▀▀░▀░▀░▀░▀░░▀░░▀▀▀░▀░▀░▀░░░▀░▀░▀▀░░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────────────────────────╝


# ╔──────────────────────────────╗
# │░▄█▄█▄░█░░░█▀█░█░█░█▀█░█░█░▀█▀│
# │░▄█▄█▄░█░░░█▀█░░█░░█░█░█░█░░█░│
# │░░▀░▀░░▀▀▀░▀░▀░░▀░░▀▀▀░▀▀▀░░▀░│
# ╚──────────────────────────────╝


# Some settings that I use on almost every layout, which saves us
# from having to type these out for each individual layout.
layout_theme = {
    "border_width": 3,
    "margin": 5,
    "border_focus": colors[8],
    "border_normal": colors[1],
}

layouts = [
    # layout.Bsp(ratio=0.75,**layout_theme),
    # layout.Floating(**layout_theme)
    # layout.RatioTile(**layout_theme),
    # layout.VerticalTile(**layout_theme),
    # layout.Matrix(**layout_theme),
    # layout.MonadWide(**layout_theme),
    # layout.Stack(**layout_theme, num_stacks=2),
    # layout.Columns(**layout_theme),
    # layout.Zoomy(**layout_theme),
    # layout.Tile(shift_windows=True,ratio=0.75, **layout_theme),  # can be used  for write + reading + video = for fun
    layout.MonadTall(
        ratio=0.75,
        min_ratio=0.6,
        max_ratio=0.85,
        **layout_theme,
    ),
    layout.Max(
        border_width=0,
        margin=0,
    ),
    layout.TreeTab(
        font="Ubuntu Bold",
        fontsize=11,
        border_width=0,
        bg_color=colors[0],
        active_bg=colors[8],
        active_fg=colors[2],
        inactive_bg=colors[3],
        inactive_fg=colors[0],
        padding_left=8,
        padding_x=5,
        padding_y=6,
        sections=["ONE", "TWO", "THREE", "DEV"],
        section_fontsize=10,
        section_fg=colors[7],
        section_top=15,
        section_bottom=15,
        level_shift=8,
        vspace=3,
        panel_width=180,
    ),
]

# Some settings that I use on almost every widget, which saves us
# from having to type these out for each individual widget.
widget_defaults = dict(
    font="Ubuntu Bold",
    fontsize=10,
    padding=0,
)

extension_defaults = widget_defaults.copy()

# ╔───────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█░░░█▀█░█░█░█▀█░█░█░▀█▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█░░░█▀█░░█░░█░█░█░█░░█░░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀▀▀░▀░▀░░▀░░▀▀▀░▀▀▀░░▀░░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────╝


# ╔──────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▀░█▀▄░█▀▀░█▀▀░█▀█│
# │░▄█▄█▄░▀▀█░█░░░█▀▄░█▀▀░█▀▀░█░█│
# │░░▀░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░▀│
# ╚──────────────────────────────╝


def init_widgets_list():
    return [
        *left_side_widgets(),
        ewidget.Spacer(length=bar.STRETCH),
        groupbox_widget(),
        ewidget.Spacer(length=bar.STRETCH),
        *right_side_widgets(),
    ]


# Monitor 1 will display ALL widgets in widgets_list. It is important that this
# is the only monitor that displays all widgets because the systray widget will
# crash if you try to run multiple instances of it.


# TODO: FIX THE SYSTRAY issue later when i got 2nd screen :)
def init_widgets_screen1():
    widgets_screen1 = init_widgets_list()
    return widgets_screen1


# All other monitors' bars will display everything but widgets 22 (systray) and 23 (spacer).
def init_widgets_screen2():
    widgets_screen2 = init_widgets_list()
    # del widgets_screen2[22:24]
    return widgets_screen2


def init_screens():
    return [
        Screen(
            top=bar.Bar(
                widgets=init_widgets_screen1(),
                size=28,
                margin=[5, 10, 5, 10],  # top, right, bottom, left
                # IMP: this is the background color of the bar
                background="#11111b00",  # transparent
            ),
        ),
        Screen(
            top=bar.Bar(
                widgets=init_widgets_screen2(),
                size=28,
                margin=[5, 10, 5, 10],  # top, right, bottom, left
                # IMP: this is the background color of the bar
                background="#11111b00",  # transparent
            ),
        ),
    ]


if __name__ in ["config", "__main__"]:
    screens = init_screens()
    widgets_list = init_widgets_list()
    widgets_screen1 = init_widgets_screen1()
    widgets_screen2 = init_widgets_screen2()


# ╔───────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█▀▀░█▀▄░█▀▀░█▀▀░█▀█░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░▀▀█░█░░░█▀▄░█▀▀░█▀▀░█░█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░▀░▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────────╝


# ╔──────────────────────────╗
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░█▀▀│
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░▀▀█│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀│
# ╚──────────────────────────╝

# Drag floating layouts.
mouse = [
    Drag(
        [mod],
        "Button1",
        lazy.window.set_position_floating(),
        start=lazy.window.get_position(),
    ),
    Drag(
        [mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()
    ),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]


dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    border_focus=colors[8],
    border_width=2,
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="dialog"),  # dialog boxes
        Match(wm_class="download"),  # downloads
        Match(wm_class="error"),  # error msgs
        Match(wm_class="file_progress"),  # file progress boxes
        Match(wm_class="kdenlive"),  # kdenlive
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="notification"),  # notifications
        Match(wm_class="pinentry-gtk-2"),  # GPG key password entry
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(wm_class="toolbar"),  # toolbars
        Match(wm_class="Yad"),  # yad boxes
        Match(title="branchdialog"),  # gitk
        Match(title="Confirmation"),  # tastyworks exit box
        Match(title="Qalculate!"),  # qalculate-gtk
        Match(title="pinentry"),  # GPG key password entry
        Match(title="tastycharts"),  # tastytrade pop-out charts
        Match(title="tastytrade"),  # tastytrade pop-out side gutter
        Match(title="tastytrade - Portfolio Report"),  # tastytrade pop-out allocation
        Match(wm_class="tasty.javafx.launcher.LauncherFxApp"),  # tastytrade settings
        Match(title="imv"),  # Match the imv window
        Match(title="feh"),  # Match feh
        Match(wm_class="mpv"),  # mpv
        Match(wm_class="mpvk"),  # mpv
        Match(wm_class="satty"),  # satty
        Match(wm_class="emacs"),  # emacs
        Match(title="link-preview"),  # preview of nvim (qutebrowser edit link)
        Match(wm_class="org.gnome.NautilusPreviewer"),  # make the preview float
        # Match(wm_class="Anki"),  # make the preview float
    ],
)
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None


# ╔───────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────╝


# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"
