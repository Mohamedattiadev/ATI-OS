#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================
# VARIABLES (HARDENED)
# =====================================================
USER_NAME="$(id -un)"

ARCH_CONFIG_DIR="$HOME/.config/arch-config"
HOSTS_DIR="$ARCH_CONFIG_DIR/hosts"
CONFIG_FILE="$ARCH_CONFIG_DIR/config.yaml"

: "${USER_NAME:?USER_NAME empty}"
: "${ARCH_CONFIG_DIR:?ARCH_CONFIG_DIR empty}"
: "${HOSTS_DIR:?HOSTS_DIR empty}"
: "${CONFIG_FILE:?CONFIG_FILE empty}"

# =====================================================
# SANITY CHECKS
# =====================================================
[[ -d "$HOSTS_DIR" ]] || {
  echo "ERROR: hosts directory not found:"
  echo "  $HOSTS_DIR"
  exit 1
}

[[ -f "$CONFIG_FILE" ]] || {
  echo "ERROR: config.yaml not found:"
  echo "  $CONFIG_FILE"
  exit 1
}

TARGET_HOST_FILE="$HOSTS_DIR/$USER_NAME.yaml"

# =====================================================
# FAST EXIT IF EVERYTHING IS ALREADY CORRECT
# =====================================================
if [[ -f "$TARGET_HOST_FILE" ]]; then
  HOST_IN_HOST_FILE="$(sed -n -E 's/^host:[[:space:]]*(.+)/\1/p' "$TARGET_HOST_FILE" | head -n1 || true)"
  HOST_IN_CONFIG_FILE="$(sed -n -E 's/^host:[[:space:]]*(.+)/\1/p' "$CONFIG_FILE" | head -n1 || true)"

  if [[ "$HOST_IN_HOST_FILE" == "$USER_NAME" && "$HOST_IN_CONFIG_FILE" == "$USER_NAME" ]]; then
    echo "OK   everything already in sync for host: $USER_NAME"
    exit 0
  fi
fi

# =====================================================
# BACKUP SETUP (ONLY AFTER WE KNOW CHANGES ARE NEEDED)
# =====================================================
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$ARCH_CONFIG_DIR/.backup-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "======================================"
echo "arch-config host sync"
echo "User       : $USER_NAME"
echo "Hosts dir  : $HOSTS_DIR"
echo "Backup dir : $BACKUP_DIR"
echo "======================================"
echo

# =====================================================
# HOST FILE ENSURE (STRICT)
# =====================================================
if [[ ! -f "$TARGET_HOST_FILE" ]]; then
  shopt -s nullglob
  HOST_FILES=("$HOSTS_DIR"/*.yaml)
  shopt -u nullglob

  if [[ "${#HOST_FILES[@]}" -eq 0 ]]; then
    echo "ERROR: no host YAML file found in:"
    echo "  $HOSTS_DIR"
    exit 1
  fi

  if [[ "${#HOST_FILES[@]}" -gt 1 ]]; then
    echo "ERROR: multiple host YAML files found:"
    for f in "${HOST_FILES[@]}"; do
      echo "  - $(basename "$f")"
    done
    echo "Refusing to guess. Keep exactly ONE."
    exit 1
  fi

  EXISTING_HOST_FILE="${HOST_FILES[0]}"
  EXISTING_NAME="$(basename "$EXISTING_HOST_FILE")"

  echo "RENAME host file:"
  echo "  $EXISTING_NAME -> $USER_NAME.yaml"

  cp "$EXISTING_HOST_FILE" "$BACKUP_DIR/$EXISTING_NAME"
  mv "$EXISTING_HOST_FILE" "$TARGET_HOST_FILE"
fi

# =====================================================
# UPDATE host FIELD INSIDE HOST YAML (IF NEEDED)
# =====================================================
CURRENT_HOST_IN_HOST_FILE="$(sed -n -E 's/^host:[[:space:]]*(.+)/\1/p' "$TARGET_HOST_FILE" | head -n1 || true)"

if [[ "$CURRENT_HOST_IN_HOST_FILE" != "$USER_NAME" ]]; then
  echo "Updating host inside $USER_NAME.yaml"

  cp "$TARGET_HOST_FILE" "$BACKUP_DIR/$USER_NAME.yaml"

  sed -i \
    -E "s/^host:[[:space:]]+.*/host: $USER_NAME/" \
    "$TARGET_HOST_FILE"
fi

# =====================================================
# UPDATE config.yaml POINTER (IF NEEDED)
# =====================================================
CURRENT_HOST_IN_CONFIG_FILE="$(sed -n -E 's/^host:[[:space:]]*(.+)/\1/p' "$CONFIG_FILE" | head -n1 || true)"

if [[ "$CURRENT_HOST_IN_CONFIG_FILE" != "$USER_NAME" ]]; then
  echo "Updating config.yaml pointer"

  cp "$CONFIG_FILE" "$BACKUP_DIR/config.yaml"

  sed -i \
    -E "s/^host:[[:space:]]+.*/host: $USER_NAME/" \
    "$CONFIG_FILE"
fi

# =====================================================
# DONE
# =====================================================
echo
echo "======================================"
echo "DONE ✅"
echo "Host is now set to: $USER_NAME"
echo "Backups stored in:"
echo "  $BACKUP_DIR"
echo "======================================"
