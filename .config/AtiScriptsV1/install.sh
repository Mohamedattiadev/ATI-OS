#!/bin/bash
# Symlink every regular file to /usr/local/bin so future edits in
# dotfiles apply immediately. Old behavior (`cp`) left stale copies
# after every dotfiles update — theme-toggle / theme-apply silently
# diverged from source until re-run. Also purges any stale copies in
# ~/.local/bin (older install path; PATH-precedes /usr/local/bin so
# the stale copy wins otherwise).

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
#  qsipc — the one binary here that gets COMPILED, not symlinked
# ---------------------------------------------------------------------------
# Its source lives in hypr/scripts/qsipc.cpp, not here: this directory's own
# promise (see the header above) is "every file here is what runs", and a
# .cpp can't be that. See qsipc.cpp's own header for what it is and why —
# `qs ipc call`'s ~40ms is pure process-startup cost for the whole
# quickshell binary (94 linked libs), and this links only Qt6Core +
# Qt6Network to make the same call in 15-20ms.
#
# Rebuilt only when the source is newer than the installed binary, so a
# plain re-run of this script after every dotfiles pull stays fast. Never
# fatal: base-devel and qt6-base are already required elsewhere in this
# repo's package modules, but a machine missing either should still finish
# installing everything else rather than dying on one optimisation.
QSIPC_SRC="$SCRIPT_DIR/../hypr/scripts/qsipc.cpp"
QSIPC_BIN="/usr/local/bin/qsipc"
if [[ -f "$QSIPC_SRC" ]] && { [[ ! -x "$QSIPC_BIN" ]] || [[ "$QSIPC_SRC" -nt "$QSIPC_BIN" ]]; }; then
    if command -v g++ >/dev/null 2>&1 && pkg-config --exists Qt6Core Qt6Network 2>/dev/null; then
        tmp="$(mktemp)"
        if g++ -std=c++20 -O2 $(pkg-config --cflags Qt6Core Qt6Network) \
               "$QSIPC_SRC" -o "$tmp" $(pkg-config --libs Qt6Core Qt6Network); then
            sudo install -m755 "$tmp" "$QSIPC_BIN"
            echo "qsipc → built and installed to $QSIPC_BIN"
        else
            echo "qsipc → build failed, leaving any existing $QSIPC_BIN in place" >&2
        fi
        rm -f "$tmp"
    else
        echo "qsipc → g++/Qt6 dev files not found, skipping (falls back to qs ipc call)" >&2
    fi
fi

# ---- RECURSES, so the scripts can be grouped into subdirectories ----
#
# This was `for f in "$SCRIPT_DIR"/*` with `[[ -d ]] && continue`, i.e. flat
# only. That is the single thing standing between this directory and being
# grouped by concern (ARCHITECTURE.md, Phase 1): the moment a script moves
# into a subdirectory the old loop stops seeing it, and its /usr/local/bin
# symlink dangles.
#
# WHAT COUNTS AS A COMMAND, once this recurses:
#
#   * everything directly in this directory, as before -- chmod'd and linked
#     whether or not it already had the bit;
#   * in a SUBdirectory, only files that are ALREADY EXECUTABLE.
#
# That second rule is what keeps the existing subdirectories out of PATH
# without naming them: themes/ (21 palettes), __pycache__/ (18 .pyc),
# patches/ and hooks/ hold DATA, and not one file under them is executable --
# checked. A grouped script, by contrast, arrives with its bit already set,
# so it is picked up automatically. No allow-list to keep in sync, and a
# stray README or .pyc can never become a command.
#
# The COMMAND NAME IS STILL THE BASENAME. Nothing about grouping changes what
# anything is called -- `ati-satty` stays `ati-satty` whether it lives here or
# in capture/. That matters beyond tidiness: `rofi` and `pcmanfm-qt` in this
# directory are deliberate shims that SHADOW the real binaries in /usr/bin,
# and they only work because /usr/local/bin precedes it on PATH.
while IFS= read -r f; do
    name="$(basename "$f")"
    # Subdirectory files must already be executable -- see the note above.
    [[ "$(dirname "$f")" == "$SCRIPT_DIR" || -x "$f" ]] || continue
    chmod +x "$f"
    sudo ln -sfn "$f" "/usr/local/bin/$name"
    # Purge stale ~/.local/bin copies (older install path).
    if [[ -f "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]]; then
        rm -f "$HOME/.local/bin/$name"
        ln -sfn "$f" "$HOME/.local/bin/$name"
    elif [[ -L "$HOME/.local/bin/$name" ]] && [[ "$(readlink "$HOME/.local/bin/$name")" != "$f" ]]; then
        ln -sfn "$f" "$HOME/.local/bin/$name"
    fi
done < <(find -L "$SCRIPT_DIR" -type f -not -name install.sh \
              -not -path '*/__pycache__/*' | sort)

# Prune dangling symlinks left behind by a rename: the loop above only
# ever adds/updates a link for a file that currently exists here, so a
# renamed or deleted script's OLD name stays behind in /usr/local/bin
# (and ~/.local/bin) forever, pointing at nothing, until something
# removes it. Scoped to symlinks that point INSIDE this directory, so a
# rename here can never touch an unrelated dangling link for some other
# reason (a half-installed package, etc).
#
# Canonicalize both sides with readlink -f before comparing, not a plain
# string prefix match: SCRIPT_DIR resolves differently depending on
# whether install.sh was invoked through the stow symlink
# (~/.config/AtiScriptsV1) or the real checkout (~/.dotfiles/.config/
# AtiScriptsV1) it points at -- same files, two different path strings.
# readlink -f canonicalizes a dangling symlink's target fine even though
# the final component doesn't exist, since only that last component is
# missing; every directory above it is real (the stow symlink itself).
# A naive prefix match against the un-resolved $SCRIPT_DIR silently
# missed every link created via the other invocation style -- caught by
# creating a synthetic dangling link the same way the real stale ones
# were shaped, and confirming the prune actually fired on it.
REAL_SCRIPT_DIR="$(readlink -f "$SCRIPT_DIR")"
for bindir in /usr/local/bin "$HOME/.local/bin"; do
    [[ -d "$bindir" ]] || continue
    for link in "$bindir"/*; do
        [[ -L "$link" ]] || continue
        real_target="$(readlink -f "$link")"
        [[ "$real_target" == "$REAL_SCRIPT_DIR"/* ]] || continue
        [[ -e "$real_target" ]] && continue
        if [[ -w "$bindir" ]]; then
            rm -f "$link"
        else
            sudo rm -f "$link"
        fi
        echo "AtiScriptsV1 → removed stale link $link (target no longer exists: $real_target)"
    done
done

echo "AtiScriptsV1 → symlinked to /usr/local/bin (edits in dotfiles apply immediately)."
