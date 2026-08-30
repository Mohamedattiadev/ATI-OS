#!/usr/bin/env bash
# reorg-ati-scripts.sh — ARCHITECTURE.md Phase 1: group AtiScriptsV1 by
# concern, without renaming a single command.
#
#   ./reorg-ati-scripts.sh            # DRY RUN — prints the plan, changes nothing
#   ./reorg-ati-scripts.sh --apply    # does it
#
# WHY THIS IS A SCRIPT AND NOT A COMMIT
# -------------------------------------
# 105 files move at once, and three things in that directory make a blind
# `git mv` a way to break the desktop. Each is handled below, and each was
# found by looking rather than assumed:
#
#   1. `rofi` and `pcmanfm-qt` are SHIMS THAT SHADOW /usr/bin. They work only
#      because /usr/local/bin precedes /usr/bin on PATH. Grouping is safe --
#      the symlink is made from the BASENAME, which never changes -- but they
#      must not be renamed, ever.
#   2. `bar-action`, `theme-apply`, `theme-toggle`, `ui-scale`, `theme-animate`
#      and friends are RELATIVE SYMLINKS to their `ati-*` twins
#      (`bar-action -> ati-bar-action`). Move the target and leave the alias
#      and the link dangles. Both ends move together here.
#   3. The /usr/local/bin symlinks point at the OLD flat paths and need root
#      to repoint. Between the move and `sudo install.sh` every keybind would
#      be dead -- so this bridges through ~/.local/bin first, which needs no
#      root and PRECEDES /usr/local/bin on PATH (position 2 vs 11, measured).
#      Nothing is ever broken, not even for a second.
#   4. ABOUT A DOZEN THINGS REFERENCE THESE SCRIPTS BY ABSOLUTE PATH, and no
#      PATH bridge helps those. Found by grep, not assumed -- `ati-menu.json`
#      (Menu.qml and MenuLayer.qml), `theme-apply` (the island's shell.qml,
#      popups.qml and ThemePickerLayer.qml), `ati-translate-query`
#      (Translate.qml), `ati-simplenote-push` (sum-toggle.sh, sum_app.py and
#      nvim's autocmds.lua), `ati-reset-pc`, `rofi_anki`, `ati-ui-scale`,
#      `onboarding-first-run`, `ati-bar-action`. Move the files without
#      rewriting these and the menu, theme switching and notes sync all
#      break. Step 3 below rewrites every one, in comments as well as code --
#      a comment pointing at a path that no longer exists is a lie the next
#      reader has to disprove.
#
# install.sh already recurses (see its own note), so a grouped tree links
# exactly as a flat one did.
set -uo pipefail

# Overridable so the whole thing can be rehearsed against a COPY of the repo
# before it is ever pointed at the real one. That rehearsal is not optional
# for a change this wide -- see the header.
DIR="${REORG_DIR:-$HOME/.config/AtiScriptsV1}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

cd "$DIR" || { printf 'no %s\n' "$DIR" >&2; exit 1; }

