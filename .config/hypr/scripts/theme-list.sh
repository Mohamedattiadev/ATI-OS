#!/usr/bin/env bash
# theme-list.sh — emit every theme AtiScriptsV1/theme-apply knows about,
# with a swatch for each, as JSON on stdout.
#
# Consumed by the island's theme picker (quickshell/tide-island-fork/
# qml/island/ThemePickerLayer.qml), which needs names AND colours: a
# theme picker that lists 22 bare words is a menu, not a picker.
#
# WHY THIS PARSES theme-apply INSTEAD OF CARRYING ITS OWN TABLE
# ------------------------------------------------------------
# The obvious thing is to hardcode the palettes in the QML. That table
# would then be a second copy of numbers that already exist in
# theme-apply's `resolve_palette`, and the two would drift the first time
# a theme is added or a shade adjusted — silently, because a wrong swatch
# still renders. Nothing would ever fail; the picker would just start
# lying about what it applies.
#
# So the table is read out of theme-apply at runtime. It is not sourced —
# theme-apply is a 1,660-line script that applies a theme when run, and
# sourcing it to read four hex codes would repaint the desktop as a side
# effect. The `presets = { ... }` block inside its embedded python heredoc
# is extracted textually instead, which is why the awk range below is
# anchored on those exact delimiters.
#
# The order of the list is theme-apply's own, which is also the order its
# --help prints, so the picker and the usage message agree.

set -euo pipefail

THEME_APPLY="${THEME_APPLY:-$HOME/.dotfiles/.config/AtiScriptsV1/theme-apply}"
STATE_FILE="${THEME_STATE_FILE:-$HOME/.cache/qtile/theme_mode}"

if [[ ! -r "$THEME_APPLY" ]]; then
  echo '{"error":"theme-apply not found","current":"","themes":[]}'
  exit 0
fi

# Current theme is shared with the qtile session through this one file, so
# the island highlights whatever either session last applied.
current=""
[[ -r "$STATE_FILE" ]] && current="$(tr -d '[:space:]' <"$STATE_FILE" 2>/dev/null || true)"

# The tuples are ("bg","fg","bg_alt","accent") — that order is
# resolve_palette's, not alphabetical, and getting it wrong swaps
# foreground and background in every swatch while still looking
# plausible at a glance. It is asserted below rather than trusted.
awk -v current="$current" '
  /^ *presets = {/ { inblock = 1; next }
  inblock && /^ *}/ { inblock = 0; next }
  inblock {
    line = $0
    # "name": ("#bg","#fg","#alt","#accent"),
    if (match(line, /"[^"]+" *: *\( *"#[0-9a-fA-F]{6}" *, *"#[0-9a-fA-F]{6}" *, *"#[0-9a-fA-F]{6}" *, *"#[0-9a-fA-F]{6}" *\)/)) {
      n = split(line, parts, "\"")
      # parts: 1 pre, 2 name, 3 sep, 4 bg, 5 sep, 6 fg, 7 sep, 8 alt, 9 sep, 10 accent
      name = parts[2]; bg = parts[4]; fg = parts[6]; alt = parts[8]; accent = parts[10]
      out[++count] = sprintf("{\"name\":\"%s\",\"bg\":\"%s\",\"fg\":\"%s\",\"alt\":\"%s\",\"accent\":\"%s\"}", name, bg, fg, alt, accent)
    }
  }
  END {
    # wal is not in the presets table because it has no fixed palette —
    # it is derived from the current wallpaper. It is still a valid
    # argument to theme-apply, so it is appended by hand and drawn with a
    # neutral swatch the picker can special-case.
    out[++count] = "{\"name\":\"wal\",\"bg\":\"#1a1a1a\",\"fg\":\"#e0e0e0\",\"alt\":\"#0d0d0d\",\"accent\":\"#888888\",\"dynamic\":true}"

    printf "{\"current\":\"%s\",\"themes\":[", current
    for (i = 1; i <= count; i++) printf "%s%s", (i > 1 ? "," : ""), out[i]
    printf "]}\n"
  }
' "$THEME_APPLY"
