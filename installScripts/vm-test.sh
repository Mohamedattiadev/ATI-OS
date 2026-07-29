#!/usr/bin/env bash
# vm-test.sh — run ./install.sh on a throw-away Arch VM.
#
# The point of this script is the preflight. Booting qemu is three lines;
# what actually goes wrong is starting a 4 GB VM on a laptop with 2 GB
# free and wedging the host halfway through a 500 MB download. So this
# refuses up front, with the specific number that failed, rather than
# discovering it at module 21 of 32.
#
# It is deliberately NOT fully unattended. `archinstall` is interactive by
# design, and an unattended path that silently picks the wrong disk on a
# machine with two of them is worse than no script. You drive that one
# step; everything either side is automated.
#
# Usage:
#   ./vm-test.sh --check     # preflight only, touch nothing (do this first)
#   ./vm-test.sh             # preflight, fetch ISO, create disk, boot
#   ./vm-test.sh --clean     # delete the VM disk and ISO

set -Eeuo pipefail

VM_DIR="${VM_DIR:-$HOME/vm-dotfiles-test}"
ISO="$VM_DIR/archlinux-x86_64.iso"
DISK="$VM_DIR/arch.qcow2"
MIRROR="https://geo.mirror.pkgbuild.com/iso/latest"

# Sized from what the install actually does, not from round numbers:
# dcli sync (~5 min of pacman), whisper small.en (~500 MB), piper voices
# (~60 MB), wallpapers clone (~500 MB), plus the base system.
VM_RAM_MB=4096
VM_DISK_GB=20
NEED_HOST_FREE_MB=$((VM_RAM_MB + 1024))   # VM + headroom for the host
NEED_DISK_GB=$((VM_DISK_GB + 2))          # qcow2 grows; leave room for the ISO

r=$'\033[31m'; g=$'\033[32m'; y=$'\033[33m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s[vm-test]%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '%s[vm-test]%s %s✓%s %s\n' "$d" "$o" "$g" "$o" "$*"; }
warn() { printf '%s[vm-test]%s %s!%s %s\n' "$d" "$o" "$y" "$o" "$*"; }
bad()  { printf '%s[vm-test]%s %s✖%s %s\n' "$d" "$o" "$r" "$o" "$*"; FAIL=1; }

FAIL=0

preflight() {
  say "checking host can host a $((VM_RAM_MB / 1024))G / ${VM_DISK_GB}G VM…"

  if command -v qemu-system-x86_64 >/dev/null; then
    ok "qemu present"
  else
    bad "qemu-system-x86_64 missing — sudo pacman -S qemu-desktop edk2-ovmf"
  fi

  if [[ -w /dev/kvm ]]; then
    ok "/dev/kvm writable (hardware acceleration available)"
  elif [[ -e /dev/kvm ]]; then
    bad "/dev/kvm exists but is not writable — add yourself to the kvm group"
  else
    bad "/dev/kvm missing — enable virtualisation in firmware; without KVM this is unusably slow"
  fi

  # available, not free: free excludes reclaimable page cache and will
  # scare you off a machine that is actually fine.
  local avail_mb; avail_mb=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
  if (( avail_mb >= NEED_HOST_FREE_MB )); then
    ok "RAM available: ${avail_mb}MB (need ${NEED_HOST_FREE_MB}MB)"
  else
    bad "RAM available: ${avail_mb}MB, need ${NEED_HOST_FREE_MB}MB."
    printf '            Close your browser, or run this when the machine is idle.\n'
    printf '            Starting the VM anyway will swap the host to a standstill\n'
    printf '            mid-install, which is the one failure this script exists to stop.\n'
  fi

  # Measure the nearest existing ancestor. Creating VM_DIR here would make
  # the "nothing was created" line below a lie on a failed preflight.
  local probe="$VM_DIR"
  while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe=$(dirname "$probe"); done
  local avail_gb; avail_gb=$(df -BG --output=avail "$probe" | tail -1 | tr -dc '0-9')
  if (( avail_gb >= NEED_DISK_GB )); then
    ok "disk on $(df --output=target "$probe" | tail -1): ${avail_gb}G (need ${NEED_DISK_GB}G)"
  else
    bad "only ${avail_gb}G free at $probe, need ${NEED_DISK_GB}G — set VM_DIR= to a roomier filesystem"
  fi

  if curl -fsI --max-time 10 "$MIRROR/" >/dev/null 2>&1; then
    ok "mirror reachable"
  else
    warn "could not reach $MIRROR — check connectivity before the ISO download"
  fi

  if (( FAIL )); then
    printf '\n%s[vm-test] preflight failed — nothing was created.%s\n\n' "$r" "$o"
    exit 1
  fi
  printf '\n'; ok "host is ready"
}

