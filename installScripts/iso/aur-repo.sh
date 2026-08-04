#!/usr/bin/env bash
# aur-repo.sh — build every AUR package this repo declares into a local
# pacman repository, so the ISO can install them as binaries.
#
# This is the expensive half of the ISO and the whole reason it is worth
# building one. `pacman-static` alone compiles pacman and every dependency
# statically through single-threaded autotools -- about an hour. espanso,
# paru, didyoumean and yt-x are Rust. whisper.cpp is C++. On a fresh
# machine that is roughly two hours before the desktop appears; here it
# happens once, on the build host, and every install afterwards is a
# binary copy.
#
# Builds happen in a CLEAN CHROOT (devtools' makechrootpkg), never against
# the host. A package built against whatever happens to be installed here
# can link to a library that is not in its own dependency list, work
# perfectly on this machine, and fail on the user's -- which is the exact
# class of bug the VM harness was written to catch. The chroot has only
# `base-devel` plus each package's declared dependencies, so anything
# undeclared fails HERE rather than on a stranger's laptop.
#
# Usage:
#   ./aur-repo.sh              # build everything missing, then repo-add
#   ./aur-repo.sh --check      # preflight only, build nothing
#   ./aur-repo.sh --force PKG  # rebuild one package even if it is current
#   ./aur-repo.sh --clean      # delete the chroot (keeps the built packages)

set -Eeuo pipefail

# Everything lives under one root, and it defaults to $HOME rather than the
# repo: these trees run to tens of gigabytes and must never end up inside a
# git checkout. On the author's machine / has 6.5G free and /home has 102G,
# so a default of "next to the script" would fill the root filesystem.
WORK="${ATI_ISO_WORK:-$HOME/ati-os-build}"
REPO_DIR="$WORK/repo"                 # the [ati-local] repository
CHROOT="$WORK/chroot"                 # devtools clean chroot
SRC_DIR="$WORK/aur-src"               # cloned PKGBUILDs
LOG_DIR="$WORK/logs"
REPO_NAME="ati-local"

# Space the builds actually need: the chroot (~2G), 31 source trees with
# their build artefacts (Rust target/ dirs dominate), and the finished
# packages. Measured rather than rounded -- espanso's target/ alone is
# over a gigabyte, and pacman-static unpacks every dependency's source.
NEED_GB="${NEED_GB:-25}"

# ─── the package set ─────────────────────────────────────────────────
#
# Derived from the module yamls by `comm`-ing the declared package list
# against `pacman -Ssq`, then closing over dependencies via the AUR RPC.
# It is written out literally rather than computed at build time on
# purpose: a build that silently changes its own package set between runs
# is not reproducible, and this list is exactly what the ISO promises.
#
# i3lock-color is NOT declared by any module. It arrives as a dependency
# of betterlockscreen and is AUR-only, so it must be built too -- and it
# must be built BEFORE betterlockscreen, which is why the build loop below
# is iterative rather than a straight for-loop.
AUR_PKGS=(
  ani-cli auto-cpufreq brave-bin dcli-arch-git didyoumean
  dmscripts-git downgrade espanso-x11 eww google-chrome gromit-mpx
  informant light neovim-remote pacman-static papirus-folders paru
  python-pulsectl python-simplenote qtile-extras rofi-pass
  shell-color-scripts-git sweet-gtk-theme-dark timeshift-autosnap
  ttf-amiri ttf-cairo whisper.cpp-git yay-bin yt-x-git
  i3lock-color betterlockscreen
)

# ─── output helpers, matching wizard.sh's voice ──────────────────────
if [[ -t 1 ]]; then
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_R=$'\e[0m'
else
  C_OK=; C_WARN=; C_ERR=; C_DIM=; C_R=
fi
_OK()   { printf '%s  ok %s %s\n'   "$C_OK"   "$C_R" "$*"; }
_WARN() { printf '%swarn %s %s\n'   "$C_WARN" "$C_R" "$*"; }
_ERR()  { printf '%sfail %s %s\n'   "$C_ERR"  "$C_R" "$*" >&2; }
_DIM()  { printf '%s     %s%s\n'    "$C_DIM"  "$*" "$C_R"; }
say()   { printf '\n=== %s ===\n' "$*"; }

