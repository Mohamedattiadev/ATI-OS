#!/usr/bin/env bash
set -Eeuo pipefail

# =======================
# PATHS
# =======================
# Derived from where this script actually lives, not assumed to be ~/.dotfiles:
# the repo is routinely checked out elsewhere (a clone under a different name, a
# git worktree, /tmp during container tests) and hardcoding the path made the
# script silently stow a *different* checkout than the one it was run from.
# DOTFILES_DIR can still be overridden explicitly.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
CONFIG_SRC="$DOTFILES_DIR/.config"
CONFIG_DST="$HOME/.config"
BACKUP_ROOT="$HOME/DefaultConfig"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

# Plasma / system configs to ignore
IGNORE=(
  kdeglobals
  plasmashellrc
  kwinrc
  ksmserverrc
  install.sh
  hintsConfig.py
  gromit-mpx.cfg
)

# =======================
# SETUP
# =======================
command -v stow >/dev/null 2>&1 || {
  echo "ERROR: GNU stow is not installed."
  echo "  Arch: sudo pacman -S stow   Debian/Ubuntu: sudo apt install stow"
  exit 1
}
[[ -d "$CONFIG_SRC" ]] || {
  echo "ERROR: $CONFIG_SRC not found — is $DOTFILES_DIR really the dotfiles repo?"
  exit 1
}

# Anything .stow-local-ignore excludes must not be backed up either: moving a
# file stow was never going to link just relocates the user's data for nothing.
if [[ -f "$DOTFILES_DIR/.stow-local-ignore" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* || "$line" == */* ]] && continue
    IGNORE+=("$line")
  done < "$DOTFILES_DIR/.stow-local-ignore"
fi

mkdir -p "$BACKUP_DIR"
# Ensure ~/.config exists so stow descends into it instead of folding the whole
# dir into a single symlink (would pollute the repo with future app configs).
mkdir -p "$CONFIG_DST"

echo "======================================"
echo "Dotfiles stow script"
echo "Dotfiles: $DOTFILES_DIR"
echo "Backup:   $BACKUP_DIR"
echo "======================================"
echo

# =======================
# HELPERS
# =======================
should_ignore() {
  local name="$1"
  for ignore in "${IGNORE[@]}"; do
    [[ "$name" == "$ignore" ]] && return 0
  done
  return 1
}

# =======================
# BACKUP DEFAULT CONFIGS
# =======================
shopt -s dotglob nullglob

# Top-level dotfiles (~/.tmux.conf and friends) were never backed up, so on any
# machine that already had one stow aborted with a conflict and the whole
# install stopped. Only regular FILES are moved: an existing directory is not a
# conflict, stow just descends into it, and moving e.g. a real ~/.claude out
# from under the user would be destructive rather than helpful.
for src in "$DOTFILES_DIR"/*; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  dst="$HOME/$name"

  should_ignore "$name" && continue
  [[ -L "$dst" ]] && { echo "OK   (already symlinked): $name"; continue; }

  if [[ -e "$dst" ]]; then
    echo "MOVE (default -> backup): $name"
    mv "$dst" "$BACKUP_DIR/"
  fi
done

for src in "$CONFIG_SRC"/*; do
  name="$(basename "$src")"
  dst="$CONFIG_DST/$name"

  if should_ignore "$name"; then
    echo "SKIP (ignored): $name"
    continue
  fi

  if [ -L "$dst" ]; then
    echo "OK   (already symlinked): $name"
    continue
  fi

  if [ -e "$dst" ]; then
    echo "MOVE (default -> backup): $name"
    mv "$dst" "$BACKUP_DIR/"
  else
    echo "OK   (not present): $name"
  fi
done

# =======================
# STOW
# =======================
echo
echo "======================"
echo "Running stow"
echo "======================"
cd "$DOTFILES_DIR"
# ~/.config already exists (mkdir -p above), so stow descends into it and
# creates per-subdir symlinks (~/.config/qtile -> repo, etc.) instead of
# folding the whole dir into one symlink and polluting the repo.
if ! stow -v -t "$HOME" .; then
  echo
  echo "ERROR: stow reported conflicts (listed above)."
  echo "Move or delete the conflicting files, then rerun."
  echo "Anything already backed up is in: $BACKUP_DIR"
  exit 1
fi

# A run where nothing needed backing up used to leave an empty timestamped dir
# behind in ~/DefaultConfig every single time.
rmdir "$BACKUP_DIR" 2>/dev/null && echo "(nothing needed backing up)" || true

echo
echo "======================"
echo "DONE ✅"
echo "======================"
