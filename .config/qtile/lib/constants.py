import os

ARCH_ICON_MAIN = "󰕰"
NON_EN_NOTIFY_ID = 9001

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

DEFAULT_CHIP_COLOR = colorsW[2]

CHORD_CHIP_COLORS = {
    "Resize-Mode": colorsW[5],
    "Rofi-Mode": colorsW[6],
    "Media-Mode": colorsW[4],
    "Scratch-Mode": colorsW[8],
    "Draw-Mode": colorsW[3],
    "Mouse-Mode": colorsW[7],
    "Lang-Switch": colorsW[1],
    "CheatSheet-Mode": colorsW[3],
    "WallpaperPicker": colorsW[3],
    "PASSTHROUGH": colorsW[8],
}

myTerm = "kitty"
my2ndTerm = "alacritty"
myFullScreenTerm = "kitty --start-as=fullscreen"

home = os.path.expanduser("~")
user = (os.environ.get("USER") or os.environ.get("LOGNAME") or "").upper()
todos_dir = os.path.expanduser(f"~/{user}TODOS")
sum_file = os.path.join(todos_dir, "TODOS.md")

mod = "mod4"
mod2 = "mod1"
