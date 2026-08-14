#!/usr/bin/env bash
# layout-notify.sh <layout-key>
#
# qtile's non-English layout warning, for the Hyprland session.
#
# config.py raises a PERSISTENT, CRITICAL notification whenever the keyboard
# layout is not `us`, and takes it down again when it comes back:
#
#     show_layout_warning()  notify-send -r 9001 -u critical -t 0 \
#                              "Non-English Layout Active" \
#                              "Current layout: AR\nMany shortcuts may not
#                               work.\nSwitch to EN (US) to use all shortcuts."
#     hide_layout_warning()  notify-send -r 9001 -t 1 "" ""
#
# Nothing under Hyprland did either, which is what was reported. The three
# details that make it work are all in those two lines and are easy to drop:
#
#   * `-r 9001` is a fixed REPLACE ID, so switching us -> ara -> tr leaves ONE
#     notification that changes its text, not a stack of three.
#   * `-t 0` means it never expires. The warning is about a state, and the
#     state lasts until you switch back — a warning that fades after five
#     seconds while the layout is still wrong is worse than none, because it
#     trains you to ignore it.
#   * clearing is `-t 1` on the SAME id with empty text, not `notify-send
#     -C`/`dunstctl close`: that replaces the sticky notification with one
#     that expires in a millisecond, which is how you retract a notification
#     that has no expiry, whatever the server is.
#
# WHY A SCRIPT AND NOT A LINE IN THE BAR
# --------------------------------------
# The layout changes from three places — the topbar's chip, the language
# submap (submaps.conf E/A/T/D), and the island — and only one of those is
# running at a time. A script is the one copy all of them can call, and it is
# also what lets the notification be tested without a bar at all.
#
# Takes the layout KEY ("us", "ara", "tr", "de"), because that is what the
# bars carry and what config.py's configured_keyboards holds. The display
# name is what Hyprland's `activelayout` event carries; the caller maps it.

set -euo pipefail

NON_EN_NOTIFY_ID=9001        # config.py:355, kept identical so the two
                             # sessions cannot stack two warnings.

layout="${1:-us}"
layout="${layout//[[:space:]]/}"

if [[ -z "$layout" || "$layout" == "us" ]]; then
    notify-send -r "$NON_EN_NOTIFY_ID" -t 1 "" "" 2>/dev/null || true
    exit 0
fi

upper="${layout^^}"

notify-send \
    -r "$NON_EN_NOTIFY_ID" \
    -u critical \
    -t 0 \
    "Non-English Layout Active" \
    "Current layout: ${upper}
Many shortcuts may not work.
Switch to EN (US) to use all shortcuts." 2>/dev/null || true
