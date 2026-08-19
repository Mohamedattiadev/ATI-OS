#!/usr/bin/env bash
# ============================================================
#  wallpaper-set — apply a wallpaper AND record it, in that order of
#  importance but the opposite order of operation.
#
#  ---- WHY THE ISLAND'S PICKER NEEDED THIS ----
#
#  Clicking a thumbnail in Tide Island's wallpaper picker did nothing at
#  all, and gave no error. Upstream's apply path shells out to
#
#      awww img <path> --transition-type ... --transition-step ...
#
#  i.e. swww, a wallpaper daemon that is not installed here and never was
#  — this machine has run hyprpaper since the Hyprland session existed.
#  The failure is silent by construction: the picker runs the command
#  through a `Process`, checks only `exitCode === 0` to decide whether to
#  emit "applied", and a missing binary exits non-zero, so the picker
#  simply closed and nothing changed. Nothing is logged, because nothing
#  went wrong from QML's point of view.
#
#  ---- WHY IT MUST ALSO WRITE ~/.cache/wall ----
#
#  ~/.cache/wall is the single source of truth for "the current
#  wallpaper" across BOTH sessions:
#
#      AtiScriptsV1/theme-apply   reads it (WALL_LINK, ~line 145) in
#                                 every theme mode, wal included
#      hypr/scripts/wallpaper-sync.sh   reads it at login
#      dm-setbg / the qtile WallpaperPopup   maintain it
#
#  A picker that sets the wallpaper without updating it leaves the two
#  sessions disagreeing about what is on screen, and the choice silently
#  reverts at the next login when wallpaper-sync reads the stale record.
#  So the record is written FIRST and the daemon is pointed at it second,
#  which also means a crash between the two leaves the record correct and
#  one `wallpaper-sync.sh` away from being live.
#
#  It is written as a symlink, which is theme-apply's own preferred form;
#  the readers all handle the legacy plain-text form too.
#
#  ---- THE hyprpaper 0.8.4 API TRAP ----
#
#  Do NOT call `hyprctl hyprpaper preload` first. That request was
#  REMOVED in 0.8.4 and answers "invalid hyprpaper request"; `wallpaper`
#  preloads the image itself now. Under `set -e` the dead preload aborts
#  the script before the wallpaper is ever set, which is exactly how a
#  previous session ended up with no wallpaper at all. The full probe is
#  in the header of wallpaper-sync.sh.
#
#  Usage:  wallpaper-set.sh <image>
# ============================================================
set -euo pipefail

WALL_LINK="$HOME/.cache/wall"

img="${1:-}"
if [ -z "$img" ]; then
    echo "wallpaper-set: no image given" >&2
    exit 2
fi

# Resolved before it is recorded: the picker can hand over a relative path
# or one through a symlinked library, and a record that only resolves from
# the picker's working directory is a record that fails at login.
img="$(readlink -f -- "$img")"

if [ ! -r "$img" ]; then
    echo "wallpaper-set: not readable: $img" >&2
    exit 1
fi

mkdir -p "$(dirname "$WALL_LINK")"
ln -sfn -- "$img" "$WALL_LINK"

# ---- X11 (qtile island), NAMED PRESET: THE ANIMATED PATH, NOT
#      wallpaper-sync.sh AT ALL ----
#
# Reported: "the wallpaper animaiton not applied on the islend one fix why
# make the same anitmtion of hyper for both theeme and wallpaepr". This
# island picker (WallpaperPickerLayer.qml) has always called into this
# script for BOTH sessions, and wallpaper-sync.sh's own X11 branch is
# correct as far as it goes — xwallpaper --stretch, no daemon, so no
# wave to ask it for — but that "no transition" is a bigger gap than it
# looks: there is no wave TO have on X11, but there IS the circular-
# reveal overlay, and this script was never wired to it. qtile's OWN
# native-bar wallpaper popup (WallpaperPopup.py) got exactly this fix
# already this session — same theme-wallpaper bind + theme-animate +
# wallpaper-only fast-path marker — and this is the island's mirror of
# it, so picking a wallpaper from the island under qtile now looks the
# same as picking one from qtile's own popup, and both now use the same
# overlay Hyprland's theme changes already use.
#
# Hyprland (WAYLAND_DISPLAY set) is UNTOUCHED — falls through to
# wallpaper-sync.sh below exactly as before, awww's wave and all. That is
# already "hyprland's animation"; nothing here claims to improve it.
#
# wal mode is also untouched, deliberately: there the wallpaper IS the
# palette, so wallpaper-sync.sh's instant xwallpaper here plus the
# existing theme-animate wal call further down (which was ALREADY
# correct — see the "IN wal MODE" block) is the right shape already.
# Only a NAMED preset can have a wallpaper swap that touches nothing
# else, which is exactly the case the wallpaper-only fast-path marker
# exists for (see theme-apply's own header on it).
_early_mode="$(cat "$HOME/.cache/qtile/theme_mode" 2>/dev/null || true)"
_animated_x11=false
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -n "$_early_mode" ] && [ "$_early_mode" != "wal" ] \
   && command -v theme-wallpaper >/dev/null 2>&1 && command -v theme-animate >/dev/null 2>&1
then
    _animated_x11=true
    theme-wallpaper bind "$_early_mode" "$img" \
        || echo "wallpaper-set: applied, but could not bind it to theme $_early_mode" >&2
    mkdir -p "$HOME/.cache/qtile"
    : >"$HOME/.cache/qtile/.wallpaper_only_pending" 2>/dev/null || true
    # Detached: this script's own exit code is what the island's picker
    # reads to report "applied", and the wallpaper genuinely will be —
    # theme-animate finding no overlay to answer would fall back to a
    # plain, unanimated theme-apply, never to doing nothing.
    setsid -f theme-animate "$_early_mode" >/dev/null 2>&1 &
    disown
