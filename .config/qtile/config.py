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

import os
import re
import subprocess
from libqtile.backend.base import Window
import time
from typing import Optional
import logging
from libqtile import bar, extension, hook, layout, qtile, widget
from qtile_extras.widget.decorations import RectDecoration, BorderDecoration
from qtile_extras import widget as ewidget  # use extras’ widgets
from scripts.volume_control import volume_change, toggle_mute
from scripts.float_windows import *
from scripts.mpv_manager import mpv_manager
from scripts.toggle_apps import (
    toggle_qutebrowser,
    toggle_sum,
    toggle_obsidian,
    toggle_anki,
    toggle_telegram,
    toggle_terminal,
    toggle_file_manager,
    toggle_google_chrome,
    toggle_brave,
)
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

# from pathlib import Path
#
# Make sure 'qtile-extras' is installed or this config will not work.
# from qtile_extras import widget
# from qtile_extras.widget.decorations import BorderDecoration

# from qtile_extras.widget import StatusNotifier
import colors


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
os.environ["GTK_IM_MODULE"] = "none"
os.environ["QT_IM_MODULE"] = "none"
os.environ["XMODIFIERS"] = ""


mod = "mod1"  # Sets mod key to SUPER/WINDOWS
mod2 = "mod4"  # Sets mod key to SUPER/WINDOWS
# myTerm = "alacritty"  # My terminal of choice
myTerm = "kitty"  # My terminal of choice
myFullScreenTerm = "kitty --start-as=fullscreen"
myBrowser2 = ["brave", "--layout.css.devPixelsPerPx=0.8"]
myBrowser3 = ["google-chrome-stable", "--layout.css.devPixelsPerPx=0.8"]
myBrowser4 = "qutebrowser"
# myBrowser = ["zen-browser", "--layout.css.devPixelsPerPx=0.8"]
# myBrowser = ["qutebrowser", "--layout.css.devPixelsPerPx=0.8"]
# myBrowser = "firefox-small"  # My browser of choice


# edit_title = "edit-field"
home = os.path.expanduser("~")
# myEmacs = "emacsclient -c -a 'emacs' "  # The space at the end is IMPORTANT!


# Allows you to input a name when adding treetab section.
@lazy.layout.function
def add_treetab_section(layout):
    prompt = qtile.widgets_map["prompt"]
    prompt.start_input("Section name: ", layout.cmd_add_section)


# A function for hide/show all the windows in a group
@lazy.function
def minimize_all(qtile):
    for win in qtile.current_group.windows:
        if hasattr(win, "toggle_minimize"):
            win.toggle_minimize()


# --- helper: previous layout ---
def kb_prev(qtile):
    w = qtile.widgets_map["keyboardlayout"]  # change if your widget has a custom name
    layouts = w.configured_keyboards
    current = w.backend.get_keyboard()
    if current in layouts:
        prev = layouts[(layouts.index(current) - 1) % len(layouts)]
    else:
        prev = layouts[-1]
    w.backend.set_keyboard(prev, w.option)
    w.tick()



#     ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ██╗███╗   ██╗ ██████╗ ███████╗
#     ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██║████╗  ██║██╔════╝ ██╔════╝
#     █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║██║██╔██╗ ██║██║  ███╗███████╗
#     ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║██║██║╚██╗██║██║   ██║╚════██║
#     ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝██║██║ ╚████║╚██████╔╝███████║
#     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝


sum_file = os.path.expanduser("~/ATITODOS/TODOS.md")


@lazy.function
def toggle_or_spawn_sum(qtile):
    title = "sum.md".lower()

    # Search for existing window across ALL groups
    for group in qtile.groups:
        for win in group.windows:
            if title in (win.name or "").lower():
                # Bring to current workspace
                win.togroup(qtile.current_group.name)
                win.focus()

                # Make it global (sticky)
                if hasattr(win, "toggle_sticky"):
                    win.toggle_sticky()

                return

    # Not found → launch
    qtile.cmd_spawn(
        f"{myTerm} --title sum.md  -e nvim +':set nonumber norelativenumber' {sum_file}"
    )


