# scripts/above_fullscreen.py
"""Keep an app that opens during fullscreen visible until fullscreen ends.

X11's recommended stacking order gives a focused fullscreen window the top
layer, so an app launched while something is fullscreen maps underneath it and
is simply not there as far as the screen is concerned. On a config with
`follow_mouse_focus = True` that is worse than it sounds: the fullscreen
window covers the entire screen, so every pointer move lands on it, refocuses
it and re-buries whatever just opened. The new window cannot be hovered back
-- the only ways to reach it are the keyboard or dropping fullscreen. What it
looks like from the outside is an app that opened, flashed, and vanished.

So a window that appears while a fullscreen window is on its group is
PROMOTED above the fullscreen layer, and stays there until one of three
things happens:

  * it is closed, or
  * nothing on its group is fullscreen any more, or
  * (falling out of the above) fullscreen is toggled off and on -- which is
    the escape hatch: two presses of Mod+f and the fullscreen window is clean
    again, because the promotions were released the moment it left fullscreen
    and a fresh fullscreen starts with none.

Nothing is promoted retroactively and nothing is promoted permanently, which
is what keeps this from becoming a window stuck over a video with no way to
shift it.

The promoted layer is the scratchpad one rather than a layer of its own,
because there is no room for one: layers are compared as 6-tuples of bools
where smaller means higher, and no such tuple sorts strictly between the
fullscreen layer (F,F,F,F,T,F) and the scratchpad layer (F,F,F,F,F,T).
Sharing with the dropdowns is harmless -- within a layer the order is
whichever was raised last.

The registry lives in this module, not in config.py, on purpose: a module is
a singleton in sys.modules, so the layering patch and these hooks still share
one dict after `reload_config` re-executes config.py into a fresh namespace.
"""

from libqtile import hook, qtile
from libqtile.log_utils import logger

# wid -> Window, for every window currently promoted above a fullscreen one.
# Keyed by wid but holding the window too: the X server reuses wids, and a
# promotion must not survive onto whatever inherits the number.
_promoted = {}

_reassert_pending = False

# Promotions are off until qtile says it has finished starting. A restart
# re-manages every pre-existing window through client_managed -- the startup
# scan in backend/x11/core.py calls qtile.manage() for each window it finds --
# and it does that while whatever was fullscreen before the restart still is.
# Without this gate every window on that group would be promoted at once, and
# then released again a moment later, and the resulting burst of restacking
# lands right on top of the session restore this config runs on restart
# (_save_layout_state / _save_window_group_state). A promotion is meant to
# mark "this opened DURING fullscreen"; a restart is not that.
_started = False


def is_promoted(win):
    """True if `win` is currently held above the fullscreen layer."""
    if not _promoted:
        return False
    return _promoted.get(getattr(win, "wid", None)) is win


def _fullscreen_in(group):
    """The fullscreen window on `group`, or None."""
    for win in getattr(group, "windows", ()) or ():
        if getattr(win, "fullscreen", False):
            return win
    return None


def _restack(win):
    """Re-run qtile's own layer placement for a window we just re/de-moted.

    up=True in both directions -- change_layer() works out which way the
    window actually moved by comparing the layer it reports now against the
    one it reported last (its `previous_layer`), so the demotion path drops it
    back beside its peers without any help from here.
    """
    try:
        win.change_layer(up=True)
    except Exception:
        logger.exception("above_fullscreen: could not restack %r", getattr(win, "name", win))


def _is_covered(win, stack):
    """True if `win` has sunk below the fullscreen window it was promoted over."""
    group = getattr(win, "group", None)
    covering = _fullscreen_in(group) if group is not None else None
    if covering is None:
        return False
    try:
        return stack.index(win.wid) < stack.index(covering.wid)
    except ValueError:  # one of them is not in the server's stack
        return False


