#!/usr/bin/env bash
# vm-test.sh — run ./install.sh on a throw-away Arch VM.
#
# The point of this script is the preflight. Booting qemu is three lines;
# what actually goes wrong is starting a 4 GB VM on a laptop with 2 GB
# free and wedging the host halfway through a 500 MB download. So this
# refuses up front, with the specific number that failed, rather than
# discovering it at module 21 of 32.
#
# The DEFAULT run is deliberately not unattended. `archinstall` is
# interactive by design, and an unattended path that silently picks the
# wrong disk on a machine with two of them is worse than no script. You
# drive that one step; everything either side is automated.
#
# --unattended is the exception, and it earns it by not using archinstall
# at all. That objection is about the HOST's disks; inside this VM there is
# exactly one (/dev/vda, the qcow2 this script created), so there is no
# wrong disk to pick. It scripts a minimal base system directly -- pacstrap
# and bootctl, no archinstall -- which is both deterministic and immune to
# archinstall's config schema changing between releases. Then it runs
# ./install.sh and asserts the wizard's own summary card.
#
# Usage:
#   ./vm-test.sh --check       # preflight only, touch nothing (do this first)
#   ./vm-test.sh --smoke       # 2-minute headless boot: proves qemu/KVM/ISO work
#   ./vm-test.sh               # preflight, fetch ISO, create disk, boot (you drive)
#   ./vm-test.sh --unattended  # the whole thing, start to finish, no human
#   ./vm-test.sh --clean       # delete the VM disk and ISO

set -Eeuo pipefail

VM_DIR="${VM_DIR:-$HOME/vm-dotfiles-test}"
ISO="$VM_DIR/archlinux-x86_64.iso"
DISK="$VM_DIR/arch.qcow2"
MIRROR="https://geo.mirror.pkgbuild.com/iso/latest"

# Sized from what the install actually does, not from round numbers:
# dcli sync (~5 min of pacman), whisper small.en (~500 MB), piper voices
# (~60 MB), wallpapers clone (~500 MB), plus the base system.
VM_RAM_MB="${VM_RAM_MB:-4096}"            # override for a tighter host
SMOKE_RAM_MB=2048                         # --smoke only reaches a login prompt
VM_DISK_GB=20
HOST_HEADROOM_MB=1024
NEED_DISK_GB=$((VM_DISK_GB + 2))          # qcow2 grows; leave room for the ISO

# --unattended only. The guest is driven over SSH rather than by matching
# text on the serial console: a 40-minute install scrolls pacman progress
# bars and ANSI escapes past any expect-style matcher, whereas ssh gives
# real exit codes and lets output be captured verbatim. The serial console
# is used for exactly one thing -- logging in once to install the key.
VM_USER="${VM_USER:-vmtest}"
VM_PASS="${VM_PASS:-vmtest}"              # throw-away VM, never reachable off localhost
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="$VM_DIR/id_vmtest"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/Mohamedattiadev/Newdotfile-.git}"
DOTFILES_REF="${DOTFILES_REF:-main}"
# Generous, because these are wall-clock budgets for a whole install on a
# laptop that is also doing other things. They exist to stop a wedged run
# hanging forever, not to be tight.
BASE_INSTALL_TIMEOUT="${BASE_INSTALL_TIMEOUT:-2400}"     # pacstrap + chroot
DOTFILES_INSTALL_TIMEOUT="${DOTFILES_INSTALL_TIMEOUT:-9000}"  # 32 modules, AUR builds, ~1.1GB of models

r=$'\033[31m'; g=$'\033[32m'; y=$'\033[33m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s[vm-test]%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '%s[vm-test]%s %s✓%s %s\n' "$d" "$o" "$g" "$o" "$*"; }
warn() { printf '%s[vm-test]%s %s!%s %s\n' "$d" "$o" "$y" "$o" "$*"; }
bad()  { printf '%s[vm-test]%s %s✖%s %s\n' "$d" "$o" "$r" "$o" "$*"; FAIL=1; }

