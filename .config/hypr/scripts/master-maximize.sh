#!/usr/bin/env bash
# ============================================================
#  $mod X — qtile's lazy.layout.maximize(), ported for real.
#
#  ---- WHAT WAS HERE, AND WHY IT LOOKED DEAD ----
#
#  binds.conf had:
#
#      bind = $mod, X, fullscreen, 1
#
#  `fullscreen 1` is Hyprland's MAXIMIZE: the window takes the whole
#  usable area of the monitor, gaps kept, reserved area (the notch)
#  respected.  The bind registers, the dispatcher works — measured, a
#  window went 1005x715 -> 1346x715 and back.
#
#  And it is still a NO-OP on most of this desktop, provably, because a
#  workspace holding exactly ONE tiled window already gives that window
#  the whole usable area.  Measured on the live session: workspaces 1, 2,
#  3 and 5 each hold a single window at [10,43] 1346x715, and `fullscreen
#  1` produces [10,43] 1346x715.  Four of five workspaces where the key
#  cannot do anything, whether or not it fires.  "$mod X does nothing"
#  was not a keyboard problem; it was arithmetic.
#
#  ---- WHAT QTILE ACTUALLY DID ----
#
#  ../qtile/config.py:6207
#      Key([mod], "x", lazy.layout.maximize(), desc="Toggle between min
#                                                    and max sizes")
#  over
#      layout.MonadTall(ratio=0.75, min_ratio=0.6, max_ratio=0.85)
#
#  libqtile/layout/xmonad.py:350 `maximize()` branches:
#
#      if len(self.clients) < 3 or self.focused == 0:
#          self._maximize_main()      # :279
#      else:
#          self._maximize_secondary()
#
#  and `_maximize_main` is the whole behaviour anyone remembers:
#
#      if self.ratio <= 0.5 * (self.max_ratio + self.min_ratio):
#          self.ratio = self.max_ratio
#      else:
#          self.ratio = self.min_ratio
#
#  With this config's 0.6/0.85 the midpoint is 0.725, so from the resting
#  0.75 the first press goes DOWN to 0.6 and it toggles 0.6 <-> 0.85 from
#  there.  The stack never disappears — it is squeezed.  That is the
#  difference from `fullscreen 1`, which covers the stack outright.
#
#  Hyprland's `master` layout is MonadTall's analogue (layout-cycle.sh
#  argues that mapping) and `layoutmsg mfact exact <r>` is `self.ratio`.
#  Verified live at 0.85 / 0.60 / 0.75: master 1140 / 802 / 1005 px.
#
#  `_maximize_secondary` — grow the focused STACK window's height, 3+
#  clients only — has no equivalent: Hyprland's master layout exposes
#  mfact and nothing per-stack-window.  So this script takes the
#  `_maximize_main` branch always.  That is qtile's own behaviour for
#  every case except "3+ windows AND a stack window focused", and it is
#  recorded here rather than silently dropped.
#
#  ---- THE ONE DELIBERATE DIVERGENCE ----
#
#  With a single tiled window qtile's mod+x was ALSO a no-op — ratio
#  moves, one client still fills the screen.  Being faithful there means
#  shipping the dead key that was reported.  So: one tiled window and no
#  stack to trade with, $mod X toggles true fullscreen (mode 0), which is
#  the only reading of "give this window the most space" that has any
#  space left to give.  It coincides with $mod F in exactly that case,
#  which is fine — there is one right answer when there is one window.
#
#  Floating windows have no mfact at all, so they get `fullscreen 1`,
#  which does move them (a float is not already filling the screen).
#
#  ---- THE LOG ----
#
#  One line per press into $XDG_RUNTIME_DIR, capped.  It exists because
#  "did the bind fire, or did the dispatcher do nothing visible" is the
#  question this whole file came from, and it is not answerable from a
#  screenshot: `wtype` sends to the focused surface, not through
#  compositor bindings, so a keybind cannot be synthesised on this
#  desktop and the physical keystroke is the only test there is.
# ============================================================

set -u

LOG="${XDG_RUNTIME_DIR:-/tmp}/master-maximize.log"

log() {
    printf '%s %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG"
    # keep the file from growing forever; it is a diagnostic, not a record
    if [ "$(wc -l <"$LOG" 2>/dev/null || echo 0)" -gt 200 ]; then
        tail -n 100 "$LOG" >"$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
    fi
}

# qtile's own numbers, from ../qtile/config.py:7322-7326.  Do not "tidy"
# these into hyprland's master:mfact — that is the RESTING ratio (0.75,
# also qtile's), and these two are the ends of the toggle.
MIN_RATIO=0.60
MAX_RATIO=0.85
# 0.5 * (max + min) — qtile's own threshold expression, not a taste value
MID_RATIO=0.725

