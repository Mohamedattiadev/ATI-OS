#!/bin/bash
# Symlink every regular file to /usr/local/bin so future edits in
# dotfiles apply immediately. Old behavior (`cp`) left stale copies
# after every dotfiles update — theme-toggle / theme-apply silently
# diverged from source until re-run. Also purges any stale copies in
# ~/.local/bin (older install path; PATH-precedes /usr/local/bin so
# the stale copy wins otherwise).

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
