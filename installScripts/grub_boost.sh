#!/usr/bin/env bash
# grub_boost.sh — safe kernel cmdline tweaks. Backs up /etc/default/grub,
# adds selected flags to GRUB_CMDLINE_LINUX_DEFAULT, rebuilds grub.cfg.
#
# Idempotent: rerun safely, only adds flags that aren't already present.
#
# Revert:
#   sudo cp /etc/default/grub.bak.<TIMESTAMP> /etc/default/grub
#   sudo grub-mkconfig -o /boot/grub/grub.cfg && sudo reboot
set -Eeuo pipefail

# No RED: this script reports (ok/warn/skip) and never hard-fails.
GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; RESET="\033[0m"
info() { echo -e "${BLUE}==>${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }

[[ $EUID -ne 0 ]] || { echo "Run as your user (uses sudo)."; exit 1; }

# A machine booted by systemd-boot, rEFInd or a UKI has no /etc/default/grub —
# that is "nothing to do here", not a failure, so a wrapper running every module
# does not stop on it. Same for the rebuild binary: Arch/Debian call it
# grub-mkconfig, Fedora/openSUSE grub2-mkconfig. Resolve it BEFORE editing
# anything, otherwise we rewrite the cmdline and then die before regenerating
# grub.cfg — leaving a config that says one thing and a boot that does another.
[[ -f /etc/default/grub ]] || { echo "GRUB not in use (/etc/default/grub missing) — skipped."; exit 0; }
command -v sudo >/dev/null 2>&1 || { echo "sudo is required but not installed."; exit 1; }

MKCONFIG=""
for c in grub-mkconfig grub2-mkconfig; do
  command -v "$c" >/dev/null 2>&1 && { MKCONFIG="$c"; break; }
done
[[ -n "$MKCONFIG" ]] || { echo "grub-mkconfig/grub2-mkconfig not found — refusing to edit the cmdline."; exit 1; }

sudo -v

# --------- Detect GPU for i915.enable_guc=3 ---------
# lspci lives in pciutils, which a minimal install may not have; without it we
# just skip the Intel-only flag rather than erroring.
if command -v lspci >/dev/null 2>&1; then
  GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
else
  GPU_INFO=""
  warn "lspci not found (install pciutils) — skipping Intel GPU detection"
fi
INTEL=false
grep -qi intel <<<"$GPU_INFO" && INTEL=true

# --------- Build desired flag list ---------
FLAGS=(nowatchdog "quiet" "loglevel=3" "rd.udev.log_level=3" "vt.global_cursor_default=0")
$INTEL && FLAGS+=("i915.enable_guc=3")

echo
info "Proposed flags to ADD to GRUB_CMDLINE_LINUX_DEFAULT:"
for f in "${FLAGS[@]}"; do echo "    + $f"; done
echo
warn "SKIPPED (opt-in, less secure): mitigations=off  (10-30% CPU, disables Spectre/Meltdown)"
echo "  To add it later, edit /etc/default/grub manually."
echo

# `read` returns 1 at EOF, which under `set -e` kills the script before the
# default-to-no below ever runs. Piped/CI/non-tty invocations must fall through
# to "no", not die halfway with a bare exit code.
ans=""
read -rp "Proceed? [y/N] " ans || true
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted."; exit 0; }

# --------- Backup ---------
TS="$(date +%Y%m%d-%H%M%S)"
BAK="/etc/default/grub.bak.$TS"
sudo cp /etc/default/grub "$BAK"
ok "Backed up: $BAK"

# --------- Read current line ---------
CURRENT="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -1 || true)"
[[ -n "$CURRENT" ]] || { echo "GRUB_CMDLINE_LINUX_DEFAULT not found."; exit 1; }

# Extract the quoted contents, accepting single quotes as well.
#
# The old sed only matched the double-quoted form and, on no match, passed the
# WHOLE line through unchanged — so a single-quoted or unquoted cmdline ended up
# written back as GRUB_CMDLINE_LINUX_DEFAULT="GRUB_CMDLINE_LINUX_DEFAULT='quiet'
# nowatchdog ...", i.e. an unbootable-looking config produced silently. Anything
# we cannot parse with confidence must abort before the write, not be guessed at.
if [[ "$CURRENT" =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\"([^\"]*)\"[[:space:]]*$ ]]; then
  INNER="${BASH_REMATCH[1]}"
elif [[ "$CURRENT" =~ ^GRUB_CMDLINE_LINUX_DEFAULT=\'([^\']*)\'[[:space:]]*$ ]]; then
  INNER="${BASH_REMATCH[1]}"
else
  echo "Could not parse GRUB_CMDLINE_LINUX_DEFAULT — edit /etc/default/grub by hand:"
  echo "  $CURRENT"
  echo "(backup left at $BAK)"
  exit 1
fi

# Append missing flags
NEW="$INNER"
for f in "${FLAGS[@]}"; do
  key="${f%%=*}"
  if grep -qE "(^| )${key}(=|$| )" <<<"$NEW"; then
    echo "  ○ already present: $f"
  else
    NEW="$NEW $f"
    echo "  + added: $f"
  fi
done
NEW="$(sed -E 's/^ +| +$//g; s/ +/ /g' <<<"$NEW")"

# --------- Write ---------
sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW\"|" /etc/default/grub
ok "GRUB_CMDLINE_LINUX_DEFAULT = \"$NEW\""

# --------- Rebuild ---------
info "Rebuilding grub.cfg"
CFG=""
[[ -d /boot/grub  ]] && CFG=/boot/grub/grub.cfg
[[ -z "$CFG" && -d /boot/grub2 ]] && CFG=/boot/grub2/grub.cfg

if [[ -n "$CFG" ]]; then
  # A failed regeneration leaves /etc/default/grub edited but grub.cfg stale.
  # Say so and hand back the exact revert command instead of dying on set -e
  # with nothing on screen but a non-zero status.
  if ! sudo "$MKCONFIG" -o "$CFG"; then
    warn "$MKCONFIG failed — /etc/default/grub was edited but grub.cfg was NOT regenerated"
    echo "  revert: sudo cp $BAK /etc/default/grub"
    exit 1
  fi
else
  warn "grub.cfg location not found; rebuild manually with: sudo $MKCONFIG -o <path>"
fi

ok "DONE. Reboot to apply."
echo
echo "Revert with:"
echo "  sudo cp $BAK /etc/default/grub && sudo $MKCONFIG -o ${CFG:-/boot/grub/grub.cfg} && sudo reboot"