# ---------------------------------------------------------------------------
#  The mapping. Prefix-matched, first hit wins, longest patterns first.
#  Anything unmatched stays in the root -- deliberately: an unrecognised
#  script should be visible in the top level, not silently filed somewhere
#  wrong.
# ---------------------------------------------------------------------------
group_for() {
    case "$1" in
        # data + shared code, never commands in their own right
        ati-rofi-common.sh|rofi_common.sh|rofi_shared|ati_palette.py) echo lib ;;
        ati-menu.json|ati-menu-extensions.json|ati-emoji-data.json)   echo lib ;;
        # shims shadowing real binaries -- grouped, never renamed
        rofi|pcmanfm-qt)                                              echo shims ;;
        ati-capture-*|ati-satty|ati-record|ati-transcode|ati-phone-screen) echo capture ;;
        ati-clip-*|ati-copyq-*)                                       echo clipboard ;;
        ati-theme-*|theme-*|ati-wal-*|ati-dm-setbg)                   echo theme ;;
        ati-bar-action|bar-action|bar-switch|bar-chooser)             echo bar ;;
        ati-todos-append|ati-note-capture|ati-simplenote-push|ati-reminder|rofi_todo) echo notes ;;
        ati-translate-*|rofi_translator|dm-spellcheck)                echo translate ;;
        ati-voice-*)                                                  echo voice ;;
        ati-install-gaming-*|ati-webapp-*|ati-launch-webapp|ati-default-app) echo apps ;;
        ati-keymaps|ati-keybindings|ati-qtile-keys|ati-keyboard-layout-watcher) echo input ;;
        ati-emoji-insert|ati-ui-scale|ui-scale*|ati-do)               echo input ;;
        # ati-adhkar left this tree entirely in ARCHITECTURE.md Phase 4 --
        # it is plugins/adhkar/bin/ati-adhkar now. The mapping stays because
        # this script is the RECORD of the Phase 1 move, and rewriting
        # history to match a later phase would make it stop describing what
        # it actually did.
        ati-adhkar)                                                   echo islam ;;
        ati-menu|ati-menu-select|ati-docs|ati-onboarding-cheatsheet|onboarding-first-run) echo menu ;;
        rofi_anki|rofi_windows|rofi_light|ati-kill|ati-pass|ati-ilovepdf|dm-confedit) echo menu ;;
        ati-update|safe-update|pacman-preflight|ati-post-update-notify) echo update ;;
        ati-disk-*|ati-battery-notify|battery-events|ati-dns-set|ati-network-speedtest*) echo system ;;
        ati-reset-pc|ati-logout|dm-logout|ati-stay-awake|boot-splash|ati-edit-config) echo system ;;
        ati-hook|ati-hook-install|ati-run-in-terminal|clock_popup)    echo system ;;
        omarchy-font-*)                                               echo theme ;;
        *) echo "" ;;
    esac
}

moves=()
while IFS= read -r f; do
    name="$(basename "$f")"
    [[ "$name" == "install.sh" ]] && continue
    g="$(group_for "$name")"
    [[ -n "$g" ]] || continue
    moves+=("$name|$g")
done < <(find . -maxdepth 1 -type f -o -maxdepth 1 -type l | sed 's|^\./||' | sort)

printf '%-42s -> %s\n' "SCRIPT" "GROUP"
printf '%s\n' "-------------------------------------------------------------"
for m in "${moves[@]}"; do printf '%-42s -> %s/\n' "${m%%|*}" "${m##*|}"; done
printf '\n%s files grouped, %s left in the root\n' \
    "${#moves[@]}" "$(( $(find . -maxdepth 1 \( -type f -o -type l \) | wc -l) - ${#moves[@]} - 1 ))"

if (( ! APPLY )); then
    printf '\nDRY RUN. Nothing changed. Re-run with --apply to do it.\n'
    exit 0
fi

# ---- 1. bridge FIRST, so nothing is ever unresolvable ----
mkdir -p "${REORG_BIN:-$HOME/.local/bin}"
for m in "${moves[@]}"; do
    name="${m%%|*}"; g="${m##*|}"
    ln -sfn "$DIR/$g/$name" "${REORG_BIN:-$HOME/.local/bin}/$name"
done
printf 'bridged %s commands through ~/.local/bin\n' "${#moves[@]}"

# ---- 2. move, preserving git history ----
for m in "${moves[@]}"; do
    name="${m%%|*}"; g="${m##*|}"
    mkdir -p "$g"
    git -C "$DIR" mv "$name" "$g/$name" 2>/dev/null || mv "$name" "$g/$name"
done

