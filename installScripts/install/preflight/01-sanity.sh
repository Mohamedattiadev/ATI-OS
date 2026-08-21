# install/preflight/01-sanity.sh — the "sanity" picker module: a second,
# lighter Arch/Wayland/dotfiles-dir check runnable on its own via
# --only=sanity, distinct from the always-run 00-checks.sh gate. Extracted
# verbatim from wizard.sh (no behavior change).

step_sanity() {
  [[ -f /etc/arch-release ]] || { _ERR "Not Arch Linux"; return 1; }
  [[ "${XDG_SESSION_TYPE:-}" != wayland ]] || { _ERR "Wayland not supported"; return 1; }
  # The ~ is prose in a message shown to a human, not a path being expanded.
  # shellcheck disable=SC2088
  [[ -d "$DOTFILES_DIR" ]] || { _ERR "~/.dotfiles missing"; return 1; }
  _OK "System checks passed"
}

# No-op uninstalls (installer step is safe to leave in place, or
# reversing it would harm the user's system).
uninstall_sanity()            { :; }
