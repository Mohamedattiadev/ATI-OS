#!/usr/bin/env python3
"""
ewmh-state.py — the island's compositor feed for the X11 session.

WHY THIS EXISTS
---------------
The island's workspace number and window strip are wired to
`Quickshell.Hyprland` and to Wayland's foreign-toplevel protocol. Under qtile
BOTH are empty, and neither says so:

  * `Hyprland.focusedMonitor` is null, so `HyprlandWorkspaceTracker`'s
    `monitorWorkspaceId` is 0, `syncWorkspaceState()` returns early forever,
    and `CompositorWorkspaceTracker`'s initial `currentWorkspaceId: 1` is
    what stays on screen. Measured: qtile on group "4", island drawing "1",
    across a five-group sweep in which the digit never once changed.
  * `ToplevelManager.toplevels` is the Wayland protocol and reports nothing
    on X11, so the window strip is permanently empty.

Neither is a crash and neither logs. `CompositorBackend.compositor` reports
"hyprland" even in a qtile session — probed — so the island cannot even tell
that it is being lied to.

WHY EWMH RATHER THAN `qtile cmd-obj`
------------------------------------
qtile is EWMH-compliant and publishes everything the island needs on the root
window: `_NET_CURRENT_DESKTOP`, `_NET_DESKTOP_NAMES`, `_NET_CLIENT_LIST`,
`_NET_ACTIVE_WINDOW`, plus `_NET_WM_DESKTOP`/`WM_CLASS`/`_NET_WM_NAME` per
client. That beats the two alternatives:

  * `qtile cmd-obj` is a Python CLI — ~150 ms and a whole interpreter per
    call. Polling it fast enough to feel live would burn a core.
  * qtile hooks pushing into the island over IPC would work, but needs
    surgery on a 3000-line config.py and only ever serves qtile.

EWMH is event-driven, costs one process, and is what every other X11 WM
publishes too, so this feed is not qtile-specific.

OUTPUT
------
One JSON object per line on stdout, flushed, emitted on every relevant change
and once at startup:

  {"desktop": 3, "names": ["1","2",...], "active": 40108046,
   "windows": [{"id": 52428814, "desktop": 10, "appId": "kitty",
                "title": "~", "normal": true}]}

`desktop` indexes `names`. qtile's group LABELS are not exported over EWMH —
`_NET_DESKTOP_NAMES` carries the group names ("1".."9", "S", "scratchpad"),
which is what the island wants to draw anyway.

TRAP, and it is the reason clients are subscribed individually: a window's
title and its desktop change WITHOUT any root property changing. Watching
only the root gives a strip whose titles are frozen at the moment the window
opened. Every client therefore gets its own PropertyChange mask, refreshed
whenever _NET_CLIENT_LIST changes.
"""

import json
import select
import struct
import sys

import xcffib
import xcffib.xproto as xp

ATOM_NAMES = (
    "_NET_CURRENT_DESKTOP",
    "_NET_DESKTOP_NAMES",
    "_NET_CLIENT_LIST",
    "_NET_ACTIVE_WINDOW",
    "_NET_WM_DESKTOP",
    "_NET_WM_NAME",
    "_NET_WM_WINDOW_TYPE",
    "_NET_WM_WINDOW_TYPE_NORMAL",
    "_NET_WM_WINDOW_TYPE_DIALOG",
    "UTF8_STRING",
)

# A property change on any of these is worth a fresh snapshot. WM_NAME and
# WM_CLASS are the ICCCM spellings, kept because not every X client sets the
# _NET_ ones — Java apps in particular.
WATCHED = {
    "_NET_CURRENT_DESKTOP",
    "_NET_DESKTOP_NAMES",
    "_NET_CLIENT_LIST",
    "_NET_ACTIVE_WINDOW",
    "_NET_WM_DESKTOP",
    "_NET_WM_NAME",
    "WM_NAME",
    "WM_CLASS",
}


