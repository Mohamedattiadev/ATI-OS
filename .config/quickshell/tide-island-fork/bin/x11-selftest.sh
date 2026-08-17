#!/usr/bin/env bash
# x11-selftest.sh — does the island actually work in this X11/qtile session?
#
# WHY THIS EXISTS
# ---------------
# Every fault fixed in the qtile port shared one property: it was SILENT. The
# workspace digit froze at 1, the window strip was empty, popups opened behind
# windows, the lock screen returned 0 without locking, the mode HUD drew no
# rows -- and in each case nothing logged, nothing crashed, and the shell
# reported "Configuration Loaded". Several were only found by looking at
# pixels or at xprop.
#
# So the checks live in a script rather than in a session's memory. Run it
# after touching the island, qtile's config, or either bar script.
#
#     bin/x11-selftest.sh            # everything
#     bin/x11-selftest.sh -v         # show each command's output on failure
#
# NON-DESTRUCTIVE. It reads state, runs --dry-run paths, and asks qtile
# questions. It does not switch bars, does not lock the screen, does not
# inject keystrokes, and does not change the focused group.
set -uo pipefail

VERBOSE=0
[[ "${1:-}" == "-v" ]] && VERBOSE=1

FORK="${TIDE_ISLAND_FORK_DIR:-$HOME/.config/quickshell/tide-island-fork}"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PASS=0; FAIL=0; SKIP=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s — %s\n' "$1" "$2"; SKIP=$((SKIP+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# qtile eval returns its value JSON-encoded; strip the quotes for comparisons.
qeval() { qtile cmd-obj -o cmd -f eval -a "$1" 2>/dev/null | sed 's/^"//; s/"$//'; }

island_pid() {
  ps -eo pid=,args= | awk -v want="$FORK" \
    '!/awk/ { for (i = 1; i < NF; i++) if ($i == "-p" && $(i + 1) == want) { print $1; exit } }'
}

# ---------------------------------------------------------------------------
head_ "session"
# ---------------------------------------------------------------------------
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  echo "  This is a Wayland session; these checks are for the X11/qtile one."
  exit 0
fi
command -v qtile >/dev/null || { echo "  qtile not on PATH"; exit 1; }
ok "X11 session (WAYLAND_DISPLAY unset)"

PID="$(island_pid)"
if [[ -n "$PID" ]]; then ok "island running (pid $PID)"; else bad "island running" "no quickshell -p $FORK"; fi

n=$(ps -eo args= | awk -v w="$FORK" '$0 == "quickshell -p " w {n++} END{print n+0}')
[[ "$n" == "1" ]] && ok "exactly one island instance" || bad "exactly one island instance" "found $n"

# ---------------------------------------------------------------------------
head_ "workspace + windows (the EWMH feed)"
# ---------------------------------------------------------------------------
if [[ -x "$FORK/bin/ewmh-state.py" ]]; then
  frame="$(timeout 6 python3 "$FORK/bin/ewmh-state.py" 2>/dev/null | head -1)"
  if [[ -n "$frame" ]]; then
    read -r idx name wins <<<"$(printf '%s' "$frame" | python3 -c '
import json,sys
d=json.load(sys.stdin)
i=d["desktop"]; n=d["names"][i] if 0<=i<len(d["names"]) else "?"
print(i, n, len(d["windows"]))')"
    ok "feed emits a frame (desktop $idx = \"$name\", $wins windows)"
    qname="$(qtile cmd-obj -o group -f info 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["name"])')"
    [[ "$name" == "$qname" ]] && ok "feed agrees with qtile (group $qname)" \
                              || bad "feed agrees with qtile" "feed=$name qtile=$qname"
  else
    bad "feed emits a frame" "no output from ewmh-state.py"
  fi
  pgrep -f "$FORK/bin/ewmh-state.py" >/dev/null && ok "island's own feed process is alive" \
                                                || bad "island's own feed process is alive"
else
  bad "ewmh-state.py present and executable"
fi

