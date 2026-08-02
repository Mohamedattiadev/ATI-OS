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
import weakref
from libqtile import bar, hook, layout, pangocffi, qtile, widget
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


# ---------------------------------------------------------------------
# UI scale
# ---------------------------------------------------------------------
# Every pixel dimension below -- font sizes, bar heights, margins, icon
# sizes -- was tuned on a 1366x768 14" panel at ~125 DPI. On a 15" 4K
# laptop that same config renders a sliver of a bar with unreadable text,
# and nothing warns you: the desktop just looks wrong on the one axis
# these dotfiles are supposed to keep identical across machines.
#
# `ui-scale` (AtiScriptsV1) computes a factor from the primary display's
# real DPI and writes it here. It is per-machine and untracked, so the
# repo stays identical while the rendering adapts. A missing file means
# 1.0, which is exactly the reference machine's behaviour -- so qtile
# still starts correctly if ui-scale has never been run.
def _load_ui_scale():
    try:
        with open(os.path.expanduser("~/.cache/qtile/ui_scale")) as f:
            v = float(f.read().strip())
        # Refuse absurd values rather than rendering a 40px bar as 4px and
        # leaving the user with no way to read the menu that fixes it.
        return v if 0.5 <= v <= 4.0 else 1.0
    except (OSError, ValueError):
        return 1.0


UI_SCALE = _load_ui_scale()


def _s(px):
    """Scale a pixel dimension. Floor of 1 so nothing rounds away to zero."""
    return max(1, int(round(px * UI_SCALE)))


from popups import VimCheatsheet, FishCheatsheet, QtileCheatsheet
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

from popups import BluetoothPopup
from popups import AudioPopup
from popups import DisplayPopup


from popups import WifiPopup
from popups import WifiQR

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


