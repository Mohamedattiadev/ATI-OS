#!/usr/bin/env bash
# ============================================================
#  float-extra.sh — qtile's float_extra_qutebrowsers, as an event listener
#
#  THE ONE FLOAT RULE THAT CANNOT BE A WINDOWRULE
#  ----------------------------------------------
#  rules.conf carries every other float qtile has, including the sizes.
#  This one it cannot: config.py's float_extra_qutebrowsers floats the
#  SECOND and later qutebrowser at 900x600 and leaves the FIRST tiled.
#
#      if existing_qutes:
#          window.floating = True
#          window.cmd_set_size_floating(900, 600)
#          qtile.call_later(0.1, window.cmd_center)
#      else:
#          window.floating = False
#
#  That is a rule about how many instances already exist, and Hyprland's
#  rule language has no way to ask. A windowrule matches a window against
#  its own properties; it cannot count its siblings. So the decision has to
#  be made when the window appears, which is what this listens for.
#
#  rules.conf's own note pointed at this seam and named workspace-layout.sh
#  as the precedent. This is that script's shape, deliberately — same
#  socket, same lock, same reconnect handling, so there is one pattern here
#  and not two.
#
#  WHY IT COUNTS AT openwindow AND NOT AFTER
#  -----------------------------------------
#  The window that just opened is ALREADY in `hyprctl clients` by the time
#  the event arrives, so the test is "more than one", not "any". Counting
#  before it appeared would need a cache of state this script has no reason
#  to keep, and a cache that can drift is worse than a question that can be
#  asked.
# ============================================================
set -euo pipefail

SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/float-extra.lock"

# qtile matches `"qutebrowser" in wm_class[0].lower()`, which covers both the
# bare name and the reverse-DNS one. rules.conf records that the live class
# here is org.qutebrowser.qutebrowser.
CLASS_RE='qutebrowser'
WIDTH=900
HEIGHT=600

# Two instances would both answer every openwindow and both resize the same
# window, interleaved. Non-blocking: if one already holds it, this one is
# redundant. Same reasoning as workspace-layout.sh's.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "float-extra: another instance holds $LOCK_FILE — exiting" >&2
    exit 0
fi

[ -S "$SOCKET" ] || { echo "float-extra: no event socket: $SOCKET" >&2; exit 1; }

handle() {
    # openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE
    local payload="$1" addr class
    payload="${payload#openwindow>>}"
    addr="${payload%%,*}"
    class="$(printf '%s' "$payload" | cut -d, -f3)"

    printf '%s' "$class" | grep -qi "$CLASS_RE" || return 0

    # How many qutebrowsers exist RIGHT NOW, this one included. One means it
    # is the first, and qtile leaves the first tiled.
    local count
    count="$(hyprctl -j clients 2>/dev/null | python3 -c "
import json,sys
try: cs=json.load(sys.stdin)
except Exception: print(0); sys.exit()
print(sum(1 for c in cs if '$CLASS_RE' in (c.get('class') or '').lower()))
" 2>/dev/null || echo 0)"

    [ "${count:-0}" -gt 1 ] || return 0

    # `address:` and not the focused window: openwindow does not imply focus,
    # and by the time this runs the user may already be somewhere else. The
    # address is the only handle that cannot address the wrong window.
    hyprctl --batch "\
dispatch setfloating address:0x${addr#0x} ; \
dispatch resizewindowpixel exact $WIDTH $HEIGHT,address:0x${addr#0x} ; \
dispatch centerwindow" >/dev/null 2>&1 || true
}

# A python reader and NOT socat, which is what workspace-layout.sh uses and
# for the reason that matters here: socat IS NOT INSTALLED on this machine.
# Written against socat first, and the script would have started, held its
# lock, read nothing and exited quietly — a listener that is running and deaf,
# which is exactly the failure mode NEXT-SESSION.md records for the two
# listeners that died silently. Checked with `command -v socat` before
# trusting it.
read_events() {
    python3 -u -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
buf = b""
while True:
    chunk = s.recv(4096)
    if not chunk:
        break
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        print(line.decode("utf-8", "replace"), flush=True)
' "$SOCKET"
}

RECONNECTS=0
while :; do
    exec 7< <(read_events)
    READER_PID=$!

    while IFS= read -r line <&7; do
        case "$line" in
            openwindow\>\>*) handle "$line" ;;
        esac
    done

    exec 7<&-
    [ -n "${READER_PID:-}" ] && kill "$READER_PID" 2>/dev/null || true

    # The socket FILE going away is Hyprland going away; anything else is a
    # dropped read and worth reconnecting for. workspace-layout.sh's note
    # records why a listener that connects once dies silently and stays dead.
    [ -S "$SOCKET" ] || break

    RECONNECTS=$((RECONNECTS + 1))
    if [ "$RECONNECTS" -le 5 ]; then sleep 1; else sleep 5; fi
    echo "float-extra: event socket read ended, reconnecting (attempt $RECONNECTS)" >&2
done
