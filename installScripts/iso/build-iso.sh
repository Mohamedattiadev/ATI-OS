#!/usr/bin/env bash
# build-iso.sh — build the ATI-OS installation medium.
#
# Order of operations, and why:
#
#   1. aur-repo.sh must already have run. Building 31 AUR packages is two
#      to three hours and is cached; rebuilding it to change a menu label
#      would be absurd, so it is a separate script and this one only
#      checks its output.
#   2. The profile is STAGED into a work directory before mkarchiso sees
#      it. Nothing is generated inside installScripts/iso/profile, so a
#      build never dirties the git checkout and `git status` stays
#      meaningful after one.
#   3. mkarchiso runs against the staged copy.
#
# Usage:
#   ./build-iso.sh            # build
#   ./build-iso.sh --check    # preflight only, build nothing
#   ./build-iso.sh --clean    # remove the work directory (keeps the ISO)

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

WORK="${ATI_ISO_WORK:-$HOME/ati-os-build}"
REPO_DIR="$WORK/repo"
STAGE="$WORK/profile"        # the staged profile mkarchiso actually reads
ISO_WORK="$WORK/mkarchiso"   # mkarchiso's scratch space
OUT_DIR="$WORK/out"
REPO_NAME=ati-local

# mkarchiso unpacks the whole airootfs uncompressed before squashing it,
# so the scratch space is far larger than the finished ISO: the live
# environment, plus ~2 GB of prebuilt packages, plus the squashfs being
# written alongside it.
NEED_GB="${NEED_GB:-25}"

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

CHECK_ONLY=0; DO_CLEAN=0
while (( $# )); do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --clean) DO_CLEAN=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) _ERR "unknown argument: $1"; exit 2 ;;
  esac
  shift
done

preflight() {
  say "preflight"
  local fail=0

  if command -v mkarchiso >/dev/null; then
    _OK "mkarchiso"
  else
    _ERR "mkarchiso not found — sudo pacman -S archiso"
    fail=1
  fi

  if [[ -d "$SCRIPT_DIR/profile" ]]; then
    _OK "profile at $SCRIPT_DIR/profile"
  else
    _ERR "no profile directory"
    fail=1
  fi

  # The prebuilt repository is what makes this ISO worth building. Without
  # it the image still works, but every AUR package is compiled on the
  # user's machine and the install goes back to two hours -- so warn
  # loudly rather than producing that quietly.
  if [[ -f "$REPO_DIR/$REPO_NAME.db.tar.zst" ]] \
     && compgen -G "$REPO_DIR/*.pkg.tar.*" >/dev/null; then
    local n sz
    n=$(find "$REPO_DIR" -name '*.pkg.tar.*' | wc -l)
    sz=$(du -sh "$REPO_DIR" | cut -f1)
    _OK "prebuilt repository: $n packages, $sz"
  else
    _WARN "no prebuilt AUR repository at $REPO_DIR"
    _DIM "run ./aur-repo.sh first, or the ISO ships without it and every"
    _DIM "install compiles the AUR set itself (~2 hours)"
  fi

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    _OK "dotfiles checkout at $DOTFILES_DIR"
  else
    _ERR "$DOTFILES_DIR is not a git checkout"
    fail=1
  fi

  mkdir -p "$WORK"
  local avail_gb
  avail_gb=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc '0-9')
  if (( avail_gb >= NEED_GB )); then
    _OK "disk: ${avail_gb}G free at $WORK (need ${NEED_GB}G)"
  else
    _ERR "disk: ${avail_gb}G free at $WORK, need ${NEED_GB}G"
    fail=1
  fi

  if sudo -n true 2>/dev/null; then
    _OK "sudo available, passwordless"
  elif [[ -t 0 ]]; then
    _WARN "sudo needs a password — mkarchiso will ask"
  else
    _ERR "sudo needs a password and there is no terminal to type it into"
    fail=1
  fi

  (( fail )) && { _ERR "preflight failed — nothing was built"; exit 1; }
  _OK "preflight clean"
}

# Unmount anything still bind-mounted under the work directory BEFORE
# deleting it.
#
# This is a safety fix, not tidiness. mkarchiso bind-mounts /dev, /proc,
# /sys and /run into its airootfs, and if a build is interrupted those
# mounts survive it. `rm -rf` does not stop at a mount point -- it
# descends through it -- so deleting the work directory while /dev is
# still bound there means running `rm -rf` against the HOST's /dev.
#
# That nearly happened here: a build was killed when the ISO it had open
# was deleted underneath it, leaving eight stale mounts including /dev and
# /proc. The host survived, but only because device nodes happened to
# resist deletion.
#
# Deepest paths first, so /dev/pts comes down before /dev.
unmount_workdir() {
  local target="$1" m
  mount | awk -v t="$target" '$3 ~ ("^" t) {print $3}' | sort -r | while read -r m; do
    sudo umount -l "$m" 2>/dev/null || true
  done
  if mount | awk -v t="$target" '$3 ~ ("^" t)' | grep -q .; then
    _ERR "could not unmount everything under $target — refusing to delete it"
    mount | awk -v t="$target" '$3 ~ ("^" t) {print "       " $3}'
    exit 1
  fi
}

stage_profile() {
  say "staging the profile"
  sudo rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -a "$SCRIPT_DIR/profile/." "$STAGE/"

  # Same trap aur-repo.sh hit, in a second place: mkarchiso pacstraps the
  # airootfs using the PROFILE's pacman.conf, whose HookDir falls back to
  # the compiled-in default of /etc/pacman.d/hooks -- the HOST's. This
  # repo installs 00-preflight.hook there, which execs
  # /usr/local/bin/pacman-preflight, which does not exist inside a fresh
  # airootfs. pacman reports that as "call to execv failed" and names
  # neither the hook nor the file.
  #
  # An explicit HookDir REPLACES the default rather than adding to it, and
  # it must be inserted into [options] -- appended at the end of the file
  # it would land inside [extra] and be silently ignored.
  local empty_hooks="$WORK/empty-hooks"
  mkdir -p "$empty_hooks"
  sed -i "0,/^\[options\]/s|^\[options\]|[options]\nHookDir = $empty_hooks/|" \
    "$STAGE/pacman.conf"
  local resolved
  resolved=$(pacman-conf --config "$STAGE/pacman.conf" HookDir)
  [[ "$resolved" == "$empty_hooks/" ]] \
    || { _ERR "HookDir override did not take (got: $resolved)"; exit 1; }
  _OK "host pacman hooks excluded from the airootfs"

  local share="$STAGE/airootfs/usr/share/ati-os"
  install -d "$share"

  # Stamp the build date INTO the medium.
  #
  # The prebuilt AUR packages are the one part of this ISO that genuinely
  # rots. Everything else is fetched at install time -- mirrors via
  # reflector, databases via pacman -Sy, the base system and its libraries
  # from those databases -- so an old medium still installs a current
  # system. The [ati-local] packages do not: they were COMPILED against
  # the libraries of this build day, and get installed next to whatever
  # glibc/rust/python the mirrors are serving on install day.
  #
  # That is a partial upgrade wearing a disguise. It does not fail at
  # install; it fails later, when something reaches for a .so version that
  # no longer exists. So the medium records when it was made, and the
  # installer decides what to do about it rather than finding out the hard
  # way.
  date +%s > "$share/BUILD_EPOCH"
  date -Iseconds > "$share/BUILD_DATE"
  _OK "build date stamped ($(date -Iseconds))"

  # The prebuilt packages ride along as FILES rather than being installed
  # into the live environment. The live session never needs eww or brave;
  # only the installer does, and it installs them into the target.
  if compgen -G "$REPO_DIR/*.pkg.tar.*" >/dev/null; then
    install -d "$share/repo"
    cp -a "$REPO_DIR/." "$share/repo/"
    _OK "prebuilt packages staged ($(du -sh "$share/repo" | cut -f1))"
  fi

  # Bake the dotfiles from the LOCAL checkout, not from GitHub. The point
  # of this ISO is to reproduce this machine, and the local checkout is
  # what this machine actually runs. A clone from GitHub would silently
  # build an ISO of whatever was last pushed instead.
  local branch dirty
  branch=$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref HEAD)
  dirty=$(git -C "$DOTFILES_DIR" status --porcelain | wc -l)
  if (( dirty )); then
    # Worth stopping for. `git clone` copies COMMITS, so uncommitted work
    # is silently absent from the ISO -- and the resulting image looks
    # perfectly fine while being subtly not what is on this machine.
    _WARN "$dirty uncommitted change(s) in $DOTFILES_DIR"
    _DIM "git clone copies commits only, so these will NOT be on the ISO"
    _DIM "commit them first if they are meant to ship"
  fi
  git clone --no-hardlinks --branch "$branch" "$DOTFILES_DIR" "$share/dotfiles" 2>/dev/null
  _OK "dotfiles baked from branch '$branch' @ $(git -C "$share/dotfiles" rev-parse --short HEAD)"
}

