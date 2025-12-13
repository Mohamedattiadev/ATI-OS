
# scripts/float_windows.py
from libqtile import hook
from libqtile.lazy import lazy
@hook.subscribe.client_new
def float_satty(window):
    if window.window.get_wm_class() and 'satty' in window.window.get_wm_class()[0].lower():
        window.floating = True
        window.cmd_set_size_floating(1000, 700)
        window.cmd_center()

@hook.subscribe.client_new
def float_edit_nvim(window):
    if window.window.get_name() == "edit-field":
        window.floating = True
        window.cmd_set_size_floating(650, 200)

@hook.subscribe.client_new
def float_link_preview(window):
    if window.window.get_name() == "link-preview":
        window.floating = True
        window.cmd_set_size_floating(200, 150)
        window.cmd_set_position_floating(100, 250)



#
# main_qutes = set()  # global set to track first main qutebrowser
#
# @hook.subscribe.client_new
# def float_extra_qutebrowsers(window):
#     global main_qutes
#
#     wm_class = window.window.get_wm_class()
#     title = window.window.get_name().lower() if window.window.get_name() else ""
#     wid = window.window.wid  # unique window id
#
#     # Treat windows without wm_class or with "whoops" in title as report/error
#     if not wm_class or "whoops" in title:
#         window.floating = True
#         window.cmd_set_size_floating(900, 600)
#         window.qtile.call_later(0.1, window.cmd_center)
#         return
#
#     # If this is the first main qutebrowser, keep it normal
#     if not main_qutes:
#         main_qutes.add(wid)
#         window.floating = False
#     else:
#         # Any subsequent normal qutebrowser floats
#         window.floating = True
#         window.cmd_set_size_floating(900, 600)
#         window.qtile.call_later(0.1, window.cmd_center)


@hook.subscribe.client_new
def float_extra_qutebrowsers(window):
    wm_class = window.window.get_wm_class()
    if not wm_class or "qutebrowser" not in wm_class[0].lower():
        return

    # Check existing qutebrowser windows (excluding this one)
    existing_qutes = [
        w for w in window.qtile.windows_map.values()
        if w != window
        and w.window.get_wm_class()
        and "qutebrowser" in w.window.get_wm_class()[0].lower()
    ]

    if existing_qutes:
        # If there is already at least one qutebrowser, float this new one
        window.floating = True
        window.cmd_set_size_floating(900, 600)

        # Use qtile's timer to center after a short delay
        def center_later():
            window.cmd_center()

        # Schedule centering after 100ms
        window.qtile.call_later(0.1, center_later)
    else:
        # First qutebrowser stays normal
        window.floating = False



#
# @hook.subscribe.client_new
# def float_anki(window):
#     wm_class = window.window.get_wm_class()
#     if wm_class and any("anki" == c.lower() for c in wm_class):
#         window.floating = True
#         window.cmd_set_size_floating(1000, 700)
#         window.cmd_center()
