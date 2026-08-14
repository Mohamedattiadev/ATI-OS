#!/usr/bin/env bash
# border-focus.sh dim | restore
#
# Pulls the WINDOW borders down while an island panel is open, and puts them
# back when it closes.
#
# WHY
# ---
# Asked for directly: "i saw that the color of the islend is too similar to
# the terminal so i thought that when a popup is on we can reduce the color
# of the border of the apps so the color will be to low not seen, and when
# the popup is on the island will have a border color".
#
# The island grows an accent border when a panel opens (see
# DynamicIslandWindow.qml, `panelBorderColor`). That border is the palette's
# accent — and so is `col.active_border`, from the same `accent_of_mode`
# slot, so without this the focused window is outlined in exactly the colour
# the panel is trying to claim. Two accents on screen is one too many: the
# eye has nothing to tell it which surface is in front.
#
# So this is not decoration. It is what makes the island's border MEAN
# something: while a panel is up there is exactly one accent on the screen.
#
# WHAT "DIM" IS
# -------------
# `$border_inactive` — the colour every unfocused window already wears. Not
# a computed blend and not transparency:
#
#   * a blend is a third colour to keep in step with 22 palettes, and this
#     file would be the only thing that knew how to compute it;
#   * `col.active_border` takes a gradient spec, and alpha there is applied
#     to the border ON the wallpaper, so a "faded" border on a light
#     wallpaper is not fainter, it is a different hue.
#
# Using the inactive colour says the true thing: while a panel owns the
# keyboard, no window is the focused one.
#
# WHERE THE VALUES COME FROM
# --------------------------
# colors.conf, which theme-apply rewrites — NOT from `hyprctl getoption`
# read at dim time and replayed at restore time. That would work exactly
# until the theme changed while a panel was open, at which point restore
# would write the OLD palette's border back over the new one and the only
# way to notice would be to look at a window edge.
#
# Reading the file also means restore is correct after a crash, a reload, or
# a `restore` called with no matching `dim`.
#
# IDEMPOTENT. Both verbs can be called any number of times in any order;
# there is no stored state, because the state that matters is in colors.conf
# and in whether a panel is open, and this script owns neither.

set -uo pipefail

COLORS="${HYPR_COLORS:-$HOME/.config/hypr/colors.conf}"

# `$name = value` -> value. Anchored on the variable name so a substring
# match ($border_active vs $border_inactive) cannot pick the wrong line.
read_var() {
    local name="$1"
    sed -n "s/^\\\$$name[[:space:]]*=[[:space:]]*\\(.*\\)\$/\\1/p" "$COLORS" \
        | tail -1 | tr -d '[:space:]'
}

apply() {
    local active="$1" inactive="$2"
    [ -n "$active" ] || return 0
    # One `--batch`, not two calls. Two round trips means one frame where the
    # active and inactive borders disagree, and on a screen full of windows
    # that reads as a flicker rather than as a fade.
    hyprctl --batch "\
keyword general:col.active_border $active ;\
keyword general:col.inactive_border $inactive" >/dev/null 2>&1
}

case "${1:-}" in
    dim)
        inactive="$(read_var border_inactive)"
        # Both to the inactive colour: see "what dim is" above.
        apply "$inactive" "$inactive"
        ;;
    restore)
        apply "$(read_var border_active)" "$(read_var border_inactive)"
        ;;
    *)
        echo "usage: border-focus.sh dim|restore" >&2
        exit 2
        ;;
esac
