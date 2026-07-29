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
import sys
import time
import threading
from libqtile import bar, hook, layout, qtile, widget
from qtile_extras.widget.decorations import RectDecoration
from qtile_extras import widget as ewidget
from qtile_extras.widget.mixins import TooltipMixin
from scripts.volume_control import volume_change, toggle_mute
from scripts.brightness_control import brightness_change

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
from scripts.sum_app import float_center_sum, is_sum_window, toggle_or_spawn_sum
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

# ----------------------------------------------------------------
# Stop xmodmap blocking startup.
#
# libqtile's KeyboardLayout widget runs `xmodmap ~/.Xmodmap` through a
# blocking check_output while the bar is being built. ~/.Xmodmap here
# rewrites the modifier map (clear mod1 / add mod1 for the Caps->Alt
# remap), and xmodmap refuses to do that while ANY modifier key is held,
# retrying at 2s, 4s, 8s, 16s, 32s. The restart keybind is Super+Shift+R,
# so Super is always still down at that moment -- measured at 15s of dead
# startup time on this config, which was the entire reason restarts felt
# slow. There is no XKB option equivalent to this remap (no `caps:alt`),
# so the Xmodmap has to stay; it just must not be on the critical path.
#
# Same command, fire-and-forget. _reapply_xmodmap_when_idle() below then
# guarantees it actually lands once the keyboard is quiet.
# ----------------------------------------------------------------
try:
    from libqtile.widget import keyboardlayout as _kbl

    def _set_keyboard_nonblocking(self, layout, options):
        command = ["setxkbmap"]
        command.extend(layout.split(" "))
        if options:
            command.extend(["-option", options])
        try:
            subprocess.check_output(command)
        except Exception:
            return
        if os.path.isfile(os.path.expanduser("~/.Xmodmap")):
            try:
                subprocess.Popen(
                    ["sh", "-c", "xmodmap $HOME/.Xmodmap"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except Exception:
                pass

    _kbl._X11LayoutBackend.set_keyboard = _set_keyboard_nonblocking
except Exception:
    pass

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

ARCH_ICON_MAIN = "󰕰"

DEFAULT_CHIP_COLOR = colorsW[2]

os.environ["GTK_IM_MODULE"] = "none"
os.environ["QT_IM_MODULE"] = "none"
os.environ["XMODIFIERS"] = ""

mod = "mod4"  # Primary mod = WINDOWS (Alt broken on hardware)
mod2 = "mod1"  # Secondary mod = ALT
myTerm = "kitty"  # My terminal of choice
my2ndTerm = "alacritty"  # My terminal of choice
myFullScreenTerm = "kitty --start-as=fullscreen"
home = os.path.expanduser("~")
user = (os.environ.get("USER") or os.environ.get("LOGNAME") or "").upper()
todos_dir = os.path.expanduser(f"~/{user}TODOS")
sum_file = os.path.join(todos_dir, "TODOS.md")

BAR_MODE = "top"  # "top" or "bottom"

ACTIVE_CHORD = None

NON_EN_NOTIFY_ID = 9001


passthrough_active = False
_PASS_PREV_BAR_MODE = None
_PASS_CONFIRM_LAYOUT = None
# qtile hardcodes Escape to leave any chord (core/manager.py: `key.key == "Escape"`),
# so Esc always ungrabs before we can veto it. _PASS_NEXT tells the leave_chord hook
# which chord to re-enter instead of tearing passthrough down:
#   "CONFIRM" -> the y/n popup chord, "PASS" -> back to passthrough, None -> really exit.
_PASS_NEXT = None
PASSTHROUGH_CHORD = None
PASSTHROUGH_CONFIRM_CHORD = None
FLOAT_STATES = {}

colors: list[list[str]] = color_schemes.active_palette()


# ────────────────────────────────────────────────────────────────────
# Live palette swap — instant theme change without qtile restart.
# theme-apply invokes this via `qtile cmd-obj -f eval` after writing
# the new mode to ~/.cache/qtile/theme_mode. Walks every widget in
# every bar, remaps colors by slot index (matched against the old
# palette hex), then redraws. Falls back to restart in theme-apply
# if this fails or a widget skips redraw.
#
# Slot mapping is derived from the current `colors` global: each
# hex the widget currently holds is looked up in old_palette →
# replaced with the same slot from new_palette. Works for any
# widget attr set from `colors[N]` at construction (foreground /
# background / border_color / GroupBox active|inactive|highlight_*
# / RectDecoration.colour|colours|line_colour / decoration lists).
# ────────────────────────────────────────────────────────────────────

# widget/decoration attributes we scan for palette hexes
_PALETTE_ATTRS = (
    "foreground", "background", "border_color",
    "active", "inactive", "urgent_border",
    "this_current_screen_border", "this_screen_border",
    "other_current_screen_border", "other_screen_border",
    "highlight_color", "block_highlight_text_color",
    "fill_color", "colour", "colours", "line_colour",
    "border", "border_focus", "border_normal",
)


def _remap_palette_value(val, slot):
    """Given a widget attr value and a hex→slot map, return the new
    value with each recognized hex replaced. Preserves structure
    (str stays str, list stays list, tuple stays tuple)."""
    if isinstance(val, str):
        return slot.get(val, val)
    if isinstance(val, (list, tuple)):
        typ = type(val)
        return typ(_remap_palette_value(v, slot) for v in val)
    return val


def apply_palette_live():
    """Mutate every bar widget's palette-derived color to the new
    palette on disk. No qtile restart, no widget re-instantiation.

    Slot map built from EVERY known preset (not just current), so a
    decoration built with e.g. doomone hex still resolves after
    dracula was swapped in-between: any hex → its slot index in
    ANY preset → new palette's hex at same slot."""
    global colors
    import importlib
    importlib.reload(color_schemes)
    new_palette_rows = color_schemes.active_palette()
    new_flat = [row[0] if isinstance(row, (list, tuple)) else row for row in new_palette_rows]
    # Build hex → slot index map from every registered preset + wal.
    hex_to_slot = {}
    presets = list(color_schemes._PRESETS.values())
    wal = getattr(color_schemes, "Wal", None)
    if wal:
        presets.append(wal)
    for pal in presets:
        for i, row in enumerate(pal):
            h = row[0] if isinstance(row, (list, tuple)) else row
            if isinstance(h, str) and h not in hex_to_slot:
                hex_to_slot[h] = i
                hex_to_slot[h.lower()] = i
                hex_to_slot[h.upper()] = i
    if len(new_flat) < 9:
        return False
    def remap_hex(h):
        if not isinstance(h, str):
            return h
        idx = hex_to_slot.get(h)
        if idx is None:
            idx = hex_to_slot.get(h.lower())
        if idx is None:
            return h
        return new_flat[idx] if idx < len(new_flat) else h
    # Local remap function that closes over hex_to_slot/new_flat.
    def remap_value(val):
        if isinstance(val, str):
            return remap_hex(val)
        if isinstance(val, (list, tuple)):
            typ = type(val)
            return typ(remap_value(v) for v in val)
        return val
    # Shadow global helper with the closure version.
    slot_map = None  # kept for API compat; unused below
    def collect_widgets(w_list, out, seen):
        """Recurse into WidgetBox / nested containers so children get
        remapped too (SmartWidgetBox holds the icon widgets whose
        foreground otherwise never updates)."""
        for w in w_list:
            wid = id(w)
            if wid in seen:
                continue
            seen.add(wid)
            out.append(w)
            # WidgetBox exposes .widgets — its children may be shown
            # when the box is open. Recurse.
            for attr in ("widgets", "_widgets"):
                nested = getattr(w, attr, None)
                if isinstance(nested, (list, tuple)):
                    collect_widgets(nested, out, seen)

    for screen in qtile.screens:
        for bar_obj in (getattr(screen, "top", None), getattr(screen, "bottom", None),
                        getattr(screen, "left", None), getattr(screen, "right", None)):
            if bar_obj is None:
                continue
            top_widgets = getattr(bar_obj, "widgets", None) or []
            widgets = []
            collect_widgets(top_widgets, widgets, set())
            # bar background itself
            bg = getattr(bar_obj, "background", None)
            if bg:
                new_bg = remap_value(bg)
                if new_bg != bg:
                    try:
                        bar_obj.background = new_bg
                    except Exception:
                        pass
            for w in widgets:
                for attr in _PALETTE_ATTRS:
                    if not hasattr(w, attr):
                        continue
                    v = getattr(w, attr)
                    new_v = remap_value(v)
                    if new_v != v:
                        try:
                            setattr(w, attr, new_v)
                        except Exception:
                            pass
                # Decorations (RectDecoration etc)
                decs = getattr(w, "decorations", None) or []
                for d in decs:
                    for attr in _PALETTE_ATTRS:
                        if not hasattr(d, attr):
                            continue
                        v = getattr(d, attr)
                        new_v = remap_value(v)
                        if new_v != v:
                            try:
                                setattr(d, attr, new_v)
                            except Exception:
                                pass
                # force redraw
                try:
                    w.draw()
                except Exception:
                    pass
            try:
                bar_obj.draw()
            except Exception:
                pass
    # Window border colors — MonadTall/Max/etc. store border_focus /
    # border_normal captured from layout_theme at __init__. Walk every
    # group's layouts and remap.
    for g in qtile.groups:
        for lay in getattr(g, "layouts", []) or []:
            for attr in ("border_focus", "border_normal", "border_focus_stack",
                         "border_normal_stack", "active_bg", "active_fg",
                         "inactive_bg", "inactive_fg", "bg_color", "urgent_border"):
                if not hasattr(lay, attr):
                    continue
                v = getattr(lay, attr)
                new_v = remap_value(v)
                if new_v != v:
                    try:
                        setattr(lay, attr, new_v)
                    except Exception:
                        pass
            # trigger re-tile so borders repaint
            try:
                lay.group.layout_all()
            except Exception:
                pass
    # Also repaint focused window borders on every screen.
    for scr in qtile.screens:
        try:
            g = scr.group
            if g and hasattr(g, "layout_all"):
                g.layout_all()
        except Exception:
            pass

    # Update global so subsequent live-swaps have correct old_flat
    colors = new_palette_rows
    # Write marker so bash caller can detect success (qtile eval
    # can't return values from multi-statement code).
    try:
        with open(os.path.expanduser("~/.cache/qtile/.palette_live_ok"), "w") as f:
            f.write(str(int(time.time())))
    except Exception:
        pass
    return True

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


CHORD_CHIP_COLORS = {
    "Resize-Mode": colorsW[5],  # orange
    "Rofi-Mode": colorsW[6],  # blue
    "Media-Mode": colorsW[4],  # cyan
    "Scratch-Mode": colorsW[8],
    "Draw-Mode": colorsW[3],
    "Mouse-Mode": colorsW[7],
    "Lang-Switch": colorsW[1],
    "CheatSheet-Mode": colorsW[3],
    "WallpaperPicker": colorsW[3],
    "PASSTHROUGH": colorsW[8],
    "PASSTHROUGH-CONFIRM": colorsW[1],  # urgent/warm -- it is asking to quit
    # NOTE: Bluetooth popup will be used later
    # "Bluetooth-Mode": colorsW[4],
    # NOTE: Audio popup will be used later
    # "Audio-Mode": colorsW[4],
    # NOTE: Wifi popup will be used later
    # "Wifi-Mode": colorsW[4],
    # NOTE: updates popup  will be used later
    # "Updates-Mode": colorsW[4],
}

# ╔──────────────────────────────────────────╗
# │░▄█▄█▄░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█│
# │░░▀░▀░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀│
# ╚──────────────────────────────────────────╝


# ------------------------------------------------
# -2- passthrough
# -------------------------------------------------


def _enable_passthrough(qtile):
    global passthrough_active, _PASS_PREV_BAR_MODE, BAR_MODE
    if passthrough_active:
        # Re-grab after an Esc that was answered "no" — already in passthrough,
        # so don't re-save BAR_MODE (it is "bottom" now) or re-notify.
        return
    passthrough_active = True

    _PASS_PREV_BAR_MODE = BAR_MODE
    BAR_MODE = "bottom"
    try:
        apply_bar_mode()
    except Exception:
        pass

    qtile.spawn("notify-send 'PASSTHROUGH MODE'")


def _disable_passthrough(qtile):
    global passthrough_active, _PASS_PREV_BAR_MODE, BAR_MODE, _PASS_NEXT
    _PASS_NEXT = None
    _close_pass_confirm()
    if not passthrough_active:
        # "y" disables directly and then ungrabs, which fires leave_chord and
        # lands here a second time. Don't restore the bar or notify twice.
        return
    passthrough_active = False

    if _PASS_PREV_BAR_MODE is not None:
        BAR_MODE = _PASS_PREV_BAR_MODE
        _PASS_PREV_BAR_MODE = None
        try:
            apply_bar_mode()
        except Exception:
            pass

    qtile.spawn("notify-send 'NORMAL MODE'")


def _close_pass_confirm():
    global _PASS_CONFIRM_LAYOUT
    if _PASS_CONFIRM_LAYOUT:
        try:
            _PASS_CONFIRM_LAYOUT.hide()
        except Exception:
            pass
        _PASS_CONFIRM_LAYOUT = None


def _show_pass_confirm(qtile):
    global _PASS_CONFIRM_LAYOUT
    if _PASS_CONFIRM_LAYOUT:
        return
    from qtile_extras.popup import PopupRelativeLayout, PopupText
    from popups._wal_colors import fade_in_popup, load_colors

    # Read per open, like the cheatsheet/wallpaper popups, so a theme-apply while
    # qtile is running is picked up without a restart.
    c = load_colors()

    controls = [
        PopupText(
            text=(
                '<span size="large" weight="bold" foreground="{fg}">'
                "Exit passthrough mode?</span>".format(fg=c["fg"])
            ),
            markup=True,
            pos_x=0.0, pos_y=0.15, width=1.0, height=0.30,
            h_align="center", v_align="middle",
        ),
        PopupText(
            text='<b><span foreground="{0}">  Yes  (y)  </span></b>'.format(c["green"]),
            markup=True,
            pos_x=0.05, pos_y=0.55, width=0.42, height=0.30,
            h_align="center", v_align="middle",
            # can_focus defaults to "auto" -> True for anything with a Button1
            # callback, which flips the layout's keyboard_navigation on and makes
            # show() steal X focus + hijack key presses. That swallows the chord's
            # y/n/Escape. Clicks still work: button_press only reads mouse_callbacks.
            can_focus=False,
            mouse_callbacks={"Button1": lambda *_a, **_k: _passthrough_confirm_yes(qtile)},
        ),
        PopupText(
            text='<b><span foreground="{0}">  No  (n)  </span></b>'.format(c["red"]),
            markup=True,
            pos_x=0.53, pos_y=0.55, width=0.42, height=0.30,
            h_align="center", v_align="middle",
            can_focus=False,  # see the Yes control above
            mouse_callbacks={"Button1": lambda *_a, **_k: _passthrough_confirm_no(qtile)},
        ),
    ]
    _PASS_CONFIRM_LAYOUT = PopupRelativeLayout(
        qtile,
        width=360, height=140,
        background=c["bg"] + "F2",
        initial_focus=None,
        close_on_click=False,
        controls=controls,
    )
    _PASS_CONFIRM_LAYOUT.show(centered=True)
    fade_in_popup(_PASS_CONFIRM_LAYOUT, duration=0.16, steps=10)


def _passthrough_esc(qtile):
    """Esc inside PASSTHROUGH: raise the confirm popup and hand the keyboard to
    the confirm chord. qtile ungrabs on Escape no matter what, so the actual swap
    happens in cleanup_on_leave."""
    global _PASS_NEXT
    _show_pass_confirm(qtile)
    _PASS_NEXT = "CONFIRM"


def _pass_back_to_passthrough(qtile, ungrab):
    """Dismiss the popup and return to passthrough."""
    global _PASS_NEXT
    _close_pass_confirm()
    _PASS_NEXT = "PASS"
    if ungrab:
        qtile.ungrab_chord()


def _passthrough_confirm_yes(qtile):
    global _PASS_NEXT
    _close_pass_confirm()
    _PASS_NEXT = None
    _disable_passthrough(qtile)
    qtile.ungrab_chord()


def _passthrough_confirm_no(qtile):
    # "n" (and the popup's No button): qtile only auto-ungrabs for Escape, so
    # leaving the confirm chord is on us.
    _pass_back_to_passthrough(qtile, ungrab=True)


def _passthrough_confirm_esc(qtile):
    # Escape: qtile ungrabs the confirm chord itself right after this returns.
    _pass_back_to_passthrough(qtile, ungrab=False)


@lazy.function
def passthrough_on(qtile):
    _enable_passthrough(qtile)


@lazy.function
def passthrough_off(qtile):
    _disable_passthrough(qtile)


# ----------------------------------------------------------
# -1  Function for toggle to normaluserbar
# ---------------------------------------------------------


#
def apply_bar_mode():
    for s in qtile.screens:
        if BAR_MODE == "top":
            if s.bottom and s.bottom.is_show():
                s.bottom.show(False)
            if s.top and not s.top.is_show():
                s.top.show(True)
        else:
            if s.top and s.top.is_show():
                s.top.show(False)
            if s.bottom and not s.bottom.is_show():
                s.bottom.show(True)


@hook.subscribe.startup_complete
def apply_bar_on_startup():
    qtile.call_later(0.1, apply_bar_mode)


@hook.subscribe.startup
def apply_bar_on_reload_startup():
    # Fires on both initial start and after reload_config; ensures single-bar mode
    qtile.call_later(0.05, apply_bar_mode)


# ----------------------------------------------------------------
# Layout state persistence — qtile's built-in restart pickle keeps
# window→group mapping but resets layout ratios/sizes to defaults.
# Save MonadTall ratio + relative stack sizes per group before shutdown,
# restore after startup_complete so widths survive mod+shift+r.
# ----------------------------------------------------------------
import json as _json
_LAYOUT_STATE_FILE = os.path.expanduser("~/.cache/qtile/layout_state.json")


# NOTE: no shutdown hook — qtile tears down layouts BEFORE firing
# shutdown, so a save at that point would clobber the file with
# default ratios. Periodic 3s save + inline save in the mod+shift+r
# keybind cover both the resize and the restart paths.


# layout_change hook removed too — it fires during restart's teardown
# with default state and clobbers the saved good values.


def _save_layout_state():
    """Merge current layout state INTO existing file — never overwrite
    non-default entries with defaults. Prevents freshly-restarted qtile
    (empty rs, default ratio) from clobbering the saved good values
    before restore has a chance to run."""
    try:
        try:
            with open(_LAYOUT_STATE_FILE) as f:
                state = _json.load(f)
        except Exception:
            state = {}
        for g in qtile.groups:
            lay = g.layout
            new_entry = {"name": lay.name, "index": g.current_layout}
            if hasattr(lay, "ratio"):
                new_entry["ratio"] = lay.ratio
            if hasattr(lay, "relative_sizes"):
                new_entry["relative_sizes"] = list(lay.relative_sizes)
            old_entry = state.get(g.name, {})
            # Only overwrite each field when we have meaningful new data.
            # Default MonadTall: ratio=0.75, relative_sizes=[].
            merged = dict(old_entry)
            merged["name"] = new_entry["name"]
            merged["index"] = new_entry["index"]
            if "ratio" in new_entry:
                # Always take live ratio — MonadTall min_ratio=0.6 so any
                # user resize produces a non-default value; on cold start
                # this equals the config default which is also fine.
                merged["ratio"] = new_entry["ratio"]
            # Only overwrite relative_sizes when live value is non-empty.
            # Empty = layout was just re-instantiated and hasn't been
            # touched — keep the saved value from previous session.
            if new_entry.get("relative_sizes"):
                merged["relative_sizes"] = new_entry["relative_sizes"]
            state[g.name] = merged
        os.makedirs(os.path.dirname(_LAYOUT_STATE_FILE), exist_ok=True)
        with open(_LAYOUT_STATE_FILE, "w") as f:
            _json.dump(state, f)
    except Exception:
        pass


def _apply_layout_state():
    try:
        with open(_LAYOUT_STATE_FILE) as f:
            state = _json.load(f)
    except Exception:
        return
    for g in qtile.groups:
        entry = state.get(g.name)
        if not entry:
            continue
        try:
            if "index" in entry and 0 <= entry["index"] < len(g.layouts):
                if g.current_layout != entry["index"]:
                    g.current_layout = entry["index"]
            lay = g.layout
            if entry.get("name") != lay.name:
                continue
            if "ratio" in entry and hasattr(lay, "ratio"):
                if hasattr(lay, "set_ratio"):
                    try:
                        lay.set_ratio(float(entry["ratio"]))
                    except Exception:
                        lay.ratio = float(entry["ratio"])
                else:
                    lay.ratio = float(entry["ratio"])
            if "relative_sizes" in entry and hasattr(lay, "relative_sizes"):
                lay.relative_sizes = list(entry["relative_sizes"])
            g.layout_all()
        except Exception:
            continue


@hook.subscribe.startup_complete
def _attach_live_swap():
    # Expose apply_palette_live on the qtile object so
    # `qtile cmd-obj -f eval -a 'str(self.apply_palette_live())'`
    # from theme-apply can call it without config-module imports.
    try:
        qtile.apply_palette_live = apply_palette_live
    except Exception:
        pass
    # Same trick for the restart itself. theme-apply used to call qtile's
    # raw `restart`, which skips _smooth_restart entirely -- so changing
    # theme reloaded with the full window pile on show and no veil, even
    # though Super+Shift+R was covered.
    try:
        qtile.smooth_restart = lambda: _smooth_restart(qtile)
    except Exception:
        pass


@hook.subscribe.startup_complete
def _restore_layout_state():
    # Defer so all windows finish re-parenting to their groups before we
    # overwrite the freshly-instantiated layout's ratios.
    qtile.call_later(0.5, _apply_layout_state)
    qtile.call_later(1.5, _apply_layout_state)
    # Periodic save starts AFTER restore has run — otherwise the
    # freshly-instantiated layout's empty state overwrites the good file
    # before restore even reads it.
    def _periodic():
        _save_layout_state()
        _save_window_group_state()
        qtile.call_later(3, _periodic)
    qtile.call_later(5, _periodic)


# ----------------------------------------------------------------
# Window→group persistence — qtile's Match rules re-fire on restart
# and yank manually-moved windows back to their default group.
# Save {wid: group_name} + per-group focus order, restore after
# startup_complete, and skip Match reassignment for known wids.
# ----------------------------------------------------------------
_WINDOW_GROUP_FILE = os.path.expanduser("~/.cache/qtile/window_group_state.json")
_RESTORED_WIN_MAP = {}   # wid(str) -> group_name; consulted by client_new
_RESTORED_FOCUS = {}     # group_name -> [wid, ...] focus order
# wid(str) set that was minimized at save time. qtile's restart pickle does not
# carry minimized state, so a reload used to un-minimize everything -- most
# visibly the Mod+Shift+S summary, which client_managed then re-floated centre
# screen. Consulted by _float_and_center_sum and re-asserted by the restore pass.
_RESTORED_MINIMIZED = set()


def _save_window_group_state():
    try:
        wmap = {}
        focus = {}
        minimized = []
        for g in qtile.groups:
            order = []
            for w in g.windows:
                wid = str(w.wid)
                wmap[wid] = g.name
                order.append(wid)
                if getattr(w, "minimized", False):
                    minimized.append(wid)
            focus[g.name] = order
        os.makedirs(os.path.dirname(_WINDOW_GROUP_FILE), exist_ok=True)
        with open(_WINDOW_GROUP_FILE, "w") as f:
            _json.dump({"map": wmap, "focus": focus,
                        "minimized": minimized}, f)
    except Exception:
        pass


# ----------------------------------------------------------------
# Restart transition.
#
# Measured on this config in an isolated Xephyr sandbox: after execv,
# qtile's boot scan maps EVERY window from EVERY group at once and leaves
# them piled on top of each other for ~2.2s, then hides the foreign ones
# roughly 0.1s BEFORE the `startup` hook fires. So no config-level code
# is alive while the ugly frame is on screen -- masking it requires a
# process that outlives the execv. That is scripts/qtile-restart-veil.py.
#
# All visual work happens in the veil. qtile only snapshots the current
# window rects, launches the veil, waits for it to confirm it has
# painted, restarts, and signals "done" once the layout has settled.
# Nothing here moves window geometry, so there is no fighting with
# layout_all() and no way to strand a window off-grid.
#
# The veil is override-redirect with an empty input shape: it can never
# take focus, never grabs keyboard or pointer, and passes all input
# through. It also self-destructs after --max-seconds. This is
# deliberately unlike the earlier feh --fullscreen attempt, which behaved
# as an exclusive fullscreen app and had to be dismissed by hand.
# ----------------------------------------------------------------
_VEIL_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "scripts", "qtile-restart-veil.py")
# Failsafe only — the veil normally exits as soon as _veil_signal_done()
# fires. Measured restart on this config takes ~7s wall (dominated by
# config/widget load, not by the veil), so 8s was dangerously tight: if
# boot ran long the veil would vanish and expose the pile it exists to
# hide. The veil is click-through and self-destructs, so a generous
# ceiling costs nothing.
_VEIL_MAX_SECONDS = 20.0
# The veil reads the wallpaper + palette from ~/.cache/wal/colors.json
# itself, so it always matches the current theme with no plumbing here.
#
# Timings: the restore passes used to sit at 0.6s/1.6s and the veil lifted
# at 1.8s, which made every restart feel ~1s longer than it needed to.
# Pulled in after verifying in the sandbox that the restores still land.
# These are pure dead time at the END of the restart -- qtile is already
# up and the desktop is already correct, the veil is just still on screen.
# Every 0.1s here is 0.1s the user experiences as "slow". Halved after
# confirming in the sandbox that both restore passes still land before
# the veil lifts; pass 2 is the safety net, and it now runs at 0.34s
# rather than 0.70s.
_VEIL_SIGNAL_DELAY = 0.40       # after startup_complete, once restores settle
_RESTORE_PASS_1 = 0.14
_RESTORE_PASS_2 = 0.34


def _veil_paths():
    d = os.path.dirname(_WINDOW_GROUP_FILE)
    return (os.path.join(d, "veil_rects.json"),
            os.path.join(d, "veil_done"),
            os.path.join(d, "veil_ready"))


def _veil_stage_path():
    return os.path.join(os.path.dirname(_WINDOW_GROUP_FILE), "veil_stage")


def _veil_tips_path():
    return os.path.join(os.path.dirname(_WINDOW_GROUP_FILE), "veil_tips.json")


import random as _random  # noqa: E402  (kept next to its only use)


_VEIL_MOD_NAMES = {
    "mod4": "Super", "mod1": "Alt", "mod5": "AltGr",
    "shift": "Shift", "control": "Ctrl", "lock": "Caps",
}
# Keyed by the lowered keysym — see _veil_tips.
_VEIL_KEY_NAMES = {
    "return": "Enter", "space": "Space", "tab": "Tab", "escape": "Esc",
    "backspace": "Backspace", "print": "PrtSc", "period": ".", "comma": ",",
    "slash": "/", "backslash": "\\", "minus": "-", "equal": "=",
    "bracketleft": "[", "bracketright": "]", "semicolon": ";",
    "apostrophe": "'", "grave": "`",
}
# Bindings that are useless or actively confusing to advertise while the
# thing they act on is mid-restart.
_VEIL_TIP_SKIP = ("restart", "reload", "quit", "shutdown", "logout",
                  "exit qtile")


def _veil_message():
    """One line shown above the cards, different every reload.

    Deliberately built from facts about THIS session -- window and group
    counts, the live layout, the active theme, the real binding count --
    rather than from a canned list of encouraging sentences. Generic
    filler ("Getting things ready...") is precisely the thing that reads
    as machine-written, and it also tells the user nothing they cannot
    already see.
    """
    opts = []
    try:
        groups = [g for g in qtile.groups if g.windows]
        wins = sum(len(g.windows) for g in groups)
        if wins:
            opts.append("%d window%s open across %d group%s"
                        % (wins, "" if wins == 1 else "s",
                           len(groups), "" if len(groups) == 1 else "s"))
    except Exception:
        pass
    try:
        lay = qtile.current_group.layout.name
        opts.append("layout · %s" % lay)
    except Exception:
        pass
    try:
        mode = open(os.path.expanduser(
            "~/.cache/qtile/theme_mode")).read().strip()
        if mode:
            opts.append("theme · %s" % mode)
    except Exception:
        pass
    try:
        n = len([k for k in qtile.config.keys if getattr(k, "desc", "")])
        opts.append("%d keybindings loaded" % n)
    except Exception:
        pass
    try:
        with open("/proc/uptime") as f:
            up = float(f.read().split()[0])
        h, m = int(up // 3600), int((up % 3600) // 60)
        opts.append("uptime · %dh %02dm" % (h, m) if h else
                    "uptime · %dm" % m)
    except Exception:
        pass
    if not opts:
        return ""
    try:
        return _random.choice(opts)
    except Exception:
        return opts[0]


def _veil_tips(n=5):
    """Sample real bindings out of the running config.

    Deliberately read from qtile.config.keys rather than from a
    hand-written list: a hardcoded list silently goes stale the moment a
    binding changes, and showing the user a shortcut that no longer
    exists is worse than showing nothing.
    """
    out = []
    try:
        for k in qtile.config.keys:
            desc = (getattr(k, "desc", "") or "").strip()
            key = getattr(k, "key", "")
            if not desc or not isinstance(key, str) or not key:
                continue
            if any(s in desc.lower() for s in _VEIL_TIP_SKIP):
                continue
            # Descriptions here double as developer notes ("CopyQ
            # clipboard rofi picker (ctrl+j/k nav, thumbnails)"). The
            # parenthetical is detail nobody reads off a 2.6s hint.
            desc = desc.split("(")[0].strip(" -–—") or desc
            if len(desc) > 44:
                continue
            # The per-group bindings are ~18 near-identical entries
            # ("Switch to group 7", "Move focused window to group 4").
            # Left in, they swamp a random sample of five -- and they are
            # the one set of shortcuts the user certainly already knows.
            if key.isdigit():
                continue
            mods = [_VEIL_MOD_NAMES.get(m, m.title())
                    for m in (getattr(k, "modifiers", None) or [])]
            # Keysyms are not consistently cased in the config ("tab" and
            # "Tab" both appear), so match on the lowered name.
            label = _VEIL_KEY_NAMES.get(key.lower())
            if label is None:
                label = key.upper() if len(key) == 1 else key.title()
            out.append({"keys": " + ".join(mods + [label]), "desc": desc})
    except Exception:
        return []
    # Prefer the shortcuts worth advertising. A flat random sample kept
    # surfacing single-modifier basics the user already uses every day
    # ("Super + T  toggle floating"); the interesting ones are the deeper
    # chords and the function keys, which are exactly what gets forgotten.
    deep = [t for t in out if t["keys"].count("+") >= 2]
    shallow = [t for t in out if t["keys"].count("+") < 2]
    try:
        pick = _random.sample(deep, min(n - 1, len(deep)))
        rest = [t for t in shallow + deep if t not in pick]
        pick += _random.sample(rest, min(n - len(pick), len(rest)))
        _random.shuffle(pick)
        return pick
    except Exception:
        return out[:n]


def _veil_stage(frac, text):
    """Report real progress to the veil.

    The veil could fake a timed bar, but qtile actually knows where it is
    in the restart, so it reports genuine stages instead: a bar that
    stalls because the config is slow is useful information, a bar that
    animates regardless is a lie.
    """
    try:
        with open(_veil_stage_path(), "w") as f:
            f.write("%.3f\n%s" % (frac, text))
    except Exception:
        pass


def _veil_active():
    """True if a veil we launched is still up and has painted.

    Used so a caller that already raised the veil (theme-apply, via
    _veil_hold) does not get a second one stacked on top when the restart
    finally happens. Checks the process, not just the ready file: a stale
    ready file from a veil that died would otherwise suppress the real one
    and expose the window pile.
    """
    try:
        _rects, _done, ready_file = _veil_paths()
        if not os.path.exists(ready_file):
            return False
        out = subprocess.run(
            ["pgrep", "-f", os.path.basename(_VEIL_SCRIPT)],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1,
        )
        return bool(out.stdout.strip())
    except Exception:
        return False


def _veil_hold():
    """Paint the veil now and leave it up; the caller restarts later.

    Exists for theme-apply. It writes ~10 app palettes (kitty, alacritty,
    GTK, qt5ct/qt6ct, rofi, dunst, …) before it asks for a restart, which
    meant ~4s of fully visible desktop between picking a theme and the
    veil appearing -- the palette visibly swapping under you, then a pause,
    then a loading screen. Raising the veil first hides that entire window
    of work behind it, so the restart *feels* ~4s shorter without being
    one second faster.

    Idempotent: a second call while a veil is already up is a no-op.
    """
    if _veil_active():
        return True
    ok = _veil_launch()
    if ok:
        _veil_stage(0.05, "Applying theme")
        _dunst(True)
    return ok


def _veil_launch():
    """Start the veil. Returns True only if it was actually spawned."""
    if not os.path.exists(_VEIL_SCRIPT):
        return False
    rects_file, done_file, ready_file = _veil_paths()
    scr = qtile.current_screen
    rects = []
    for w in qtile.current_group.windows:
        try:
            if getattr(w, "minimized", False):
                continue
            cls = ""
            try:
                wc = w.get_wm_class() or []
                if wc:
                    cls = wc[-1] or wc[0] or ""
            except Exception:
                cls = ""
            entry = {"x": w.x, "y": w.y, "w": w.width, "h": w.height,
                     "wm_class": cls, "name": (w.name or "")[:40]}
            # Icon-theme lookup by wm_class misses plenty of apps
            # (qutebrowser fell back to a "Q" badge). _NET_WM_ICON is the
            # icon the app itself advertises, so it always matches, and
            # qtile already decodes it to premultiplied BGRA -- which is
            # byte-identical to cairo's ARGB32, so the veil can wrap it
            # with no conversion.
            try:
                icons = getattr(w, "icons", None) or {}
                best, best_px = None, -1
                for dim, arr in icons.items():
                    iw, _, ih = dim.partition("x")
                    iw, ih = int(iw), int(ih)
                    if iw != ih or iw > 128:
                        continue
                    if iw * ih > best_px:
                        best, best_px = (iw, ih, arr), iw * ih
                if best:
                    iw, ih, arr = best
                    raw = os.path.join(os.path.dirname(rects_file),
                                       "veil_icon_%d.raw" % len(rects))
                    with open(raw, "wb") as f:
                        f.write(bytes(arr))
                    entry["icon_raw"] = raw
                    entry["icon_w"] = iw
                    entry["icon_h"] = ih
            except Exception:
                pass
            rects.append(entry)
        except Exception:
            continue
    os.makedirs(os.path.dirname(rects_file), exist_ok=True)
    with open(rects_file, "w") as f:
        _json.dump(rects, f)
    for stale in (done_file, ready_file):
        try:
            os.remove(stale)
        except OSError:
            pass
    tips_file = _veil_tips_path()
    try:
        with open(tips_file, "w") as f:
            _json.dump(_veil_tips(), f)
    except Exception:
        tips_file = ""

    _veil_stage(0.14, "Preparing")
    subprocess.Popen(
        [sys.executable, _VEIL_SCRIPT,
         "--x", str(scr.x), "--y", str(scr.y),
         "--width", str(scr.width), "--height", str(scr.height),
         "--rects-file", rects_file,
         "--tips-file", tips_file,
         "--message", _veil_message(),
         "--stage-file", _veil_stage_path(),
         "--group", str(getattr(qtile.current_group, "name", "")),
         "--done-file", done_file,
         "--ready-file", ready_file,
         "--max-seconds", str(_VEIL_MAX_SECONDS)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,          # must survive the execv
    )
    return True


def _dunst(paused):
    """Notifications are their own override-redirect windows and sit above
    the veil, so anything that fires mid-restart (including qtile's own
    "Reloaded" toast, now removed) lands on top of the transition."""
    try:
        subprocess.Popen(["dunstctl", "set-paused", "true" if paused else "false"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def _modifiers_held():
    """True while Shift/Ctrl/Alt/Super are physically down.

    This matters a lot: the KeyboardLayout widget runs
    `xmodmap ~/.Xmodmap` synchronously at startup (libqtile
    widget/keyboardlayout.py), and ~/.Xmodmap does `clear mod1` /
    `add mod1`. xmodmap refuses to rewrite the modifier map while any
    modifier key is held and retries at 2s, 4s, 8s, 16s, 32s -- blocking
    qtile's whole startup. Since the restart keybind is Super+Shift+R,
    Super is *always* still down at that moment, which is what made
    restarts take ~12s. Waiting for release first avoids it entirely.

    Checked via QueryKeymap (the real physical key bitmap), NOT the
    pointer's modifier mask: xmodmap inspects pressed *keys*, and the two
    disagree -- an early version of this used the pointer mask, reported
    "nothing held", and the 2/4/8/16/32s stall happened anyway. Waiting
    for the keyboard to be completely idle is stricter than necessary but
    is exactly what clears xmodmap's check, and after releasing
    Super+Shift+R that takes ~200ms.

    Only genuine modifier keycodes count. An earlier version treated any
    pressed key as "held", so merely typing would have delayed a restart
    (and a single stuck key wasted the whole wait budget).
    """
    try:
        core = qtile.core.conn.conn.core
        mods = core.GetModifierMapping().reply()
        mod_codes = {kc for kc in mods.keycodes if kc}
        if not mod_codes:
            return False
        keymap = core.QueryKeymap().reply().keys
        for kc in mod_codes:
            if keymap[kc >> 3] & (1 << (kc & 7)):
                return True
        return False
    except Exception:
        return False


@hook.subscribe.startup
def _veil_stage_config_loaded():
    # Fires once the config has been imported and screens/bars are built —
    # the single longest part of a restart on this config.
    if os.path.exists(_veil_stage_path()):
        _veil_stage(0.62, "Configuration loaded")


def _reapply_xmodmap_when_idle(tries=40):
    """Re-run ~/.Xmodmap once the keyboard is actually idle.

    The startup call is fire-and-forget now, so it can lose the race
    against a held Super. This retries cheaply (250ms apart, ~10s total)
    and applies it the moment no key is down, keeping Caps->Alt reliable
    without ever blocking qtile.
    """
    try:
        if not os.path.isfile(os.path.expanduser("~/.Xmodmap")):
            return
        if _modifiers_held() and tries > 0:
            qtile.call_later(0.25, _reapply_xmodmap_when_idle, tries - 1)
            return
        subprocess.Popen(
            ["sh", "-c", "xmodmap $HOME/.Xmodmap"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def _veil_signal_done():
    """Tell the veil the desktop is ready; it fades out and exits. If this
    never runs, the veil's own watchdog kills it anyway."""
    try:
        _rects, done_file, _ready = _veil_paths()
        open(done_file, "w").close()
    except Exception:
        pass
    _veil_stage(1.0, "Ready")
    qtile.call_later(0.1, _reapply_xmodmap_when_idle)
    # The veil unpauses dunst itself when its window actually goes away
    # (see the `finally` in qtile-restart-veil.py) -- that is the only
    # place that knows the real moment, and dunst dumps its entire queued
    # backlog the instant it unpauses. This is a backstop for the case
    # where the veil died without running its exit path; it is idempotent,
    # so both firing is harmless. Kept well clear of the fade-out.
    qtile.call_later(1.5, lambda: _dunst(False))


def _smooth_restart(qtile):
    _veil_stage(0.08, "Saving session")
    try:
        # Reuse a veil that theme-apply already raised via _veil_hold();
        # only spawn one if nothing is up. Spawning unconditionally would
        # put a second veil over the first and restart the fade-in.
        if _veil_active() or _veil_launch():
            # Save state AFTER spawning the veil, not before. qtile then
            # blocks on the veil reporting it has painted, and the veil
            # needs ~0.4s just to start python and import GTK -- measured.
            # Doing the saves first meant that 0.4s was spent idling; doing
            # them here overlaps them with the veil's boot. Both still
            # complete strictly before qtile.restart() below.
            _save_layout_state()
            _save_window_group_state()
            _dunst(True)
            # Wait for the veil to report it has actually painted before
            # replacing the process image. A fixed delay is not enough:
            # python+GTK startup is slower than any sane fixed wait, and
            # restarting early lets the pile flash through underneath.
            _rects, _done, ready_file = _veil_paths()
            # 1.0s ceiling. This wait used to be load-bearing (it kept
            # xmodmap from stalling startup for tens of seconds), but that
            # is now fixed at the source by making the xmodmap call
            # non-blocking, so this is only belt-and-braces. A stuck key
            # should not cost a full 3s of dead time on every restart.
            budget = [40]

            def _wait():
                budget[0] -= 1
                if budget[0] <= 0:
                    _veil_stage(0.22, "Restarting window manager")
                    qtile.restart()
                    return
                # Both conditions: the veil must be painted (so the pile
                # never shows) and the modifiers must be up (so xmodmap
                # does not stall the next startup for tens of seconds).
                if os.path.exists(ready_file) and not _modifiers_held():
                    _veil_stage(0.22, "Restarting window manager")
                    qtile.restart()
                else:
                    qtile.call_later(0.025, _wait)

            qtile.call_later(0.025, _wait)
            return
    except Exception:
        pass
    # Fallthrough: the veil never launched, so nothing has been saved yet.
    _save_layout_state()
    _save_window_group_state()
    qtile.restart()          # kill-switch: plain, known-good restart


def _load_window_group_state():
    global _RESTORED_WIN_MAP, _RESTORED_FOCUS
    try:
        with open(_WINDOW_GROUP_FILE) as f:
            data = _json.load(f)
        _RESTORED_WIN_MAP = dict(data.get("map", {}))
        _RESTORED_FOCUS = dict(data.get("focus", {}))
    except Exception:
        _RESTORED_WIN_MAP = {}
        _RESTORED_FOCUS = {}


def _load_minimized_state():
    """Read just the minimized wids, at config-import time.

    Deliberately separate from _load_window_group_state, which only runs on
    startup_complete: the boot scan fires client_managed for every adopted
    window BEFORE that, and _float_and_center_sum needs this set already
    populated or the summary window floats open for a moment first.
    """
    global _RESTORED_MINIMIZED
    try:
        with open(_WINDOW_GROUP_FILE) as f:
            _RESTORED_MINIMIZED = set(_json.load(f).get("minimized", []))
    except Exception:
        _RESTORED_MINIMIZED = set()


_load_minimized_state()


def _restore_window_group_state():
    """Move already-adopted windows to their saved groups + restore
    per-group focus order. Runs after startup_complete so all windows
    have been re-adopted by qtile."""
    try:
        for wid_str, gname in list(_RESTORED_WIN_MAP.items()):
            try:
                wid = int(wid_str)
            except Exception:
                continue
            win = qtile.windows_map.get(wid)
            if not win:
                continue
            if getattr(win, "group", None) and win.group.name == gname:
                continue
            try:
                win.togroup(gname)
            except Exception:
                pass
        for gname, order in _RESTORED_FOCUS.items():
            g = qtile.groups_map.get(gname)
            if not g:
                continue
            for wid_str in order:
                try:
                    wid = int(wid_str)
                except Exception:
                    continue
                win = qtile.windows_map.get(wid)
                if win and getattr(win, "group", None) and win.group.name == gname:
                    try:
                        g.focus(win, warp=False)
                    except Exception:
                        pass
        # Last, after togroup() and focus() have both had their way with these
        # windows -- either can leave a window mapped again.
        for wid_str in list(_RESTORED_MINIMIZED):
            try:
                win = qtile.windows_map.get(int(wid_str))
            except Exception:
                continue
            if win is not None and not getattr(win, "minimized", False):
                try:
                    win.minimized = True
                except Exception:
                    pass
    except Exception:
        pass


@hook.subscribe.startup_complete
def _init_window_group_state():
    _veil_stage(0.80, "Restoring windows")
    _load_window_group_state()
    qtile.call_later(_RESTORE_PASS_1, _restore_window_group_state)
    qtile.call_later(_RESTORE_PASS_2, _restore_window_group_state)
    qtile.call_later(_VEIL_SIGNAL_DELAY, _veil_signal_done)


@hook.subscribe.client_new
def _override_match_from_saved(client):
    # Runs before Match assignment completes; schedule after so we win.
    try:
        wid_str = str(client.wid)
    except Exception:
        return
    gname = _RESTORED_WIN_MAP.get(wid_str)
    if not gname:
        return
    def _move():
        try:
            win = qtile.windows_map.get(client.wid)
            if win and (not getattr(win, "group", None) or win.group.name != gname):
                win.togroup(gname)
        except Exception:
            pass
    qtile.call_later(0.05, _move)


@hook.subscribe.client_managed
def _track_window_group(client):
    try:
        if getattr(client, "group", None):
            _RESTORED_WIN_MAP[str(client.wid)] = client.group.name
    except Exception:
        pass


@hook.subscribe.client_managed
def _float_and_center_sum(client):
    """TODOS summary (Mod+Shift+S) opens floating and centered.

    The float_rules Match handles the floating part on its own, but qtile only
    auto-centers a float whose first-map position is off-screen (see the
    no_reposition_rules note on floating_layout) -- alacritty maps on-screen, so
    the centering has to be explicit.

    Done synchronously, NOT via call_later: manage() fires client_new (before the
    window has a group), then group.add() applies the float rules and places the
    window, then fires client_managed. So by the time we get here `floating` and
    `group.screen` are both set -- everything center() needs. Deferring even 50ms
    past this point just let the window paint once at alacritty's own size before
    snapping to 55%x65%, which is the jump that looked like a glitch.
    """
    if not is_sum_window(client):
        return

    # Re-adopted across a reload while minimized: leave it minimized. Without
    # this the window is floated centre screen here and only re-hidden by the
    # restore pass ~0.14s later, which reads as a flash. float_center_sum()
    # un-minimizes as part of _enablefloating(), so it cannot run first.
    if str(client.wid) in _RESTORED_MINIMIZED:
        try:
            client.minimized = True
        except Exception:
            pass
        return

    float_center_sum(client)


@hook.subscribe.client_killed
def _drop_window_group(client):
    try:
        _RESTORED_WIN_MAP.pop(str(client.wid), None)
        # X reuses wids, so a stale entry here would minimize an unrelated
        # window that happens to inherit the number.
        _RESTORED_MINIMIZED.discard(str(client.wid))
    except Exception:
        pass


# qdrop (scripts/qdrop.py) following the currently active group: tried
# two qtile-side approaches, both reverted.
#   1. Re-togroup() on every `setgroup` hook fire: togroup() unconditionally
#      calls the window's own hide() (a real X11 unmap) and re-runs the
#      floating layout's placement pass (incl. a mouse warp), which
#      desyncs GTK's own mapped-state bookkeeping from reality and left
#      the window stuck unmapped.
#   2. client.static(): detaches the window from the group system
#      entirely (screen-bound, like a dock/panel) so it's always visible
#      regardless of active group -- but qtile never routes keyboard
#      focus to a Static window, which broke qdrop's search/delete/
#      ctrl+a shortcuts.
# Fix now lives in qdrop.py itself instead: it asks qtile (via the
# command socket) which group it's really on right before showing, and
# if it differs from the current one, does its own hide()+togroup()+
# full remap dance (see show_animated()) rather than qtile silently
# doing it from underneath.


@hook.subscribe.screens_reconfigured
def apply_bar_on_reconfigure():
    apply_bar_mode()


# ----------------------------------------------------------------
# Bar tooltips — hover any widget for a hint. Dynamically injects
# TooltipMixin into each widget instance's class.
# ----------------------------------------------------------------

TOOLTIP_BY_NAME = {
    "chord_chip": "Current mode",
    "chord_chip_nu": "Current mode",
    "main_icon_chip": "Arch menu · L-click → terminal · R-click → launcher",
    "main_icon_chip_nu": "Arch menu · L-click → launcher · R-click → terminal",
    "screenshot_chip_nu": "Screenshot area → clipboard",
    "tooltip_widgetbox": "Tips (💡) · click → toggle onboarding",
    "system_widgetbox": "CPU + Memory",
    "2nd_system_widgetbox": "Updates · Disk · Volume",
    "wallpaper_toggle": "Wallpaper picker",
    "systray_widgetbox": "System tray",
    "w_cpu": "CPU load · click → mission-center",
    "w_mem": "RAM used · click → btop",
    "w_disk": "Disk free (/ + /home) · click → notify",
    "w_volume": "Volume · scroll to change",
    "w_battery": "Battery · click → status",
    "w_lang": "Keyboard layout",
    "w_clock": "Next prayer",
    "w_mpris": "L: play/pause · M: album art · R: prev · scroll: next/prev",
    "w_nightlight": "Nightlight · L: on · R: off",
}

TOOLTIP_BY_CLASS = {
    "GroupBox": "Workspaces · click to switch",
    "TaskList": "Open windows",
    "Clock": "Date & time · click → popup",
    "Spacer": None,
    "TextBox": None,
    "Chord": "Current mode",
    "Systray": "System tray",
    "CheckUpdates": "Pending updates",
    "CurrentLayout": "Layout · R-click to cycle",
    "LaunchBar": "Quick launch: Brave · Qute · Kitty · Files · VSCode",
}


_TOOLTIP_WIDGETS = []


def _kill_all_tooltips(except_w=None):
    for w in list(_TOOLTIP_WIDGETS):
        if w is except_w:
            continue
        try:
            if getattr(w, "_tooltip_timer", None):
                w._tooltip_timer.cancel()
                w._tooltip_timer = None
            if getattr(w, "_tooltip", None) is not None:
                w._tooltip.hide()
                w._tooltip.kill()
                w._tooltip = None
        except Exception:
            pass


def _install_tooltip(widget_, text):
    if not text:
        return
    cls = widget_.__class__
    if not issubclass(cls, TooltipMixin):
        new_cls = type(cls.__name__ + "WithTooltip", (cls, TooltipMixin), {})
        try:
            widget_.__class__ = new_cls
        except TypeError:
            return
        TooltipMixin.__init__(widget_)
        try:
            widget_.add_defaults(TooltipMixin.defaults)
        except Exception:
            pass
    # kill any stale popup from previous install/reload
    try:
        if getattr(widget_, "_tooltip", None) is not None:
            widget_._tooltip.hide()
            widget_._tooltip.kill()
            widget_._tooltip = None
        if getattr(widget_, "_tooltip_timer", None):
            widget_._tooltip_timer.cancel()
            widget_._tooltip_timer = None
    except Exception:
        pass
    if widget_ not in _TOOLTIP_WIDGETS:
        _TOOLTIP_WIDGETS.append(widget_)
    widget_.tooltip_text = text
    widget_.tooltip_delay = 0.35
    widget_.tooltip_background = "#11131a"
    widget_.tooltip_color = "#e6e8ef"
    widget_.tooltip_font = "Ubuntu"
    widget_.tooltip_fontsize = 11
    widget_.tooltip_padding = [4, 10]

    # Patch _show_tooltip: upstream sets `self._tooltip.text = ...`, but
    # Popup has no `text` setter — attr is orphaned and layout stays empty
    # (width=0). Also set `layout.text` so text actually renders.
    _orig_show = widget_._show_tooltip

    def _fixed_show(x, y, _w=widget_, _orig=_orig_show):
        _orig(x, y)
        try:
            if _w._tooltip is None or not _w.tooltip_text.strip():
                if _w._tooltip is not None:
                    _w._tooltip.hide()
                    _w._tooltip.kill()
                    _w._tooltip = None
                return
            tt = _w._tooltip
            tt.layout.text = _w.tooltip_text
            tt.width = tt.layout.width + 2 * tt.horizontal_padding
            tt.height = tt.layout.height + 2 * tt.vertical_padding
            # clamp x within screen and add small vertical margin below bar
            screen = _w.bar.screen
            margin = 6
            tt.x = max(4, min(tt.x, screen.width - tt.width - 4))
            if screen.top == _w.bar:
                tt.y = _w.bar.height + margin
            elif screen.bottom == _w.bar:
                tt.y = screen.height - _w.bar.height - tt.height - margin
            # start invisible for fade-in
            try:
                tt.win.opacity = 0.0
            except Exception:
                pass
            tt.place()
            tt.clear()
            tt.draw_text()
            tt.draw()
            # fade in over ~140ms
            steps = 7
            for i in range(1, steps + 1):
                op = i / steps

                def _step(o=op, _tt=tt):
                    try:
                        if _tt.win:
                            _tt.win.opacity = o
                    except Exception:
                        pass

                qtile.call_later(0.02 * i, _step)
        except Exception:
            pass

    widget_._show_tooltip = _fixed_show

    def _safe_stop(x, y, _w=widget_):
        try:
            if _w._tooltip_timer and not _w._tooltip:
                _w._tooltip_timer.cancel()
                _w._tooltip_timer = None
                return
            if _w._tooltip is not None:
                _w._tooltip.hide()
                _w._tooltip.kill()
            _w._tooltip = None
            _w._tooltip_timer = None
        except Exception:
            pass

    def _wrapped_enter(x, y, _w=widget_):
        _kill_all_tooltips(except_w=_w)
        _w._start_tooltip(x, y)

    widget_.mouse_enter = _wrapped_enter
    widget_.mouse_leave = _safe_stop


def install_bar_tooltips():
    from libqtile.log_utils import logger

    _kill_all_tooltips()
    _TOOLTIP_WIDGETS.clear()
    # kill orphan internal windows (leftover tooltip popups from
    # previous config reloads). exclude bar windows + big internals.
    try:
        bar_wids = set()
        for screen in qtile.screens:
            for pos in ("top", "bottom", "left", "right"):
                b = getattr(screen, pos, None)
                if b and getattr(b, "window", None):
                    try:
                        bar_wids.add(b.window.wid)
                    except Exception:
                        pass
        for wid, w in list(qtile.windows_map.items()):
            try:
                if type(w).__name__ != "Internal":
                    continue
                if wid in bar_wids:
                    continue
                ww = getattr(w, "width", 0)
                hh = getattr(w, "height", 0)
                if ww <= 500 and hh <= 100:
                    w.kill()
            except Exception:
                pass
    except Exception:
        pass
    seen = set()
    installed = 0
    total = 0
    for screen in qtile.screens:
        for pos in ("top", "bottom", "left", "right"):
            b = getattr(screen, pos, None)
            if not b:
                continue
            for w in b.widgets:
                if id(w) in seen:
                    continue
                seen.add(id(w))
                total += 1
                text = TOOLTIP_BY_NAME.get(getattr(w, "name", ""), None)
                if text is None:
                    text = TOOLTIP_BY_CLASS.get(w.__class__.__name__)
                if text:
                    try:
                        _install_tooltip(w, text)
                        installed += 1
                        if getattr(w, "name", "") == "w_mpris":
                            _make_tooltip_dynamic(w, _player_title_text, "No player")
                        if getattr(w, "name", "") == "w_clock":
                            _make_tooltip_dynamic(w, _prayer_text, "No prayer data")
                        if getattr(w, "name", "") == "w_cpu":
                            _make_tooltip_dynamic(w, _cpu_top_text)
                        if getattr(w, "name", "") == "w_mem":
                            _make_tooltip_dynamic(w, _mem_top_text)
                        if getattr(w, "name", "") == "w_disk":
                            _make_tooltip_dynamic(w, _disk_parts_text)
                        if getattr(w, "name", "") == "w_battery":
                            _make_tooltip_dynamic(w, _battery_detail_text)
                    except Exception as e:
                        logger.warning(
                            f"tooltip install failed for {w.__class__.__name__}: {e}"
                        )
    logger.warning(f"[tooltips] installed={installed} total={total}")


def _wrap_mpris_hover(widget_):
    _prev_enter = getattr(widget_, "mouse_enter", None)
    _prev_leave = getattr(widget_, "mouse_leave", None)

    def _enter(x, y, _p=_prev_enter):
        _mpris_apply_templates(True)
        if _p:
            try:
                _p(x, y)
            except Exception:
                pass

    def _leave(x, y, _p=_prev_leave):
        _mpris_apply_templates(False)
        if _p:
            try:
                _p(x, y)
            except Exception:
                pass

    widget_.mouse_enter = _enter
    widget_.mouse_leave = _leave


def _make_tooltip_dynamic(widget_, text_func, fallback=""):
    _orig_enter = widget_.mouse_enter

    def _dyn_enter(x, y, _w=widget_, _fn=text_func, _fb=fallback, _orig=_orig_enter):
        try:
            t = (_fn() or "").strip() or _fb
            _w.tooltip_text = t
        except Exception:
            pass
        _orig(x, y)

    widget_.mouse_enter = _dyn_enter


@hook.subscribe.startup_complete
def _bar_tooltips_on_start_complete():
    qtile.call_later(0.3, install_bar_tooltips)


@hook.subscribe.startup
def _bar_tooltips_on_reload():
    # startup fires on reload_config too; startup_complete does not.
    qtile.call_later(2.0, install_bar_tooltips)


#
#
@lazy.function
def toggle_top_bottom_exclusive(qtile):
    global BAR_MODE

    screen = qtile.current_screen
    top = screen.top
    bottom = screen.bottom

    if not top or not bottom:
        return

    if BAR_MODE == "top":
        BAR_MODE = "bottom"
    else:
        BAR_MODE = "top"

    apply_bar_mode()


# ------------------------------------------------------------
# 0-  Function for the autostart.sh script  (runs on startup)
# -----------------------------------------------------------


@hook.subscribe.startup_once
def start_once():
    home = os.path.expanduser("~")
    # Popen fire-and-forget: subprocess.call blocks main loop until autostart.sh returns.
    subprocess.Popen(
        [home + "/.config/qtile/autostart.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


# -------------------------------------------------
# 1- Function for Not En Layout
# -------------------------------------------------


def show_layout_warning(qtile, layout):
    layout_name = layout.upper()

    qtile.spawn(
        "notify-send "
        f"-r {NON_EN_NOTIFY_ID} "
        "-u critical "
        "-t 0 "
        '"Non-English Layout Active" '
        f'"Current layout: {layout_name}\n'
        "Many shortcuts may not work.\n"
        'Switch to EN (US) to use all shortcuts."'
    )


def hide_layout_warning(qtile):
    qtile.spawn(f'notify-send -r {NON_EN_NOTIFY_ID} -t 1 "" ""')


# ---------------------------------------------------
# 2- Function for Going to the same group and notify
# ---------------------------------------------------


@lazy.function
def go_to_group_or_notify(qtile, group_name):
    current = qtile.current_group.name

    if current == group_name:
        qtile.spawn(
            f'notify-send -u normal -t 5000  "Qtile" "You are already in workspace {group_name}"'
        )
    else:
        qtile.groups_map[group_name].toscreen()


# ---------------------------------------------------
# 3- Function for tooltip_widgetbox
# ---------------------------------------------------


def toggle_onboarding(qtile):
    w = qtile.widgets_map.get("tooltip_widgetbox")
    if not w:
        return

    if w.box_is_open:
        qtile.spawn("eww close onboarding-welcome")
        w.toggle()
    else:
        qtile.spawn("eww open onboarding-welcome")
        w.toggle()


# ----------------------------------------------
# 4- Function for setting icon temporarily  "󰕰"
# ---------------------------------------------


def set_icon_temporarily(qtile, icon, cmd):
    w = qtile.widgets_map.get("main_icon_chip")
    if not w:
        return

    # update icon immediately
    w.update(icon)

    # spawn app
    qtile.spawn(cmd)

    # qtile.call_later avoids spawning a thread per keypress.
    qtile.call_later(0.3, lambda: w.update(ARCH_ICON_MAIN))


def open_terminal(qtile):
    set_icon_temporarily(qtile, "󰞷", myTerm)


def open_launcher(qtile):
    set_icon_temporarily(
        qtile,
        "󰍉",
        "rofi -show drun -show-icons",
    )


# ╔────────────────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▄█░█▀█░█▀▄░█▀▀░█▀▀░░░█▀▀░█░█░█▀█░█▀▀░▀█▀░▀█▀░█▀█░█▀█░█▀▀│
# │░▄█▄█▄░█░█░█░█░█░█░█▀▀░▀▀█░░░█▀▀░█░█░█░█░█░░░░█░░░█░░█░█░█░█░▀▀█│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀░░▀▀▀░▀▀▀░░░▀░░░▀▀▀░▀░▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀░▀░▀▀▀│
# ╚────────────────────────────────────────────────────────────────╝


# -----------------------------------------------
# 5- Function to remember which mode we are in
# ----------------------------------------------


@hook.subscribe.enter_chord
def remember_chord(chord_name):
    global ACTIVE_CHORD
    ACTIVE_CHORD = chord_name


# --------------------------------------------------------------
# 6- Function to auto launch warpd when "Mouse-Mode" is active
# --------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_warpd(chord_name):
    if chord_name == "Mouse-Mode":
        qtile.spawn("warpd --normal")


# ---------------------------------------------------------------------------------------
# 7- Function to lanuch gromit-mpx when "Draw-Mode" if not lunched and then activate it
# ---------------------------------------------------------------------------------------


def ensure_gromit_and_toggle(qtile):
    # Shell handles pgrep + branching. Async fork via qtile.spawn — main loop never blocks.
    qtile.spawn(
        "sh -c '"
        "if pgrep -x gromit-mpx >/dev/null; then "
        "gromit-mpx -t; "
        "else "
        "notify-send -u normal -t 4000 \"Gromit MPX\" "
        "\"Gromit was not running — starting it now…\"; "
        "gromit-mpx & sleep 0.3; gromit-mpx -t; "
        "fi'"
    )


@hook.subscribe.enter_chord
def auto_enable_draw(chord_name):
    if chord_name == "Draw-Mode":
        ensure_gromit_and_toggle(qtile)


# --------------------------------------------------------------------------------------------------------
# 8- Function to auto lanuch the CheatSheet when it's mode activated, Function to exit the CheatSheet mode
# --------------------------------------------------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_cheatsheet(chord_name):
    if chord_name == "CheatSheet-Mode":
        show_qtile_cheatsheet(qtile)


def exit_cheatsheet_mode(qtile):
    close_qtile_cheatsheet()
    close_vim_cheatsheet()
    close_fish_kitty_cheatsheet()
    qtile.ungrab_chord()


# -----------------------------------------------------------------------------------------------------
# 9- Function to auto lanuch the WallpaperPicker when it's mode activated , Function to close wallpaper
# -----------------------------------------------------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_wallpaper_picker(chord_name):
    if chord_name == "WallpaperPicker":
        show_wallpaper_picker(qtile)
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and not w.box_is_open:
            w.toggle()


def close_wallpaper_mode(qtile):
    close_wallpaper_picker()
    qtile.ungrab_chord()

    w = qtile.widgets_map.get("wallpaper_toggle")
    if w and w.box_is_open:
        w.toggle()


def toggle_wallpaper_picker(qtile):
    # The chip's icon (✖/) already tracks open/close state via the
    # enter_chord/leave_chord hooks below -- but the click handler itself
    # used to ignore that state and always re-fire the "open" keypress
    # sequence, so clicking while already open didn't close it.
    w = qtile.widgets_map.get("wallpaper_toggle")
    if w and w.box_is_open:
        close_wallpaper_mode(qtile)
    else:
        SmartWidgetBox.close_all()
        qtile.simulate_keypress([mod], "p")
        qtile.simulate_keypress([], "b")


# ----------------------------------------------------------------
# 10- Function to cleanup and close all apps of the modes  on leave
# ----------------------------------------------------------------


@hook.subscribe.leave_chord
def cleanup_on_leave():
    global ACTIVE_CHORD, _PASS_NEXT

    if ACTIVE_CHORD == "Draw-Mode":
        qtile.spawn("gromit-mpx -v")

    elif ACTIVE_CHORD == "CheatSheet-Mode":
        close_qtile_cheatsheet()
        close_vim_cheatsheet()
        close_fish_kitty_cheatsheet()

    elif ACTIVE_CHORD == "WallpaperPicker":
        close_wallpaper_picker()
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and w.box_is_open:
            w.toggle()

    elif ACTIVE_CHORD in ("PASSTHROUGH", "PASSTHROUGH-CONFIRM"):
        # Deferred because ungrab_chord() still calls ungrab_keys() and pops the
        # chord stack after this hook returns -- grabbing inline gets wiped.
        nxt, _PASS_NEXT = _PASS_NEXT, None
        if nxt == "CONFIRM" and PASSTHROUGH_CONFIRM_CHORD is not None:
            qtile.call_later(0.01, lambda: qtile.grab_chord(PASSTHROUGH_CONFIRM_CHORD))
        elif nxt == "PASS" and PASSTHROUGH_CHORD is not None:
            qtile.call_later(0.01, lambda: qtile.grab_chord(PASSTHROUGH_CHORD))
        else:
            _disable_passthrough(qtile)

    # NOTE: Bluetooth popup will be used later
    # elif ACTIVE_CHORD == "Bluetooth-Mode":
    #     close_bluetooth_popup(qtile)

    # NOTE : Audio popup will be used later
    # elif ACTIVE_CHORD == "Audio-Mode":
    #     close_audio_popup(qtile)

    # NOTE : Wifi popup will be used later
    # elif ACTIVE_CHORD == "Wifi-Mode":
    #     close_wifi_popup(qtile)

    # NOTE : updates popup  will be used later
    # elif ACTIVE_CHORD == "Updates-Mode":
    #     close_updates_popup(qtile)

    ACTIVE_CHORD = None


# -------------------------------------------------------------------------------
# 11- Function to group keys while we are inside the modes with (1,2,3....9)
# -------------------------------------------------------------------------------


def group_keys():
    return [
        Key(
            [],
            str(i),
            go_to_group_or_notify(str(i)),
            desc=f"Switch to group {i}",
        )
        for i in range(1, 10)
    ]


# ---------------------------------------------------
# 12- function to change the color of the chord chip
# --------------------------------------------------


@hook.subscribe.enter_chord
def chord_chip_enter(chord_name):
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            # deco.colour = CHORD_CHIP_COLORS.get(chord_name, colorsW[2])
            setattr(deco, "colour", CHORD_CHIP_COLORS.get(chord_name, colorsW[2]))

    if w.bar:
        w.bar.draw()


@hook.subscribe.leave_chord
def chord_chip_leave():
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            # deco.colour = colorsW[2]  # default chip color
            setattr(deco, "colour", colorsW[2])

    w.bar.draw()


# ----------------------------------------------------------------
# 12.5- On chord enter: close any open SmartWidgetBox and remember
#       which ones were open. On chord leave: reopen exactly those.
# ----------------------------------------------------------------

_SAVED_WIDGETBOX_NAMES = []


def _all_smart_widgetboxes():
    seen = set()
    for screen in qtile.screens:
        for pos in ("top", "bottom", "left", "right"):
            b = getattr(screen, pos, None)
            if not b:
                continue
            for w in b.widgets:
                if w.__class__.__name__ == "SmartWidgetBox" and id(w) not in seen:
                    seen.add(id(w))
                    yield w
    # also cover any SmartWidgetBox tracked via its own registry
    for w in getattr(SmartWidgetBox, "_instances", []):
        if id(w) not in seen:
            seen.add(id(w))
            yield w


@hook.subscribe.enter_chord
def close_widgetboxes_on_chord(chord_name):
    global _SAVED_WIDGETBOX_NAMES
    _SAVED_WIDGETBOX_NAMES = []
    for w in _all_smart_widgetboxes():
        if bool(getattr(w, "box_is_open", False)):
            _SAVED_WIDGETBOX_NAMES.append(getattr(w, "name", None))
            try:
                w.toggle()
            except Exception:
                pass


@hook.subscribe.leave_chord
def restore_widgetboxes_on_chord_leave():
    global _SAVED_WIDGETBOX_NAMES
    names = list(_SAVED_WIDGETBOX_NAMES)
    _SAVED_WIDGETBOX_NAMES = []
    if not names:
        return

    def _do_restore():
        for w in _all_smart_widgetboxes():
            if getattr(w, "name", None) in names and not bool(
                getattr(w, "box_is_open", False)
            ):
                try:
                    w.toggle()
                except Exception:
                    pass

    # defer one tick so the chord-leave state fully settles before
    # we mutate bar widgets (otherwise toggle can race and no-op).
    qtile.call_later(0.05, _do_restore)


# ----------------------------------------------
# 13- Function to enable the passthrough mode
# ---------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_passthrough(chord_name):
    if chord_name == "PASSTHROUGH":
        _enable_passthrough(qtile)


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


def _cycle_keyboard(step=1):
    """Cycle the w_lang chip's layout forward (step=1) or back (step=-1).

    KeyboardLayout ships only next_keyboard(), so right-click-to-go-back
    has to walk configured_keyboards itself. Reuses the widget's own
    backend + option so the layout is set exactly the way the widget
    would have set it, then tick()s to repaint immediately rather than
    waiting for the next poll.

    Not reachable from `qtile cmd-obj -f eval`: that runs in the Qtile
    object's namespace, not this module's. Test it by clicking the chip
    (or via xdotool), not through eval.
    """
    w = qtile.widgets_map.get("w_lang")
    if not w:
        return
    try:
        kbs = list(w.configured_keyboards)
        if not kbs:
            return
        current = w.backend.get_keyboard()
        idx = kbs.index(current) if current in kbs else 0
        target = kbs[(idx + step) % len(kbs)]
        # set_keyboard() already reloads ~/.Xmodmap itself after running
        # setxkbmap, so there is no need to spawn xmodmap again here.
        w.backend.set_keyboard(target, w.option)
        w.tick()
    except Exception:
        # logger is imported lazily elsewhere in this file, so import it
        # here rather than relying on a module-level name that does not
        # exist -- otherwise the handler itself raises NameError.
        from libqtile.log_utils import logger

        logger.exception("_cycle_keyboard failed")


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


# Select an area and copy the PNG to the clipboard. A real script rather than an
# inline `sh -c` string: it logs to /tmp/qtile-screenshot-$UID.log, so if the
# button ever looks like it does nothing there is something to read.
SCREENSHOT_AREA_CMD = os.path.expanduser(
    "~/.config/qtile/scripts/screenshot-area.sh"
)


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
        widget.TextBox(
            name="screenshot_chip_nu",
            text="󰹑",
            fontsize=16,
            padding=10,
            foreground=colors[1],
            mouse_callbacks={
                "Button1": lazy.spawn(SCREENSHOT_AREA_CMD),
            },
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
            # default urgent_alert_method is "border" -- draws a thick
            # (borderwidth=4) solid-colored box around the group's icon
            # glyph when a background/unvisited group gets a new window,
            # which at this icon size just reads as an ugly filled
            # square. "text" instead just recolors the icon glyph itself,
            # consistent with highlight_method="text" above for the
            # active group -- no boxes anywhere on this widget.
            urgent_alert_method="text",
            urgent_text=colors[3],
            hide_unused=True,
            # GroupBox enables drag-and-drop of group names by default.
            # button_release() ends a drag with
            # `group.switch_groups(self.clicked.name)`, which SWAPS the
            # two groups outright -- so a stray drag while clicking
            # silently reorders the workspace icons. That is destructive
            # here because every group carries `matches=[]` rules binding
            # apps to it (browsers -> 2, files -> 3, editors -> 4,
            # chrome -> 6); swapping two groups leaves apps opening in
            # the wrong workspace with nothing on screen explaining why.
            #
            # Nothing here wants runtime group reordering -- the order is
            # declared in the Group list and the keybinds assume it -- so
            # the gesture is turned off entirely.
            #
            # Side effect, and a welcome one: with drag disabled,
            # clicking the ALREADY-ACTIVE group toggles back to the
            # previous group (`toggle` defaults True, and go_to_group
            # only reaches that branch when disable_drag is set).
            disable_drag=True,
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
                "Media-Mode": "󰕾   MEDIA : J , K , M , H , L , P ",
                "Scratch-Mode": "󰈆   SCRATCH",
                "Draw-Mode": "󰏫   DRAW : w , c , z , r , v ",
                "Mouse-Mode": "󰍽   MOUSE : n , f , g , e , r , m ",
                "Lang-Switch": "   LANG : a , e , t , d ",
                "CheatSheet-Mode": "󰆍   CHEATSHEET : k , v , f ",
                "WallpaperPicker": "󰸉   WALLPAPERS : / , h , j , k ,l , R , ENTER ",
                "PASSTHROUGH": "   PASSTHROUGH : ESC",
                "PASSTHROUGH-CONFIRM": "   EXIT PASSTHROUGH ? y , n , ESC",
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
                "Button1": lambda: qtile.spawn(
                    'battery_notify'
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
                "Button1": lambda: qtile.spawn(
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
                "Button1": lambda: qtile.spawn(myFullScreenTerm + " -e btop")
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
        # See matching comment on the normal_user_bar() GroupBox above --
        # default urgent_alert_method="border" draws an ugly filled-
        # looking box around the icon glyph for unvisited groups with a
        # new window; "text" just recolors the glyph instead.
        urgent_alert_method="text",
        urgent_text=colors[3],
        hide_unused=True,
        # See the disable_drag comment on the other GroupBox above: a
        # stray drag swaps two groups and breaks the per-group app
        # matches. Must be set on BOTH GroupBoxes or the bar this one
        # builds keeps the destructive gesture.
        disable_drag=True,
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
            # markup styles — use the active palette so TaskList retints
            # on theme swap. colors[2]=bg-alt, colors[0]=bg, colors[6]=blue,
            # colors[5]=purple, colors[3]=red.
            markup_normal=f'<span background="{colors[2][0]}55">{{}}</span>',
            markup_focused=f'<span background="{colors[0][0]}EE" foreground="{colors[6][0]}" weight="bold">F {{}}</span>',
            markup_floating=f'<span background="{colors[0][0]}EE" foreground="{colors[5][0]}">V {{}}</span>',
            markup_focused_floating=f'<span background="{colors[0][0]}EE" foreground="{colors[5][0]}" weight="bold">VF {{}}</span>',
            markup_minimized=f'<span background="{colors[0][0]}EE" foreground="{colors[3][0]}">↓ {{}}</span>',
            max_title_width=120,
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
                "Media-Mode": "󰕾   MEDIA : J , K , M , H , L , P ",
                "Scratch-Mode": "󰈆   SCRATCH",
                "Draw-Mode": "󰏫   DRAW : w , c , z , r , v ",
                "Mouse-Mode": "󰍽   MOUSE : n , f , g , e , r , m ",
                "Lang-Switch": "   LANG : a , e , t , d ",
                "CheatSheet-Mode": "󰆍   CHEATSHEET : k , v , f ",
                "WallpaperPicker": "󰸉   WALLPAPERS : / , h , j , k ,l , R , ENTER ",
                "PASSTHROUGH": "   PASSTHROUGH : ESC",
                "PASSTHROUGH-CONFIRM": "   EXIT PASSTHROUGH ? y , n , ESC",
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
        # ---------------- player (Mpris2, hover expands in-chip) ----------------
        chip(
            ewidget.Mpris2,
            name="w_mpris",
            objname="org.mpris.MediaPlayer2.playerctld",
            format="{xesam:title} — {xesam:artist}",
            playing_text='<span size="12000">⏸</span>',
            paused_text='<span size="9000">▶</span>',
            markup=True,
            stopped_text="",
            no_metadata_text="",
            scroll=True,
            scroll_chars=28,
            padding=10,
            fontsize=15,
            foreground=colors[4],
            mouse_callbacks={
                "Button1": lambda: qtile.spawn("playerctl play-pause"),
                "Button2": lambda: (
                    qtile.widgets_map["w_mpris"].toggle_player()
                    if hasattr(qtile.widgets_map.get("w_mpris"), "toggle_player")
                    else None
                ),
                "Button3": lambda: qtile.spawn("playerctl previous"),
                "Button4": lambda: qtile.spawn("playerctl next"),
                "Button5": lambda: qtile.spawn("playerctl previous"),
            },
        ),
        # ------------------------------------------------------------------------
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
                        "Button1": lambda: qtile.spawn(
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
                        "Button1": lambda: qtile.spawn(
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
                "Button1": lazy.function(toggle_wallpaper_picker),
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
                    mouse_callbacks={
                        "Button1": lazy.spawn(
                            "python3 " + os.path.expanduser(
                                "~/.config/qtile/scripts/qupdate.py"
                            ) + " --toggle"
                        ),
                    },
                ),
                # Disk — root + home free space in one chip (separate
                # partitions on this machine; root alone is misleading
                # since it's the much smaller one).
                chip(
                    ewidget.GenPollText,
                    name="w_disk",
                    func=_disk_combined_text,
                    update_interval=60,
                    fontsize=10,
                    padding=11,
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
                "Button1": lambda: qtile.spawn(
                    'battery_notify'
                )
            },
        ),
        # Keyboard layout
        chip(
            ewidget.KeyboardLayout,
            name="w_lang",
            configured_keyboards=["us", "ara", "tr", "de"],
            # Nerd Font keyboard glyph rather than a flag emoji. Colour
            # emoji are bitmap glyphs: they ignore the widget's
            # foreground, sit on their own baseline, and render at a size
            # unrelated to the surrounding text -- which is why the flag
            # looked too small at bar size and too big once scaled. A
            # monochrome glyph is just a character, so the size and
            # colour set below actually take effect.
            #
            # Flag emoji. Tried monochrome Nerd Font glyphs (keyboard,
            # keyboard_variant, globe) to get something that inherits the
            # theme colour -- none of them read as well as the flag, which
            # is instantly recognisable without being learned.
            #
            # Size is the fiddly part: these are colour BITMAP glyphs, so
            # they render at whatever size the font provides and sit
            # slightly small next to text at the same nominal size. Bar
            # text is 10pt (10240 pango units); unscaled the flag looked
            # undersized, and 15000 was too big. 12000 splits it.
            display_map={
                "us": "<span size='11000'>🇺🇸</span> EN",
                "ara": "<span size='11000'>🇸🇦</span> AR",
                "tr": "<span size='11000'>🇹🇷</span> TR",
                "de": "<span size='11000'>🇩🇪</span> DE",
            },
            markup=True,
            fmt="{}",
            padding=11,
            foreground=colors[4],
            mouse_callbacks={
                # Left cycles forward, right cycles back. Upstream ships
                # only next_keyboard, so _cycle_keyboard walks the same
                # configured_keyboards list in either direction.
                "Button1": lambda: _cycle_keyboard(1),
                "Button3": lambda: _cycle_keyboard(-1),
            },
        ),
        # Clock
        chip(
            ewidget.Clock,
            name="w_clock",
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
                chip(
                    HideablePollText,
                    name="w_nightlight",
                    func=_nightlight_text,
                    update_interval=5,
                    padding=11,
                    fontsize=11,
                    foreground=colors[6],
                    mouse_callbacks={
                        "Button1": lambda: _nightlight_on(),
                        "Button3": lambda: _nightlight_off(),
                    },
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


# ----------------------------------------------------------------
# Player (playerctl) helpers + auto-hiding poll text
# ----------------------------------------------------------------


def _pctl(*args):
    try:
        r = subprocess.run(
            ["playerctl", *args], capture_output=True, text=True, timeout=0.5
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _player_status():
    s = _pctl("status")
    return s if s in ("Playing", "Paused") else ""


def _player_title_text():
    if not _player_status():
        return ""
    t = _pctl("metadata", "-f", "{{artist}} - {{title}}")
    t = t.strip(" -")
    return (" " + (t[:35] + "…" if len(t) > 36 else t)) if t else ""


def _player_playpause_text():
    s = _player_status()
    if s == "Playing":
        return "="
    if s == "Paused":
        return "▶"
    return ""


def _player_prev_text():
    return "<" if _player_status() else ""


def _player_next_text():
    return ">" if _player_status() else ""


def _player_close_text():
    return "✕" if _player_status() else ""


# Mpris hover — expand icon to "‹  icon  ›" inside same chip
_MPRIS_BASE_PLAYING = '<span size="12000">⏸</span>'
_MPRIS_BASE_PAUSED = '<span size="9000">▶</span>'
_MPRIS_HOVER_PLAYING = '<span size="12000">‹    ⏸    ›</span>'
_MPRIS_HOVER_PAUSED = '<span size="11000">‹    ▶    ›</span>'


def _mpris_apply_templates(hovered):
    w = qtile.widgets_map.get("w_mpris")
    if not w:
        return
    playing = _MPRIS_HOVER_PLAYING if hovered else _MPRIS_BASE_PLAYING
    paused = _MPRIS_HOVER_PAUSED if hovered else _MPRIS_BASE_PAUSED
    try:
        w.playing_text = playing
        w.paused_text = paused
        if hasattr(w, "prefixes"):
            w.prefixes["Playing"] = playing
            w.prefixes["Paused"] = paused
        w.status = playing if getattr(w, "is_playing", False) else paused
        track = getattr(w, "track_info", "") or ""
        new_text = w.status.format(track=track)
        w.update(new_text)
    except Exception:
        pass


# -------- Nightlight (gammastep / redshift) --------
def _nightlight_bin():
    for b in ("gammastep", "redshift"):
        try:
            r = subprocess.run(["which", b], capture_output=True, text=True)
            if r.returncode == 0:
                return b
        except Exception:
            pass
    return None


_NIGHTLIGHT_MARK = os.path.expanduser("~/.cache/qtile_nightlight")


def _nightlight_active():
    return os.path.exists(_NIGHTLIGHT_MARK)


def _nightlight_text():
    if not _nightlight_bin():
        return ""
    return "󱩌"


def _nightlight_on():
    b = _nightlight_bin()
    if not b:
        subprocess.Popen(
            ["notify-send", "Nightlight", "install gammastep or redshift"]
        )
        return
    subprocess.Popen(["pkill", "-x", b])
    flags = "-m randr " if b == "gammastep" else ""
    subprocess.Popen(["sh", "-c", f"{b} {flags}-O 4000 >/dev/null 2>&1"])
    try:
        open(_NIGHTLIGHT_MARK, "w").close()
    except Exception:
        pass


def _nightlight_off():
    b = _nightlight_bin()
    if not b:
        return
    subprocess.Popen(["pkill", "-x", b])
    if b == "gammastep":
        subprocess.Popen(["sh", "-c", "gammastep -m randr -x >/dev/null 2>&1"])
    else:
        subprocess.Popen(["sh", "-c", "redshift -x >/dev/null 2>&1"])
    try:
        os.remove(_NIGHTLIGHT_MARK)
    except Exception:
        pass


# -------- Dynamic tooltip helpers --------
def _sh(cmd, timeout=1.5):
    try:
        r = subprocess.run(
            ["sh", "-c", cmd], capture_output=True, text=True, timeout=timeout
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _cpu_top_text():
    out = _sh(
        "ps -eo pcpu,comm --sort=-pcpu --no-headers | awk 'NF' | head -5"
    )
    if not out:
        return "No data"
    lines = []
    for ln in out.splitlines():
        parts = ln.strip().split(None, 1)
        if len(parts) == 2:
            lines.append(f"{parts[0]:>5}%  {parts[1]}")
    return "Top CPU:\n" + "\n".join(lines)


def _mem_top_text():
    out = _sh(
        "ps -eo pmem,rss,comm --sort=-pmem --no-headers | awk 'NF' | head -5"
    )
    if not out:
        return "No data"
    lines = []
    for ln in out.splitlines():
        parts = ln.strip().split(None, 2)
        if len(parts) == 3:
            mib = int(parts[1]) // 1024
            lines.append(f"{parts[0]:>5}%  {mib:>5} MiB  {parts[2]}")
    return "Top MEM:\n" + "\n".join(lines)


_TOP_DIRS_CACHE = ""
_TOP_DIRS_LAST = 0.0
_TOP_DIRS_TTL = 900  # 15 min
_TOP_DIRS_RUNNING = False
_TOP_DIRS_CACHE_FILE = os.path.expanduser("~/.cache/qtile/top_dirs")


def _load_top_dirs_cache():
    global _TOP_DIRS_CACHE, _TOP_DIRS_LAST
    try:
        st = os.stat(_TOP_DIRS_CACHE_FILE)
        with open(_TOP_DIRS_CACHE_FILE) as f:
            _TOP_DIRS_CACHE = f.read().strip()
        _TOP_DIRS_LAST = st.st_mtime
    except Exception:
        pass


def _refresh_top_dirs():
    global _TOP_DIRS_CACHE, _TOP_DIRS_LAST, _TOP_DIRS_RUNNING
    if _TOP_DIRS_RUNNING:
        return
    _TOP_DIRS_RUNNING = True
    try:
        # Parallel per-subdir du: much faster on multi-core than single du walk.
        # ionice+nice keep it out of the way. Only top-level dirs of $HOME.
        cmd = (
            "cd ~ && ls -A1 | "
            "xargs -d '\\n' -P 8 -I{} "
            "ionice -c3 nice -n19 du -sxb -- {} 2>/dev/null | "
            "sort -rn | head -6 | "
            "numfmt --to=iec --suffix=B --field=1 --padding=7"
        )
        r = subprocess.run(
            ["bash", "-c", cmd],
            capture_output=True,
            text=True,
            timeout=600,
        )
        if r.returncode == 0 and r.stdout.strip():
            _TOP_DIRS_CACHE = r.stdout.strip()
            _TOP_DIRS_LAST = time.time()
            try:
                os.makedirs(os.path.dirname(_TOP_DIRS_CACHE_FILE), exist_ok=True)
                with open(_TOP_DIRS_CACHE_FILE, "w") as f:
                    f.write(_TOP_DIRS_CACHE)
            except Exception:
                pass
    except Exception:
        pass
    finally:
        _TOP_DIRS_RUNNING = False


_load_top_dirs_cache()


def _top_dirs_text():
    if time.time() - _TOP_DIRS_LAST > _TOP_DIRS_TTL:
        threading.Thread(target=_refresh_top_dirs, daemon=True).start()
    if not _TOP_DIRS_CACHE:
        return "(computing…)"
    home = os.path.expanduser("~")
    out = []
    for ln in _TOP_DIRS_CACHE.splitlines():
        parts = ln.split(None, 1)
        if len(parts) != 2:
            continue
        size, path = parts
        if path == home or path in (".", ""):
            continue
        if path.startswith(home):
            short = "~" + path[len(home):]
        elif path.startswith("/"):
            short = path
        else:
            short = "~/" + path
        out.append(f" {size:>7}  {short}")
    return "\n".join(out[:5])


def _disk_combined_text():
    import os

    def stat_info(path):
        try:
            st_dev = os.stat(path).st_dev
            vfs = os.statvfs(path)
            return st_dev, vfs.f_bavail * vfs.f_frsize / (1024**3)
        except Exception:
            return None, None

    root_dev, root_free = stat_info("/")
    home_dev, home_free = stat_info("/home")

    if root_free is None and home_free is None:
        return "🖴 N/A"
    if home_dev is None or root_dev == home_dev:
        # /home isn't a separate partition -- just show root.
        return f"🖴 /{root_free:.1f}G" if root_free is not None else "🖴 N/A"
    # Separated partitions -- show whichever has more free space.
    if (root_free or 0) >= (home_free or 0):
        return f"🖴 /{root_free:.1f}G"
    return f"🖴  {home_free:.1f}G"


def _disk_parts_text():
    out = _sh(
        "df -h --output=target,source,fstype,size,used,avail,pcent "
        "-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x fuse.portal "
        "2>/dev/null | tail -n +2"
    )
    if not out:
        return "No data"
    rows = []
    for ln in out.splitlines():
        p = ln.split()
        if len(p) < 7:
            continue
        target, source, fstype, size, used, avail, pcent = p[:7]
        try:
            pct = int(pcent.rstrip("%"))
        except Exception:
            pct = 0
        rows.append((target, source, fstype, size, used, avail, pcent, pct))
    if not rows:
        return "No data"
    rows.sort(key=lambda r: -r[7])
    lines = ["Disk usage"]
    for target, source, fstype, size, used, avail, pcent, pct in rows:
        lines.append(f" {target} — {pcent}   ({avail} free / {size})")
    top = _top_dirs_text()
    if top:
        lines.append("")
        lines.append("Biggest in ~:")
        lines.append(top)
    return "\n".join(lines)


def _battery_detail_text():
    import glob

    bats = glob.glob("/sys/class/power_supply/BAT*")
    if not bats:
        return "No battery"
    b = bats[0]

    def _r(p, cast=str, default=None):
        try:
            with open(os.path.join(b, p)) as f:
                return cast(f.read().strip())
        except Exception:
            return default

    status = _r("status", str, "?") or "?"
    pct = _r("capacity", int, 0)
    energy_now = _r("energy_now", int) or _r("charge_now", int) or 0
    energy_full = _r("energy_full", int) or _r("charge_full", int) or 1
    power_now = _r("power_now", int) or _r("current_now", int) or 0

    lines = [f"Battery: {status}  {pct}%"]
    if power_now > 0:
        watts = power_now / 1_000_000
        lines.append(f"Draw: {watts:.2f} W")
        if status == "Discharging":
            hours = energy_now / power_now
        elif status == "Charging":
            hours = (energy_full - energy_now) / power_now
        else:
            hours = 0
        if hours > 0:
            h = int(hours)
            m = int((hours - h) * 60)
            label = "remaining" if status == "Discharging" else "to full"
            lines.append(f"~{h}h {m}m {label}")
    else:
        lines.append("Draw: idle")
    return "\n".join(lines)


# -------- Prayer countdown --------
_PRAYER_SCRIPT = os.path.expanduser("~/.config/qtile/scripts/prayer_next.sh")


def _prayer_text():
    try:
        r = subprocess.run(
            [_PRAYER_SCRIPT], capture_output=True, text=True, timeout=8
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


class HideablePollText(ewidget.GenPollText):
    def calculate_length(self):
        if not (self.text or "").strip():
            return 0
        return super().calculate_length()

    def draw(self):
        if not (self.text or "").strip():
            try:
                self.drawer.clear(self.background or self.bar.background)
                self.drawer.draw(offsetx=self.offset, offsety=self.offsety, width=0)
            except Exception:
                pass
            return
        super().draw()


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
        was_open = getattr(self, "box_is_open", False)
        if not was_open:
            SmartWidgetBox.close_all(except_self=self)
        res = super().toggle(*a, **k)
        try:
            qtile.call_later(0.1, install_bar_tooltips)
        except Exception:
            pass
        if not was_open and self.box_is_open:
            self._animate_reveal()
        # Systray icons need a forced repaint after every toggle, in both
        # directions -- see _repaint_systray for why.
        try:
            qtile.call_later(0.05, self._repaint_systray)
        except Exception:
            pass
        return res

    def _repaint_systray(self):
        """Force embedded tray icons to repaint after a box toggle.

        Symptom this fixes: tray icons are invisible but still take
        clicks.

        Tray icons are not painted by the bar at all -- each is a
        separate XEmbed *client* window owned by its application.
        WidgetBox.toggle_widgets() hides them on close and relies on
        Systray.draw() calling icon.unhide() to bring them back. But
        draw() also does

            icon.window.set_attribute(backpixmap=self.drawer.pixmap)

        and that pixmap is reallocated when the widget is removed from
        and re-inserted into the bar. So the icons come back mapped and
        correctly positioned -- hence still clickable -- while painting
        from a stale pixmap, which reads as invisible. It is
        intermittent because it depends on whether the client happens to
        receive an expose event that makes it redraw itself.

        Fix: once the bar has settled, hide the icons and redraw, which
        re-runs the unhide + _XEMBED_EMBEDDED_NOTIFY handshake against
        the current pixmap and makes each client repaint.
        """
        try:
            for w in self.widgets:
                # Duck-typed rather than isinstance: qtile_extras'
                # Systray subclasses the libqtile one, and importing
                # either here just to type-check would be fragile.
                icons = getattr(w, "tray_icons", None)
                if not icons:
                    continue
                if w not in self.bar.widgets:
                    continue  # box is closed; nothing to repaint
                for icon in icons:
                    try:
                        icon.hide()
                    except Exception:
                        pass
                w.draw()
        except Exception:
            # Never let a cosmetic repaint break the toggle itself.
            pass

    def _animate_reveal(self):
        # A true width/layout-growth animation isn't practical here --
        # qtile computes each widget's own calculate_length() at insert
        # time, and animating that reliably across both toggle_widgets()
        # code paths (default vs insert_before_name) is fragile.
        #
        # Tried hiding each chip via drawer.disable() until its reveal
        # moment first -- turned out disable() is a pure no-op skip
        # inside Drawer.draw() (see backend/base/drawer.py), not a
        # blank-paint, so nothing was ever actually hidden: the chips
        # were already fully visible the instant toggle_widgets() ran
        # (base WidgetBox.toggle() itself calls bar.draw() with every
        # child already enabled), so the "reveal" was just riding on
        # stale already-visible pixels -- no perceptible left-to-right
        # order, and disable()/enable() churn mid-flash likely explains
        # the reported glitchiness.
        #
        # Replaced with what's actually achievable: a real multi-step
        # (not instant on/off) color pulse across each chip's
        # background decoration, staggered left-to-right by
        # `self.widgets` index -- confirmed via `qtile cmd-obj -o bar
        # top -f info` that this index order matches true on-screen
        # left-to-right order (toggle_widgets() reverse-inserts at a
        # fixed index, which nets out to preserving self.widgets'
        # original order).
        STEPS = 8
        RAMP_S = 0.09
        STAGGER_S = 0.10

        def _mix(base_hex, bright_hex, t):
            b = base_hex.lstrip("#")
            h = bright_hex.lstrip("#")
            br, bgc, bb = int(b[0:2], 16), int(b[2:4], 16), int(b[4:6], 16)
            hr, hg, hb = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
            r = int(br + (hr - br) * t)
            g = int(bgc + (hg - bgc) * t)
            bl = int(bb + (hb - bb) * t)
            return f"#{r:02x}{g:02x}{bl:02x}"

        for i, w in enumerate(self.widgets):
            deco = getattr(w, "_flash_deco", None)
            base = getattr(w, "_flash_base", None)
            bright = getattr(w, "_flash_bright", None)
            if deco is None or base is None or bright is None:
                continue

            def _tick(step, deco=deco, base=base, bright=bright):
                try:
                    t = step / STEPS if step <= STEPS else 1 - (step - STEPS) / STEPS
                    deco.colour = _mix(base, bright, max(0.0, min(1.0, t)))
                    self.bar.draw()
                except Exception:
                    return False
                if step < STEPS * 2:
                    self.timeout_add(RAMP_S / STEPS, lambda: _tick(step + 1))
                return False

            self.timeout_add(i * STAGGER_S, lambda tick=_tick: tick(0))

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


def _brighten_hex(hexcolor, amount=0.35):
    hexcolor = hexcolor.lstrip("#")
    r, g, b = int(hexcolor[0:2], 16), int(hexcolor[2:4], 16), int(hexcolor[4:6], 16)
    r = int(r + (255 - r) * amount)
    g = int(g + (255 - g) * amount)
    b = int(b + (255 - b) * amount)
    return f"#{r:02x}{g:02x}{b:02x}"


def _brighten_color(c, amount=0.35):
    # colorsW entries are [hex, hex] pairs (gradient-capable decorations);
    # handle both that and a plain hex string.
    if isinstance(c, (list, tuple)):
        return [_brighten_hex(x, amount) for x in c]
    return _brighten_hex(c, amount)


class _ChipFlashMixin:
    """Brief brighten-then-fade flash on click. Wraps button_press so
    whatever click behavior the underlying widget/mouse_callbacks already
    have runs completely unchanged -- this only adds visual feedback
    around it, never replaces the actual click handling."""

    _flash_deco = None
    _flash_base = None
    _flash_bright = None

    def button_press(self, x, y, button):
        if self._flash_deco is not None:
            try:
                self._flash_deco.colour = self._flash_bright
                self.bar.draw()
                self.timeout_add(0.25, self._chip_flash_revert)
            except Exception:
                pass
        return super().button_press(x, y, button)

    def _chip_flash_revert(self):
        try:
            self._flash_deco.colour = self._flash_base
            self.bar.draw()
        except Exception:
            pass


_flash_widget_cache = {}


def _flash_widget_class(WCls):
    if WCls not in _flash_widget_cache:
        _flash_widget_cache[WCls] = type(
            f"Flash{WCls.__name__}", (_ChipFlashMixin, WCls), {}
        )
    return _flash_widget_cache[WCls]


def chip(WCls, chip_color=None, **kwargs):
    base_color = chip_color if chip_color is not None else DEFAULT_CHIP_COLOR
    deco = RectDecoration(
        colour=base_color,
        radius=11,
        filled=True,
        padding_x=3,
        padding_y=2,
        # NOTE:  if u want just a border, u can use this
        # filled=False,
        # line_width=1.5,
        # line_colour= colorsW[8]
    )

    if "decorations" in kwargs and kwargs["decorations"]:
        kwargs["decorations"] = list(kwargs["decorations"]) + [deco]
    else:
        kwargs["decorations"] = [deco]

    # Click-feedback flash only on chips that actually respond to clicks --
    # no point animating ones that don't do anything when pressed.
    has_click = bool(kwargs.get("mouse_callbacks"))
    cls = _flash_widget_class(WCls) if has_click else WCls

    w = cls(**kwargs)
    if has_click:
        w._flash_deco = deco
        w._flash_base = base_color
        w._flash_bright = _brighten_color(base_color, amount=0.55)

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
    # --- Homerow: keyboard hints over the focused window ---
    # Not Homerow's own shift+space, which would swallow every shift+space
    # you type.
    Key(
        [mod2, "shift"],
        "f",
        lazy.spawn(
            os.path.expanduser(
                "~/Attia-Pro/Projects/Homerow_replika/homerow-hint"
            )
        ),
        desc="Homerow: hint and click UI elements by keyboard",
    ),
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
    # ---screenshot: select an area, straight to the clipboard---
    Key(
        [],
        "Print",
        lazy.spawn(SCREENSHOT_AREA_CMD),
        desc="Screenshot area -> clipboard (same as the bar's camera chip)",
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
    # ---copyq clipboard popup---
    Key([mod2], "v", lazy.spawn(os.path.expanduser("~/.config/AtiScriptsV1/copyq_rofi")), desc="CopyQ clipboard rofi picker (ctrl+j/k nav, thumbnails)"),
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
    # ---restart qtile — preserves window→group + layout state via
    # qtile's pickle serialization. reload_config loses layout order and
    # can re-shuffle Match'd apps to their default group.
    Key(
        [mod, "shift"],
        "r",
        lazy.function(_smooth_restart),
        desc="Restart qtile (preserves window state)",
    ),
    # --- logout menu ---
    Key([mod, "shift"], "q", lazy.spawn("dm-logout -r"), desc="Logout menu"),
    # --- theme toggle (doomone <-> pywal) ---
    # Theme picker moved to win+p → c (KeyChord below).
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
            # Theme picker (rofi).
            Key(
                [],
                "c",
                lazy.spawn("theme-toggle"),
                desc="Theme picker (rofi)",
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
            Key(["shift"], "h", lazy.function(lambda _: brightness_change(-5))),
            Key(["shift"], "l", lazy.function(lambda _: brightness_change(5))),
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
            # Only F12 here: y/n live in PASSTHROUGH_CONFIRM_CHORD so they stay
            # typable in passthrough, and Escape is re-appended below (qtile's
            # KeyChord.__init__ would otherwise shadow it).
            Key([], "F12", lazy.function(_passthrough_esc)),
        ],
        mode=True,
        swallow=False,
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

# Handle to re-grab PASSTHROUGH after Esc; see _passthrough_esc / cleanup_on_leave.
PASSTHROUGH_CHORD = next(
    (k for k in keys if isinstance(k, KeyChord) and k.name == "PASSTHROUGH"), None
)

# Only grabbed while the confirm popup is up, so y/n remain ordinary typable keys
# for the rest of passthrough. Never reachable from the root keymap -- the trigger
# below is a placeholder; cleanup_on_leave grabs this chord programmatically.
PASSTHROUGH_CONFIRM_CHORD = KeyChord(
    [],
    "F13",
    [
        Key([], "y", lazy.function(_passthrough_confirm_yes)),
        Key([], "n", lazy.function(_passthrough_confirm_no)),
    ],
    mode=True,
    swallow=True,
    name="PASSTHROUGH-CONFIRM",
)

# KeyChord.__init__ appends its own bare Key([], "Escape") to every chord's
# submappings. It lands last, so grab_chord() grabs it last and it overwrites our
# Escape in keys_map -- leaving Escape with zero commands, which is why the confirm
# popup never opened. Re-append ours so it is grabbed last and actually runs.
if PASSTHROUGH_CHORD is not None:
    PASSTHROUGH_CHORD.submappings.append(
        Key([], "Escape", lazy.function(_passthrough_esc))
    )
PASSTHROUGH_CONFIRM_CHORD.submappings.append(
    Key([], "Escape", lazy.function(_passthrough_confirm_esc))
)

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
            # Match(
            #     wm_class="alacritty",
            #     title=re.compile(r"^(?!.*(nvimsum|edit-field)).*$"),
            # ),
            Match(wm_class="cursor"),
        ],
        layout="monadtall",
    ),
    Group(
        "5",
        label="",
        matches=[
            Match(wm_class="brave"),
            Match(wm_class="brave-browser"),
        ],
        layout="max",
    ),
    Group(
        "6",
        label="👁",
        matches=[
            Match(wm_class="google-chrome"),
            # Chrome sets WM_CLASS "chrome"/"Chrome" for some windows and
            # "google-chrome"/"Google-chrome" for others, so match both or
            # half the windows escape to the current group.
            Match(wm_class="chrome"),
            Match(wm_class="chromium"),
        ],
        layout="monadtall",
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
            Match(wm_class="discord"),
        ],
    ),
]


# -------------------------------------------------------
# this is  a special  WorkSpace  for  Obsidian  and  Anki
# -------------------------------------------------------

for i in groups:
    if i.name == "S":
        continue

    keys.extend(
        [
            Key(
                [mod],
                i.name,
                go_to_group_or_notify(i.name),
                desc=f"Switch to group {i.name}",
            ),
            Key(
                [mod, "shift"],
                i.name,
                lazy.window.togroup(i.name),
                desc="Move focused window to group {}".format(i.name),
            ),
        ]
    )


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
                "calc",
                "env GTK_THEME=Adwaita:dark qalculate-gtk",
                width=0.6,
                height=0.6,
                x=0.2,
                y=0.1,
                opacity=1,
            ),
            # qdrop is self-managed (socket-controlled). See scripts/qdrop.py.
            ### NOTE:for chatgpt & deepseek & whatsapp i decided to use brave browser by using one browser engine for all, i  used separate profiles for
            ### each browser. They live as PROFILES inside the main Brave instance
            ### (~/.config/BraveSoftware/Brave-Browser/<Name>), not as separate browsers.
            #
            # --profile-directory, NOT --user-data-dir. This is the difference
            # between "a profile" and "a whole second browser", and it was worth
            # ~1GB on this 8G laptop.
            #
            # A separate --user-data-dir cannot share anything with the main
            # instance: each one spawned its own gpu-process, network service,
            # storage service and 3 zygotes just to render a single page. Three
            # scratchpads meant four independent Brave stacks totalling ~4.6G of
            # 7.6G RAM, which is what kept earlyoom SIGTERMing renderers and
            # showing "Aw, Snap!" in the WhatsApp dropdown (TROUBLESHOOTING.md).
            # --profile-directory keeps the separate logins/cookies/sessions but
            # shares the engine, so each dropdown costs one renderer.
            #
            # MATCH ON THE URL HOST, NOT ON --class.
            #
            # --class does NOT survive this. When brave is already running the
            # new invocation is forwarded over the singleton socket, and the
            # window is created by the ORIGINAL browser process using its own
            # class. What actually lands on the window is:
            #
            #     WM_CLASS = ("web.whatsapp.com", "Brave-browser")
            #                  ^ URL-derived instance  ^ NOT sp-whatsapp
            #
            # With Match(wm_class="sp-whatsapp") that never fires, and the
            # dropdown opens as a normal tiled window in monadtall instead.
            #
            # The instance field is URL-derived and stable, so match on that.
            # It is also correct on a cold start -- when the scratchpad is what
            # launches brave, --class DOES apply, but the host half of the pair
            # is identical either way, which is exactly what --class is not.
            # Match(wm_instance_class=...) is the rule that targets exactly
            # that field: compare() maps it to wm_class[0], where a plain
            # wm_class rule is tested against every field of the pair.
            #
            # Only --app= windows get a host-derived instance name; ordinary
            # brave windows are ("brave-browser", "Brave-browser"), so these
            # matches cannot swallow a normal browser window by accident.
            # --class/--name are dropped below rather than left in as flags
            # that only sometimes do something. Check any of this with:
            #     xprop WM_CLASS
            #
            # The old --disable-background-networking / --disable-component-update
            # / --disable-breakpad / --disable-sync / --no-first-run flags are
            # gone: they configure a BROWSER PROCESS at startup, and these
            # commands now join the already-running one, so they were silently
            # ignored. Put them in ~/.config/brave-flags.conf if you want them --
            # that applies them to the single instance that actually starts.
            DropDown(
                "chatgpt",
                'brave --profile-directory="Chatgpt" '
                "--app=https://chat.openai.com ",
                match=Match(wm_instance_class="chat.openai.com"),
                width=0.7,
                height=0.8,
                x=0.15,
                y=0.1,
                opacity=1,
                on_focus_lost_hide=False,
            ),
            DropDown(
                "deepseek",
                'brave --profile-directory="Deepseek" '
                "--app=https://chat.deepseek.com ",
                match=Match(wm_instance_class="chat.deepseek.com"),
                width=0.7,
                height=0.8,
                x=0.15,
                y=0.1,
                opacity=0.95,
                on_focus_lost_hide=False,
            ),
            DropDown(
                "whats",
                'brave --profile-directory="Whatsapp" '
                "--app=https://web.whatsapp.com ",
                match=Match(wm_instance_class="web.whatsapp.com"),
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
        Key([mod2], "1", lazy.group["scratchpad"].dropdown_toggle("term1")),
        Key([mod2], "2", lazy.group["scratchpad"].dropdown_toggle("term2")),
        Key([mod2], "3", lazy.group["scratchpad"].dropdown_toggle("mixer")),
        Key([mod2], "4", lazy.group["scratchpad"].dropdown_toggle("2ndScreen")),
        Key([mod2], "5", lazy.group["scratchpad"].dropdown_toggle("calc")),
        Key([mod2], "8", lazy.group["scratchpad"].dropdown_toggle("whats")),
        Key([mod2], "9", lazy.group["scratchpad"].dropdown_toggle("deepseek")),
        Key([mod2], "0", lazy.group["scratchpad"].dropdown_toggle("chatgpt")),
        Key(
            [mod2, "shift"],
            "d",
            lazy.spawn("python3 " + os.path.expanduser("~/.config/qtile/scripts/qdrop.py") + " --toggle"),
        ),
    ]
)


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
    # layout.Tile(shift_windows=True,ratio=0.75, **layout_theme),  # can be used  for write + reading + video = for fun
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

# Some settings that I use on almost every widget, which saves us
# from having to type these out for each individual widget.
widget_defaults = dict(
    font="Ubuntu Bold",
    fontsize=10,
    padding=0,
)

extension_defaults = widget_defaults.copy()

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


def _center_top_groupbox():
    """Pin the GroupBox to the true centre of each top bar.

    Two STRETCH spacers only split the *leftover* space evenly, so the GroupBox
    slides right as the TaskList grows with each opened window. Instead the left
    spacer is a fixed length we recompute: bar centre minus everything left of it.
    The right spacer stays STRETCH so the right-hand widgets still hug the edge.
    """
    for screen in getattr(qtile, "screens", []):
        b = getattr(screen, "top", None)
        widgets = getattr(b, "widgets", None) if b else None
        if not widgets:
            continue
        gb_i = next(
            (i for i, w in enumerate(widgets) if isinstance(w, ewidget.GroupBox)), None
        )
        if not gb_i:  # missing, or nothing to its left
            continue
        sp = widgets[gb_i - 1]
        if not isinstance(sp, ewidget.Spacer):
            continue
        try:
            target = (b.width - widgets[gb_i].length) // 2
            left = widgets[: gb_i - 1]
            tl = next((w for w in left if isinstance(w, widget.TaskList)), None)
            others = sum(w.length for w in left if w is not tl)

            changed = False
            # Pin the TaskList to a fixed width. With stretch=False it sizes to
            # content, so each opened window widened it and shoved the GroupBox
            # right -- at 605px it was already past the bar's centre, which no
            # spacer value can undo. TaskList natively accepts an externally
            # assigned length (that is what its default stretch mode does), so
            # holding it STATIC here is not fighting the widget.
            if tl is not None:
                cap = max(0, target - others)
                if tl.length_type != bar.STATIC or tl.length != cap:
                    tl.length_type = bar.STATIC
                    tl.length = cap
                    changed = True

            left_w = others + (tl.length if tl is not None else 0)
            new_len = max(0, target - left_w)
            # Guard the assignment: draw() redraws widgets and can re-enter this,
            # so an unconditional set would loop.
            if new_len != sp.length:
                sp.length = new_len
                changed = True

            if changed:
                b.draw()
        except Exception:
            pass


_GB_CENTER_PENDING = False


def _schedule_center_groupbox(*_args, **_kwargs):
    """Debounced trigger -- these hooks can fire several times per window event."""
    global _GB_CENTER_PENDING
    if _GB_CENTER_PENDING:
        return
    _GB_CENTER_PENDING = True

    def _run():
        global _GB_CENTER_PENDING
        _GB_CENTER_PENDING = False
        _center_top_groupbox()

    try:
        qtile.call_later(0.05, _run)
    except Exception:
        _GB_CENTER_PENDING = False


for _gb_hook in (
    "startup_complete",
    "client_managed",
    "client_killed",
    "client_name_updated",
    "setgroup",
    "changegroup",
    "focus_change",
):
    try:
        getattr(hook.subscribe, _gb_hook)(_schedule_center_groupbox)
    except Exception:
        pass


def init_widgets_list():
    return [
        *left_side_widgets(),
        # Fixed, not STRETCH -- _center_top_groupbox() drives this length.
        ewidget.Spacer(length=0),
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

# Drag floating layouts.
# Move windows with SUPER instead of ALT
mouse = [
    Drag(
        [mod],  # Super key
        "Button1",
        lazy.window.set_position_floating(),
        start=lazy.window.get_position(),
    ),
    Drag(
        [mod],
        "Button3",
        lazy.window.set_size_floating(),
        start=lazy.window.get_size(),
    ),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]


dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
floating_layout = layout.Floating(
    border_focus=colors[7],
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
        Match(title="imv"),  # Match the imv window
        Match(title="feh"),  # Match feh
        Match(wm_class="mpv"),  # mpv
        Match(wm_class="mpvk"),  # mpv
        Match(wm_class="satty"),  # satty
        Match(wm_class="emacs"),  # emacs
        Match(title="link-preview"),  # preview of nvim (qutebrowser edit link)
        Match(wm_class="clip-view"),  # copyq_rofi alt+w full-text preview
        Match(wm_class="imv"),  # copyq_rofi alt+w image preview
        Match(wm_class="org.gnome.NautilusPreviewer"),  # make the preview float
        Match(wm_class="qdrop"),  # qdrop drop-stash
        # TODOS summary (Mod+Shift+S), centered by _float_and_center_sum.
        # wm_class, not title: WM_CLASS exists before the MapRequest, so this rule
        # wins at group.add() and the window never enters the tiling layout.
        Match(wm_class="sum-md"),
        Match(title="sum.md"),  # fallback for a window opened before the reload
        # Match(wm_class="Anki"),  # make the preview float
    ],
    # qdrop fully self-manages its own position (slide animation driven
    # by scripts/qdrop.py's own move() calls). Without this, qtile's
    # Floating.compute_client_position() re-centers ANY window whose
    # first-map position isn't already on-screen -- confirmed via
    # xdotool geometry polling: it happens regardless of
    # has_user_set_position()/WM_NORMAL_HINTS, since on_screen() alone
    # gates the recenter branch. qdrop deliberately maps off-screen
    # first (see SAFE_OFFSCREEN_Y in qdrop.py) so its real content
    # height can settle before the visible slide starts, which qtile's
    # placement logic reads as "invalid position" and recenters --
    # producing a one-frame flash at qtile's own centered coordinates
    # (computed from qdrop's pre-allocation width, so not even the same
    # spot as a true screen-center) before qdrop's own code corrects it
    # 20ms later. no_reposition_rules skips compute_client_position()
    # entirely for matched clients, so qdrop's own move() calls are the
    # only thing that ever touches its position.
    no_reposition_rules=[Match(wm_class="qdrop")],
)
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None


# ╔───────────────────────────────────────────────────────╗
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░█▀▀░░░█▀▀░█▀█░█▀▄░█▀▀░░░░░░░░░░░│
# │░▄█▄█▄░█▀▄░█░█░█░░░█▀▀░▀▀█░░░█▀▀░█░█░█░█░▀▀█░░░░░░░░░░░│
# │░░▀░▀░░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░░░▀▀▀░▀░▀░▀▀░░▀▀▀░░░▀░░▀░░▀░│
# ╚───────────────────────────────────────────────────────╝


# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"
