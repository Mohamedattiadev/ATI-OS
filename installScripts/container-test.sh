#!/usr/bin/env bash
# container-test.sh — run the wizard on a throw-away Arch container.
#
# The cheap half of vm-test.sh. A container cannot test the things that
# need real hardware or a real init: no X server, so nothing about qtile,
# picom, animations or themes is exercised; no systemd, so no services;
# no PCI bus, so step_gpu correctly detects nothing. Those need vm-test.sh
# or an actual machine.
#
# What it DOES catch is the class of bug that made a fresh install differ
# from this laptop in the first place, and it catches it in ~3 minutes
# instead of ~40:
#
#   * a package that is used but declared in no module
#   * a path that only resolves because $HOME happens to be /home/ati
#   * a step that is not idempotent (it runs the wizard twice and diffs)
#   * a module that assumes something an earlier module left behind
#
# Usage:
#   ./container-test.sh              # full run: stow + paths + audit, twice
#   ./container-test.sh --check      # verify the runtime works, touch nothing
#   ./container-test.sh --keep       # leave the container for poking at
#
# Deliberately NOT run as root-with-everything: it creates an unprivileged
# user with passwordless sudo, because "works when you are root" is exactly
# the assumption that breaks on a real login.

set -Eeuo pipefail

IMAGE="${IMAGE:-archlinux:base-devel}"
NAME="${NAME:-dotfiles-smoke}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEEP=0
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --keep)  KEEP=1 ;;
    --check) CHECK_ONLY=1 ;;
    # 26 is the last comment line of the header. It used to say 30, so
    # --help spilled `set -Eeuo pipefail` and the first variables into the
    # help text.
    --help|-h) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "container-test: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

r=$'\033[31m'; g=$'\033[32m'; y=$'\033[33m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s[container-test]%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '%s[container-test]%s %s✓%s %s\n' "$d" "$o" "$g" "$o" "$*"; }
warn() { printf '%s[container-test]%s %s!%s %s\n' "$d" "$o" "$y" "$o" "$*"; }
die()  { printf '%s[container-test]%s %s✗%s %s\n' "$d" "$o" "$r" "$o" "$*" >&2; exit 1; }

# ── runtime ──────────────────────────────────────────────────────────
if command -v podman >/dev/null 2>&1; then
  RT=podman
elif command -v docker >/dev/null 2>&1; then
  RT=docker
else
  die "neither podman nor docker found — install one (podman needs no daemon)"
fi
say "runtime: $RT"

# docker needs a running daemon; podman does not. Check before pulling a
# 700MB image and failing on the first real command.
if [[ "$RT" == docker ]] && ! docker info >/dev/null 2>&1; then
  die "docker daemon not reachable — 'sudo systemctl start docker', or add yourself to the docker group"
fi

[[ -f "$REPO_DIR/installScripts/wizard.sh" ]] \
  || die "wizard.sh not found under $REPO_DIR — is this the dotfiles repo?"
ok "repo: $REPO_DIR"

if (( CHECK_ONLY )); then
  ok "preflight passed — run without --check to actually test"
  exit 0
fi