def _chip_plate(bg_hex):
    """The plate colour every chip sits on, derived from the active theme.

    This was colorsW[2] -- "#1c1f24", a literal from the static doom-one
    palette baked into this file -- so it stayed the same on all 22 themes.
    Invisible on the dark ones, and plainly wrong on mono-light, where
    near-black chips sat on a white desktop.

    Derived rather than pointed at colors[2], because colors[2] is #000000 on
    every dark theme here: correct in the sense that it tracks, but it would
    turn every chip pure black and change how the bar looks on the themes
    actually in use. Darkening the theme's own background instead keeps the
    plate a shade below whatever the desktop is, which is the relationship
    the hardcoded value had.

    Two factors, chosen by lightness: 30% on a dark background lands gruvbox
    on #1c1c1c, indistinguishable from the #1c1f24 it replaces, while the
    same 30% on white would give mid-grey. 12% on a light background lands
    mono-light on #e0e0e0 -- which is exactly what that theme's own alt slot
    holds, so the derivation agrees with the palette where the palette has an
    opinion.
    """
    r, g, b = (int(bg_hex.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    light = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.5
    f = 0.88 if light else 0.70
    return "#{:02x}{:02x}{:02x}".format(*(round(c * f) for c in (r, g, b)))



os.environ["GTK_IM_MODULE"] = "none"
os.environ["QT_IM_MODULE"] = "none"
os.environ["XMODIFIERS"] = ""

mod = "mod4"  # Primary mod = WINDOWS (Alt broken on hardware)
mod2 = "mod1"  # Secondary mod = ALT

# homerow client. A shell script that pokes the resident daemon over a socket,
# so spawning it costs ~12ms rather than a Python interpreter start.
HOMEROW = os.path.expanduser(
    "~/Attia-Pro/Projects/Homerow_replika/homerow-hint"
)

# Bar indicator for homerow's direct alt+space/j//c bindings. These are not
# qtile chords (see the "Hint mode is bound directly" comment on the keys
# below), so the existing Chord widget cannot show them -- it only reflects
# qtile's own chord state. Instead the homerow daemon itself writes the name
# of whichever mode is currently open to this file the instant it opens one,
# and removes the file the instant it closes (service.py: _set_mode /
# _clear_mode) -- including on a hang, since a killed daemon's next start
# clears any stale file left behind. Polling this is what lets the bar show
# real homerow state rather than a proxy for it.
HOMEROW_MODE_PATH = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "homerow-mode"
)
HOMEROW_MODE_LABELS = {
    "hint": "󰍽   HINT",
    "scroll": "   SCROLL",
    "search": "   SEARCH",
    "caret": "   CARET",
    "caret-search": "   CARET/",
}


def homerow_mode_text():
    """" LABEL " when a mode is open, bare "" when idle.

    The padding is baked in here rather than left to the widget's `fmt`,
    which wraps every poll result unconditionally -- an empty string through
    `fmt=" {} "` would still render as a blank padded pill instead of true
    zero width, so the chip would sit there empty between modes instead of
    disappearing the way the Chord widget above it does.
    """
    try:
        with open(HOMEROW_MODE_PATH, encoding="utf-8") as handle:
            name = handle.read().strip()
    except OSError:
        return ""
    if not name:
        return ""
    return f" {HOMEROW_MODE_LABELS.get(name, name.upper())} "
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

# Must follow `colors`: _chip_plate() reads the active background, and this
# module previously set DEFAULT_CHIP_COLOR eighty lines earlier from a
# literal, where no palette existed yet.
_plate = _chip_plate(colors[0][0])
DEFAULT_CHIP_COLOR = [_plate, _plate]


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


class FittedChord(ewidget.Chord):
    """Chord widget that re-fits the bar BEFORE it repaints it.

    Entering a chord makes this widget go from zero width to the width of a
    whole mode legend -- 225px for Rofi-Mode -- and _TextBox.update() reacts
    by calling bar.draw() immediately. The pass that shrinks the TaskList to
    make room is driven off the enter_chord hook, and hooks run to
    completion before that draw, so for one frame the bar was laid out with
    the new chip and the old TaskList and the right-hand chips sat past the
    edge of the screen.

    Caught on camera rather than guessed at: sampling the bar at 29fps
    across a chord entry, the last chip's right edge sat at x=1355 instead
    of 1351 for two frames, then snapped back. Dropping the debounce delay
    to 0 removed one of them; this removes the other, by doing the re-fit
    between setting the text and asking for the repaint, so the only frame
    that ever reaches the screen is the settled one.

    Overrides update() rather than draw(): draw() runs per repaint, and the
    width only changes when the text does.
    """

    def update(self, text):
        if text is None:
            text = ""
        if self.text == text:
            return
        # The setter stores the text and re-lays the pango layout, so the
        # widget's length is already the NEW one below -- but it does not
        # draw, which is the whole point.
        self.text = text
        try:
            _center_top_groupbox()
        except Exception:
            pass
        if getattr(self, "bar", None):
            self.bar.draw()


# Indices into `colors`, the ACTIVE theme palette, not colorsW. colorsW is
# the static doom-one set baked into this file, so every mode badge stayed
# doom-one blue/orange/purple on all 22 themes while the rest of the bar
# retinted around it. The index semantics line up between the two lists --
# 3 red, 4 green, 5 orange/yellow, 6 blue, 7 purple, 8 cyan/bright -- so the
# hue each mode was chosen for survives the move.
CHORD_CHIP_COLORS = {
    "Resize-Mode": colors[5],  # orange
    "Rofi-Mode": colors[6],  # blue
    "Media-Mode": colors[8],  # cyan
    "Scratch-Mode": colors[8],
    "Draw-Mode": colors[3],
    "Hint-Mode": colors[7],
    "Lang-Switch": colors[1],
    "CheatSheet-Mode": colors[3],
    "WallpaperPicker": colors[3],
    "PASSTHROUGH": colors[8],
    "PASSTHROUGH-CONFIRM": colors[1],  # urgent/warm -- it is asking to quit
    "Wifi-Mode": colors[6],
    "Wifi-QR": colors[6],
    "Bluetooth-Mode": colors[6],
    # Purple, so audio reads as its own mode beside the blue radios.
    "Audio-Mode": colors[7],
    "Display-Mode": colors[6],
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
# True only for the brief window between startup_complete and the end of the
# restore passes. _override_match_from_saved consults it; see the comment on
# _finish_window_group_restore() for why honouring the saved map after that
# point actively teleports NEW windows to the wrong group.
_RESTORE_ARMED = False
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

    Remapping the Caps Lock keycode to Alt_L only changes what keysym it
    produces going forward -- it does not un-latch the X server's Lock
    modifier if Caps Lock was pressed even once before this reapply ran
    (e.g. in the brief window at session start while the key was still
    bound to real Caps_Lock under the default keymap). Left alone that
    stays stuck "on" indefinitely, since no key produces the Caps_Lock
    keysym any more to toggle it back off -- every letter then types
    capitalised everywhere, in every app, for the rest of the session.
    So after reapplying the remap, also check whether Lock is stuck on
    and clear it: `xdotool key Caps_Lock` can synthesize that keysym via
    a throwaway keycode even though nothing is statically bound to it,
    which is exactly what toggles the latch back off.
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
        subprocess.Popen(
            ["sh", "-c",
             "xset q | grep -qE 'Caps Lock:\\s+on\\b' && "
             "xdotool key Caps_Lock"],
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


def _finish_window_group_restore():
    """Disarm the saved map, and drop every entry that is not a live window.

    THE SAVED MAP IS A RESTORE MECHANISM, NOT LIVE BOOKKEEPING, and leaving
    it armed afterwards is a bug with a long fuse. It is loaded off disk
    holding the PREVIOUS session's wids. The restore passes hand the windows
    that came back to their groups; every remaining entry belongs to a window
    that did not come back, and client_killed cannot clear those -- that hook
    only ever fires for windows alive in THIS session.

    So they sit in the map forever, armed. X11 recycles window ids, so the
    moment a brand-new window is handed a dead one's number,
    _override_match_from_saved teleports it -- 50ms after it maps, silently,
    to a group chosen by a window that no longer exists.

    Reproduced exactly: current group 4, a docs viewer opened and closed to
    free its wid, that wid armed to group "9", the next viewer handed the
    same wid -- and it opened on 9. The documentation viewer is the worst
    affected because it is opened and closed constantly and so churns the
    same recycled range, but nothing about this is specific to it.

    Pruning alone would not be enough either: _track_window_group keeps
    refilling the map for live windows (that is what gets saved on exit), and
    those wids are just as reusable. The map must stop being CONSULTED for
    new windows once the restore is over, which is what the flag does.
    """
    global _RESTORE_ARMED
    _RESTORE_ARMED = False
    try:
        for wid_str in [k for k in _RESTORED_WIN_MAP if int(k) not in qtile.windows_map]:
            _RESTORED_WIN_MAP.pop(wid_str, None)
    except Exception:
        pass


@hook.subscribe.startup_complete
def _init_window_group_state():
    global _RESTORE_ARMED
    _veil_stage(0.80, "Restoring windows")
    _load_window_group_state()
    _RESTORE_ARMED = True
    qtile.call_later(_RESTORE_PASS_1, _restore_window_group_state)
    qtile.call_later(_RESTORE_PASS_2, _restore_window_group_state)
    # Margin over PASS_2 so a window still being adopted as that pass runs is
    # covered; after this, new windows are genuinely new and belong wherever
    # you opened them.
    qtile.call_later(_RESTORE_PASS_2 + 1.0, _finish_window_group_restore)
    qtile.call_later(_VEIL_SIGNAL_DELAY, _veil_signal_done)


@hook.subscribe.client_new
def _override_match_from_saved(client):
    # Only while the restore is in flight -- see _finish_window_group_restore.
    if not _RESTORE_ARMED:
        return
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


# Was 0.62 x 0.55, which on this 1366x768 panel is 847x422 -- and the file
# LIST inside it got maybe a third of that, because the chooser spends the
# rest on the name field, the shortcut sidebar, the path bar and the
# button row. Picking a download folder meant scrolling a six-row viewport.
#
# The height matters more than the width here: the sidebar is a fixed column,
# so every pixel of height goes to the list, while extra width mostly
# stretches the (already legible) filename column. Hence H is raised
# proportionally further than W.
FILE_CHOOSER_W_RATIO = 0.74
FILE_CHOOSER_H_RATIO = 0.74
FILE_CHOOSER_W_MIN = 820
FILE_CHOOSER_H_MIN = 480

# Documentation viewer (rofi_docs opens README/TROUBLESHOOTING/nvim in
# `kitty --class docs-view`). Larger than the file chooser because it holds
# prose and code, but still inset so the desktop stays visible behind it --
# reading a doc should not feel like leaving what you were doing.
DOCS_W_RATIO = 0.78
DOCS_H_RATIO = 0.80
DOCS_W_MIN = 720
DOCS_H_MIN = 420


@hook.subscribe.client_managed
def _float_and_center_docs(client):
    """Centre the documentation viewer.

    float_rules already carries Match(wm_class="docs-view"), so it floats
    on its own -- but a floating terminal maps wherever the WM last felt
    like putting it, which for a doc you opened deliberately is usually
    half off-screen. Same shrink-and-centre approach as the file chooser
    above."""
    try:
        if (client.window.get_wm_class() or ("", ""))[0] != "docs-view":
            return
    except Exception:
        return
    try:
        group = getattr(client, "group", None)
        screen = group.screen if group and group.screen else None
        if screen is None:
            return
        w = max(DOCS_W_MIN, int(screen.width * DOCS_W_RATIO))
        h = max(DOCS_H_MIN, int(screen.height * DOCS_H_RATIO))
        # Never wider or taller than the screen: DOCS_*_MIN would otherwise
        # push the window off a small panel, which is the exact machine
        # this repo was tuned on.
        w = min(w, screen.width)
        h = min(h, screen.height)
        client._enablefloating(
            x=screen.x + (screen.width - w) // 2,
            y=screen.y + (screen.height - h) // 2,
            w=w,
            h=h,
        )
        client.bring_to_front()
    except Exception:
        pass


def _is_gtk_file_chooser(client):
    """GTK sets WM_WINDOW_ROLE to this for its file open/save dialog,
    regardless of which app spawned it (browsers, file managers, ...) --
    so matching on role here covers Brave/Chromium/Nautilus-style pickers
    alike without one Match per application."""
    try:
        return (client.window.get_wm_window_role() or "") == "GtkFileChooserDialog"
    except Exception:
        return False


@hook.subscribe.client_managed
def _float_and_center_file_chooser(client):
    """GTK file-open/save dialogs (e.g. a browser's download-to/save-as
    picker) already float -- they carry wm_type=dialog, which is in
    default_float_rules -- but they map at a large, off-centre size that
    covers most of the browser behind them. Shrink and centre them, same
    approach as _float_and_center_sum above."""
    if not _is_gtk_file_chooser(client):
        return
    try:
        group = getattr(client, "group", None)
        screen = group.screen if group and group.screen else None
        if screen is None:
            return
        w = max(FILE_CHOOSER_W_MIN, int(screen.width * FILE_CHOOSER_W_RATIO))
        h = max(FILE_CHOOSER_H_MIN, int(screen.height * FILE_CHOOSER_H_RATIO))
        # Never larger than the screen. The docs viewer has carried this clamp
        # since it was written; the chooser did not, and raising the minimums
        # is exactly what makes it reachable -- on a panel narrower than
        # FILE_CHOOSER_W_MIN the dialog would hang off the edge, taking its
        # Cancel/Save buttons with it.
        w = min(w, screen.width)
        h = min(h, screen.height)
        client._enablefloating(
            x=screen.x + (screen.width - w) // 2,
            y=screen.y + (screen.height - h) // 2,
            w=w,
            h=h,
        )
        client.bring_to_front()
    except Exception:
        pass


# pinentry -- the master-password prompt rbw pops for Mod+p p.
#
# It maps as _NET_WM_WINDOW_TYPE_NORMAL, not DIALOG (read off a live
# window with xprop, not assumed), so nothing in default_float_rules
# catches it and qtile tiled it into the layout like an ordinary app. A
# password prompt that rearranges your windows -- and that you can tab
# into by accident -- is the wrong shape for what it is.
#
# Matched on the class prefix rather than an exact name because the
# binary varies by flavour: pinentry-gtk here, with -gnome3 and -qt as
# drop-in alternatives (TROUBLESHOOTING suggests switching if the GTK one
# misbehaves under qtile).
#
# 480x300 against its natural 531x354 -- smaller, but not so small that
# GTK clips the entry field or the OK/Cancel row.
PINENTRY_W = 480
PINENTRY_H = 300


def _is_pinentry(client):
    try:
        return any(
            c and c.lower().startswith("pinentry")
            for c in (client.get_wm_class() or ())
        )
    except Exception:
        return False


@hook.subscribe.client_managed
def _float_and_center_pinentry(client):
    """Float the password prompt, centred and compact."""
    if not _is_pinentry(client):
        return
    try:
        group = getattr(client, "group", None)
        screen = group.screen if group and group.screen else None
        if screen is None:
            screen = getattr(qtile, "current_screen", None)
        if screen is None:
            return
        w = min(PINENTRY_W, screen.width)
        h = min(PINENTRY_H, screen.height)
        client._enablefloating(
            x=screen.x + (screen.width - w) // 2,
            y=screen.y + (screen.height - h) // 2,
            w=w,
            h=h,
        )
        client.bring_to_front()
        # Focus it explicitly -- you are about to type a password into
        # it. warp=False keeps the pointer where it was, as everywhere
        # else in this config.
        if group is not None:
            try:
                group.focus(client, warp=False)
            except Exception:
                pass
    except Exception:
        pass


# Reading/writing apps -- LibreOffice and the document readers. They are
# assigned to group 8 (see `groups`) and opening one takes you there.
#
# Every value is the REAL WM_CLASS, read off a live window rather than
# guessed: the libreoffice-* names are what its .desktop files declare as
# StartupWMClass, and okular/zathura were launched and inspected because they
# declare none. zathura in particular is "org.pwmt.zathura", not "zathura",
# which is the sort of thing a plausible guess gets wrong silently -- the app
# just keeps opening on whatever group you happened to be on.
#
# qtile's Match(wm_class=...) tests the instance AND the class, so one entry
# covers both halves of a WM_CLASS pair.
DOCUMENT_APP_CLASSES = [
    "libreoffice-writer",
    "libreoffice-calc",
    "libreoffice-impress",
    "libreoffice-draw",
    "libreoffice-base",
    "libreoffice-math",
    "libreoffice-startcenter",
    "soffice",  # the instance name every LibreOffice window also carries
    "okular",
    "org.pwmt.zathura",
]
_DOCUMENT_APP_CLASS_SET = {c.lower() for c in DOCUMENT_APP_CLASSES}


def _is_document_app(client):
    try:
        return bool(
            {c.lower() for c in (client.get_wm_class() or ()) if c}
            & _DOCUMENT_APP_CLASS_SET
        )
    except Exception:
        return False


def _is_secondary_window(client):
    """A dialog, splash or transient -- not the window an app IS.

    LibreOffice is the reason this exists. Launching Writer maps the document
    window first and then, a second later, a "Tip of the Day" dialog
    (wm_class soffice/Soffice, so it matches DOCUMENT_APP_CLASSES too). The
    focus hook fired for both, and the second one won -- so you arrived on
    group 8 looking at a tip box instead of your document. Same shape as any
    splash or progress window an app puts up while it loads.

    Type and transient_for both, because toolkits are inconsistent about
    which they set -- a dialog normally carries WM_TRANSIENT_FOR back to its
    parent, a bare splash usually only sets the type, and either alone would
    miss half the cases. Checked against the live window list: every ordinary
    window classifies False and qdrop's dropdown classifies True.
    """
    try:
        if (client.window.get_wm_type() or "normal") != "normal":
            return True
    except Exception:
        pass
    try:
        return bool(client.window.get_wm_transient_for())
    except Exception:
        return False


@hook.subscribe.client_managed
def _focus_document_app(client):
    """Opening a document app takes you to it.

    The Match entries on group 8 only decide WHERE the window lands; they do
    not move you. Without this, opening a PDF from a browser or a file manager
    put okular on another group and left you looking at the window you started
    from, with no sign anything had happened.

    Both halves of the ask fall out of the same two calls: toscreen() is a
    no-op when group 8 is already current, so being there already just means
    the focus() runs -- which is the "focus the app that opened" case.

    warp=False deliberately: the pointer stays where it is. Warping it to the
    new window is what makes a group switch feel like it grabbed the mouse out
    of your hand, and this config disables cursor warping everywhere else too.
    """
    if not _is_document_app(client) or _is_secondary_window(client):
        return
    try:
        group = getattr(client, "group", None)
        if group is None:
            return

        # Remember where the jump came FROM, so closing the document can
        # put you back (see _return_from_document_group). Only recorded
        # when this actually changes group: opening a second PDF while
        # already on 8 must not overwrite the origin with "8" itself.
        global _DOCUMENT_RETURN_GROUP
        current = getattr(qtile, "current_group", None)
        if current is not None and current.name != group.name:
            _DOCUMENT_RETURN_GROUP = current.name

        try:
            _DOCUMENT_APP_WIDS.add(client.window.wid)
        except Exception:
            pass

        group.toscreen()
        group.focus(client, warp=False)
        client.bring_to_front()
    except Exception:
        pass


# Group the document jump came from. None means "we never jumped", in
# which case closing a document must not move you anywhere.
_DOCUMENT_RETURN_GROUP = None

# Window ids of the document windows we sent to the document group.
#
# client_killed cannot ask X what class a window had -- the window is
# already gone, so get_wm_class() raises and _is_document_app() would
# answer False for every window it is handed. Recording the ids on the
# way in is what makes the close side of this work at all.
_DOCUMENT_APP_WIDS = set()


@hook.subscribe.client_killed
def _return_from_document_group(client):
    """Closing the last document window returns you where you came from.

    The counterpart to _focus_document_app. Opening a PDF or a Writer
    document moves you to the document group; without this you were then
    stranded there staring at an empty group, and had to navigate back by
    hand every single time.

    Two deliberate restrictions. It fires only when the LAST document
    window goes away -- closing one of three open PDFs should leave you
    reading the other two. And it fires only while you are still on the
    document group, so closing a background document never yanks the
    group out from under whatever you moved on to.
    """
    global _DOCUMENT_RETURN_GROUP
    try:
        wid = client.window.wid
    except Exception:
        return

    if wid not in _DOCUMENT_APP_WIDS:
        return
    _DOCUMENT_APP_WIDS.discard(wid)

    if _DOCUMENT_RETURN_GROUP is None:
        return

    try:
        group = getattr(client, "group", None)
        if group is None:
            return

        # This hook can fire before the window leaves group.windows, so
        # exclude it by id rather than trusting the list to be current.
        for w in group.windows:
            try:
                other = w.window.wid
            except Exception:
                continue
            if other != wid and other in _DOCUMENT_APP_WIDS:
                return  # another document is still open here

        current = getattr(qtile, "current_group", None)
        target_name = _DOCUMENT_RETURN_GROUP
        _DOCUMENT_RETURN_GROUP = None

        if current is None or current.name != group.name:
            return  # you already navigated away; leave you where you are

        target = qtile.groups_map.get(target_name)
        if target is not None:
            target.toscreen()
    except Exception:
        pass


@hook.subscribe.client_managed
def _keep_qdrop_floating(client):
    """Force qdrop out of the tiling layout.

    floating_layout already carries Match(wm_class="qdrop") and it does
    match -- checked against the live client, both config.floating_layout
    and the group's own clone return True. Even so, qtile has been seen
    holding qdrop at NOT_FLOATING, i.e. as an ordinary tiled client. The
    cost is not just qdrop being the wrong shape: monadtall hands it a
    column and resizes every other window on the group to make room, so
    merely having the (hidden, off-screen) qdrop daemon around rearranges
    the workspace.

    qdrop re-asserts this itself on each show, which covers the state
    being lost during its hide()+togroup()+remap dance. This hook covers
    the other window: qtile restarts (theme-apply triggers them often)
    re-manage the long-lived daemon window, and without this the layout
    would stay disturbed from the restart until the next qdrop keypress.
    """
    try:
        if "qdrop" not in (client.get_wm_class() or []):
            return
        if not client.floating:
            client.floating = True
    except Exception:
        pass


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


def _rescale_then_restart(q):
    """Re-derive the UI scale for the new display set, then restart.

    UI_SCALE is read once, at config import, from ~/.cache/qtile/ui_scale --
    and nothing wrote that file except a manual `ui-scale` run or the rofi
    picker. So docking a 1366x768 laptop to a 4K monitor restarted qtile
    (below) and rebuilt every bar at the LAPTOP's scale: a sliver of a bar
    with unreadable text on the display you just plugged in, until you
    remembered the command. Undocking had the mirror-image problem.

    A pinned scale is safe: ui-scale reads ~/.cache/qtile/ui_scale.pinned
    first and a pin always wins, so "the formula disagrees with my eyes"
    still survives a hotplug.

    Synchronous on purpose, despite being in the event loop. The file has
    to be on disk BEFORE the config re-imports, and this callback's whole
    remaining job is os.execv() -- there is nothing left to be responsive
    for. The timeout is the guard: a wedged xrandr or xrdb costs a few
    seconds of stale bar, never the restart itself, which happens either
    way.
    """
    try:
        import shutil

        exe = shutil.which("ui-scale") or os.path.expanduser(
            "~/.dotfiles/.config/AtiScriptsV1/ui-scale"
        )
        if os.path.exists(exe):
            subprocess.run(
                [exe],
                timeout=8,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except Exception:
        # Never let a scale probe cost the restart -- a bar at the old
        # scale beats a second screen with no bar at all.
        pass
    _smooth_restart(q)


@hook.subscribe.screens_reconfigured
def apply_bar_on_reconfigure():
    apply_bar_mode()
    # reconfigure_screens=True only re-lays-out the Screen objects that
    # already exist; it never creates new ones. Since `screens` is built
    # once at config-load time from the monitor count then, plugging a
    # monitor in afterwards leaves that output with no bar at all (and
    # unplugging leaves a stranded Screen). The only thing that rebuilds
    # the list is re-importing the config, i.e. a restart.
    #
    # Guarded on the count specifically: this hook also fires for plain
    # resolution/rotation changes, and restarting qtile on every one of
    # those would be far more disruptive than the bug being fixed.
    try:
        if _monitor_count() != len(qtile.screens):
            # Deferred: this hook runs inside qtile's own RandR handling,
            # and replacing the process image from in there re-enters the
            # event loop mid-teardown. A 1s tick also coalesces the burst
            # of events a single hotplug emits into one restart.
            qtile.call_later(1, lambda: _rescale_then_restart(qtile))
    except Exception:
        # Never let a failed monitor probe take the hook (and with it
        # apply_bar_mode) down -- a missing bar mode is worse than a
        # missing bar on a second screen.
        pass


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
    "w_layout": "Layout · R-click to cycle",
    "w_updates": "Pending updates · click → update manager",
    "w_cpu": "CPU load · click → mission-center",
    "w_mem": "RAM used · click → btop",
    "w_disk": "Disk free (/ + /home) · click → notify",
    "w_volume": "Volume · scroll to change",
    "w_battery": "Battery · click → status",
    "w_lang": "Keyboard layout",
    "w_clock": "Next prayer · USD/EUR rates",
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


_tooltip_widget_cache = {}


def _tooltip_widget_class(cls):
    """Cached `cls + TooltipMixin`, keeping cls's own __name__.

    Two separate bugs lived here. install_bar_tooltips() runs at least
    twice per startup and again 0.1s after every SmartWidgetBox toggle,
    and this used to mint a brand-new class object on each pass -- an
    unbounded class leak. It also renamed the class to "<X>WithTooltip",
    so on the SECOND pass the TOOLTIP_BY_CLASS lookup no longer matched
    and those widgets silently dropped out of _TOOLTIP_WIDGETS. That is
    the installed=19 / installed=14 alternation in qtile.log.
    """
    if cls not in _tooltip_widget_cache:
        new_cls = type(cls.__name__, (cls, TooltipMixin), {})
        new_cls.__qualname__ = f"{cls.__name__}WithTooltip"
        _tooltip_widget_cache[cls] = new_cls
    return _tooltip_widget_cache[cls]


def _install_tooltip(widget_, text):
    if not text:
        return
    # An unconfigured widget has no .bar/.drawer, so touching it later
    # (calculate_length, _show_tooltip) raises. It also should not be in
    # a bar at all -- see _SafeLengthMixin.
    if not getattr(widget_, "configured", False):
        return
    cls = widget_.__class__
    if not issubclass(cls, TooltipMixin):
        new_cls = _tooltip_widget_class(cls)
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

            # Opt-in centring (w_clock: prayer line over the FX lines).
            # Popup fixes its alignment once, in __init__, from
            # text_alignment="left" -- so it has to be re-set on the pango
            # layout here. Alignment is also a no-op while the layout width
            # is -1 (each line just starts at x=0), hence: measure the
            # natural width first, then pin the layout to it so the short
            # lines have a box to centre inside.
            if getattr(_w, "tooltip_center", False):
                tt.layout.reset_width()
                text_w = tt.layout.width
                tt.layout.layout.set_alignment(pangocffi.ALIGN_CENTER)
                tt.layout.width = text_w

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
                            w.tooltip_center = True
                            _make_tooltip_dynamic(
                                w, _clock_tooltip_text, "No prayer data"
                            )
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
    # debug, not warning: this is a routine tally, not a problem. Nothing is
    # wrong with installed < total -- only the widgets we define tooltips for
    # get one, so 20/33 is the expected steady state. Real failures already
    # log a warning of their own ("tooltip install failed for ...") a few
    # lines up. At warning level this fired on every start AND every reload,
    # and install_bar_tooltips() is scheduled twice at startup, so it was
    # four lines of noise a session that always said the same thing.
    logger.debug(f"[tooltips] installed={installed} total={total}")


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


_TOOLTIP_TEXT_CACHE = {}


def _make_tooltip_dynamic(widget_, text_func, fallback=""):
    """Resolve a tooltip's text WITHOUT blocking the event loop.

    mouse_enter is dispatched straight from qtile's asyncio loop, and
    every one of these text_funcs shells out with a blocking
    subprocess.run -- so hovering a chip froze the whole WM (keyboard,
    focus, bar, everything) for as long as the command took:

        w_clock  _clock_tooltip_text-> prayer_next.sh + fx_rates.sh, timeout=8
        w_disk   _disk_parts_text   -> _sh(timeout=1.5)
        w_cpu    _cpu_top_text      -> _sh(timeout=1.5)
        w_mem    _mem_top_text      -> _sh(timeout=1.5)
        w_mpris  _player_title_text -> 2x playerctl @ 0.5s

    The clock is the worst and the least obvious. Measured,
    prayer_next.sh returns in ~44ms while ~/.cache/qtile_prayer.json is
    same-day -- but the first hover after midnight takes the refresh
    branch and runs `curl --max-time 6`. That was a hard 6-8s freeze of
    the window manager, once a day, caused by hovering the clock.

    Now: show the last known value instantly (or the fallback on the very
    first hover), compute the fresh one in a worker thread, and hand the
    result back to the loop via call_soon_threadsafe. A per-widget
    in-flight guard keeps repeated hovers from stacking threads. Nothing
    here blocks, so the worst case is a tooltip one hover stale rather
    than an unresponsive desktop.
    """
    _orig_enter = widget_.mouse_enter
    key = id(widget_)

    def _dyn_enter(x, y, _w=widget_, _fn=text_func, _fb=fallback, _orig=_orig_enter):
        cached = _TOOLTIP_TEXT_CACHE.get(key)
        _w.tooltip_text = cached if cached else _fb
        _orig(x, y)

        if getattr(_w, "_tooltip_refreshing", False):
            return
        _w._tooltip_refreshing = True

        def _work():
            try:
                text = (_fn() or "").strip() or _fb
            except Exception:
                text = _fb

            def _publish():
                _w._tooltip_refreshing = False
                _TOOLTIP_TEXT_CACHE[key] = text
                _w.tooltip_text = text
                # Only repaint if the tooltip is still on screen -- the
                # pointer may well have moved on by now.
                tt = getattr(_w, "_tooltip", None)
                if tt is None:
                    return
                try:
                    tt.layout.text = text
                    tt.width = tt.layout.width + 2 * tt.horizontal_padding
                    tt.height = tt.layout.height + 2 * tt.vertical_padding
                    tt.place()
                    tt.clear()
                    tt.draw_text()
                    tt.draw()
                except Exception:
                    pass

            try:
                qtile.call_soon_threadsafe(_publish)
            except Exception:
                _w._tooltip_refreshing = False

        threading.Thread(target=_work, daemon=True).start()

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


def open_docs(qtile):
    # Left-clicking the logo used to open a terminal -- which Mod+Return
    # and several other bindings already do. A desktop with 79 documented
    # keybindings, 22 themes and a dozen custom tools has a discovery
    # problem, not a terminal-launching problem, so the most prominent
    # click in the bar now answers "what can this thing do".
    set_icon_temporarily(qtile, "󰋗", "rofi_docs")


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
# 6- Hint-Mode deliberately launches nothing on entry
# --------------------------------------------------------------
# The old Mouse-Mode spawned `warpd --normal` from an enter_chord hook, which
# could not stay: warpd grabbed the keyboard the moment it started, so h/s/f
# never reached qtile and the chord looked dead. warpd itself is gone now --
# it segfaulted in x_input_wait on every boot, so its `n`/`w` bindings had
# been dead for a while without anyone noticing. Homerow covers the same
# ground (h hint, s scroll, f search, v caret) and does not grab the keyboard.


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


# Entering CheatSheet-Mode always shows the qtile sheet. That is right when
# the chord is entered from the keyboard, and wrong when rofi_docs asked
# specifically for the vim or fish one -- the qtile sheet would flash up
# first and then be replaced. This flag lets open_cheatsheet() suppress the
# auto-show for exactly one chord entry.
_SUPPRESS_CHEATSHEET_AUTOSHOW = False


@hook.subscribe.enter_chord
def auto_enable_cheatsheet(chord_name):
    global _SUPPRESS_CHEATSHEET_AUTOSHOW
    if chord_name != "CheatSheet-Mode":
        return
    if _SUPPRESS_CHEATSHEET_AUTOSHOW:
        _SUPPRESS_CHEATSHEET_AUTOSHOW = False
        return
    show_qtile_cheatsheet(qtile)


def _find_chord(name, mappings=None):
    """Find a KeyChord by name, at ANY depth.

    Not every chord is top-level: WallpaperPicker is nested under Rofi-Mode
    (mod+p, then b), so the flat scan over `keys` that this function replaces
    would walk straight past it and report the chord as missing.
    """
    for k in (keys if mappings is None else mappings):
        if isinstance(k, KeyChord):
            if getattr(k, "name", "") == name:
                return k
            found = _find_chord(name, k.submappings)
            if found is not None:
                return found
    return None


def open_cheatsheet(which="qtile"):
    """Open a cheatsheet from outside qtile (rofi_docs calls this over IPC).

    Replaying the key chord with xdotool -- the obvious approach -- cannot
    work here, and failed in three distinct ways:

      * `super+shift+k` then `k` entered the chord (which auto-shows the
        qtile sheet) and then the `k` TOGGLED it back off, so the sheet
        appeared for a frame and vanished.
      * for vim and fish the qtile sheet showed first and was then
        replaced, which looked like a glitch.
      * xdotool races rofi's keyboard grab, so it was timing-dependent.

    Entering the chord properly instead means the sheet is dismissed the
    same way it always was -- Esc or q -- rather than needing its own
    close path.
    """
    global _SUPPRESS_CHEATSHEET_AUTOSHOW

    chord = _find_chord("CheatSheet-Mode")
    if chord is None:
        return "no CheatSheet-Mode chord in config"

    # Suppress the auto-show unless the qtile sheet is what was asked for.
    _SUPPRESS_CHEATSHEET_AUTOSHOW = which != "qtile"
    qtile.grab_chord(chord)

    if which == "vim":
        toggle_vim_cheatsheet(qtile)
    elif which == "fish":
        toggle_fish_kitty_cheatsheet(qtile)
    return "ok"


def _close_other_cheatsheets(keep):
    """Close every cheatsheet except `keep`.

    auto_enable_cheatsheet() shows the qtile sheet on every chord entry,
    unconditionally. Pressing v or f used to just toggle_*_cheatsheet() on
    top of that -- which opened the new sheet without closing the qtile
    one still sitting underneath it. Both stayed "open" as far as
    is_open() was concerned, and since page/scroll_cheatsheet() check
    (Qtile, Vim, Fish) in that order and act on the first match, j/k/Tab
    kept driving the invisible qtile sheet no matter which one was on
    screen. Only close_*_cheatsheet() actually closes a sheet -- this is
    what open_vim_cheatsheet()/open_fish_cheatsheet() call before opening
    theirs, so the "one sheet open at a time" every other function here
    assumes is actually true.
    """
    for sheet, closer in (
        (QtileCheatsheet, close_qtile_cheatsheet),
        (VimCheatsheet, close_vim_cheatsheet),
        (FishCheatsheet, close_fish_kitty_cheatsheet),
    ):
        if sheet is not keep and sheet.is_open():
            closer()


def open_vim_cheatsheet(qtile):
    """v inside CheatSheet-Mode: switch to the vim sheet, closing whatever
    else is open first. If vim is already the one open, this is a toggle
    (closes it) same as before."""
    if not VimCheatsheet.is_open():
        _close_other_cheatsheets(VimCheatsheet)
    toggle_vim_cheatsheet(qtile)


def open_fish_cheatsheet(qtile):
    """f inside CheatSheet-Mode: same as open_vim_cheatsheet() but fish."""
    if not FishCheatsheet.is_open():
        _close_other_cheatsheets(FishCheatsheet)
    toggle_fish_kitty_cheatsheet(qtile)


def page_cheatsheet(qtile, step=1):
    """Tab inside CheatSheet-Mode: move a screenful in whichever sheet is on
    screen. Only one sheet is ever open at a time (k / v / f each toggle
    their own, and leaving the chord closes all three), so "the open one"
    is unambiguous. Does nothing when nothing is open.
    """
    for sheet in (QtileCheatsheet, VimCheatsheet, FishCheatsheet):
        if sheet.is_open():
            sheet.next_page(qtile, step)
            return


def scroll_cheatsheet(qtile):
    """j inside CheatSheet-Mode: scroll whichever sheet is on screen down by
    its default step. Does nothing when nothing is open."""
    for sheet in (QtileCheatsheet, VimCheatsheet, FishCheatsheet):
        if sheet.is_open():
            sheet.scroll(qtile)
            return


def cheatsheet_k(qtile):
    """k inside CheatSheet-Mode is overloaded: with nothing open it opens
    the qtile sheet (its original job); with a sheet already open, k is
    vim's "up", so it scrolls up instead of re-toggling the sheet closed."""
    for sheet in (QtileCheatsheet, VimCheatsheet, FishCheatsheet):
        if sheet.is_open():
            sheet.scroll(qtile, rows=-sheet.SCROLL_ROWS)
            return
    toggle_cheatsheet(qtile)


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
        # Icon first, THEN build the popup. show_wallpaper_picker() loads
        # every wallpaper in the directory and lays out 3 columns of
        # PopupText controls before it returns -- measured well over a
        # second with a few hundred wallpapers -- so doing it before the
        # toggle meant the chip sat on its closed icon for that whole
        # stretch after the chord had already opened. The toggle itself is
        # just a state flip + one redraw, so flipping it first makes the
        # icon land the instant you enter the chord, not after the popup
        # finishes building.
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and not w.box_is_open:
            w.toggle()
        show_wallpaper_picker(qtile)


def close_wallpaper_mode(qtile):
    close_wallpaper_picker()
    # ungrab_chord() only pops the innermost level and re-grabs whatever
    # chord is beneath it -- correct for a keyboard "back" inside a nested
    # menu, but WallpaperPicker is nested under Rofi-Mode (mod+p, then b),
    # so that left qtile silently re-grabbed into Rofi-Mode's keymap with
    # no visible indicator. The chip's next click assumed a clean root
    # state and replayed [mod]+p then b to re-enter -- [mod]+p is not
    # bound inside Rofi-Mode's own keymap (only bare "p" is, for
    # rofi-pass), so it was swallowed and the reopen relied on "b" alone,
    # which only works if nothing else consumed the chord state first.
    # ungrab_all_chords() drops the whole stack back to root bindings, so
    # a chip click is always a real, independent toggle.
    qtile.ungrab_all_chords()

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
        # THIS CHIP WAS OPENING THE BLUETOOTH POPUP. It entered the chord by
        # replaying mod+p then "b" as fake keypresses, and under Rofi-Mode
        # "b" is Bluetooth-Mode -- the wallpaper picker is "w". Whichever way
        # round it once was, a hardcoded key replay cannot survive the keymap
        # being rearranged, and it silently opened the wrong popup instead of
        # failing.
        #
        # open_wallpaper_picker() grabs the chord OBJECT, found by name, so
        # there is no key to get wrong and no round trip through the X server
        # to race. That also retires the reason the icon was flipped early
        # here: grab_chord() fires enter_chord synchronously, so
        # auto_enable_wallpaper_picker() flips the chip before this returns.
        open_wallpaper_picker()


def open_wallpaper_picker():
    """Open the wallpaper picker from outside qtile (rofi_docs calls this
    over IPC), the same way open_cheatsheet() opens a sheet.

    NOT toggle_wallpaper_picker(): that enters the chord with
    simulate_keypress([mod], "p") then "b", which feeds fake events back
    through the X server. The caller here is a rofi menu that is holding a
    keyboard grab as it exits, which is the exact race open_cheatsheet()
    documents xdotool losing. grab_chord() installs the keymap directly, with
    no round trip and nothing to race.

    Entering the chord is also what makes the picker usable rather than just
    visible: /, hjkl, r and Enter are the chord's own keys, and
    auto_enable_wallpaper_picker() fires off enter_chord to build the popup
    and flip the bar chip. Calling show_wallpaper_picker() alone would put a
    picker on screen that no key could drive.
    """
    chord = _find_chord("WallpaperPicker")
    if chord is None:
        return "no WallpaperPicker chord in config"
    SmartWidgetBox.close_all()
    qtile.grab_chord(chord)
    return "ok"


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
        # Icon first, same reasoning as auto_enable_wallpaper_picker above:
        # don't make the chip's redraw wait behind the picker's own
        # teardown work.
        w = qtile.widgets_map.get("wallpaper_toggle")
        if w and w.box_is_open:
            w.toggle()
        close_wallpaper_picker()

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

    elif ACTIVE_CHORD == "Bluetooth-Mode":
        # close() also stops the discovery child process -- leaving the chord
        # without it would keep the radio scanning indefinitely.
        BluetoothPopup.close(qtile)

    elif ACTIVE_CHORD == "Audio-Mode":
        AudioPopup.close(qtile)

    elif ACTIVE_CHORD == "Display-Mode":
        # close() also reverts a change still inside its confirmation
        # countdown -- leaving the chord must never strand a layout that
        # nobody has confirmed is visible.
        DisplayPopup.close(qtile)

    elif ACTIVE_CHORD == "Wifi-Mode":
        WifiPopup.close(qtile)
        # `s` can put the QR popup on top of the picker without a chord of
        # its own (Wifi-Mode already owns Escape), so leaving this chord has
        # to take both down or the QR is left stranded with no way to close.
        WifiQR.close(qtile)

    elif ACTIVE_CHORD == WifiQR.CHORD_NAME:
        # The QR popup grabs an Escape-only chord while it is up (it is
        # opened by a bar click, so nothing else routes keys to it).
        # KeyChord appends its own bare Escape over any binding, so this
        # hook -- not a Key command -- is what actually closes it.
        WifiQR.on_chord_left()

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
            setattr(deco, "colour", CHORD_CHIP_COLORS.get(chord_name, DEFAULT_CHIP_COLOR))

    if w.bar:
        w.bar.draw()


@hook.subscribe.leave_chord
def chord_chip_leave():
    w = qtile.widgets_map.get("chord_chip")
    if not w:
        return

    for deco in w.decorations:
        if isinstance(deco, RectDecoration):
            setattr(deco, "colour", DEFAULT_CHIP_COLOR)

    w.bar.draw()


# ----------------------------------------------------------------
# 12.5- On chord enter: close any open SmartWidgetBox and remember
#       which ones were open. On chord leave: reopen exactly those.
# ----------------------------------------------------------------

_SAVED_WIDGETBOX_NAMES = []


_CHORD_OWNED_WIDGETBOXES = {"wallpaper_toggle"}


def _all_smart_widgetboxes():
    """SmartWidgetBoxes eligible for the generic hide-while-in-a-chord
    treatment below.

    Excludes "wallpaper_toggle": that chip's open/closed icon is not an
    independent user-toggled panel -- it *is* the WallpaperPicker chord's
    own state, driven directly by auto_enable_wallpaper_picker (entry) and
    cleanup_on_leave (exit). Left in this list, entering ANY chord
    (including WallpaperPicker's own entry, since this hook has no name
    filter) closed it back out the instant those functions opened it, and
    leaving the chord then reopened it 50ms later via
    restore_widgetboxes_on_chord_leave -- exactly backwards from the real
    state, which is why the chip's icon never seemed to track open/close.
    """
    seen = set()
    for screen in qtile.screens:
        for pos in ("top", "bottom", "left", "right"):
            b = getattr(screen, pos, None)
            if not b:
                continue
            for w in b.widgets:
                # isinstance, not a __name__ string compare: chip() builds
                # a subclass, so the clickable boxes (tooltip_widgetbox,
                # wallpaper_toggle) never matched by name and were only
                # ever found via the registry fallback below.
                if (
                    isinstance(w, SmartWidgetBox)
                    and id(w) not in seen
                    and getattr(w, "name", None) not in _CHORD_OWNED_WIDGETBOXES
                ):
                    seen.add(id(w))
                    yield w
    # also cover any SmartWidgetBox tracked via its own registry
    for w in list(getattr(SmartWidgetBox, "_instances", [])):
        if (
            id(w) not in seen
            and w._usable()
            and getattr(w, "name", None) not in _CHORD_OWNED_WIDGETBOXES
        ):
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


def _clamp_phone_mirror(*_args):
    """Drag the scrcpy window back on screen after the phone rotates.

    scrcpy sizes its window to the device's real framebuffer, so turning
    the phone sideways -- opening a video fullscreen, say -- makes it
    swap width and height on its own. phone_screen parks it flush against
    the right edge in portrait (~307x684 here), and the rotated window is
    then ~684 wide from the same left edge: most of it hangs off the
    screen, controls included, with no way to reach them.

    Only floating windows can be repositioned like this, and only scrcpy
    is touched: clamping every float would fight anyone deliberately
    dragging a window half off-screen.

    Stays a no-op whenever the window already fits, so it can never fight
    a window that is already where it should be.
    """
    # Every window, not qtile.current_window: the rotation happens in the
    # phone's hand, so the mirror is usually NOT the focused window when
    # it resizes itself. Keying off focus meant the clamp simply never
    # ran at the one moment it was needed.
    scr = qtile.current_screen
    margin = 8

    for group in qtile.groups:
        for win in list(group.windows):
            if not getattr(win, "floating", False):
                continue
            classes = win.get_wm_class() or []
            if not any("scrcpy" in c.lower() for c in classes):
                continue

            bw = win.borderwidth * 2
            w, h = win.width, win.height

            # MOVE ONLY -- never resize. scrcpy locks its window to the
            # device aspect ratio and re-applies that lock immediately
            # after any external resize, so setting a size here starts a
            # fight it wins: clamping a 684-wide landscape window once
            # produced a 136-wide sliver, because scrcpy kept the height
            # and pulled the width back to the portrait ratio.
            #
            # dx/dy/dwidth/dheight are what is left once the bar is
            # subtracted -- clamping to width/height tucks it under the bar.
            x = min(max(win.x, scr.dx + margin), scr.dx + scr.dwidth - w - bw - margin)
            y = min(max(win.y, scr.dy + margin), scr.dy + scr.dheight - h - bw - margin)

            if (x, y) == (win.x, win.y):
                continue
            win.set_position_floating(x, y)


# client_managed ONLY. float_change was subscribed here too, on the
# assumption it covered later rotations -- it does not. Probed directly:
# a floating window resized and moved from outside qtile fired the hook
# zero times. float_change tracks floating STATE, not geometry, so an app
# resizing its own window is invisible to it.
#
# That leaves this hook covering exactly one case: the phone is already
# sideways when the mirror opens. Rotation DURING a session is handled by
# the bounds watcher in phone_screen, which is the only thing that can
# see it.
hook.subscribe.client_managed(_clamp_phone_mirror)


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
@hook.subscribe.enter_chord
def auto_enable_bluetooth_popup(chord_name):
    if chord_name == "Bluetooth-Mode":
        BluetoothPopup.show(qtile)


# ------------------------------------------------------------------------------
# 15 - Function to lanuch the Audio popup when it's mode activated
# ------------------------------------------------------------------------------
@hook.subscribe.enter_chord
def auto_enable_audio_popup(chord_name):
    if chord_name == "Audio-Mode":
        AudioPopup.show(qtile)


@hook.subscribe.enter_chord
def auto_enable_display_popup(chord_name):
    if chord_name == "Display-Mode":
        DisplayPopup.show(qtile)

# -----------------------------------------------------------
# 16 - Function to launch WiFi popup when mode is activated
# -----------------------------------------------------------


@hook.subscribe.enter_chord
def auto_enable_wifi_popup(chord_name):
    if chord_name == "Wifi-Mode":
        # Cheap to build (no image loading, no per-file work) and it draws
        # its own "Scanning…" state, so unlike the wallpaper picker there is
        # nothing to order around a widget redraw here.
        WifiPopup.show(qtile)


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
    ]

    for s in REMOVE:
        text = text.replace(s, "")

    # The list above used to end with two GENERIC separator entries, " - "
    # and " \u2014 ", removed with str.replace -- which deletes every
    # occurrence, not just the one before an application name. So
    # "Ati's Homepage - qutebrowser" came out as "Ati's Homepagequtebrowser",
    # two words welded together, on any title containing a dash at all.
    #
    # Strip a TRAILING " - <name>" instead, and only when the tail looks like
    # an application name: no further separator inside it, and short. A real
    # subtitle ("Chapter 3 - The Long Way Home") is left alone.
    for sep in (" \u2014 ", " - "):
        head, found, tail = text.rpartition(sep)
        if found and head and len(tail) <= 25 and sep.strip() not in tail:
            text = head

    # Leading status glyph. The terminal sessions in here set their title to
    # a spinner frame plus the task -- "\u2802 Fix ...", "\u2733 Upgrade ..." --
    # and the frame changes several times a second. In a bar that is a
    # character of pure noise in the highest-value column, and it repaints
    # the widget every time it ticks. Braille block U+2800-U+28FF is the
    # spinner; the rest are the done/busy marks that replace it.
    text = text.lstrip()
    while text and (0x2800 <= ord(text[0]) <= 0x28FF or text[0] in "\u2733\u2713\u2717\u25b6\u23f8"):
        text = text[1:].lstrip()

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
            fontsize=_s(19),
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
            fontsize=_s(14),
        ),
        widget.LaunchBar(
            progs=[
                ("", "brave", "Brave Browser"),
                ("", "qutebrowser", "Qutebrowser"),
                ("", "kitty", "Kitty Terminal"),
                ("", "pcmanfm-qt", "File Manager"),
                ("󰨞", "code", "VS Code"),
            ],
            # The first field of each tuple is a NERD FONT GLYPH, not an app
            # name -- so LaunchBar's icon lookup was always going to miss,
            # fall back to text mode, and log a warning while doing exactly
            # what we wanted. 105 lines of
            #     No icon found for application "󰨞" (None) switch to text mode
            # per boot, all of them noise hiding the warnings that matter.
            # text_only says the quiet part out loud and skips the lookup.
            text_only=True,
            fontsize=_s(14),
            padding=12,
            foreground=colors[1],
        ),
        widget.TextBox(
            name="screenshot_chip_nu",
            text="󰹑",
            fontsize=_s(16),
            padding=10,
            foreground=colors[1],
            mouse_callbacks={
                "Button1": lazy.spawn(SCREENSHOT_AREA_CMD),
            },
        ),
        ewidget.Spacer(length=bar.STRETCH),
        widget.GroupBox(
            fontsize=_s(12),
            margin_y=_s(2),
            margin_x=_s(8),
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
            # The five popup-backed modes show only their name here: each
            # of those popups draws its own hint bar listing the same keys,
            # and the chip repeating them just made the bar 200px wider for
            # nothing. The modes below that have no popup keep their letters
            # -- for those, this chip is the only place the keys are shown.
            name_transform=lambda name: {
                "Resize-Mode": "󰩨   RESIZE : H, J, N",
                "Rofi-Mode": "󰍉   ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h ",
                "Media-Mode": "󰕾   MEDIA : J , K , M , H , L , P ",
                "Scratch-Mode": "󰈆   SCRATCH",
                "Draw-Mode": "󰏫   DRAW : w , c , z , r , v ",
                "Hint-Mode": "󰍽   HINT : h hint , s scroll , f search , v caret ",
                "Lang-Switch": "   LANG : a , e , t , d ",
                "CheatSheet-Mode": "󰆍   CHEATSHEET : k , v , f , j/k scroll , TAB , ESC ",
                "WallpaperPicker": "󰸉   WALLPAPERS",
                "PASSTHROUGH": "   PASSTHROUGH : ESC",
                "PASSTHROUGH-CONFIRM": "   EXIT PASSTHROUGH ? y , n , ESC",
                "Bluetooth-Mode": "󰂯   BLUETOOTH",
                "Audio-Mode": "󰕾   AUDIO",
                "Display-Mode": "󰍹   DISPLAY",
                "Wifi-Mode": "󰤨   WIFI",
                "Wifi-QR": "   WIFI QR : ESC to close ",
            }.get(name, name.upper()),
        ),
        # Homerow mode chip — see the matching one in right_side_widgets()
        # and homerow_mode_text() near the top of the file for why this
        # can't just reuse the Chord widget above it.
        #
        # Explicit chip_color/foreground rather than colors[N] indices:
        # colors[2] (#1c2126) landed almost exactly on DEFAULT_CHIP_COLOR
        # (#1c1f24, the chip()-wrapped widget's default background) --
        # near-black text on a near-black chip, invisible. These two are
        # picked from opposite ends of the live palette (brightest accent,
        # darkest background) specifically so that can't happen again
        # regardless of what the active theme's other slots resolve to.
        chip(
            widget.GenPollText,
            chip_color=colors[4],
            name="homerow_mode_chip_nu",
            func=homerow_mode_text,
            update_interval=0.2,
            padding=11,
            foreground=colors[0],
            background=None,
        ),
        widget.TextBox(
            text="|",
            font="Ubuntu Mono",
            foreground=colors[1],
            padding=0,
            fontsize=_s(14),
        ),
        widget.Battery(
            name="w_battery_nu",
            format="  {char}{percent:2.0%}",
            fontsize=_s(11),
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
            fontsize=_s(14),
        ),
        widget.CPU(
            name="w_cpu_nu",
            format="  {load_percent}%",
            fontsize=_s(10),
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
            fontsize=_s(14),
        ),
        widget.Memory(
            name="w_mem_nu",
            format="{MemUsed: .0f}{mm}",
            fmt="🖥  {} ",
            fontsize=_s(10),
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
            fontsize=_s(14),
        ),
        widget.Clock(
            format=" %a, %b %d - %H:%M",
            padding=14,
            fontsize=_s(11),
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
        fontsize=_s(10),
        margin_y=_s(2),
        margin_x=_s(8),
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
            fontsize=_s(15),
            padding=11,
            foreground=colors[7],
            mouse_callbacks={
                # Terminal moves to middle-click rather than being dropped:
                # muscle memory is real, and Mod+Return still does it too.
                "Button1": lazy.function(open_docs),  # left   — docs menu
                "Button2": lazy.function(open_terminal),  # middle — terminal
                "Button3": lazy.function(open_launcher),  # right  — drun
            },
        ),
        # Current Layout — original padding, text mode; right-click cycles layout
        chip(
            ewidget.CurrentLayout,
            # Explicit name so the tooltip resolves by name and the widget
            # is addressable as lazy.widget["w_layout"], rather than
            # depending on class-name derivation.
            name="w_layout",
            padding=18,
            foreground=colors[3],
            mouse_callbacks={
                "Button3": lazy.next_layout(),
            },
        ),
        # No "|" separator here. The bottom bar is built from bare widgets
        # and uses pipes to group them; this bar is built from chips, where
        # every element already carries its own rounded background. The one
        # pipe left on it was the sole flat element among them, sitting
        # between the layout chip and the tasklist and reading as a stray
        # mark rather than a divider. Chip padding does the separating.
        # task list
        widget.TaskList(
            font="JetBrainsMono Nerd Font",
            fontsize=_s(10),
            # icons
            icon_size=_s(16),
            markup=True,
            # markup styles — use the active palette so TaskList retints
            # on theme swap. colors[2]=bg-alt, colors[0]=bg, colors[6]=blue,
            # colors[5]=purple, colors[3]=red.
            # State is carried by COLOUR and WEIGHT, not by letters. Every
            # entry used to be prefixed with a private code -- "F" focused,
            # "V" floating, "VF" both -- in the one widget whose entire job is
            # showing window names, and those characters cost width the name
            # then lost to truncation. Focus already reads from the accent
            # colour and the bold; nothing needs spelling out.
            #
            # The two states that are NOT otherwise visible keep a mark, and
            # it has to live in the markup string. txt_minimized / txt_floating
            # look like the right home for it and are DEAD config the moment a
            # markup_* string is set: tasklist.py:245 returns
            # markup_str.format(name) and never interpolates `state` at all --
            # it is only used on the no-markup path below it. That is why the
            # original spelled the arrow out here too.
            #
            # The leading/trailing spaces are the padding: they sit INSIDE the
            # span, so the highlight becomes a rounded-ish block around the
            # title instead of ending flush against the first letter.
            markup_normal=f'<span background="{colors[2][0]}44" foreground="{colors[1][0]}"> {{}} </span>',
            markup_focused=f'<span background="{colors[0][0]}EE" foreground="{colors[6][0]}" weight="bold"> {{}} </span>',
            markup_floating=f'<span background="{colors[0][0]}CC" foreground="{colors[5][0]}"> 󰊔 {{}} </span>',
            markup_focused_floating=f'<span background="{colors[0][0]}EE" foreground="{colors[5][0]}" weight="bold"> 󰊔 {{}} </span>',
            markup_minimized=f'<span background="{colors[0][0]}66" foreground="{colors[3][0]}"> 󰖰 {{}} </span>',
            # 120px at fontsize 11 is about fourteen characters, which
            # truncated every real window title to "Fix Qt…" / "Upgr…" --
            # three open windows and no way to tell them apart, which is the
            # one job a tasklist has. _s() so it tracks the UI scale like
            # every other dimension here; _center_groupbox already caps the
            # widget's TOTAL width, so this only governs per-title
            # truncation and cannot push the groupbox off centre.
            # 210 let a title run most of the way to the groupbox. The point
            # of the strip is telling three windows apart, not reading the
            # whole title -- the first few words already do that, and the
            # rest just crowds the bar. Narrower, and a point smaller, so
            # more of the name survives inside the smaller box.
            max_title_width=_s(115),
            padding_x=3,
            padding_y=2,
            margin_x=_s(3),
            margin_y=_s(4),
            spacing=2,
            parse_text=parse_task_name,
            # window_name_location prepends "[n] ", the window's index within
            # its group -- and TaskList adds it BEFORE parse_text runs, which
            # is why the spinner strip in parse_task_name has to work anywhere
            # in the string rather than only at the front. Off now: it cost
            # four characters of a roughly fourteen character budget, nearly a
            # third of the visible width, to say something the app icon beside
            # it already distinguishes, and nothing here binds a window by
            # that index.
            window_name_location=False,
            foreground=colors[1],
            background=None,
            highlight_method="text",
            border=colors[7],
            borderwidth=0,
            # Kept only for the no-markup fallback path; see the note above
            # the markup_* block for why these are otherwise inert.
            txt_minimized="󰖰 ",
            txt_floating="󰊔 ",
            txt_maximized="",
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
            FittedChord,
            name="chord_chip",
            fmt=" {} ",
            padding=11,
            # The theme's BACKGROUND colour as the text colour: the chip
            # behind it is a theme accent, so bg-on-accent is legible by
            # construction on light and dark palettes alike. colors[2] was a
            # hardcoded #000000, which only worked because every theme here
            # happened to be dark -- on mono-light it is black text on a dark
            # accent.
            foreground=colors[0],
            background=None,
            name_transform=lambda name: {
                "Resize-Mode": "󰩨   RESIZE : H, J, N",
                "Rofi-Mode": "󰍉   ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h ",
                "Media-Mode": "󰕾   MEDIA : J , K , M , H , L , P ",
                "Scratch-Mode": "󰈆   SCRATCH",
                "Draw-Mode": "󰏫   DRAW : w , c , z , r , v ",
                "Hint-Mode": "󰍽   HINT : h hint , s scroll , f search , v caret ",
                "Lang-Switch": "   LANG : a , e , t , d ",
                "CheatSheet-Mode": "󰆍   CHEATSHEET : k , v , f , j/k scroll , TAB , ESC ",
                "WallpaperPicker": "󰸉   WALLPAPERS",
                "PASSTHROUGH": "   PASSTHROUGH : ESC",
                "PASSTHROUGH-CONFIRM": "   EXIT PASSTHROUGH ? y , n , ESC",
                "Bluetooth-Mode": "󰂯   BLUETOOTH",
                "Audio-Mode": "󰕾   AUDIO",
                "Display-Mode": "󰍹   DISPLAY",
                "Wifi-Mode": "󰤨   WIFI",
                "Wifi-QR": "   WIFI QR : ESC to close ",
                # NOTE: updates popup  will be used later
                # "Updates-Mode": "󰏖   UPDATES : j , k , h , l , space , Enter , y , n , ESC",
            }.get(name, name.upper()),
        ),
        # Homerow mode chip — same idea as the Chord widget above, but for
        # homerow's direct alt+space/j//c bindings, which are not qtile
        # chords and so never touch that widget. See homerow_mode_text().
        #
        # Explicit chip_color/foreground, not colors[N] indices -- see the
        # matching comment on homerow_mode_chip_nu in normal_user_bar() for
        # why: colors[2] landed on almost exactly DEFAULT_CHIP_COLOR here,
        # invisible near-black text on a near-black chip.
        chip(
            widget.GenPollText,
            chip_color=colors[4],
            name="homerow_mode_chip",
            func=homerow_mode_text,
            update_interval=0.2,
            padding=11,
            foreground=colors[0],
            background=None,
        ),
        # tooltip_widgetbox (lamp) — original leftmost of right cluster
        chip(
            SmartWidgetBox,
            name="tooltip_widgetbox",
            widgets=[],
            padding=11,
            fontsize=_s(12),  # bulb ink was 12px tall, tallest of the set
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
            # Required. qtile refuses to enable scrolling without an
            # explicit pixel width and logs "You must specify a width when
            # enabling scrolling" -- which it did on all 53 recorded
            # starts, so scroll=True/scroll_chars above were dead config.
            width=220,
            padding=10,
            fontsize=_s(15),
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
            fontsize=_s(15),  # window ink was 10px, shortest
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
                    fontsize=_s(10),
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
                    fontsize=_s(10),
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
            fontsize=_s(13),  # heavy X ink was 10px
            # ✖/󰍜 is deliberate -- keep it. U+2716 is not in
            # JetBrainsMono Nerd Font, so fc-match falls back to AdwaitaMono
            # and this chip draws in a different family from its neighbours.
            # That is a known, accepted trade: the heavier X is the shape
            # wanted here. Do not "correct" it to a nerd font glyph again.
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
            fontsize=_s(14),
            padding=10,
            close_button_location="right",
            start_opened=False,
            text_closed="󰤂",
            text_open="󰁂",
            widgets=[
                chip(
                    ewidget.CheckUpdates,
                    name="w_updates",
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
                    fontsize=_s(10),
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
            fontsize=_s(10),
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
            # text_closed carries pango markup; see _apply_raw_markup().
            raw_markup=True,
            # Back to 11: this sizes the CLOSE chevron, which is an ordinary
            # nerd font glyph. The triangle carries its own size in its
            # markup below, so the two states no longer have to share one
            # number -- which is what made the chevron balloon when the
            # triangle was scaled up.
            fontsize=_s(11),
            padding=11,
            # △/ is deliberate -- keep it. U+25B3 is a plain
            # geometric shape rather than an icon from the nerd font set,
            # chosen for its silhouette rather than for consistency with
            # the others. Do not "correct" it to a chevron again.
            # Adwaita Mono Bold, not JetBrainsMono. The ask was a BOLDER
            # triangle of the same shape, and JetBrainsMono cannot give one:
            # rendered at matched ink height it draws U+25B3 with identical
            # ink at Thin, SemiBold and Bold alike, so <b> and weight="900"
            # are measurably no-ops. Surveying every installed font that has
            # the codepoint, normalised to a 12px ink height and scored on
            # ink-per-perimeter (i.e. stroke thickness, independent of size):
            #
            #   AdwaitaMono-Bold      1.63   <- same outline shape, thickest
            #   AdwaitaMono-Regular   1.51
            #   AdwaitaSans-Regular   1.36
            #   JetBrainsMono (any)   1.24
            #
            # 31% more stroke than the old one at the same size, and Adwaita
            # Mono is already on this bar anyway -- the wallpaper chip's ✖
            # falls back to it.
            #
            # size and rise live here rather than on the widget so the close
            # chevron keeps its own metrics -- sharing one number is what
            # made the chevron balloon when the triangle was scaled up.
            #
            # size is in 1024ths of a point and was swept against the live
            # chip for INK height, since that is what the eye compares:
            # 14000 -> 11x10, 16000 -> 12x10, 18000 -> 14x11, 20000 -> 16x13.
            # 14000 puts it on the same 10-11px line as the rest of the
            # cluster, and it carries 50 ink pixels in that box against the
            # old glyph's 46 in a much larger 15x13 -- so it is smaller and
            # visibly heavier at once, which was the point.
            #
            # rise swept the same way: 0-4000 no movement, 6000 -> +0.5px,
            # 8000 -> -0.5px.
            text_closed=(
                '<span font_family="Adwaita Mono" weight="bold" '
                'size="15500" rise="7000">△</span>'
            ),
            text_open="",
            start_opened=False,
            close_button_location="right",
            widgets=[
                ewidget.Systray(
                    icon_size=_s(14),
                    padding=6,
                    hide_crash=True,
                ),
                chip(
                    HideablePollText,
                    name="w_nightlight",
                    func=_nightlight_text,
                    update_interval=5,
                    padding=11,
                    fontsize=_s(11),
                    foreground=colors[6],
                    mouse_callbacks={
                        "Button1": lambda: _nightlight_on(),
                        "Button3": lambda: _nightlight_off(),
                    },
                ),
                # Share the current wifi as a QR code. A plain TextBox, not a
                # poll widget: it has no state to track, so it costs nothing
                # sitting here, and everything it needs is read on click.
                chip(
                    ewidget.TextBox,
                    name="w_wifi_qr",
                    text="\uf029",
                    padding=11,
                    fontsize=_s(11),
                    foreground=colors[5],
                    mouse_callbacks={
                        "Button1": lazy.function(WifiQR.toggle),
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


# -------- Prayer countdown + FX --------
_PRAYER_SCRIPT = os.path.expanduser("~/.config/qtile/scripts/prayer_next.sh")
_FX_SCRIPT = os.path.expanduser("~/.config/qtile/scripts/fx_rates.sh")


def _prayer_text():
    try:
        r = subprocess.run(
            [_PRAYER_SCRIPT], capture_output=True, text=True, timeout=8
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _fx_text():
    try:
        r = subprocess.run([_FX_SCRIPT], capture_output=True, text=True, timeout=8)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _clock_tooltip_text():
    """Next prayer, with USD/EUR in TL and EGP under it.

    The two halves are independent: whichever one comes back empty (dead
    network, missing cache) just drops its block instead of blanking the
    tooltip. Runs in the tooltip worker thread (see _make_tooltip_dynamic),
    so the two subprocesses being serial is harmless -- both read caches.
    """
    blocks = [b for b in (_prayer_text(), _fx_text()) if b]
    return "\n\n".join(blocks)


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

    # WeakSet, not list. As a plain list this leaked in two directions:
    # the orphan widget trees built at the bottom of this file registered
    # here and were never used, and every reload_config appended a whole
    # new generation while the previous one stayed -- with .bar pointing
    # at a dead Bar. close_all() and _all_smart_widgetboxes() then
    # iterated those corpses and called toggle() on them, which
    # toggle_widgets() turns into `self.bar.widgets.insert(...)`. That is
    # the most plausible route by which an unconfigured widget reached a
    # live bar and crashed the draw (see _SafeLengthMixin).
    _instances = weakref.WeakSet()

    def __init__(self, *a, insert_before_name=None, raw_markup=False, **k):
        # raw_markup opts this box out of WidgetBox's label escaping -- see
        # _apply_raw_markup().
        self.raw_markup = raw_markup
        self.insert_before_name = insert_before_name
        super().__init__(*a, **k)

    def _apply_raw_markup(self):
        """Re-apply the label without WidgetBox's pango escaping.

        WidgetBox runs markup_escape_text() over text_closed/text_open
        (widgetbox.py:68 and :99), and it is right to by default -- its own
        default label is "[<]", which pango would otherwise read as a broken
        tag. But it also means a box label can never carry markup, and the
        systray chip needs a <span rise> to sit on the centre line.

        Only for boxes that asked for it: every other one keeps upstream's
        escaping.
        """
        if not getattr(self, "raw_markup", False):
            return
        self.text = self.text_open if self.box_is_open else self.text_closed

    def set_box_label(self):
        """Every label write goes through here, so the un-escaping does too.

        This used to be re-applied only after the two calls this class
        overrides (_configure and toggle), on the reading that those were the
        only two places upstream sets the label. They are not: close_all()
        deliberately calls `super(SmartWidgetBox, wb).toggle()` to close a
        sibling WITHOUT recursing back into our toggle, and upstream's toggle
        calls set_box_label() -- so the systray chip was re-escaped every time
        a different box was opened, and the bar then drew the literal string
        `<span font_family="Adwaita Mono" ...>` where the triangle belongs.
        Clicking the chip fixed it, which is why it looked intermittent.

        Overriding the one method that writes the label closes that hole for
        every path into it, including upstream's open()/close() and anything
        added later, instead of leaving each new caller to remember.
        """
        super().set_box_label()
        self._apply_raw_markup()

    def _configure(self, qtile, bar):
        super()._configure(qtile, bar)
        # Not covered by the set_box_label() override: WidgetBox._configure
        # assigns self.text directly rather than going through it.
        self._apply_raw_markup()
        # Register on _configure, not __init__: only boxes that actually
        # belong to a live bar should ever be reachable from here.
        SmartWidgetBox._instances.add(self)

    def _usable(self):
        """True only if this box is attached to a bar we can safely touch."""
        return bool(getattr(self, "configured", False)) and getattr(self, "bar", None)

    @classmethod
    def close_all(cls, except_self=None):
        for wb in list(cls._instances):
            if wb is except_self or not wb._usable():
                continue
            if getattr(wb, "box_is_open", False):
                try:
                    super(SmartWidgetBox, wb).toggle()
                except Exception:
                    pass

    def toggle(self, *a, **k):
        was_open = getattr(self, "box_is_open", False)
        if not was_open:
            SmartWidgetBox.close_all(except_self=self)
        # No _apply_raw_markup() here: upstream's toggle() calls
        # set_box_label(), which this class overrides to do it.
        res = super().toggle(*a, **k)
        # Opening a box changes how much room the right-hand side needs, and
        # the centring pass is subscribed to CLIENT hooks only -- nothing
        # about a window changed here, so none of them fire. Without this the
        # tasklist keeps its old width and the surplus pushes the last chip
        # off the bar.
        #
        # Synchronously, NOT via _schedule_center_groupbox(). That helper
        # defers to call_later(0), and upstream's toggle() has already
        # queued the repaint with call_soon() -- asyncio drains the
        # call_soon ready queue before it promotes an expired timer, so
        # the bar PAINTS ONCE at the stale widths and only then gets
        # centred. That intermediate frame is the visible one: while
        # something is playing, w_mpris is a STATIC 220px chip, and 220
        # already exceeds the ~205px of slack the stretch spacer holds
        # with every box closed. Opening a box (another ~140px) leaves
        # the bar 155px over-full for that frame, so `_resize` clamps the
        # spacer to zero and every chip from the player rightwards is
        # drawn shifted, then snaps back when the tasklist gives the room
        # up. Running the pass here means the tasklist is already capped
        # when the single queued draw fires, so there is no frame to see.
        try:
            _center_top_groupbox()
        except Exception:
            pass
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
        # Never mutate a bar we are not actually part of.
        if not self._usable():
            return None

        if not self.insert_before_name:
            return super().toggle_widgets()

        for widget in self.widgets:
            try:
                self.bar.widgets.remove(widget)
                widget.drawer.disable()
            except (ValueError, AttributeError):
                # ValueError: not currently in the bar (already removed).
                # AttributeError: widget was never _configure()d, so it
                # has no .drawer -- and must not be inserted below either.
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
                # An unconfigured child has no .drawer and would raise
                # from calculate_length() on the very next Bar._resize().
                if not getattr(widget, "configured", False):
                    continue
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


class _SafeLengthMixin:
    """Never let one widget's length take the whole bar down.

    libqtile's own _Widget.length wraps calculate_length() in a
    try/except and returns 0 on failure (widget/base.py). But
    qtile_extras' inject_decorations() REPLACES `length` on each concrete
    widget class with its own unguarded length_get -- see
    _guard_injected_length() below -- so any exception escapes the property, Python
    falls through to Configurable.__getattr__, and the caller sees

        AttributeError: <X> has no attribute: length

    Bar._resize() sums w.length over every widget, so a single bad one
    aborts the entire draw. That is exactly what happened here: 6 crashed
    startups out of 47 in qtile.log, all of the form

        bar.py:440 in _resize -> sum(w.length for w in widgets ...)
        AttributeError: FlashTextBoxWithTooltip has no attribute: length

    Reproduced directly: an UNCONFIGURED TextBox raises
    `AttributeError: ... has no attribute: bar` out of calculate_length(),
    because self.bar only exists after _configure(). So the underlying
    defect is an unconfigured widget reaching bar.widgets -- addressed by
    the orphan widget trees removed at the bottom of this file and the
    guards on SmartWidgetBox below -- but the bar should degrade to a
    0-width widget rather than stop rendering, which is what upstream
    already does and what this restores.
    """

    @property
    def length(self):
        try:
            return super().length
        except Exception:
            from libqtile.log_utils import logger

            logger.warning(
                "widget %s could not compute length (configured=%s); "
                "treating as 0 so the bar still draws",
                getattr(self, "name", self.__class__.__name__),
                getattr(self, "configured", "?"),
            )
            return 0

    @length.setter
    def length(self, value):
        # _Widget.__init__ assigns self.length, so the setter has to keep
        # working or no chip could be constructed at all. Same body as
        # upstream _Widget.length.setter.
        self._length = value


def _guard_widget_length():
    """Extend the _SafeLengthMixin guarantee to widgets we did not subclass.

    _SafeLengthMixin only protects chips built through _derive(). The bar
    also holds plain widget.TextBox / widget.Spacer / Systray instances,
    and Bar._resize() sums `w.length` across ALL of them -- so one
    unguarded widget still aborts the whole draw. qtile.log recorded
    exactly that as recently as 13:17 today:

        bar.py:440 in _resize -> sum(w.length for w in widgets ...)
        AttributeError: TextBox has no attribute: length

    Why upstream's own try/except does not catch it: _Widget.length reads
    `self.length_type` and `self._length` OUTSIDE the try, and -- more
    subtly -- its `except` handler formats `self.name` into the log
    message. On a widget that has not been _configure()d yet, any of those
    raises AttributeError. An AttributeError escaping a property makes
    Python fall back to Configurable.__getattr__, which reports the
    *property* as missing ("has no attribute: length") rather than the
    attribute that actually failed -- which is why this was hard to read.

    So the guard has to wrap the entire property access, and must not
    touch anything on the widget while handling the failure.
    """
    from libqtile.widget import base as _wbase

    # Reloading the config re-imports this module. Without the flag each
    # reload would wrap the previous wrapper, nesting closures for the
    # lifetime of the session.
    if getattr(_wbase._Widget, "_length_guarded", False):
        return
    _orig = _wbase._Widget.length

    def _get(self):
        try:
            return _orig.fget(self)
        except Exception:
            from libqtile.log_utils import logger

            # type(self).__name__, not self.name: self.name is one of the
            # attributes that can be missing here, and raising from inside
            # the handler is the bug we are fixing.
            logger.warning(
                "widget %s could not compute length (configured=%s); "
                "treating as 0 so the bar still draws",
                type(self).__name__,
                getattr(self, "configured", "?"),
            )
            return 0

    _wbase._Widget.length = property(_get, _orig.fset, _orig.fdel)
    _wbase._Widget._length_guarded = True


_guard_widget_length()


def _guard_injected_length():
    """Close the hole _guard_widget_length() cannot reach.

    Patching _Widget.length is not enough, because qtile_extras does not
    inherit that property -- it OVERWRITES it. decorations.py:1175:

        classdef.length = property(length_get, length_set)

    inject_decorations() runs that against every concrete widget class it
    decorates, so libqtile.widget.textbox.TextBox ends up with its own
    `length` in __dict__ that shadows the guarded one further up the MRO.
    That is why this kept crashing the bar after the first guard went in,
    once per reload_config:

        bar.py:440 in _resize -> sum(w.length for w in widgets ...)
        AttributeError: TextBox has no attribute: length

    It is invisible from a plain `import libqtile` -- the injection happens
    at runtime, not in libqtile's source -- which is what made the earlier
    reading of this ("TextBox OVERRIDES length") look wrong when checked.

    qtile_extras' length_get() reads self.length_type, self._length and
    self.calculate_length() with no guard at all, and every one of those
    needs _configure() to have run. The chips are safe already because
    _SafeLengthMixin sits ahead of the qtile_extras class in their MRO;
    what is left exposed is the plain widgets built directly, like the "|"
    separator TextBoxes.

    Both halves are needed: the sweep covers classes already injected by
    the time this module is imported, and wrapping inject_decorations
    covers anything imported afterwards.
    """
    from libqtile.widget import base as _wbase
    from qtile_extras.widget import decorations as _dec

    def _wrap_class(cls):
        prop = cls.__dict__.get("length")
        # __dict__, not getattr: an inherited guarded property must not
        # count as this class being done, or a subclass that gets its own
        # injection later would be skipped.
        if prop is None or cls.__dict__.get("_length_guard_applied"):
            return
        fget = prop.fget

        def _get(self):
            try:
                return fget(self)
            except Exception:
                from libqtile.log_utils import logger

                # type(self).__name__, never self.name -- self.name is one
                # of the attributes that may be missing here, and raising
                # from inside the handler is the bug being fixed.
                logger.warning(
                    "widget %s could not compute length (configured=%s); "
                    "treating as 0 so the bar still draws",
                    type(self).__name__,
                    getattr(self, "configured", "?"),
                )
                return 0

        cls.length = property(_get, prop.fset, prop.fdel)
        cls._length_guard_applied = True

    def _sweep(cls):
        for sub in cls.__subclasses__():
            _wrap_class(sub)
            _sweep(sub)

    _sweep(_wbase._Widget)

    if not getattr(_dec, "_length_guard_installed", False):
        _orig_inject = _dec.inject_decorations

        def _inject(classdef):
            result = _orig_inject(classdef)
            _wrap_class(classdef)
            return result

        _dec.inject_decorations = _inject
        _dec._length_guard_installed = True


_guard_injected_length()


def _requeue_bar_draw(w, delay=0.2):
    """Ask the bar to draw again shortly, once `w` is configured.

    The companion to skipping a draw: without this the widget would stay
    blank until something else happened to repaint the bar. Guarded by a
    per-widget flag so a bar full of not-yet-ready widgets queues one
    retry, not one per widget per frame.

    Everything is getattr()-ed because the whole point is that this runs on
    a widget that has NOT been _configure()d -- `self.bar` and `self.qtile`
    are among the attributes that do not exist yet.
    """
    b = getattr(w, "bar", None)
    q = getattr(w, "qtile", None) or qtile
    if b is None or q is None or getattr(w, "_draw_requeued", False):
        return
    w._draw_requeued = True

    def _again():
        w._draw_requeued = False
        try:
            if getattr(w, "layout", None) is not None and getattr(w, "configured", False):
                b.draw()
        except Exception:
            pass

    try:
        q.call_later(delay, _again)
    except Exception:
        w._draw_requeued = False


def _guard_groupbox_draw():
    """Stop an unconfigured GroupBox from throwing out of the bar draw.

    Same defect as _SafeLengthMixin, one method further along. A bar can be
    asked to draw while its widgets are still configured=False, and every
    one of the ~20 occurrences in qtile.log looks identical: a burst of

        widget <X> could not compute length (configured=False)

    for the whole bottom-bar widget list -- TextBox, CurrentLayout,
    GroupBox, the SmartWidgetBoxes, Battery, KeyboardLayout, Clock -- and
    then, one millisecond later,

        bar.py:_actual_draw  Widget failed to draw
        groupbox.py:72 in drawbox -> self.layout.text = ...
        AttributeError: 'NoneType' object has no attribute 'text'

    _TextBox.__init__ sets self.layout = None and only _GroupBase._configure()
    builds the real one, so every other widget in that list degrades to
    length 0 (thanks to the length guard) while the GroupBox is the one
    that actually raises. _Widget.finalize() puts it back to None too, so a
    screen being reconfigured -- plugging or unplugging the second monitor
    -- reaches the same state from the other direction.

    Bar._actual_draw() catches the exception, so this was never fatal: the
    cost is the workspace icons missing from that frame and a traceback in
    the log. Skipping the draw and queueing a retry is the same bargain the
    length guard already makes -- degrade, log nothing, repaint when ready.

    drawbox() is patched on _GroupBase, which both GroupBox and AGroupBox
    inherit without overriding, and draw() on the concrete classes.
    qtile_extras' GroupBox is not a separate class -- it re-exports
    libqtile's with decorations injected (checked: __module__ is
    libqtile.widget.groupbox) -- so both bars' widgets are covered, as are
    the _derive()d chip subclasses, which inherit draw() rather than
    defining their own.
    """
    from libqtile.widget import groupbox as _gb

    # Reloading the config re-imports this module; without the flag each
    # reload would wrap the previous wrapper.
    if getattr(_gb._GroupBase, "_draw_guarded", False):
        return

    def _ready(w):
        return getattr(w, "layout", None) is not None and getattr(w, "configured", False)

    _orig_drawbox = _gb._GroupBase.drawbox

    def drawbox(self, *args, **kwargs):
        if getattr(self, "layout", None) is None:
            _requeue_bar_draw(self)
            return
        return _orig_drawbox(self, *args, **kwargs)

    _gb._GroupBase.drawbox = drawbox

    def _guarded_draw(orig):
        def draw(self):
            if not _ready(self):
                _requeue_bar_draw(self)
                return
            return orig(self)

        return draw

    for _cls in (_gb.GroupBox, _gb.AGroupBox):
        _own = _cls.__dict__.get("draw")
        if _own is not None:
            _cls.draw = _guarded_draw(_own)

    _gb._GroupBase._draw_guarded = True


_guard_groupbox_draw()


def _centre_textbox_vertically():
    """Undo libqtile's hardcoded one-pixel downward nudge on widget text.

    libqtile/widget/base.py, _TextBox.draw():

        y = (self.bar.size - self.layout.height) / 2 + 1

    That `+ 1` is not a rounding correction, it is a constant, and it puts
    EVERY text widget in the bar one pixel below true centre. Measured by
    cropping each chip and comparing its plate's bounding box against its
    glyph's ink box: the tooltip, system, wallpaper and systray chips all
    sat at dy = +1.0, and the clock at +1.5. It reads as "the icons are not
    centred" because that is precisely what it is.

    Correcting each glyph with its own pango rise was the wrong SHAPE of
    fix -- it treats a global constant as though it were per-glyph ink
    offsets, and every chip added later would need its own magic number.
    One pixel comes off the draw position instead, once, for everything.

    Done by shifting the layout at the point of use rather than
    reimplementing draw(): that method is long, handles scroll clipping and
    rotation, and copying it here would drift from upstream on the next
    qtile release. Wrapping the single call whose y we care about leaves
    the rest of it upstream's problem.
    """
    from libqtile.widget import base as _wbase

    if getattr(_wbase._TextBox, "_vcentre_patched", False):
        return
    _orig_draw = _wbase._TextBox.draw

    def draw(self):
        layout = self.layout
        # Upstream's draw() opens with `if not self.can_draw(): return`, and
        # can_draw() is exactly `self.layout is not None`. Reaching for
        # layout.draw before delegating stepped in front of that guard, so an
        # unconfigured widget -- which is every widget for a moment during a
        # reload -- raised "'NoneType' object has no attribute 'draw'" out of
        # here instead of being skipped. Hand those straight back.
        if layout is None:
            return _orig_draw(self)
        real_draw = layout.draw

        def shifted(x, y, *a, **k):
            return real_draw(x, y - 1, *a, **k)

        layout.draw = shifted
        try:
            _orig_draw(self)
        finally:
            # Drop the instance attribute so the class method is visible
            # again. The layout can be rebuilt underneath us, so tolerate
            # it having already gone.
            try:
                del layout.draw
            except AttributeError:
                pass

    _wbase._TextBox.draw = draw
    _wbase._TextBox._vcentre_patched = True


_centre_textbox_vertically()


def _guard_x11_layering():
    """Stop a stale window reference taking the whole session down.

    This is the bug that ended the session on 2026-07-31 at 04:37:53. The
    fatal traceback, from the log:

        core.py:947  check_stacking   -> self.last_focused.change_layer()
        window.py:1167 change_layer   -> self.qtile.windows_map[wid].window...
        KeyError: 31457294

    Core.check_stacking keeps `last_focused` as a direct reference to a
    Window and never clears it when that window stops being managed. During
    a restart or a config reload, qtile tears down and rebuilds
    windows_map, so `last_focused` routinely points at a window that no
    longer exists -- and check_stacking calls change_layer() on it anyway.
    change_layer then looks the wid up in windows_map and raises KeyError,
    out of an event handler, which is fatal.

    Two guards, because there are two ways in:

    check_stacking gets the missing membership test. It is six lines
    upstream and is reimplemented here rather than wrapped, since the point
    is a condition in the middle of it.

    change_layer gets a blanket catch, which is the right shape for this
    one: its entire job is deciding which window sits above which, so the
    cost of giving up on a single call is one frame of possibly-wrong
    stacking order, corrected by the next focus event. The cost of NOT
    giving up is the session dying. The same function also does
    `group_bar.window.get_layering_information()` without checking that the
    bar HAS a window yet -- that is the AttributeError that fired thirteen
    times on toggle_fullscreen in the previous log -- so the catch covers
    both rather than guessing at every unbuilt object it might touch.
    """
    from libqtile.backend.x11 import core as _x11core
    from libqtile.backend.x11 import window as _x11window

    if getattr(_x11core.Core, "_layering_guarded", False):
        return

    def check_stacking(self, win):
        last = self.last_focused
        if win is last:
            return
        # The added test: only restack a window qtile still manages.
        if (
            last is not None
            and getattr(last, "wid", None) in self.qtile.windows_map
            and last.fullscreen
        ):
            last.change_layer()
        self.last_focused = win

    _x11core.Core.check_stacking = check_stacking

    _orig_change_layer = _x11window._Window.change_layer

    def change_layer(self, *a, **k):
        try:
            return _orig_change_layer(self, *a, **k)
        except (KeyError, AttributeError):
            from libqtile.log_utils import logger

            logger.warning(
                "change_layer failed for %s; leaving the stacking order alone "
                "rather than raising out of an event handler",
                getattr(self, "wid", "?"),
            )

    _x11window._Window.change_layer = change_layer
    _x11core.Core._layering_guarded = True


_guard_x11_layering()


class _ChipFlashMixin(_SafeLengthMixin):
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
_safe_widget_cache = {}


def _derive(WCls, bases, marker):
    """Build a subclass that is indistinguishable from WCls by name.

    This matters more than it looks. _Widget.__init__ does

        self.name = self.__class__.__name__.lower()

    so naming the generated class "FlashCurrentLayout" silently renamed
    the widget to "flashcurrentlayout" -- which then matched neither
    TOOLTIP_BY_NAME nor TOOLTIP_BY_CLASS (keyed "CurrentLayout"), so the
    CurrentLayout and CheckUpdates chips could never get a tooltip.
    Confirmed live: `qtile cmd-obj -o bar top -f info` reported the
    widget as "flashcurrentlayout". It also hid the clickable
    SmartWidgetBox chips from _all_smart_widgetboxes(), whose bar scan
    tested `w.__class__.__name__ == "SmartWidgetBox"`.

    Keeping __name__ identical fixes all of that at once. __qualname__
    still carries the marker, so tracebacks and repr stay debuggable.
    """
    cls = type(WCls.__name__, bases, {})
    cls.__qualname__ = f"{marker}{WCls.__name__}"
    return cls


def _flash_widget_class(WCls):
    if WCls not in _flash_widget_cache:
        _flash_widget_cache[WCls] = _derive(WCls, (_ChipFlashMixin, WCls), "Flash")
    return _flash_widget_cache[WCls]


def _safe_widget_class(WCls):
    """Same _SafeLengthMixin guard for chips with no click handler.

    The crash in the log happened to be on a clickable chip, but nothing
    about it is click-specific -- any chip can hit it -- so every chip
    gets the guard, not just the ones that pick up _ChipFlashMixin.
    """
    if WCls not in _safe_widget_cache:
        _safe_widget_cache[WCls] = _derive(WCls, (_SafeLengthMixin, WCls), "Safe")
    return _safe_widget_cache[WCls]


def chip(WCls, chip_color=None, **kwargs):
    base_color = chip_color if chip_color is not None else DEFAULT_CHIP_COLOR
    deco = RectDecoration(
        colour=base_color,
        # radius = half the plate's height, so the short sides are true
        # semicircles: single-glyph chips come out round and wider ones come
        # out as proper pills. It was a flat 11 against a plate that is
        # _s(28) - 2*padding_y = 24 tall, which is one pixel short of the 12
        # a full round needs -- leaving a 2px straight segment on each short
        # side. Small, but it is the difference between "circle" and
        # "squircle", and it was visible on the logo chip.
        # Derived rather than hardcoded so it stays correct at any UI scale;
        # keep the 28 in step with the bar's own size= below.
        radius=(_s(28) - 2 * 2) / 2,
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
    # Either way the chip gets _SafeLengthMixin (via _ChipFlashMixin for
    # the clickable ones), so a widget that cannot compute its length can
    # never abort the whole bar draw.
    has_click = bool(kwargs.get("mouse_callbacks"))
    cls = _flash_widget_class(WCls) if has_click else _safe_widget_class(WCls)

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
    # Hint mode is bound directly, not only in the chord. It is the action
    # you take constantly, and a chord costs a keystroke plus remembering you
    # are in a mode -- Homerow on macOS is one chord-free keystroke, and that
    # is most of what makes it feel immediate. The other modes stay in the
    # Hint-Mode chord (win+shift+f), where discovering them is worth the step.
    # alt+space rather than Homerow's shift+space, which would swallow every
    # shift+space you type.
    Key(
        [mod2],
        "space",
        lazy.spawn(HOMEROW),
        desc="Homerow: hint and click / switch window",
    ),
    # Homerow binds a key per mode rather than nesting them: shift+space,
    # shift+J, shift+/ over there. Same shape here with alt, since grabbing
    # shift+<letter> globally on X11 would swallow ordinary typing.
    # alt+v is already the CopyQ picker, so caret takes alt+c.
    Key(
        [mod2],
        "j",
        lazy.spawn(HOMEROW + " --scroll"),
        desc="Homerow: scroll mode",
    ),
    Key(
        [mod2],
        "slash",
        lazy.spawn(HOMEROW + " --search"),
        desc="Homerow: search mode",
    ),
    Key(
        [mod2],
        "c",
        lazy.spawn(HOMEROW + " --caret"),
        desc="Homerow: caret mode",
    ),
    Key(
        [mod2, "shift"],
        "c",
        lazy.spawn(HOMEROW + " --caret-search"),
        desc="Homerow: caret search (type to find a word, land the caret there)",
    ),
    Key(
        [mod2],
        "e",
        lazy.spawn(HOMEROW + " --edit"),
        desc="Homerow: edit a field in nvim, in place",
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
    # --- voice dictation ---
    # Bare F8/F9, moved off Super+Shift+V/B. Dictation is a hold-a-thought
    # action: the whole value is being able to start it before the sentence
    # goes, and a three-key chord is long enough to lose it. F8 and F9 stay
    # adjacent the way V and B were, so the live/batch pair is still one
    # finger apart.
    #
    # F8/F9 and not F6/F7, which is where these first landed. A bare binding
    # is a GLOBAL grab -- qtile takes the key from every application, for
    # good -- so the only question that matters is which keys nothing else
    # wants. Across the row:
    #
    #   F1 help   F2 rename   F3 find-next   F5 reload
    #   F6 address bar        F7 caret browsing (Firefox)
    #   F10 menu bar   F11 fullscreen   F12 devtools
    #   F8, F9 -- claimed by essentially nothing
    #
    # F6 and F7 were the two genuinely contested keys in the row; F8 and F9
    # cost nothing to take. Same single keystroke, no conflict traded for it.
    #
    # Inside qtile the whole row was free either way: only Super+F12
    # (passthrough) and Super+Shift+F5 (refresh) are bound anywhere in it.
    Key(
        [],
        "F8",
        lazy.spawn("voice_dictate_live"),
        desc="Start/stop live voice dictation (types each phrase as you pause)",
    ),
    Key(
        [],
        "F9",
        lazy.spawn("voice_dictate"),
        desc="Start/stop batch voice dictation (whisper.cpp -> xdotool type)",
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
        # myTerm, not my2ndTerm. alacritty was the only reason my2ndTerm
        # existed, and its font.size is 9.0 against kitty's 11.0 -- so this
        # one window rendered ~18% smaller than every other terminal on the
        # desktop, permanently, at every scale. It also could not follow a
        # UI scale change: kitty re-derives its cell size from Xft.dpi while
        # running (measured across a DPI change, minimized included),
        # alacritty reads it once at startup, and this window is long-lived
        # and only ever minimized -- so it kept whatever scale it was born
        # at until something killed it.
        lazy.function(lambda qtile: toggle_or_spawn_sum(qtile, myTerm, sum_file)),
        desc="Open or focus sum.md globally",
    ),
    # --- Android phone screen (scrcpy over Wi-Fi) ---
    Key(
        [mod, "shift"],
        "F6",
        # Next to Super+Shift+F5 (Refresh PC) on purpose: both are
        # whole-machine actions rather than window management, and this
        # keeps that pair adjacent. The F6/F7 contention noted above
        # applies to the BARE keys; under Super+Shift the row is free.
        #
        # phone_screen does the discovery adb cannot: Arch's android-tools
        # is built without mDNS, so it never finds a wirelessly-debugging
        # phone by itself and the address+port have to be copied off the
        # phone by hand every session. The script reads the same mDNS
        # announcement through avahi-browse and hands adb a host:port.
        lazy.spawn("phone_screen"),
        desc="Mirror the Android phone (scrcpy, USB or Wi-Fi)",
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
    Key(
        [mod2],
        "n",
        lazy.spawn("dunstctl close"),
        desc="Dismiss the top notification",
    ),
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
    # left()/right() exist on MonadTall/Columns/BSP but NOT on Max or
    # TreeTab -- and groups 2 (browsers) and 5 (brave) both default to
    # max, so plain lazy.layout.left() logged
    #     KB command error left: No such command
    # during ordinary use. Verified against the layout classes: Max
    # exposes up/down/next/previous, TreeTab exposes next/previous
    # (plus section_up/section_down and move_left/move_right).
    Key(
        [mod],
        "h",
        lazy.layout.left().when(layout=["monadtall", "monadwide", "columns", "bsp"]),
        lazy.layout.previous().when(layout=["max", "treetab"]),
        desc="Move focus to left",
    ),
    Key(
        [mod],
        "l",
        lazy.layout.right().when(layout=["monadtall", "monadwide", "columns", "bsp"]),
        lazy.layout.next().when(layout=["max", "treetab"]),
        desc="Move focus to right",
    ),
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
            # --- passwords ---
            # Was a commented-out `passmenu` line for years. rofi_pass
            # replaces it: a rofi picker over Vaultwarden (local, on
            # 127.0.0.1:8222) via rbw, so the same vault the Bitwarden
            # phone app syncs from is the one this reads.
            Key([], "p", lazy.spawn("rofi_pass"), desc="Passwords (Vaultwarden)"),
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
                    "python3 "
                    + os.path.expanduser(
                        "~/.config/rofi_translator/wordreference.py"
                    )
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
            # w for wallpaper. (Was b, which now opens Bluetooth.)
            KeyChord(
                [],
                "w",
                [
                    # NAVIGATE LEFT / RIGHT
                    Key([], "h", lazy.function(lambda _: WallpaperPopup.move(0, -1))),
                    Key([], "l", lazy.function(lambda _: WallpaperPopup.move(0, 1))),
                    # Lowercase deliberately. qtile's keysym table is
                    # lowercase-normalised and lookups are lowercased, so
                    # Key([], "R") never meant Shift+R -- it has always
                    # bound plain `r`. Spelling it "r" keeps the existing
                    # behaviour and stops the binding lying about itself;
                    # the chord chip labels now agree.
                    Key(
                        [],
                        "r",
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
                    # `A and B` evaluated to B alone -- lazy.function(...)
                    # is truthy -- so the close call was discarded at
                    # config-load time and this Key only ever ungrabbed.
                    # It looked fine because ungrab fires leave_chord and
                    # cleanup_on_leave closes the picker. Key(*commands)
                    # takes them as separate positional arguments.
                    Key(
                        [],
                        "q",
                        lazy.function(
                            lambda _: WallpaperPopup.close_wallpaper_picker()
                        ),
                        lazy.ungrab_chord(),
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
            # --- a Special mode for "Bluetooth" ---
            # --- Bluetooth MODE ---
            # b for bluetooth. Everything happens in the popup: scan, pair,
            # trust, connect, disconnect, remove -- blueman's window is not
            # involved.
            KeyChord(
                [],
                "b",
                [
                    # NAVIGATE
                    Key([], "j", lazy.function(lambda _: BluetoothPopup.move(1))),
                    Key([], "k", lazy.function(lambda _: BluetoothPopup.move(-1))),
                    Key([], "g", lazy.function(lambda _: BluetoothPopup.jump("top"))),
                    Key(
                        ["shift"],
                        "g",
                        lazy.function(lambda _: BluetoothPopup.jump("bottom")),
                    ),
                    # ACTIONS
                    Key([], "Return", lazy.function(lambda _: BluetoothPopup.connect())),
                    Key([], "d", lazy.function(lambda _: BluetoothPopup.disconnect())),
                    Key([], "x", lazy.function(lambda _: BluetoothPopup.remove())),
                    Key([], "t", lazy.function(lambda _: BluetoothPopup.toggle_power())),
                    Key([], "r", lazy.function(lambda _: BluetoothPopup.scan())),
                    # Abort a pair/connect that is hanging. bluetoothctl
                    # connect never returns for an out-of-range device.
                    Key([], "c", lazy.function(lambda _: BluetoothPopup.cancel())),
                    Key([], "slash", lazy.function(lambda _: BluetoothPopup.search())),
                    # EXIT. No Escape binding: KeyChord appends its own after
                    # these and later grabs win, so Escape closes via
                    # cleanup_on_leave. Same as the WiFi chord.
                    Key(
                        [],
                        "q",
                        lazy.function(lambda qtile: BluetoothPopup.close(qtile)),
                        lazy.ungrab_chord(),
                    ),
                ],
                mode=True,
                name="Bluetooth-Mode",
                desc="Bluetooth device picker",
            ),
            # --- a Special mode for "Audio" ---
            # --- AUDIO MODE ---
            # v for volume: a is taken (rofi_anki), and g/j/u/v were the only
            # free letters left in this chord. Everything happens in the
            # popup -- output, mic, per-app volume and card profiles -- so
            # pavucontrol is not involved.
            KeyChord(
                [],
                "v",
                [
                    # NAVIGATE
                    Key([], "j", lazy.function(lambda _: AudioPopup.move(1))),
                    Key([], "k", lazy.function(lambda _: AudioPopup.move(-1))),
                    Key([], "g", lazy.function(lambda _: AudioPopup.jump("top"))),
                    Key(
                        ["shift"],
                        "g",
                        lazy.function(lambda _: AudioPopup.jump("bottom")),
                    ),
                    # VIEWS. Tab cycles; the direct letters are for jumping
                    # straight to one.
                    Key([], "Tab", lazy.function(lambda _: AudioPopup.cycle_view(1))),
                    Key(
                        ["shift"],
                        "Tab",
                        lazy.function(lambda _: AudioPopup.cycle_view(-1)),
                    ),
                    Key([], "o", lazy.function(lambda _: AudioPopup.set_view("outputs"))),
                    Key([], "i", lazy.function(lambda _: AudioPopup.set_view("inputs"))),
                    Key([], "a", lazy.function(lambda _: AudioPopup.set_view("playback"))),
                    Key(
                        [],
                        "s",
                        lazy.function(lambda _: AudioPopup.set_view("recording")),
                    ),
                    Key([], "p", lazy.function(lambda _: AudioPopup.show_profiles())),
                    # Every card at once -- pavucontrol's Configuration tab.
                    Key(["shift"], "c", lazy.function(lambda _: AudioPopup.show_cards())),
                    # Enter on a stream opens the device picker; d is the
                    # shortcut for "just put it on the default".
                    Key([], "d", lazy.function(lambda _: AudioPopup.send_to_default())),
                    # Shift+p for the jack/port dropdown -- the thing that
                    # picks Headphones over Speakers on one card.
                    Key(["shift"], "p", lazy.function(lambda _: AudioPopup.show_ports())),
                    # Balance, stereo devices only. 0 re-centres.
                    Key(
                        [],
                        "b",
                        lazy.function(
                            lambda _: AudioPopup.change_balance(-AudioPopup.BALANCE_STEP)
                        ),
                    ),
                    Key(
                        ["shift"],
                        "b",
                        lazy.function(
                            lambda _: AudioPopup.change_balance(AudioPopup.BALANCE_STEP)
                        ),
                    ),
                    Key([], "0", lazy.function(lambda _: AudioPopup.change_balance(0))),
                    # ACTIONS. Enter on an output also drags the running
                    # streams over -- setting the default alone only affects
                    # what starts playing afterwards.
                    Key([], "Return", lazy.function(lambda _: AudioPopup.activate())),
                    Key(
                        [],
                        "l",
                        lazy.function(
                            lambda _: AudioPopup.change_volume(AudioPopup.VOLUME_STEP)
                        ),
                    ),
                    Key(
                        [],
                        "h",
                        lazy.function(
                            lambda _: AudioPopup.change_volume(-AudioPopup.VOLUME_STEP)
                        ),
                    ),
                    Key([], "m", lazy.function(lambda _: AudioPopup.toggle_mute())),
                    Key([], "r", lazy.function(lambda _: AudioPopup.refresh(True))),
                    # Abort a card-profile switch: a bluez renegotiation can
                    # sit there for seconds.
                    Key([], "c", lazy.function(lambda _: AudioPopup.cancel())),
                    # EXIT. No Escape binding: KeyChord appends its own after
                    # these and later grabs win, so Escape closes via
                    # cleanup_on_leave. Same as the WiFi and Bluetooth chords.
                    Key(
                        [],
                        "q",
                        lazy.function(lambda qtile: AudioPopup.close(qtile)),
                        lazy.ungrab_chord(),
                    ),
                ],
                mode=True,
                name="Audio-Mode",
                desc="Audio output / input / per-app volume picker",
            ),
            # --- a Special mode for "Displays" ---
            # --- DISPLAY MODE ---
            # g for graphics. No autorandr on this system, so this is the
            # only keyboard path to a second monitor.
            KeyChord(
                [],
                "g",
                [
                    # NAVIGATE. In arrange mode j/k/h/l move the picked
                    # monitor instead of the cursor -- see DisplayPopup.nav
                    # and .place, which branch on the active view.
                    Key([], "j", lazy.function(lambda _: DisplayPopup.nav(1))),
                    Key([], "k", lazy.function(lambda _: DisplayPopup.nav(-1))),
                    Key([], "Tab", lazy.function(lambda _: DisplayPopup.pick_next(1))),
                    Key([], "a", lazy.function(lambda _: DisplayPopup.start_arrange())),
                    Key([], "g", lazy.function(lambda _: DisplayPopup.jump("top"))),
                    Key(
                        ["shift"],
                        "g",
                        lazy.function(lambda _: DisplayPopup.jump("bottom")),
                    ),
                    # Enter opens the resolution / refresh list for the
                    # selected output, and applies the mode from inside it.
                    Key([], "Return", lazy.function(lambda _: DisplayPopup.activate())),
                    Key([], "BackSpace", lazy.function(lambda _: DisplayPopup.back())),
                    # ONE-KEY LAYOUTS -- the 95% cases.
                    Key([], "i", lazy.function(lambda _: DisplayPopup.preset("internal"))),
                    Key([], "e", lazy.function(lambda _: DisplayPopup.preset("external"))),
                    Key([], "m", lazy.function(lambda _: DisplayPopup.preset("mirror"))),
                    # Placement. u/d rather than j/k: those are the cursor.
                    Key([], "h", lazy.function(lambda _: DisplayPopup.place("left"))),
                    Key([], "l", lazy.function(lambda _: DisplayPopup.place("right"))),
                    Key([], "u", lazy.function(lambda _: DisplayPopup.preset("above"))),
                    Key([], "d", lazy.function(lambda _: DisplayPopup.preset("below"))),
                    # PER-OUTPUT
                    Key([], "p", lazy.function(lambda _: DisplayPopup.set_primary())),
                    Key([], "t", lazy.function(lambda _: DisplayPopup.rotate())),
                    Key([], "f", lazy.function(lambda _: DisplayPopup.reflect())),
                    Key([], "o", lazy.function(lambda _: DisplayPopup.toggle_output())),
                    Key([], "r", lazy.function(lambda _: DisplayPopup.refresh(True))),
                    # SAVED LAYOUTS -- what autorandr would do, except this
                    # machine does not have autorandr.
                    Key([], "v", lazy.function(lambda _: DisplayPopup.show_layouts())),
                    Key([], "s", lazy.function(lambda _: DisplayPopup.save_current())),
                    Key([], "x", lazy.function(lambda _: DisplayPopup.delete_layout())),
                    # A change that could blank the screen stays provisional
                    # until `y`; `c` reverts it now, and doing nothing reverts
                    # it when the countdown runs out.
                    Key([], "y", lazy.function(lambda _: DisplayPopup.keep())),
                    # Cross-axis alignment while arranging: tops / centres /
                    # bottoms. The one thing arandr could do that this could
                    # not.
                    Key([], "equal", lazy.function(lambda _: DisplayPopup.cycle_align())),
                    Key([], "c", lazy.function(lambda _: DisplayPopup.cancel())),
                    # EXIT. No Escape binding, same reason as above -- and
                    # cleanup_on_leave reverts any pending change on the way
                    # out.
                    Key(
                        [],
                        "q",
                        lazy.function(lambda qtile: DisplayPopup.close(qtile)),
                        lazy.ungrab_chord(),
                    ),
                ],
                mode=True,
                name="Display-Mode",
                desc="Display / xrandr layout picker",
            ),
            # --- a Special mode for "WiFi" ---
            # --- WiFi MODE ---
            # n for network. (Was w, which now opens the wallpaper picker.)
            KeyChord(
                [],
                "n",
                [
                    # NAVIGATE
                    Key([], "j", lazy.function(lambda _: WifiPopup.move(1))),
                    Key([], "k", lazy.function(lambda _: WifiPopup.move(-1))),
                    Key([], "g", lazy.function(lambda _: WifiPopup.jump("top"))),
                    Key(["shift"], "g", lazy.function(lambda _: WifiPopup.jump("bottom"))),
                    # ACTIONS
                    Key([], "Return", lazy.function(lambda _: WifiPopup.connect())),
                    Key([], "d", lazy.function(lambda _: WifiPopup.disconnect())),
                    Key([], "x", lazy.function(lambda _: WifiPopup.forget())),
                    Key([], "n", lazy.function(lambda _: WifiPopup.connect_hidden())),
                    Key([], "t", lazy.function(lambda _: WifiPopup.toggle_radio())),
                    Key([], "s", lazy.function(lambda q: WifiPopup.share_qr(q))),
                    # Abort a connect that is taking too long. Advertised in
                    # the footer while busy rather than as a permanent hint
                    # chip -- that bar is at 808px of its 874px.
                    Key([], "c", lazy.function(lambda _: WifiPopup.cancel())),
                    Key([], "r", lazy.function(lambda _: WifiPopup.rescan())),
                    Key([], "slash", lazy.function(lambda _: WifiPopup.search())),
                    # EXIT. Passed as separate positional commands --
                    # `lazy.function(...) and lazy.ungrab_chord()` evaluates
                    # to the second one alone and silently drops the close.
                    Key(
                        [],
                        "q",
                        lazy.function(lambda qtile: WifiPopup.close(qtile)),
                        lazy.ungrab_chord(),
                    ),
                    # No Escape binding on purpose. KeyChord.__init__ appends
                    # its own bare Key([], "Escape") *after* the submappings,
                    # and grab_chord binds them in order with later ones
                    # overriding earlier -- so a hand-written Escape here is
                    # dead code that only logs "Key spec duplicated".
                    # Escape still works: process_key_event ungrabs the chord
                    # for any key named Escape, which fires leave_chord, and
                    # cleanup_on_leave closes this popup.
                ],
                mode=True,
                name="Wifi-Mode",
                desc="WiFi network picker",
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
            # Moved off n (now the WiFi picker) to o -- "nOte". g/j/u/v/y are
            # the other free letters in this chord.
            Key([], "o", lazy.spawn("dm-note -r"), desc="Store and copy notes"),
            # --- rofi password menu ---
            # Removed: a second Key([], "p") in this same chord, so it
            # duplicated the binding above and only one could ever win.
            # It spawned `rofi-pass`, the frontend for pass(1) -- both
            # are installed, but ~/.password-store does not exist, so it
            # had no vault to read either way. Passwords now go through
            # rofi_pass (Vaultwarden via rbw), bound above.
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
            # Disabled: `w` now opens the WiFi picker (chord above).
            # Key([], "w", lazy.spawn("dm-weather -r"), desc="Search weather"),
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
    # --- Hint Mode (was Mouse-Mode) ---
    # win+shift+f opens it; h/s/f then pick hint, scroll or search. Keys only
    # do anything while the chord is active, so none of these letters are
    # taken away from normal typing.
    KeyChord(
        [mod, "shift"],
        "f",
        [
            # --- homerow (AT-SPI: real elements, exact bounds) ---
            # Each of these leaves the chord. It used to persist so actions
            # could be chained, but this chord is mode=True and swallow=True:
            # while it is open every other binding on the desktop is dead,
            # including the ones that reload qtile, and nothing in the bar
            # says you are in it. A chord you cannot tell you are inside is
            # indistinguishable from the keyboard having broken. Chaining is
            # no longer worth that -- every mode has its own alt binding now.
            Key(
                [], "h",
                lazy.spawn(HOMEROW),
                lazy.ungrab_chord(),
                desc="hint and click elements / switch window",
            ),
            Key(
                [], "s",
                lazy.spawn(HOMEROW + " --scroll"),
                lazy.ungrab_chord(),
                desc="pick a scrollable region, drive it with vim keys",
            ),
            Key(
                [], "f",
                lazy.spawn(HOMEROW + " --search"),
                lazy.ungrab_chord(),
                desc="search elements, digits pick, enter clicks",
            ),
            Key(
                [], "v",
                lazy.spawn(HOMEROW + " --caret"),
                lazy.ungrab_chord(),
                desc="caret mode: vim motions over real text, v selects, y yanks",
            ),
            Key(
                ["shift"], "v",
                lazy.spawn(HOMEROW + " --caret-search"),
                lazy.ungrab_chord(),
                desc="caret search: type to find a word, land the caret there",
            ),
            Key(
                [], "e",
                lazy.spawn(HOMEROW + " --edit"),
                lazy.ungrab_chord(),
                desc="edit a field in nvim, in place; :wq puts it back",
            ),
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
        name="Hint-Mode",
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
                lazy.function(cheatsheet_k),
                desc="Show cheatsheet / scroll up",
            ),
            Key(
                [],
                "j",
                lazy.function(scroll_cheatsheet),
                desc="Scroll down",
            ),
            Key(
                [],
                "v",
                lazy.function(open_vim_cheatsheet),
                desc="Show vim cheatsheet",
            ),
            Key(
                [],
                "f",
                lazy.function(open_fish_cheatsheet),
                desc="Show fish cheatsheet",
            ),
            # Tab moves a screenful in whichever sheet is open; j/k above
            # move by a few rows for fine scrolling.
            Key(
                [],
                "Tab",
                lazy.function(page_cheatsheet),
                desc="Next cheatsheet screenful",
            ),
            Key(
                ["shift"],
                "Tab",
                lazy.function(lambda q: page_cheatsheet(q, -1)),
                desc="Previous cheatsheet screenful",
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
# popup never opened. Ours has to be grabbed last to actually run.
#
# We used to just append a second Escape on top. That worked, but left two
# Escape specs in the list, and qtile logs one
#   WARNING:libqtile:Key spec duplicated, overriding previous: <Key ([], Escape)>
# per chord on every startup and every reload -- two lines of scary-looking
# noise, at the top of the screen at login, for a situation we created on
# purpose. Drop qtile's auto-added Escape first, then append ours: same
# "ours is last" guarantee, exactly one spec, no warning.
def _set_chord_escape(chord, handler):
    if chord is None:
        return
    chord.submappings[:] = [
        k
        for k in chord.submappings
        if not (isinstance(k, Key) and k.key == "Escape" and not k.modifiers)
    ]
    chord.submappings.append(Key([], "Escape", lazy.function(handler)))


_set_chord_escape(PASSTHROUGH_CHORD, _passthrough_esc)
_set_chord_escape(PASSTHROUGH_CONFIRM_CHORD, _passthrough_confirm_esc)

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
        # pcmanfm-qt reports WM_CLASS ("pcmanfm-qt", "pcmanfm-qt"). Match is an
        # exact test, not a substring one, so the old "pcmanfm" entry does NOT
        # catch it -- a Qt window would have stayed on whatever group spawned
        # it. Both are listed: the GTK build is still installed as an LXDE
        # dependency and can still be launched by hand.
        matches=[
            Match(wm_class="org.gnome.Nautilus"),
            Match(wm_class="pcmanfm-qt"),
            Match(wm_class="pcmanfm"),
        ],
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
    # Documents: LibreOffice + the PDF/ebook readers. _focus_document_app()
    # takes you here when one opens, so this is not just where they are filed
    # away -- it is where you end up.
    Group(
        "8",
        # U+F02D (book). Checked with fc-match before use, like every other
        # label here: the GroupBox inherits widget_defaults' "Ubuntu Bold",
        # which has no Font Awesome range at all, so these all arrive by
        # fontconfig fallback -- silently, and as a blank box when the glyph
        # is not actually there. This one resolves to FiraCode Nerd Font, the
        # same family already serving groups 1, 2, 4 and 5, and was rendered
        # to confirm it is a book and not tofu.
        #
        # Written as an escape, not as the literal glyph the other labels use:
        # a bare PUA character does not survive every editor and tool that
        # touches this file, and it arrived here once already as an empty
        # string -- which renders as a blank slot in the bar, not as an error.
        label="",
        matches=[Match(wm_class=c) for c in DOCUMENT_APP_CLASSES],
        # max, not monadtall: a document is one thing you read at a time, and
        # monadtall's side column would hand half the width to whatever else
        # happened to be open on the group. Full width is the point here.
        layout="max",
    ),
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
        border_width=_s(0),
        margin=0,
    ),
    layout.TreeTab(
        font="Ubuntu Bold",
        fontsize=_s(11),
        border_width=_s(8),
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
    fontsize=_s(10),
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
        # Only touch a bar that is actually live. This runs from nine hooks,
        # several of which (setgroup, focus_change, client_managed) fire
        # during the screen churn a monitor hotplug causes -- and in that
        # window Bar.finalize() has killed the bar's window and finalized
        # its widgets while screen.top still points at it. Measuring a
        # half-torn-down bar gives nonsense lengths, and the b.draw() below
        # would be a draw on finalized widgets.
        if not getattr(b, "_configured", False) or getattr(b, "window", None) is None:
            continue
        if any(not getattr(w, "configured", False) for w in widgets):
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
                # Centring alone is not enough. The spacer to the RIGHT of the
                # GroupBox is the only STRETCH widget, so it is the only thing
                # that can absorb growth on that side -- and a SmartWidgetBox
                # opening inserts its contents there. Once those exceed the
                # spacer's slack (189px with everything closed), the surplus
                # runs off the end of the bar and the systray chip, being
                # last, is what disappears.
                #
                # So the TaskList is also capped by what is actually left over
                # once the right-hand side has been paid for. STRETCH widgets
                # are excluded from that sum: the spacer collapsing to zero is
                # exactly the slack being counted here, and counting it twice
                # would shrink the tasklist for no reason.
                right = widgets[gb_i + 1:]
                right_w = sum(
                    w.length for w in right if w.length_type != bar.STRETCH
                )
                fits = b.width - others - widgets[gb_i].length - right_w
                cap = min(cap, max(0, fits))
                if tl.length_type != bar.STATIC or tl.length != cap:
                    tl.length_type = bar.STATIC
                    tl.length = cap
                    changed = True

            left_w = others + (tl.length if tl is not None else 0)
            new_len = max(0, target - left_w)
            # Centring must yield to fitting. This spacer is pure padding
            # placed to push the GroupBox to the middle, so when the bar is
            # over-full it simply re-eats whatever the TaskList just gave up
            # and the surplus still runs off the right-hand end. Capped by the
            # room genuinely left after the right-hand side is paid for: the
            # GroupBox drifts off-centre only once there is no alternative,
            # which is the better failure -- an off-centre GroupBox is
            # visible, a chip past the edge of the screen is not.
            room = b.width - others - (tl.length if tl is not None else 0) \
                - widgets[gb_i].length - right_w
            new_len = min(new_len, max(0, room))
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
        # Delay 0, not 0.05. The debounce is about COALESCING -- these hooks
        # fire several times per event and the flag above already collapses
        # them -- not about waiting. The 50ms wait was visible: entering a
        # chord draws the chip at full width first, and the bar stays
        # over-full until this runs. Captured it at 29fps: the last chip's
        # right edge sat at x=1355 instead of 1351 for two frames, then
        # snapped back. call_later(0) runs on the next pass of the event
        # loop, after the widget that grew has updated but before the bar
        # settles, so there is no intermediate frame to see.
        qtile.call_later(0, _run)
    except Exception:
        _GB_CENTER_PENDING = False


# Chord enter/leave included: the chord chip appears and disappears with the
# mode, and that changes the bar's total width by its whole length without any
# client event happening. Same class of problem as a widget box opening, which
# SmartWidgetBox.toggle() now handles directly -- anything that resizes a
# widget without touching a window has to say so, or the surplus silently runs
# off the right-hand end of the bar.
for _gb_hook in (
    "startup_complete",
    "client_managed",
    "client_killed",
    "client_name_updated",
    "setgroup",
    "changegroup",
    "focus_change",
    "enter_chord",
    "leave_chord",
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


def init_widgets_screen1():
    widgets_screen1 = init_widgets_list()
    return widgets_screen1


def _strip_systray(widgets):
    """Remove the Systray from a widget list, in place, and return it.

    X11 allows exactly one system tray owner per display (the tray is a
    single XEmbed selection, _NET_SYSTEM_TRAY_S0). Building a second
    Systray therefore does not merely render an empty box -- the second
    instance fails to acquire the selection and qtile aborts config load,
    which is the whole reason the second monitor's bar never worked.

    The Systray is not a top-level entry here: it lives inside the
    SmartWidgetBox named "systray_widgetbox" (see right_side_widgets), so
    the old index-slicing approach could never have reached it. Descend
    into any widget exposing a .widgets list and drop Systray instances
    wherever they turn up, leaving every sibling (nightlight, etc.) in
    place so secondary bars stay otherwise identical.
    """
    for w in widgets:
        inner = getattr(w, "widgets", None)
        if isinstance(inner, list):
            inner[:] = [i for i in inner if not isinstance(i, widget.Systray)]
    return [w for w in widgets if not isinstance(w, widget.Systray)]


# All other monitors' bars display everything except the systray.
def init_widgets_screen2():
    return _strip_systray(init_widgets_list())


def init_widgets_normaluserbar():
    widgets_screen1 = init_widgets_list_normaluserbar()
    return widgets_screen1


def _monitor_count():
    """How many monitors are currently connected (>=1).

    Screens are matched positionally against qtile's detected outputs, so
    a hardcoded list of two is wrong in both directions: with one monitor
    qtile builds a bar it never shows, and with three the third output
    gets no bar at all. `xrandr --listmonitors` reports the post-RandR
    monitor list (what qtile itself lays screens out against), not raw
    connectors, so mirrored outputs correctly count once.
    """
    try:
        out = subprocess.run(
            ["xrandr", "--listmonitors"],
            capture_output=True, text=True, timeout=5,
        ).stdout
        # First line is "Monitors: N"; trust it over counting lines.
        n = int(out.split("\n", 1)[0].split(":")[1])
        return max(n, 1)
    except Exception:
        # No X yet, xrandr missing, or unparsable output. One screen is
        # the safe floor -- returning 0 would leave qtile with no bar at
        # all, which is far worse than a spare unused Screen.
        return 1


def init_screens():
    # Screen 0 is the only one with the systray and the bottom bar.
    screens_list = [
        Screen(
            top=bar.Bar(
                widgets=init_widgets_screen1(),
                size=_s(28),
                margin=[_s(5), _s(10), _s(5), _s(10)],  # top, right, bottom, left
                # IMP: this is the background color of the bar
                background="#11111b00",  # transparent
            ),
            bottom=bar.Bar(
                widgets=init_widgets_list_normaluserbar(),
                size=_s(40),
                margin=[_s(5), _s(10), _s(5), _s(10)],  # top, right, bottom, left
                # IMP: this is the background color of the bar
                background=colors[2],  # transparent
            ),
        ),
    ]
    for _ in range(_monitor_count() - 1):
        screens_list.append(
            Screen(
                top=bar.Bar(
                    widgets=init_widgets_screen2(),
                    size=_s(28),
                    margin=[_s(5), _s(10), _s(5), _s(10)],  # top, right, bottom, left
                    # IMP: this is the background color of the bar
                    background="#11111b00",  # transparent
                ),
            )
        )
    return screens_list


if __name__ in ["config", "__main__"]:
    # Only `screens` is read by qtile. The widgets_list / widgets_screen1 /
    # widgets_screen2 assignments that used to live here were leftovers
    # from the DTOS template: each one built a COMPLETE extra widget tree
    # -- Systray included -- that was never attached to a bar and never
    # _configure()d, then registered its SmartWidgetBoxes in the global
    # instance registry, where the chord hooks would later toggle them.
    # Three dead widget trees per config load, for nothing.
    screens = init_screens()


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
    border_width=_s(2),
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
        # scrcpy renders the phone's real framebuffer, so a tiled window
        # letterboxes a ~9:20 portrait panel into a landscape tile and
        # wastes most of it. Floating keeps the phone's aspect ratio,
        # which is the whole point of looking at it.
        Match(wm_class="scrcpy"),
        # phone_screen's pairing QR. It asks feh for a small centred
        # geometry, and a tiled window discards that request and stretches
        # a 260px code across a whole tile. The Match(title="feh") below
        # does not cover it: this window sets its own title.
        Match(title="Phone pairing QR"),
        Match(title="imv"),  # Match the imv window
        Match(title="feh"),  # Match feh
        Match(wm_class="mpv"),  # mpv
        Match(wm_class="mpvk"),  # mpv
        Match(wm_class="satty"),  # satty
        Match(wm_class="emacs"),  # emacs
        Match(title="link-preview"),  # preview of nvim (qutebrowser edit link)
        # rofi_docs viewer: README / TROUBLESHOOTING / nvim, centred by
        # _float_and_center_docs. wm_class, not title, so the rule wins at
        # group.add() before the window can enter the tiling layout.
        Match(wm_class="docs-view"),
        Match(wm_class="clip-view"),  # copyq_rofi alt+w full-text preview
        Match(wm_class="imv"),  # copyq_rofi alt+w image preview
        # Master-password prompt (rbw / gpg). Sized and centred by
        # _float_and_center_pinentry; this rule is what stops it entering
        # the tiling layout in the first place, since it maps as
        # wm_type=normal and so misses default_float_rules entirely.
        # One entry per flavour: qtile matches the literal class, and
        # unlike the hook there is no prefix matching here.
        Match(wm_class="pinentry-gtk"),
        Match(wm_class="pinentry-gnome3"),
        Match(wm_class="pinentry-qt"),
        Match(wm_class="pinentry"),
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


# ╔───────────────────────────────────────────────────────╗
# │  ORPHANED POPUP SWEEP                                 │
# ╚───────────────────────────────────────────────────────╝
# Every popup in popups/ (wallpaper, wifi, bluetooth, audio, updates, the
# three cheatsheets, the QR) is an Internal window held by ONE module-level
# handle. Lose that handle while the window is still mapped and the popup is
# stranded: on screen, referenced by nothing, and unclosable -- its close()
# takes the "nothing is open" early return forever after.
#
# The wallpaper picker's version of this is fixed at source (see the _CLOSING
# guard in WallpaperPopup.show_wallpaper_picker), but that fix is one module's.
# Nine modules share the pattern, the handle is dropped on any teardown that
# raises, and a reload while a popup is open is a whole extra way to lose one.
# So this is the backstop: whatever the cause, a stranded popup does not
# survive a config load.
#
# Config load is the right moment for it. reload_config re-executes this file
# with the bar and every keybinding rebuilt, so no popup on screen at that
# point is one you can still drive -- it is debris by definition.


def sweep_orphan_popups():
    """Kill Internal windows that are not part of a bar. Returns a count.

    FAIL-SAFE: if no bar window can be identified, this does NOTHING rather
    than guess. Bars are Internal windows too, so an empty "keep" set would
    mean sweeping the bars off the screen -- the one outcome worse than the
    orphan it is cleaning up.
    """
    try:
        keep = set()
        for screen in getattr(qtile, "screens", None) or []:
            for pos in ("top", "bottom", "left", "right"):
                win = getattr(getattr(screen, pos, None), "window", None)
                wid = getattr(win, "wid", None)
                if wid is not None:
                    keep.add(wid)
        if not keep:
            return 0
        killed = 0
        for wid, win in list(getattr(qtile, "windows_map", {}).items()):
            if wid in keep or type(win).__name__ != "Internal":
                continue
            try:
                win.kill()
                killed += 1
            except Exception:
                pass
        if killed:
            # Local import, matching _SafeLengthMixin -- logger is not a
            # module-level name in this config.
            from libqtile.log_utils import logger

            logger.warning("swept %s orphaned popup window(s)", killed)
        return killed
    except Exception:
        return 0


# At import time, so it covers reload_config -- which fires no startup hook.
# qtile is None during the very first config load, when there is nothing to
# sweep anyway.
if qtile is not None:
    sweep_orphan_popups()


# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"
