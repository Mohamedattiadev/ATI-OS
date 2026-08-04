#!/usr/bin/env bash
# test-iso.sh — boot the ATI-OS medium in qemu, install unattended, and
# assert the result.
#
# Four phases, each proving something the others cannot:
#
#   A0 boot the ISO through its OWN bootloader and screenshot the result.
#      Proves the medium is bootable.
#   A  boot the ISO's kernel directly and run ati-os-install --unattended.
#      Proves the BASE system installs. It does not touch the desktop.
#   B  boot the installed disk with the medium detached. The first-boot
#      service runs the wizard here -- so this phase is where the desktop
#      is actually built, and it is also the only proof the boot entry
#      works, since there is nothing else present to boot from.
#   C  mount the installed filesystem and assert against the files.
#
# The wizard runs in phase B, not phase A, because it runs on a BOOTED
# system rather than in a chroot -- see the long comment in ati-os-install.
# An earlier version ran it under arch-chroot, where its `gum` bootstrap
# failed, and produced a machine with no desktop while reporting success.
#
# Phase C exists because the alternative is putting sshd on the product to
# make it testable, and a test that changes what ships is not testing what
# ships.
#
# What this CANNOT cover, and must never be read as covering:
#
#   - the GPU path. qemu has no graphics hardware, so picom, glx and the
#     window animations are untouched by all three phases. This is the same
#     limit vm-test.sh already documents and it has not moved.
#   - AMD and NVIDIA. No such hardware here.
#   - HiDPI. No 4K panel here.
#   - booting from a real USB stick on real firmware. qemu boots the ISO
#     file; that is not the same as a machine's own UEFI reading a stick.
#
# Usage:
#   ./test-iso.sh --check     # preflight only
#   ./test-iso.sh             # all three phases
#   ./test-iso.sh --clean     # delete the test disk and logs

set -Eeuo pipefail

WORK="${ATI_ISO_WORK:-$HOME/ati-os-build}"
OUT_DIR="$WORK/out"
TEST_DIR="$WORK/test"
DISK="$TEST_DIR/ati-os-test.qcow2"   # reassigned per mode in main()
SERIAL_A="$TEST_DIR/phase-a-serial.log"
SERIAL_B="$TEST_DIR/phase-b-serial.log"
HTTP_DIR="$TEST_DIR/http"
HTTP_PORT="${HTTP_PORT:-8731}"

# The guest sees the host as 10.0.2.2 under qemu's user-mode networking.
# That is what lets the ISO fetch the autotest script without baking any
# test-only file into the product.
HOST_FROM_GUEST=10.0.2.2

VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_DISK_GB="${VM_DISK_GB:-60}"
HOST_HEADROOM_MB="${HOST_HEADROOM_MB:-1024}"

# The install compiles nothing now -- that is the entire point of the
# prebuilt repository -- but it still downloads ~250 packages and runs 46
# modules. Generous, because a timeout that fires early looks exactly like
# a hang and wastes a whole run.
PHASE_A_TIMEOUT="${PHASE_A_TIMEOUT:-5400}"
# Phase B now runs the ENTIRE wizard on first boot, not just a boot
# check. 300s was right when it only had to reach a login prompt and
# would guillotine the desktop install halfway through.
PHASE_B_TIMEOUT="${PHASE_B_TIMEOUT:-3600}"

TEST_USER=atitest
TEST_PASS=atitest        # throw-away guest, never reachable off localhost
TEST_HOST=ati-os-test
# Deliberately lowercase letters and digits only: the passphrase has to be
# typed into the LUKS prompt one key at a time through qemu's monitor, and
# every extra character class is another keymap edge case for no test value.
LUKS_PASS="${LUKS_PASS:-atitest123}"

# Type a string into the guest through the qemu monitor.
#
# The LUKS passphrase prompt appears on the VGA console and NOWHERE else --
# the installed system has no console=ttyS0 -- so there is no way to answer
# it over serial. sendkey is the only channel that reaches it.
send_keys() {                 # send_keys <monitor-sock> <string>
  python3 - "$1" "$2" <<'PYK'
import socket, sys, time
sock, text = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(sock)
time.sleep(0.5)
try: s.recv(65536)
except Exception: pass
for ch in text:
    key = ch if ch.isalpha() else {'0':'0','1':'1','2':'2','3':'3','4':'4',
                                   '5':'5','6':'6','7':'7','8':'8','9':'9'}.get(ch)
    if key is None:
        continue
    s.sendall(("sendkey %s\n" % key).encode()); time.sleep(0.06)
s.sendall(b"sendkey ret\n"); time.sleep(0.3)
PYK
}

if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_R=$'\e[0m'
else
  C_OK=; C_WARN=; C_ERR=; C_DIM=; C_R=
