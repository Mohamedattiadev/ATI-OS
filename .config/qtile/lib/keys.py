from libqtile.config import Key, KeyChord
from libqtile.lazy import lazy

from scripts.volume_control import volume_change, toggle_mute
from scripts.mpv_manager import mpv_manager
from scripts.sum_app import toggle_or_spawn_sum
from scripts.toggle_apps import (
    toggle_qutebrowser,
    toggle_obsidian,
    toggle_anki,
    toggle_telegram,
    toggle_terminal,
    toggle_file_manager,
    toggle_brave,
)

from popups.QtileCheatsheet import toggle_cheatsheet
from popups.VimCheatsheet import toggle_vim_cheatsheet
from popups.FishCheatsheet import toggle_fish_kitty_cheatsheet
from popups import WallpaperPopup
from popups.WallpaperPopup import close_wallpaper_picker

from lib.constants import mod, mod2, myTerm, my2ndTerm, sum_file
from lib.helpers import (
    group_keys,
    exit_cheatsheet_mode,
    toggle_top_bottom_exclusive,
    set_kb,
)


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
