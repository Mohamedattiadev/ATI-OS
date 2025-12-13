
# scripts/mpv_manager.py
import logging
from typing import Optional
from libqtile.backend.base import Window
from libqtile import hook, qtile

logger = logging.getLogger(__name__)

class MPVManager:
    def __init__(self):
        self.current_mpv: Optional[Window] = None
        self.is_in_pip_mode: bool = False

    def setup_mpv(self, window: Window):
        wm_class = window.get_wm_class()
        if wm_class and any(cls.lower() in ['mpv', 'mpvk'] for cls in wm_class):
            self.current_mpv = window
            self.is_in_pip_mode = False
            window.cmd_enable_floating()
            self.set_center_mode()

    def on_mpv_killed(self, window: Window):
        if self.current_mpv and self.current_mpv.wid == window.wid:
            self.current_mpv = None
            self.is_in_pip_mode = False

    def follow_to_new_group(self):
        if self.current_mpv and self.is_in_pip_mode:
            try:
                self.current_mpv.togroup(qtile.current_group.name)
            except Exception as e:
                logger.error(f"Failed to move MPV window: {e}")

    def set_center_mode(self):
        if not self.current_mpv:
            return
        screen = qtile.current_screen
        width = int(screen.width * 0.60)
        height = int(screen.height * 0.50)
        x = screen.x + (screen.width - width) // 2
        y = screen.y + (screen.height - height) // 2
        self.current_mpv.cmd_set_size_floating(width, height)
        self.current_mpv.cmd_set_position_floating(x, y)
        self.current_mpv.togroup(qtile.current_group.name)

    def set_pip_mode(self):
        if not self.current_mpv:
            return
        screen = qtile.current_screen
        width, height = 250, 150
        margin = 20
        x = screen.x + screen.width - width - margin
        y = screen.y + screen.height - height - margin
        self.current_mpv.cmd_set_size_floating(width, height)
        self.current_mpv.cmd_set_position_floating(x, y)
        self.current_mpv.cmd_bring_to_front()

    def toggle_pip_mode(self, qtile):
        if not self.current_mpv:
            return
        self.is_in_pip_mode = not self.is_in_pip_mode
        if self.is_in_pip_mode:
            self.set_pip_mode()
        else:
            self.set_center_mode()

mpv_manager = MPVManager()

@hook.subscribe.client_new
def _(window):
    mpv_manager.setup_mpv(window)

@hook.subscribe.client_killed
def _(window):
    mpv_manager.on_mpv_killed(window)

@hook.subscribe.setgroup
def _():
    mpv_manager.follow_to_new_group()
