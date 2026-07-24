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

RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; RESET="\033[0m"
info() { echo -e "${BLUE}==>${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }

[[ $EUID -ne 0 ]] || { echo "Run as your user (uses sudo)."; exit 1; }
[[ -f /etc/default/grub ]] || { echo "GRUB not detected (/etc/default/grub missing)."; exit 1; }

sudo -v

# --------- Detect GPU for i915.enable_guc=3 ---------
GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
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

read -rp "Proceed? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted."; exit 0; }

# --------- Backup ---------
TS="$(date +%Y%m%d-%H%M%S)"
BAK="/etc/default/grub.bak.$TS"
sudo cp /etc/default/grub "$BAK"
ok "Backed up: $BAK"

# --------- Read current line ---------
CURRENT="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | head -1)"
[[ -n "$CURRENT" ]] || { echo "GRUB_CMDLINE_LINUX_DEFAULT not found."; exit 1; }

# Extract quoted contents
INNER="$(sed -E 's/GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"/\1/' <<<"$CURRENT")"

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
if [[ -d /boot/grub ]]; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg
elif [[ -d /boot/grub2 ]]; then
  sudo grub-mkconfig -o /boot/grub2/grub.cfg
else
  warn "grub.cfg location not found; rebuild manually"
fi

ok "DONE. Reboot to apply."
echo
echo "Revert with:"
echo "  sudo cp $BAK /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg && sudo reboot"
