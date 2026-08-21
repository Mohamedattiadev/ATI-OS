# install/lib/common.sh — shared globals, traps, and low-level helpers for
# wizard.sh. Extracted verbatim from the top of wizard.sh (no behavior
# change) as the first step of splitting the installer into phase
# directories, mirroring how Omarchy structures install/.
#
# Sourced as: source ".../install/lib/common.sh" "$@" — bash restores the
# caller's positional parameters once sourcing completes, so the arg-parsing
# loop below sees wizard.sh's original $@ without wizard.sh needing to pass
# anything explicitly afterward.

# ─── SIGNAL / EXIT TRAPS ─────────────────────────────────────────────
# Catch Ctrl-C anywhere, print a friendly bye card instead of a raw
# trace. Cleanup pid-file style artifacts.
_TRAP_ACTIVE=1
_on_interrupt() {
  (( _TRAP_ACTIVE )) || return
  _TRAP_ACTIVE=0
  echo
  gum style --border thick --border-foreground '#ff6c6b' \
    --padding "1 3" --align center \
    "$(gum style --bold --foreground '#ff6c6b' 'Interrupted')" \
    "" \
    "Wizard aborted by user (Ctrl-C)." \
    "State may be partial. Re-run — steps are idempotent."
  exit 130
}
trap _on_interrupt INT TERM

_on_err() {
  local rc=$?
  gum style --foreground '#ff6c6b' "wizard.sh: internal bash error (rc=$rc) at line $1"
}
trap '_on_err $LINENO' ERR

# ─── SUDO KEEP-ALIVE ─────────────────────────────────────────────────
# A long run (AUR builds especially — easily 30-60+ min) can outlast
# sudo's credential cache (~15 min default). When that happens mid-way
# through an AUR build, the final `pacman -U` install-after-build step
# fails silently: makepkg reports "Finished making", but the package
# never actually lands on disk. Priming once + refreshing in the
# background for the whole run prevents that class of silent failure
# outright, instead of chasing it step by step.
_SUDO_KEEPALIVE_PID=""
_start_sudo_keepalive() {
  (( DRY_RUN )) && return
  sudo -v 2>/dev/null || return  # no tty to prompt on — nothing to keep alive
  ( while true; do sleep 60; sudo -n -v 2>/dev/null || exit; done ) &
  _SUDO_KEEPALIVE_PID=$!
  disown
}
_stop_sudo_keepalive() {
  [[ -n "$_SUDO_KEEPALIVE_PID" ]] && kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null
  return 0
}
trap _stop_sudo_keepalive EXIT

# Per-module logs are written to /tmp/wizard-<id>.{log,err} by _run_module.
# There used to be a WIZ_RUNLOG="$XDG_STATE_HOME/wizard/run-<ts>.log" here
# that nothing ever wrote to -- it only had the side effect of creating an
# empty ~/.local/state/wizard directory on every run. Removed rather than
# wired up: a whole-run log would duplicate the per-module ones.

# ─── CONFIG ──────────────────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
ONLY_LIST=""
SKIP_LIST=""
UNINSTALL=0
SHOW_HELP=0
AUDIT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y)     ASSUME_YES=1 ;;
    --only=*)     ONLY_LIST="${arg#*=}" ;;
    --skip=*)     SKIP_LIST="${arg#*=}" ;;
    --uninstall)  UNINSTALL=1 ;;
    --audit)      AUDIT=1 ;;
    # Deferred: the module id list is printed FROM MOD_ORDER, which is not
    # defined yet at argument-parse time. It used to be a hand-maintained
    # copy here and drifted -- dark-mode and browser-memory existed as real
    # modules for weeks while --help denied they were valid --only targets.
    --help|-h)    SHOW_HELP=1 ;;
    # These take a value with '=' and are silently value-less otherwise.
    # `--only boot-fallback` used to leave ONLY_LIST empty and drop the id
    # into the ignored-argument bucket below -- i.e. it ran the FULL
    # install, live, instead of the one module you asked for. On a wizard
    # whose second step is `pacman -Syu`, that is not a typo you get to
    # make twice.
    --only|--skip)
      echo "wizard: $arg takes its value with '=' — try ${arg}=id1,id2" >&2
      exit 2 ;;
    *)
      echo "wizard: unknown argument '$arg' (see --help)" >&2
      exit 2 ;;
  esac
done

_id_in_csv() { [[ ",$1," == *",$2,"* ]]; }

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
# (No INSTALL_SH here any more. It dated from when the wizard shelled out to
# install.sh; the dependency now runs the other way and it was never read.)

# ─── run() — the DRY-RUN switch ──────────────────────────────────────
# Any side-effecting shell command must go through here.
run() {
  if (( DRY_RUN )); then
    _DIM "  [dry] $*"
  else
    # eval is the point, not an accident: callers pass a command *string*
    # containing shell syntax -- pipes, &&, redirections, here-docs. Running
    # "$@" directly would look for a binary literally named
    # `sudo tee /etc/... > /dev/null && sudo chmod ...`.
    # shellcheck disable=SC2294  # args are shell source, deliberately
    eval "$@"
  fi
}

# Read-only privileged probes -- `sudo test -e`, `sudo bootctl --print-esp-path`
# and friends. A --dry-run is supposed to be free: it changes nothing and it
# should need nothing. These probes were plain `sudo`, so previewing an install
# on a machine with no cached credentials stopped dead on a password prompt for
# a run that was never going to write anything. Under --dry-run they degrade to
# non-interactive sudo and simply report "unknown", which at worst makes the
# preview show a skip.
sudo_probe() {
  if (( DRY_RUN )); then sudo -n "$@" 2>/dev/null; else sudo "$@"; fi
}

# retry_net <max> <sleep> -- <cmd...>  → retry on non-zero exit.
# Wraps network-heavy actions (pacman, git clone, curl).
retry_net() {
  local max="${1:-3}" delay="${2:-3}" attempt=0
  shift 2
  while :; do
    attempt=$((attempt+1))
    if "$@"; then return 0; fi
    (( attempt >= max )) && return 1
    _DIM "  ↻ retry $attempt/$max after ${delay}s: $*"
    sleep "$delay"
  done
}
