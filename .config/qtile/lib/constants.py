import os

ARCH_ICON_MAIN = "󰕰"
NON_EN_NOTIFY_ID = 9001

myTerm = "kitty"
my2ndTerm = "alacritty"
myFullScreenTerm = "kitty --start-as=fullscreen"

home = os.path.expanduser("~")
user = (os.environ.get("USER") or os.environ.get("LOGNAME") or "").upper()
todos_dir = os.path.expanduser(f"~/{user}TODOS")
sum_file = os.path.join(todos_dir, "TODOS.md")

mod = "mod4"
mod2 = "mod1"
