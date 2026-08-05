#!/usr/bin/env bash
# film-iso.sh — record a real install as an animated GIF.
#
# Every frame is a genuine screendump from a running guest. Nothing here is
# drawn or mocked up: the point is to show what a person actually sees, and
# a hand-made mockup would drift from the product the moment either
# changed. It is also a test in its own right -- it has already been the
# case today that a screenshot showed something quite different from what
# the assertions claimed.
#
# Two segments, because an install spans a reboot:
#   1  the medium booting, the welcome screen, and the installer running
#   2  the first boot, where the desktop builds itself
#
# Usage:
#   ./film-iso.sh              # record both segments and build the GIF
#   ./film-iso.sh --check      # preflight only

set -Eeuo pipefail

WORK="${ATI_ISO_WORK:-$HOME/ati-os-build}"
OUT_DIR="$WORK/out"
FILM_DIR="$WORK/film"
FRAMES="$FILM_DIR/frames"
GIF="$FILM_DIR/ati-os-install.gif"

# One frame every INTERVAL seconds. Slow enough not to steal CPU from the
# guest it is filming, fast enough that a 5-minute install is not three
# frames.
INTERVAL="${INTERVAL:-6}"
SEG1_SECS="${SEG1_SECS:-600}"     # boot + welcome + installer
SEG2_SECS="${SEG2_SECS:-1500}"    # first boot, the wizard's 47 modules

VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_DISK_GB="${VM_DISK_GB:-60}"
TEST_USER=atifilm
TEST_PASS=atifilm
TEST_HOST=ati-os

if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_R=$'\e[0m'
else
  C_OK=; C_ERR=; C_DIM=; C_R=
fi
_OK()  { printf '%s  ok %s %s\n' "$C_OK"  "$C_R" "$*"; }
_ERR() { printf '%sfail %s %s\n' "$C_ERR" "$C_R" "$*" >&2; }
_DIM() { printf '%s     %s%s\n'  "$C_DIM" "$*" "$C_R"; }
say()  { printf '\n=== %s ===\n' "$*"; }

CHECK_ONLY=0; ONLY3=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  # Re-film only the desktop. The install is already on the disk, so this
  # is minutes rather than another full run.
  --desktop-only) ONLY3=1 ;;
esac

find_iso()  { ISO=$(find "$OUT_DIR" -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-); [[ -n "$ISO" ]]; }
find_ovmf() {
  local c
  for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd \
           /usr/share/edk2-ovmf/x64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [[ -f "$c" ]] && { OVMF_CODE="$c"; break; }; done
  for c in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd \
           /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$c" ]] && { OVMF_VARS_SRC="$c"; break; }; done
  [[ -n "${OVMF_CODE:-}" && -n "${OVMF_VARS_SRC:-}" ]]
}

preflight() {
  say "preflight"
  local fail=0
  for t in qemu-system-x86_64 qemu-img python3 magick; do
    if command -v "$t" >/dev/null; then _OK "$t"
    elif [[ "$t" == magick ]] && command -v convert >/dev/null; then _OK "convert (ImageMagick)"
    else _ERR "$t not found"; fail=1; fi
  done
  find_iso  && _OK "ISO: $ISO"        || { _ERR "no ISO in $OUT_DIR"; fail=1; }
  find_ovmf && _OK "OVMF: $OVMF_CODE" || { _ERR "no OVMF firmware"; fail=1; }
  [[ -e /dev/kvm && -w /dev/kvm ]] && { _OK "KVM"; ACCEL=(-enable-kvm -cpu host); } \
                                   || { _OK "no KVM (slower)"; ACCEL=(-cpu max); }
  (( fail )) && { _ERR "preflight failed"; exit 1; }
  _OK "preflight clean"
}

# Grab one frame through the qemu monitor.
#
# The monitor is a unix socket and the wait happens HERE, on the host,
# because qemu's monitor has no `sleep` command -- a lesson this repo paid
# for with a phase that screenshotted qemu's "display not initialized"
# placeholder and called it a pass.
shoot() {                     # shoot <sock> <path>
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.settimeout(8); s.connect(sys.argv[1])
time.sleep(0.2)
try: s.recv(65536)
except Exception: pass
s.sendall(("screendump %s\n" % sys.argv[2]).encode())
time.sleep(1.2)
PY
}

# Film a running guest until it stops or the budget runs out.
film_loop() {                 # film_loop <sock> <seconds> <prefix> <pid>
  local sock="$1" budget="$2" prefix="$3" pid="$4"
  local n=0 elapsed=0
  while (( elapsed < budget )); do
    kill -0 "$pid" 2>/dev/null || break
    shoot "$sock" "$FRAMES/${prefix}-$(printf '%04d' "$n").ppm"
    n=$((n + 1)); elapsed=$((elapsed + INTERVAL))
    sleep "$INTERVAL"
  done
  printf '%s' "$n"
}