# ─── AUR RPC, with retries ───────────────────────────────────────────
#
# The AUR rate-limits, and a single failed query used to abort the whole
# run in preflight -- three hours of work refused because of one blip. It
# is also queried per package during the build, where a silent failure is
# worse than a loud one: build_one falls back to using the package name as
# its git base, which is exactly the empty-clone bug that split packages
# already caused once.
#
# Three attempts with growing backoff, and the caller can tell the
# difference between "the AUR said no such package" and "the AUR did not
# answer".
aur_rpc() {                   # aur_rpc <pkg> -> prints json, or fails
  local pkg="$1" try
  for try in 1 2 3; do
    if curl -sf --max-time 15 \
         "https://aur.archlinux.org/rpc/?v=5&type=info&arg=$pkg"; then
      return 0
    fi
    (( try < 3 )) && sleep $((try * 3))
  done
  return 1
}

aur_field() {                 # aur_field <pkg> <Field> -> prints value
  local json
  json=$(aur_rpc "$1") || return 1
  printf '%s' "$json" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

CHECK_ONLY=0; DO_CLEAN=0; FORCE_PKG=""
while (( $# )); do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --clean) DO_CLEAN=1 ;;
    --force) FORCE_PKG="${2:?--force needs a package name}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) _ERR "unknown argument: $1"; exit 2 ;;
  esac
  shift
done

# ─── preflight ───────────────────────────────────────────────────────
#
# Same principle as vm-test.sh's: refuse up front with the number that
# failed, rather than dying two hours in with a full disk. A build that
# runs out of space at package 27 of 31 has cost more than the check.
preflight() {
  say "preflight"
  local fail=0

  for t in makechrootpkg mkarchroot repo-add git; do
    if command -v "$t" >/dev/null; then
      _OK "$t"
    else
      _ERR "$t not found"
      case "$t" in
        makechrootpkg|mkarchroot) _DIM "install it: sudo pacman -S devtools" ;;
        repo-add)                 _DIM "install it: sudo pacman -S pacman" ;;
      esac
      fail=1
    fi
  done

  mkdir -p "$WORK"
  local avail_gb
  avail_gb=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc '0-9')
  if (( avail_gb >= NEED_GB )); then
    _OK "disk: ${avail_gb}G free at $WORK (need ${NEED_GB}G)"
  else
    _ERR "disk: ${avail_gb}G free at $WORK, need ${NEED_GB}G"
    _DIM "set ATI_ISO_WORK to a roomier filesystem"
    fail=1
  fi

  # A clean chroot is bind-mounted and executed from. On a filesystem
  # mounted nodev or noexec the builds fail in ways that read as compiler
  # errors, so name it now.
  local mnt opts
  mnt=$(df --output=target "$WORK" | tail -1)
  opts=$(findmnt -no OPTIONS "$mnt" 2>/dev/null || echo "")
  if [[ "$opts" == *noexec* || "$opts" == *nodev* ]]; then
    _ERR "$mnt is mounted noexec/nodev — chroot builds cannot run there"
    fail=1
  else
    _OK "$mnt is exec/dev capable"
  fi

  # Probe with `sudo -n true` and nothing else. `sudo -v` looks like the
  # right check and is not: it validates the user's credentials in
  # GENERAL, so on a machine whose NOPASSWD rule is scoped to particular
  # commands -- which is what this repo's passwordless-sudo module
  # writes -- `sudo -n true` succeeds while `sudo -v` demands a password.
  # The first version of this script probed one way and kept the cache
  # warm the other, so preflight reported "ok sudo available" and the run
  # then died on a password prompt with nothing built.
  if sudo -n true 2>/dev/null; then
    SUDO_PASSWORDLESS=1
    _OK "sudo available, passwordless (an unattended run is safe)"
  elif [[ -t 0 ]]; then
    SUDO_PASSWORDLESS=0
    _WARN "sudo needs a password — this run cannot be left unattended"
    _DIM "the credential cache expires mid-build and it will stop and wait"
  else
    _ERR "sudo needs a password and there is no terminal to type it into"
    _DIM "run this in a terminal, or configure NOPASSWD first"
    fail=1
  fi

  if aur_rpc yay-bin >/dev/null; then
    _OK "aur.archlinux.org reachable"
  else
    _ERR "cannot reach the AUR after 3 attempts"
    _DIM "the AUR rate-limits; if this is the only failure, wait and retry"
    fail=1
  fi

  (( fail )) && { _ERR "preflight failed — nothing was built"; exit 1; }
  _OK "preflight clean"
}