keys = [
    # Key([mod], "s", lazy.spawn("bash -c \"notify-send '🎤 STT' 'Speak now…' && ~/.config/qtile/scripts/stt_script.sh\"")),
    # --- Open todo manager ---
    Key(
        [mod2, "shift"],
        "s",
        toggle_or_spawn_sum,  # ✅ NO parentheses
        lazy.layout.shuffle_down(),
        desc="Open or focus sum.md globally",
    ),
    # ---zen-mode---
    Key(
        [mod, "shift"], "z", lazy.hide_show_bar(position="top"), desc="Toggle Zen Mode"
    ),
    Key([mod2, "shift"], "k", lazy.spawn("rofi_keymaps"), desc="Show keymaps"),
    # --- Gromit-MPX controls ---
    Key([mod2, "shift"], "w", lazy.spawn("gromit-mpx -t"), desc="Gromit: toggle draw"),
    Key([mod2, "shift"], "z", lazy.spawn("gromit-mpx -z"), desc="Gromit: undo"),
    Key([mod2, "shift"], "r", lazy.spawn("gromit-mpx -y"), desc="Gromit: redo"),
    Key([mod2, "shift"], "c", lazy.spawn("gromit-mpx -c"), desc="Gromit: clear"),
    Key(
        [mod2, "shift"],
        "v",
        lazy.spawn("gromit-mpx -v"),
        desc="Gromit: toggle visibility",
    ),
    # ---today & week: plans-todos popup---
    Key(
        [mod2],
        "p",
        lazy.spawn("clock_popup"),
        desc="clock popup (today & week: plans-todos)",
    ),
    # ---volume---
    Key(
        [mod2],
        "bracketleft",
        lazy.function(lambda q: volume_change(-5)),
        desc="volume down",
    ),
    Key(
        [mod2],
        "bracketright",
        lazy.function(lambda q: volume_change(5)),
        desc="volume up",
    ),
    Key([mod2], "minus", lazy.function(lambda q: toggle_mute()), desc="mute volume"),
    # ---close notifications---
    Key([mod2], "n", lazy.spawn("dunstctl close")),
    # ---hints start---
    # Key([mod2], "f", lazy.spawn("hints")),
    # NOTE: need to do:
    # ```
    #  pipx install git+https://github.com/AlfredoSequeida/hints.git
    #  "Installing Wayland/X11-specific dependencies for 'hints'...""
    #  yay -S --needed --noconfirm libwnck3
    #
    #   NOTE: "Configuring accessibility environment variables in /etc/environment..."
    #       sudo tee -a /etc/environment >/dev/null <<EOF
    #       # Required for 'hints'
    #       ACCESSIBILITY_ENABLED=1
    #       GTK_MODULES=gail:atk-bridge
    #       OOO_FORCE_DESKTOP=gnome
    #       GNOME_ACCESSIBILITY=1
    #       QT_ACCESSIBILITY=1
    #       QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
    #       EOF
    # ```
    # "Enabling and starting hintsd and accessibility DBus service..."
    # systemctl --user enable --now hintsd.service
    # systemctl --user restart at-spi-dbus-bus.service
    #
    #  WARN: important to work:
    #   systemctl --user enable --now hintsd.service
    #   systemctl --user restart at-spi-dbus-bus.service
    # "NOTE: To customize hints configuration, edit:"
    # NOTE: copy the hintsConfig form `~/.dotfiles/installScript/hintsConfig.py`to this:
    #  `~/.local/share/pipx/venvs/hints/lib/python*/site-packages hints/constants.py`
    #
    # ---hints end---
    # ---gptscript-inline---
    Key(
        [mod],
        "g",
        lazy.spawn(
            "fish -c 'xdotool key ctrl+a ctrl+x; ~/.config/GptScript/gpt_inline_auto.py'"
        ),
        desc="gpt inline script (/gpt ,/mail, /sum)",
    ),
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
    Key([mod], "b", toggle_qutebrowser(), desc="toggle qutebrowser session"),
    # --- toggle terminal app session ---
    Key([mod], "n", toggle_terminal(), desc="toggle terminal session"),
    # --- toggle file manager app session ---
    Key([mod], "m", toggle_file_manager(), desc="toggle filemanager session"),
    # Key([mod2,"shift"], "n", toggle_alacritty(),desc="toggle alacritty session"),
    # --- toggle google chrome app session ---
    Key(
        [mod2, "shift"],
        "b",
        toggle_google_chrome(),
        desc="toggle google chrome session",
    ),
    # --- toggle brave app session ---
    Key([mod], "v", toggle_brave(), desc="toggle brave session"),
    # ---keyboardlayout---
    Key(
        [mod2],
        "space",
        lazy.widget["keyboardlayout"].next_keyboard(),
        desc="Switch keyboard layout",
    ),
    Key(
        [mod2, "shift"],
        "space",
        lazy.function(kb_prev),
        desc="Previous keyboard layout",
    ),
    # ---vimium like scroll motions---
    Key(
        [mod2, "shift"],
        "g",
        lazy.spawn("xdotool click --repeat 500 --delay 1 5"),
        desc="scroll down fast",
    ),
    Key([mod2], "g", lazy.spawn("gg_scroll"), desc="scroll up fast"),
    Key(
        [mod2],
        "j",
        lazy.spawn("xdotool click --repeat 4 --delay 1 5"),
        desc="scroll down x4",
    ),
    Key(
        [mod2],
        "k",
        lazy.spawn("xdotool click --repeat 4 --delay 1 4"),
        desc="scroll up x4",
    ),
    Key(
        [mod2],
        "h",
        lazy.spawn("xdotool click --repeat 4 --delay 1 6"),
        desc="scroll left x4",
    ),
    Key(
        [mod2],
        "l",
        lazy.spawn("xdotool click --repeat 4 --delay 1 7"),
        desc="scroll right x4",
    ),
    # ---left-middle-right click---
    Key([mod2], "m", lazy.spawn("xdotool click 1"), desc="left click"),
    # Key([mod2], "comma", lazy.spawn("xdotool click 2"),desc="middle click"),
    Key([mod2], "period", lazy.spawn("xdotool click 3"), desc=" right click"),
    # ---youtube like PIP mpv---
    Key(
        [mod],
        "slash",
        lazy.function(mpv_manager.toggle_pip_mode),
        desc="Toggle MPV PIP mode",
    ),
    # ---open termianl---
    Key([mod], "Return", lazy.spawn(myTerm), desc="Terminal"),
    # ---open rofi---
    Key(
        [mod, "shift"],
        "Return",
        lazy.spawn("rofi -show drun -show-icons"),
        desc="Run Launcher",
    ),
    # ---open browsers---
    # Key([mod], "b", lazy.spawn(myBrowser4), desc="Web browser"),
    # Key([mod, "shift"],"b", lazy.spawn(myBrowser3), desc="Web browser3"),
    # ---toggle between layouts---
    Key([mod], "Tab", lazy.next_layout(), desc="Toggle between layouts"),
    # ---kill focused window---
    Key([mod, "shift"], "c", lazy.window.kill(), desc="Kill focused window"),
    # ---reload the qtile config with notification and without---
    # Key([mod, "shift"], "r", lazy.reload_config(), desc="Reload the config"),
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
    # Treetab prompt
    # --- Prompt to add new section in treetab ---
    Key(
        [mod, "shift"],
        "a",
        add_treetab_section,
        desc="Prompt to add new section in treetab",
    ),
    # Grow/shrink windows left/right.
    # This is mainly for the 'monadtall' and 'monadwide' layouts
    # although it does also work in the 'bsp' and 'columns' layouts.
    # --- Grow window to the left,right ---
    Key(
        [mod],
        "equal",
        lazy.layout.grow_left().when(layout=["bsp", "columns"]),
        lazy.layout.grow().when(layout=["monadtall", "monadwide"]),
        desc="Grow window to the left",
    ),
    Key(
        [mod],
        "minus",
        lazy.layout.grow_right().when(layout=["bsp", "columns"]),
        lazy.layout.shrink().when(layout=["monadtall", "monadwide"]),
        desc="Grow window to the left",
    ),
    # Grow windows up, down, left, right.  Only works in certain layouts.
    # Works in 'bsp' and 'columns' layout.
    # --- Grow window up, down, left, right columns layout ---
    Key([mod, "control"], "h", lazy.layout.grow_left(), desc="Grow window to the left"),
    Key(
        [mod, "control"], "l", lazy.layout.grow_right(), desc="Grow window to the right"
    ),
    Key([mod, "control"], "j", lazy.layout.grow_down(), desc="Grow window down"),
    Key([mod, "control"], "k", lazy.layout.grow_up(), desc="Grow window up"),
    # --- Reset all window sizes ---
    # Key([mod], "n", lazy.layout.normalize(), desc="Reset all window sizes"),
    # --- Toggle between min and max sizes ---
    Key([mod], "x", lazy.layout.maximize(), desc="Toggle between min and max sizes"),
    # --- toggle floating ---
    Key([mod], "t", lazy.window.toggle_floating(), desc="toggle floating"),
    # --- toggle fullscreen ---
    Key([mod], "f", lazy.window.toggle_fullscreen(), desc="toggle fullscreen"),
    # --- Toggle hide/show all windows on current group ---
    Key(
        [mod, "shift"],
        "m",
        minimize_all(),
        desc="Toggle hide/show all windows on current group",
    ),
    # Switch focus of monitors
    # --- Move focus to next/prev monitor ---
    Key([mod], "period", lazy.next_screen(), desc="Move focus to next monitor"),
    Key([mod], "comma", lazy.prev_screen(), desc="Move focus to prev monitor"),
    # --- "P" with letter to do actions
    KeyChord(
        [mod],
        "p",
        [
            #
            # Key([], "a", lazy.spawn("dm-sounds -r"), desc='Choose ambient sound'),
            # Key([], "o", lazy.spawn("emacsclient --eval '(emacs-everywhere)'"), desc='Open emacs edit field'),
            # Key([], "c", lazy.spawn("dtos-colorscheme"), desc='Choose color scheme'),
            # Key([], "e", lazy.spawn("dm-confedit"), desc='Choose a config file to edit'),
            # Key([], "o", lazy.spawn("dm-bookman -r"), desc='Browser bookmarks'),
            # Key([], "p", lazy.spawn('passmenu -p "Pass: "'), desc="pass menu"),
            # Key([], "u", lazy.spawn("dm-music -r"), desc='Toggle music mpc/mpd')
            # Key([], "r", lazy.spawn("dm-record -r"), desc='record'),
            #
            # --- Translate text ---
            # Key([], "e", lazy.spawn("rofi_translator"), desc='Translate text'),
            Key(
                [],
                "e",
                lazy.spawn(
                    "python3 /home/ati/.config/rofi_translator/wordreference.py"
                ),
                desc="Translate text",
            ),
            # --- add anki note ---
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
            # --- Set background ---
            Key([], "b", lazy.spawn("dm-setbg -r"), desc="Set background"),
            # --- show documents ---
            Key([], "d", lazy.spawn("dm-documents -r"), desc="Set background"),
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
            # --- Search various engines ---
            # Key([], "s", lazy.spawn("dm-websearch -r"), desc='Search various engines'),
            # ---  Spell check menu ---
            Key([], "s", lazy.spawn("dm-spellcheck -r"), desc="Spell check menu"),
            # --- Search wifi ---
            Key([], "w", lazy.spawn("dm-wifi -r"), desc="Search wifi"),
            # --- Open todo manager ---
            Key([], "t", lazy.spawn("rofi_todo"), desc="Open todo manager"),
            # --- screen light ---
            Key([], "l", lazy.spawn("rofi_light"), desc="screen light"),
            # --- iLovePDF style image,pdf converter ---
            Key(
                [],
                "u",
                lazy.spawn("rofi_ilovepdf"),
                desc="Ultimate converter ( iLovePDF style image,pdf )",
            ),
        ],
    ),
]