fi
_OK()   { printf '%s  ok %s %s\n' "$C_OK"   "$C_R" "$*"; }
_WARN() { printf '%swarn %s %s\n' "$C_WARN" "$C_R" "$*"; }
_ERR()  { printf '%sfail %s %s\n' "$C_ERR"  "$C_R" "$*" >&2; }
_DIM()  { printf '%s     %s%s\n'  "$C_DIM"  "$*" "$C_R"; }
say()   { printf '\n=== %s ===\n' "$*"; }

PASSES=0; FAILS=0
assert() {           # assert <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _OK "$desc"; PASSES=$((PASSES+1))
  else _ERR "$desc"; FAILS=$((FAILS+1)); fi
}

# Test modes. The default path is what most people install; the other two
# both touch the BOOT CHAIN, which is the one thing that must not break, so
# neither ships on the strength of "it compiled".
MODE=default
CHECK_ONLY=0; DO_CLEAN=0
while (( $# )); do
  case "$1" in
    --check)     CHECK_ONLY=1 ;;
    --clean)     DO_CLEAN=1 ;;
    --encrypted) MODE=encrypted ;;
    --dualboot)  MODE=dualboot ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) _ERR "unknown argument: $1"; exit 2 ;;
  esac
  shift
done

HTTP_PID=""; NBD_CONNECTED=0
cleanup() {
  [[ -n "$HTTP_PID" ]] && kill "$HTTP_PID" 2>/dev/null || true
  # An abandoned nbd connection holds the qcow2 open and makes the next run
  # fail with a misleading "device busy", so it must come down on every
  # exit path, not just the happy one.
  if (( NBD_CONNECTED )); then
    sudo umount -R "$TEST_DIR/mnt" 2>/dev/null || true
    sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

find_iso() {
  ISO=$(find "$OUT_DIR" -name '*.iso' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -n "$ISO" ]]
}

find_ovmf() {
  # Package layouts for OVMF have moved more than once. Probe rather than
  # hardcode, and name every path tried when none matches.
  local c
  for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd \
           /usr/share/edk2/x64/OVMF_CODE.fd \
           /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
           /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f "$c" ]] && { OVMF_CODE="$c"; break; }
  done
  for c in /usr/share/edk2/x64/OVMF_VARS.4m.fd \
           /usr/share/edk2/x64/OVMF_VARS.fd \
           /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
           /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$c" ]] && { OVMF_VARS_SRC="$c"; break; }
  done
  [[ -n "${OVMF_CODE:-}" && -n "${OVMF_VARS_SRC:-}" ]]
}

preflight() {
  say "preflight"
  local fail=0

  # sgdisk is needed by the dual-boot fixture, which partitions a disk on
  # the HOST to fake an existing operating system. It lives in gptfdisk and
  # is NOT installed by default -- and without it the fixture silently
  # wrote nothing, so the failure surfaced as "fixture partitions never
  # appeared" rather than as a missing tool. Name it here instead.
  for t in qemu-system-x86_64 qemu-img qemu-nbd python3 sgdisk; do
    if command -v "$t" >/dev/null; then _OK "$t"
    else _ERR "$t not found"; [[ "$t" == sgdisk ]] && _DIM "install it: sudo pacman -S gptfdisk"; fail=1; fi
  done

  if find_iso; then _OK "ISO: $ISO"
  else _ERR "no ISO in $OUT_DIR — run ./build-iso.sh first"; fail=1; fi

  if find_ovmf; then _OK "OVMF firmware: $OVMF_CODE"
  else _ERR "no OVMF firmware — sudo pacman -S edk2-ovmf"; fail=1; fi

  # UEFI is not optional here: the installer refuses on BIOS by design, so
  # a test that fell back to SeaBIOS would assert nothing useful.
  if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    _OK "KVM available"
    ACCEL=(-enable-kvm -cpu host)
  else
    _WARN "no KVM — the run will be several times slower"
    ACCEL=(-cpu max)
  fi

  local free_mb
  free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  if (( free_mb >= VM_RAM_MB + HOST_HEADROOM_MB )); then
    _OK "memory: ${free_mb} MB free (guest ${VM_RAM_MB} MB + ${HOST_HEADROOM_MB} MB headroom)"
  else
    _ERR "memory: ${free_mb} MB free, need $((VM_RAM_MB + HOST_HEADROOM_MB)) MB"
    _DIM "lower VM_RAM_MB, or close something"
    fail=1
  fi

  mkdir -p "$TEST_DIR"
  local avail_gb
  avail_gb=$(df -BG --output=avail "$TEST_DIR" | tail -1 | tr -dc '0-9')
  if (( avail_gb >= VM_DISK_GB / 2 )); then
    _OK "disk: ${avail_gb}G free (qcow2 is sparse; it grows to ~20G in practice)"
  else
    _ERR "disk: ${avail_gb}G free at $TEST_DIR"
    fail=1
  fi

  # nbd is how phase C reads the installed filesystem. Load it now rather
  # than discovering it is missing an hour into the run.
  if sudo modprobe nbd max_part=8 2>/dev/null; then
    _OK "nbd module loaded (phase C needs it)"
  else
    _ERR "cannot load the nbd kernel module — phase C could not run"
    fail=1
  fi

  (( fail )) && { _ERR "preflight failed — nothing was run"; exit 1; }
  _OK "preflight clean"
}

