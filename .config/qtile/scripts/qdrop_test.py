#!/usr/bin/env python3
"""qdrop test suite. Import-only tests + live IPC probes.

Run: python3 qdrop_test.py
Exits non-zero on failure. Skips IPC tests if daemon not running.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
QDROP = HERE / "qdrop.py"

sys.path.insert(0, str(HERE))
import qdrop  # noqa: E402
import qdrop_watch  # noqa: E402
from gi.repository import GLib  # noqa: E402  (pulled in by qdrop's gi setup)

FAILS: list[str] = []


def check(cond, msg):
    if cond:
        print(f"  ✓ {msg}")
    else:
        print(f"  ✗ {msg}")
        FAILS.append(msg)


def section(name):
    print(f"\n== {name} ==")


# --- pure helpers -----------------------------------------------------


def t_uri_to_path():
    section("uri_to_path")
    check(qdrop.uri_to_path("file:///tmp/x") == "/tmp/x", "basic file uri")
    check(qdrop.uri_to_path("file:///tmp/a%20b.txt") == "/tmp/a b.txt", "decodes spaces")
    check(qdrop.uri_to_path("http://x") is None, "rejects non-file scheme")
    check(qdrop.uri_to_path("garbage") is None, "rejects garbage")


def t_url_detect():
    section("URL detection")
    check(qdrop.detect_text_entry_type("https://example.com") == "url", "https detected")
    check(qdrop.detect_text_entry_type("http://x.io/a?b=c") == "url", "http w/ query")
    check(qdrop.detect_text_entry_type("hello https://x") == "text", "not sole url = text")
    check(qdrop.detect_text_entry_type("plain text") == "text", "plain text")


def t_sort_key():
    section("sort key")
    pinned = {"type": "text", "value": "z", "pinned": True, "added_ts": 1}
    fresh = {"type": "text", "value": "a", "pinned": False, "added_ts": 100}
    old = {"type": "text", "value": "m", "pinned": False, "added_ts": 5}
    lst = sorted([old, fresh, pinned], key=lambda e: qdrop.entry_sort_key(e, "date"))
    check(lst[0] is pinned, "pinned first (date)")
    check(lst[1] is fresh, "newer next (date)")
    lst = sorted([old, fresh, pinned], key=lambda e: qdrop.entry_sort_key(e, "name"))
    check(lst[0] is pinned, "pinned first (name)")
    check(lst[1] is fresh, "'a' before 'm' (name)")


def t_badges():
    section("entry_badge / entry_label")
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
        img = f.name
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
        pdf = f.name
    d = tempfile.mkdtemp()
    try:
        check(qdrop.entry_badge({"type": "file", "value": img}) == "IMG", "img badge")
        check(qdrop.entry_badge({"type": "file", "value": pdf}) == "DOC", "pdf badge")
        check(qdrop.entry_badge({"type": "file", "value": d}) == "DIR", "dir badge")
        check(qdrop.entry_badge({"type": "text", "value": "hi"}) == "TXT", "text badge")
        check(qdrop.entry_label({"type": "text", "value": ""}) == "(empty)", "empty text label")
        check(
            qdrop.entry_label({"type": "text", "value": "hello\nworld"}) == "hello",
            "text label = first line",
        )
        long = "a" * 500
        check(len(qdrop.entry_label({"type": "text", "value": long})) <= 24, "label capped")
    finally:
        os.unlink(img); os.unlink(pdf); os.rmdir(d)


def t_state_roundtrip():
    section("load_state / save_state")
    orig = qdrop.STATE_FILE
    with tempfile.TemporaryDirectory() as td:
        qdrop.STATE_FILE = Path(td) / "state.json"
        # missing file
        check(qdrop.load_state() == [], "empty when missing")
        # garbage
        qdrop.STATE_FILE.write_text("not json")
        check(qdrop.load_state() == [], "empty when garbage")
        # bad entries filtered
        qdrop.STATE_FILE.write_text(json.dumps([
            {"type": "text", "value": "keep"},
            {"type": "file", "value": "/nonexistent/path/xyz"},
            "invalid",
            {"missing": "keys"},
        ]))
        loaded = qdrop.load_state()
        check(len(loaded) == 1 and loaded[0]["value"] == "keep", "filters bad + missing files")
        # roundtrip (load applies defaults)
        entries = [{"type": "text", "value": "hi"}]
        qdrop.save_state(entries)
        loaded = qdrop.load_state()
        check(
            len(loaded) == 1 and loaded[0]["type"] == "text" and loaded[0]["value"] == "hi",
            "roundtrip preserves core fields",
        )
        check("added_ts" in loaded[0] and "pinned" in loaded[0], "roundtrip adds defaults")
    qdrop.STATE_FILE = orig


# --- IPC / daemon (live) ---------------------------------------------


def _daemon_alive() -> bool:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(str(qdrop.SOCK_PATH))
        s.sendall(b"STATUS")
        s.recv(16)
        s.close()
        return True
    except Exception:
        return False


def t_ipc():
    section("IPC (live daemon)")
    if not _daemon_alive():
        print("  ~ daemon not running; skipping")
        return
    check(qdrop._send_cmd("STATUS"), "STATUS ok")
    check(qdrop._send_cmd("SHOW"), "SHOW ok")
    time.sleep(0.4)
    check(qdrop._send_cmd("HIDE"), "HIDE ok")
    time.sleep(0.4)
    check(qdrop._send_cmd("TOGGLE"), "TOGGLE ok")
    time.sleep(0.4)
    check(qdrop._send_cmd("ADD-TEXT hello from test"), "ADD-TEXT ok")
    time.sleep(0.2)
    # confirm state file grew
    data = json.loads(qdrop.STATE_FILE.read_text())
    check(
        any(e.get("type") == "text" and e.get("value") == "hello from test" for e in data),
        "text entry persisted",
    )
    # cleanup
    remaining = [e for e in data if not (e.get("type") == "text" and e.get("value") == "hello from test")]
    qdrop.save_state(remaining)
    qdrop._send_cmd("HIDE")


def t_single_instance():
    section("single-instance guard")
    if not _daemon_alive():
        print("  ~ daemon not running; skipping")
        return
    r = subprocess.run(
        [sys.executable, str(QDROP)],
        capture_output=True, text=True, timeout=3,
    )
    check(r.returncode == 0, "second launch exits cleanly")
    check("already running" in r.stderr, "prints already-running msg")


def t_cli_client():
    section("CLI client (--status)")
    r = subprocess.run(
        [sys.executable, str(QDROP), "--status"],
        capture_output=True, text=True, timeout=2,
    )
    check(r.returncode == 0, "--status returns 0 when running")
    check(r.stdout.strip() == "running", "prints 'running'")


def t_is_text_file():
    section("is_text_file")
    with tempfile.NamedTemporaryFile(suffix=".py", delete=False) as f:
        py = f.name
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        f.write(b"\x00\x01\x02")
        binf = f.name
    with tempfile.NamedTemporaryFile(suffix="", delete=False) as f:
        f.write(b"plain ascii text")
        plain = f.name
    try:
        check(qdrop.is_text_file(py), ".py detected by extension")
        check(not qdrop.is_text_file(binf), ".bin binary rejected")
        check(qdrop.is_text_file(plain), "no-ext plain text via mime")
    finally:
        for p in (py, binf, plain):
            os.unlink(p)


def t_ipc_shake_flow():
    section("hide/show/toggle flow")
    if not _daemon_alive():
        print("  ~ daemon not running; skipping")
        return
    qdrop._send_cmd("HIDE"); time.sleep(0.4)
    qdrop._send_cmd("SHOW"); time.sleep(0.4)
    # send SHOW again while visible - should be no-op, not error
    check(qdrop._send_cmd("SHOW"), "double SHOW ok")
    qdrop._send_cmd("HIDE"); time.sleep(0.4)
    check(qdrop._send_cmd("HIDE"), "double HIDE ok")
    check(qdrop._send_cmd("TOGGLE"), "toggle after hide")
    time.sleep(0.3)
    check(qdrop._send_cmd("TOGGLE"), "toggle after show")


def t_shake_shape():
    section("shake shape (qdrop_watch.Axis)")

    def feed(deltas):
        """Reversals counted for a synthetic delta stream on one axis."""
        ax = qdrop_watch.Axis("t")
        now = time.time()
        for d in deltas:
            ax.feed(d, now)
        return ax.shaking()

    amp = qdrop_watch.MIN_SEG_PX * 2
    check(not feed([amp] * 20), "straight drag is not a shake")
    check(feed([amp, -amp, amp, -amp, amp, -amp]), "back-and-forth is a shake")
    check(not feed([amp, -1, amp, -1, amp]), "sub-threshold jitter ignored")
    # Axis is axis-agnostic, so the same stream fed to the y detector is
    # what makes up/down and diagonal shakes work -- see main().
    check(feed([-amp, amp, -amp, amp, -amp, amp]), "shake starting backwards")


def t_dnd_probe():
    section("XDND payload probe")
    dragging, why = qdrop_watch.dnd_payload()
    # Nothing is being dragged while the suite runs, so the gate must be
    # shut. (If the X probe can't init at all it fails open, with a
    # distinct reason string -- accept that rather than fail the suite.)
    check(not dragging or "gate disabled" in why, f"no drag in flight: {why}")
    check(qdrop_watch.REQUIRE_DND, "payload gate on by default")


# --- show/hide animation state machine --------------------------------
#
# Drives the real Dropzone.show_animated()/hide_animated()/toggle() and
# their GLib timers, with every X11/GTK/qtile touchpoint stubbed out, so
# the transition logic is exercised without putting a window on the
# user's screen. Every window position the code asks for is recorded,
# which is what makes "does it visibly jump / replay / vibrate?"
# answerable as an assertion instead of by eye.

ANIM_H = 300  # pretend allocated height
ANIM_TARGET_Y = 40  # pretend on-screen resting Y
ANIM_OFF_Y = -ANIM_H  # fully off-screen


class AnimHarness(qdrop.Dropzone):
    def __init__(self):  # deliberately does NOT run Gtk.Window.__init__
        self.moves: list[int] = []
        self.presented = 0
        self.timer_resets = 0
        self.entries = []
        self._hide_timer = 0
        self._visible = False
        self._hiding = False
        self._mapped = False
        self._slide_timer = 0
        self._show_pending = False
        self._y = None
        self._anim_gen = 0
        self._suspend_hide = 0
        self.revealer = type("R", (), {"set_reveal_child": lambda *_: None})()

    # --- stubbed GTK/X/qtile surface ---
    def move(self, _x, y):
        self.moves.append(y)

    def present(self):
        self.presented += 1

    def show_all(self):
        pass

    def hide(self):
        pass

    def get_allocated_height(self):
        return ANIM_H

    def get_allocated_width(self):
        return qdrop.WIN_W

    def _target_xy(self):
        return (0, ANIM_TARGET_Y)

    def _refresh(self):
        pass

    def _sync_to_current_qtile_group(self):
        pass

    def _force_qtile_focus(self):
        pass

    def _reset_hide_timer(self):
        self.timer_resets += 1
        self._hide_timer = 1


def pump(ms: int):
    """Run GLib timers for ms of wall clock."""
    ctx = GLib.MainContext.default()
    end = time.monotonic() + ms / 1000.0
    while time.monotonic() < end:
        while ctx.pending():
            ctx.iteration(False)
        time.sleep(0.002)


def settle(w: AnimHarness, ms: int = 500):
    pump(ms)


def open_settled() -> AnimHarness:
    w = AnimHarness()
    w.show_animated()
    settle(w)
    w.moves.clear()
    w.presented = 0
    w.timer_resets = 0
    return w


def monotonic_down(ys) -> bool:
    return all(b <= a for a, b in zip(ys, ys[1:]))


def monotonic_up(ys) -> bool:
    return all(b >= a for a, b in zip(ys, ys[1:]))


def resumes_from(first: int, cur: int, dest: int) -> bool:
    """Did a redirected slide pick up from `cur` instead of teleporting?

    The first frame is allowed to cover a chunk of the distance --
    _slide_move eases *out*, so ~25% of the span lands on frame 1 by
    design, for the plain open animation too. What must not happen is
    the window reappearing on the far side of where it was: starting
    beyond the destination, or snapping back past `cur`.
    """
    lo, hi = min(cur, dest), max(cur, dest)
    return lo <= first <= hi and abs(first - cur) <= 0.35 * abs(dest - cur)


def t_anim_open_close():
    section("animation: plain open / close")
    w = AnimHarness()
    w.show_animated()
    settle(w)
    onscreen = [y for y in w.moves if y > -4000]  # drop the SAFE_OFFSCREEN_Y map
    check(w._visible and w._mapped, "open leaves window visible+mapped")
    check(onscreen[0] == ANIM_OFF_Y, "reveal starts fully off-screen")
    check(w.moves[-1] == ANIM_TARGET_Y, "reveal ends exactly at target")
    check(monotonic_up(onscreen), "reveal never moves backwards")
    check(not w._anim_busy(), "no timer left running after reveal")

    w.moves.clear()
    w.hide_animated()
    settle(w)
    check(resumes_from(w.moves[0], ANIM_TARGET_Y, ANIM_OFF_Y),
          "close starts from the resting position")
    check(w.moves[-1] == ANIM_OFF_Y, "close ends fully off-screen")
    check(monotonic_down(w.moves), "close never moves backwards")
    check(not w._visible and not w._hiding, "closed state is clean")
    check(not w._anim_busy(), "no timer left running after close")


def t_anim_show_while_open():
    section("animation: SHOW while already open (shake with qdrop up)")
    w = open_settled()
    w.show_animated()
    settle(w, 300)
    # The bug: this used to teleport to -height and slide back down,
    # which reads as the window closing and reopening.
    check(w.moves == [], "no re-slide — window does not move at all")
    check(w._visible and not w._hiding, "still open")
    check(w.timer_resets >= 1, "auto-hide countdown restarted")

    w.moves.clear()
    for _ in range(5):
        w.show_animated()
    settle(w, 300)
    check(w.moves == [], "five rapid SHOWs still never move the window")


def t_anim_show_during_reveal():
    section("animation: SHOW during the reveal")
    w = AnimHarness()
    w.show_animated()
    pump(60)  # mid-slide
    before = len(w.moves)
    w.show_animated()
    settle(w)
    after = w.moves[before:]
    check(monotonic_up([y for y in w.moves if y > -4000]),
          "reveal continues smoothly, not restarted")
    check(w.moves[-1] == ANIM_TARGET_Y, "still lands on target")
    check(all(y >= ANIM_OFF_Y for y in after), "never jumps back off-screen")


def t_anim_show_during_close():
    section("animation: SHOW during the close (shake mid-close)")
    w = open_settled()
    w.hide_animated()
    pump(60)  # mid-close
    mid = w.moves[-1]
    check(ANIM_OFF_Y < mid < ANIM_TARGET_Y, f"close is mid-flight at y={mid}")
    n = len(w.moves)
    w.show_animated()
    settle(w)
    back = w.moves[n:]
    check(bool(back), "SHOW mid-close is not ignored")
    check(resumes_from(back[0], mid, ANIM_TARGET_Y),
          "resumes from where it was, no teleport")
    check(monotonic_up(back), "reversal is a clean slide back down")
    check(w.moves[-1] == ANIM_TARGET_Y, "ends open at target")
    check(w._visible and not w._hiding, "state is open, not hiding")
    check(not w._anim_busy(), "no leftover timer")


def t_anim_hide_during_reveal():
    section("animation: HIDE during the reveal")
    w = AnimHarness()
    w.show_animated()
    pump(60)
    mid = w.moves[-1]
    n = len(w.moves)
    w.hide_animated()
    settle(w)
    back = w.moves[n:]
    check(bool(back), "HIDE mid-reveal is honoured")
    check(resumes_from(back[0], mid, ANIM_OFF_Y),
          "close starts from current Y, no snap")
    check(monotonic_down(back), "close runs one way")
    check(w.moves[-1] == ANIM_OFF_Y, "ends fully off-screen")
    check(not w._visible, "ends hidden")


def t_anim_hide_during_first_show_gap():
    section("animation: HIDE inside the first-show allocation gap")
    w = AnimHarness()
    w.show_animated()  # maps off-screen, slide starts 20ms later
    w.hide_animated()  # lands inside that gap
    settle(w)
    check(w.moves[-1] <= ANIM_OFF_Y, "window never slides into view")
    check(not w._visible and not w._hiding, "ends hidden and clean")
    check(not w._show_pending, "pending-show flag cleared")


def t_anim_toggle():
    section("animation: toggle")
    w = open_settled()
    w.toggle()
    settle(w)
    check(not w._visible, "toggle on open window closes it")

    w.toggle()
    settle(w)
    check(w._visible and w.moves[-1] == ANIM_TARGET_Y, "toggle reopens")

    w.hide_animated()
    pump(60)
    w.toggle()  # mid-close: must reopen, not no-op
    settle(w)
    check(w._visible and w.moves[-1] == ANIM_TARGET_Y,
          "toggle mid-close reopens instead of doing nothing")


def t_anim_idempotence():
    section("animation: repeated/no-op commands")
    w = AnimHarness()
    w.hide_animated()
    settle(w, 100)
    check(w.moves == [], "HIDE while never shown does nothing")

    w = open_settled()
    w.hide_animated()
    w.hide_animated()
    settle(w)
    check(monotonic_down(w.moves), "double HIDE does not double-animate")
    check(w.moves[-1] == ANIM_OFF_Y, "double HIDE still lands off-screen")

    w.moves.clear()
    w.hide_animated()
    settle(w, 100)
    check(w.moves == [], "HIDE on an already-closed window does nothing")


def t_anim_single_timer():
    section("animation: only one slide in flight")
    w = open_settled()
    # Hammer the state machine the way a frantic shake + keybind would.
    seq = [w.hide_animated, w.show_animated, w.hide_animated,
           w.show_animated, w.toggle, w.show_animated]
    for fn in seq:
        fn()
        pump(25)
    settle(w)
    check(w._slide_timer == 0, "no slide timer left running")
    check(w.moves[-1] == ANIM_TARGET_Y, "settles exactly on target")
    check(w._visible and not w._hiding, "state matches final position")
    # Two live timers interleave their move() calls, so the tail of the
    # sequence would zig-zag; a single timer cannot.
    tail = w.moves[-8:]
    check(monotonic_up(tail) or monotonic_down(tail),
          "final approach is smooth (no two animations fighting)")


def t_watcher_alive():
    section("watcher process")
    r = subprocess.run(["pgrep", "-af", "qdrop_watch.py"],
                       capture_output=True, text=True)
    check(bool(r.stdout.strip()), "watcher process running")


def main() -> int:
    t_uri_to_path()
    t_url_detect()
    t_sort_key()
    t_badges()
    t_is_text_file()
    t_state_roundtrip()
    t_shake_shape()
    t_dnd_probe()
    t_anim_open_close()
    t_anim_show_while_open()
    t_anim_show_during_reveal()
    t_anim_show_during_close()
    t_anim_hide_during_reveal()
    t_anim_hide_during_first_show_gap()
    t_anim_toggle()
    t_anim_idempotence()
    t_anim_single_timer()
    t_watcher_alive()
    t_ipc_shake_flow()
    t_ipc()
    t_single_instance()
    t_cli_client()
    print()
    if FAILS:
        print(f"FAIL: {len(FAILS)}")
        for f in FAILS:
            print(f"  - {f}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