#  ██████╗ ██████╗  ██████╗ ██╗   ██╗██████╗ ███████╗
# ██╔════╝ ██╔══██╗██╔═══██╗██║   ██║██╔══██╗██╔════╝
# ██║  ███╗██████╔╝██║   ██║██║   ██║██████╔╝███████╗
# ██║   ██║██╔══██╗██║   ██║██║   ██║██╔═══╝ ╚════██║
# ╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║     ███████║
#  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝


# NOTE: some icons may u need
# group_labels = ["", "", "👁", "", "", "", "✀", "🗯", "", "⎙"]
# group_labels = [
#     "",  # Terminal
#     "",  # Browser (Firefox)
#     "",  # Internet / Global
#     "",  # VSCode / Dev
#     "",  # Code
#     "",  # Files
#     "",  # Folder (alternative)
#     "",  # Folder-open
#     "",  # Layouts
#     "",  # Lab / Experiments
#     "",  # Slack / Chat
#     "",  # Telegram
#     "",  # Messages
#     "",  # Discord
#     "",  # Media / Video
#     "",  # Spotify
#     "🎵",  # Music
#     "🎮",  # Gaming
#     "🎨",  # Design / GFX
#     "",  # Images
#     "📸",  # Photography
#     "✀",  # Editing / Cut
#     "🧠",  # Study / Research
#     "📚",  # Reading
#     "💼",  # Work
#     "⚙️",  # System / Tools
#     "🧰",  # Toolbox
#     "📜",  # Docs / Writing
#     "🌐",  # Web general
#     "🌙",  # Chill / Night
# ]

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
            Match(wm_class="brave"),
            Match(wm_class="brave-browser"),
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
            Match(
                wm_class="Alacritty",
                title=re.compile(r"^(?!.*(nvimsum|edit-field)).*$"),
            ),
            Match(wm_class="cursor"),
        ],
        layout="monadtall",
    ),
    Group(
        "5",
        label="",
        matches=[Match(wm_class="qutebrowser")],
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
            # Match(wm_class="whatsdesk"),
            Match(wm_class="discord"),
        ],
    ),
]


