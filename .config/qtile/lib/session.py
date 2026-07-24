"""Cross-logout window→group persistence.

On qtile shutdown: dump every managed window's wm_class + group.name to
JSON at ~/.cache/qtile/session.json. On startup_complete: read the file,
match newly-appearing windows by wm_class, and move them to the recorded
group. Best-effort — pids change, wm_class may collide, some windows may
never re-appear.
"""
import json
import os

from libqtile import hook, qtile


CACHE_DIR = os.path.expanduser("~/.cache/qtile")
STATE_FILE = os.path.join(CACHE_DIR, "session.json")


def _dump_session():
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        entries = []
        seen = set()
        for group in qtile.groups:
            for w in group.windows:
                cls = None
                try:
                    cls = w.window.get_wm_class()
                except Exception:
                    pass
                if not cls:
                    continue
                key = (tuple(cls), group.name)
                if key in seen:
                    continue
                seen.add(key)
                entries.append({"wm_class": list(cls), "group": group.name})
        with open(STATE_FILE, "w") as f:
            json.dump(entries, f)
    except Exception:
        pass  # never let this break shutdown


def _restore_session():
    if not os.path.exists(STATE_FILE):
        return
    try:
        with open(STATE_FILE) as f:
            entries = json.load(f)
    except Exception:
        return

    # Build a wm_class -> group.name map. First entry wins for duplicates.
    class_to_group = {}
    for e in entries:
        cls = tuple(e.get("wm_class") or ())
        grp = e.get("group")
        if cls and grp and cls not in class_to_group:
            class_to_group[cls] = grp

    if not class_to_group:
        return

    # For each currently-open window, if its wm_class matches, move it.
    for group in qtile.groups:
        for w in list(group.windows):
            try:
                cls = tuple(w.window.get_wm_class() or ())
            except Exception:
                continue
            target = class_to_group.get(cls)
            if target and target != group.name and target in qtile.groups_map:
                try:
                    w.togroup(target)
                except Exception:
                    pass


@hook.subscribe.shutdown
def on_shutdown():
    _dump_session()


@hook.subscribe.startup_complete
def on_startup_complete():
    # Delay so windows from autostart have time to appear.
    qtile.call_later(3.0, _restore_session)
