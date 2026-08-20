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

for f in "$SCRIPT_DIR"/*; do
    [[ -d "$f" ]] && continue
    name="$(basename "$f")"
    [[ "$name" == "install.sh" ]] && continue
    chmod +x "$f"
    sudo ln -sfn "$f" "/usr/local/bin/$name"
    # Purge stale ~/.local/bin copies (older install path).
    if [[ -f "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]]; then
        rm -f "$HOME/.local/bin/$name"
        ln -sfn "$f" "$HOME/.local/bin/$name"
    elif [[ -L "$HOME/.local/bin/$name" ]] && [[ "$(readlink "$HOME/.local/bin/$name")" != "$f" ]]; then
        ln -sfn "$f" "$HOME/.local/bin/$name"
    fi
done

echo "AtiScriptsV1 → symlinked to /usr/local/bin (edits in dotfiles apply immediately)."