segment1() {
  say "segment 1 — boot, welcome screen, installer"
  rm -f "$DISK"
  qemu-img create -f qcow2 "$DISK" "${VM_DISK_GB}G" >/dev/null
  cp "$OVMF_VARS_SRC" "$FILM_DIR/vars1.fd"

  # Driven by the same script= hook test-iso.sh uses, so what gets filmed
  # is the real installer on the real medium rather than a staged run.
  mkdir -p "$FILM_DIR/http"
  cat > "$FILM_DIR/http/film.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
systemctl is-system-running --wait || true
# Show the welcome screen for a while so it appears in the film, then hand
# over to the installer. A human would sit here reading it.
ati-os-welcome < /dev/null &
sleep 25
kill %1 2>/dev/null || true
export ATI_DISK=/dev/vda ATI_HOSTNAME=$TEST_HOST ATI_USER=$TEST_USER
export ATI_PASS=$TEST_PASS ATI_TIMEZONE=UTC ATI_ENCRYPT=0 ATI_DUALBOOT=0
ati-os-install --unattended
sleep 20
systemctl poweroff -i
EOF
  chmod +x "$FILM_DIR/http/film.sh"
  ( cd "$FILM_DIR/http" && python3 -m http.server 8732 --bind 127.0.0.1 ) >/dev/null 2>&1 &
  HTTP_PID=$!
  sleep 1

  local m="$FILM_DIR/isomnt"
  sudo mkdir -p "$m"; sudo mount -o loop,ro "$ISO" "$m"
  cp "$m/arch/boot/x86_64/vmlinuz-linux" "$FILM_DIR/vmlinuz"
  cp "$m/arch/boot/x86_64/initramfs-linux.img" "$FILM_DIR/initramfs.img"
  sudo umount "$m"
  local label
  label=$(blkid -o value -s LABEL "$ISO")

  local sock="$FILM_DIR/s1.sock"; rm -f "$sock"
  qemu-system-x86_64 "${ACCEL[@]}" -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$FILM_DIR/vars1.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -drive file="$ISO",if=none,id=cd,media=cdrom,readonly=on \
    -device virtio-scsi-pci -device scsi-cd,drive=cd \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -kernel "$FILM_DIR/vmlinuz" -initrd "$FILM_DIR/initramfs.img" \
    -append "archisobasedir=arch archisolabel=$label script=http://10.0.2.2:8732/film.sh" \
    -display none -monitor "unix:$sock,server,nowait" &
  local qpid=$!
  sleep 3
  local n; n=$(film_loop "$sock" "$SEG1_SECS" "a" "$qpid")
  kill "$qpid" 2>/dev/null || true; wait "$qpid" 2>/dev/null || true
  kill "$HTTP_PID" 2>/dev/null || true
  _OK "segment 1: $n frames"
}

segment2() {
  say "segment 2 — first boot, the desktop builds itself"
  cp "$OVMF_VARS_SRC" "$FILM_DIR/vars2.fd"
  local sock="$FILM_DIR/s2.sock"; rm -f "$sock"
  qemu-system-x86_64 "${ACCEL[@]}" -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$FILM_DIR/vars2.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none -monitor "unix:$sock,server,nowait" &
  local qpid=$!
  sleep 3
  local n; n=$(film_loop "$sock" "$SEG2_SECS" "b" "$qpid")
  kill "$qpid" 2>/dev/null || true; wait "$qpid" 2>/dev/null || true
  _OK "segment 2: $n frames"
}

