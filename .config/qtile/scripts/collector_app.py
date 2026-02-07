# NOTE:  here the best logic was : in order to avoid conflicts with other apps and to hide the collector when it is not needed
# is to not "minimize" is to "move it out of the screen" 


COLLECTOR_GROUP = "_collector"


def _find_collector(qtile):
    for w in qtile.windows_map.values():
        wm = w.window.get_wm_class()
        if wm and "collector" in wm[0].lower():
            return w
    return None


def _show_collector(qtile, w):
    screen = qtile.current_screen
    margin = 8
    width = 360

    x = screen.x + screen.width - width - margin
    y = screen.y + margin

    w.floating = True
    w.togroup(qtile.current_group.name)
    w.cmd_set_position_floating(x, y)
    w.cmd_bring_to_front()
    w.focus()


def _hide_collector(qtile, w):
    # park it in the hidden collector group
    w.togroup(COLLECTOR_GROUP)


def toggle_collector(qtile):
    w = _find_collector(qtile)

    if w:
        if w.group and w.group.name == COLLECTOR_GROUP:
            _show_collector(qtile, w)
        else:
            _hide_collector(qtile, w)
        return

    qtile.cmd_spawn("flatpak run it.mijorus.collector")