build() {
  say "mkarchiso"
  _DIM "20-40 minutes; xz compression of the squashfs is most of it"
  mkdir -p "$OUT_DIR"
  unmount_workdir "$ISO_WORK"
  sudo rm -rf "$ISO_WORK"
  sudo mkarchiso -v -w "$ISO_WORK" -o "$OUT_DIR" "$STAGE"
  # mkarchiso's scratch space is tens of gigabytes and is worthless after
  # a successful build.
  unmount_workdir "$ISO_WORK"
  sudo rm -rf "$ISO_WORK"
}

report() {
  say "result"
  local iso
  iso=$(find "$OUT_DIR" -name '*.iso' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -n "$iso" ]] || { _ERR "no ISO was produced"; exit 1; }
  _OK "$iso"
  _DIM "size: $(du -h "$iso" | cut -f1)"

  # A checksum, so a bad download or a dying USB stick is caught BEFORE
  # someone boots it and blames the installer. A half-written image fails
  # in bizarre ways that look like bugs.
  sha256sum "$iso" > "$iso.sha256"
  _OK "checksum: $(basename "$iso").sha256"
  _DIM "verify with:  sha256sum -c $(basename "$iso").sha256"
  printf '\n'
  _DIM "test it here:   ./test-iso.sh"
  _DIM "write to USB:   sudo dd if=$iso of=/dev/sdX bs=4M status=progress oflag=sync"
  _DIM "                (check /dev/sdX with lsblk first — dd does not ask)"
}

main() {
  if (( DO_CLEAN )); then
    say "cleaning"
    unmount_workdir "$ISO_WORK"
    sudo rm -rf "$STAGE" "$ISO_WORK"
    _OK "work directories removed (ISOs in $OUT_DIR kept)"
    exit 0
  fi
  preflight
  (( CHECK_ONLY )) && { _OK "--check only, nothing was built"; exit 0; }
  stage_profile
  build
  report
}

mkdir -p "$WORK"
exec > >(tee -a "$WORK/build-iso-run.log") 2>&1
printf '\n===== run started %s =====\n' "$(date -Is)"
main "$@"
