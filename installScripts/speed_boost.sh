#!/usr/bin/env bash
# speed_boost.sh — safe, reversible CPU / RAM / GPU / IO tweaks for Arch.
# Idempotent: rerun anytime. Every change is easy to undo (paths noted in comments).
#
# What it does:
#   1. zram-generator swap (RAM-backed)  -> revert: rm /etc/systemd/zram-generator.conf
#   2. VM tunables matched to zram       -> revert: rm /etc/sysctl.d/99-zram.conf
#   3. earlyoom                          -> revert: systemctl disable --now earlyoom
#   4. auto-cpufreq                      -> revert: systemctl disable --now auto-cpufreq
#   5. pacman ParallelDownloads + color  -> revert: edit /etc/pacman.conf
#   6. pacman NoExtract non-EN locales   -> revert: remove NoExtract line
#   7. journald size cap (200M)          -> revert: rm /etc/systemd/journald.conf.d/00-size.conf
#   8. GPU: enable VAAPI/vulkan drivers if detected (Intel / AMD / NVIDIA)
#   9. Preload dbus (fast IPC) — safe no-op if already enabled
#
# NOT included (needs bootloader edit, reboot):
#   - GRUB kernel cmdline (i915.enable_guc=3, mitigations=off, nowatchdog)
#   Print manual instructions at end.

set -Eeuo pipefail

RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; RESET="\033[0m"
info() { echo -e "${BLUE}==>${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
skip() { echo -e "${YELLOW}○${RESET} $*"; }

[[ $EUID -ne 0 ]] || { echo "Run as your user (not root). Uses sudo internally."; exit 1; }
[[ -f /etc/arch-release ]] || { echo "Arch only."; exit 1; }

info "Refreshing sudo credentials"
sudo -v

# =====================================================
# 1. zram-generator
# =====================================================
info "[1/9] zram-generator"

if ! pacman -Q zram-generator &>/dev/null; then
  sudo pacman -S --needed --noconfirm zram-generator
fi

# Sized `ram`, not `ram / 2`.
#
# This used to be min(ram/2, 4096). On the 8G laptop that gave 3.8G of zram,
# and a normal browsing session filled it to 100% — at which point earlyoom
# started SIGTERMing Brave renderer processes and tabs died with Chromium's
# "Aw, Snap! Error code 61696". The kill was correct behaviour; the machine
# was genuinely out of memory.
#
# zram is compressed RAM, not disk: with zstd, mixed browser heap compresses
# around 3:1, so a 7.6G zram device costs roughly 2.5G of real RAM when full
# while absorbing ~7.6G of anonymous pages. Sizing it at `ram` is what Fedora
# ships by default and roughly doubles the headroom before earlyoom fires.
ZRAM_CONF=/etc/systemd/zram-generator.conf
ZRAM_WANT='[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
swap-priority = 100'

# Rewrite whenever the content differs, rather than skipping on the mere
# presence of a [zram0] section. The old check meant an existing machine kept
# whatever size it was first given — including the undersized default that
# caused the OOM kills — and never picked up this change.
if [[ ! -f "$ZRAM_CONF" ]] || ! diff -q <(printf '%s\n' "$ZRAM_WANT") "$ZRAM_CONF" &>/dev/null; then
  [[ -f "$ZRAM_CONF" ]] && sudo cp "$ZRAM_CONF" "$ZRAM_CONF.bak"
  printf '%s\n' "$ZRAM_WANT" | sudo tee "$ZRAM_CONF" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl start /dev/zram0 2>/dev/null || true
  ok "zram-generator configured (size = min(ram, 8192))"
  warn "resize needs a reboot — the running zram0 keeps its old size until then"
else
  skip "zram already configured correctly"
fi

# =====================================================
# 2. VM tunables for zram
# =====================================================
info "[2/9] VM tunables (zram-aware)"

# The kernel defaults assume swap is a slow spinning disk. With zram, swapping
# is a memcpy plus a zstd round-trip — cheap enough that the kernel should
# reach for it early instead of thrashing page cache and then OOM-killing.
#
#   swappiness 180        cost-of-swap now well below cost-of-refault; 60 left
#                         zram mostly idle while the machine ran out of memory
#   page-cluster 0        no readahead — zram has no seek penalty, so batching
#                         4 pages per fault just wastes decompression work
#   watermark_boost_factor 0
#                         disables the reclaim boost that causes latency spikes
#                         when zram is the backing store
#   watermark_scale_factor 125
#                         start reclaiming a little earlier, so there is slack
#                         when a browser allocates in a burst
#
# These are the values Fedora ships alongside zram. Revert: rm this file.
SYSCTL_ZRAM=/etc/sysctl.d/99-zram.conf
SYSCTL_WANT='# Written by ~/.dotfiles/installScripts/speed_boost.sh
# Tuned for zram-backed swap. Revert: sudo rm /etc/sysctl.d/99-zram.conf
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125'

if [[ ! -f "$SYSCTL_ZRAM" ]] || ! diff -q <(printf '%s\n' "$SYSCTL_WANT") "$SYSCTL_ZRAM" &>/dev/null; then
  printf '%s\n' "$SYSCTL_WANT" | sudo tee "$SYSCTL_ZRAM" >/dev/null
  sudo sysctl -q --load="$SYSCTL_ZRAM"
  ok "vm tunables applied (swappiness=180, page-cluster=0)"
else
  skip "vm tunables already set"
fi

# =====================================================
# 3. earlyoom
# =====================================================
info "[3/9] earlyoom"

if ! pacman -Q earlyoom &>/dev/null; then
  sudo pacman -S --needed --noconfirm earlyoom
fi
if ! systemctl is-enabled earlyoom.service &>/dev/null; then
  sudo systemctl enable --now earlyoom.service
  ok "earlyoom enabled"
else
  skip "earlyoom already enabled"
fi

# =====================================================
# 4. auto-cpufreq
# =====================================================
info "[4/9] auto-cpufreq"

if pacman -Q auto-cpufreq &>/dev/null; then
  if ! systemctl is-enabled auto-cpufreq.service &>/dev/null; then
    sudo systemctl enable --now auto-cpufreq.service
    ok "auto-cpufreq enabled"
  else
    skip "auto-cpufreq already enabled"
  fi
else
  warn "auto-cpufreq not installed (add to dcli or: yay -S auto-cpufreq)"
fi

# =====================================================
# 5. pacman.conf tweaks
# =====================================================
info "[5/9] pacman.conf tweaks"

sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
sudo sed -i 's/^#\?Color/Color/' /etc/pacman.conf

if ! grep -q '^ILoveCandy' /etc/pacman.conf; then
  sudo sed -i '/^# Misc options/a ILoveCandy' /etc/pacman.conf 2>/dev/null || true
fi
ok "ParallelDownloads=5, Color, ILoveCandy set"

# =====================================================
# 6. pacman NoExtract non-EN locales
# =====================================================
info "[6/9] Skip non-English locale extraction"

if ! grep -q '^NoExtract.*usr/share/locale' /etc/pacman.conf; then
  sudo sed -i '/^\[options\]/a NoExtract = usr/share/locale/* !usr/share/locale/en* !usr/share/locale/ar* !usr/share/locale/de* !usr/share/locale/tr*' /etc/pacman.conf
  ok "NoExtract locales added (keeping en, ar, de, tr)"
else
  skip "NoExtract already set"
fi

# =====================================================
# 7. journald size cap
# =====================================================
info "[7/9] journald cap"

sudo mkdir -p /etc/systemd/journald.conf.d
JC=/etc/systemd/journald.conf.d/00-size.conf
if [[ ! -f "$JC" ]]; then
  sudo tee "$JC" >/dev/null <<'EOF'
[Journal]
SystemMaxUse=200M
SystemKeepFree=1G
RuntimeMaxUse=100M
EOF
  sudo systemctl restart systemd-journald
  ok "journald capped (200M)"
else
  skip "journald already capped"
fi

# =====================================================
# 8. GPU drivers by detection
# =====================================================
info "[8/9] GPU drivers"

GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
echo "  detected: $GPU_INFO"

install_if_missing() {
  local pkgs=("$@")
  local to_install=()
  for p in "${pkgs[@]}"; do
    pacman -Q "$p" &>/dev/null || to_install+=("$p")
  done
  if [[ ${#to_install[@]} -gt 0 ]]; then
    sudo pacman -S --needed --noconfirm "${to_install[@]}"
  fi
}

if grep -qi intel <<<"$GPU_INFO"; then
  info "  Intel GPU → mesa + vulkan-intel + intel-media-driver"
  install_if_missing mesa vulkan-intel intel-media-driver libva-intel-driver libva-utils
  ok "Intel drivers ok"
fi

if grep -qi 'amd\|radeon' <<<"$GPU_INFO"; then
  info "  AMD GPU → mesa + vulkan-radeon + libva-mesa-driver"
  install_if_missing mesa vulkan-radeon libva-mesa-driver mesa-vdpau libva-utils
  ok "AMD drivers ok"
fi

if grep -qi nvidia <<<"$GPU_INFO"; then
  info "  NVIDIA GPU → nvidia + nvidia-utils + libva-nvidia-driver"
  warn "  NVIDIA install may need dkms + kernel headers; verify boot before rebooting."
  install_if_missing nvidia-open nvidia-utils libva-nvidia-driver || \
    install_if_missing nvidia nvidia-utils libva-nvidia-driver
  ok "NVIDIA drivers ok"
fi

if [[ -z "$GPU_INFO" ]]; then
  skip "  No GPU detected"
fi

# =====================================================
# 9. dbus-broker (faster D-Bus daemon)
# =====================================================
info "[9/9] dbus-broker"

if ! pacman -Q dbus-broker &>/dev/null; then
  sudo pacman -S --needed --noconfirm dbus-broker
fi
if ! systemctl is-enabled dbus-broker.service &>/dev/null; then
  sudo systemctl enable dbus-broker.service 2>/dev/null || warn "dbus-broker enable skipped"
  sudo systemctl --global enable dbus-broker.service 2>/dev/null || true
  ok "dbus-broker enabled (takes effect next reboot)"
else
  skip "dbus-broker already enabled"
fi

# =====================================================
# DONE
# =====================================================
echo
ok "SPEED BOOST APPLIED"
echo
echo "Verify:"
echo "  swapon --show                     # zram0 line, priority 100, size ~= RAM"
echo "  sysctl vm.swappiness vm.page-cluster   # 180 / 0"
echo "  journalctl -b -u earlyoom | grep -i 'low memory'   # should be quiet now"
echo "  systemctl status earlyoom auto-cpufreq"
echo "  systemd-analyze                   # boot time"
echo "  systemd-analyze blame | head      # top slow services"
echo "  free -h                           # zram counts as swap"
echo
echo "Reboot for full effect (dbus-broker, zram initrd, journald)."
echo
echo "OPTIONAL kernel cmdline (edit /etc/default/grub, add to GRUB_CMDLINE_LINUX_DEFAULT,"
echo "then: sudo grub-mkconfig -o /boot/grub/grub.cfg && sudo reboot):"
echo "  nowatchdog                         # -1s boot, no watchdog dmesg spam"
echo "  quiet loglevel=3                   # cleaner boot"
if grep -qi intel <<<"$GPU_INFO"; then
  echo "  i915.enable_guc=3                  # Intel: GPU scheduling + HuC firmware"
fi
echo "  mitigations=off                    # personal-only: 10-30% CPU (less secure)"
