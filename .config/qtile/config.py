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

# NOTE: Bluetooth popup will be used later
# from popups.BluetoothPopup import (
#     show as show_bluetooth_popup,
#     close as close_bluetooth_popup,
#     move as bluetooth_move,
#     toggle_device as bluetooth_toggle,
#     request_disconnect,
#     confirm_disconnect,
#     reload_devices,
# )


# NOTE : Audio popup will be used later
# from popups.AudioPopup import (
#     show as show_audio_popup,
#     close as close_audio_popup,
#     move as audio_move,
#     left as audio_left,
#     right as audio_right,
#     select as audio_select,
#     refresh as audio_refresh,
# )


# NOTE : WiFi popup will be used later
# from popups.WifiPopup import (
#     show as show_wifi_popup,
#     close as close_wifi_popup,
#     move_vertical as wifi_move,
#     move_horizontal as wifi_move_col,
#     select as wifi_select,
#     manual_refresh as wifi_manual_refresh,
# )

# NOTE: updates popup  will be used later
# from popups.UpdatesPopup import (
#     show as updates_popup,
#     move as updates_move,
#     toggle_select as updates_toggle,
#     request_update,
#     ignore_selected,
#     confirm,
#     rofi_search,
#     close as close_updates_popup,
# )

import colors as color_schemes
import logging

# ╔──────────────────────────────────────────╗
# │░▄█▄█▄░█░█░█▀█░█▀▄░▀█▀░█▀█░█▀▄░█░░░█▀▀░█▀▀│
# │░▄█▄█▄░▀▄▀░█▀█░█▀▄░░█░░█▀█░█▀▄░█░░░█▀▀░▀▀█│
# │░░▀░▀░░░▀░░▀░▀░▀░▀░▀▀▀░▀░▀░▀▀░░▀▀▀░▀▀▀░▀▀▀│
# ╚──────────────────────────────────────────╝


logging.basicConfig(level=logging.ERROR)

os.environ["GTK_IM_MODULE"] = "none"
os.environ["QT_IM_MODULE"] = "none"
os.environ["XMODIFIERS"] = ""

from lib import state
from lib.constants import (
    ARCH_ICON_MAIN,
    NON_EN_NOTIFY_ID,
    mod,
    mod2,
    myTerm,
    my2ndTerm,
    myFullScreenTerm,
    home,
    user,
    todos_dir,
    sum_file,
    colorsW,
    DEFAULT_CHIP_COLOR,
    CHORD_CHIP_COLORS,
)

passthrough_active = False
FLOAT_STATES = {}

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


# ╔──────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█│
# │░░▀░▀░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀│
# ╚──────────────────────────────────────────╝


# ------------------------------------------------
# -2- passthrough
# -------------------------------------------------


from lib.helpers import (
    _enable_passthrough,
    _disable_passthrough,
    passthrough_on,
    passthrough_off,
    apply_bar_mode,
    toggle_top_bottom_exclusive,
    show_layout_warning,
    hide_layout_warning,
    go_to_group_or_notify,
    group_keys,
    toggle_onboarding,
    set_icon_temporarily,
    open_terminal,
    open_launcher,
    ensure_gromit_and_toggle,
    exit_cheatsheet_mode,
    close_wallpaper_mode,
)


import lib.hooks  # noqa: F401  side-effect: registers @hook.subscribe.* handlers


# --------------------------------------------------------------------
# 14- Function to lanuch the Bluetooth popup when it's mode activated
# --------------------------------------------------------------------
# NOTE: Bluetooth popup will be used later
# @hook.subscribe.enter_chord
# def auto_enable_bluetooth_popup(chord_name):
#     if chord_name == "Bluetooth-Mode":
#         show_bluetooth_popup(qtile)


# ------------------------------------------------------------------------------
# 15 - Function to lanuch the Audio popup when it's mode activated
# ------------------------------------------------------------------------------


# NOTE : Audio popup will be used later
# @hook.subscribe.enter_chord
# def auto_enable_audio_popup(chord_name):
#     if chord_name == "Audio-Mode":
#         show_audio_popup(qtile)

# -----------------------------------------------------------
# 16 - Function to launch WiFi popup when mode is activated
# -----------------------------------------------------------


# NOTE : Wifi popup will be used later
# @hook.subscribe.enter_chord
# def auto_enable_wifi_popup(chord_name):
#     if chord_name == "Wifi-Mode":
#         show_wifi_popup(qtile)

# -----------------------------------------------------------
# 17 - Function to launch Updates popup when mode is activated
# -----------------------------------------------------------


