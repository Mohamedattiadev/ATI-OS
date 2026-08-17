#!/usr/bin/env bash
# x11-panel-focus.sh grab|release — hand the keyboard to the island's panel
# under X11, and give it back afterwards.
#
# WHY THIS IS NEEDED, AND WHY `focusable` IS NOT ENOUGH
# -----------------------------------------------------
# IslandWindowX11.qml maps the island's `islandKeyboardFocus` onto
# XPanelWindow's `focusable`, and that half works: measured with the
# application launcher open, the island's panel window advertises
#
#     WM_HINTS: Client accepts input or input focus: True
#
# and at rest it advertises False. Quickshell is doing its part exactly.
#
# What does not happen is qtile focusing it. Every Quickshell panel is
# `_NET_WM_WINDOW_TYPE_DOCK`, and a dock is furniture: qtile does not manage
# it, does not put it in a group, and never gives it the keyboard, whatever
# WM_HINTS says. So under qtile every keyboard-driven panel opened and then
# ignored the keyboard — the bar picker's "type to filter" and j/k did
# nothing, the launcher's search field stayed empty, and Escape went to
# whatever window was behind and did not close the panel. All measured, not
# inferred: `xdotool type` into an open launcher landed in the terminal
# behind it until this was fixed.
#
# `xdotool windowfocus` is XSetInputFocus, which goes straight to the X
# server and does not ask the window manager's opinion. Verified on the live
# session: focus the panel that way and typing lands in the launcher's field.
#
# WHICH WINDOW, AND WHY THAT TEST
# -------------------------------
# Quickshell owns several X windows and offers no way to ask QML for a window
# id — XPanelWindow exposes exactly six properties and none of them is a
# handle. So the window is found by the one thing that already distinguishes
# it: the panel asking for keys is the ONLY one whose WM_HINTS input flag is
# True, because that flag IS `focusable`, which is set from the island's own
# keyboard state. The test and the intent are therefore the same fact, and
# the rule cannot drift from what the island believes.
#
# Matching on geometry was the alternative and it is worse in every way: the
# island's height changes with every panel, the overlay window is fullscreen,
# and the exclusive-zone reserver is 1 px tall.

set -euo pipefail

FORK_DIR="${TIDE_ISLAND_FORK_DIR:-$HOME/.config/quickshell/tide-island-fork}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/tide-island"
PREV_FOCUS_FILE="$STATE_DIR/x11-prev-focus"

command -v xdotool >/dev/null 2>&1 || exit 0
[[ -n "${DISPLAY:-}" ]] || exit 0

# ---------------------------------------------------------------------------
#  AND THE FOCUS HAS TO STAY TAKEN
# ---------------------------------------------------------------------------
# XSetInputFocus wins the argument with qtile once. It does not win it twice,
# and the second argument is the one that was being lost: reported as "in
# qtile ... not closing with q or esc", i.e. a panel that opens, takes the
# keyboard exactly as this script intends, and then goes deaf.
#
# BackendSurface.md predicted the mechanism and stopped short of fixing it —
# "the *guarantee* is gone, and qtile's `follow_mouse_focus = True` can hand
# focus away mid-panel". Confirmed in the installed libqtile rather than
# assumed, which also settles how to fix it:
#
#     backend/x11/window.py:2050   handle_EnterNotify:
#         if self.qtile.config.follow_mouse_focus is True:
#             if self.group.current_window != self:
#                 self.group.focus(self, False)
#
# Two things fall out of reading it. First, the steal is on ENTER, not on
# motion — so it is not every twitch of the mouse, it is the moment the
# pointer crosses into any managed window, which for a shelf at the top of
# the screen is the first move you make toward the file you were going to
# drag. Second, and this is what makes the fix a fix, **the flag is read at
# event time from `qtile.config`**, not baked in at startup. Setting it live
# takes effect on the next EnterNotify.
#
# So the grab turns it off and the release turns it back on. NOT a permanent
# change to config.py: follow-mouse is the behaviour this desktop wants
# everywhere except inside the ~2 seconds a modal island panel is up, and a
# config edit would be answering "the panel loses focus" with "give up
# focus-follows-mouse", which is not the trade anybody asked for.
#
# The previous value is READ AND STORED rather than assumed to be True,
# because `follow_mouse_focus` also has a "click_or_drag_only" setting and
# restoring a tri-state as a bool would silently change what the desktop does
# for anyone using it.
#
# ONE `qtile cmd-obj` PER TRANSITION, and that is the whole budget. Each call
# is a fresh Python interpreter — ~150 ms, measured in this tree when the
# EWMH feed was designed and the reason that feed is not built on this CLI —
# so read-and-set is one eval and not two, and it runs in the BACKGROUND
# behind the focus take, which is the part with a deadline.
FOLLOW_FILE="$STATE_DIR/x11-prev-follow-mouse"

qtile_running() { command -v qtile >/dev/null 2>&1 && pgrep -x qtile >/dev/null 2>&1; }

