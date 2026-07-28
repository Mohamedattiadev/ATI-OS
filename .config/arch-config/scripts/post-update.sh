#!/usr/bin/env bash
# dcli post_update hook -- runs after the system upgrade completes.
#
# The pre-update hook can only WARN that a library bump might break AUR
# packages. This one checks whether it actually did, while you are still
# at the keyboard and still remember what changed -- rather than a week
# later when an app fails to launch and the cause is no longer obvious.
#
# The failure mode it catches: a repo library bumps its soname, every
# binary compiled against the old version keeps its files but can no
# longer resolve them at load time. Nothing is missing on disk, so
# `pacman -Qkk` is happy; the program simply refuses to start with
# "cannot open shared object file". Repo packages are rebuilt by their
# maintainers, so it is almost always AUR packages that are left behind.

set -uo pipefail

y=$'\033[33m'; g=$'\033[32m'; r=$'\033[31m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s[post-update]%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '%s[post-update]%s %s✓%s %s\n' "$d" "$o" "$g" "$o" "$*"; }
warn() { printf '%s[post-update]%s %s!%s %s\n' "$d" "$o" "$y" "$o" "$*"; }

# ---- 1. Broken dynamic links in AUR packages ---------------------------
# Scanning every binary on the system takes minutes; AUR packages are
# where this actually bites, and there are far fewer of them.
say "checking AUR packages for broken library links…"
broken_pkgs=()
while read -r pkg; do
  [[ -n "$pkg" ]] || continue
  # Only ELF files in bin/lib dirs -- skip data, docs, icons.
  while read -r f; do
    [[ -f "$f" && -x "$f" ]] || continue
    if ldd "$f" 2>/dev/null | grep -q "not found"; then
      broken_pkgs+=("$pkg")
      break
    fi
  done < <(pacman -Qlq "$pkg" 2>/dev/null | grep -E '/(bin|lib|lib64)/[^/]+$' | head -40)
done < <(pacman -Qmq 2>/dev/null)

if (( ${#broken_pkgs[@]} )); then
  warn "${#broken_pkgs[@]} AUR package(s) have unresolved libraries:"
  printf '              %s\n' "${broken_pkgs[@]}"
  printf '\n              These will fail to start. Rebuild them:\n'
  printf '                yay -S --rebuild %s\n\n' "${broken_pkgs[*]}"
else
  ok "no broken library links in AUR packages"
fi

# ---- 2. New .pacnew configs from this upgrade --------------------------
mapfile -t pacnew < <(find /etc -name '*.pacnew' 2>/dev/null | head -20)
if (( ${#pacnew[@]} )); then
  warn "${#pacnew[@]} new .pacnew config(s) -- merge with: sudo pacdiff"
  printf '              %s\n' "${pacnew[@]:0:6}"
else
  ok "no new .pacnew configs"
fi

# ---- 3. Reboot needed? -------------------------------------------------
# Comparing the running kernel against the installed one is the reliable
# signal: a kernel upgrade leaves the old modules directory gone, so
# loading any not-yet-loaded module (USB, filesystem, …) fails until
# reboot -- a class of "random" breakage that looks unrelated.
running=$(uname -r)
installed=$(pacman -Q linux 2>/dev/null | awk '{print $2}' | sed 's/\.arch/-arch/')
if [[ -n "$installed" ]] && [[ "$running" != "$installed"* ]]; then
  warn "kernel changed (running $running, installed $installed) -- REBOOT."
  printf '              Until you do, modules that are not already loaded\n'
  printf '              cannot be loaded at all.\n'
else
  ok "running kernel matches installed"
fi

# ---- 4. Services still using deleted libraries -------------------------
# After a library upgrade a long-running daemon keeps the OLD file open
# via its inode. It works until restarted, then may fail -- typically at
# the least convenient moment, i.e. next boot.
if command -v checkservices >/dev/null 2>&1; then
  say "services referencing replaced libraries:"
  checkservices 2>/dev/null | head -12 | sed 's/^/              /'
fi

printf '\n'
say "post-update checks complete"
exit 0