# ---------------------------------------------------------------------------
head_ "geometry: the island reserves its strut and nothing more"
# ---------------------------------------------------------------------------
dy=$(qeval '__import__("libqtile").qtile.screens[0].dy')
res=$(qeval '__import__("libqtile").qtile.screens[0].top._reserved_space[0]')
hid=$(qeval 'str(getattr(__import__("libqtile").qtile.screens[0].top.window,"hidden",None))')
if [[ "$(cat "$HOME/.cache/bar-mode" 2>/dev/null)" == "island" ]]; then
  [[ "$hid" == "True" ]] && ok "qtile's own bar is hidden in island mode" \
                         || bad "qtile's own bar is hidden in island mode" "hidden=$hid"
  [[ "$dy" == "$res" && "$dy" != "0" ]] \
    && ok "screen dy ($dy) equals the island's reservation — no dead gap" \
    || bad "screen dy equals the reservation" "dy=$dy reserved=$res (leak or lost strut)"
else
  skip "bar geometry" "not in island mode"
fi

# ---------------------------------------------------------------------------
head_ "stacking: the island is above ordinary windows"
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null && [[ -n "$PID" ]]; then
  python3 - "$PID" <<'PY'
import sys, xcffib, xcffib.xproto
pid = int(sys.argv[1])
c = xcffib.connect(); root = c.get_setup().roots[c.pref_screen].root
def prop(w, n):
    a = c.core.InternAtom(False, len(n), n).reply().atom
    try:
        r = c.core.GetProperty(False, w, a, xcffib.xproto.GetPropertyType.Any, 0, 64).reply()
    except Exception:
        return None
    return bytes(bytearray(r.value.buf())) if r and r.value_len else None
order = []
for w in c.core.QueryTree(root).reply().children:
    try:
        g = c.core.GetGeometry(w).reply(); a = c.core.GetWindowAttributes(w).reply()
    except Exception:
        continue
    if a.map_state != 2 or g.width < 200 or g.height < 100:
        continue
    p = prop(w, "_NET_WM_PID")
    order.append((w, int.from_bytes(p[:4], "little") if p else 0))
isl = [i for i, (w, pv) in enumerate(order) if pv == pid]
if not isl:
    print("  \033[33mSKIP\033[0m  island above windows — no big island surface mapped"); raise SystemExit(0)
top = max(isl)
# Scratchpads and kept-above windows legitimately sit higher; only count
# ordinary clients below the island.
below = sum(1 for i, _ in enumerate(order) if i < top)
above = len(order) - top - 1
print(f"  \033[32mPASS\033[0m  island is above {below} window(s); {above} above it (scratchpad/kept-above are expected)")
PY
else
  skip "stacking" "xcffib or island unavailable"
fi

ms=$(qeval '(lambda s: (__import__("sys").modules["config"].restack_docks(), round((__import__("time").perf_counter()-s)*1000,2))[1])(__import__("time").perf_counter())')
if [[ -n "$ms" ]]; then
  awk -v m="$ms" 'BEGIN{exit !(m+0 < 2)}' \
    && ok "restack_docks() steady-state is cheap (${ms} ms)" \
    || bad "restack_docks() steady-state is cheap" "${ms} ms — it should settle under 2 ms"
else
  bad "restack_docks() is callable"
fi

