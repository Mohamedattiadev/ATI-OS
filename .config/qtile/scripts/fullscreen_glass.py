# scripts/fullscreen_glass.py
"""Nothing bleeds through the glassy terminal while it's fullscreen --
and the terminal keeps its glass, unlike this module's first cut.

Reported behaviour: fullscreening a glassy kitty (background_opacity < 1 --
see _term_opacity() in config.py, the same knob Hyprland's $term_opacity
drives) let the qtile bar, and any other window still mapped underneath it,
show straight through. X11 has no equivalent of Hyprland's "a fullscreen
window is the only thing on the workspace" guarantee: change_layer() only
RAISES the fullscreen window above its siblings (see the layering patch in
config.py, and above_fullscreen.py for the related "new window opened
during fullscreen" problem) -- every other mapped window is still sitting
in the stack underneath it, and picom composites whatever is genuinely
there regardless of what visually covers it.

First attempt here forced the TERMINAL itself opaque on fullscreen --
wrong, reported back as "the terminal not glassy like hyper in full
screen". Hyprland's own fix for the same original report (hypr/
hyprglass.conf) does not touch the terminal's opacity either: it disables
glass on fullscreen for every app EXCEPT kitty-family terminals, precisely
because a fullscreen window there has nothing behind it to bleed --
Hyprland's compositor does not render workspace siblings at all while one
is up. That guarantee is what's missing under X11, so this recreates it
directly instead: while something is fullscreen, the bar and every OTHER
mapped window sharing its group are pushed to _NET_WM_WINDOW_OPACITY 0 --
still mapped, still tiled, just contributing nothing to the composite, so
picom has nothing left behind the glass but the desktop. Their real
opacity is restored the moment fullscreen ends. The fullscreen window's
own opacity is never touched.

Windows meant to stay visible OVER a fullscreen window are left alone:
scratchpad dropdowns (ScratchPad.dropdowns) and anything above_fullscreen
has promoted (is_promoted) -- both already carry their own "float above
this" story and zeroing their opacity would just be a second, conflicting
one.

float_change is the right hook -- see above_fullscreen.py's docstring on
the same hook for the proof: entering and leaving fullscreen both run
through _reconfigure_floating/floating in the X11 backend, and both fire
it, in that order, with the window's fullscreen state already updated by
the time this runs.
"""

from libqtile import hook, qtile
from libqtile.log_utils import logger
from libqtile.scratchpad import ScratchPad as _ScratchPadGroup

from scripts.above_fullscreen import is_promoted

# wid -> (window, opacity it had before this module touched it). Bars are
# keyed by id(bar) instead, since a Bar has no wid.
_dimmed_windows = {}
_dimmed_bars = {}


def _owned_by_scratchpad(win):
    """Same registry walk as config.py's own layering patch -- duplicated
    rather than imported, since that copy lives inside a guarded `if not
    getattr(...)` block in config.py and isn't a module-level name."""
    qtile_obj = getattr(win, "qtile", None)
    if qtile_obj is None:
        return False
    for grp in qtile_obj.groups:
        if isinstance(grp, _ScratchPadGroup):
            for toggler in grp.dropdowns.values():
                if toggler.window is win:
                    return True
    return False


def _fullscreen_in(group):
    for win in getattr(group, "windows", ()) or ():
        if getattr(win, "fullscreen", False):
            return win
    return None


_enforcing_single_fullscreen = False


def _enforce_single_fullscreen(group):
    """qtile core has no "one fullscreen per group" rule -- Mod+f only
    flips the FOCUSED window's own flag, so alt-tabbing to a second
    tiled window while a first is still fullscreen and pressing Mod+f
    there leaves BOTH windows reporting fullscreen=True.

    Confirmed live: with two such windows in one group, _fullscreen_in()
    below picks whichever happens first in group.windows on a given
    _sync() call -- and that order tracks focus history, so it is not the
    same window call to call. Whichever one loses the pick is still
    covering the whole screen (it IS fullscreen, at 0,0 screen-size) but
    gets treated as an ordinary sibling and dimmed to opacity 0 by the
    loop below. Across a couple of float_change firings both windows had
    taken a turn losing the pick, and both ended up at opacity 0 -- desktop
    wallpaper full-screen, nothing rendered, no way back short of an
    opacity reset. This is the actual mechanism behind that.

    Fix at the source: a group may only have one real fullscreen window.
    Whichever is current_window wins (that is the one Mod+f was just
    pressed on); every other fullscreen window in the group is dropped
    back out of fullscreen the normal way, through disable_fullscreen(),
    so its own float_info/geometry restore runs too, not just its flag.
    """
    global _enforcing_single_fullscreen
    if _enforcing_single_fullscreen:
        return
    fs_wins = [w for w in getattr(group, "windows", ()) or () if getattr(w, "fullscreen", False)]
    if len(fs_wins) <= 1:
        return
    current = getattr(group, "current_window", None)
    keep = current if current in fs_wins else fs_wins[-1]
    _enforcing_single_fullscreen = True
    try:
        for win in fs_wins:
            if win is keep:
                continue
            try:
                win.disable_fullscreen()
            except Exception:
                logger.exception(
                    "fullscreen_glass: could not clear duplicate fullscreen on %r",
                    getattr(win, "name", win),
                )
    finally:
        _enforcing_single_fullscreen = False