# ─── the script the guest fetches and runs ───────────────────────────
write_autotest() {
  mkdir -p "$HTTP_DIR"
  cat > "$HTTP_DIR/autotest.sh" <<EOF
#!/usr/bin/env bash
# Fetched by archiso's own script= cmdline mechanism. Nothing test-related
# is baked into the ISO itself.
set -Eeuo pipefail
exec > >(tee /dev/ttyS0) 2>&1

echo "ATI-OS-TEST: guest is up"

# archiso runs the script= hook while other units may still be starting.
# pacman-init in particular populates the keyring, and pacstrap fails in a
# thoroughly confusing way if it is not finished.
systemctl is-system-running --wait || true
echo "ATI-OS-TEST: system settled"

export ATI_DISK=/dev/vda
export ATI_HOSTNAME=$TEST_HOST
export ATI_USER=$TEST_USER
export ATI_PASS=$TEST_PASS
export ATI_TIMEZONE=UTC
export ATI_ENCRYPT=$([[ "$MODE" == encrypted ]] && echo 1 || echo 0)
export ATI_LUKS_PASS='$LUKS_PASS'
export ATI_DUALBOOT=$([[ "$MODE" == dualboot ]] && echo 1 || echo 0)

if ati-os-install --unattended; then
  echo "ATI-OS-TEST: INSTALL-OK"
else
  echo "ATI-OS-TEST: INSTALL-FAILED rc=\$?"
fi
echo "ATI-OS-TEST: powering off"
sync
systemctl poweroff -i
EOF
  chmod +x "$HTTP_DIR/autotest.sh"
}

start_http() {
  ( cd "$HTTP_DIR" && python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 ) \
    >/dev/null 2>&1 &
  HTTP_PID=$!
  sleep 1
  kill -0 "$HTTP_PID" 2>/dev/null || { _ERR "could not start the http server"; exit 1; }
  _OK "serving autotest.sh on 127.0.0.1:$HTTP_PORT"
}

