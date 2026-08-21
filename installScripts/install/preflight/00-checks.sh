# install/preflight/00-checks.sh — the fail-fast readiness gate wizard.sh
# runs before the module picker. Extracted verbatim from wizard.sh's
# preflight() (no behavior change) as the first phase-directory step of
# splitting the installer, mirroring Omarchy's install/preflight/.
#
# Only defines preflight() here; wizard.sh still calls it itself, at the
# same point in main() as before — this file changes where the function is
# defined, not when it runs.

preflight() {
  _BOX_HEADER "preflight checks"
  local fatal=0
  _check() {
    local msg="$1" test_expr="$2" hint="$3"
    if eval "$test_expr" >/dev/null 2>&1; then _OK "  ✔ $msg"
    else _ERR "  ✖ $msg"; [[ -n "$hint" ]] && _DIM "      → $hint"; fatal=1
    fi
  }
  _check "Arch Linux"                  "[[ -f /etc/arch-release ]]"                "not Arch — this dotfile stack targets Arch only"
  _check "not running as root"         "[[ $(id -u) -ne 0 ]]"                      "run as your normal user, sudo prompts on demand"
  _check "sudo available"              "command -v sudo >/dev/null"                "install sudo: pacman -S sudo (as root)"
  _check "X11 session (not Wayland)"   "[[ '${XDG_SESSION_TYPE:-}' != 'wayland' ]]" "boot into TTY, not a Wayland session"
  _check "HOME writable"               "[[ -w $HOME ]]"                            "fix HOME permissions"
  _check "dotfiles clone at $DOTFILES_DIR" "[[ -d $DOTFILES_DIR ]]"                "git clone the repo to $DOTFILES_DIR"
  _check "internet reachable"          "curl -fsS --max-time 5 https://archlinux.org >/dev/null" "network down or firewall blocks HTTPS"
  # Scale the requirement to what was actually asked for. The 10 GB figure
  # is the fast rebuild trees + wallpapers + a full dcli sync;
  # `--only=stow,paths` downloads none of that, and demanding 10 GB for it
  # blocked the container smoke test and any config-only re-run on a full
  # disk. Refusing for a reason that does not apply to this run is just a
  # false negative, and false negatives are how safety checks get bypassed.
  #
  # voxtype is NOT in this list: its model download is ~150MB, well inside
  # the default 1GB budget below -- whisper/whisper-fast used to be here
  # for the old ~630MB of models plus whisper.cpp-git's multi-GB AUR build
  # tree, neither of which voxtype-bin (a prebuilt package) has.
  local _need_gb=1 _heavy _heavy_sel=0
  for _heavy in dcli-sync dcli-sync-extra piper wallpapers candy-icons speed; do
    if [[ -n "$ONLY_LIST" ]]; then
      _id_in_csv "$ONLY_LIST" "$_heavy" && _heavy_sel=1
    elif [[ -n "$SKIP_LIST" ]]; then
      _id_in_csv "$SKIP_LIST" "$_heavy" || _heavy_sel=1
    else
      _heavy_sel=1
    fi
  done
  (( _heavy_sel )) && _need_gb=10
  _check "disk free > ${_need_gb} GB on \$HOME" "[[ $(df -Pk "$HOME" | awk 'NR==2{print $4}') -gt $((_need_gb * 1048576)) ]]" "this run needs ~${_need_gb}GB (10GB covers piper 60MB + dcli pkgs + wallpapers; 1GB when none of those are selected — voxtype's ~150MB model always fits the 1GB floor)"
  _check "RAM ≥ 2 GB"                  "[[ $(awk '/MemTotal/{print $2}' /proc/meminfo) -gt 2000000 ]]" "wizard pulls 500MB+ concurrently — <2GB risks OOM/freeze"
  # Not run through _check: _check swallows stdout AND stdin. The swallowed
  # stdout hid the "pacman is running — waiting up to 60s" line, so a
  # legitimate wait was indistinguishable from a frozen wizard; the swallowed
  # stdin left the interactive "remove the stale lock?" confirm blocking on a
  # prompt that had been redirected out of existence.
  if _pacman_lock_check; then
    _OK "  ✔ pacman db lock clear"
  else
    _ERR "  ✖ pacman db lock"; _DIM "      → another pacman may be running"; fatal=1
  fi
  if (( fatal )); then
    echo
    _ERR "Preflight failed. Fix the above and re-run."
    exit 1
  fi
  echo
  _OK "All preflight checks passed."
  sleep 1
}
