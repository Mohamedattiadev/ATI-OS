# scripts/mpv_manager.py
import json
import os

from libqtile import hook, qtile
from libqtile.backend.base import FloatStates
from libqtile.log_utils import logger

MPV_CLASSES = ("mpv", "mpvk")

PIP_W = 320
PIP_MARGIN = 20
PIP_GAP = 12  # vertical gap when several PiP windows stack
CENTER_W_RATIO = 0.60
CENTER_H_RATIO = 0.50
DEFAULT_ASPECT = 16 / 9

# Overridable so the test suite can point it at a temp file.
STATE_PATH = os.path.expanduser("~/.cache/qtile/mpv_state.json")

# Every qtile method this module calls on a window. The original version of this
# script silently stopped working when qtile dropped the `cmd_` prefix in 0.22 --
# `cmd_set_size_floating` simply ceased to exist and every call raised inside a
# hook, where the traceback is easy to miss. Checking the contract at startup
# turns the next such rename into a named warning instead of dead behaviour.
REQUIRED_WINDOW_API = (
    "get_wm_class",
    "togroup",
    "keep_above",
    "bring_to_front",
    "enable_floating",
    "set_size_floating",
    "set_position_floating",
)
# Private, so more likely to move than the public names above. _place() already
# falls back to the public sequence if it goes; this just makes it visible.
OPTIONAL_WINDOW_API = ("_enablefloating",)


def _is_mpv(window) -> bool:
    try:
        return any(
            (cls or "").lower() in MPV_CLASSES for cls in (window.get_wm_class() or [])
        )
    except Exception:
        return False


def check_window_api(window_cls=None) -> list:
    """Report qtile window methods this module needs but cannot find."""
    if window_cls is None:
        try:
            from libqtile.backend.x11.window import Window as window_cls
        except Exception:
            logger.warning("mpv_manager: cannot import X11 Window, skipping API check")
            return []

    missing = [n for n in REQUIRED_WINDOW_API if not hasattr(window_cls, n)]
    if missing:
        logger.error(
            "mpv_manager: qtile window API changed -- missing %s. "
            "PiP/centre placement will not work until these are updated.",
            ", ".join(missing),
        )
    absent = [n for n in OPTIONAL_WINDOW_API if not hasattr(window_cls, n)]
    if absent:
        logger.warning(
            "mpv_manager: %s missing; using the slower public placement path "
            "(may show the window moving into position).",
            ", ".join(absent),
        )
    return missing


def load_state(path=None) -> dict:
    """Return {wid(int): {"pip": bool, "aspect": float}}."""
    try:
        with open(path or STATE_PATH) as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {}
    except Exception:
        logger.exception("mpv_manager: could not read state")
        return {}

    if not isinstance(data, dict):
        return {}
    out = {}
    for wid, entry in (data.get("windows") or {}).items():
        if not isinstance(entry, dict):
            continue
        try:
            out[int(wid)] = {
                "pip": bool(entry.get("pip")),
                "aspect": float(entry.get("aspect") or DEFAULT_ASPECT),
            }
        except (TypeError, ValueError):
            continue
    return out


def save_state(state: dict, path=None) -> None:
    target = path or STATE_PATH
    payload = {
        "windows": {
            str(wid): {"pip": bool(e.get("pip")), "aspect": float(e.get("aspect", DEFAULT_ASPECT))}
            for wid, e in (state or {}).items()
        }
    }
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        tmp = target + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(payload, fh)
        os.replace(tmp, target)  # atomic; never leaves a half-written file
    except Exception:
        logger.exception("mpv_manager: could not write state")


def fit(aspect: float, box_w: int, box_h: int):
    """Largest w/h inside the box preserving `aspect`."""
    w = box_w
    h = int(round(w / aspect))
    if h > box_h:
        h = box_h
        w = int(round(h * aspect))
    return int(w), int(h)