# ─── keep sudo alive for the whole build ─────────────────────────────
#
# makechrootpkg needs root for every one of the 31 builds, and the set
# takes two to three hours. sudo's credential cache is fifteen minutes by
# default, so without this the run stops dead at a password prompt
# somewhere around package four -- and if it was started in the background
# it hangs there silently until someone notices.
#
# The refresher is killed on exit, including on error, so it cannot outlive
# the build and leave a machine with a permanently warm sudo cache.
SUDO_PASSWORDLESS=0
SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
  # Nothing to keep alive when sudo never asks; starting a refresher then
  # would just spin a pointless subshell for three hours.
  (( SUDO_PASSWORDLESS )) && return 0
  sudo -v
  ( while true; do sudo -n true 2>/dev/null; sleep 60; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'stop_sudo_keepalive' EXIT INT TERM
}
stop_sudo_keepalive() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}

# ─── chroot ──────────────────────────────────────────────────────────
#
# The chroot's pacman.conf gets [ati-local] appended so that a package can
# depend on one built earlier in the same run -- betterlockscreen needs
# i3lock-color, and without this it would resolve nothing and fail.
#
# SigLevel is Optional TrustAll for this repo. That is deliberate and it is
# not a shortcut: the packages, the database and the pacman reading them
# all live on the same read-only medium (this build host now, the ISO
# later), so a signature would be verifying the medium against itself. It
# is the same trust model archiso already uses for its own airootfs. The
# repo is removed from the installed system's pacman.conf at the end of the
# install, so it never becomes a lasting unsigned source.
setup_chroot() {
  say "clean chroot"
  mkdir -p "$REPO_DIR" "$SRC_DIR" "$LOG_DIR"

  # An empty database has to exist before the chroot can list the repo,
  # otherwise pacman -Sy inside it errors on a missing db.
  [[ -f "$REPO_DIR/$REPO_NAME.db.tar.zst" ]] \
    || repo-add -q "$REPO_DIR/$REPO_NAME.db.tar.zst" >/dev/null 2>&1 || true

  # The base is devtools' STOCK config, not the host's /etc/pacman.conf.
  # That distinction is the whole point of building in a clean chroot and
  # the first version of this script got it wrong: copying the host config
  # brought the host's HookDir with it, so this repo's own
  # 00-preflight.hook fired inside the fresh root and tried to exec
  # /usr/local/bin/pacman-preflight -- which exists on this machine and in
  # no new root anywhere. pacman reported it as
  #
  #   call to execv failed (No such file or directory)
  #   error: failed to commit transaction (failed to run transaction hooks)
  #
  # which names neither the hook nor the missing file. Any host
  # customisation -- hooks, extra repos, a local mirror, IgnorePkg -- would
  # leak the same way and make the built packages depend on this machine.
  #
  # extra.conf carries [core] and [extra] and nothing else. multilib is
  # deliberately absent: it is not enabled on this host and no declared
  # package lives there, so adding it would widen the build surface for
  # nothing.
  local base_conf=/usr/share/devtools/pacman.conf.d/extra.conf
  [[ -r "$base_conf" ]] || { _ERR "missing $base_conf (reinstall devtools)"; exit 1; }

  # Using the stock config is necessary but NOT sufficient, which cost a
  # second failed run to learn. HookDir is not part of extra.conf, so it
  # fell back to its compiled-in default of /etc/pacman.d/hooks -- the
  # HOST's sysadmin hook directory -- and this repo's 00-preflight.hook
  # fired again with exactly the same unhelpful execv error.
  #
  # An explicit HookDir REPLACES that default rather than adding to it
  # (verified: `pacman-conf --config <file> HookDir` answers only what the
  # file names). Pointing it at an empty directory therefore drops the
  # host's hooks. Package-provided hooks under /usr/share/libalpm/hooks are
  # compiled in separately and still run, from inside the new root where
  # they belong -- which is what keeps the chroot's keyring and ldconfig
  # correct.
  local empty_hooks="$WORK/empty-hooks"
  mkdir -p "$empty_hooks"

  local pacconf="$WORK/pacman-chroot.conf"
  cp "$base_conf" "$pacconf"

  # HookDir is an [options] directive and extra.conf ends with [core] and
  # [extra], so this has to be INSERTED after the [options] header, not
  # appended to the file. Appended, it would land inside [extra], where
  # pacman treats it as a repo setting and silently ignores it -- the
  # host's hooks would keep running and the failure would look identical
  # to not having made the change at all.
  sed -i "0,/^\[options\]/s|^\[options\]|[options]\nHookDir = $empty_hooks/|" "$pacconf"

  # A repo section, by contrast, belongs at the end.
  cat >> "$pacconf" <<EOF

[$REPO_NAME]
SigLevel = Optional TrustAll
Server = file://$REPO_DIR
EOF

  if [[ -d "$CHROOT/root" ]]; then
    _OK "chroot exists at $CHROOT"
  else
    # mkarchroot resolves its working directory with `readlink -f`, which
    # returns an EMPTY string when the path's parent does not exist -- and
    # it then reports that as "Please specify a working directory", which
    # reads like the argument was missing rather than that its parent was.
    # So $CHROOT must exist before the call. $CHROOT/root must NOT: the
    # next thing mkarchroot does is die if its target already exists.
    mkdir -p "$CHROOT"
    _DIM "creating $CHROOT (a few minutes, ~2G)"
    sudo mkarchroot -C "$pacconf" "$CHROOT/root" base-devel
    _OK "chroot created"
  fi

  # The chroot's own pacman.conf must know about the repo too -- mkarchroot
  # only used ours to POPULATE it.
  sudo cp "$pacconf" "$CHROOT/root/etc/pacman.conf"
}

