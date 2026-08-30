#!/usr/bin/env bash
# theme-list.sh — emit every theme AtiScriptsV1/theme/theme-apply knows about,
# with a swatch for each, as JSON on stdout.
#
# Consumed by the island's theme picker (quickshell/tide-island-fork/
# qml/island/ThemePickerLayer.qml), which needs names AND colours: a
# theme picker that lists 22 bare words is a menu, not a picker.
#
# WHY THIS READS themes/<mode>/colors.toml INSTEAD OF CARRYING ITS OWN TABLE
# ----------------------------------------------------------------------
# The obvious thing is to hardcode the palettes in the QML. That table
# would then be a second copy of numbers that already exist in
# AtiScriptsV1/themes/<mode>/colors.toml, and the two would drift the
# first time a theme is added or a shade adjusted — silently, because a
# wrong swatch still renders. Nothing would ever fail; the picker would
# just start lying about what it applies.
#
# So the swatches are read out of the same per-theme colors.toml files
# theme-apply itself now reads (see theme-apply's THEME_LOADED gate).
# This used to awk-scrape a `presets = { ... }` python dict out of
# theme-apply's source text instead — a workaround for there being no
# single source of truth at the time, now unnecessary since every preset
# has its own folder.
#
# The order is the same alphabetical order theme-apply derives its own
# PRESETS list in (both read the same themes/ directory the same way),
# so the picker and theme-apply's own usage message agree.

set -euo pipefail

THEMES_DIR="${THEMES_DIR:-$HOME/.dotfiles/.config/AtiScriptsV1/themes}"
STATE_FILE="${THEME_STATE_FILE:-$HOME/.cache/qtile/theme_mode}"

if [[ ! -d "$THEMES_DIR" ]]; then
  echo '{"error":"themes directory not found","current":"","themes":[]}'
  exit 0
fi

# Current theme is shared with the qtile session through this one file, so
# the island highlights whatever either session last applied.
current=""
[[ -r "$STATE_FILE" ]] && current="$(tr -d '[:space:]' <"$STATE_FILE" 2>/dev/null || true)"

_toml_get() { sed -n "s/^$2 = \"\\(.*\\)\"\$/\\1/p" "$1"; }

# ARCHITECTURE.md Phase 3's theme load point: plugins are a SECOND search
# path, not a copy into themes/. A plugin's palette lives at
# <plugin>/theme/colors.toml and is offered under the PLUGIN's name, since
# the directory itself is always called "theme".
#
# Searched live rather than materialised into themes/ by `ati-plugin sync`,
# and that is the whole reason this is a path and not a symlink farm: a
# theme is resolved by name at the moment the picker draws, so a stale copy
# would be a theme that keeps appearing after its plugin is gone -- and
# picking it would apply a palette read from a directory that no longer
# exists.
ATI_PLUGIN_DIR="${ATI_PLUGIN_DIR:-$HOME/.config/ati-plugins}"

_theme_dirs() {
  find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
  [[ -d "$ATI_PLUGIN_DIR" ]] &&
    find "$ATI_PLUGIN_DIR" -mindepth 2 -maxdepth 2 -type d -name theme -print0 2>/dev/null
}

out=()
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  # A plugin's palette directory is always literally "theme"; the name the
  # picker shows is the plugin's.
  [[ "$name" == "theme" ]] && name="$(basename "$(dirname "$dir")")"
  toml="$dir/colors.toml"
  [[ -f "$toml" ]] || continue
  bg="$(_toml_get "$toml" bg)"
  fg="$(_toml_get "$toml" fg)"
  alt="$(_toml_get "$toml" bg_alt)"
  accent="$(_toml_get "$toml" accent)"
  [[ -n "$bg" && -n "$fg" && -n "$alt" && -n "$accent" ]] || continue
  out+=("{\"name\":\"$name\",\"bg\":\"$bg\",\"fg\":\"$fg\",\"alt\":\"$alt\",\"accent\":\"$accent\"}")
done < <(_theme_dirs | sort -z)

# wal has no folder — it has no fixed palette, it's derived from the
# current wallpaper. Still a valid argument to theme-apply, so it's
# appended by hand and drawn with a neutral swatch the picker can
# special-case.
out+=('{"name":"wal","bg":"#1a1a1a","fg":"#e0e0e0","alt":"#0d0d0d","accent":"#888888","dynamic":true}')

printf '{"current":"%s","themes":[' "$current"
for i in "${!out[@]}"; do
  [[ $i -gt 0 ]] && printf ','
  printf '%s' "${out[$i]}"
done
printf ']}\n'