# Phase A0 and phase A test two different things, and the split is not
# bureaucracy -- it is forced by how qemu works.
#
# Driving an unattended install needs a kernel command line (archiso's
# `script=` hook), and qemu's -append only applies to a kernel it loads
# itself with -kernel. Booting the ISO from an emulated CD gives no way to
# set the cmdline at all, short of typing at the bootloader prompt.
#
# So: A0 boots the medium exactly as a user would, and proves the
# BOOTLOADER works. A then boots the same kernel directly to run the
# install. Neither alone is enough -- A with -kernel would pass on an ISO
# whose bootloader was completely broken, which is precisely the kind of
# false pass this repo has been bitten by before.
phase_a0() {
  say "phase A0 — the medium's own bootloader"
  cp "$OVMF_VARS_SRC" "$TEST_DIR/OVMF_VARS_a0.fd"
  local shot="$TEST_DIR/phase-a0-screen.ppm"
  local sock="$TEST_DIR/a0-monitor.sock"
  rm -f "$shot" "$sock"

  # The monitor is driven over a unix socket with the wait happening on the
  # HOST, because qemu's monitor has NO `sleep` command.
  #
  # The first version piped "sleep 90\nscreendump ..." into -monitor stdio.
  # `sleep` was rejected as an unknown command and `screendump` fired
  # immediately, capturing qemu's own placeholder frame -- the one that
  # reads "Guest has not initialized the display (yet)." That placeholder
  # has about six distinct colours, so the old `colours > 2` assertion
  # PASSED on a guest that had not booted at all.
  qemu-system-x86_64 \
    "${ACCEL[@]}" -m 2048 -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/OVMF_VARS_a0.fd" \
    -drive file="$ISO",if=none,id=cd,media=cdrom,readonly=on \
    -device virtio-scsi-pci -device scsi-cd,drive=cd,bootindex=0 \
    -display none -monitor "unix:$sock,server,nowait" &
  local qpid=$!

  # systemd-boot's menu times out after 15s; the kernel and the live
  # environment then need time to reach a console.
  sleep "${A0_WAIT:-150}"
  python3 - "$sock" "$shot" <<'PYA0' || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.settimeout(10); s.connect(sys.argv[1])
time.sleep(0.5)
try: s.recv(65536)
except Exception: pass
s.sendall(("screendump %s\n" % sys.argv[2]).encode())
time.sleep(4)
try: s.sendall(b"quit\n")
except Exception: pass
time.sleep(0.5)
PYA0
  kill "$qpid" 2>/dev/null || true
  wait "$qpid" 2>/dev/null || true

  if [[ ! -s "$shot" ]]; then
    _ERR "no screenshot — could not reach the qemu monitor"
    FAILS=$((FAILS+1)); return
  fi

  # Two numbers, and BOTH must clear their bar. Distinct colours alone is
  # what let the placeholder through; the lit fraction is what separates a
  # console full of text from a single centred line of qemu's own.
  local metrics colours lit
  metrics=$(python3 - "$shot" <<'PYM'
import sys
d = open(sys.argv[1], "rb").read()
i = 0
for _ in range(3):                      # P6, dimensions, maxval
    while d[i:i+1].isspace(): i += 1
    while not d[i:i+1].isspace(): i += 1
i += 1
px = d[i:]
n = len(px) // 3
seen = set(); lit = 0
for j in range(0, n * 3, 3):
    p = px[j:j+3]
    seen.add(p)
    if p != b"\x00\x00\x00": lit += 1
print(len(seen), round(100.0 * lit / n, 2))
PYM
) || metrics="0 0"
  colours=${metrics%% *}
  lit=${metrics##* }

  # The numbers are printed either way, so a human can judge rather than
  # trusting a bare "ok" -- the exact thing that went wrong the first time.
  # Thresholds set from MEASURED values, not guessed:
  #   qemu's "display not initialized" placeholder:  6 colours, ~2.0% lit
  #   a real booted archiso console (motd + prompt): 12 colours, ~4.1% lit
  # The bars sit between the two, not just above the placeholder -- 4% was
  # the first attempt and a real boot cleared it by 0.09%, which is not a
  # margin, it is a coincidence waiting to fail.
  if (( colours > ${A0_MIN_COLOURS:-8} )) && awk "BEGIN{exit !($lit > ${A0_MIN_LIT:-3})}"; then
    _OK "the medium boots through its own bootloader ($colours colours, ${lit}% of the screen lit)"
    PASSES=$((PASSES+1))
  else
    _ERR "the medium did not reach a console ($colours colours, ${lit}% lit)"
    _DIM "measured references: placeholder = 6 colours / ~2.0% lit,"
    _DIM "real console = 12 colours / ~4.1% lit. Look at $shot before"
    _DIM "believing either verdict — that step is what caught the false pass."
    FAILS=$((FAILS+1))
  fi
}

extract_kernel() {
  # Pulled out of the ISO rather than from the build tree, so phase A runs
  # the kernel that was actually shipped.
  local m="$TEST_DIR/isomnt"
  sudo mkdir -p "$m"
  sudo mount -o loop,ro "$ISO" "$m"
  cp "$m/arch/boot/x86_64/vmlinuz-linux"        "$TEST_DIR/vmlinuz"
  cp "$m/arch/boot/x86_64/initramfs-linux.img"  "$TEST_DIR/initramfs.img"
  sudo umount "$m"
  [[ -s "$TEST_DIR/vmlinuz" && -s "$TEST_DIR/initramfs.img" ]]
}

# A disk that already has somebody else's operating system on it.
#
# Without this the dual-boot path could only ever be tested against empty
# space, which is precisely the case where it cannot do damage. The point
# of the test is the opposite: prove that an existing ESP and an existing
# data partition come through untouched. The marker file is what makes
# "untouched" checkable rather than assumed.
make_dualboot_disk() {
  qemu-img create -f qcow2 "$DISK" "${VM_DISK_GB}G" >/dev/null
  # Connect first with no partitions expected, write the table, then wait
  # for the nodes rather than sleeping and hoping.
  sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1 || true
  sleep 1
  sudo qemu-nbd --connect=/dev/nbd0 -f qcow2 "$DISK"
  NBD_CONNECTED=1
  sleep 1
  sudo sgdisk -n1:0:+300M -t1:ef00 -c1:EFI      /dev/nbd0 >/dev/null
  sudo sgdisk -n2:0:+20G  -t2:8300 -c2:OTHER_OS /dev/nbd0 >/dev/null

  for _ in $(seq 1 20); do
    sudo partprobe /dev/nbd0 2>/dev/null || true
    udevadm settle || true
    [[ -b /dev/nbd0p2 ]] && break
    sleep 1
  done
  [[ -b /dev/nbd0p2 ]] || { _ERR "fixture partitions never appeared"; return 1; }
  sudo mkfs.fat -F32 /dev/nbd0p1 >/dev/null 2>&1
  sudo mkfs.ext4 -F  /dev/nbd0p2 >/dev/null 2>&1
  sudo mkdir -p "$TEST_DIR/other"
  sudo mount /dev/nbd0p2 "$TEST_DIR/other"
  echo "DO-NOT-DELETE-ME" | sudo tee "$TEST_DIR/other/other-os-marker" >/dev/null
  sudo umount "$TEST_DIR/other"
  # A file on the existing ESP too: the ESP is the partition an installer
  # is most likely to reformat by accident, and doing so destroys the other
  # system's bootloader.
  sudo mount /dev/nbd0p1 "$TEST_DIR/other"
  sudo mkdir -p "$TEST_DIR/other/EFI/OtherOS"
  echo "OTHER-BOOTLOADER" | sudo tee "$TEST_DIR/other/EFI/OtherOS/bootx64.efi" >/dev/null
  sudo umount "$TEST_DIR/other"
  sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null
  NBD_CONNECTED=0
  _OK "created a disk with an existing ESP, a 20G OTHER_OS partition and free space"
}

phase_a() {
  say "phase A — install, unattended"
  rm -f "$DISK" "$SERIAL_A"
  if [[ "$MODE" == dualboot ]]; then
    make_dualboot_disk
  else
    qemu-img create -f qcow2 "$DISK" "${VM_DISK_GB}G" >/dev/null
    _OK "created a ${VM_DISK_GB}G blank disk"
  fi

  # A private copy of the EFI variable store. Sharing the packaged one
  # would let the guest write to a root-owned system file, and a guest with
  # no writable NVRAM cannot record a boot entry at all.
  cp "$OVMF_VARS_SRC" "$TEST_DIR/OVMF_VARS.fd"

  extract_kernel || { _ERR "could not extract the kernel from the ISO"; FAILS=$((FAILS+1)); return 1; }
  _OK "kernel and initramfs extracted from the ISO"

  write_autotest
  start_http

  # archisolabel must match iso_label in profiledef.sh, or the initramfs
  # cannot find its own squashfs and drops to an emergency shell.
  local label
  label=$(blkid -o value -s LABEL "$ISO" 2>/dev/null || true)
  [[ -n "$label" ]] || { _ERR "could not read the ISO volume label"; FAILS=$((FAILS+1)); return 1; }
  _OK "ISO volume label: $label"

  _DIM "installing; up to $((PHASE_A_TIMEOUT / 60)) minutes. serial: $SERIAL_A"
  timeout "$PHASE_A_TIMEOUT" qemu-system-x86_64 \
    "${ACCEL[@]}" -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/OVMF_VARS.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -drive file="$ISO",if=none,id=cd,media=cdrom,readonly=on \
    -device virtio-scsi-pci -device scsi-cd,drive=cd \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -kernel "$TEST_DIR/vmlinuz" -initrd "$TEST_DIR/initramfs.img" \
    -append "archisobasedir=arch archisolabel=$label console=ttyS0,115200 script=http://$HOST_FROM_GUEST:$HTTP_PORT/autotest.sh" \
    -display none -serial "file:$SERIAL_A" \
    2>/dev/null || true

  if grep -q 'ATI-OS-TEST: INSTALL-OK' "$SERIAL_A" 2>/dev/null; then
    _OK "the installer reported success"
    PASSES=$((PASSES+1))
  else
    _ERR "the installer did not report success"
    _DIM "last 30 lines of $SERIAL_A:"
    tail -30 "$SERIAL_A" 2>/dev/null | sed 's/^/       /'
    FAILS=$((FAILS+1))
    return 1
  fi
}

# nbd helpers, shared by the phase B injection and phase C's assertions.
# Connect $DISK to /dev/nbd0 and wait for its partitions to appear.
#
# Two failures this avoids, both seen for real:
#
#   1. A previous run that ended badly leaves /dev/nbd0 connected. The next
#      --connect then attaches to a busy device and the partitions never
#      show up, which surfaces as
#      "fsconfig() failed: /dev/nbd0p2: Can't lookup blockdev" -- an error
#      that names the symptom and nothing else.
#   2. A fixed `sleep 2` is a guess. Partition nodes appear when udev has
#      finished, which is sometimes slower than two seconds and usually
#      much faster, so waiting for the device beats sleeping for a number.
nbd_connect() {                # nbd_connect <image> [expected-part-count]
  local img="$1" want="${2:-2}"
  sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1 || true
  sleep 1
  sudo qemu-nbd --connect=/dev/nbd0 -f qcow2 "$img"
  NBD_CONNECTED=1
  sudo partprobe /dev/nbd0 2>/dev/null || true
  udevadm settle || true
  for _ in $(seq 1 20); do
    [[ -b "/dev/nbd0p$want" ]] && return 0
    sudo partprobe /dev/nbd0 2>/dev/null || true
    sleep 1
  done
  _ERR "/dev/nbd0p$want never appeared after connecting $img"
  return 1
}

nbd_up() {
  local want=2
  [[ "$MODE" == dualboot ]] && want=3
  nbd_connect "$DISK" "$want" || return 1

  # Which partition holds the root filesystem depends on the mode: a
  # normal install is partition 2, a dual-boot install is partition 3
  # because 1 and 2 already belonged to the other operating system.
  local rootpart=/dev/nbd0p2
  [[ "$MODE" == dualboot ]] && rootpart=/dev/nbd0p3

  if [[ "$MODE" == encrypted ]]; then
    # The container has to be opened from the HOST to read anything, which
    # doubles as proof that it is genuinely encrypted: if this succeeds
    # with the passphrase, the data was not sitting there in plain text.
    printf '%s' "$LUKS_PASS" | sudo cryptsetup open "$rootpart" testcrypt - 2>/dev/null \
      || { _ERR "could not open the LUKS container with the passphrase"; FAILS=$((FAILS+1)); return 1; }
    rootpart=/dev/mapper/testcrypt
    LUKS_OPENED=1
  fi

  sudo mkdir -p "$TEST_DIR/mnt"
  sudo mount "$rootpart" "$TEST_DIR/mnt"
  sudo mount /dev/nbd0p1 "$TEST_DIR/mnt/boot"
}
nbd_down() {
  sudo umount -R "$TEST_DIR/mnt"
  (( ${LUKS_OPENED:-0} )) && { sudo cryptsetup close testcrypt 2>/dev/null || true; LUKS_OPENED=0; }
  sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null
  NBD_CONNECTED=0
}

phase_b() {
  say "phase B — first boot: the desktop installs itself"

  # A test-only unit is INJECTED into the image rather than shipped on the
  # ISO. The product must not contain a service that powers the machine off
  # when setup finishes -- that is a test harness behaviour, and baking it
  # in would mean testing something other than what ships.
  #
  # It waits for ati-os-firstboot to finish, then halts, which is what lets
  # this phase run to completion without guessing a duration.
  nbd_up
  sudo tee "$TEST_DIR/mnt/etc/systemd/system/ati-os-test-poweroff.service" >/dev/null <<'EOF'
[Unit]
Description=TEST ONLY — power off once first-boot setup has finished
After=ati-os-firstboot.service
Requires=ati-os-firstboot.service

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff -i

[Install]
WantedBy=multi-user.target
EOF
  sudo mkdir -p "$TEST_DIR/mnt/etc/systemd/system/multi-user.target.wants"
  sudo ln -sf /etc/systemd/system/ati-os-test-poweroff.service \
    "$TEST_DIR/mnt/etc/systemd/system/multi-user.target.wants/ati-os-test-poweroff.service"
  nbd_down
  _OK "injected the test-only poweroff unit"

  rm -f "$SERIAL_B"
  local bsock="$TEST_DIR/b-monitor.sock"
  rm -f "$bsock"

  # No ISO attached. If the boot entry, the PARTUUID or the ESP layout is
  # wrong there is nothing else here to boot from.
  _DIM "running the wizard on first boot; up to $((PHASE_B_TIMEOUT / 60)) minutes"
  timeout "$PHASE_B_TIMEOUT" qemu-system-x86_64 \
    "${ACCEL[@]}" -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$TEST_DIR/OVMF_VARS.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none -serial "file:$SERIAL_B" \
    -monitor "unix:$bsock,server,nowait" &
  local bpid=$!

  if [[ "$MODE" == encrypted ]]; then
    # Typed blind, because the prompt is on VGA and this phase watches
    # serial. The passphrase is sent twice at different delays rather than
    # trying to detect the prompt: cryptsetup simply re-asks after a wrong
    # or early answer, so an extra attempt costs nothing, while a single
    # mistimed one would hang the whole phase for an hour.
    _DIM "sending the LUKS passphrase through the qemu monitor"
    sleep 25; send_keys "$bsock" "$LUKS_PASS" 2>/dev/null || true
    sleep 25; send_keys "$bsock" "$LUKS_PASS" 2>/dev/null || true
  fi

  wait "$bpid" 2>/dev/null || true

  # The evidence is on DISK, not on the serial line.
  #
  # An earlier version grepped this log for a login prompt and reported
  # failure when it found none -- but the installed system's cmdline has no
  # console=ttyS0, so kernel and getty output go to VGA and can never
  # appear here. The serial log did prove one thing, which is why it is
  # still captured: systemd-boot rendered a menu titled ATI-OS and counted
  # down, so firmware found the ESP and the entry is valid.
  if grep -qa 'ATI-OS' "$SERIAL_B" 2>/dev/null; then
    _OK "systemd-boot found and rendered the ATI-OS entry"
    PASSES=$((PASSES+1))
  else
    _ERR "systemd-boot did not render an ATI-OS entry"
    _DIM "last 20 lines of $SERIAL_B:"
    tail -20 "$SERIAL_B" 2>/dev/null | tr -d '\000' | sed 's/^/       /'
    FAILS=$((FAILS+1))
  fi
}

phase_c() {
  say "phase C — assert against the installed filesystem"
  local mnt="$TEST_DIR/mnt"
  nbd_up

  # The first-boot evidence comes first, because everything else about the
  # desktop depends on the wizard having actually run. The marker holds the
  # wizard's EXIT STATUS, so "it ran" and "it succeeded" are distinct
  # answers rather than one hopeful one.
  if sudo test -f "$mnt/var/lib/ati-os/firstboot-complete"; then
    local rc
    rc=$(sudo cat "$mnt/var/lib/ati-os/firstboot-complete" 2>/dev/null || echo "?")
    if [[ "$rc" == "0" ]]; then
      _OK "first-boot setup ran and the wizard exited 0"
      PASSES=$((PASSES+1))

      # The exit status is NOT the whole answer. wizard.sh returns 0 even
      # when individual modules fail -- a run reporting
      # "45 ok / 0 not run / 1 failed" still exits 0 -- so trusting it
      # alone reported 15/15 on an install with a broken module. The
      # summary card is the real tally, and it is parsed here rather than
      # believed.
      local card failed_n
      card=$(sudo tr '\r' '\n' < "$mnt/var/log/ati-os-firstboot.log" 2>/dev/null \
             | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -aoE '[0-9]+ ok[^│]*[0-9]+ failed' | tail -1)
      failed_n=$(printf '%s' "$card" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')
      if [[ -z "$card" ]]; then
        _ERR "could not find the wizard's summary card in the log"
        FAILS=$((FAILS+1))
      elif [[ "$failed_n" == "0" ]]; then
        _OK "every wizard module passed ($card)"
        PASSES=$((PASSES+1))
      else
        _ERR "wizard modules failed ($card)"
        _DIM "the failing module's own output is what to read, not this line:"
        sudo tr '\r' '\n' < "$mnt/var/log/ati-os-firstboot.log" \
          | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -a -B6 'failed (attempt' \
          | grep -avE '^\s*$|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]' | tail -8 | sed 's/^/       /'
        FAILS=$((FAILS+1))
      fi
    else
      _ERR "first-boot setup ran but the wizard exited $rc"
      _DIM "wizard output, last 40 lines:"
      sudo tail -40 "$mnt/var/log/ati-os-firstboot.log" 2>/dev/null | sed 's/^/       /'
      FAILS=$((FAILS+1))
    fi
  else
    _ERR "first-boot setup never completed (no marker)"
    _DIM "log, if it exists:"
    sudo tail -30 "$mnt/var/log/ati-os-firstboot.log" 2>/dev/null | sed 's/^/       /'
    FAILS=$((FAILS+1))
  fi

  assert "os-release names ATI-OS" \
    sudo grep -q '^NAME="ATI-OS"' "$mnt/etc/os-release"
  assert "os-release keeps ID_LIKE=arch (wizard's Arch gate depends on it)" \
    sudo grep -q '^ID_LIKE=arch' "$mnt/etc/os-release"
  assert "the dotfiles landed in the user's home" \
    sudo test -d "$mnt/home/$TEST_USER/.dotfiles/.git"
  assert "qtile config is present" \
    sudo test -f "$mnt/home/$TEST_USER/.config/qtile/config.py"
  assert "the install-time package repo was removed (during first boot)" \
    sudo bash -c "! grep -q '\[ati-local\]' '$mnt/etc/pacman.conf'"
  assert "the install-time package cache was removed" \
    sudo bash -c "! test -d '$mnt/var/cache/ati-local'"
  assert "a boot entry exists" \
    sudo test -f "$mnt/boot/loader/entries/ati-os.conf"

  # The check that matters most, and the one this repo added
  # `boot-splash verify-root` for: an entry whose root= does not match the
  # real partition boots something else, or nothing.
  # An encrypted install has no root=PARTUUID at all -- root is the mapper
  # device the initramfs creates, named via rd.luks.name. Asserting on
  # PARTUUID there compares an empty string against a real one and fails a
  # system that is correct, which is exactly what it did on the first
  # encrypted run. The equivalent check for that mode is the pair of
  # assertions further down (the hook, and the entry naming the container).
  if [[ "$MODE" == encrypted ]]; then
    assert "the boot entry points root at the unlocked container" \
      sudo grep -q 'root=/dev/mapper/' "$mnt/boot/loader/entries/ati-os.conf"
  else
    local entry_uuid real_uuid rootdev=/dev/nbd0p2
    [[ "$MODE" == dualboot ]] && rootdev=/dev/nbd0p3
    entry_uuid=$(sudo grep -oP 'root=PARTUUID=\K[0-9a-fA-F-]+' \
                   "$mnt/boot/loader/entries/ati-os.conf" || true)
    real_uuid=$(sudo blkid -o value -s PARTUUID "$rootdev" || true)
    if [[ -n "$entry_uuid" && "$entry_uuid" == "$real_uuid" ]]; then
      _OK "boot entry root=PARTUUID matches the real root partition"
      PASSES=$((PASSES+1))
    else
      _ERR "boot entry PARTUUID mismatch (entry='$entry_uuid' real='$real_uuid')"
      FAILS=$((FAILS+1))
    fi
  fi

  assert "the kernel is on the ESP" sudo test -f "$mnt/boot/vmlinuz-linux"
  assert "an initramfs is on the ESP" sudo test -f "$mnt/boot/initramfs-linux.img"

  # Spot-check that the prebuilt packages were actually INSTALLED, not
  # merely carried. If pacman ignored [ati-local] and yay compiled them
  # instead, the install still succeeds -- it just takes two hours -- and
  # nothing else in this test would notice.
  local missing=()
  for p in eww qtile-extras pacman-static espanso-x11 yay-bin; do
    sudo test -d "$mnt/var/lib/pacman/local" \
      && sudo bash -c "ls '$mnt/var/lib/pacman/local' | grep -q '^$p-'" \
      || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    _OK "prebuilt AUR packages are installed (eww, qtile-extras, pacman-static, espanso, yay)"
    PASSES=$((PASSES+1))
  else
    _ERR "not installed: ${missing[*]}"
    FAILS=$((FAILS+1))
  fi

  if [[ "$MODE" == encrypted ]]; then
    # Opening it above already proved it decrypts. This proves the
    # installed system knows how to do so ITSELF -- without the hook and
    # the cmdline the machine boots to an emergency shell every time.
    assert "the initramfs has an encryption hook" \
      sudo grep -qE '^HOOKS=.*(sd-encrypt|encrypt)' "$mnt/etc/mkinitcpio.conf"
    assert "the boot entry unlocks the container" \
      sudo grep -qE 'rd.luks.name=|cryptdevice=' "$mnt/boot/loader/entries/ati-os.conf"
    assert "cryptsetup is installed in the target" \
      sudo bash -c "ls '$mnt/var/lib/pacman/local' | grep -q '^cryptsetup-'"
  fi

  if [[ "$MODE" == dualboot ]]; then
    # The whole point. If either of these fails, the installer ate
    # somebody's operating system.
    sudo mkdir -p "$TEST_DIR/other"
    sudo mount /dev/nbd0p2 "$TEST_DIR/other" 2>/dev/null
    assert "the other OS partition still has its data" \
      sudo grep -q 'DO-NOT-DELETE-ME' "$TEST_DIR/other/other-os-marker"
    sudo umount "$TEST_DIR/other" 2>/dev/null || true
    assert "the other OS bootloader survived on the shared ESP" \
      sudo grep -q 'OTHER-BOOTLOADER' "$mnt/boot/EFI/OtherOS/bootx64.efi"
    assert "ATI-OS added its own boot entry alongside" \
      sudo test -f "$mnt/boot/loader/entries/ati-os.conf"
  fi

  nbd_down
}

report() {
  say "result"
  printf '  passed: %d\n  failed: %d\n\n' "$PASSES" "$FAILS"
  _DIM "phase A serial: $SERIAL_A"
  _DIM "phase B serial: $SERIAL_B"
  printf '\n'
  _WARN "not covered by any phase: the GPU path (picom, glx, animations),"
  _DIM "AMD and NVIDIA, HiDPI, and booting a real USB stick on real firmware."
  _DIM "qemu has no graphics hardware — a pass here says nothing about them."
  (( FAILS == 0 ))
}

main() {
  if (( DO_CLEAN )); then
    say "cleaning"
    rm -rf "$TEST_DIR"
    _OK "test artefacts removed"
    exit 0
  fi
  # A separate image per mode: three runs that shared one file would each
  # destroy the previous one's evidence.
  [[ "$MODE" != default ]] && DISK="$TEST_DIR/ati-os-test-$MODE.qcow2"
  say "mode: $MODE"
  preflight
  (( CHECK_ONLY )) && { _OK "--check only, nothing was run"; exit 0; }
  phase_a0
  phase_a || { report; exit 1; }
  phase_b
  phase_c
  report
}

mkdir -p "$WORK"
exec > >(tee -a "$WORK/test-iso-run.log") 2>&1
printf '\n===== run started %s =====\n' "$(date -Is)"
main "$@"