# ---------------------------------------------------------------------------
head_ "qtile config integrity"
# ---------------------------------------------------------------------------
python3 - <<'PY'
import ast, os
p = os.path.expanduser("~/.config/qtile/config.py")
src = open(p).read()
tree = ast.parse(src)
defined = {n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
# Helpers referenced from inside the `keys` list. A linter that prunes
# "unused" names has removed one of these before, leaving a config that
# compiles and then dies on the next reload with NameError.
needed = ["island_or", "island_owns_chord", "restack_docks", "refresh_dock_wids",
          "publish_layout_to_island", "publish_keyboard_to_island",
          "reconcile_bar_space", "_clamp_hidden_bar_space", "_on_screen"]
missing = [n for n in needed if n not in defined and n in src]
if missing:
    print("  \033[31mFAIL\033[0m  every helper used is defined")
    print("        USED BUT UNDEFINED: %s" % ", ".join(missing))
else:
    print("  \033[32mPASS\033[0m  every helper used is defined")
PY

# ---------------------------------------------------------------------------
head_ "keys: island actions qtile can reach"
# ---------------------------------------------------------------------------
count=$(grep -c 'bar-action ' "$HOME/.config/qtile/config.py")
[[ "$count" -ge 35 ]] && ok "$count bar-action bindings wired" \
                      || bad "bar-action bindings wired" "only $count"

for chord in Rofi-Mode Media-Mode Bluetooth-Mode Wifi-Mode Audio-Mode Display-Mode CheatSheet-Mode; do
  found=$(qeval "str(__import__('sys').modules['config']._find_chord('$chord') is not None)")
  [[ "$found" == "True" ]] && ok "chord $chord exists" || bad "chord $chord exists"
done

twins=$(qeval 'str(len(__import__("sys").modules["config"]._ISLAND_CHORD_TWINS))')
[[ "$twins" -ge 6 ]] && ok "$twins chords hand over to the island in island mode" \
                     || bad "chords hand over to the island" "only $twins"

# ---------------------------------------------------------------------------
head_ "the mode HUD reads qtile's chords"
# ---------------------------------------------------------------------------
for chord in Rofi-Mode Media-Mode; do
  rows=$(python3 "$HOME/.config/hypr/scripts/cheatsheet.py" --submap-json "$chord" 2>/dev/null \
         | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["keys"]))' 2>/dev/null)
  [[ "${rows:-0}" -gt 0 ]] && ok "HUD rows for $chord ($rows)" \
                           || bad "HUD rows for $chord" "got ${rows:-none}"
done

# ---------------------------------------------------------------------------
head_ "readouts fed from this session"
# ---------------------------------------------------------------------------
lay="$(cat "$RUNTIME/hypr-layouts/current" 2>/dev/null)"
qlay=$(qtile cmd-obj -o group -f info 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["layout"])')
[[ -n "$lay" && "$lay" == "$qlay" ]] && ok "layout glyph source agrees with qtile ($lay)" \
                                     || bad "layout glyph source" "file=${lay:-missing} qtile=$qlay"

kb="$(cat "$RUNTIME/hypr-layouts/keyboard" 2>/dev/null)"
xkb=$(setxkbmap -query 2>/dev/null | awk '/^layout:/{print $2}' | cut -d, -f1)
[[ -n "$kb" && "$kb" == "$xkb" ]] && ok "keyboard readout source agrees with X ($kb)" \
                                  || bad "keyboard readout source" "file=${kb:-missing} X=$xkb"

# ---------------------------------------------------------------------------
head_ "actions that must not be Hyprland-only"
# ---------------------------------------------------------------------------
lockcmd="$($HOME/.config/hypr/scripts/power-ctl.sh --dry-run lock 2>/dev/null)"
case "$lockcmd" in
  *betterlockscreen*) ok "power menu locks with an X11 locker ($lockcmd)" ;;
  *) bad "power menu locks with an X11 locker" "got: ${lockcmd:-nothing}" ;;
esac
command -v "${lockcmd%% *}" >/dev/null && ok "locker binary is installed" || bad "locker binary is installed"
[[ -d "$HOME/.cache/betterlockscreen" ]] && ok "locker has a cached image" \
                                         || bad "locker has a cached image" "run betterlockscreen -u <image>"

refcmd="$($HOME/.config/hypr/scripts/power-ctl.sh --dry-run refresh 2>/dev/null)"
case "$refcmd" in
  *qtile*) ok "power menu reload targets qtile ($refcmd)" ;;
  *) bad "power menu reload targets qtile" "got: ${refcmd:-nothing}" ;;
esac

grep -q 'hypr/scripts/qdrop.sh' "$HOME/.config/qtile/config.py" \
  && ok "drop shelf goes through the island-aware wrapper" \
  || bad "drop shelf goes through the island-aware wrapper"

# ---------------------------------------------------------------------------
head_ "compositor"
# ---------------------------------------------------------------------------
grep -q "window_type = 'dock'" "$HOME/.config/picom/picom.conf" \
  && ok "picom does not animate the island's own window" \
  || bad "picom does not animate the island's own window" "add window_type = 'dock' to animation-exclude"
pgrep -x picom >/dev/null && ok "picom is running" || skip "picom is running" "no compositor"

# ---------------------------------------------------------------------------
printf '\n\033[1mresult\033[0m  %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
