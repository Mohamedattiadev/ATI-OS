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