fetch_iso() {
  mkdir -p "$VM_DIR"
  if [[ -f "$ISO" ]]; then
    ok "ISO already present ($(du -h "$ISO" | cut -f1))"
    return
  fi
  say "downloading Arch ISO (~1.2 GB)…"
  curl -fL --progress-bar -o "$ISO.part" "$MIRROR/archlinux-x86_64.iso"
  mv "$ISO.part" "$ISO"
  ok "ISO downloaded"

  # Verify against the mirror's checksum. An ISO truncated by a dropped
  # connection boots just far enough to waste an hour.
  if curl -fsL -o "$VM_DIR/sha256sums.txt" "$MIRROR/sha256sums.txt" 2>/dev/null; then
    local want got
    want=$(awk '/archlinux-x86_64.iso$/ {print $1; exit}' "$VM_DIR/sha256sums.txt")
    got=$(sha256sum "$ISO" | cut -d' ' -f1)
    if [[ -n "$want" && "$want" == "$got" ]]; then
      ok "checksum verified"
    elif [[ -n "$want" ]]; then
      bad "checksum MISMATCH — delete $ISO and re-run"; exit 1
    fi
  else
    warn "could not fetch sha256sums.txt — ISO not verified"
  fi
}

create_disk() {
  if [[ -f "$DISK" ]]; then
    ok "VM disk already exists ($(du -h "$DISK" | cut -f1)) — reusing"
    return
  fi
  qemu-img create -f qcow2 "$DISK" "${VM_DISK_GB}G" >/dev/null
  ok "created ${VM_DISK_GB}G qcow2"
}

boot() {
  cat <<INSTRUCTIONS

${g}Booting the VM.${o} Inside it:

  1. ${d}# base install — pick minimal profile, create a user WITH sudo${o}
     archinstall

  2. ${d}# reboot into the installed system, log in as that user${o}

  3. git clone https://github.com/Mohamedattiadev/Newdotfile-.git ~/.dotfiles
     cd ~/.dotfiles/installScripts
     ./install.sh

${g}Pass:${o} the wizard ends on the green card,
      "Installation Complete · ✔ 32 ok · ⚠ 0 not run · ✖ 0 failed",
      and after logout + startx qtile comes up themed.

${d}Ctrl-A X quits qemu. Re-running this script reuses the disk.${o}

INSTRUCTIONS

  local -a args=(
    -enable-kvm
    -m "$VM_RAM_MB"
    -smp 2
    -drive "file=$DISK,if=virtio,format=qcow2"
    -boot order=dc
    -cdrom "$ISO"
    -netdev "user,id=n0" -device "virtio-net,netdev=n0"
    -vga virtio -display gtk
  )
  # UEFI when the firmware is installed: the boot-fallback module writes
  # systemd-boot entries, and testing that on a BIOS VM tests nothing.
  if [[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd ]]; then
    args+=(-drive "if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd")
    ok "booting UEFI (matches the real install; boot-fallback is testable)"
  else
    warn "edk2-ovmf not installed — booting BIOS, so the boot-fallback module cannot be validated"
  fi
  exec qemu-system-x86_64 "${args[@]}"
}

case "${1:-}" in
  --check) preflight ;;
  --clean) rm -rf "$VM_DIR"; ok "removed $VM_DIR" ;;
  --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
  "")      preflight; fetch_iso; create_disk; boot ;;
  *)       echo "vm-test.sh: unknown argument: $1" >&2; exit 2 ;;
esac
