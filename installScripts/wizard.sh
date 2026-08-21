#!/usr/bin/env bash
# wizard.sh — premium TUI installer for Ati Dotfiles.
#
# This is the single source of truth for installing these dotfiles.
# install.sh is a thin wrapper that calls `wizard.sh --yes`, kept so
# `./install.sh` keeps working; it holds no install logic of its own.
# Colors tint from ~/.cache/wal/colors.json when available so the
# wizard matches the current wallpaper palette.
#
# Usage:
#   ./wizard.sh              full run
#   ./wizard.sh --dry-run    preview every command, touch nothing
#   ./wizard.sh --yes        skip module picker, install all
#
# Bootstraps `gum` via pacman if missing.

set -Eeuo pipefail

# Traps, sudo keep-alive, arg-parsing (DRY_RUN/ASSUME_YES/ONLY_LIST/
# SKIP_LIST/UNINSTALL/SHOW_HELP/AUDIT), DOTFILES_DIR, run()/sudo_probe()/
# retry_net() all live in install/lib/common.sh now — moved verbatim as the
# first step of splitting the installer into phase directories. Passing
# "$@" lets the arg-parsing loop in common.sh see wizard.sh's real
# positional parameters; bash restores them here once sourcing completes.
source "$(dirname "${BASH_SOURCE[0]}")/install/lib/common.sh" "$@"

# ─── BOOTSTRAP GUM ───────────────────────────────────────────────────
if ! command -v gum >/dev/null; then
  echo "Bootstrapping wizard dep 'gum'…"
  if ! sudo pacman -S --needed --noconfirm gum >/dev/null 2>&1; then
    echo "Failed to install gum. Install manually: sudo pacman -S gum" >&2
    exit 1
  fi
fi

# ─── PALETTE — Doom Emacs doom-one ───────────────────────────────────
# Full doom-one accent palette. ACCENT is magenta so headers, chips,
# borders pop violet/blue instead of the muted-green feel. Cyan for
# info emphasis, blue for hyperlinks/keys, green reserved for ✓ ok.
ACCENT='#c678dd'   # doom magenta — primary brand
INFO='#46d9ff'     # doom cyan
BLUE='#51afef'     # doom blue
VIOLET='#a9a1e1'   # doom violet — badges accent
TEAL='#4db5bd'     # doom teal
OK_C='#98be65'     # doom green — reserved for ✓
URGENT='#ff6c6b'   # doom red
ORANGE='#da8548'   # doom orange
WARN_C='#ecbe7b'   # doom yellow
MUTED='#5b6268'
FG='#bbc2cf'
# Precomputed truecolor escape for the live spinner line — avoids
# spawning `gum style` on every poll tick (would visibly lag the spin).
MUTED_ANSI=$(printf '\033[38;2;%d;%d;%dm' "0x5b" "0x62" "0x68")
BG='#282c34'

# Gum uses 256-color / hex; passing hex directly is supported.
_H1()   { gum style --bold --foreground "$ACCENT" "$@"; }
_H2()   { gum style --bold --foreground "$INFO"   "$@"; }
_INFO() { gum style --foreground "$FG"     "$@"; }
_DIM()  { gum style --foreground "$MUTED"  "$@"; }
_OK()   { gum style --foreground "$OK_C" "$@"; }
_WARN() { gum style --foreground '#e5c07b' "$@"; }
_ERR()  { gum style --foreground "$URGENT" "$@"; }

_LOGO=$'\n     █████╗ ████████╗██╗\n    ██╔══██╗╚══██╔══╝██║\n    ███████║   ██║   ██║\n    ██╔══██║   ██║   ██║\n    ██║  ██║   ██║   ██║\n    ╚═╝  ╚═╝   ╚═╝   ╚═╝\n           d o t f i l e s\n'

_BOX_HEADER() {
  # `clear` exits non-zero when TERM is unset or unknown -- which under
  # `set -e` plus the ERR trap aborted the whole install. That happens in a
  # container, over a bare ssh exec, and from a CI runner: every
  # non-interactive context where you would want an unattended run most.
  clear 2>/dev/null || true
  gum style --align center --foreground "$ACCENT" "$_LOGO"
  gum style --align center --foreground "$MUTED" \
    "Arch · X11 · Qtile · wal-themed"
  echo
  gum style --border thick --align center \
    --border-foreground "$ACCENT" --padding "0 4" --margin "0 0 1 0" \
    "$1"
}

# Colored group badge — pill with fg=bg bg=group-color. Palette biased
# toward doom's blue/magenta/cyan/violet family.
_BADGE() {
  local g="$1" c
  case "$g" in
    System)   c="$BLUE" ;;
    Dotfiles) c="$VIOLET" ;;
    Themes)   c="$ACCENT" ;;   # magenta
    Browsers) c="$INFO" ;;     # cyan
    Apps)     c="$TEAL" ;;
    Media)    c="$ORANGE" ;;
    *)        c="$MUTED" ;;
  esac
  gum style --foreground "$BG" --background "$c" --padding "0 1" --bold "$g"
}

# Numbered step chip: "[03/26]" — magenta background per brand.
_CHIP() {
  local n="$1" total="$2"
  gum style --foreground "$BG" --background "$ACCENT" --bold --padding "0 1" \
    "$(printf '%02d/%02d' "$n" "$total")"
}

# Progress bar via unicode blocks.
_PROGRESS() {
  local cur="$1" total="$2" width=40
  local pct=$(( cur * 100 / total ))
  local filled=$(( cur * width / total ))
  local bar
  bar="$(printf '█%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $((width - filled))))"
  gum style --foreground "$ACCENT" "  $bar  ${pct}%"
}