else
    # Delegate the actual set, so there is exactly ONE place that knows how
    # to talk to hyprpaper. Duplicating the hyprctl call here is how the
    # preload trap above would come back in a second copy that nobody
    # re-probes.
    #
    # NOT `exec` any more -- see the re-derive below, which has to run after it.
    "$(dirname "$(readlink -f "$0")")/wallpaper-sync.sh"
fi

#  ---- IN `wal` MODE THE WALLPAPER *IS* THE PALETTE ----
#
#  On the 21 named themes the palette is fixed and a wallpaper change must
#  NOT touch it. In `wal` mode it is derived from the image, and nothing
#  here re-derived it: this script recorded the new wallpaper and pointed
#  the daemon at it, and stopped. theme-apply was never re-run, so every
#  colour in both sessions stayed derived from the PREVIOUS image.
#
#  MEASURED, switching 0182.jpg -> 0071.jpg through this script with the
#  mode set to wal: ~/.cache/wall followed, and colors.conf's $bg stayed
#  0b0f13 -- 0182's background -- where 0071's precompiled palette gives
#  0c1013. Window borders are the visible half of that, which is the
#  reported "the border of the apps not following the color theme
#  sometimes": only in wal mode, and only until the next theme change.
#
#  (A first attempt to prove this compared $border_active and found it
#  UNCHANGED across both wallpapers, which looked like the bug and was not
#  evidence of it -- the wal generator emits the same first and last accent
#  for both images (#ee5b2b, #3cc2dd), so the cyan slot is simply not a
#  slot that varies. A staleness test has to read a field that moves.)
#
#  Guarded on the mode rather than run unconditionally, and placed here
#  rather than in wallpaper-sync.sh, because sync is also autostart.conf's
#  login hook -- re-deriving there would run a full theme regeneration on
#  every boot. This script is the "the user picked a new wallpaper" entry
#  point, which is exactly the event that should re-derive.
#
#  No recursion, and this now needs saying rather than observing:
#  theme-apply DOES set a wallpaper as of ask #5, but it does it through
#  `theme-wallpaper apply`, which pokes awww/xwallpaper directly and never
#  calls back into either of these scripts. The second guard is that
#  theme-apply skips the wallpaper entirely in wal mode, which is the only
#  mode in which the branch below re-enters theme-apply.
MODE_FILE="$HOME/.cache/qtile/theme_mode"

#  ---- A MANUAL PICK REBINDS THE CURRENT THEME (ask #5) ----
#
#  "Each theme has a default wallpaper, applied on theme change, and a
#  manual wallpaper choice still sticks." Those two only coexist under one
#  reading, which is the one the user chose: picking a wallpaper while a
#  named theme is active makes it THAT THEME'S wallpaper from then on.
#
#  Otherwise the next `theme-apply synthwave` would overwrite a choice made
#  thirty seconds earlier and the pick would not have stuck at all.
#
#  Not in wal mode: there the wallpaper drives the palette rather than
#  belonging to it, so there is no theme to bind it to. `theme-wallpaper
#  forget <theme>` puts the generated default back.
#
#  Non-fatal, like the re-derive below and for the same reason — the
#  wallpaper genuinely was applied by this point, and the island reads
#  this script's exit code to decide whether to report "applied".
mode="$(cat "$MODE_FILE" 2>/dev/null || true)"
# $_animated_x11's own branch above already did exactly this bind — same
# mode, same image, since neither can have changed in between — so this
# is skipped rather than repeated. Not merely a micro-optimisation:
# calling theme-wallpaper bind a second time is harmless on its own, but
# it is one more subprocess between the pick and the reveal on the path
# this session's own measurements said was the slow one.
if [ "$_animated_x11" != true ] && [ -n "$mode" ] && [ "$mode" != "wal" ] \
   && command -v theme-wallpaper >/dev/null 2>&1
then
    theme-wallpaper bind "$mode" "$img" \
        || echo "wallpaper-set: applied, but could not bind it to theme $mode" >&2
fi

if [ -r "$MODE_FILE" ] && [ "$(cat "$MODE_FILE" 2>/dev/null)" = "wal" ]; then
    # The wallpaper is already set and recorded by this point, so a
    # theme-apply failure must not fail this script: the island's picker
    # reads the exit code to decide whether to report "applied", and the
    # wallpaper genuinely was. Loud on stderr, non-fatal to the exit code.
    #
    # theme-animate rather than theme-apply directly: in wal mode a wallpaper
    # change IS a theme change, so it should look like one. Asked for in as
    # many words — "when I change the theme and wallpaper I want the same
    # animation of the island" — and this is the second half of it, since the
    # picker only covers the first. It hands the change to whichever shell can
    # draw the circular reveal and falls back to theme-apply when there is
    # none, so the failure branch below still means what it meant.
    # Guarded for the same reason theme-toggle guards it: theme-animate is a
    # new script and is absent until AtiScriptsV1/install.sh has been re-run.
    # `set -e` is on here, so an unguarded call to a missing command would end
    # this script — after the wallpaper was already applied and recorded, i.e.
    # at exactly the point where the caller reads the exit code to decide
    # whether to say "applied".
    if command -v theme-animate >/dev/null 2>&1; then
        theme_cmd=theme-animate
    else
        theme_cmd=theme-apply
    fi
    if ! "$theme_cmd" wal; then
        echo "wallpaper-set: wallpaper applied, but theme-apply wal failed;" \
             "colours are still from the previous image" >&2
    fi
fi
