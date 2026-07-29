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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/wizard.sh" --yes "$@"