for i in groups:
    if i.name == "S":
        continue  # Disable mod+s and mod+shift+s for the "S" group

    keys.extend(
        [
            # mod + group letter = switch to group
            Key(
                [mod],
                i.name,
                lazy.group[i.name].toscreen(),
                desc="Switch to group {}".format(i.name),
            ),
            Key(
                [mod, "shift"],
                i.name,
                lazy.window.togroup(i.name),
                desc="Move focused window to group {}".format(i.name),
            ),
        ]
    )

# ███████╗ ██████╗██████╗  █████╗ ████████╗ ██████╗██╗  ██╗██████╗  █████╗ ██████╗ ███████╗
# ██╔════╝██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝
# ███████╗██║     ██████╔╝███████║   ██║   ██║     ███████║██████╔╝███████║██║  ██║███████╗
# ╚════██║██║     ██╔══██╗██╔══██║   ██║   ██║     ██╔══██║██╔═══╝ ██╔══██║██║  ██║╚════██║
# ███████║╚██████╗██║  ██║██║  ██║   ██║   ╚██████╗██║  ██║██║     ██║  ██║██████╔╝███████║
# ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═════╝ ╚══════╝


### IMP: the width, height and x y opacity are just for the positioning it vary , you can change it as you want

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
                "note",
                "env GTK_THEME=Adwaita:dark notorious",
                width=0.3,
                height=0.6,
                x=0.0,
                y=0.01,
                opacity=1,
                on_focus_lost_hide=False,
            ),
            ### for chatgpt & deepseek & whatsapp i decided to use brave browser by using one browser engine for all, i  used separate profiles for
            ### each browser and it will be in the ~/.config/qtile/brave-profiles
            ### by using some flags i can disable some features like sync, background networking, component update, etc which will make it faster and reduce
            ### the memory usage ,cpu usage and battery usage
            # TODO: chage the /home/ati/.config to ~/.config
            # TODO: add the brave-profiles to the .gitignore
            DropDown(
                "chatgpt",
                "brave --user-data-dir=/home/ati/.config/qtile/brave-profiles/chatgpt "
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
                "brave --user-data-dir=/home/ati/.config/qtile/brave-profiles/deepseek "
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
                "brave --user-data-dir=/home/ati/.config/qtile/brave-profiles/whatsapp "
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
        Key(["mod4"], "8", lazy.group["scratchpad"].dropdown_toggle("whats")),
        Key(["mod4"], "9", lazy.group["scratchpad"].dropdown_toggle("deepseek")),
        Key(["mod4"], "0", lazy.group["scratchpad"].dropdown_toggle("chatgpt")),
    ]
)
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
#
# It is best not manually change the colorscheme; instead run 'dtos-colorscheme'
# which is set to 'MOD + p c'