FAIL=0

preflight() {
  # $1 = guest RAM this run actually needs. --smoke boots a 2G guest and has
  # no business demanding the full install budget; that mismatch made
  # --smoke unrunnable on exactly the hosts it exists to help.
  local guest_mb="${1:-$VM_RAM_MB}"
  local need_mb=$((guest_mb + HOST_HEADROOM_MB))
  say "checking host can host a ${guest_mb}MB / ${VM_DISK_GB}G VM…"

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
  if (( avail_mb >= need_mb )); then
    ok "RAM available: ${avail_mb}MB (need ${need_mb}MB)"
  else
    bad "RAM available: ${avail_mb}MB, need ${need_mb}MB."
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
      # Delete it here rather than telling you to. Leaving the bad file in
      # place meant the next run hit the `[[ -f "$ISO" ]]` shortcut above,
      # reported "ISO already present", and never re-checked -- so a single
      # truncated download poisoned every run after it.
      rm -f "$ISO"
      bad "checksum MISMATCH — corrupt ISO deleted, re-run to download again"; exit 1
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
  if [[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd && -f /usr/share/edk2/x64/OVMF_VARS.4m.fd ]]; then
    # BOTH halves, and the VARS half writable. Code-only was the bug: with
    # no variable store the guest has no EFI NVRAM, so `bootctl install`
    # and efibootmgr fail and nothing survives a reboot -- the VM looked
    # like UEFI and could not test the one module UEFI was turned on for.
    # Private copy in VM_DIR because qemu writes to it, and the packaged
    # template is root-owned.
    [[ -f "$VM_DIR/OVMF_VARS.fd" ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VM_DIR/OVMF_VARS.fd"
    args+=(-drive "if=pflash,unit=0,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd")
    args+=(-drive "if=pflash,unit=1,format=raw,file=$VM_DIR/OVMF_VARS.fd")
    ok "booting UEFI with a writable varstore (boot-fallback is testable)"
  else
    warn "edk2-ovmf not installed — booting BIOS, so the boot-fallback module cannot be validated"
  fi
  exec qemu-system-x86_64 "${args[@]}"
}

smoke() {
  # Prove qemu + KVM + the ISO + the disk all work, in ~2 minutes and 2 GB,
  # BEFORE committing to a multi-hour install. If this fails there is no
  # point starting the real thing; if it passes, everything up to the
  # archinstall prompt is known good.
  #
  # It boots the ISO's kernel directly (-kernel/-initrd) rather than via the
  # ISO bootloader, purely so `console=ttyS0` can be appended and the whole
  # boot captured to a file. Booting the cdrom normally gives no serial
  # output to assert on. archisolabel is read off the ISO rather than
  # hardcoded -- it carries the release date (ARCH_YYYYMM) and changes every
  # month.
  local k="$VM_DIR/arch/boot/x86_64/vmlinuz-linux"
  local i="$VM_DIR/arch/boot/x86_64/initramfs-linux.img"
  local slog="$VM_DIR/smoke-serial.log"

  [[ -f "$ISO" ]] || { bad "no ISO yet — run ./vm-test.sh first (or --check)"; exit 1; }
  if [[ ! -f "$k" || ! -f "$i" ]]; then
    say "extracting kernel + initramfs from the ISO…"
    bsdtar -xf "$ISO" -C "$VM_DIR" \
      arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
  fi
  local label
  # blkid also exits 0 with NOTHING on stdout when it cannot read a LABEL
  # off the image, which `|| echo` does not catch. That produced an empty
  # `archisolabel=`, and the guest then failed to find its own root device
  # -- a boot failure that looks like a broken ISO rather than a broken
  # kernel argument.
  label=$(blkid -o value -s LABEL "$ISO" 2>/dev/null || true)
  [[ -n "$label" ]] || label=ARCH_202607
  [[ -f "$DISK" ]] || create_disk

  say "booting headless (${SMOKE_RAM_MB}MB, 240s cap) — watching for the login prompt…"
  timeout 240 qemu-system-x86_64 \
    -enable-kvm -m "$SMOKE_RAM_MB" -smp 2 \
    -drive "file=$DISK,if=virtio,format=qcow2" \
    -cdrom "$ISO" \
    -kernel "$k" -initrd "$i" \
    -append "archisobasedir=arch archisolabel=$label console=ttyS0" \
    -netdev "user,id=n0" -device "virtio-net,netdev=n0" \
    -display none -serial "file:$slog" \
    -no-reboot >/dev/null 2>&1 || true   # timeout is the expected exit

  # Assert on what the boot actually reached, not on qemu's exit status --
  # it sits at the login prompt forever, so `timeout` always kills it.
  local fail=0
  grep -q 'Reached target.*Network'      "$slog" || { bad "never reached the network target"; fail=1; }
  grep -q 'archiso login:'               "$slog" || { bad "never reached the login prompt"; fail=1; }
  if (( fail )); then
    printf '\n%s[vm-test] smoke test FAILED — full boot log: %s%s\n\n' "$r" "$slog" "$o"
    exit 1
  fi
  ok "network up"
  ok "reached 'archiso login:' — qemu, KVM, ISO and disk all good"
  printf '\n'; say "full boot log: $slog"
}

# ── unattended ───────────────────────────────────────────────────────
# Three phases, each of which must finish before the next can start:
#
#   A  boot the live ISO, log in once over the serial console, install an
#      ssh key and start sshd. This is the ONLY console-scraping in the
#      script, and it matches two fixed strings.
#   B  over ssh: partition /dev/vda, pacstrap a minimal base, write a
#      systemd-boot entry, create the sudo user. Then power off.
#   C  boot the INSTALLED system from disk under UEFI -- no -kernel, no
#      cdrom, so this exercises the real bootloader -- then over ssh clone
#      the repo, run ./install.sh, and assert the wizard's summary card.

QEMU_PID=""
_qemu_kill() {
  [[ -n "$QEMU_PID" ]] || return 0
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
}

_ovmf_args() {
  # Same UEFI setup the interactive path uses, and for the same reason:
  # boot-fallback writes systemd-boot entries, and testing that on a BIOS
  # VM tests nothing. Both halves, VARS writable and private to VM_DIR.
  [[ -f /usr/share/edk2/x64/OVMF_CODE.4m.fd && -f /usr/share/edk2/x64/OVMF_VARS.4m.fd ]] || return 0
  [[ -f "$VM_DIR/OVMF_VARS.fd" ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VM_DIR/OVMF_VARS.fd"
  printf '%s\n' \
    "-drive" "if=pflash,unit=0,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd" \
    "-drive" "if=pflash,unit=1,format=raw,file=$VM_DIR/OVMF_VARS.fd"
}

# Built once and reused, because the long-running calls below need to be
# wrapped in `timeout`, and `timeout` execs a binary -- it cannot run a
# shell function. So the options live in an array and the two forms share
# it, rather than _ssh being a function that timeout silently cannot find.
_ssh_opts() {
  printf '%s\n' -q -i "$SSH_KEY" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 -o LogLevel=ERROR \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=10
}
SSH_OPTS=()

_ssh() { ssh "${SSH_OPTS[@]}" "$1@127.0.0.1" "${@:2}"; }

# Poll until sshd answers as $1. Returns 1 on timeout rather than hanging:
# a guest that never comes up must fail the run, not stall it.
_wait_ssh() {
  local user="$1" limit="$2" waited=0
  while (( waited < limit )); do
    if _ssh "$user" true 2>/dev/null; then return 0; fi
    sleep 5; waited=$((waited + 5))
    (( waited % 60 )) || say "  … still waiting for ssh as $user (${waited}s)"
  done
  return 1
}

unattended() {
  local slog="$VM_DIR/unattended-serial.log"
  local blog="$VM_DIR/unattended-base.log"
  local ilog="$VM_DIR/unattended-install.log"
  local k="$VM_DIR/arch/boot/x86_64/vmlinuz-linux"
  local i="$VM_DIR/arch/boot/x86_64/initramfs-linux.img"

  trap '_qemu_kill' EXIT INT TERM
  mapfile -t SSH_OPTS < <(_ssh_opts)

  # A wedged previous run leaves the port bound; say so rather than letting
  # ssh cheerfully connect to the wrong VM.
  if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$SSH_PORT" 2>/dev/null | grep -q LISTEN; then
    bad "port $SSH_PORT is already in use — another VM is running, or set SSH_PORT="
    exit 1
  fi

  # Always from scratch. Reusing a disk that already has a base system on
  # it would silently skip phase B and test half of what was asked for.
  rm -f "$DISK" "$VM_DIR/OVMF_VARS.fd"
  create_disk

  rm -f "$SSH_KEY" "$SSH_KEY.pub"
  ssh-keygen -q -t ed25519 -N '' -f "$SSH_KEY" -C vm-test
  local pubkey; pubkey="$(cat "$SSH_KEY.pub")"

  if [[ ! -f "$k" || ! -f "$i" ]]; then
    say "extracting kernel + initramfs from the ISO…"
    bsdtar -xf "$ISO" -C "$VM_DIR" \
      arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
  fi
  local label
  label=$(blkid -o value -s LABEL "$ISO" 2>/dev/null || true)
  [[ -n "$label" ]] || label=ARCH_202607

  # ── phase A ──────────────────────────────────────────────────────
  say "phase A — booting the live ISO"
  local sser="$VM_DIR/serial.sock"
  rm -f "$sser"
  local -a ovmf=(); mapfile -t ovmf < <(_ovmf_args)
  # q35 + an explicit AHCI cd, not the one-liner `-cdrom`. Under OVMF a
  # plain -cdrom does not enumerate: the ISO never appears as a block
  # device, archiso cannot find /dev/disk/by-label/$label, and the guest
  # drops to the initramfs emergency shell 30 seconds in. The BIOS smoke
  # test does not hit this, which is exactly why it did not catch it.
  # q35 is also the machine type OVMF is built for, and phase C reuses it
  # so the firmware's boot variables stay valid across the reboot.
  qemu-system-x86_64 \
    -machine q35 -enable-kvm -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive "file=$DISK,if=virtio,format=qcow2" \
    -device ahci,id=ahci \
    -device ide-cd,bus=ahci.0,drive=cd0 \
    -drive "id=cd0,file=$ISO,format=raw,if=none,media=cdrom" \
    -kernel "$k" -initrd "$i" \
    -append "archisobasedir=arch archisolabel=$label console=ttyS0" \
    -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22" -device "virtio-net,netdev=n0" \
    "${ovmf[@]}" \
    -display none -serial "unix:$sser,server=on,wait=off" \
    >/dev/null 2>&1 &
  QEMU_PID=$!

  say "  logging in on the serial console to install an ssh key…"
  if ! python3 - "$sser" "$pubkey" "$slog" <<'PY'
import re, socket, sys, time

sock_path, pubkey, logpath = sys.argv[1], sys.argv[2], sys.argv[3]
ANSI = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][B0]|\x1b[78=>]')

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(60):                      # qemu creates the socket at startup
    try:
        s.connect(sock_path); break
    except OSError:
        time.sleep(1)
else:
    print("could not connect to the serial socket", file=sys.stderr); sys.exit(1)

s.settimeout(1.0)
buf = bytearray()
log = open(logpath, "wb")

def wait_for(needle, timeout, send_on_idle=None):
    """Read until `needle` appears. send_on_idle is re-sent every 15s of
    silence: the getty may already have printed its prompt before we
    connected, in which case nothing new arrives until we poke it."""
    deadline = time.time() + timeout
    last_poke = 0.0
    while time.time() < deadline:
        try:
            chunk = s.recv(4096)
            if chunk:
                buf.extend(chunk); log.write(chunk); log.flush()
        except socket.timeout:
            pass
        if needle in ANSI.sub(b'', bytes(buf)):
            return True
        if send_on_idle and time.time() - last_poke > 15:
            s.sendall(send_on_idle); last_poke = time.time()
    return False

# archiso's root account has an empty password, so the login is two words.
if not wait_for(b'archiso login:', 300, send_on_idle=b'\n'):
    print("never reached the archiso login prompt", file=sys.stderr); sys.exit(1)
s.sendall(b'root\n')
if not wait_for(b'root@archiso', 120, send_on_idle=b'\n'):
    print("logged in but never saw a root prompt", file=sys.stderr); sys.exit(1)

buf.clear()
setup = (
    "install -d -m700 /root/.ssh && "
    f"printf '%s\\n' '{pubkey}' > /root/.ssh/authorized_keys && "
    "chmod 600 /root/.ssh/authorized_keys && "
    "systemctl start sshd && "
    "echo VMTEST_SSH_IS_READY\n"
)
s.sendall(setup.encode())
if not wait_for(b'VMTEST_SSH_IS_READY', 180):
    print("ssh key install did not confirm", file=sys.stderr); sys.exit(1)
print("serial handshake complete")
PY
  then
    bad "phase A failed — serial log: $slog"; exit 1
  fi

  _wait_ssh root 180 || { bad "sshd never answered on port $SSH_PORT"; exit 1; }
  ok "phase A — live ISO up, ssh reachable"

  # ── phase B ──────────────────────────────────────────────────────
  say "phase B — installing a minimal base system (this is the pacstrap)"
  if ! timeout "$BASE_INSTALL_TIMEOUT" \
       ssh "${SSH_OPTS[@]}" root@127.0.0.1 \
       "VM_USER='$VM_USER' VM_PASS='$VM_PASS' PUBKEY='$pubkey' bash -s" \
       < <(_base_install_script) > "$blog" 2>&1; then
    bad "base install failed — log: $blog"
    tail -25 "$blog" >&2
    exit 1
  fi
  ok "phase B — base system installed"

  say "  powering the live environment down…"
  _ssh root "systemctl poweroff --no-block" >/dev/null 2>&1 || true
  local waited=0
  while kill -0 "$QEMU_PID" 2>/dev/null && (( waited < 120 )); do
    sleep 2; waited=$((waited + 2))
  done
  _qemu_kill

  # ── phase C ──────────────────────────────────────────────────────
  # No -kernel and no -cdrom: this boots the ESP that phase B wrote, under
  # OVMF, which is the only way the bootloader work gets tested at all.
  say "phase C — booting the installed system from disk (UEFI, real bootloader)"
  mapfile -t ovmf < <(_ovmf_args)
  qemu-system-x86_64 \
    -machine q35 -enable-kvm -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive "file=$DISK,if=virtio,format=qcow2" \
    -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22" -device "virtio-net,netdev=n0" \
    "${ovmf[@]}" \
    -display none -serial "file:$VM_DIR/unattended-boot.log" \
    >/dev/null 2>&1 &
  QEMU_PID=$!

  if ! _wait_ssh "$VM_USER" 300; then
    bad "the installed system never came up — boot log: $VM_DIR/unattended-boot.log"
    exit 1
  fi
  ok "phase C — installed system booted from its own ESP"

  say "  running ./install.sh in the guest (32 modules, AUR builds, ~1.1GB of models)"
  say "  this is the long part; output streams to $ilog"
  local rc=0
  timeout "$DOTFILES_INSTALL_TIMEOUT" \
    ssh "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1" \
    "DOTFILES_REPO='$DOTFILES_REPO' DOTFILES_REF='$DOTFILES_REF' bash -s" \
    < <(_dotfiles_install_script) > "$ilog" 2>&1 || rc=$?
  # Pull the wizard's per-module error logs back BEFORE anything can shut
  # the guest down. The first run of this test reported "5 failed" and then
  # took the reason to the grave with the VM: those logs live in the
  # guest's /tmp, which is a tmpfs, so they do not survive even its own
  # reboot. Knowing WHICH module failed without knowing WHY is most of a
  # wasted hour.
  mkdir -p "$VM_DIR/module-errors"
  rm -f "$VM_DIR/module-errors/"*.err 2>/dev/null || true
  scp -q "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1:/tmp/wizard-*.err" \
      "$VM_DIR/module-errors/" 2>/dev/null || true
  if compgen -G "$VM_DIR/module-errors/*.err" >/dev/null; then
    say "  module error logs saved to $VM_DIR/module-errors/"
  fi

  if (( rc )); then
    bad "./install.sh did not complete (exit $rc) — log: $ilog"
    tail -40 "$ilog" >&2
    exit 1
  fi

  # ── assertions ───────────────────────────────────────────────────
  # The wizard prints its own summary card; that card is the pass
  # condition this script has always documented. Asserted on the FAILED
  # and NOT-RUN counts rather than on "32 ok", because the module count
  # legitimately changes as modules are added.
  local fail=0
  if grep -qE '✖ 0 failed' "$ilog"; then
    ok "wizard reported 0 failed modules"
  else
    bad "wizard reported failed modules:"
    grep -E '✔ .* ok|⚠ .* not run|✖ .* failed' "$ilog" | tail -3 >&2
    fail=1
  fi
  if grep -qE 'Installation Complete' "$ilog"; then
    ok "wizard reached its completion card"
  else
    bad "wizard never printed a completion card"; fail=1
  fi
  if grep -q 'VMTEST_VALIDATE_OK' "$ilog"; then
    ok "validate.sh passed inside the guest (qtile config loads, fonts resolve)"
  else
    bad "validate.sh did not pass in the guest"; fail=1
  fi
  if grep -q 'VMTEST_VERIFYROOT_OK' "$ilog"; then
    ok "every boot entry's root= matches the guest's real root device"
  else
    warn "boot-entry root check did not report (see $ilog)"
  fi

  # ── phase D — does the desktop actually come up? ─────────────────
  # The one thing no layer below this could reach. The container has no X
  # server and neither did this VM, so "qtile comes up themed" had always
  # been a human check on real hardware.
  #
  # Xvfb, not Xephyr: Xephyr renders INTO a parent X display, and a
  # headless guest has no display to be a parent.
  #
  # Note what is and is not asserted. `qtile cmd-obj -f status` answering
  # OK does NOT prove this repo's config loaded -- qtile falls back to its
  # own built-in config on a config error and answers OK exactly the same.
  # So the log is checked for that fallback, and the screenshot for having
  # drawn more than a flat colour. The PNG comes back to the host either
  # way, because the last mile really is a human looking at it.
  say "phase D — starting a headless X server and checking qtile renders"
  local dlog="$VM_DIR/unattended-desktop.log"
  local shot="$VM_DIR/qtile-screenshot.png"
  local drc=0
  timeout 900 ssh "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1" bash -s \
    < <(_desktop_check_script) > "$dlog" 2>&1 || drc=$?

  scp -q "${SSH_OPTS[@]}" "$VM_USER@127.0.0.1:/tmp/qtile-headless.png" "$shot" 2>/dev/null || true

  if (( drc )); then
    bad "desktop check did not complete (exit $drc) — log: $dlog"
    tail -20 "$dlog" >&2
    fail=1
  else
    if grep -q VMTEST_QTILE_OK "$dlog"; then
      ok "qtile started under X and answered IPC"
    else
      bad "qtile did not start under X"; fail=1
    fi
    if grep -q VMTEST_QTILE_OWN_CONFIG "$dlog"; then
      ok "it loaded THIS repo's config (no fallback in the qtile log)"
    else
      bad "qtile fell back to its built-in config — the repo's config did not load"; fail=1
    fi
    if grep -q VMTEST_QTILE_RENDERED "$dlog"; then
      ok "the root window actually rendered ($(grep -o 'colours=[0-9]*' "$dlog" | head -1))"
    else
      bad "the screen came out blank"; fail=1
    fi
  fi
  [[ -s "$shot" ]] && say "screenshot: $shot — worth an actual look"

  printf '\n'
  if (( fail )); then
    printf '%s[vm-test] UNATTENDED RUN FAILED — %s%s\n\n' "$r" "$ilog" "$o"
    # The reason, not just the verdict.
    local ef
    for ef in "$VM_DIR"/module-errors/*.err; do
      [[ -s "$ef" ]] || continue
      printf '%s── %s ──%s\n' "$y" "${ef##*/}" "$o"
      tail -15 "$ef" | sed 's/^/    /'
    done
    exit 1
  fi
  ok "unattended run passed"
  say "logs: $blog · $ilog · $VM_DIR/unattended-boot.log"
  printf '\n%sWhat this still does not prove:%s the desktop on REAL hardware.\n' "$y" "$o"
  printf 'Xvfb has no GPU, so picom, the compositing and the animations are\n'
  printf 'untested, and a screenshot is not the same as looking at the thing.\n'
  printf 'It does now prove qtile starts, loads THIS config rather than the\n'
  printf 'fallback, and draws.\n\n'
  _qemu_kill
}

# Guest-side scripts. Kept as functions emitting heredocs rather than files
# so there is nothing to keep in sync and nothing to copy into the VM.
_base_install_script() {
  cat <<'GUEST'
set -Eeuo pipefail
DISK=/dev/vda
[[ -b $DISK ]] || { echo "no $DISK in the guest"; exit 1; }

# 512M ESP + the rest as root. The ESP is mounted at /boot (not /efi) so
# that mkinitcpio writes the kernel and initramfs straight onto it, which
# is the layout the repo's boot modules assume:
# `bootctl --print-esp-path` answers /boot on this machine too.
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI "$DISK"
sgdisk -n2:0:0     -t2:8304 -c2:root "$DISK"
partprobe "$DISK" 2>/dev/null || true; sleep 2
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F  "${DISK}2"
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# Deliberately minimal: the point is to test what THIS repo installs, so
# anything the wizard is supposed to bring in must not be pre-seeded here.
# base-devel and git are the exception -- yay cannot bootstrap without them.
pacstrap -K /mnt base linux linux-firmware sudo networkmanager openssh git base-devel
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt bash -s <<CHROOT
set -Eeuo pipefail
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo vmtest > /etc/hostname
useradd -m -G wheel -s /bin/bash '$VM_USER'
echo '$VM_USER:$VM_PASS' | chpasswd
echo "root:$VM_PASS" | chpasswd
# NOPASSWD because the wizard runs sudo dozens of times with no tty to
# prompt on. The repo has its own passwordless-sudo module; this is just
# what makes the run possible in the first place.
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/00-wheel
chmod 440 /etc/sudoers.d/00-wheel
systemctl enable NetworkManager sshd
bootctl install
CHROOT

# The boot entry, written from the real PARTUUID of the partition we just
# made. This is exactly the class of entry `boot-splash verify-root` was
# added to check, so phase C ends up validating that check for free.
ROOT_PARTUUID="$(blkid -o value -s PARTUUID "${DISK}2")"
[[ -n $ROOT_PARTUUID ]] || { echo "could not read root PARTUUID"; exit 1; }
cat > /mnt/boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
EOF
cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$ROOT_PARTUUID rw
EOF

install -d -m700 "/mnt/home/$VM_USER/.ssh"
printf '%s\n' "$PUBKEY" > "/mnt/home/$VM_USER/.ssh/authorized_keys"
chmod 600 "/mnt/home/$VM_USER/.ssh/authorized_keys"
arch-chroot /mnt chown -R "$VM_USER:$VM_USER" "/home/$VM_USER/.ssh"

sync
umount -R /mnt
echo "BASE_INSTALL_OK"
GUEST
}

_dotfiles_install_script() {
  cat <<'GUEST'
set -Eeuo pipefail
export TERM=dumb                       # no tty here; keep the wizard's output parseable

sudo systemctl start systemd-timesyncd 2>/dev/null || true
git clone --branch "$DOTFILES_REF" "$DOTFILES_REPO" "$HOME/.dotfiles"
cd "$HOME/.dotfiles/installScripts"

# The thing under test.
./install.sh

# Both cheap, both meaningful, and neither is reachable from the container
# layer: validate.sh loads the real qtile config and resolves real fonts,
# and verify-root compares this guest's boot entry against its own root.
./validate.sh && echo VMTEST_VALIDATE_OK
"$HOME/.dotfiles/.config/AtiScriptsV1/boot-splash" verify-root && echo VMTEST_VERIFYROOT_OK
GUEST
}

_desktop_check_script() {
  cat <<'GUEST'
set -Eeuo pipefail
export DISPLAY=:99

# Test-only packages, installed AFTER install.sh has already been asserted
# so they cannot influence what was under test.
sudo pacman -S --needed --noconfirm xorg-server-xvfb imagemagick >/dev/null 2>&1 || true

Xvfb :99 -screen 0 1366x768x24 >/tmp/xvfb.log 2>&1 &
for _ in $(seq 1 20); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo >/dev/null 2>&1 || { echo "Xvfb never came up"; cat /tmp/xvfb.log; exit 1; }
echo "Xvfb up"

qtile start -b x11 >/tmp/qtile-vm.log 2>&1 &
for _ in $(seq 1 40); do
  qtile cmd-obj -o cmd -f status >/dev/null 2>&1 && break
  sleep 2
done

if [ "$(qtile cmd-obj -o cmd -f status 2>/dev/null | tr -d '"')" = OK ]; then
  echo VMTEST_QTILE_OK
else
  echo "qtile never answered IPC"; tail -40 /tmp/qtile-vm.log; exit 1
fi

# qtile logs this and silently substitutes its built-in config when ours
# raises. Without this check a completely broken config still reports OK.
if grep -qiE 'error while reading config|could not import config|configuration error' \
     /tmp/qtile-vm.log ~/.local/share/qtile/qtile.log 2>/dev/null; then
  echo "qtile fell back to its built-in config:"
  grep -ihE 'error while reading config|could not import config|configuration error' \
     /tmp/qtile-vm.log ~/.local/share/qtile/qtile.log 2>/dev/null | head -5
else
  echo VMTEST_QTILE_OWN_CONFIG
fi

import -window root /tmp/qtile-headless.png 2>/dev/null || true
if [ -s /tmp/qtile-headless.png ]; then
  k="$(magick identify -format '%k' /tmp/qtile-headless.png 2>/dev/null || echo 0)"
  echo "colours=$k"
  # A bare X root is one flat colour. A drawn bar is hundreds -- measured
  # at 396 on the host. 20 is a floor an empty screen cannot reach, and it
  # does not depend on the wallpaper having loaded.
  [ "${k:-0}" -gt 20 ] && echo VMTEST_QTILE_RENDERED
fi

qtile cmd-obj -o cmd -f shutdown >/dev/null 2>&1 || true
GUEST
}

case "${1:-}" in
  --check) preflight ;;
  --smoke) preflight "$SMOKE_RAM_MB"; fetch_iso; smoke ;;
  --unattended) preflight; fetch_iso; unattended ;;
  --clean) rm -rf "$VM_DIR"; ok "removed $VM_DIR" ;;
  --help|-h) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
  "")      preflight; fetch_iso; create_disk; boot ;;
  *)       echo "vm-test.sh: unknown argument: $1" >&2; exit 2 ;;
esac