class MPVManager:
    """Tracks every mpv window, not just the newest.

    Each entry is {"win", "aspect", "pip"}. Actions target the focused mpv when
    one is focused, otherwise the most recently seen live one -- so with two mpv
    windows open the keybind acts on the one you are looking at instead of
    whichever happened to open last.
    """

    def __init__(self):
        self.tracked = {}  # wid -> {"win": Window, "aspect": float, "pip": bool}
        self.last_wid = None

    # ------------------------------------------------------------------
    # state
    # ------------------------------------------------------------------
    def _persist(self):
        save_state(
            {
                wid: {"pip": e["pip"], "aspect": e["aspect"]}
                for wid, e in self.tracked.items()
            }
        )

    def _live(self):
        """Tracked entries whose window still exists, pruning any that don't."""
        try:
            existing = qtile.windows_map
        except Exception:
            return dict(self.tracked)
        for wid in [w for w in self.tracked if w not in existing]:
            self.tracked.pop(wid, None)
        return self.tracked

    def target(self):
        """The window a keybind should act on: focused mpv, else most recent."""
        live = self._live()
        if not live:
            return None
        try:
            current = qtile.current_window
            if current is not None and current.wid in live:
                return live[current.wid]["win"]
        except Exception:
            pass
        if self.last_wid in live:
            return live[self.last_wid]["win"]
        return next(iter(live.values()))["win"]

    # ------------------------------------------------------------------
    # tracking
    # ------------------------------------------------------------------
    def setup_mpv(self, window):
        if not _is_mpv(window):
            return
        wid = getattr(window, "wid", None)
        if wid is None:
            return
        # Read the aspect BEFORE the first placement: mpv sizes its own window to
        # the video, so this is the only moment the natural ratio is on the
        # window. Everything after this point is a geometry we imposed.
        aspect = self._read_aspect(window)

        # A qtile restart re-manages existing windows, so this hook also fires
        # for an mpv that was already playing. Centring unconditionally there
        # would drop it out of PiP on every Mod+Shift+R.
        saved = load_state().get(wid)
        if saved:
            pip = saved["pip"]
            aspect = saved["aspect"] or aspect
        else:
            pip = self._looks_like_pip(window)

        self.tracked[wid] = {"win": window, "aspect": aspect, "pip": pip}
        self.last_wid = wid
        self.apply(window)
        self._persist()

    @staticmethod
    def _read_aspect(window) -> float:
        try:
            w, h = window.width, window.height
            if w > 0 and h > 0:
                return w / h
        except Exception:
            pass
        return DEFAULT_ASPECT

    @staticmethod
    def _looks_like_pip(window) -> bool:
        """Fallback PiP detection for when there is no saved state.

        Width only, deliberately. A restart preserves the window's size but qtile
        re-centres floating windows as it adopts them (Floating's
        compute_client_position) -- a PiP window at 1026,508 comes back at
        523,258 -- so position cannot be part of the test. Verified by logging
        the geometry seen in this hook across a restart.
        """
        try:
            return window.width == PIP_W
        except Exception:
            return False

    def on_mpv_killed(self, window):
        wid = getattr(window, "wid", None)
        if wid in self.tracked:
            self.tracked.pop(wid, None)
            if self.last_wid == wid:
                self.last_wid = next(iter(self.tracked), None)
            self._persist()
            # Remaining PiP windows shift down into the freed slot.
            self.restack_pips()

    def adopt_existing(self):
        """Re-attach to mpv windows that outlived a qtile restart.

        client_managed only fires for newly mapped windows, so without this a
        restart left nothing tracked and the PiP keybind did nothing until mpv
        was reopened.
        """
        try:
            saved = load_state()
            for win in qtile.windows_map.values():
                if type(win).__name__ == "Internal" or not _is_mpv(win):
                    continue
                wid = win.wid
                if wid in self.tracked:
                    continue
                entry = saved.get(wid)
                self.tracked[wid] = {
                    "win": win,
                    "aspect": (entry or {}).get("aspect") or self._read_aspect(win),
                    "pip": (entry or {}).get("pip", self._looks_like_pip(win)),
                }
                self.last_wid = wid
        except Exception:
            logger.exception("mpv_manager: adopt_existing failed")

    # ------------------------------------------------------------------
    # placement
    # ------------------------------------------------------------------
    @staticmethod
    def _screen(window):
        """The screen the window is actually on.

        Not qtile.current_screen: that is the *focused* screen, so with a second
        monitor a PiP window living on screen 2 would be positioned against
        screen 1's bottom-right corner.
        """
        try:
            group = getattr(window, "group", None)
            if group is not None and group.screen is not None:
                return group.screen
        except Exception:
            pass
        return qtile.current_screen

    @staticmethod
    def _place(window, x, y, w, h):
        """Float + move + resize in a single placement.

        The obvious sequence (enable_floating, then set_size_floating, then
        set_position_floating) re-places the window three times and renders the
        intermediate steps -- the same visible drift that had to be fixed for the
        TODOS summary window. _enablefloating() assigns the geometry and calls
        place() exactly once.
        """
        if window is None:
            return
        try:
            window._enablefloating(
                x=x, y=y, w=w, h=h, new_float_state=FloatStates.FLOATING
            )
        except AttributeError:
            logger.warning("mpv_manager: _enablefloating missing, using public API")
            try:
                window.enable_floating()
                window.set_size_floating(w, h)
                window.set_position_floating(x, y)
            except Exception:
                logger.exception("mpv_manager: public placement failed")
                return
        except Exception:
            logger.exception("mpv_manager: placement failed")
            return
        try:
            window.bring_to_front()
        except Exception:
            pass

    def _pip_order(self, screen):
        """PiP windows on this screen, oldest first -- defines the stack order."""
        out = []
        for wid in sorted(self._live()):
            entry = self.tracked[wid]
            if not entry["pip"]:
                continue
            if self._screen(entry["win"]) is screen:
                out.append(wid)
        return out

    def set_pip_mode(self, window):
        entry = self.tracked.get(getattr(window, "wid", None))
        if entry is None:
            return
        screen = self._screen(window)
        # Height follows the video, so a 4:3 clip is no longer letterboxed
        # inside a hardcoded 5:3 box.
        w, h = fit(entry["aspect"], PIP_W, screen.height)

        # Stack multiple PiP windows upward from the corner instead of piling
        # them all on the same spot.
        offset = 0
        for wid in self._pip_order(screen):
            if wid == window.wid:
                break
            other = self.tracked[wid]
            _, oh = fit(other["aspect"], PIP_W, screen.height)
            offset += oh + PIP_GAP

        self._place(
            window,
            screen.x + screen.width - w - PIP_MARGIN,
            screen.y + screen.height - h - PIP_MARGIN - offset,
            w,
            h,
        )
        try:
            # Keep it above the other floats (qdrop, the summary window, dialogs)
            # -- a PiP that can be covered is not much of a PiP.
            window.keep_above(True)
        except Exception:
            logger.exception("mpv_manager: keep_above failed")

    def set_center_mode(self, window):
        entry = self.tracked.get(getattr(window, "wid", None))
        if entry is None:
            return
        # Separate try blocks on purpose: these are independent, and sharing one
        # meant a togroup() failure silently skipped keep_above(False), leaving
        # the window pinned above everything with no way back. Caught by
        # mpv_manager_test.py.
        try:
            window.togroup(qtile.current_group.name)
        except Exception:
            logger.exception("mpv_manager: togroup failed")
        try:
            window.keep_above(False)
        except Exception:
            logger.exception("mpv_manager: keep_above(False) failed")

        screen = self._screen(window)  # after togroup: the new group's screen
        w, h = fit(
            entry["aspect"],
            int(screen.width * CENTER_W_RATIO),
            int(screen.height * CENTER_H_RATIO),
        )
        self._place(
            window,
            screen.x + (screen.width - w) // 2,
            screen.y + (screen.height - h) // 2,
            w,
            h,
        )

    def apply(self, window):
        entry = self.tracked.get(getattr(window, "wid", None))
        if entry is None:
            return
        if entry["pip"]:
            self.set_pip_mode(window)
        else:
            self.set_center_mode(window)

    def restack_pips(self):
        """Re-place every PiP window so the stack has no gaps."""
        for wid in list(self._live()):
            entry = self.tracked.get(wid)
            if entry and entry["pip"]:
                self.set_pip_mode(entry["win"])

    def reapply(self):
        """Re-assert every window's mode (after a screen/resolution change)."""
        for wid in list(self._live()):
            self.apply(self.tracked[wid]["win"])

    def follow_to_new_group(self):
        moved = False
        for wid in list(self._live()):
            entry = self.tracked[wid]
            if not entry["pip"]:
                continue
            try:
                entry["win"].togroup(qtile.current_group.name)
                moved = True
            except Exception:
                logger.exception("mpv_manager: failed to move MPV window")
        if moved:
            # togroup re-runs the layout, so re-assert the PiP geometry after it.
            self.restack_pips()

    def toggle_pip_mode(self, _qtile=None):
        window = self.target()
        if window is None:
            self.adopt_existing()
            window = self.target()
            if window is None:
                return
        entry = self.tracked[window.wid]
        entry["pip"] = not entry["pip"]
        self.last_wid = window.wid
        self.apply(window)
        self.restack_pips()  # the others close the gap this one left
        self._persist()


mpv_manager = MPVManager()


# client_managed, not client_new: manage() fires client_new before the window
# joins a group (core/manager.py:800 vs :810), so at that point there is no
# group/screen -- togroup() and any floating placement have nothing to act on.
@hook.subscribe.client_managed
def _mpv_client_managed(window):
    mpv_manager.setup_mpv(window)


@hook.subscribe.client_killed
def _mpv_client_killed(window):
    mpv_manager.on_mpv_killed(window)


@hook.subscribe.setgroup
def _mpv_setgroup():
    mpv_manager.follow_to_new_group()


@hook.subscribe.startup_complete
def _mpv_startup_complete():
    check_window_api()
    mpv_manager.adopt_existing()
    mpv_manager.reapply()


@hook.subscribe.screen_change
def _mpv_screen_change(_event=None):
    # Resolution/monitor change moves the bottom-right corner; without this a
    # PiP window keeps its old coordinates and can end up partly off-screen.
    mpv_manager.reapply()
