#!/usr/bin/env bash
set -Eeuo pipefail

# =======================
# PATHS
# =======================
DOTFILES_DIR="$HOME/.dotfiles"
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
mkdir -p "$BACKUP_DIR"

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
stow -v -t ~ .

echo
echo "======================"
echo "DONE ✅"
echo "======================"
