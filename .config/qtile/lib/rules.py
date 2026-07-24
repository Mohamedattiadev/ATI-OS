from libqtile import layout
from libqtile.config import Match

import colors as color_schemes

colors = color_schemes.DoomOne

layout_theme = {
    "border_width": 3,
    "margin": 5,
    "border_focus": colors[8],
    "border_normal": colors[1],
}

layouts = [
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
        border_width=8,
        border_focus=colors[0],
        border_normal=colors[0],
        margin_left=8,
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

dgroups_key_binder = None
dgroups_app_rules = []
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False

floating_layout = layout.Floating(
    border_focus=colors[7],
    border_width=2,
    float_rules=[
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),
        Match(wm_class="dialog"),
        Match(wm_class="download"),
        Match(wm_class="error"),
        Match(wm_class="file_progress"),
        Match(wm_class="kdenlive"),
        Match(wm_class="makebranch"),
        Match(wm_class="maketag"),
        Match(wm_class="notification"),
        Match(wm_class="pinentry-gtk-2"),
        Match(wm_class="ssh-askpass"),
        Match(wm_class="toolbar"),
        Match(wm_class="Yad"),
        Match(title="branchdialog"),
        Match(title="Confirmation"),
        Match(title="Qalculate!"),
        Match(title="pinentry"),
        Match(title="tastycharts"),
        Match(title="tastytrade"),
        Match(title="tastytrade - Portfolio Report"),
        Match(wm_class="tasty.javafx.launcher.LauncherFxApp"),
        Match(title="imv"),
        Match(title="feh"),
        Match(wm_class="mpv"),
        Match(wm_class="mpvk"),
        Match(wm_class="satty"),
        Match(wm_class="emacs"),
        Match(title="link-preview"),
        Match(wm_class="org.gnome.NautilusPreviewer"),
    ],
)

auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True
auto_minimize = True
wl_input_rules = None
wmname = "LG3D"