def _dim_window(win):
    wid = getattr(win, "wid", None)
    if wid is None or wid in _dimmed_windows:
        return
    try:
        prev = win.opacity
        win.opacity = 0.0
    except Exception:
        logger.exception("fullscreen_glass: could not dim %r", getattr(win, "name", win))
        return
    _dimmed_windows[wid] = (win, prev)


def _undim_window(wid):
    entry = _dimmed_windows.pop(wid, None)
    if entry is None:
        return
    win, prev = entry
    try:
        win.opacity = prev
    except Exception:
        logger.exception("fullscreen_glass: could not restore %r", getattr(win, "name", win))


def _dim_bar(bar_):
    if bar_ is None or not getattr(bar_, "window", None):
        return
    key = id(bar_)
    if key in _dimmed_bars:
        return
    try:
        prev = bar_.window.opacity
        bar_.window.opacity = 0.0
    except Exception:
        logger.exception("fullscreen_glass: could not dim bar")
        return
    _dimmed_bars[key] = (bar_, prev)


def _undim_bar(key):
    entry = _dimmed_bars.pop(key, None)
    if entry is None:
        return
    bar_, prev = entry
    try:
        bar_.window.opacity = prev
    except Exception:
        logger.exception("fullscreen_glass: could not restore bar")


def _sync():
    for grp in qtile.groups:
        _enforce_single_fullscreen(grp)

    covered_groups = set()
    for grp in qtile.groups:
        fs_win = _fullscreen_in(grp)
        if fs_win is None:
            continue
        covered_groups.add(grp)

        # fs_win itself can already be sitting in _dimmed_windows -- it was
        # an ordinary dimmed sibling a moment ago, before
        # _enforce_single_fullscreen() above just handed IT the fullscreen
        # slot. The loop below skips dimming it (it IS fs_win now), but
        # skipping a dim is not the same as reversing the old one: nothing
        # else here ever revisits an already-dimmed window once its group
        # is still covered, so without this it stays opacity 0 forever --
        # the fullscreen window rendering as nothing but bare wallpaper,
        # confirmed live via the exact enable-fullscreen-on-B-while-A-is-
        # fullscreen sequence above.
        _undim_window(getattr(fs_win, "wid", None))

        for win in grp.windows:
            if win is fs_win:
                continue
            if _owned_by_scratchpad(win) or is_promoted(win):
                continue
            _dim_window(win)

        screen = getattr(grp, "screen", None)
        if screen is not None:
            _dim_bar(getattr(screen, "top", None))
            _dim_bar(getattr(screen, "bottom", None))

    # Undim anything this module dimmed whose group is no longer covered.
    for wid, (win, _prev) in list(_dimmed_windows.items()):
        if getattr(win, "group", None) not in covered_groups:
            _undim_window(wid)

    for key, (bar_, _prev) in list(_dimmed_bars.items()):
        screen = getattr(bar_, "screen", None)
        group = getattr(screen, "group", None) if screen is not None else None
        if group not in covered_groups:
            _undim_bar(key)


@hook.subscribe.float_change
def _sync_fullscreen_glass():
    _sync()


@hook.subscribe.client_killed
def _forget_closed_window(win):
    _dimmed_windows.pop(getattr(win, "wid", None), None)


@hook.subscribe.startup_complete
def _seed_fullscreen_glass():
    # A restart (theme change, Mod+Shift+R) landing while something is
    # already fullscreen starts this module with empty state -- without
    # this it would never learn those windows/bars are its responsibility,
    # and leaving fullscreen later would leave them dimmed for good.
    #
    # The inverse also happens, and is worse: a restart wipes
    # _dimmed_windows (in-memory only) but NOT the X server, which still
    # has whatever _NET_WM_WINDOW_OPACITY the previous process's _dim_window
    # set. A window left fullscreen for a while, then un-fullscreened
    # through a path that fires float_change on a qtile process that has
    # since restarted, has no record anywhere telling anyone to undim it --
    # confirmed live: three kitty windows stuck at opacity 0 with nothing
    # covering their group, invisible with no way back short of this sweep.
    # Reset anything orphaned that way BEFORE _sync() below decides what
    # actually needs dimming right now.
    for grp in qtile.groups:
        fs_win = _fullscreen_in(grp)
        for win in getattr(grp, "windows", ()) or ():
            if win is fs_win:
                continue
            try:
                if win.opacity == 0.0:
                    win.opacity = 1.0
            except Exception:
                continue
    _sync()