# ─── segment 3 — the actual desktop ──────────────────────────────────
#
# This is the part people actually want to see, and it needs the guest to
# log in and start X. Both are TEST-ONLY changes injected into the image
# here, never shipped on the ISO: a distribution that auto-logs-in and
# launches X without being asked is a different product.
#
# What this shows honestly: the real config.py, the real theme, the real
# fonts, the real bar -- rendered by the real qtile. What it does NOT show
# is compositing. qemu has no GPU, so picom's blur and the window
# animations are absent or wrong here. A frame from this segment is
# evidence about LAYOUT and THEME, not about the effects.
segment3() {
  say "segment 3 — the desktop itself"

  sudo modprobe nbd max_part=8 2>/dev/null || true
  sudo qemu-nbd --connect=/dev/nbd0 -f qcow2 "$DISK"
  sleep 2
  sudo partprobe /dev/nbd0 2>/dev/null || true
  udevadm settle || true; sleep 1
  local m="$FILM_DIR/mnt"
  sudo mkdir -p "$m"
  sudo mount /dev/nbd0p2 "$m"

  # Autologin on tty1.
  sudo mkdir -p "$m/etc/systemd/system/getty@tty1.service.d"
  sudo tee "$m/etc/systemd/system/getty@tty1.service.d/autologin.conf" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $TEST_USER --noclear %I \$TERM
EOF

  # Start X on that login.
  #
  # It must be a FISH snippet, not .bash_profile. step_login_shell chsh's
  # the account to fish, so bash's profile is never read and the first
  # attempt at this filmed a TTY running the shell's colour-test script
  # instead of the desktop -- a segment that looked like a capture failure
  # and was actually a wrong-shell failure.
  #
  # /etc/fish/conf.d rather than ~/.config/fish: the home directory's
  # config is stow-symlinked into the dotfiles checkout, so writing there
  # would modify the repo inside the guest.
  sudo mkdir -p "$m/etc/fish/conf.d"
  sudo tee "$m/etc/fish/conf.d/00-film-autostart.fish" >/dev/null <<'EOF'
# TEST-ONLY: injected by film-iso.sh so the desktop appears on camera.
if status is-login
    if test -z "$DISPLAY" -a "$XDG_VTNR" = 1
        exec startx
    end
end
EOF
  # Bash fallback, in case fish failed to install and the account is still bash.
  sudo mkdir -p "$m/etc/profile.d"
  sudo tee "$m/etc/profile.d/00-film-autostart.sh" >/dev/null <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ] && [ -n "${BASH_VERSION:-}" ]; then
  case "$-" in *i*) exec startx ;; esac
fi
EOF

  sudo umount "$m"
  sudo qemu-nbd --disconnect /dev/nbd0 >/dev/null
  _OK "injected autologin + startx (test-only, not on the ISO)"

  cp "$OVMF_VARS_SRC" "$FILM_DIR/vars3.fd"
  local sock="$FILM_DIR/s3.sock"; rm -f "$sock"
  # -vga virtio: qtile needs a framebuffer Xorg's built-in modesetting
  # driver can drive. step_gpu correctly installs no vendor driver in a
  # VM, so there is nothing else here to render with.
  qemu-system-x86_64 "${ACCEL[@]}" -m "$VM_RAM_MB" -smp "$(nproc)" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$FILM_DIR/vars3.fd" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -vga virtio -display none -monitor "unix:$sock,server,nowait" &
  local qpid=$!
  sleep 3
  local n; n=$(film_loop "$sock" "${SEG3_SECS:-240}" "c" "$qpid")
  kill "$qpid" 2>/dev/null || true; wait "$qpid" 2>/dev/null || true
  _OK "segment 3: $n frames"
}

build_gif() {
  say "assembling the GIF"
  local IM=magick
  command -v magick >/dev/null || IM=convert

  # Consecutive identical frames are dropped. A install spends minutes on
  # one unchanging progress screen, and without this the GIF is mostly
  # duplicates: bigger file, nothing more shown.
  local prev="" kept=0
  mkdir -p "$FRAMES/keep"
  local f
  for f in "$FRAMES"/*.ppm; do
    [[ -e "$f" ]] || continue
    local sum; sum=$(sha256sum "$f" | cut -d' ' -f1)
    [[ "$sum" == "$prev" ]] && continue
    prev="$sum"
    cp "$f" "$FRAMES/keep/$(printf '%04d' "$kept").ppm"
    kept=$((kept + 1))
  done
  _DIM "$kept distinct frames of $(find "$FRAMES" -maxdepth 1 -name '*.ppm' | wc -l)"
  (( kept )) || { _ERR "no frames captured"; exit 1; }

  # 900px wide keeps console text legible while keeping the file sane.
  $IM -delay 90 -loop 0 "$FRAMES/keep/"*.ppm \
      -resize 900x -colors 64 -layers optimize "$GIF"
  _OK "$GIF ($(du -h "$GIF" | cut -f1), $kept frames)"
}

main() {
  mkdir -p "$FILM_DIR" "$FRAMES"
  DISK="$FILM_DIR/film.qcow2"
  preflight
  (( CHECK_ONLY )) && { _OK "--check only"; exit 0; }
  if (( ONLY3 )); then
    rm -f "$FRAMES"/c-*.ppm; rm -rf "$FRAMES/keep"
    segment3
  else
    rm -f "$FRAMES"/*.ppm; rm -rf "$FRAMES/keep"
    segment1
    segment2
    segment3
  fi
  build_gif
}

main "$@"