active=$(hyprctl -j activewindow 2>/dev/null)
if [ -z "$active" ] || [ "$active" = "{}" ]; then
    log "no active window"
    exit 0
fi

# The helper prints exactly two lines: the dispatcher call, then the
# reason it chose it.  Two lines rather than one string because the
# dispatcher's own arguments contain spaces and re-splitting them in
# shell is how this kind of script acquires a quoting bug.
decision=$(hyprctl -j clients 2>/dev/null | \
    ACTIVE="$active" MIN_RATIO="$MIN_RATIO" MAX_RATIO="$MAX_RATIO" \
    MID_RATIO="$MID_RATIO" python3 -c '
import json, os, subprocess, sys

active = json.loads(os.environ["ACTIVE"])
clients = json.load(sys.stdin)
MIN_RATIO = os.environ["MIN_RATIO"]
MAX_RATIO = os.environ["MAX_RATIO"]
MID_RATIO = float(os.environ["MID_RATIO"])

ws = active["workspace"]["id"]

# Any fullscreen state at all hides the layout, so a ratio change under it
# is invisible.  Leave it first; that IS the visible answer to the key.
#
# `fullscreenstate 0 0` and not `fullscreen <n>`, because the two
# numbers are different alphabets and it is a trap: in `hyprctl clients`
# the `fullscreen` field is a STATE (0 none, 1 maximized, 2 fullscreen),
# while the `fullscreen` DISPATCHER takes a MODE (0 fullscreen, 1
# maximize, 2 fullscreen-without-telling-the-client).  Feeding the state
# back to the dispatcher happens to toggle off — measured, it does — but
# only because "requested mode equals current" is also the toggle
# condition, and 2 means two different things on the two sides of that
# coincidence.  `fullscreenstate 0 0` asserts the result instead of
# toggling toward it, for both states.  Verified on both.
fs = active.get("fullscreen", 0)
if fs:
    print(f"fullscreenstate 0 0\nleave-fullscreen (state={fs})")
    sys.exit(0)

if active.get("floating"):
    print("fullscreen 1\nfloat-maximize")
    sys.exit(0)

tiled = [c for c in clients
         if c["workspace"]["id"] == ws and not c["floating"] and c.get("mapped", True)]

if len(tiled) < 2:
    # nothing to trade space with — see "the one deliberate divergence"
    print("fullscreen 0\nsolo-fullscreen")
    sys.exit(0)

mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"],
                                 capture_output=True, text=True).stdout)
mon = next((m for m in mons if m["name"] == active["monitor"]), None) \
      or next((m for m in mons if m["id"] == active.get("monitorID")), mons[0])
res = mon["reserved"]  # left, top, right, bottom

orient = subprocess.run(["hyprctl", "getoption", "master:orientation", "-j"],
                        capture_output=True, text=True).stdout
orient = json.loads(orient).get("str", "left") if orient else "left"

# `center` splits three ways and its master is neither extreme; this
# config runs `left` and the fallback is documented rather than guessed.
vertical = orient in ("top", "bottom")
if vertical:
    usable = mon["height"] - res[1] - res[3]
    key = (lambda c: c["at"][1])
    span = (lambda c: c["size"][1])
else:
    usable = mon["width"] - res[0] - res[2]
    key = (lambda c: c["at"][0])
    span = (lambda c: c["size"][0])

master = (max(tiled, key=key) if orient in ("right", "bottom")
          else min(tiled, key=key))

# Gaps bias this by ~(2*gaps_out + gaps_in)/usable, about 0.015 here, and
# the three ratios in play (0.60 / 0.75 / 0.85) all sit far from the
# 0.725 threshold, so reading the raw fraction keeps the script free of
# any gap parsing without changing a single decision.
ratio = span(master) / usable if usable else 0.75

target = MAX_RATIO if ratio <= MID_RATIO else MIN_RATIO
print(f"layoutmsg mfact exact {target}\n"
      f"ratio={ratio:.3f} n={len(tiled)} orient={orient} -> {target}")
')

if [ -z "$decision" ]; then
    log "clients query failed"
    exit 1
fi

dispatch=$(printf '%s\n' "$decision" | head -n 1)
reason=$(printf '%s\n' "$decision" | tail -n 1)

log "$dispatch  ($reason)"
# shellcheck disable=SC2086  # hyprctl joins argv itself; the words here
# are built above from a fixed set and contain no user input
hyprctl dispatch $dispatch >/dev/null