# @hook.subscribe.enter_chord
# def auto_enable_updates_popup(chord_name):
#     if chord_name == "Updates-Mode":
#         updates_popup(qtile)


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
        # Reset options + reapply Xmodmap so Alt (mod1) survives layout switch
        qtile.spawn(
            f"sh -c 'setxkbmap -layout {layout} -option && xmodmap ~/.Xmodmap'"
        )

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


# ------------------------------------------------------------------------------
# 0- normal user bar
# -----------------------------------------------------------------------------
def normal_user_bar():
    return [
        widget.TextBox(
            name="main_icon_chip_nu",
            text=ARCH_ICON_MAIN,
            fontsize=19,
            padding=16,
            foreground=colors[7],
            mouse_callbacks={
                "Button1": lazy.function(open_launcher),
                "Button3": lazy.function(open_terminal),
            },
        ),
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=3,
            fontsize=14,
        ),
        widget.LaunchBar(
            progs=[
                ("", "brave", "Brave Browser"),
                ("", "qutebrowser", "Qutebrowser"),
                ("", "kitty", "Kitty Terminal"),
                ("", "pcmanfm", "File Manager"),
                ("󰨞", "code", "VS Code"),
            ],
            fontsize=14,
            padding=12,
            foreground=colors[1],
        ),
        ewidget.Spacer(length=bar.STRETCH),
        widget.GroupBox(
            fontsize=12,
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
            # hide_unused=True,
        ),
        ewidget.Spacer(length=bar.STRETCH),
        widget.Chord(
            name="chord_chip_nu",
            fmt=" {} ",
            padding=11,
            foreground=colors[7],
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
                "PASSTHROUGH": "   PASSTHROUGH : ESC , q",
                # NOTE: Bluetooth popup will be used later
                # "Bluetooth-Mode": "󰂯   BLUETOOTH : j , k , Enter , x , r",
                # NOTE: Audio popup will be used later
                # "Audio-Mode": "󰍬   AUDIO : j , k , h , l , Enter , r",
                # NOTE: Wifi popup will be used later
                # "Wifi-Mode": "󰤨   WIFI : j , k , Enter , x , r",
            }.get(name, name.upper()),
        ),
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=0,
            fontsize=14,
        ),
        widget.Battery(
            name="w_battery_nu",
            format="  {char}{percent:2.0%}",
            fontsize=11,
            padding=4,
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
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=4,
            fontsize=14,
        ),
        widget.CPU(
            name="w_cpu_nu",
            format="  {load_percent}%",
            fontsize=10,
            padding=4,
            foreground=colors[5],
            mouse_callbacks={
                "Button1": lambda: qtile.cmd_spawn(
                    "env GTK_THEME=Adwaita:dark missioncenter"
                )
            },
        ),
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=4,
            fontsize=14,
        ),
        widget.Memory(
            name="w_mem_nu",
            format="{MemUsed: .0f}{mm}",
            fmt="🖥  {} ",
            fontsize=10,
            padding=4,
            foreground=colors[8],
            mouse_callbacks={
                "Button1": lambda: qtile.cmd_spawn(myFullScreenTerm + " -e btop")
            },
        ),
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=0,
            fontsize=14,
        ),
        widget.Clock(
            format=" %a, %b %d - %H:%M",
            padding=14,
            fontsize=11,
            foreground=colors[1],
            mouse_callbacks={"Button1": lambda: qtile.spawn("clock_popup")},
        ),
    ]


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
        # Current Layout — original padding, text mode; right-click cycles layout
        chip(
            ewidget.CurrentLayout,
            padding=18,
            foreground=colors[3],
            mouse_callbacks={
                "Button3": lazy.next_layout(),
            },
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
            markup_normal='<span background="#00000055">{}</span>',
            markup_focused='<span background="#1a1b26EE" foreground="#7aa2f7" weight="bold">F {}</span>',
            markup_floating='<span background="#1a1b26EE" foreground="#da8548">V {}</span>',
            markup_focused_floating='<span background="#1a1b26EE" foreground="#ffaa00" weight="bold">VF {}</span>',
            markup_minimized='<span background="#1a1b26EE" foreground="#ff6c6b">↓ {}</span>',
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
                "PASSTHROUGH": "   PASSTHROUGH : ESC , q",
                # NOTE: Bluetooth popup will be used later
                # "Bluetooth-Mode": "󰂯   BLUETOOTH : j , k , Enter , x , r",
                # NOTE: Audio popup will be used later
                # "Audio-Mode": "󰍬   AUDIO : j , k , h , l , Enter , r",
                # NOTE: Wifi popup will be used later
                # "Wifi-Mode": "󰤨   WIFI : j , k , Enter , x , r",
                # NOTE: updates popup  will be used later
                # "Updates-Mode": "󰏖   UPDATES : j , k , h , l , space , Enter , y , n , ESC",
            }.get(name, name.upper()),
        ),
        # tooltip_widgetbox (lamp) — original leftmost of right cluster
        chip(
            SmartWidgetBox,
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
            SmartWidgetBox,
            name="system_widgetbox",
            insert_before_name="tooltip_widgetbox",
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
            ],
            foreground=colors[7],
        ),
        # wallpaper_toggle (X) — original position between system + 2nd_system
        chip(
            SmartWidgetBox,
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
                "Button1": lazy.function(
                    lambda q: (
                        SmartWidgetBox.close_all(),
                        q.simulate_keypress([mod], "p"),
                        q.simulate_keypress([], "b"),
                    )
                ),
            },
        ),
        chip(
            SmartWidgetBox,
            name="2nd_system_widgetbox",
            insert_before_name="tooltip_widgetbox",
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
                    # NOTE: upadtes popup click handler will be used later
                    # mouse_callbacks={
                    #     "Button1": lazy.spawn("sh -c 'xdotool key Alt_L+u '")
                    # },
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
            SmartWidgetBox,
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


class SmartWidgetBox(ewidget.WidgetBox):
    """WidgetBox that auto-closes siblings and inserts its content
    before an anchor widget (by name) instead of adjacent to itself."""

    _instances = []

    def __init__(self, *a, insert_before_name=None, **k):
        self.insert_before_name = insert_before_name
        super().__init__(*a, **k)
        SmartWidgetBox._instances.append(self)

    @classmethod
    def close_all(cls, except_self=None):
        for wb in cls._instances:
            if wb is not except_self and getattr(wb, "box_is_open", False):
                try:
                    super(SmartWidgetBox, wb).toggle()
                except Exception:
                    pass

    def toggle(self, *a, **k):
        if not getattr(self, "box_is_open", False):
            SmartWidgetBox.close_all(except_self=self)
        return super().toggle(*a, **k)

    def toggle_widgets(self):
        if not self.insert_before_name:
            return super().toggle_widgets()

        for widget in self.widgets:
            try:
                self.bar.widgets.remove(widget)
                widget.drawer.disable()
            except ValueError:
                continue

        target = None
        for w in self.bar.widgets:
            if getattr(w, "name", None) == self.insert_before_name:
                target = w
                break

        if target is None:
            return super().toggle_widgets()

        index = self.bar.widgets.index(target)

        if self.box_is_open:
            for widget in self.widgets[::-1]:
                widget.drawer.enable()
                self.bar.widgets.insert(index, widget)


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
    # --- voice dictation (whisper.cpp) ---
    Key(
        [mod, "shift"],
        "v",
        lazy.spawn("voice_dictate"),
        desc="Start/stop voice dictation (whisper.cpp -> xdotool type)",
    ),
    # --- refresh PC (reset_PC script) ---
    Key(
        [mod, "shift"],
        "F5",
        lazy.spawn(
            'sh -c \'notify-send "Qtile" "Refreshing PC…" && ~/.config/AtiScriptsV1/reset_PC\''
        ),
        desc="Refresh PC (reset_PC)",
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
        [mod, "shift"],
        "s",
        lazy.function(lambda qtile: toggle_or_spawn_sum(qtile, my2ndTerm, sum_file)),
        desc="Open or focus sum.md globally",
    ),
    # ---toggle to normal user bar---
    Key(
        [mod, "shift"],
        "z",
        toggle_top_bottom_exclusive,
        desc="Toggle Top ↔ Bottom bar",
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
        [mod, "shift"],
        "o",
        toggle_obsidian(),
        desc="Open Obsidian to draw (u should have exclidraw in obsidian)",
    ),
    # ---toggle telegram  session---
    Key([mod, "shift"], "t", toggle_telegram(), desc="toggle telegram session"),
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
                qtile.hide_show_bar(position="bottom", screen="current"),
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
        [mod],
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
        [mod, "shift"],
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
        [mod],
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
        [mod, "shift"],
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
    KeyChord(
        [mod],
        "F12",
        [
            Key([], "Escape", lazy.ungrab_chord()),
            Key([], "F12", lazy.ungrab_chord()),
        ],
        mode=True,
        name="PASSTHROUGH",
    ),
    # NOTE : Bluetooth popup will be used later
    # KeyChord(
    #     [mod],
    #     "u",
    #     [
    #         Key([], "j", lazy.function(lambda _: bluetooth_move(1))),
    #         Key([], "k", lazy.function(lambda _: bluetooth_move(-1))),
    #         Key([], "Return", lazy.function(lambda _: bluetooth_toggle())),
    #         Key([], "x", lazy.function(lambda _: request_disconnect())),
    #         Key([], "y", lazy.function(lambda _: confirm_disconnect(True))),
    #         Key([], "n", lazy.function(lambda _: confirm_disconnect(False))),
    #         Key([], "r", lazy.function(lambda _: reload_devices())),
    #         Key(
    #             [],
    #             "Escape",
    #             lazy.function(lambda qtile: close_bluetooth_popup(qtile)),
    #             lazy.ungrab_chord(),
    #         ),
    #     ],
    #     mode=True,
    #     name="Bluetooth-Mode",
    #     desc="Bluetooth device picker",
    # ),
    # NOTE : Audio popup will be used later
    # KeyChord(
    #     [mod],
    #     "o",
    #     [
    #         Key([], "j", lazy.function(lambda _: audio_move(1))),
    #         Key([], "k", lazy.function(lambda _: audio_move(-1))),
    #         Key([], "h", lazy.function(lambda _: audio_left())),
    #         Key([], "l", lazy.function(lambda _: audio_right())),
    #         Key([], "Return", lazy.function(lambda _: audio_select())),
    #         Key([], "r", lazy.function(lambda _: audio_refresh())),
    #         Key([], "Escape", lazy.function(lambda qtile: close_audio_popup(qtile))),
    #     ],
    #     mode=True,
    #     name="Audio-Mode",
    # ),
    # NOTE: Wifi popup will be used later
    # KeyChord(
    #     [mod],
    #     "i",
    #     [
    #         Key([], "j", lazy.function(lambda _: wifi_move(1))),
    #         Key([], "k", lazy.function(lambda _: wifi_move(-1))),
    #         Key([], "h", lazy.function(lambda _: wifi_move_col(-1))),
    #         Key([], "l", lazy.function(lambda _: wifi_move_col(1))),
    #         Key([], "Return", lazy.function(lambda _: wifi_select())),
    #         Key([], "r", lazy.function(lambda _: wifi_manual_refresh())),
    #         Key([], "Escape", lazy.function(lambda qtile: close_wifi_popup(qtile))),
    #     ],
    #     mode=True,
    #     name="Wifi-Mode",
    #     desc="WiFi network picker",
    # ),
    # NOTE: updates popup  will be used later
    # KeyChord(
    #     [mod],
    #     "u",
    #     [
    #         Key([], "j", lazy.function(lambda q: updates_move(1, 0))),
    #         Key([], "k", lazy.function(lambda q: updates_move(-1, 0))),
    #         Key([], "h", lazy.function(lambda q: updates_move(0, -1))),
    #         Key([], "l", lazy.function(lambda q: updates_move(0, 1))),
    #         Key([], "space", lazy.function(lambda q: updates_toggle())),
    #         Key([], "Return", lazy.function(lambda q: request_update())),
    #         Key([], "x", lazy.function(lambda q: ignore_selected())),
    #         Key([], "slash", lazy.function(lambda q: rofi_search())),
    #         Key(
    #             [],
    #             "y",
    #             lazy.function(
    #                 lambda q: confirm(True),
    #             ),
    #             lazy.ungrab_chord(),
    #         ),
    #         Key([], "n", lazy.function(lambda q: confirm(False))),
    #         Key(
    #             [],
    #             "Escape",
    #             lazy.function(lambda q: close_updates_popup(q)),
    #             lazy.ungrab_chord(),
    #         ),
    #     ],
    #     mode=True,
    #     name="Updates-Mode",
    # ),
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


from lib.groups import groups, build_nav_keys, build_scratchpad_keys
keys.extend(build_nav_keys(mod, groups))


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
keys.extend(build_scratchpad_keys(mod2))


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


from lib.rules import layout_theme, layouts

from lib.theme import widget_defaults, extension_defaults

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


def init_widgets_list_normaluserbar():
    return [
        *normal_user_bar(),
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


def init_widgets_normaluserbar():
    widgets_screen1 = init_widgets_list_normaluserbar()
    # del widgets_screen1[22:24]
    return widgets_screen1


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
            bottom=bar.Bar(
                widgets=init_widgets_list_normaluserbar(),
                size=40,
                margin=[5, 10, 5, 10],  # top, right, bottom, left
                # IMP: this is the background color of the bar
                background=colors[2],  # transparent
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

from lib.mouse import build_mouse
mouse = build_mouse(mod)


from lib.rules import (
    dgroups_key_binder,
    dgroups_app_rules,
    follow_mouse_focus,
    bring_front_click,
    cursor_warp,
    floating_layout,
    auto_fullscreen,
    focus_on_window_activation,
    reconfigure_screens,
    auto_minimize,
    wl_input_rules,
)


# ╔───────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────╝


from lib.rules import wmname