#  ██████╗██╗  ██╗██╗██████╗     ███████╗████████╗██╗   ██╗██╗     ███████╗
# ██╔════╝██║  ██║██║██╔══██╗    ██╔════╝╚══██╔══╝╚██╗ ██╔╝██║     ██╔════╝
# ██║     ███████║██║██████╔╝    ███████╗   ██║    ╚████╔╝ ██║     █████╗
# ██║     ██╔══██║██║██╔═══╝     ╚════██║   ██║     ╚██╔╝  ██║     ██╔══╝
# ╚██████╗██║  ██║██║██║         ███████║   ██║      ██║   ███████╗███████╗
#  ╚═════╝╚═╝  ╚═╝╚═╝╚═╝         ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚══════╝
#
# (logo) ( monadtall ) | nvim config.py ~/c/qtile     CPU:54%  MEM:3445M  DISK:84%  SSD:86G  VOL:49%  LANG:EN  Sun,Nov 02 00:54 (systray)


def chip(WCls, **kwargs):
    deco = [
        RectDecoration(
            colour=colorsW[2],
            radius=11,  # <- roundness
            filled=True,
            padding_x=3,  # outer spacing so the rounded bg shows nicely
            padding_y=2,
        )
    ]
    if "decorations" in kwargs and kwargs["decorations"]:
        kwargs["decorations"] = list(kwargs["decorations"]) + deco
    else:
        kwargs["decorations"] = deco
    return WCls(**kwargs)