_FOOTER() {
  local hints="$1"
  local mode
  (( DRY_RUN )) && mode="$(gum style --foreground "$URGENT" '[DRY RUN]')" \
                || mode="$(gum style --foreground "$INFO" '[LIVE]')"
  local footer
  footer=$(gum style --foreground "$MUTED" \
    "$mode  $hints")
  echo
  echo "$footer"
}

# run(), sudo_probe() → install/lib/common.sh (sourced above).

# ─── MODULE DEFINITIONS ──────────────────────────────────────────────
# MOD_ORDER/MOD_TITLE/MOD_DESC/MOD_GROUP/MOD_CMD, OPTIN_MODS/_is_optin(),
# _reg()/_validate_ids(), and every _reg call → install/lib/registry.sh
# (sourced here — see that file's header for why this is safe to run
# earlier than the original inline position).
source "$(dirname "${BASH_SOURCE[0]}")/install/lib/registry.sh"

# preflight() → install/preflight/ (sourced here; still called from main()
# at the same point as before — see that phase's all.sh header).
source "$(dirname "${BASH_SOURCE[0]}")/install/preflight/all.sh"

if (( AUDIT )); then
  # Package drift audit. This exists because the audit was once run by hand
  # and found 27 packages installed on this machine and declared in no
  # module at all -- including `networkmanager`, whose absence would have
  # given a fresh install the nm-applet tray icon with no daemon behind it
  # and no working network GUI. Drift is silent by nature: you pacman -S
  # something at 2am, it works, and the repo never hears about it. The only
  # defence is to make the check cheap enough to run often.
  #
  # Read-only. Touches nothing, needs no sudo.
  _mods="$DOTFILES_DIR/.config/arch-config/modules"
  [[ -d "$_mods" ]] || { echo "wizard: no modules dir at $_mods" >&2; exit 2; }

  _declared="$(mktemp)"; _explicit="$(mktemp)"; _present="$(mktemp)"
  _core="$(mktemp)"

  # Which module files count. The host's enabled_modules drive dcli, plus
  # base (always), plus the sets installed at runtime by their own wizard
  # modules -- optional.yaml (dcli-sync-extra) and graphics-*.yaml (gpu).
  # Excluded: example.yaml and declared-packages.yaml, which are not
  # modules. (system-packages-ati.yaml used to need excluding here too --
  # a dcli-merge snapshot that declared nvidia, plasma and pulseaudio. It
  # has since been deleted outright.)
  _host="$(sed -n 's/^host:[[:space:]]*//p' \
    "$DOTFILES_DIR/.config/arch-config/config.yaml" 2>/dev/null | head -1)"
  _hostfile="$DOTFILES_DIR/.config/arch-config/hosts/${_host}.yaml"
  # Split deliberately: _core is what a default ./install.sh must produce,
  # so anything declared there and absent is a real gap. optional.yaml and
  # the non-matching graphics-*.yaml sets are legitimately absent.
  _optin_files=("$_mods/optional.yaml" "$_mods/splash.yaml" "$_mods"/graphics-*.yaml)
  _core_files=("$_mods/base.yaml")
  _files=("${_core_files[@]}" "${_optin_files[@]}")
  if [[ -f "$_hostfile" ]]; then
    while read -r _m; do
      [[ -f "$_mods/$_m.yaml" ]] || continue
      _files+=("$_mods/$_m.yaml"); _core_files+=("$_mods/$_m.yaml")
    done < <(sed -n '/^enabled_modules:/,/^[a-z_]*:/p' "$_hostfile" \
             | sed -n 's/^[[:space:]]*-[[:space:]]*\([A-Za-z0-9_-]*\).*/\1/p')
  else
    _WARN "no host file at $_hostfile — auditing every module file"
    _files=("$_mods"/*.yaml)
  fi

  # Only the `packages:` block. A naive "^  - " grep also swallows the
  # `conflicts:` list, which would report linux-zen and linux-hardened --
  # packages we explicitly never want -- as missing.
  awk '
    /^packages:/          { inpkg=1; next }
    /^[a-z_]+:/           { inpkg=0 }
    inpkg && /^[ \t]*-[ \t]*[A-Za-z0-9]/ {
      sub(/^[ \t]*-[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); sub(/[ \t]+$/, "")
      if (length($0)) print
    }
  ' "${_files[@]}" | sort -u > "$_declared"
  # Same extraction over the core-only file set.
  awk '
    /^packages:/          { inpkg=1; next }
    /^[a-z_]+:/           { inpkg=0 }
    inpkg && /^[ \t]*-[ \t]*[A-Za-z0-9]/ {
      sub(/^[ \t]*-[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); sub(/[ \t]+$/, "")
      if (length($0)) print
    }
  ' "${_core_files[@]}" | sort -u > "$_core"

  # Deliberate non-declarations, each with a documented reason. Kept in its
  # own list rather than folded into `declared`: these must not count as
  # drift, but must not be reported as missing either -- amd-ucode is
  # correctly absent on an Intel box, and declaring it would be the bug.
  _ignorelist="$(mktemp)"
  trap 'rm -f "$_declared" "$_explicit" "$_present" "$_core" "$_ignorelist"' EXIT
  : > "$_ignorelist"
  _ignore="$DOTFILES_DIR/.config/arch-config/audit-ignore.yaml"
  if [[ -f "$_ignore" ]]; then
    awk '
      /^packages:/ { inpkg=1; next }
      /^[a-z_]+:/  { inpkg=0 }
      inpkg && /^[ \t]*-[ \t]*[A-Za-z0-9]/ {
        sub(/^[ \t]*-[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); sub(/[ \t]+$/, "")
        if (length($0)) print
      }
    ' "$_ignore" | sort -u > "$_ignorelist"
  fi

  pacman -Qqe | sort > "$_explicit"   # explicitly installed
  pacman -Qq  | sort > "$_present"    # installed at all, deps included

  # Drift is explicit-but-undeclared. A package pulled in as a dependency
  # is not drift -- nobody chose it.
  # `*-debug` packages are byproducts: makepkg splits debug symbols out
  # whenever OPTIONS=debug is set, so every AUR or vendored build leaves
  # one behind. Nobody chose them, they are never declared, and listing
  # each one by name in audit-ignore would just be a chore that grows with
  # every package built from source.
  _drift="$(comm -13 "$_declared" "$_explicit" | comm -13 "$_ignorelist" - | grep -v -- '-debug$' || true)"
  # Missing means absent entirely. Comparing against -Qqe instead would
  # flag every declared package that happens to also be some other
  # package's dependency, which is most of them.
  _missing="$(comm -23 "$_core" "$_present")"
  _missing_optin="$(comm -23 "$_declared" "$_present" | comm -13 "$_core" -)"

  printf '\n  host: %s   ·   modules audited: %s\n' "${_host:-?}" "${#_files[@]}"
  printf '  declared: %s   ·   explicitly installed: %s\n\n' \
    "$(wc -l < "$_declared")" "$(wc -l < "$_explicit")"

  if [[ -n "$_drift" ]]; then
    printf '  \033[33mINSTALLED BUT NOT DECLARED\033[0m — absent on a fresh machine:\n'
    printf '%s\n' "$_drift" | fmt -w 68 | sed 's/^/    /'
    printf '\n    Fix: add each to the right modules/*.yaml, or accept it as\n'
    printf '    deliberate and note it in optional.yaml'"'"'s exclusion list.\n\n'
  else
    printf '  \033[32m✔\033[0m nothing installed that is not declared\n\n'
  fi

  if [[ -n "$_missing" ]]; then
    printf '  \033[31mDECLARED IN AN ENABLED MODULE BUT NOT INSTALLED\033[0m — a real gap:\n'
    printf '  a default ./install.sh is supposed to produce these.\n'
    printf '%s\n' "$_missing" | fmt -w 68 | sed 's/^/    /'
    printf '\n    Fix: dcli sync --force\n\n'
  else
    printf '  \033[32m✔\033[0m every package in an enabled module is installed\n\n'
  fi

  if [[ -n "$_missing_optin" ]]; then
    printf '  \033[90mnot installed, and correctly so\033[0m — optional.yaml plus the GPU\n'
    printf '  \033[90mvendor sets that do not match this machine:\033[0m\n'
    printf '%s\n' "$_missing_optin" | fmt -w 68 | sed 's/^/    /'
    printf '\n'
  fi

  # Non-zero on either real problem, so this can gate a commit or a CI run.
  if [[ -n "$_drift" || -n "$_missing" ]]; then exit 1; fi
  exit 0
fi

if (( SHOW_HELP )); then
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'HELP'

Filters (combine with --yes for scripted runs):
  --only=id1,id2       Run only these module ids (comma-sep)
  --skip=id1,id2       Skip these module ids (comma-sep)

Note: --only and --skip REQUIRE '='. `--only boot-fallback` is rejected
rather than silently running the full install.

Audit (read-only, no sudo, exits non-zero if anything is wrong):
  ./wizard.sh --audit   Compare every declared package against what is
                        actually installed. Catches the two failure modes
                        that make a fresh machine differ from this one:
                        something installed by hand and never declared, and
                        something declared that never got installed.
                        Deliberate exceptions live in
                        .config/arch-config/audit-ignore.yaml.

Opt-in modules run ONLY when named in --only= (or ticked in the picker).
A default run leaves them out:
  dcli-sync-extra    docker · jdk · qemu · printing -- none of it is
                     needed for qtile, the themes, the fonts or the
                     widgets. Install later with:
                       ./wizard.sh --yes --only=dcli-sync-extra

Everything else, boot-splash included, runs in a default `./install.sh`.
boot-splash edits the kernel cmdline and rebuilds the initramfs; it runs
straight after boot-fallback, so the verbose LTS rescue entries exist
before the splash is ever switched on. Opt out with:
  ./install.sh --skip=boot-splash        (reverse: ./wizard.sh --uninstall --only=boot-splash)

HELP
  printf 'Module ids (%d, generated from MOD_ORDER; unknown ids are rejected):\n' "${#MOD_ORDER[@]}"
  printf '%s\n' "${MOD_ORDER[@]}" | fmt -w 72 | sed 's/^/  /'
  cat <<'HELP'

Example (safe non-network test — skip heavy downloads):
  ./wizard.sh --yes --skip=dcli-sync,whisper,whisper-fast,piper,wallpapers,flatpak

Uninstall (reverse config files + sudoers + policies wizard wrote —
NEVER touches pacman packages, dcli syncs, or downloaded models):
  ./wizard.sh --uninstall            # interactive confirm
  ./wizard.sh --uninstall --dry-run  # preview reversals
  ./wizard.sh --uninstall --yes      # unattended
HELP
  exit 0
fi

_validate_ids "$ONLY_LIST" --only
_validate_ids "$SKIP_LIST" --skip

# ─── STEP IMPLEMENTATIONS ────────────────────────────────────────────
# Each step_* delegates to install.sh's actual work via `run`.
# For the wizard scaffold we call install.sh with an env-guarded flag
# where possible; otherwise we inline the minimal command.
#
# The step_*/uninstall_* bodies themselves live in install/<phase>/all.sh
# now (packaging/config/login/post-install — sourced below; preflight/ was
# sourced earlier, near the top of this file). Module dispatch (_reg,
# MOD_CMD, UMOD_CMD, _run_module, page_execute) is unchanged and still
# lives in this file / install/lib/registry.sh — only where each step's
# and uninstall's implementation is DEFINED moved, not how or when it runs.
# _pkgs_from_module and _pacman_lock_check stay here rather than in one
# phase file: both are called from step_*/uninstall_* functions that ended
# up in more than one phase (_pkgs_from_module: gpu/packaging,
# boot-splash/login, dcli-sync-extra/packaging; _pacman_lock_check: called
# from install/preflight/00-checks.sh). A shared helper used across phases
# stays centrally defined rather than being duplicated or arbitrarily
# owned by whichever phase happened to need it first.
source "$(dirname "${BASH_SOURCE[0]}")/install/packaging/all.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install/config/all.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install/login/all.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install/post-install/all.sh"

_pkgs_from_module() {
  # Shared by step_gpu and step_dcli_sync_extra: pull the package list out
  # of a module yaml. Only lines of the exact form "  - name" count, so the
  # commentary and the `exclude:`/`conflicts:` keys below it are ignored.
  sed -n 's/^  - \([A-Za-z0-9._+-]*\).*/\1/p' "$1"
}

# ─── PREFLIGHT / RESILIENCE ──────────────────────────────────────────
# retry_net() → install/lib/common.sh (sourced above).

# Ensure no stale pacman db lock. Root cause of many mid-install fails:
# a crashed pacman leaves /var/lib/pacman/db.lck. Detect + prompt.
_pacman_lock_check() {
  [[ -f /var/lib/pacman/db.lck ]] || return 0
  # Real pacman running? If yes, wait.
  if pgrep -x pacman >/dev/null 2>&1; then
    _WARN "pacman is running — waiting up to 60s"
    local i
    for i in $(seq 1 60); do
      pgrep -x pacman >/dev/null 2>&1 || return 0
      sleep 1
    done
    _ERR "pacman still running after 60s — aborting"
    return 1
  fi
  _WARN "stale pacman db.lck detected (no pacman process)"
  if (( ASSUME_YES )); then
    _DIM "  --yes: auto-removing"
    sudo rm -f /var/lib/pacman/db.lck
    return 0
  fi
  if gum confirm "Remove stale /var/lib/pacman/db.lck?"; then
    sudo rm -f /var/lib/pacman/db.lck
    return 0
  fi
  return 1
}

# Preflight — hard-check the environment before any step runs.
# Fails loud + actionable instead of letting a mid-install step die.
# preflight() → install/preflight/00-checks.sh (sourced near the top of
# this file).

# ─── UNINSTALL FUNCTIONS ─────────────────────────────────────────────
# Each reverses what its step_* wrote. Package installs, dcli syncs,
# and downloaded models are NEVER touched — those may be shared with
# other user workflows. Only removes files/policies wizard authored.
# Idempotent: safe to run twice.


# Register uninstaller commands per module id.
declare -A UMOD_CMD
UMOD_CMD[sanity]="uninstall_sanity"
UMOD_CMD[bootstrap]="uninstall_bootstrap"
UMOD_CMD[yay]="uninstall_yay"
UMOD_CMD[dcli]="uninstall_dcli"
UMOD_CMD[stow]="uninstall_stow"
UMOD_CMD[arch-config]="uninstall_arch_config"
UMOD_CMD[dcli-sync]="uninstall_dcli_sync"
UMOD_CMD[radios]="uninstall_radios"
UMOD_CMD[cargo]="uninstall_cargo"
UMOD_CMD[ati-scripts]="uninstall_ati_scripts"
UMOD_CMD[hintium]="uninstall_hintium"
UMOD_CMD[simplenote]="uninstall_simplenote"
UMOD_CMD[pacman-guard]="uninstall_pacman_guard"
UMOD_CMD[boot-fallback]="uninstall_boot_fallback"
UMOD_CMD[login-shell]="uninstall_login_shell"
UMOD_CMD[touchpad]="uninstall_touchpad"
UMOD_CMD[xinit]="uninstall_xinit"
UMOD_CMD[xresources]="uninstall_xresources"
UMOD_CMD[xmodmap]="uninstall_xmodmap"
UMOD_CMD[keyd]="uninstall_keyd"
UMOD_CMD[lid]="uninstall_lid"
UMOD_CMD[image-envs]="uninstall_image_envs"
UMOD_CMD[flatpak]="uninstall_flatpak"
UMOD_CMD[piper]="uninstall_piper"
UMOD_CMD[ankiconnect]="uninstall_ankiconnect"
UMOD_CMD[vaultwarden]="uninstall_vaultwarden"
UMOD_CMD[vaultwarden-phone]="uninstall_vaultwarden_phone"
UMOD_CMD[tmux-tpm]="uninstall_tmux_tpm"
UMOD_CMD[whisper]="uninstall_whisper"
UMOD_CMD[whisper-fast]="uninstall_whisper_fast"
UMOD_CMD[mic-gain]="uninstall_mic_gain"
UMOD_CMD[scrcpy]="uninstall_scrcpy"
UMOD_CMD[passwordless-sudo]="uninstall_passwordless_sudo"
UMOD_CMD[ownership]="uninstall_ownership"
UMOD_CMD[disable-dm]="uninstall_disable_dm"
UMOD_CMD[candy-icons]="uninstall_candy_icons"
UMOD_CMD[wallpapers]="uninstall_wallpapers"
UMOD_CMD[speed]="uninstall_speed"
UMOD_CMD[themes]="uninstall_themes"
UMOD_CMD[dark-mode]="uninstall_dark_mode"
UMOD_CMD[browser-flags]="uninstall_browser_flags"
UMOD_CMD[browser-memory]="uninstall_browser_memory"
UMOD_CMD[chrome-policy]="uninstall_chrome_policy"
UMOD_CMD[paths]="uninstall_paths"
UMOD_CMD[ui-scale]="uninstall_ui_scale"
UMOD_CMD[picom-pin]="uninstall_picom_pin"
UMOD_CMD[githooks]="uninstall_githooks"
UMOD_CMD[gpu]="uninstall_gpu"
UMOD_CMD[dcli-sync-extra]="uninstall_dcli_sync_extra"
UMOD_CMD[grub-boost]="uninstall_grub_boost"
UMOD_CMD[boot-splash]="uninstall_boot_splash"

# Every module must have a reversal, even if that reversal is a documented
# no-op. Without this check a module added to MOD_ORDER but not to UMOD_CMD
# fails as `UMOD_CMD[$id]: unbound variable` under `set -u` -- and it fails
# *mid-uninstall*, after earlier modules have already been reversed, which
# is the worst possible moment to discover it. dark-mode and browser-memory
# shipped that way. Catch it at startup instead.
_missing_uninstallers=()
for _id in "${MOD_ORDER[@]}"; do
  [[ -n "${UMOD_CMD[$_id]:-}" ]] || _missing_uninstallers+=("$_id")
done
if (( ${#_missing_uninstallers[@]} )); then
  echo "wizard: BUG: module(s) with no uninstaller: ${_missing_uninstallers[*]}" >&2
  echo "wizard: add a UMOD_CMD entry (use a no-op if reversal would be harmful)" >&2
  exit 2
fi
unset _missing_uninstallers _id

# ─── PAGES ───────────────────────────────────────────────────────────

page_welcome() {
  _BOX_HEADER "one-command bootstrap · dry-run capable · picky modules"
  echo
  _INFO "This wizard installs and configures the full Ati dotfiles stack:"
  _DIM  "  · Base + AUR + dcli-managed packages"
  _DIM  "  · Dotfile deployment via stow"
  _DIM  "  · Wal-themed kitty/rofi/dunst/qtile/gtk/eww"
  _DIM  "  · Brave/chromium wal theme extension + policy"
  _DIM  "  · Optional media/voice models (piper + whisper)"
  if (( ASSUME_YES )); then
    _DIM "  (--yes: skipping interactive prompts)"
    return
  fi
  _FOOTER "[enter] continue  ·  [ctrl-c] quit"
  read -rsn1 -p ""
}

page_module_picker() {
  _BOX_HEADER "select modules · all pre-checked · space to toggle"
  # Options are just clean module lines (no commas anywhere) so gum's
  # CSV --selected can preselect everything by default.
  local options=() preselect=() csv line
  for id in "${MOD_ORDER[@]}"; do
    line="$(printf '%-22s [%-8s] %s' "$id" "${MOD_GROUP[$id]}" "${MOD_DESC[$id]}")"
    options+=("$line")
    # Opt-in modules are offered but start UNCHECKED, so the habit of
    # hitting enter on this screen still gives you the desktop-only run.
    _is_optin "$id" || preselect+=("$line")
  done
  csv="$(printf '%s\n' "${preselect[@]}" | paste -sd, -)"
  local picked
  picked=$(printf '%s\n' "${options[@]}" | gum choose --no-limit \
    --cursor.foreground "$ACCENT" \
    --selected.foreground "$ACCENT" \
    --header "space=toggle · a=all · enter=continue" \
    --selected="$csv" || true)
  PICKED_IDS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    PICKED_IDS+=("$(awk '{print $1}' <<<"$line")")
  done <<<"$picked"
  (( ${#PICKED_IDS[@]} )) || { _WARN "Nothing picked, aborting."; exit 0; }
}

page_summary() {
  _BOX_HEADER "review · ${#PICKED_IDS[@]} module(s) queued"
  # Aligned card list: chip · badge · title
  for id in "${PICKED_IDS[@]}"; do
    local chip badge title
    chip="$(gum style --foreground "$OK_C" --bold '  ✔')"
    badge="$(_BADGE "${MOD_GROUP[$id]}")"
    title="$(gum style --foreground "$FG" "${MOD_TITLE[$id]}")"
    gum join --horizontal "$chip" "  " "$badge" "  " "$title"
    _DIM "       ${MOD_DESC[$id]}"
  done
  echo
  if (( DRY_RUN )); then
    gum style --border thick --align center --padding "0 2" \
      --border-foreground "$URGENT" --foreground "$URGENT" --bold \
      "DRY RUN — commands preview only, nothing executed"
  fi
  _FOOTER "[y] proceed  ·  [n] cancel"
  if (( ASSUME_YES )); then return 0; fi
  gum confirm "Proceed with ${#PICKED_IDS[@]} module(s)?"
}

_FAILED_IDS=()

_run_module() {
  # Two statements, not one. `local a="$1" b="$a"` does NOT let b see the
  # a assigned beside it -- bash expands the whole `local` line against the
  # *enclosing* scope first. This read `/tmp/wizard-$id.log` from the
  # caller's `id`, and only produced correct filenames because
  # page_execute's `for id in ...` loop variable happens to be unlocalised
  # and happens to hold the same value. Make that loop `local`, or call
  # this from anywhere else, and every module's log silently collapses
  # into one `/tmp/wizard-.log` while the UI keeps telling you to
  # `tail /tmp/wizard-<id>.err`. (shellcheck SC2318)
  local id="$1"
  local logf="/tmp/wizard-$id.log" errf="/tmp/wizard-$id.err"
  : >"$logf"; : >"$errf"
  local cmd
  if (( UNINSTALL )); then cmd="${UMOD_CMD[$id]}"; else cmd="${MOD_CMD[$id]}"; fi
  # sudo writes its password prompt straight to the tty, bypassing our
  # log capture — if it fires mid-spinner, the \r redraw below erases
  # it almost as fast as it appears. Prime credentials up front with a
  # clean, uncontested prompt before the spinner starts. Cheap/instant
  # no-op if already cached; harmless no-op (no hang) if there's no
  # tty to prompt on at all.
  sudo -v 2>/dev/null || true
  # stdin comes from /dev/null on purpose. A module's stdout and stderr are
  # captured to files behind the spinner, so anything in there that reads a
  # line -- a git credential prompt on a repo that moved, a makepkg question
  # a missing --noconfirm let through, a helper's `read -rp` -- waits forever
  # on a prompt nobody can see, and the spinner keeps turning as if work were
  # happening. Closed stdin turns that infinite hang into an immediate,
  # logged failure the retry/skip logic can act on. sudo is unaffected: it
  # reads its password from /dev/tty, not stdin.
  ( set +e; "$cmd" >"$logf" 2>"$errf" </dev/null ) &
  local pid=$! spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 last=""
  while kill -0 "$pid" 2>/dev/null; do
    last="$(tail -n1 "$logf" 2>/dev/null)"
    [[ -z "$last" ]] && last="$(tail -n1 "$errf" 2>/dev/null)"
    printf '\r  %s%s %.80s\033[0m\033[K' "$MUTED_ANSI" "${spin:i++%${#spin}:1}" "$last"
    sleep 0.12
  done
  printf '\r\033[K'
  local rc=0
  wait "$pid" || rc=$?
  return "$rc"
}

_show_error_tail() {
  local id="$1"                       # separate statement -- see _run_module
  local errf="/tmp/wizard-$id.err" logf="/tmp/wizard-$id.log"
  local tail_content
  tail_content=$(tail -5 "$errf" 2>/dev/null | grep -v '^\s*$' | head -5) || true
  [[ -z "$tail_content" ]] && { tail_content=$(tail -5 "$logf" 2>/dev/null | grep -v '^\s*$' | head -5) || true; }
  [[ -z "$tail_content" ]] && tail_content="(no output captured — check $errf)"
  gum style --border rounded --border-foreground "$URGENT" \
    --padding "0 2" --margin "0 4" --foreground "$URGENT" \
    "$tail_content"
}

page_execute() {
  if (( UNINSTALL )); then
    _BOX_HEADER "uninstalling — reversing wizard writes"
  else
    _BOX_HEADER "installing modules"
  fi
  # `id` is scoped deliberately. It used to leak into the global namespace,
  # and _run_module's log filenames silently depended on that leak.
  local ok=0 fail=0 total=${#PICKED_IDS[@]} idx=0 id
  for id in "${PICKED_IDS[@]}"; do
    idx=$((idx+1))
    local chip badge title status_line
    chip="$(_CHIP "$idx" "$total")"
    badge="$(_BADGE "${MOD_GROUP[$id]}")"
    title="$(gum style --bold --foreground "$FG" "${MOD_TITLE[$id]}")"
    gum join --horizontal "$chip" " " "$badge" " " "$title"
    if (( DRY_RUN )); then
      # Actually call the step/uninstall so their `run` wrapper prints
      # every command that would execute — real audit trail.
      local cmd
      if (( UNINSTALL )); then cmd="${UMOD_CMD[$id]}"; else cmd="${MOD_CMD[$id]}"; fi
      "$cmd" 2>&1 | sed 's/^/    /' || true
      status_line="$(gum style --foreground "$OK_C" '   ✔ preview ok')"
      ok=$((ok+1))
    else
      local attempts=0
      while :; do
        attempts=$((attempts+1))
        if _run_module "$id"; then
          status_line="$(gum style --foreground "$OK_C" '   ✔ ok')"
          ok=$((ok+1))
          break
        fi
        # Failed: show tail, then prompt (or auto-skip under --yes).
        gum style --foreground "$URGENT" --bold "   ✖ failed (attempt $attempts)"
        _show_error_tail "$id"
        local choice
        if (( ASSUME_YES )); then
          choice="skip · continue"
          gum style --foreground "$WARN_C" "   (--yes: auto-skipping)"
        else
          choice=$(gum choose --header "Module '$id' failed. What now?" \
            "retry" "skip · continue" "quit installer")
        fi
        case "$choice" in
          retry)
            gum style --foreground "$INFO" "   ↻ retrying $id…"
            ;;
          "skip · continue")
            status_line="$(gum style --foreground "$WARN_C" '   ⚠ skipped after failure')"
            fail=$((fail+1))
            _FAILED_IDS+=("$id")
            break
            ;;
          *)
            gum style --foreground "$URGENT" --bold "   ✖ Aborted by user at $id"
            _finale_summary "$ok" "$fail" "$total" "$idx" "aborted"
            exit 2
            ;;
        esac
      done
    fi
    printf '%s\n' "$status_line"
    _PROGRESS "$idx" "$total"
    echo
  done
  _finale_summary "$ok" "$fail" "$total" "$total" "done"
}

_finale_summary() {
  local ok="$1" fail="$2" total="$3" ran="$4" status="$5"
  local what="Installation"
  (( UNINSTALL )) && what="Uninstall"
  local border_color="$ACCENT" title="$what Complete"
  if [[ "$status" == "aborted" ]]; then
    border_color="$URGENT"
    title="$what Aborted"
  elif (( fail )); then
    border_color="$WARN_C"
    title="$what Finished (with failures)"
  fi
  echo
  gum style --border rounded --padding "1 3" --align center \
    --border-foreground "$border_color" \
    "$(gum style --bold "$title")" \
    "" \
    "$(gum style --foreground "$OK_C" "✔ $ok ok")   $(gum style --foreground "$WARN_C" "⚠ $((total - ran)) not run")   $(gum style --foreground "$URGENT" "✖ $fail failed")"
  if (( ${#_FAILED_IDS[@]} )); then
    echo
    _H2 "Failed modules — logs at /tmp/wizard-<id>.err:"
    for fid in "${_FAILED_IDS[@]}"; do
      _ERR "  · $fid  ($(gum style --foreground "$MUTED" "tail /tmp/wizard-$fid.err"))"
    done
  fi
}

# Arm (or disarm) the onboarding tour for the next graphical login.
#
# The install ends in a TTY; the tour is an eww window that can only exist
# inside a qtile session, i.e. after `letsgo` -- usually after a reboot.
# This stamp is the handoff between the two. autostart.sh calls
# onboarding-first-run on every login, which consumes the stamp and shows
# the tour exactly once.
#
# Written directly rather than via `onboarding-first-run --arm`: the
# ati-scripts module symlinks that script into /usr/local/bin, and it is
# perfectly legal to run the wizard with that module skipped. The stamp
# format is an empty file, so there is nothing to get out of step.
#
# "Once" means once per machine, not once per wizard run. This is a
# dotfiles repo: ./install.sh is re-run all the time to apply a change or
# a single --only= module, and each of those runs used to clear the .done
# stamp and re-arm, so the tour reappeared at the next reboot -- exactly
# the behaviour it exists to avoid. A consumed stamp is therefore final
# here; uninstall clears it, so a genuine reinstall gets the tour again,
# and `onboarding-first-run --arm` still forces it back on demand.
arm_onboarding() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/atidots"
  if (( UNINSTALL )); then
    rm -f "$state_dir/onboarding.pending" "$state_dir/onboarding.done"
    return
  fi
  [[ -e "$state_dir/onboarding.done" ]] && return
  mkdir -p "$state_dir" || return
  : >"$state_dir/onboarding.pending"
}

# Ask for the Simplenote login, once, after every module has run.
#
# Deliberately not inside step_simplenote: _run_module captures step output to a
# log file behind a spinner, so a prompt there is invisible. Deliberately at the
# end rather than up front: an install is long enough to walk away from, and a
# password prompt that blocks the whole run for 40 minutes is worse than one
# that waits for you at the finish.
#
# Gated on --yes as well as on a tty. This used to ask during `./install.sh`
# on the grounds that install.sh is the interactive path -- but ./install.sh is
# `wizard.sh --yes`, whose contract is that you can start it and walk away.
# A password prompt at the end of a 40-minute run breaks that: the wizard sits
# there indefinitely, and whether the install finished depends on someone being
# in the chair. Simplenote is a phone convenience, not part of a working
# desktop, so --yes prints how to set it up and finishes instead.
page_simplenote_creds() {
  local id found=0
  for id in "${PICKED_IDS[@]}"; do [[ "$id" == simplenote ]] && found=1; done
  (( found )) || return 0
  (( DRY_RUN )) && return 0
  [[ -t 0 ]] || return 0
  if (( ASSUME_YES )); then
    echo
    _DIM "Simplenote (Mod+Shift+S note → phone) is installed but not logged in."
    _DIM "  Connect it whenever you like:  ./wizard.sh --only=simplenote"
    return 0
  fi

  local cred="$HOME/.config/simplenote/credentials"
  [[ -f "$cred" ]] || return 0
  # Already configured -- do not re-ask, and do not print the stored address.
  if ! grep -qE '^[[:space:]]*(email|password)[[:space:]]*=[[:space:]]*$' "$cred"; then
    return 0
  fi

  echo
  _H1 "Simplenote"
  _INFO "  Mirrors the Mod+Shift+S TODOS note to the Simplenote app on your phone."
  _DIM  "  Leave the email blank to skip — you can set it up later with:"
  _DIM  "    ./wizard.sh --only=simplenote"
  echo

  local email password
  email="$(gum input --placeholder 'Simplenote email (blank = skip)')" || return 0
  [[ -n "$email" ]] || { _DIM "  Skipped."; return 0; }
  password="$(gum input --password --placeholder 'Simplenote password')" || return 0
  if [[ -z "$password" ]]; then
    _WARN "  No password entered — skipped."
    return 0
  fi

  # Write via a 600 temp file rather than editing in place: a plaintext password
  # must never exist, even briefly, at the default umask.
  local tmp
  tmp="$(mktemp)"; chmod 600 "$tmp"
  printf '[simplenote]\nemail = %s\npassword = %s\n' "$email" "$password" >"$tmp"
  mv "$tmp" "$cred"; chmod 600 "$cred"

  # Verify immediately. The script exits 0 on every failure (it must never break
  # :w), so its stderr is what says whether the login actually worked.
  local out
  out="$("$HOME/.config/AtiScriptsV1/simplenote_push" 2>&1)" || true
  if [[ -z "$out" ]]; then
    _OK "  Connected — check the Simplenote app on your phone."
    return 0
  fi

  _WARN "  Saved, but the first push did not go through:"
  _WARN "    $out"

  # Some networks blackhole auth.simperium.com (login) while leaving
  # api.simperium.com (every actual note read/write) reachable, which is why
  # the web app keeps working when this does not. A token taken from the web
  # app skips the login host entirely.
  if [[ "$out" == *auth.simperium.com* ]]; then
    local snippet='Object.entries(localStorage).forEach(([k,v])=>{if(/[0-9a-f]{32}/.test(v))console.log(k,v)})'
    echo
    _INFO "  Your network blocks auth.simperium.com — the login host."
    _INFO "  The note API itself is reachable, so a token from the web app works."
    echo
    # A fresh install runs in a TTY, before startx: there is no browser to log
    # in with and no X clipboard to paste into. Say so plainly and let them
    # finish from the desktop rather than dead-ending in a prompt they cannot
    # satisfy.
    if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
      _WARN "  No graphical session yet — you need a browser for this step."
      _DIM  "  Finish it after your first login to the desktop:"
      _DIM  "    ./wizard.sh --only=simplenote"
      _DIM  "  Full walkthrough: TROUBLESHOOTING.md → Simplenote"
      return 0
    fi
    _INFO "  1. Log in at:  https://app.simplenote.com"
    _INFO "  2. Press F12 → Console tab"
    if command -v xclip >/dev/null && printf '%s' "$snippet" | xclip -selection clipboard 2>/dev/null; then
      _OK "  3. The snippet is already on your clipboard — just paste it (Ctrl+V) + Enter"
      _DIM "     (Brave may ask you to type 'allow pasting' first)"
    else
      _INFO "  3. Paste this into the console, then Enter:"
      _DIM  "       $snippet"
    fi
    _INFO "  4. Copy the 32-character hex value it prints (accessToken)"
    echo
    local token
    token="$(gum input --placeholder 'Simperium token (blank = skip)')" || return 0
    if [[ -n "$token" ]]; then
      local tmp2
      tmp2="$(mktemp)"; chmod 600 "$tmp2"
      printf '[simplenote]\nemail = %s\npassword = %s\ntoken = %s\n' \
        "$email" "$password" "$token" >"$tmp2"
      mv "$tmp2" "$cred"; chmod 600 "$cred"
      out="$("$HOME/.config/AtiScriptsV1/simplenote_push" 2>&1)" || true
      if [[ -z "$out" ]]; then
        _OK "  Connected via token — check the Simplenote app on your phone."
        return 0
      fi
      _WARN "  Still failing:  $out"
    fi
  fi
  _DIM  "  Retry any time:  ~/.config/AtiScriptsV1/simplenote_push"
  _DIM  "  Details:         TROUBLESHOOTING.md → Simplenote"
}

page_finale() {
  (( DRY_RUN )) || arm_onboarding
  echo
  if (( UNINSTALL )); then
    # Telling someone who just uninstalled to "run letsgo" would send them
    # into a qtile session whose config was just unlinked.
    _H1 "Next steps"
    _INFO "  · Packages, dcli syncs and downloaded models were left alone."
    _INFO "  · Re-install any time:     ./install.sh"
    echo
    _DIM "Log out and back in so the shell/session changes take effect."
    echo
    return
  fi
  _H1 "Next steps"
  _INFO "  · Log out to TTY and run:  letsgo   (or: startx)"
  _INFO "  · Reload qtile any time:   qtile cmd-obj -o cmd -f reload_config"
  _INFO "  · Update packages:         dcli sync"
  _INFO "  · Update this config:      ati-update      (--check to preview)"
  echo
  # Said here because this is the only screen everybody sees. The config
  # is pushed far more often than the ISO is rebuilt, so somebody who
  # installed from a stick burned months ago is running months-old
  # settings and has no way to know it from the desktop itself.
  _DIM "    ati-update pulls the newest configuration from GitHub and applies"
  _DIM "    only the parts a given change needs. It checks the incoming qtile"
  _DIM "    config loads before applying anything, and rolls back if it does not."
  echo
  _OK   "  · A short tour opens by itself the first time the desktop starts."
  _DIM "    Skip it with Cancel; reopen it any time from the 💡 tray icon."
  echo
  _DIM "TROUBLESHOOTING.md documents every common failure + fix."
  echo
}

# ─── MAIN FLOW ───────────────────────────────────────────────────────
main() {
  page_welcome
  if (( ! DRY_RUN )); then
    preflight
    _start_sudo_keepalive || true
  fi
  if (( ASSUME_YES )); then
    if [[ -n "$ONLY_LIST" ]]; then
      # --only= is an explicit request for exactly these ids, so it must be
      # able to reach an opt-in module. Start from everything and let the
      # filter below narrow it; otherwise `--yes --only=dcli-sync-extra`
      # would filter an already-pruned list down to nothing and exit 0 as
      # if it had worked.
      PICKED_IDS=("${MOD_ORDER[@]}")
    else
      PICKED_IDS=()
      for id in "${MOD_ORDER[@]}"; do
        _is_optin "$id" || PICKED_IDS+=("$id")
      done
    fi
  else
    page_module_picker
  fi
  # Apply --only / --skip filters after picker (compose cleanly).
  if [[ -n "$ONLY_LIST" ]]; then
    local filtered=()
    for id in "${PICKED_IDS[@]}"; do
      _id_in_csv "$ONLY_LIST" "$id" && filtered+=("$id")
    done
    PICKED_IDS=("${filtered[@]}")
  fi
  if [[ -n "$SKIP_LIST" ]]; then
    local filtered=()
    for id in "${PICKED_IDS[@]}"; do
      _id_in_csv "$SKIP_LIST" "$id" || filtered+=("$id")
    done
    PICKED_IDS=("${filtered[@]}")
  fi
  (( ${#PICKED_IDS[@]} )) || { _WARN "No modules left after filter."; exit 0; }
  page_summary || { _WARN "Cancelled by user."; exit 0; }
  page_execute
  (( UNINSTALL )) || page_simplenote_creds
  page_finale
}

main "$@"
