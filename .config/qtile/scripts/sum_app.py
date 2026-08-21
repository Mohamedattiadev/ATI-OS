import os

from libqtile.backend.base import FloatStates

SUM_PULL_CMD = os.path.expanduser("~/.config/AtiScriptsV1/ati-simplenote-push") + " --pull"

FLOAT_W_RATIO = 0.55
FLOAT_H_RATIO = 0.65
FLOAT_W_MIN = 600
FLOAT_H_MIN = 400

SUM_WM_CLASS = "sum-md"


def is_sum_window(win):
    """Identify the summary window by WM_CLASS, falling back to the title.

    WM_CLASS is set when the X window is created, so it is already correct on the
    MapRequest that qtile turns into group.add() -- which is where float rules are
    evaluated (group.py:229). WM_NAME is not: alacritty applies --title in a race
    with qtile reading the property, so a title-only rule loses often enough that
    the window gets tiled for a frame before anything can float it.
    """
    try:
        classes = [c.lower() for c in (win.get_wm_class() or [])]
        if SUM_WM_CLASS in classes:
            return True
    except Exception:
        pass
    try:
        return "sum.md" in (win.name or "").lower()
    except Exception:
        return False


def float_center_sum(win):
    """Show the summary window floating and centred, in a single placement.

    Deliberately goes through _enablefloating() rather than the public API. The
    obvious sequence -- toggle_minimize() (which un-minimizes by setting
    `floating = False`, backend/x11/window.py:1857), then floating = True, then
    set_size_floating(), then center() -- lays the window out in MonadTall first
    and re-places it three times. A screen recording of that showed the window
    appearing small and off-centre and then growing into position over ~8 frames
    (~0.25s), which is the glitch.

    _enablefloating() assigns the geometry and calls place() exactly once
    (_reconfigure_floating, :1941), and restores from MINIMIZED on the way, so the
    window's first painted frame is already the final one.
    """
    try:
        group = getattr(win, "group", None)
        screen = group.screen if group and group.screen else None
        if screen is None:
            return
        w = max(FLOAT_W_MIN, int(screen.width * FLOAT_W_RATIO))
        h = max(FLOAT_H_MIN, int(screen.height * FLOAT_H_RATIO))
        win._enablefloating(
            x=screen.x + (screen.width - w) // 2,
            y=screen.y + (screen.height - h) // 2,
            w=w,
            h=h,
            new_float_state=FloatStates.FLOATING,
        )
        win.bring_to_front()
    except Exception:
        pass


def pull_sum(qtile):
    """Fetch anything typed on the phone before the window comes up.

    qtile.spawn(), never a blocking call: qtile's event loop is single-threaded,
    and ati-simplenote-push allows itself up to 15s on a stalled connection. Waiting
    for it here would freeze the whole WM -- every key, every redraw -- for that
    long, on a keybind pressed dozens of times a day.

    The consequence of not waiting is that the pull may land a moment after nvim
    has already read the file. That is what the `autoread` + `checktime` autocmd
    in nvim/lua/config/autocmds.lua is for: the buffer refreshes itself when the
    file changes underneath it, and refuses to clobber unsaved edits.
    """
    try:
        qtile.spawn(SUM_PULL_CMD)
    except Exception:
        # A missing script or a broken spawn must never stop the window opening.
        pass


def toggle_or_spawn_sum(qtile, myTerm, sum_file):
    for group in qtile.groups:
        for win in group.windows:
            if is_sum_window(win):

                # 🚀 CASE 1: window is on another workspace
                if win.group != qtile.current_group:
                    pull_sum(qtile)
                    win.togroup(qtile.current_group.name)
                    # float_center_sum also un-minimizes -- no toggle_minimize()
                    # here, that is what caused the tiled intermediate frame.
                    float_center_sum(win)
                    win.focus()
                    return  # ⬅️ HARD STOP (no toggle logic)

                # 🚀 CASE 2: same workspace
                if win.minimized:
                    pull_sum(qtile)
                    float_center_sum(win)
                    win.focus()

                elif qtile.current_window != win:
                    pull_sum(qtile)
                    win.focus()

                else:
                    # focused → minimize
                    win.toggle_minimize()
                    return

                float_center_sum(win)
                return

    # 🚀 CASE 3: not running
    pull_sum(qtile)
    # --class gives this window its own WM_CLASS so the float rule matches on the
    # MapRequest itself; without it the window tiles for a frame before floating.
    #
    # --name AND --class, rather than alacritty's single `--class a,b`. kitty
    # splits the WM_CLASS pair across two flags -- --name is the instance
    # half, --class is the class half -- and silently ignores a comma-joined
    # value, which would leave the window as ("kitty", "kitty") and drop it
    # straight into the tiling layout. Both halves are set to SUM_WM_CLASS so
    # is_sum_window() and the float rule match whichever they read.
    qtile.spawn(
        f"{myTerm} --name {SUM_WM_CLASS} --class {SUM_WM_CLASS} --title sum.md "
        f"-e nvim -c':set nonumber norelativenumber' {sum_file}"
    )