colors = colors.DoomOne

### LAYOUTS ###
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
    # layout.Tile(shift_windows=True,ratio=0.75, **layout_theme),  # i will use this for write + reading + video = for fun
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


def init_widgets_list():
    widgets_list = [
        # the logo part
        chip(
            ewidget.Image,
            filename="~/.config/qtile/icons/archLogo.png",
            margin=5,
            padding=13,
            scale="False",
            mouse_callbacks={"Button1": lambda: qtile.cmd_spawn(myTerm)},
        ),
        # the current layout part
        chip(
            ewidget.CurrentLayout,
            padding=18,
            foreground=colors[3],
        ),
        # the | part (not a styled chip)
        widget.TextBox(
            text="|", font="Ubuntu Mono", foreground=colors[1], padding=3, fontsize=14
        ),
        # the window name part (not a styled chip)
        widget.WindowName(
            foreground=colors[1],
            max_chars=50,
            padding=4,
            margin=5,
        ),
        # space from left  to keep group centered
        ewidget.Spacer(length=bar.STRETCH),
        # the group box part
        chip(
            ewidget.GroupBox,
            fontsize=9,
            margin_y=6,
            margin_x=8,
            padding_y=3,
            padding_x=8,
            borderwidth=3,
            active=colors[8],
            inactive=colors[1],
            highlight_color=colors[2],
            highlight_method="line",
            this_current_screen_border=colors[7],
            this_screen_border=colors[4],
            other_current_screen_border=colors[7],
            other_screen_border=colors[4],
            hide_unused=True,
        ),
        # space from right  to keep group centered
        ewidget.Spacer(length=bar.STRETCH),
        # the cpu part
        chip(
            ewidget.CPU,
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
        # the memory part
        chip(
            ewidget.Memory,
            format="{MemUsed: .0f}{mm}",
            fmt="🖥  {} ",
            fontsize=10,
            padding=11,
            foreground=colors[8],
            mouse_callbacks={
                "Button1": lambda: qtile.cmd_spawn(myFullScreenTerm + " -e btop")
            },
        ),
        # the battery part
        chip(
            ewidget.Battery,
            format="  {char} {percent:2.0%}",
            fontsize=10,
            padding=12,
            foreground=colors[6],  # > 20%
            low_foreground=colors[3],  # < 20%
            low_percentage=0.2,
            charge_char=" P↑ ",
            discharge_char=" P↓ ",
            full_char=" P✔ ",
            show_percentage=True,
            show_short_text=True,
            mouse_callbacks={
                "Button1": lambda: qtile.cmd_spawn(
                    '/bin/sh -c \'notify-send "Battery Status" "$(acpi | cut -d "," -f 2-)"\''
                )
            },
        ),
        # the disk part
        chip(
            ewidget.DF,
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
        # the volume part
        chip(
            ewidget.Volume,
            fmt="🕫  {}",
            padding=11,
            foreground=colors[7],
        ),
        # the keyboard layout part
        chip(
            ewidget.KeyboardLayout,
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
        # the clock part
        chip(
            ewidget.Clock,
            format=" %a, %b %d - %H:%M",
            padding=11,
            foreground=colors[8],
            mouse_callbacks={"Button1": lambda: qtile.spawn("clock_popup")},
        ),
        # the system tray part (icons)
        widget.Systray(padding=7, icon_size=14),
    ]
    return widgets_list


# Monitor 1 will display ALL widgets in widgets_list. It is important that this
# is the only monitor that displays all widgets because the systray widget will
# crash if you try to run multiple instances of it.
def init_widgets_screen1():
    widgets_screen1 = init_widgets_list()
    return widgets_screen1


# All other monitors' bars will display everything but widgets 22 (systray) and 23 (spacer).
def init_widgets_screen2():
    widgets_screen2 = init_widgets_list()
    del widgets_screen2[22:24]
    return widgets_screen2


# For adding transparency to your bar, add (background="#00000000") to the "Screen" line(s)
# For ex: Screen(top=bar.Bar(widgets=init_widgets_screen2(), background="#00000000", size=24)),

#
# def init_screens():
#     return [
#         Screen(top=bar.Bar(widgets=init_widgets_screen1(),
#     margin=[4, 50, 4, 50],  # top, right, bottom, left
#     size=28 ,
#             background = "#11111b00")),
#         # Screen(top=bar.Bar(widgets=init_widgets_screen2(), size=26)),
#         Screen(top=bar.Bar(widgets=init_widgets_screen2(), size=26)),
#     ]


def init_screens():
    return [
        Screen(
            top=bar.Bar(
                # all widgets (including your chip) go in this list
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
                size=26,
            ),
        ),
    ]


if __name__ in ["config", "__main__"]:
    screens = init_screens()
    widgets_list = init_widgets_list()
    widgets_screen1 = init_widgets_screen1()
    widgets_screen2 = init_widgets_screen2()

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
        Match(title="ImagePopup"),  # Match the feh window
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


@hook.subscribe.startup_once
def start_once():
    home = os.path.expanduser("~")
    subprocess.call([home + "/.config/qtile/autostart.sh"])

    # -------------------------------------------


# def assign_app_to_group(client):
#     wm_class = client.window.get_wm_class()
#     if wm_class:
#         if wm_class[0] in ["firefox", "chrome", "brave", "vivaldi"]:
#             client.togroup("3")
#         # Add more rules as needed

# -------------------------------------------


# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"
