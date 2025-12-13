# scripts/toggle_apps.py
import os
from libqtile.lazy import lazy
from libqtile import hook
from libqtile.backend.base import Window

sum_group = "S"
sum_title = "nvimsum"
sum_file = os.path.expanduser("~/.config/rofi/Todo_files/sum.md")
obsidian_group = "S"
obsidian_class = "obsidian"
anki_group = "S"
qute_group = "5"
anki_class = "Anki"
file_manager_class = "pcmanfm"
qute_class = "qutebrowser"
brave_group = "2"
brave_class = "brave-browser"
google_chrome_class = "google-chrome"
terminal_class = "kitty"
terminal_group = "4"
file_manager_group = "3"
google_chrome_group = "6"
telegram_group = "9"
telegram_name_prefix = "Telegram"
last_group = [None]


def _focus_window_and_group(qtile, group_name, window: Window):
    """Helper: move to group and make sure window is the one shown in Max."""
    qtile.groups_map[group_name].toscreen()
    if window:
        qtile.current_group.focus(window, warp=True)


def _find_window_by_name(qtile, name: str):
    for w in qtile.windows_map.values():
        if w.name == name:
            return w
    return None


def _find_window_by_class(qtile, cls: str):
    for w in qtile.windows_map.values():
        if isinstance(w, Window):
            wm_class = w.get_wm_class()
            if wm_class and cls in wm_class:
                return w
    return None


def _find_window_by_class_sensitive(qtile, cls: str):
    """Find a window by wm_class (case-insensitive)."""
    for w in qtile.windows_map.values():
        if isinstance(w, Window):
            wm_class = w.get_wm_class()
            if wm_class and any(cls.lower() in c.lower() for c in wm_class):
                return w
    return None


# --- toggle apps ---