# Sets follow_mouse_focus to $1 and prints what it was. One round trip, so
# the read and the write cannot be separated by an EnterNotify.
#
# ---- IT HAS TO BE A SINGLE EXPRESSION, AND THAT IS NOT A STYLE CHOICE ----
#
# The obvious three-line form — read into a name, assign, name the name —
# looks right and returns NOTHING. libqtile's `eval` (command/base.py:269) is
#
#     try:    return str(eval(code, globals_, locals()))
#     except SyntaxError:  exec(code, globals_, locals()); return None
#
# so any code with a statement in it takes the exec branch, where the write
# still lands and the value is thrown away. The failure is therefore
# ASYMMETRIC and would have shipped: suspending works, and only the RESTORE
# is broken, so focus-follows-mouse would have been switched off by the first
# island panel of the session and never switched back on.
#
# A list literal is an expression, and its elements evaluate left to right —
# so the repr is taken before the setattr runs, and [0] is the value that was
# there before this call.
qtile_set_follow() {
  local want="$1" code
  code="[repr(self.config.follow_mouse_focus), setattr(self.config, 'follow_mouse_focus', $want)][0]"
  qtile cmd-obj -o cmd -f eval -a "$code" 2>/dev/null || true
}

follow_suspend() {
  qtile_running || return 0
  mkdir -p "$STATE_DIR"
  # Only remember the ORIGINAL value. Two panels opening back to back would
  # otherwise have the second one record False and restore False forever,
  # which is the failure mode that turns a temporary suspension into a
  # permanent config change nobody made.
  [[ -e "$FOLLOW_FILE" ]] && return 0
  qtile_set_follow False > "$FOLLOW_FILE" 2>/dev/null || true
}

follow_restore() {
  qtile_running || return 0
  local prev=""
  [[ -r "$FOLLOW_FILE" ]] && prev="$(<"$FOLLOW_FILE")"
  rm -f "$FOLLOW_FILE" 2>/dev/null || true
  # The payload comes back as qtile's [success, "value"] pair around a repr;
  # anything that is not a value we recognise falls back to True, which is
  # this config's setting and the safe end of the trade — a desktop that
  # follows the mouse when it should not is a preference, one that has
  # silently stopped is a bug report.
  case "$prev" in
    *"'click_or_drag_only'"*) qtile_set_follow "'click_or_drag_only'" >/dev/null ;;
    *False*)                  qtile_set_follow False >/dev/null ;;
    *)                        qtile_set_follow True >/dev/null ;;
  esac
}

island_pid() {
  ps -eo pid=,args= | awk -v want="$FORK_DIR" \
    '!/awk/ { for (i = 1; i < NF; i++) if ($i == "-p" && $(i + 1) == want) { print $1; exit } }'
}

# The panel window: owned by the island, and advertising that it accepts
# input focus. Empty output means no panel currently wants the keyboard.
panel_window() {
  local pid
  pid="$(island_pid)"
  [[ -n "$pid" ]] || return 0

  local w
  for w in $(xdotool search --pid "$pid" 2>/dev/null); do
    if xprop -id "$w" WM_HINTS 2>/dev/null | grep -q 'input focus: True'; then
      printf '%s\n' "$w"
      return 0
    fi
  done
}

case "${1:-}" in
  grab)
    # RETRY, because this is a race and losing it is silent. QML sets
    # `focusable` and this script is spawned from the same property change,
    # so the WM_HINTS write and this lookup are in flight together. Without
    # the retry the panel opens un-focused perhaps one time in three, which
    # is the most annoying possible failure: intermittent, and indis-
    # tinguishable from "the panel is just broken".
    win=""
    for _ in $(seq 1 25); do
      win="$(panel_window)"
      [[ -n "$win" ]] && break
      sleep 0.04
    done
    [[ -n "$win" ]] || exit 0

    # Backgrounded: taking the focus is what has a deadline, and this is a
    # 150 ms interpreter start. The window between the two is one EnterNotify
    # wide and costs at worst the behaviour that was there before this.
    follow_suspend &

    # Remember where the keyboard came from, so `release` can hand it back.
    # `xdotool getwindowfocus` is the real X input focus, which is what we
    # are about to take -- NOT _NET_ACTIVE_WINDOW, which qtile never updated
    # for a dock and which therefore still names the window behind us.
    mkdir -p "$STATE_DIR"
    xdotool getwindowfocus 2>/dev/null > "$PREV_FOCUS_FILE" || true

    xdotool windowfocus "$win" 2>/dev/null || true
    ;;

  release)
    # Before anything else, because a panel that has closed must not leave
    # the desktop without focus-follows-mouse even if the handback below
    # fails to find a window to focus.
    follow_restore

    # Give the keyboard back to whoever had it. If the window is gone --
    # closed while a panel was open -- fall back to what qtile thinks is
    # active, and if that fails too, do nothing rather than focusing
    # something arbitrary.
    prev=""
    [[ -r "$PREV_FOCUS_FILE" ]] && prev="$(<"$PREV_FOCUS_FILE")"
    rm -f "$PREV_FOCUS_FILE" 2>/dev/null || true

    if [[ -n "$prev" ]] && xdotool getwindowname "$prev" >/dev/null 2>&1; then
      xdotool windowfocus "$prev" 2>/dev/null || true
      exit 0
    fi

    active="$(xdotool getactivewindow 2>/dev/null || true)"
    [[ -n "$active" ]] && xdotool windowfocus "$active" 2>/dev/null || true
    ;;

  *)
    printf 'usage: %s grab|release\n' "${0##*/}" >&2
    exit 2
    ;;
esac
