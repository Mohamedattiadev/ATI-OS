import os

from libqtile.config import DropDown, Group, Key, Match, ScratchPad
from libqtile.lazy import lazy

from lib.helpers import go_to_group_or_notify


groups = [
    Group(
        "1",
        label="",
        matches=[Match(wm_class="ticktick")],
        layout="monadtall",
    ),
    Group(
        "2",
        label="",
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
        label="",
        matches=[Match(wm_class="org.gnome.Nautilus"), Match(wm_class="pcmanfm")],
        layout="monadtall",
    ),
    Group(
        "4",
        label="",
        matches=[
            Match(wm_class="code"),
            Match(wm_class="dev.zed.Zed"),
            Match(wm_class="kitty"),
            Match(wm_class="cursor"),
        ],
        layout="monadtall",
    ),
    Group(
        "5",
        label="",
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
        label="",
        matches=[
            Match(wm_class="thunderbird"),
            Match(wm_class="TelegramDesktop"),
            Match(wm_class="discord"),
        ],
    ),
]


groups.append(
    ScratchPad(
        "scratchpad",
        [
            DropDown("term1", "kitty", width=0.6, height=0.6, x=0.2, y=0.1, opacity=1),
            DropDown("2ndScreen", "arandr", width=0.6, height=0.6, x=0.2, y=0.1, opacity=1),
            DropDown("term2", "kitty", width=0.6, height=0.6, x=0.2, y=0.1, opacity=1),
            DropDown(
                "mixer",
                "env GTK_THEME=Adwaita:dark pavucontrol",
                width=0.4, height=0.6, x=0.3, y=0.1, opacity=1,
            ),
            DropDown(
                "calc",
                "env GTK_THEME=Adwaita:dark qalculate-gtk",
                width=0.6, height=0.6, x=0.2, y=0.1, opacity=1,
            ),
            DropDown(
                "collector",
                "flatpak run it.mijorus.collector",
                match=Match(wm_class="collector"),
                x=0.725, y=0.67, opacity=1.0, on_focus_lost_hide=False,
            ),
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
                width=0.7, height=0.8, x=0.15, y=0.1, opacity=1,
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
                width=0.7, height=0.8, x=0.15, y=0.1, opacity=0.95,
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
                width=0.7, height=0.8, x=0.15, y=0.1, opacity=0.95,
                on_focus_lost_hide=False,
            ),
        ],
    )
)


def build_nav_keys(mod, groups_list):
    result = []
    for i in groups_list:
        if i.name in ("S", "scratchpad"):
            continue
        result.extend([
            Key([mod], i.name, go_to_group_or_notify(i.name),
                desc=f"Switch to group {i.name}"),
            Key([mod, "shift"], i.name, lazy.window.togroup(i.name),
                desc=f"Move focused window to group {i.name}"),
        ])
    return result


def build_scratchpad_keys(mod2):
    return [
        Key([mod2], "1", lazy.group["scratchpad"].dropdown_toggle("term1")),
        Key([mod2], "2", lazy.group["scratchpad"].dropdown_toggle("term2")),
        Key([mod2], "3", lazy.group["scratchpad"].dropdown_toggle("mixer")),
        Key([mod2], "4", lazy.group["scratchpad"].dropdown_toggle("2ndScreen")),
        Key([mod2], "5", lazy.group["scratchpad"].dropdown_toggle("calc")),
        Key([mod2], "8", lazy.group["scratchpad"].dropdown_toggle("whats")),
        Key([mod2], "9", lazy.group["scratchpad"].dropdown_toggle("deepseek")),
        Key([mod2], "0", lazy.group["scratchpad"].dropdown_toggle("chatgpt")),
        Key([mod2, "shift"], "d",
            lazy.group["scratchpad"].dropdown_toggle("collector")),
    ]