def reassert():
    """Put back any promoted window that has sunk below its fullscreen window.

    The order check is not an optimisation, it is the fix for a visible
    glitch. This runs on every focus change, and with follow_mouse_focus that
    is every time the pointer crosses a window edge. change_layer() is not
    cheap -- it queries the whole server stack and, on the branch this takes,
    issues a ConfigureWindow for every window it has to push back down. Doing
    that unconditionally several times a second had the compositor redrawing
    constantly, which is what the flicker was. Asking first costs one round
    trip and, in the steady state, sends nothing at all.
    """
    if not _promoted:
        return
    try:
        stack = list(qtile.core._root.query_tree())
    except Exception:
        # Can't read the stack, so can't tell -- do the work rather than
        # leave a window buried.
        stack = None
    for win in list(_promoted.values()):
        if stack is not None and not _is_covered(win, stack):
            continue
        _restack(win)


def reassert_soon():
    """reassert(), deferred to the next turn of the event loop.

    Promoting from inside client_managed is not enough on its own: qtile is
    still mapping the window when that hook runs, and the placement pass that
    follows -- Group.add -> layout_all -> Floating.configure -> place/unhide
    -- restacks around it and leaves the fullscreen window back on top.
    Measured: promoting inline left the new window at stack index 68 with the
    fullscreen window at 70; the same change_layer() call one loop turn later
    put it at 70 with the fullscreen window at 69.

    Coalesced, since one window opening fires several of the hooks below and
    the work is identical each time.
    """
    global _reassert_pending
    if _reassert_pending or not _promoted:
        return
    _reassert_pending = True
    try:
        qtile.call_later(0, _deferred_reassert)
    except Exception:
        # No loop to defer onto: do it now rather than leave the flag set and
        # every later call a silent no-op.
        _reassert_pending = False
        reassert()


def _deferred_reassert():
    global _reassert_pending
    _reassert_pending = False
    reassert()


@hook.subscribe.client_managed
def _promote_new_window(window):
    if not _started:
        return
    group = getattr(window, "group", None)
    if group is None:
        return
    covering = _fullscreen_in(group)
    # `covering is window` for an app that maps already fullscreen (a game,
    # a video player started with --fs). It is not being covered by anything;
    # it IS the cover.
    if covering is None or covering is window:
        return
    wid = getattr(window, "wid", None)
    if wid is None:
        return
    _promoted[wid] = window
    reassert_soon()


@hook.subscribe.client_focus
def _hold_promotions_on_focus(_window):
    # The case this exists for: hovering back onto the fullscreen window
    # refocuses it, which returns it to the fullscreen layer and restacks it.
    # Nothing re-runs change_layer() on the promoted window at that point, so
    # it has to be re-asserted here or the app sinks the first time the
    # pointer leaves it.
    reassert_soon()


@hook.subscribe.client_killed
def _forget_closed_window(window):
    _promoted.pop(getattr(window, "wid", None), None)


@hook.subscribe.float_change
def _release_when_fullscreen_ends():
    """Drop promotions whose fullscreen window is no longer fullscreen.

    float_change is the hook for this: entering and leaving fullscreen both
    go through _reconfigure_floating/floating, which fire it (x11/window.py).
    Leaving fires it BEFORE the window's own change_layer() call, and by that
    point _float_state is already updated, so the check below sees the truth.

    Checked per group rather than globally, so a fullscreen window on the
    second monitor does not keep the first monitor's promotions alive.
    """
    if not _promoted:
        return
    for wid, win in list(_promoted.items()):
        group = getattr(win, "group", None)
        if group is not None and _fullscreen_in(group) is not None:
            continue
        del _promoted[wid]
        _restack(win)


@hook.subscribe.startup_complete
def _enable_promotions():
    """Open for business, once the startup scan is out of the way.

    Nothing is restacked here on purpose. The gate means there is nothing to
    undo, and a restack burst at this exact moment is what would disturb the
    window order the restart has just finished restoring. _promoted is
    cleared only as belt and braces, for the case where something managed a
    window before this fired.
    """
    global _started
    _started = True
    _promoted.clear()