class Ewmh:
    def __init__(self):
        self.conn = xcffib.connect()
        self.root = self.conn.get_setup().roots[self.conn.pref_screen].root
        self.atom = {}
        for name in ATOM_NAMES + ("WM_NAME", "WM_CLASS", "STRING"):
            self.atom[name] = self._intern(name)
        # Reverse map, so a PropertyNotify's atom can be named without a
        # round trip per event.
        self.named = {v: k for k, v in self.atom.items()}
        self.watched_atoms = {self.atom[n] for n in WATCHED if n in self.atom}
        self.subscribed = set()

    def _intern(self, name):
        raw = name.encode()
        return self.conn.core.InternAtom(False, len(raw), raw).reply().atom

    def _prop(self, window, atom, length=4096):
        """Raw property bytes, or None. Windows die mid-query constantly —
        every client read here races the window being closed, so BadWindow is
        an ordinary outcome and not an error worth reporting."""
        try:
            reply = self.conn.core.GetProperty(
                False, window, atom, xp.GetPropertyType.Any, 0, length
            ).reply()
        except Exception:
            return None
        if reply is None or reply.value_len == 0:
            return None
        return bytes(bytearray(reply.value.buf()))

    def cardinals(self, window, name):
        raw = self._prop(window, self.atom[name])
        if not raw:
            return []
        count = len(raw) // 4
        return list(struct.unpack("<%dI" % count, raw[: count * 4]))

    def cardinal(self, window, name, default=-1):
        values = self.cardinals(window, name)
        return values[0] if values else default

    def strings(self, window, name):
        """NUL-separated string list — _NET_DESKTOP_NAMES and WM_CLASS both
        use this encoding, and both have a trailing NUL that must not become
        a phantom empty entry."""
        raw = self._prop(window, self.atom[name])
        if not raw:
            return []
        parts = raw.split(b"\x00")
        return [p.decode("utf-8", "replace") for p in parts if p]

    def text(self, window, *names):
        for name in names:
            raw = self._prop(window, self.atom[name])
            if raw:
                return raw.rstrip(b"\x00").decode("utf-8", "replace")
        return ""

    def geometry(self, window):
        """Root-relative x, y, w, h. Zeroes for a window that has gone.

        TranslateCoordinates rather than GetGeometry alone: a reparenting WM
        puts the client inside a frame, so GetGeometry's x/y are relative to
        that frame and would place every window at nearly the same spot.
        """
        try:
            g = self.conn.core.GetGeometry(window).reply()
            t = self.conn.core.TranslateCoordinates(window, self.root, 0, 0).reply()
            return [int(t.dst_x), int(t.dst_y), int(g.width), int(g.height)]
        except Exception:
            return [0, 0, 0, 0]

    def subscribe(self, window):
        if window in self.subscribed:
            return
        try:
            self.conn.core.ChangeWindowAttributesChecked(
                window, xp.CW.EventMask,
                # StructureNotify too: a window's GEOMETRY changes with
                # ConfigureNotify and no property changes at all, so watching
                # properties alone gives an overview drawn from where each
                # window was when it opened.
                [xp.EventMask.PropertyChange | xp.EventMask.StructureNotify]
            ).check()
            self.subscribed.add(window)
        except Exception:
            # Already gone. It will not be in the next client list either.
            pass

    def snapshot(self):
        clients = self.cardinals(self.root, "_NET_CLIENT_LIST")
        for window in clients:
            self.subscribe(window)
        self.subscribed &= set(clients)

        normal = self.atom["_NET_WM_WINDOW_TYPE_NORMAL"]
        dialog = self.atom["_NET_WM_WINDOW_TYPE_DIALOG"]

        windows = []
        for window in clients:
            wm_class = self.strings(window, "WM_CLASS")
            # WM_CLASS is (instance, class). The CLASS half is the one that
            # matches a .desktop entry, which is what the icon lookup needs.
            app_id = wm_class[-1] if wm_class else ""
            types = self.cardinals(window, "_NET_WM_WINDOW_TYPE")
            geom = self.geometry(window)
            windows.append(
                {
                    "id": window,
                    # Position and size, in root coordinates. Carried for the
                    # workspace overview, which lays windows out where they
                    # actually are rather than in a list -- the Hyprland side
                    # gets the same two fields from `hyprctl clients` as
                    # `at` and `size`.
                    "at": [geom[0], geom[1]],
                    "size": [geom[2], geom[3]],
                    # -1 rather than 0: 0 is desktop one, and a window that
                    # is genuinely on no desktop (or has not said) must not
                    # silently join it.
                    "desktop": self.cardinal(window, "_NET_WM_DESKTOP", -1),
                    "appId": app_id,
                    "title": self.text(window, "_NET_WM_NAME", "WM_NAME"),
                    "normal": (not types) or (normal in types) or (dialog in types),
                }
            )

        return {
            "desktop": self.cardinal(self.root, "_NET_CURRENT_DESKTOP", -1),
            "names": self.strings(self.root, "_NET_DESKTOP_NAMES"),
            "active": self.cardinal(self.root, "_NET_ACTIVE_WINDOW", 0),
            "windows": windows,
        }

    # How long to keep collecting events before believing the state has
    # settled. Opening a window fires a dozen PropertyNotifys describing one
    # new state; an animated terminal title (a spinner, a progress counter)
    # fires forever. Both are coalesced into at most one frame per interval.
    #
    # Measured on this session: without it, three group switches produced 17
    # frames, because a terminal running an agent was animating a spinner
    # glyph in its title the whole time. Every one of those frames rebuilt the
    # strip's delegates for a change no one asked to see.
    SETTLE_SECONDS = 0.12

    def run(self):
        self.conn.core.ChangeWindowAttributesChecked(
            self.root, xp.CW.EventMask, [xp.EventMask.PropertyChange]
        ).check()

        fd = self.conn.get_file_descriptor()
        last = None

        while True:
            payload = self.snapshot()
            # Only speak when something actually differs — a burst that
            # settles back to where it started should not reach QML at all.
            if payload != last:
                sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
                sys.stdout.flush()
                last = payload

            if not self._wait_for_change(fd):
                return

    def _wait_for_change(self, fd):
        """Block until a watched property changes, then let the burst settle.
        Returns False when the X connection closed."""
        while True:
            # Drain BEFORE selecting. xcffib may already hold events read off
            # the socket during an earlier reply, and those leave nothing for
            # select() to report — waiting first would hang until the next
            # unrelated event arrived.
            hit, alive = self._drain()
            if not alive:
                return False

            if hit:
                # Keep collecting until the server is quiet for a moment, so
                # one snapshot covers the whole burst.
                while select.select([fd], [], [], self.SETTLE_SECONDS)[0]:
                    _, alive = self._drain()
                    if not alive:
                        return False
                return True

            # Nothing queued and nothing we care about yet: sleep on the fd.
            select.select([fd], [], [])

    def _drain(self):
        """Pull every queued event without blocking.
        Returns (a watched property changed, the connection is still alive)."""
        hit = False
        try:
            event = self.conn.poll_for_event()
            while event is not None:
                if (
                    isinstance(event, xp.PropertyNotifyEvent)
                    and event.atom in self.watched_atoms
                ):
                    hit = True
                elif isinstance(event, xp.ConfigureNotifyEvent):
                    hit = True
                event = self.conn.poll_for_event()
        except xcffib.ConnectionException:
            return hit, False
        return hit, True


def main():
    try:
        Ewmh().run()
    except xcffib.ConnectionException:
        # The X server went away — the session is ending. Not an error.
        return 0
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