@lazy.function
def toggle_telegram(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, telegram_name_prefix)

    # Already in Telegram group and on Telegram → return back
    if current_group == telegram_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and telegram_name_prefix in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in Telegram group but not on Telegram → switch inside group
    if current_group == telegram_group and target_win:
        _focus_window_and_group(qtile, telegram_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, telegram_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[telegram_group].toscreen()
    qtile.cmd_spawn("Telegram")


@lazy.function
def toggle_file_manager(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, file_manager_class)

    # Already in Anki group and on Anki → return back
    if current_group == file_manager_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and file_manager_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in Anki group but not on Anki → switch inside group
    if current_group == file_manager_group and target_win:
        _focus_window_and_group(qtile, file_manager_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, file_manager_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[file_manager_group].toscreen()
    qtile.cmd_spawn("pcmanfm")


@lazy.function
def toggle_terminal(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    # Check if current window is Alacritty (case-insensitive)
    is_terminal = False
    if current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and any(terminal_class.lower() in c.lower() for c in wm_class):
            is_terminal = True

    # Already on Alacritty in group 4 → go back
    if current_group == terminal_group and is_terminal:
        if last_group[0]:
            qtile.groups_map[last_group[0]].toscreen()
        return

    # Find any Alacritty window specifically in group 4
    target_win = None
    for w in qtile.groups_map[terminal_group].windows:
        wm_class = w.get_wm_class()
        if wm_class and any(terminal_class.lower() in c.lower() for c in wm_class):
            target_win = w
            break

    # If exists in group 4 → focus it
    if target_win:
        last_group[0] = current_group
        _focus_window_and_group(qtile, terminal_group, target_win)
        return

    # Not open in group 4 → spawn it
    last_group[0] = current_group
    qtile.groups_map[terminal_group].toscreen()
    qtile.cmd_spawn("kitty")


@lazy.function
def toggle_qutebrowser(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, qute_class)

    # Already in Anki group and on Anki → return back
    if current_group == qute_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and qute_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    if current_group == qute_group and target_win:
        _focus_window_and_group(qtile, qute_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, qute_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[qute_group].toscreen()
    qtile.cmd_spawn("qutebrowser")


@lazy.function
def toggle_google_chrome(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, google_chrome_class)

    # Already in Anki group and on Anki → return back
    if current_group == google_chrome_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and google_chrome_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in Anki group but not on Anki → switch inside group
    if current_group == google_chrome_group and target_win:
        _focus_window_and_group(qtile, google_chrome_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, google_chrome_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[google_chrome_group].toscreen()
    qtile.cmd_spawn("google-chrome-stable")


@lazy.function
def toggle_brave(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, brave_class)

    # Already in Anki group and on Anki → return back
    if current_group == brave_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and brave_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in Anki group but not on Anki → switch inside group
    if current_group == brave_group and target_win:
        _focus_window_and_group(qtile, brave_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, brave_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[brave_group].toscreen()
    qtile.cmd_spawn("brave")


@lazy.function
def toggle_anki(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, anki_class)

    # Already in Anki group and on Anki → return back
    if current_group == anki_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and anki_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in Anki group but not on Anki → switch inside group
    if current_group == anki_group and target_win:
        _focus_window_and_group(qtile, anki_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, anki_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[anki_group].toscreen()
    qtile.cmd_spawn("anki")


@lazy.function
def toggle_sum(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_name(qtile, sum_title)

    # Already in S and on sum → return back
    if current_group == sum_group and current_win and current_win.name == sum_title:
        if last_group[0]:
            qtile.groups_map[last_group[0]].toscreen()
        return

    # Already in S but not on sum → switch inside S
    if current_group == sum_group and target_win:
        _focus_window_and_group(qtile, sum_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, sum_group, target_win)
        return

    # Not open → spawn it
    if not os.path.exists(sum_file):
        with open(sum_file, "w") as f:
            f.write("")

    qtile.groups_map[sum_group].toscreen()
    qtile.cmd_spawn(f"kitty --title {sum_title} -e nvim {sum_file}")


@lazy.function
def toggle_obsidian(qtile):
    current_group = qtile.current_group.name
    current_win = qtile.current_window

    target_win = _find_window_by_class(qtile, obsidian_class)

    # Already in S and on obsidian → return back
    if current_group == obsidian_group and current_win:
        wm_class = current_win.get_wm_class()
        if wm_class and obsidian_class in wm_class:
            if last_group[0]:
                qtile.groups_map[last_group[0]].toscreen()
            return

    # Already in S but not on obsidian → switch inside S
    if current_group == obsidian_group and target_win:
        _focus_window_and_group(qtile, obsidian_group, target_win)
        return

    # Normal toggle: save last group
    last_group[0] = current_group

    if target_win:
        _focus_window_and_group(qtile, obsidian_group, target_win)
        return

    # Not open → spawn it
    qtile.groups_map[obsidian_group].toscreen()
    qtile.cmd_spawn("obsidian")


# --- Hooks to return to previous group ---


# @hook.subscribe.client_killed
# def auto_return_after_alacritty_killed(window):
#     if not isinstance(window, Window):
#         return
#
#     wm_class = window.get_wm_class()
#     # Only trigger if it's Alacritty
#     if not wm_class or not any(alacritty_class.lower() in c.lower() for c in wm_class):
#         return
#
#     # Only trigger if the window was in group 4
#     if window.group and window.group.name == alacritty_group and last_group[0]:
#         window.qtile.groups_map[last_group[0]].toscreen()


@hook.subscribe.client_killed
def auto_return_after_anki_killed(window):
    if not isinstance(window, Window):
        return
    wm_class = window.get_wm_class()
    if wm_class and anki_class in wm_class and last_group[0]:
        window.qtile.groups_map[last_group[0]].toscreen()


# @hook.subscribe.client_killed
# def auto_return_after_file_manager_killed(window):
#     if not isinstance(window, Window):
#         return
#     wm_class = window.get_wm_class()
#     if wm_class and file_manager_class in wm_class and last_group[0]:
#         window.qtile.groups_map[last_group[0]].toscreen()

# @hook.subscribe.client_killed
# def auto_return_after_qutebrowser_killed(window):
#     if not isinstance(window, Window):
#         return
#     wm_class = window.get_wm_class()
#     if wm_class and qute_class in wm_class and last_group[0]:
#         window.qtile.groups_map[last_group[0]].toscreen()


# @hook.subscribe.client_killed
# def auto_return_after_telegram_killed(window):
#     if not isinstance(window, Window):
#         return
#     wm_class = window.get_wm_class()
#     if wm_class and telegram_name_prefix in wm_class and last_group[0]:
#         window.qtile.groups_map[last_group[0]].toscreen()
#


@hook.subscribe.client_killed
def auto_return_after_obsidian_killed(window):
    if not isinstance(window, Window):
        return
    wm_class = window.get_wm_class()
    if wm_class and obsidian_class in wm_class and last_group[0]:
        window.qtile.groups_map[last_group[0]].toscreen()


@hook.subscribe.client_killed
def auto_return_after_sum_killed(window):
    if window.name == sum_title and last_group[0]:
        window.qtile.groups_map[last_group[0]].toscreen()
