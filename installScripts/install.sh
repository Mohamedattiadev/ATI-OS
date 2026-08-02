#!/usr/bin/env bash
# install.sh — deprecated wrapper. All logic now lives in wizard.sh.
#
# Kept as an alias so existing muscle-memory / docs / bookmarks
# ("./install.sh") keep working: it just runs the wizard in
# unattended mode (all modules pre-selected, no prompts).
#
# For the interactive experience:  ./wizard.sh
# For dry-run preview:              ./wizard.sh --dry-run

set -e
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# `exec` on a missing or non-executable target dies with a bare shell error and
# no hint that the real entry point is wizard.sh — say it plainly instead.
if [[ ! -x "$SCRIPT_DIR/wizard.sh" ]]; then
  echo "ERROR: $SCRIPT_DIR/wizard.sh is missing or not executable." >&2
  echo "       chmod +x installScripts/wizard.sh, or run it directly." >&2
  exit 1
fi
exec "$SCRIPT_DIR/wizard.sh" --yes "$@"
