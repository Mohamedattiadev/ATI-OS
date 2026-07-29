#!/usr/bin/env bash
# dcli pre_update hook -- runs before `dcli update` touches anything.
#
# This exists because the safety checks are worthless if they live in a
# script you have to remember to type. `dcli update` is the command
# actually used day to day, so the gate belongs in its path.
#
# It REFUSES; it does not repair. A non-zero exit here aborts the update
# before any package is downloaded or unpacked, which is the only moment
# when stopping is free. Once pacman is mid-transaction, nothing can make
# a half-written filesystem whole again.
#
# The failure this prevents: a full upgrade downloads into
# /var/cache/pacman/pkg and unpacks into /usr, needing room for both at
# once. If / fills part-way through, a package's old files are already
# deleted and the new ones were never written -- libraries vanish and the
# system stops booting. That is what cost a full reinstall here.

set -uo pipefail

MIN_FREE_GB="${DCLI_MIN_FREE_GB:-6}"
fail=0

y=$'\033[33m'; r=$'\033[31m'; g=$'\033[32m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s[pre-update]%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '%s[pre-update]%s %s✓%s %s\n' "$d" "$o" "$g" "$o" "$*"; }
warn() { printf '%s[pre-update]%s %s!%s %s\n' "$d" "$o" "$y" "$o" "$*"; }
bad()  { printf '%s[pre-update]%s %s✖%s %s\n' "$d" "$o" "$r" "$o" "$*"; fail=1; }

# ---- 1. Free space on / ------------------------------------------------
root_free=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -z "$root_free" ]]; then
  warn "could not read free space on / -- skipping space gate"
elif (( root_free < MIN_FREE_GB )); then
  bad "only ${root_free}G free on / (need ${MIN_FREE_GB}G)"
  printf '\n'
  du -xhd1 / 2>/dev/null | sort -rh | head -5 | sed 's/^/            /'
  printf '\n            Reclaim:  sudo paccache -rk1  ·  journalctl --vacuum-size=50M\n\n'
else
  ok "${root_free}G free on / (need ${MIN_FREE_GB}G)"
fi

# ---- 2. Snapshots must not live on the disk they protect ---------------
# A snapshot on the same filesystem as its target is not a backup: it
# consumes the headroom the upgrade needs, and it dies with the
# filesystem it was meant to restore.
if command -v timeshift >/dev/null 2>&1; then
  ts_dir=""
  for c in /timeshift /home/timeshift; do [[ -d "$c" ]] && ts_dir="$c" && break; done
  if [[ -n "$ts_dir" ]]; then
    ts_dev=$(findmnt -no SOURCE --target "$ts_dir" 2>/dev/null)
    root_dev=$(findmnt -no SOURCE --target / 2>/dev/null)
    if [[ -n "$ts_dev" && "$ts_dev" == "$root_dev" ]]; then
      bad "timeshift snapshots are on $ts_dev, which IS your root filesystem"
      printf '            They eat the space this upgrade needs, and they die\n'
      printf '            with / if it breaks. Move them: Timeshift > Settings\n'
      printf '            > Location, pick a different partition.\n\n'
    else
      ok "snapshots on $ts_dev, separate from root ($root_dev)"
    fi
  fi
fi

# ---- 3. Arch news ------------------------------------------------------
# The posts that say "manual intervention required" are exactly the ones
# that break systems when skipped. Advisory only -- never block on it,
# since informant may simply not be installed yet.
if command -v informant >/dev/null 2>&1; then
  informant check >/dev/null 2>&1 \
    && ok "no unread Arch news" \
    || warn "unread Arch news -- run 'informant read' before continuing"
fi

# ---- 4. Existing dependency breakage -----------------------------------
# Upgrading on top of an already-inconsistent database turns one problem
# into two, and the resulting mess is far harder to attribute. Fix first,
# then upgrade.
if command -v pacman >/dev/null 2>&1; then
  if pacman -Dk >/dev/null 2>&1; then
    ok "package database is consistent"
  else
    bad "package database already has dependency errors:"
    pacman -Dk 2>&1 | grep -v "^$" | head -8 | sed 's/^/            /'
    printf '            Resolve these BEFORE upgrading.\n\n'
  fi
fi

# ---- 5. Unmerged .pacnew configs ---------------------------------------
# A .pacnew means a previous upgrade shipped a new default config that was
# never merged. They accumulate silently, and the breakage shows up much
# later as a service that will not start with a config you did not realise
# was stale.
mapfile -t pacnew < <(find /etc -name '*.pacnew' 2>/dev/null | head -20)
if (( ${#pacnew[@]} )); then
  warn "${#pacnew[@]} unmerged .pacnew config(s):"
  printf '            %s\n' "${pacnew[@]:0:6}"
  printf '            Merge with pacdiff (pacman-contrib) before upgrading.\n'
else
  ok "no unmerged .pacnew configs"
fi

# ---- 6. What is actually coming ----------------------------------------
# checkupdates uses a temporary database, so it can preview an upgrade
# WITHOUT the -Sy that would leave the real DB refreshed and the system
# one bad command away from a partial upgrade.
if command -v checkupdates >/dev/null 2>&1; then
  mapfile -t pending < <(timeout 90 checkupdates 2>/dev/null)
  if (( ${#pending[@]} )); then
    say "${#pending[@]} package(s) pending"
    # Packages whose breakage takes the whole system down rather than one
    # app. Worth knowing before you start, not after.
    risky=$(printf '%s\n' "${pending[@]}" \
      | grep -iE '^(linux|linux-lts|linux-firmware|glibc|systemd|mesa|nvidia|xorg-server|gcc-libs|openssl) ' || true)
    if [[ -n "$risky" ]]; then
      warn "high-impact packages in this batch -- reboot after, and do not"
      printf '            interrupt the transaction:\n'
      printf '%s\n' "$risky" | sed 's/^/              /'
    fi
    # A soname bump in a core library silently invalidates every AUR
    # package compiled against the old version: they keep their files but
    # fail at load time with "cannot open shared object file". Repo
    # packages get rebuilt by the maintainers; AUR ones are yours.
    aur_count=$(pacman -Qmq 2>/dev/null | wc -l)
    libbump=$(printf '%s\n' "${pending[@]}" \
      | grep -iE '^(icu|boost|ffmpeg|openssl|protobuf|abseil-cpp|libxml2|imagemagick|qt6-base|llvm) ' || true)
    if [[ -n "$libbump" && "$aur_count" -gt 0 ]]; then
      warn "library bump + $aur_count AUR package(s) installed."
      printf '            AUR builds linked against the old soname will break at\n'
      printf '            load time. Rebuild after with: yay -S --rebuildall\n'
      printf '            or reinstall the affected ones individually.\n'
    fi
  else
    ok "nothing to update"
  fi
fi

# ---- 7. Rollback material ---------------------------------------------
# `downgrade` restores a single bad package from the pacman cache. An
# empty cache means the only recovery left is a full snapshot restore.
cached=$(find /var/cache/pacman/pkg -maxdepth 1 -name '*.pkg.tar*' 2>/dev/null | wc -l)
(( cached < 50 )) \
  && warn "pacman cache has only $cached packages -- little to 'downgrade' back to" \
  || ok "pacman cache has $cached packages for rollback"

printf '\n'
if (( fail )); then
  printf '%s[pre-update] ABORTING -- nothing was changed.%s\n\n' "$r" "$o"
  exit 1
fi
say "checks passed, proceeding"
exit 0