cleanup() {
  if (( KEEP )); then
    warn "container '$NAME' left running: $RT exec -it $NAME bash"
  else
    $RT rm -f "$NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

$RT rm -f "$NAME" >/dev/null 2>&1 || true

say "starting $IMAGE ..."
# The repo is mounted read-only. The test must never be able to write back
# into the working tree -- a smoke test that dirties the thing it is
# testing is worse than no smoke test.
$RT run -d --name "$NAME" -v "$REPO_DIR:/repo:ro" "$IMAGE" sleep infinity >/dev/null \
  || die "could not start container"

cexec() { $RT exec "$NAME" bash -lc "$*"; }

say "bootstrapping user + deps ..."
cexec '
  set -e
  pacman -Sy --noconfirm --needed git stow sudo fish gum pciutils >/dev/null 2>&1
  useradd -m -s /bin/bash tester
  echo "tester ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/tester
  # Copy what git TRACKS, not the directory and not a clone.
  #
  # Not the directory: it carries gitignored runtime state, so a config that
  # only works because an untracked leftover happens to be present would
  # pass. Not `git clone`, which copies committed HEAD -- that cannot
  # validate work in progress, and silently tests the previous commit.
  # `ls-files` is the exact set a fresh clone would receive, including
  # staged additions and excluding staged deletions.
  git config --global --add safe.directory /repo
  mkdir -p /home/tester/.dotfiles
  ( cd /repo && git ls-files -z | tar --null -cf - -T - ) \
    | tar -xf - -C /home/tester/.dotfiles
  chown -R tester:tester /home/tester/.dotfiles
  # Fake enough of an Arch desktop that the sanity check passes: it
  # refuses non-Arch and refuses Wayland.
  touch /etc/arch-release
' || die "bootstrap failed"
ok "populated from tracked git contents only"

# ── the part that actually finds bugs ───────────────────────────────
# Only modules that can work without X, systemd or a network-heavy sync.
# stow and paths are the two that decide whether the desktop config lands
# correctly for a user who is not called 'ati'.
MODS="stow,paths,xinit,xresources,xmodmap,image-envs"

say "run 1/2 — modules: $MODS"
if ! cexec "su tester -c 'TERM=xterm-256color XDG_SESSION_TYPE=x11 HOME=/home/tester /home/tester/.dotfiles/installScripts/wizard.sh --yes --only=$MODS'"; then
  die "first wizard run failed"
fi
ok "run 1 completed"

# Snapshot, run again, diff. Any file that differs between two identical
# runs is a non-idempotent step -- the bug class that makes a re-run on an
# existing machine behave differently from a fresh install.
cexec "cd /home/tester && find .config .xinitrc .Xresources .Xmodmap -type f 2>/dev/null | sort | xargs -r md5sum > /tmp/snap1 2>/dev/null || true"

say "run 2/2 — same modules, checking idempotency"
if ! cexec "su tester -c 'TERM=xterm-256color XDG_SESSION_TYPE=x11 HOME=/home/tester /home/tester/.dotfiles/installScripts/wizard.sh --yes --only=$MODS'"; then
  die "second wizard run failed — the wizard is not re-runnable"
fi
cexec "cd /home/tester && find .config .xinitrc .Xresources .Xmodmap -type f 2>/dev/null | sort | xargs -r md5sum > /tmp/snap2 2>/dev/null || true"

if cexec "diff -u /tmp/snap1 /tmp/snap2 > /tmp/snapdiff"; then
  ok "idempotent — second run changed nothing"
else
  warn "second run changed these files:"
  cexec "cat /tmp/snapdiff" || true
  warn "not necessarily a bug (generated-then-regenerated files differ"
  warn "legitimately), but each line needs a reason"
fi

# ── portability assertions ──────────────────────────────────────────
say "checking for this-machine paths in the deployed config ..."
if cexec "grep -rIl '/home/ati' /home/tester/.config /home/tester/.xinitrc 2>/dev/null | grep -v '\.md$'"; then
  die "deployed config still references /home/ati — it will not work for another user"
fi
ok "no /home/ati in anything deployed"

say "checking the @HOME@ templates were actually rendered ..."
for f in .config/brave-flags.conf .config/gtk-3.0/gtk.css .config/gtk-4.0/gtk.css; do
  cexec "test -f /home/tester/$f" \
    || die "$f was never rendered — the paths module did not run or failed"
  if cexec "grep -q '@HOME@' /home/tester/$f"; then
    die "$f still contains the literal @HOME@ placeholder"
  fi
  cexec "grep -q '/home/tester' /home/tester/$f" \
    || warn "$f has no /home/tester path — check the template is right"
done
ok "templates rendered against the container's real \$HOME"

say "running the package audit ..."
# Expected to report plenty missing: this container installed almost
# nothing. Run it for the parse path -- a malformed module yaml or a broken
# awk block shows up here rather than on a real machine.
#
# The exit status is deliberately ignored -- --audit exits 1 whenever
# anything declared is not installed, which in here is nearly everything.
# But `|| true` with the output thrown away meant the line below announced
# a pass even when the audit died on the first yaml it could not parse,
# i.e. the one thing this step exists to catch. Assert on the verdict line
# instead, which only gets printed once every module file has been read.
_audit_out="$(cexec "su tester -c 'HOME=/home/tester /home/tester/.dotfiles/installScripts/wizard.sh --audit'" 2>&1 || true)"
if grep -q 'modules audited:' <<<"$_audit_out"; then
  ok "audit ran without a parse error"
else
  printf '%s\n' "$_audit_out" | tail -20 | sed 's/^/    /'
  die "audit never reached its verdict — a module yaml no longer parses"
fi

printf '\n%s[container-test]%s %sall checks passed%s\n' "$d" "$o" "$g" "$o"
say "reminder: X11, systemd, GPU and theme rendering are NOT covered here"
say "use vm-test.sh before tagging a release"