# ─── is a package already built and current? ─────────────────────────
# Package files are matched by a GLOB over the compression suffix, never
# by a hardcoded .zst.
#
# A PKGBUILD may override PKGEXT, and pacman-static does exactly that: it
# ships .pkg.tar.xz. With a hardcoded .zst this function never recognised
# it as current, so every single run would have rebuilt the most expensive
# package in the set -- an hour, silently, for nothing -- and build_one
# declared "built but produced no package" for a package sitting right
# there on disk.
PKG_GLOB='*.pkg.tar.@(zst|xz|gz|bz2)'
have_current() {
  local pkg="$1" ver
  ver=$(aur_field "$pkg" Version) || return 1
  [[ -z "$ver" ]] && return 1
  shopt -s extglob
  compgen -G "$REPO_DIR/$pkg-$ver-$PKG_GLOB" >/dev/null
}

# ─── build one package ───────────────────────────────────────────────
build_one() {
  # Two `local`s, not one. Bash expands every word of a `local` command
  # before assigning any of them, so `local pkg="$1" log=".../$pkg.log"`
  # would build the path from the PREVIOUS call's $pkg -- every package
  # after the first would append to the wrong log.
  local pkg="$1"
  local log="$LOG_DIR/$pkg.log"

  # The AUR git repository is named after the package BASE, not the
  # package. For a split package the two differ, and cloning by name
  # succeeds while producing nothing: git says
  #
  #   warning: You appear to have cloned an empty repository.
  #
  # and the build then fails with no PKGBUILD. espanso-x11 is built from
  # base `espanso`, which is exactly how this was found. Resolving the base
  # from the RPC rather than hard-coding the one known case means the next
  # split package works without anyone noticing there was a case to handle.
  #
  # A failure to RESOLVE the base is fatal rather than falling back to the
  # package name. The fallback looks harmless and is not: for a split
  # package it clones an empty repository and the build fails later with a
  # confusing error, having quietly discarded the answer it needed.
  local base
  base=$(aur_field "$pkg" PackageBase) \
    || { _ERR "$pkg: the AUR did not answer — cannot resolve its package base"; return 1; }
  [[ -n "$base" ]] || { _ERR "$pkg: no PackageBase in the AUR response"; return 1; }
  [[ "$base" != "$pkg" ]] && _DIM "  $pkg is built from base '$base'"

  if [[ -d "$SRC_DIR/$base/.git" ]]; then
    git -C "$SRC_DIR/$base" fetch -q origin && git -C "$SRC_DIR/$base" reset -q --hard origin/master
  else
    rm -rf "${SRC_DIR:?}/$base"
    git clone -q "https://aur.archlinux.org/$base.git" "$SRC_DIR/$base"
  fi
  [[ -f "$SRC_DIR/$base/PKGBUILD" ]] || { _ERR "$pkg: no PKGBUILD in $base — see $log"; return 1; }

  # -c cleans the chroot copy before building, -u updates it, -r names the
  # chroot root. -- -s installs missing deps, --noconfirm keeps it silent.
  # Output goes to a per-package log rather than the terminal for the same
  # reason vm-test.sh keeps per-module .err files: when one of 31 builds
  # fails two hours in, the only useful artefact is ITS log, not a merged
  # scrollback with 30 other packages' compiler output in it.
  # Two attempts, with a `git clean` between them.
  #
  # An interrupted run leaves a PARTIAL source tarball behind, and makepkg
  # then tries to RESUME it. GitHub does not support byte ranges, so it
  # answers:
  #
  #   curl: (33) HTTP server does not seem to support byte ranges.
  #   ==> ERROR: Failure while downloading .../v2.1.0.tar.gz
  #
  # and that is permanent -- every subsequent run resumes the same broken
  # file and fails identically. The source cache stays poisoned until
  # someone deletes it by hand, which is a miserable thing to leave in a
  # three-hour build.
  #
  # `git clean -xdf` is exactly the right hammer: the PKGBUILD, .SRCINFO
  # and any patches are TRACKED, while downloaded tarballs and build trees
  # are not, so it removes the poison and keeps the recipe. Retrying only
  # once keeps a genuinely broken package from doubling the build time.
  local attempt built_ok=0
  for attempt in 1 2; do
    if (( attempt == 2 )); then
      _DIM "  retrying $pkg from a clean source tree"
      git -C "$SRC_DIR/$base" clean -xdfq
    fi
    if ( cd "$SRC_DIR/$base" \
         && makechrootpkg -c -u -r "$CHROOT" -- --noconfirm ) >"$log" 2>&1; then
      built_ok=1
      break
    fi
  done
  # An explicit test, not `(( attempt == 2 )) && return 1` inside the loop.
  # That idiom evaluates to false on the first pass, which under `set -e`
  # is a failing last-command in a loop body -- the SC2015 trap this repo
  # already documents three instances of.
  if (( built_ok )); then
    # -debug packages are excluded. makepkg emits one per package with
    # debug symbols and they are enormous -- pacman-static-debug alone is
    # 36 MB against the real package's 16 MB -- while being useless on an
    # install medium. Carrying them would cost hundreds of megabytes of
    # ISO for symbols nobody on a fresh machine will read.
    local built=()
    mapfile -t built < <(find "$SRC_DIR/$base" -maxdepth 1 \
      \( -name '*.pkg.tar.zst' -o -name '*.pkg.tar.xz' \
         -o -name '*.pkg.tar.gz' -o -name '*.pkg.tar.bz2' \) \
      ! -name '*-debug-*')
    (( ${#built[@]} )) || { _ERR "$pkg built but produced no package — see $log"; return 1; }

    # EVERY produced package is added, not just the first. A split base
    # emits several -- building `espanso` yields espanso-x11 AND
    # espanso-wayland -- and adding only built[0] would leave the rest as
    # files in the directory that the database does not list, so pacman
    # would never see them. They cost nothing to carry and the alternative
    # is a repo that silently lacks the package that was asked for.
    local names=()
    local f
    for f in "${built[@]}"; do names+=("$REPO_DIR/$(basename "$f")"); done
    mv "${built[@]}" "$REPO_DIR/"
    repo-add -q -R "$REPO_DIR/$REPO_NAME.db.tar.zst" "${names[@]}" >>"$log" 2>&1
    return 0
  fi
  return 1
}

main() {
  if (( DO_CLEAN )); then
    say "cleaning chroot"
    sudo rm -rf "$CHROOT"
    _OK "chroot removed (built packages in $REPO_DIR kept)"
    exit 0
  fi

  preflight
  (( CHECK_ONLY )) && { _OK "--check only, nothing built"; exit 0; }

  start_sudo_keepalive
  setup_chroot

  # Iterative, not a plain for-loop, because build ORDER matters:
  # betterlockscreen cannot build until i3lock-color is in the repo. Rather
  # than hard-code an order that goes stale the moment a PKGBUILD gains a
  # dependency, each pass builds whatever it can and re-adds the rest to
  # the queue. Progress is the loop condition -- a pass that builds nothing
  # means the remainder is genuinely broken, not merely out of order.
  local queue=("${AUR_PKGS[@]}") done_n=0 total=${#AUR_PKGS[@]}
  local -a failed=()
  local pass=0

  say "building $total AUR packages"
  _DIM "logs: $LOG_DIR    packages: $REPO_DIR"
  _DIM "pacman-static alone is about an hour; the whole set is 2-3"

  while (( ${#queue[@]} )); do
    pass=$((pass + 1))
    local -a next=()
    local progressed=0

    for pkg in "${queue[@]}"; do
      if [[ "$pkg" != "$FORCE_PKG" ]] && have_current "$pkg"; then
        _OK "$pkg (already current)"
        done_n=$((done_n + 1)); progressed=1
        continue
      fi
      printf '     [%2d/%2d] building %s ... ' "$((done_n + 1))" "$total" "$pkg"
      local t0=$SECONDS
      if build_one "$pkg"; then
        printf '%sok%s (%dm%02ds)\n' "$C_OK" "$C_R" $(( (SECONDS-t0)/60 )) $(( (SECONDS-t0)%60 ))
        done_n=$((done_n + 1)); progressed=1
      else
        printf '%sdeferred%s\n' "$C_WARN" "$C_R"
        next+=("$pkg")
      fi
    done

    queue=("${next[@]}")
    if (( ${#queue[@]} && !progressed )); then
      failed=("${queue[@]}")
      break
    fi
  done

  say "result"
  if (( ${#failed[@]} )); then
    _ERR "${#failed[@]} package(s) could not be built after $pass passes:"
    for p in "${failed[@]}"; do
      _DIM "  $p   — tail of its log:"
      tail -5 "$LOG_DIR/$p.log" 2>/dev/null | sed 's/^/       /'
    done
    _DIM "read the full log before assuming the package is at fault; on a"
    _DIM "clean chroot the reported failure is often a missing DECLARED dep"
    exit 1
  fi

  _OK "$done_n/$total built"
  _OK "repository: $REPO_DIR/$REPO_NAME.db.tar.zst"
  du -sh "$REPO_DIR" | awk '{printf "     repo size: %s\n", $1}'
}

# The run log is written HERE rather than by the caller piping into tee.
# That is not a convenience: `./aur-repo.sh | tee log` reports TEE's exit
# status, which is 0 whatever the script did. The first run of this script
# died on a sudo prompt with nothing built and was reported as a success
# by exactly that mistake. `process substitution` keeps the script's own
# status intact while still capturing everything.
mkdir -p "$WORK"
exec > >(tee -a "$WORK/aur-repo-run.log") 2>&1
printf '\n===== run started %s =====\n' "$(date -Is)"
main "$@"