# ---- 3. rewrite every absolute reference to a moved script ----
# Repo-wide, both sessions, every language. Only names that actually moved are
# touched, so `AtiScriptsV1/themes` (data, stays put) and `install.sh` are
# untouched automatically rather than by exception.
REPO="${REORG_REPO:-$HOME/.dotfiles}"
rewrites=0
# perl with a NEGATIVE LOOKAHEAD, not sed with \b, and this is not a style
# choice. \b sits between a word character and a non-word one, and both `-`
# and `.` are non-word -- so `AtiScriptsV1/menu/ati-menu\b` MATCHES INSIDE
# `AtiScriptsV1/lib/ati-menu.json`, and the menu's data file gets rewritten by
# the rule for the `ati-menu` script into a group it does not belong to.
# Same collision hit ati-theme-wallpaper vs ati-theme-wallpaper-fetch. Both
# were caught by rehearsing this against a copy of the repo; neither shows up
# until something silently fails to load.
#
# The lookahead says "not followed by another name character", which is the
# boundary that actually applies to these names. \Q..\E so a dot in a name
# is a literal dot.
for m in "${moves[@]}"; do
    name="${m%%|*}"; g="${m##*|}"
    while IFS= read -r hit; do
        perl -pi -e "s{AtiScriptsV1/\Q${name}\E(?![A-Za-z0-9_.-])}{AtiScriptsV1/${g}/${name}}g" "$hit"
        rewrites=$((rewrites + 1))
    done < <(grep -rlF --exclude-dir=.git --exclude-dir=__pycache__ \
                  "AtiScriptsV1/${name}" "$REPO" 2>/dev/null || true)
done
printf 'rewrote %s absolute references\n' "$rewrites"

# ---- 4. rewrite SIBLING references: "$SCRIPT_DIR/<name>" ----
#
# The step this procedure was missing, and the one that actually broke things
# when it first ran for real. 35 scripts open with
#
#     SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
#     source "$SCRIPT_DIR/ati-rofi-common.sh"
#
# -- and the library landed in lib/ while its callers went to input/, notes/,
# capture/ and the rest, so every one of them died on a missing file. The
# absolute-path sweep in step 3 does not see these: they are relative, and
# they are relative to a directory that just changed.
#
# Every script is now exactly ONE level deep, so "../" is uniformly correct.
# The target's real group is looked up from where files actually ARE after
# the move, not from the mapping table, so this stays right even if the
# mapping is edited. themes/, patches/ and hooks/ stayed in the root and are
# rewritten to "../<dir>".
python3 - "$DIR" <<'PYEOF'
import os, re, sys
D = sys.argv[1]
loc = {}
for g in os.listdir(D):
    p = os.path.join(D, g)
    if not os.path.isdir(p) or g == "__pycache__":
        continue
    for f in os.listdir(p):
        loc[f] = g
roots = {"themes", "patches", "hooks"}
changed = 0
for g in os.listdir(D):
    p = os.path.join(D, g)
    if not os.path.isdir(p) or g == "__pycache__":
        continue
    for fn in os.listdir(p):
        fp = os.path.join(p, fn)
        if not os.path.isfile(fp) or os.path.islink(fp):
            continue
        try:
            s = open(fp, encoding="utf-8").read()
        except Exception:
            continue
        def fix(m):
            t = m.group(1)
            if t in roots:
                return "$SCRIPT_DIR/../" + t
            if t in loc:
                return "$SCRIPT_DIR/../" + loc[t] + "/" + t
            return m.group(0)
        o = s
        s = re.sub(r"\$SCRIPT_DIR/([A-Za-z0-9_][A-Za-z0-9_.-]*)", fix, s)
        if s != o:
            open(fp, "w", encoding="utf-8").write(s)
            changed += 1
print(f"rewrote sibling references in {changed} scripts")
PYEOF

# ---- 5. repair relative alias symlinks whose target moved with them ----
# `bar-action -> ati-bar-action` still resolves when both ended up in the
# same group, and that is how the mapping is written -- but it is asserted
# rather than assumed, because a silently dangling alias is a dead keybind.
bad=0
while IFS= read -r l; do
    [[ -e "$l" ]] || { printf 'DANGLING ALIAS: %s -> %s\n' "$l" "$(readlink "$l")" >&2; bad=1; }
done < <(find . -type l)
(( bad )) && printf '\nSome aliases dangle. Fix before running install.sh.\n' >&2

printf '\nDone. Now run:  sudo %s/install.sh\n' "$DIR"
printf 'Until you do, the ~/.local/bin bridge keeps every command working.\n'
