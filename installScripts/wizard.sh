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

# ─── MODULE DEFINITIONS ──────────────────────────────────────────────
# Each module: id | group | title | 1-line desc | shell to execute
# Group is only used for the picker header — keep display order stable.
declare -A MOD_TITLE MOD_DESC MOD_GROUP MOD_CMD
MOD_ORDER=(
  sanity bootstrap yay dcli stow arch-config paths dcli-sync gpu picom-pin cargo ati-scripts ui-scale githooks
  pacman-guard boot-fallback login-shell
  touchpad xinit xresources xmodmap lid image-envs flatpak piper whisper
  whisper-fast mic-gain
  passwordless-sudo ownership disable-dm candy-icons wallpapers speed
  themes dark-mode browser-flags browser-memory chrome-policy
  dcli-sync-extra boot-splash
)

# Opt-in modules: valid --only= targets, and listed (unchecked) in the
# interactive picker, but never part of a default `./install.sh` run.
#
# install.sh's promise is a working DESKTOP -- qtile, themes, fonts,
# widgets -- not a working workstation. Docker, a JDK, printing and qemu
# are a second pass you run when you actually need them, on your own
# schedule. Keeping them out of round one is what lets the first boot
# stay short and stay predictable.
OPTIN_MODS=(dcli-sync-extra boot-splash)
_is_optin() {
  local id m
  id="$1"
  for m in "${OPTIN_MODS[@]}"; do [[ "$m" == "$id" ]] && return 0; done
  return 1
}

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
  # Excluded: example.yaml and declared-packages.yaml (not modules), and
  # system-packages-ati.yaml, which is NOT in enabled_modules -- counting
  # it would declare nvidia, plasma and pulseaudio on an Intel qtile box.
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

_reg() { MOD_TITLE[$1]="$2"; MOD_GROUP[$1]="$3"; MOD_DESC[$1]="$4"; MOD_CMD[$1]="$5"; }

# Reject typo'd ids in --only/--skip. Without this a misspelled --only
# filters down to nothing and exits 0 as if it had worked, and a
# misspelled --skip silently skips nothing -- both look like success.
_validate_ids() {
  local list="$1" flag="$2" id
  local -a bad=() _ids=()
  [[ -n "$list" ]] || return 0
  IFS=',' read -r -a _ids <<< "$list"
  for id in "${_ids[@]}"; do
    [[ -z "$id" ]] && continue
    [[ " ${MOD_ORDER[*]} " == *" $id "* ]] || bad+=("$id")
  done
  if (( ${#bad[@]} )); then
    echo "wizard: $flag: unknown module id(s): ${bad[*]}" >&2
    echo "wizard: valid ids: ${MOD_ORDER[*]}" >&2
    exit 2
  fi
}
_reg sanity            "System check"        System    "Arch + X11 + dotfiles present"                          "step_sanity"
_reg bootstrap         "Bootstrap packages"  System    "base-devel · git · stow · xorg-server · curl"           "step_bootstrap"
_reg yay               "AUR helper (yay)"    System    "Build yay-bin from AUR if missing"                      "step_yay"
_reg dcli              "dcli"                System    "Declarative package sync tool"                          "step_dcli"
_reg stow              "Deploy dotfiles"     Dotfiles  "Symlink .config · .local · etc via GNU stow"            "step_stow"
_reg arch-config       "Host arch-config"    Dotfiles  "Point arch-config at this host"                         "step_arch_config"
_reg dcli-sync         "dcli sync (all pkgs)" System   "Install every declared pkg + flatpak (slow)"            "step_dcli_sync"
_reg paths             "Expand @HOME@ paths"  Dotfiles  "Render browser flags · gtk.css · bookmarks for this user"  "step_paths"
_reg ui-scale          "UI scale (DPI)"      Dotfiles  "Size bar/fonts to this display; ui-scale-toggle to override"  "step_ui_scale"
_reg githooks          "Git pre-commit hook"  Dotfiles "Refuse commits that break the config or drift packages"  "step_githooks"
_reg gpu               "GPU + microcode"     System    "Detect Intel/AMD/NVIDIA from PCI ids, install matching drivers" "step_gpu"
_reg picom-pin         "picom (pinned)"      System    "Build the animation fork from a fixed commit, not branch HEAD"  "step_picom_pin"
_reg cargo             "Cargo tools"         System    "pomodoro-tui"                                           "step_cargo"
_reg ati-scripts       "AtiScriptsV1"        Dotfiles  "Install rofi-kill · theme-apply · etc to /usr/local/bin" "step_ati_scripts"
_reg touchpad          "Touchpad tap"        System    "Enable tap-to-click"                                    "step_touchpad"
_reg pacman-guard      "Pacman safety hook"  System    "PreTransaction gate: refuse upgrades when / is too full"  "step_pacman_guard"
_reg boot-fallback     "LTS boot entries"    System    "systemd-boot entries for linux-lts + a rescue initramfs"  "step_boot_fallback"
_reg login-shell       "Fish login shell"    System    "chsh to fish so the TTY matches kitty (letsgo, aliases)" "step_login_shell"
_reg xinit             ".xinitrc"            Dotfiles  "Auto-start qtile + picom + cursor size"                 "step_xinit"
_reg xresources        ".Xresources"         Dotfiles  "Xcursor size 24 + Breeze theme (load via xrdb)"         "step_xresources"
_reg xmodmap           ".Xmodmap"            Dotfiles  "Caps fully repurposed as Alt (no tap-Caps fallback)"    "step_xmodmap"
_reg lid               "Lid = ignore"        System    "Never sleep on lid close"                               "step_lid"
_reg image-envs        "Image env"           Dotfiles  "Suppress VIPS warnings + ensure ~/tmp (fish TMPDIR)"    "step_image_envs"
_reg flatpak           "Flatpak (legacy)"    Apps      "Uninstall-only: qdrop replaced flathub/collector"       "step_flatpak"
_reg piper             "Piper voices"        Media     "EN + DE TTS voices (~60MB)"                             "step_piper"
_reg whisper           "Whisper models"      Media     "base.en (live dictation) + small.en (batch) STT (~630MB)" "step_whisper"
_reg whisper-fast      "Whisper fast build"  Media     "Rebuild whisper-cli/-stream Release (AUR pkg is ~13x slower unoptimized)" "step_whisper_fast"
_reg mic-gain          "Mic gain fix"        System    "Reassert mic capture gain WirePlumber resets on login"  "step_mic_gain"
_reg passwordless-sudo "Passwordless sudo"   System    "Add user to NOPASSWD sudoers"                           "step_nopasswd"
_reg ownership         "Fix ownership"       System    "chown -R \$USER on ~/.dotfiles"                         "step_ownership"
_reg disable-dm        "Disable display mgrs" System   "TTY + startx only"                                      "step_disable_dm"
_reg candy-icons       "Candy icons"         Themes    "Install candy-icons theme"                              "step_candy"
_reg wallpapers        "Wallpapers"          Themes    "Clone your wallpapers repo to ~/Pictures"                    "step_wallpapers"
_reg speed             "Speed tweaks"        System    "sysctl + service trims (from speed_boost.sh)"           "step_speed"
_reg themes            "Theme system"        Themes    "pywal + palette precompile + initial doom-one apply"    "step_themes"
_reg dark-mode         "Dark preference"     Themes    "Advertise prefer-dark via portal so sites use their own dark theme" "step_dark_mode"
_reg browser-flags     "Browser flags"       Browsers  "brave/chrome/chromium wal theme extension flags"        "step_browser_flags"
_reg browser-memory    "Browser memory saver" Browsers "Policy: discard idle tabs, keep whatsapp/chatgpt live"  "step_browser_memory"
_reg chrome-policy     "Chrome theme policy" Browsers  "Sign .pem + install /etc/opt/chrome force_installed"    "step_chrome_policy"
_reg dcli-sync-extra   "Optional packages"   Optional  "docker · jdk · qemu · printing (opt-in, run later)"     "step_dcli_sync_extra"
_reg boot-splash       "Boot splash"         Optional  "Your name + progress bar instead of kernel text (opt-in; edits cmdline)" "step_boot_splash"

_validate_ids "$ONLY_LIST" --only
_validate_ids "$SKIP_LIST" --skip

# ─── STEP IMPLEMENTATIONS ────────────────────────────────────────────
# Each step_* delegates to install.sh's actual work via `run`.
# For the wizard scaffold we call install.sh with an env-guarded flag
# where possible; otherwise we inline the minimal command.

step_sanity() {
  [[ -f /etc/arch-release ]] || { _ERR "Not Arch Linux"; return 1; }
  [[ "${XDG_SESSION_TYPE:-}" != wayland ]] || { _ERR "Wayland not supported"; return 1; }
  # The ~ is prose in a message shown to a human, not a path being expanded.
  # shellcheck disable=SC2088
  [[ -d "$DOTFILES_DIR" ]] || { _ERR "~/.dotfiles missing"; return 1; }
  _OK "System checks passed"
}
step_bootstrap() {
  if (( DRY_RUN )); then _DIM "  [dry] sudo pacman -Syu … (retry x3)"; return; fi
  retry_net 3 5 sudo pacman -Syu --needed --noconfirm base-devel git stow xorg-server xorg-xinit curl wget unzip
}
step_yay()          { command -v yay >/dev/null && { _OK "yay present"; return; }
                      run "rm -rf /tmp/yay-bin && cd /tmp && git clone https://aur.archlinux.org/yay-bin.git yay-bin && cd yay-bin && makepkg -si --noconfirm"; }
step_dcli()         { command -v dcli >/dev/null && { _OK "dcli present"; return; }
                      run "yay -S --noconfirm dcli-arch-git"; }
step_stow()         { run "$DOTFILES_DIR/installScripts/stow_script.sh"; }
step_arch_config()  { run "$DOTFILES_DIR/installScripts/arch-config.sh"; }
step_dcli_sync() {
  run "cd $DOTFILES_DIR && dcli sync --force && { command -v mandb >/dev/null && sudo mandb || true; } && fc-cache -fv"
  (( DRY_RUN )) && return
  # dcli can report the sync step as done even when an individual AUR
  # package's post-build install silently failed (e.g. a sudo hiccup
  # mid-build, long before the sudo-keepalive fix existed). Verify
  # with a dry-run and self-heal with bounded retries before moving on
  # — cheap insurance, and turns a silent gap into either a real fix
  # or a visible failure instead of a false "✔ ok".
  local pending attempt=0
  while (( attempt < 2 )); do
    pending=$(cd "$DOTFILES_DIR" && dcli sync --dry-run 2>/dev/null | grep -oP 'Packages to install: \K[0-9]+' | head -1)
    [[ -z "$pending" || "$pending" == "0" ]] && return 0
    attempt=$((attempt+1))
    echo "dcli sync left $pending package(s) uninstalled — retry $attempt/2"
    ( cd "$DOTFILES_DIR" && dcli sync --force )
  done
  pending=$(cd "$DOTFILES_DIR" && dcli sync --dry-run 2>/dev/null | grep -oP 'Packages to install: \K[0-9]+' | head -1)
  if [[ -n "$pending" && "$pending" != "0" ]]; then
    echo "dcli sync still has $pending package(s) uninstalled after retries — run 'dcli sync --force' manually later"
    return 1
  fi
}
step_paths() {
  # Render every @HOME@ template to its real destination.
  #
  # These are the files where $HOME genuinely cannot be used, so the only
  # alternative was a literal /home/ati baked into the repo:
  #
  #   *-flags.conf   Chromium's launcher documents "arguments are split on
  #                  whitespace and shell quoting rules apply but no further
  #                  parsing is performed", and Brave's wrapper mapfiles the
  #                  lines straight into an argv array. Neither expands a
  #                  variable. A wrong path here means --load-extension
  #                  silently fails and the browser never picks up the
  #                  generated wal theme -- the browser just looks untouched
  #                  while every other app retints.
  #   gtk.css        GTK's CSS @import takes a URL, not a shell expression.
  #                  A wrong path means the wal overlay never loads and GTK
  #                  apps keep the stock theme colors.
  #   bookmarks      GTK's bookmark file is plain "URI  label" lines.
  #
  # Written as REAL files, replacing the stow symlink, exactly like
  # theme-apply's render_dunstrc. That is what keeps a per-machine value
  # from being written back into the repo through the link.
  local src dst
  for src in \
    "$DOTFILES_DIR/.config/brave-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/chrome-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/chromium-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/gtk-3.0/gtk.css.tmpl" \
    "$DOTFILES_DIR/.config/gtk-4.0/gtk.css.tmpl" \
    "$DOTFILES_DIR/.config/gtk-3.0/bookmarks.tmpl"
  do
    [[ -f "$src" ]] || { _WARN "missing template $src"; continue; }
    dst="$HOME/.config/${src#"$DOTFILES_DIR"/.config/}"
    dst="${dst%.tmpl}"
    run "mkdir -p $(dirname "$dst") && rm -f $dst && sed 's|@HOME@|$HOME|g' $src > $dst"
  done
}

_pkgs_from_module() {
  # Shared by step_gpu and step_dcli_sync_extra: pull the package list out
  # of a module yaml. Only lines of the exact form "  - name" count, so the
  # commentary and the `exclude:`/`conflicts:` keys below it are ignored.
  sed -n 's/^  - \([A-Za-z0-9._+-]*\).*/\1/p' "$1"
}

step_ui_scale() {
  # Runs AFTER ati-scripts, which is what puts ui-scale on PATH.
  #
  # Every pixel value in the qtile config was tuned on a 1366x768 14"
  # panel. Without this the bar is a sliver of unreadable text on a 4K
  # laptop -- the one axis these dotfiles cannot keep identical by copying
  # files, because the right answer depends on the glass.
  local bin
  bin="$(command -v ui-scale || echo "$DOTFILES_DIR/.config/AtiScriptsV1/ui-scale")"
  [[ -x "$bin" ]] || { _WARN "ui-scale not found — run the ati-scripts module first"; return 0; }
  if [[ -z "${DISPLAY:-}" ]]; then
    # xrandr needs an X server. During a TTY install there is none yet, so
    # defer rather than write a wrong factor: .xinitrc runs it at login.
    _OK "no X session yet — ui-scale will run from .xinitrc on first startx"
    return 0
  fi
  run "$bin"
}

step_picom_pin() {
  # Build the animation-capable picom fork from a PINNED commit.
  #
  # The AUR package (picom-ftlabs-git) sources `#branch=next`, so it builds
  # whatever the tip is on the day you install. picom is what renders the
  # animations, rounded corners, shadows and blur this desktop is built
  # around, so letting it float means two machines from the same repo can
  # look and move differently with nothing in the config to explain it.
  local dir="$DOTFILES_DIR/.config/arch-config/pkgbuilds/picom-ftlabs-pinned"
  [[ -d "$dir" ]] || { _ERR "missing $dir"; return 1; }

  if pacman -Qq picom-ftlabs-pinned >/dev/null 2>&1; then
    _OK "picom-ftlabs-pinned present"
    return 0
  fi

  # The floating AUR build conflicts (same provides). Remove it first, or
  # makepkg fails at the install step after a full compile -- a slow way to
  # discover a problem visible up front.
  if pacman -Qq picom-ftlabs-git >/dev/null 2>&1; then
    _WARN "removing floating picom-ftlabs-git in favour of the pinned build"
    run "sudo pacman -Rdd --noconfirm picom-ftlabs-git"
  fi

  # -s installs build deps, -i installs the result, -r cleans them up.
  # Built in a temp copy: makepkg writes src/ and pkg/ next to the PKGBUILD,
  # and that directory is inside the git repo.
  local tmp
  tmp="$(mktemp -d)"
  run "cp -r $dir/. $tmp/ && cd $tmp && makepkg -si --noconfirm --needed --clean"
  rm -rf "$tmp"
}

step_githooks() {
  # A symlink, not a copy: a copied hook silently keeps running the version
  # from whenever the wizard last ran, which is the same drift problem the
  # hook exists to catch.
  local src="$DOTFILES_DIR/installScripts/hooks/pre-commit"
  local dst="$DOTFILES_DIR/.git/hooks/pre-commit"
  [[ -f "$src" ]] || { _WARN "no hook at $src"; return 0; }
  [[ -d "$DOTFILES_DIR/.git" ]] || { _WARN "$DOTFILES_DIR is not a git repo — skipping"; return 0; }
  run "ln -sfn $src $dst"
}

step_gpu() {
  # The single most portability-critical module in the wizard.
  #
  # graphics.yaml used to hardcode the Intel driver set. Installing that on
  # an AMD or NVIDIA machine leaves the real GPU with no driver, GLX falls
  # back to llvmpipe, and picom -- which this repo configures with
  # `backend = "glx"` and `vsync = true` -- either crawls or refuses to
  # start. Either way the animations, rounded corners and shadows that the
  # desktop is built around are gone, with nothing in the logs that points
  # at a package list. So: detect, then install what this machine needs.
  local mod_dir="$DOTFILES_DIR/.config/arch-config/modules"
  local arch vendors="" ids
  arch="$(uname -m)"

  if [[ "$arch" != x86_64 ]]; then
    # ARM boards have no PCI GPU to probe and no ucode package; mesa's
    # KMS drivers in graphics.yaml are the whole story there.
    _WARN "arch is $arch, not x86_64 -- skipping PCI GPU + microcode detection"
    _WARN "graphics.yaml (vendor-neutral mesa) is installed; verify GL with vainfo"
    return 0
  fi

  command -v lspci >/dev/null || run "sudo pacman -S --needed --noconfirm pciutils"

  # Class 03xx is Display controller: VGA (0300), XGA, 3D (0302). A laptop
  # with switchable graphics reports two, and genuinely needs both sets.
  ids="$(lspci -mn 2>/dev/null | awk -F'"' '$2 ~ /^03/ {print tolower($4)}')"
  [[ -n "$ids" ]] || { _ERR "no display controller found via lspci"; return 1; }

  local id
  for id in $ids; do
    case "$id" in
      8086) vendors+=" intel"  ;;   # Intel Corporation
      1002|1022) vendors+=" amd" ;; # ATI/AMD, and AMD's own vendor id
      10de) vendors+=" nvidia" ;;   # NVIDIA
      1af4|15ad|1234|80ee)
        # virtio-gpu / VMware SVGA / QEMU stdvga / VirtualBox. mesa's
        # generic KMS driver covers these; there is no vendor package, and
        # installing one would be wrong. vm-test.sh lands here.
        _OK "virtual GPU ($id) -- vendor-neutral mesa is correct, nothing to add"
        ;;
      *) _WARN "unrecognised display controller vendor id: $id" ;;
    esac
  done

  # Deduplicate: a dual-GPU laptop lists Intel twice on some firmware.
  vendors="$(printf '%s\n' $vendors | sort -u | tr '\n' ' ')"
  [[ -n "${vendors// /}" ]] || { _OK "no vendor driver set needed"; return 0; }
  _OK "GPU vendor(s) detected:${vendors% }"

  local v mod pkgs
  for v in $vendors; do
    mod="$mod_dir/graphics-$v.yaml"
    [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
    pkgs="$(_pkgs_from_module "$mod" | tr '\n' ' ')"
    [[ -n "${pkgs// /}" ]] || { _ERR "no packages parsed from $mod"; return 1; }
    run "yay -S --needed --noconfirm $pkgs"
  done

  # NVIDIA: nvidia-open-dkms only supports Turing (2018) and newer. On an
  # older card it builds and installs happily, then fails to bind at boot
  # -- you get a black screen or a fallback to modesetting with no
  # acceleration, which reads as "the dotfiles broke my machine".
  if [[ " $vendors " == *" nvidia "* ]]; then
    if ! lspci -d 10de: -k 2>/dev/null | grep -qiE 'TU[0-9]|GA[0-9]|AD[0-9]|GB[0-9]'; then
      _WARN "NVIDIA card may predate Turing; nvidia-open-dkms supports Turing+ only"
      _WARN "if X fails to start, swap it: sudo pacman -S nvidia-dkms"
    fi
  fi

  # Per-GPU picom flags. NVIDIA's proprietary GLX is the one stack where
  # picom's use-damage optimisation smears during animations; disabling it
  # costs a little GPU time and makes the motion match Intel and AMD.
  # Written per-machine and gitignored -- never committed.
  local gpu_env="$HOME/.config/picom/gpu.env"
  if [[ " $vendors " == *" nvidia "* ]]; then
    run "mkdir -p $(dirname "$gpu_env") && printf 'PICOM_GPU_FLAGS=\"--no-use-damage\"\\n' > $gpu_env"
  else
    run "mkdir -p $(dirname "$gpu_env") && printf 'PICOM_GPU_FLAGS=\"\"\\n' > $gpu_env"
  fi

  # CPU microcode. Not graphics, but the same "detected once, hardcoded
  # forever" bug: base.yaml has intel-ucode commented out, so a fresh
  # machine of either vendor got no microcode at all. Missing microcode is
  # the cause of hangs and errata that look like random instability.
  local cpu_vendor ucode
  cpu_vendor="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)"
  case "$cpu_vendor" in
    GenuineIntel) ucode=intel-ucode ;;
    AuthenticAMD) ucode=amd-ucode   ;;
    *) ucode="" ; _WARN "unknown CPU vendor '$cpu_vendor' -- no microcode installed" ;;
  esac
  [[ -n "$ucode" ]] && run "sudo pacman -S --needed --noconfirm $ucode"
}

step_boot_splash() {
  # Opt-in, and deliberately so: this edits /etc/mkinitcpio.conf and the
  # kernel cmdline and rebuilds the initramfs. Getting it wrong costs a
  # boot, which is a different category of risk from every other module
  # here -- so it never runs as part of a default install.
  local mod="$DOTFILES_DIR/.config/arch-config/modules/splash.yaml"
  local bs="$DOTFILES_DIR/.config/AtiScriptsV1/boot-splash"
  [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
  [[ -x "$bs" ]] || { _ERR "missing $bs"; return 1; }

  local pkgs; pkgs="$(_pkgs_from_module "$mod" | tr '\n' ' ')"
  run "sudo pacman -S --needed --noconfirm $pkgs"

  # The LTS rescue entries are rewritten WITHOUT quiet/splash (see the
  # token filter in step_boot_fallback), so a splashed boot that hangs can
  # always be diagnosed from the fallback entry.
  run "$bs enable"
}

step_dcli_sync_extra() {
  # modules/optional.yaml is deliberately NOT in hosts/*.yaml's
  # enabled_modules, so `dcli sync` ignores it entirely -- and dcli has no
  # per-module sync flag (see `dcli sync --help`). So read the package
  # list straight out of the yaml and hand it to the AUR helper. Keeping
  # the list in the yaml means it is still declared and reviewable in one
  # place, rather than duplicated into this script.
  local mod="$DOTFILES_DIR/.config/arch-config/modules/optional.yaml"
  [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
  local -a pkgs=()
  mapfile -t pkgs < <(_pkgs_from_module "$mod")
  (( ${#pkgs[@]} )) || { _ERR "no packages parsed from optional.yaml"; return 1; }
  # --needed so a re-run is a no-op instead of a reinstall.
  run "yay -S --needed --noconfirm ${pkgs[*]}"
}
step_cargo() {
  # rustup installs the stable toolchain but doesn't activate it as the
  # default -- every cargo/rustup invocation (this step, and any AUR
  # package built with cargo, e.g. paru/didyoumean) fails with "rustup
  # could not choose a version of cargo to run" until this is set once.
  command -v rustup >/dev/null && run "rustup default stable"
  command -v cargo >/dev/null && run "cargo install pomodoro-tui" || _WARN "cargo missing, skip"
}
step_ati_scripts()  { run "cd $DOTFILES_DIR/.config/AtiScriptsV1 && ./install.sh"; }
step_pacman_guard() {
  # Installs the PreTransaction hook that refuses a package operation when
  # / is too full to unpack safely. This has to be a pacman hook rather
  # than a dcli update_hook: dcli is third-party, and a dcli-only guard
  # disappears silently if its config format changes. A pacman hook runs
  # for dcli, yay, paru and bare pacman alike, with nothing to bypass.
  #
  # The script itself lives in AtiScriptsV1 and is symlinked into
  # /usr/local/bin by step_ati_scripts, so only the .hook needs placing.
  local hook="$DOTFILES_DIR/.config/arch-config/pacman-hooks/00-preflight.hook"
  if [[ ! -f "$hook" ]]; then
    _WARN "pacman preflight hook missing from repo — skipping"
    return 0
  fi
  # REFUSE, do not warn. The hook is AbortOnFail, so if Exec= points at a
  # missing binary then EVERY pacman transaction fails -- including the one
  # that would install the missing binary. That is an unbootstrappable box
  # from a single `--only=pacman-guard`. A warning is not enough when the
  # failure mode locks you out of the package manager.
  if (( ! DRY_RUN )) && [[ ! -x /usr/local/bin/pacman-preflight ]]; then
    _ERR "/usr/local/bin/pacman-preflight missing — refusing to install an"
    _ERR "AbortOnFail hook that would break every pacman transaction."
    _ERR "Run the ati-scripts module first:  ./wizard.sh --yes --only=ati-scripts"
    return 1
  fi
  run "sudo install -Dm644 $hook /etc/pacman.d/hooks/00-preflight.hook"
}
step_boot_fallback() {
  # Writes the boot menu entries that make `linux-lts` reachable, plus a
  # rescue entry backed by a full-module initramfs.
  #
  # Why the wizard generates these instead of copying arch-config/boot/*:
  # a boot entry is machine-specific. The root= line, the microcode image
  # and the ESP mount point differ per machine, and a stale PARTUUID gives
  # you an entry that looks fine in the menu and drops to an emergency
  # shell when you finally need it. Everything here is derived from the
  # RUNNING system: /proc/cmdline is authoritative (this machine boots a
  # UKI, so the shipped arch.conf options line is ignored and has been
  # wrong for months without anyone noticing).
  #
  # The copies in arch-config/boot/ are this machine's snapshot, kept for
  # reference and diffing -- they are not deployed.
  if ! command -v bootctl >/dev/null; then
    _WARN "bootctl missing — not a systemd-boot system, skipping LTS entries"; return 0
  fi
  local esp
  esp="$(sudo bootctl --print-esp-path 2>/dev/null)" || esp=""
  [[ -n "$esp" ]] || esp=/boot
  if ! sudo test -d "$esp/loader/entries"; then
    _WARN "$esp/loader/entries missing — systemd-boot not installed here, skipping"; return 0
  fi
  if ! sudo test -e "$esp/vmlinuz-linux-lts"; then
    _WARN "linux-lts not installed (no $esp/vmlinuz-linux-lts) — run the dcli-sync module first"
    return 0
  fi

  # Options straight off the running kernel. Anything else is a guess.
  local opts; opts="$(tr -d '\n' < /proc/cmdline)"
  # ...except quiet/splash, which are stripped deliberately.
  #
  # These entries exist to be picked when the normal boot has failed. A
  # rescue entry that inherits the boot splash shows a logo and a progress
  # bar while hiding the kernel messages that say what is wrong -- it looks
  # identical to the broken boot you are trying to escape. The boot-splash
  # module puts quiet+splash on the primary UKI entry only, and this is the
  # other half of that decision.
  # Filter tokens rather than pattern-delete: a single sed pass consumes the
  # separator, so adjacent options ("quiet splash") left the second one
  # behind and the rescue entry was still silent.
  opts="$(tr ' ' '\n' <<<"$opts" | grep -vxE 'quiet|splash' | paste -sd' ' -)"
  # Microcode is vendor-specific and optional; only reference what exists.
  local ucode_line=""
  local u
  for u in intel-ucode.img amd-ucode.img; do
    sudo test -e "$esp/$u" && ucode_line="initrd  /$u"
  done

  _DIM "  ESP $esp · options from /proc/cmdline"
  local ent="$esp/loader/entries"
  run "sudo tee $ent/arch-lts.conf >/dev/null << EOF
# Fallback kernel entry -- pick this at the boot menu when a \\\`linux\\\`
# upgrade leaves the system unbootable, and repair from here instead of
# hunting for an Arch ISO. Written by wizard.sh (boot-fallback module).
title   Arch Linux (LTS fallback)
linux   /vmlinuz-linux-lts
$ucode_line
initrd  /initramfs-linux-lts.img
options $opts
EOF"

  # Enable the fallback preset so the rescue initramfs actually exists.
  # pacman owns this file, so edit in place rather than overwriting it --
  # an overwrite would fight every linux-lts upgrade with a .pacnew.
  local preset=/etc/mkinitcpio.d/linux-lts.preset
  if sudo test -f "$preset"; then
    if sudo grep -q "^PRESETS=.*fallback" "$preset"; then
      _DIM "  fallback preset already enabled"
    else
      run "sudo sed -i \"s/^PRESETS=.*/PRESETS=('default' 'fallback')/\" $preset"
    fi
    # -S autodetect drops the autodetect hook: every module ships, not just
    # the ones probed on this machine. ~205MB, and worth it.
    sudo grep -q "^fallback_options" "$preset" \
      || run "echo \"fallback_options=\\\"-S autodetect\\\"\" | sudo tee -a $preset >/dev/null"
    run "sudo mkinitcpio -p linux-lts"
  else
    _WARN "$preset missing — skipping rescue initramfs"
  fi

  if (( DRY_RUN )) || sudo test -e "$esp/initramfs-linux-lts-fallback.img"; then
    run "sudo tee $ent/arch-lts-fallback.conf >/dev/null << EOF
# Last-resort rescue entry. Same LTS kernel as arch-lts.conf, but paired
# with the -fallback initramfs built WITHOUT autodetect, so it carries
# every module. Slower to boot, but it still comes up when the trimmed
# image is missing something. Written by wizard.sh (boot-fallback module).
title   Arch Linux (LTS rescue - all modules)
linux   /vmlinuz-linux-lts
$ucode_line
initrd  /initramfs-linux-lts-fallback.img
options $opts
EOF"
  else
    _WARN "rescue initramfs was not built — skipping the rescue entry"
  fi

  # A fallback entry you cannot select is not a fallback: systemd-boot
  # ships loader.conf with timeout commented out, which hides the menu.
  local lc="$esp/loader/loader.conf"
  if sudo test -f "$lc" && ! sudo grep -qE '^timeout[[:space:]]+[0-9]+' "$lc"; then
    run "echo 'timeout 5' | sudo tee -a $lc >/dev/null"
  fi
  (( DRY_RUN )) || _DIM "  verify with: bootctl list"
}
step_touchpad()     { run "sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null << 'EOF'
Section \"InputClass\"
    Identifier \"Touchpad\"
    MatchIsTouchpad \"on\"
    Driver \"libinput\"
    Option \"Tapping\" \"on\"
EndSection
EOF"; }
step_xinit() {
  local xrc="$HOME/.xinitrc"
  if (( DRY_RUN )); then _DIM "  [dry] write $xrc + chmod +x"; return; fi
  cat >"$xrc" <<'XINIT_EOF'
#!/bin/sh
# ===============================
# XINITRC – QTILE (STABLE BUILD)
# ===============================
unset SESSION_MANAGER
setxkbmap -layout us -option
[ -f "$HOME/.Xmodmap" ] && xmodmap "$HOME/.Xmodmap"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=qtile
export XDG_SESSION_DESKTOP=qtile
systemctl --user import-environment DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP QT_QPA_PLATFORMTHEME
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP QT_QPA_PLATFORMTHEME 2>/dev/null
fi
# Qt apps (telegram-desktop etc) ignore the GTK theme entirely. Without
# a platform theme Qt uses its built-in LIGHT palette, so they render
# white on the dark desktop. qt6ct/qt5ct read the palette theme-apply
# generates into ~/.config/qt6ct/colors/current.conf.
export QT_QPA_PLATFORMTHEME=qt6ct
# Cursor size + theme for X apps (Xcursor honors both env vars).
export XCURSOR_SIZE=24
export XCURSOR_THEME=breeze_cursors
# Size the UI to whatever display is actually attached, BEFORE xrdb merges
# .Xresources (ui-scale writes Xft.dpi into it) and before qtile reads
# ~/.cache/qtile/ui_scale. Docking to an external monitor between sessions
# changes the answer, so this runs every login rather than once at install.
command -v ui-scale >/dev/null 2>&1 && ui-scale >/dev/null 2>&1
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name left_ptr
xset s off -dpms
if [ -f "$HOME/.cache/wall" ] && command -v xwallpaper >/dev/null 2>&1; then
  wall_path="$(readlink -f "$HOME/.cache/wall")"
  [ -f "$wall_path" ] && xwallpaper --stretch "$wall_path" &
fi
if command -v picom >/dev/null 2>&1; then
  pkill -x picom 2>/dev/null
  # Per-GPU flags written by the wizard's `gpu` module; see step_gpu.
  # Absent file = no flags, which is correct for Intel and AMD.
  PICOM_GPU_FLAGS=""
  [ -f "$HOME/.config/picom/gpu.env" ] && . "$HOME/.config/picom/gpu.env"
  # shellcheck disable=SC2086
  picom $PICOM_GPU_FLAGS &
fi
# Tray icons -- Systray widget is passive, needs something to register.
command -v blueman-applet >/dev/null 2>&1 && blueman-applet &
# --no-agent so nm-applet stays a tray icon and never shows its own
# password dialog -- the qtile WiFi popup (Mod+p n) does the asking.
command -v nm-applet >/dev/null 2>&1 && nm-applet --no-agent &
# copyq_rofi needs copyq's background server running to have any
# clipboard history to query -- --start-server avoids popping its
# window open on every login.
command -v copyq >/dev/null 2>&1 && copyq --start-server &
exec qtile start
XINIT_EOF
  chmod +x "$xrc"
}

step_xresources() {
  local xres="$HOME/.Xresources"
  if (( DRY_RUN )); then _DIM "  [dry] write $xres + xrdb -merge"; return; fi
  # Preserve existing content, only replace the Xcursor block managed
  # here. Marker-guarded so re-runs are idempotent.
  local marker_begin="! BEGIN-WIZARD-XCURSOR"
  local marker_end="! END-WIZARD-XCURSOR"
  local block="$marker_begin
Xcursor.size: 24
Xcursor.theme: breeze_cursors
$marker_end"
  touch "$xres"
  if grep -q "$marker_begin" "$xres" 2>/dev/null; then
    # Replace existing block (portable sed via python for safety).
    python3 - "$xres" "$marker_begin" "$marker_end" "$block" <<'PY'
import sys, re
path, mb, me, block = sys.argv[1:5]
src = open(path).read()
pat = re.compile(re.escape(mb) + r'.*?' + re.escape(me), re.DOTALL)
open(path, 'w').write(pat.sub(block, src, count=1))
PY
  else
    printf '\n%s\n' "$block" >>"$xres"
  fi
  command -v xrdb >/dev/null 2>&1 && xrdb -merge "$xres" 2>/dev/null || true
}

step_xmodmap() {
  local xmm="$HOME/.Xmodmap"
  if (( DRY_RUN )); then _DIM "  [dry] write $xmm"; return; fi
  cat >"$xmm" <<'XMM_EOF'
! Caps physical key acts purely as Alt_L -- no tap-to-Caps-Lock fallback,
! by design (Alt is broken in hardware on this laptop, see config.py's
! `mod = "mod4"` comment; Caps is fully repurposed as the only working Alt).
clear lock
clear mod1
keycode 66 = Alt_L
add mod1 = Alt_L Alt_R
XMM_EOF
}
step_lid()          { run "sudo sed -i 's/^#\\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf && sudo systemctl restart systemd-logind"; }
                    # VIPS_WARNING now ships as a tracked fish conf.d snippet
                    # (.config/fish/conf.d/vips.fish) instead of being appended
                    # to ~/.profile: that line was fish syntax in a POSIX file,
                    # so fish never read it and sh read `set -x` as xtrace.
                    # Strip the old broken line if a previous run added it.
step_image_envs()   { run "sed -i '/VIPS_WARNING/d' $HOME/.profile 2>/dev/null || true"
                      # fish_variables (versioned) pins TMPDIR to ~/tmp for psub/mktemp
                      # (starship init, pyenv init) -- must exist or fish startup breaks.
                      run "mkdir -p $HOME/tmp"; }
step_flatpak()      { _OK "Nothing to install — flatpak/collector replaced by qdrop"; }
step_piper() {
  local dir="$HOME/.config/piper-voices"
  run "mkdir -p $dir"
  local files=(
    en/en_US/ryan/high/en_US-ryan-high.onnx
    en/en_US/ryan/high/en_US-ryan-high.onnx.json
    de/de_DE/thorsten/high/de_DE-thorsten-high.onnx
    de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json
  )
  for f in "${files[@]}"; do
    local fname; fname=$(basename "$f")
    (( DRY_RUN )) && { _DIM "  [dry] curl piper $fname (retry x3)"; continue; }
    [[ -f "$dir/$fname" ]] && continue
    retry_net 3 5 curl -fsSL -o "$dir/$fname" "https://huggingface.co/rhasspy/piper-voices/resolve/main/$f" || \
      { _ERR "piper $fname failed after 3 retries"; return 1; }
  done
}

step_whisper() {
  local dir="$HOME/.local/share/whisper"
  run "mkdir -p $dir"
  # base.en: voice_dictate_live (Super+Shift+V) -- fast enough to feel
  # instant on modest hardware, traded for lower accuracy.
  # small.en: voice_dictate (Super+Shift+B) -- much more accurate, not
  # instant. Benchmarked repeatedly on a weak 2-core CPU: small.en runs
  # ~4x slower than real-time even with the fast build below and GPU
  # offload, so it's kept for batch (manual stop) dictation only, not
  # the live mode.
  for model in ggml-base.en.bin ggml-small.en.bin; do
    local out="$dir/$model"
    if (( DRY_RUN )); then _DIM "  [dry] curl whisper $model (retry x3)"; continue; fi
    [[ -f "$out" ]] && continue
    retry_net 3 10 curl -fL --retry 3 --continue-at - -o "$out" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model" || \
      { _ERR "whisper model $model download failed after 3 retries"; return 1; }
  done
}

step_whisper_fast() {
  # whisper.cpp-git's PKGBUILD builds with `-D CMAKE_BUILD_TYPE=None` --
  # no optimization flags at all, no -march=native. Measured on this
  # hardware: encoding 2s of audio took 28s with the pacman-built
  # whisper-cli vs 2.1s with a Release build of the identical source/
  # model -- a ~13x slowdown, present in every binary the package ships.
  # It also doesn't build whisper-stream at all (needs -DWHISPER_SDL2=ON,
  # which the PKGBUILD doesn't pass), and voice_dictate_live needs
  # whisper-stream patched with patches/whisper-stream-poll-ms.patch
  # (adds --poll-ms/--vad-tail-ms, hardcoded upstream with no CLI flag).
  #
  # Builds both from the whisper.cpp-git AUR package's own cached source
  # (already fetched by dcli-sync/yay) and shadows the slow system
  # binaries via /usr/local/bin (already earlier in $PATH than /usr/bin)
  # + /usr/local/lib/whisper-cpp (registered through /etc/ld.so.conf.d,
  # so they keep working even if the yay cache is later cleared). See
  # .config/AtiScriptsV1/patches/README.md for the full writeup.
  local src="$HOME/.cache/yay/whisper.cpp-git/src/whisper.cpp-git"
  local patch="$DOTFILES_DIR/.config/AtiScriptsV1/patches/whisper-stream-poll-ms.patch"
  local build="$src/build-fast"
  local libdir="/usr/local/lib/whisper-cpp"

  if (( DRY_RUN )); then
    _DIM "  [dry] build whisper-cli + whisper-stream (Release, patched) from AUR cache, shadow via /usr/local"
    return
  fi

  if [[ ! -d "$src" ]]; then
    _ERR "whisper.cpp-git source not found at $src -- run dcli-sync first (declares whisper.cpp-git)"
    return 1
  fi

  # Idempotent: skip the (slow, few-minute) rebuild if already shadowed.
  # Checked via the patched --poll-ms flag rather than ldd against
  # $libdir: RUNPATH prefers whichever path resolves first, and an
  # earlier build's cache dir resolving fine (same file contents either
  # way) doesn't mean it's still pointed at $libdir specifically.
  if /usr/local/bin/whisper-stream --help 2>&1 | grep -q -- "--poll-ms"; then
    _OK "whisper-cli/whisper-stream already built + shadowed via /usr/local"
    return
  fi

  # --poll-ms/--vad-tail-ms not already in stream.cpp -> patch not
  # applied yet on this checkout of the AUR cache.
  if ! grep -q -- "--poll-ms" "$src/examples/stream/stream.cpp" 2>/dev/null; then
    run "cd $src && git apply $patch"
  fi
  run "cmake -S $src -B $build -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release -W no-dev"
  run "cmake --build $build --target whisper-cli whisper-stream -j$(nproc)"
  run "sudo mkdir -p $libdir"
  run "sudo cp $build/bin/lib*.so* $libdir/"
  run "echo $libdir | sudo tee /etc/ld.so.conf.d/whisper-cpp.conf >/dev/null"
  run "sudo ldconfig"
  run "sudo install -Dm755 $build/bin/whisper-cli /usr/local/bin/whisper-cli"
  run "sudo install -Dm755 $build/bin/whisper-stream /usr/local/bin/whisper-stream"
}

step_mic_gain() {
  # WirePlumber applies its own default ALSA mixer levels to hardware
  # nodes on every session start -- Capture + Internal Mic Boost both
  # reset to 100%/100% here (~60dB combined), enough to saturate the mic
  # into constant distorted noise even in a quiet room, independent of
  # and overriding whatever `alsactl restore` set moments earlier.
  # fix-mic-gain.service (After=wireplumber.service, symlinked live from
  # .config/systemd/user/) reasserts sane levels every login; this just
  # enables it once.
  if (( DRY_RUN )); then _DIM "  [dry] systemctl --user enable --now fix-mic-gain.service"; return; fi
  run "systemctl --user daemon-reload"
  run "systemctl --user enable --now fix-mic-gain.service"
}
step_nopasswd()     { run "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/zz-$(id -un)-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-$(id -un)-nopasswd"; }
step_ownership()    { run "sudo chown -R $(id -un):$(id -un) $DOTFILES_DIR"; }
step_login_shell() {
  # kitty.conf hardcodes `shell /usr/bin/fish`, so inside X you always got
  # fish -- but the TTY kept the account's login shell (bash by default).
  # Everything defined in config.fish (the `letsgo` startx helper, aliases,
  # abbreviations) was therefore missing exactly where you need it most:
  # the TTY you drop to when X dies. chsh makes the two agree.
  local target="/usr/bin/fish"
  if [[ ! -x "$target" ]]; then
    _DIM "  fish not installed yet — skipping (run after dcli sync)"
    return 0
  fi
  if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" == "$target" ]]; then
    _OK "login shell already fish"
    return 0
  fi
  # chsh refuses any shell missing from /etc/shells.
  grep -qx "$target" /etc/shells || run "echo $target | sudo tee -a /etc/shells >/dev/null"
  run "sudo chsh -s $target $(id -un)"
}
step_disable_dm()   { for dm in lightdm gdm sddm lxdm; do run "sudo systemctl disable $dm.service 2>/dev/null || true"; done; }
step_candy()        { [[ -d /usr/share/icons/candy-icons ]] && { _OK "candy-icons present"; return; }
                      run "cd /tmp && rm -rf master.zip candy-icons-master && wget -q https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip && unzip -qo master.zip && sudo mv candy-icons-master /usr/share/icons/candy-icons"; }
# Your own fork, not upstream. theme-apply's `wal` mode derives an entire
# palette from the current wallpaper, so the wallpaper set is not
# decoration -- it is an input to how the desktop looks. Pointing at
# someone else's repo means they can add, remove or re-encode an image and
# change your colours; a fork you control cannot move under you.
WALLPAPERS_REPO="${WALLPAPERS_REPO:-https://github.com/Mohamedattiadev/wallpapers}"
step_wallpapers()   { [[ -d $HOME/Pictures/Wallpapers/.git ]] && { _OK "wallpapers present"; return; }
                      run "rm -rf $HOME/Pictures/Wallpapers && mkdir -p $HOME/Pictures && git clone $WALLPAPERS_REPO $HOME/Pictures/Wallpapers"; }
step_speed()        { run "$DOTFILES_DIR/installScripts/speed_boost.sh"; }
step_themes() {
  run "sudo pacman -S --needed --noconfirm python-pywal python-pillow papirus-icon-theme jq"
  # Seed eww colors.scss from .tmpl so first theme-apply resolves.
  local eww_tmpl="$HOME/.config/eww/colors.scss.tmpl"
  local eww_out="$HOME/.config/eww/colors.scss"
  [[ -f "$eww_tmpl" && ! -f "$eww_out" ]] && run "cp $eww_tmpl $eww_out"
  # Seed qutebrowser homepage.html from .tmpl (gitignored — regenerated
  # per palette by theme-apply, needs a stable skeleton first).
  local qb_tmpl="$HOME/.config/qutebrowser/html/homepage.html.tmpl"
  local qb_out="$HOME/.config/qutebrowser/html/homepage.html"
  [[ -f "$qb_tmpl" && ! -f "$qb_out" ]] && run "cp $qb_tmpl $qb_out"
  # Seed default wallpaper if none set.
  if [[ ! -f "$HOME/.cache/wall" ]]; then
    local first
    first=$(find "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -1) || true
    [[ -n "$first" ]] && run "mkdir -p $HOME/.cache && ln -sfn $first $HOME/.cache/wall"
  fi
  run "wal-precompile"
  run "theme-apply doomone"
}
step_dark_mode() {
  # Make the desktop advertise a dark colour-scheme *preference* rather than
  # forcing dark on rendered output.
  #
  # Why this module exists: with no preference set, xdg-desktop-portal reports
  # `org.freedesktop.appearance color-scheme = 0` ("no preference"). Chromium
  # reads exactly that key, so every site was served its LIGHT stylesheet — and
  # the workaround was `--enable-features=WebContentsForceDark` in the
  # *-flags.conf files, which re-tints already-rendered pixels and mangles any
  # site that ships a real dark theme (see TROUBLESHOOTING.md).
  #
  # Setting the preference properly makes sites serve the dark CSS their own
  # designers wrote, so force-dark is no longer needed anywhere.
  #
  # GTK3/GTK4 settings.ini already carry gtk-application-prefer-dark-theme;
  # this covers the gsettings/portal channel, which is the one Chromium,
  # Electron and libadwaita apps actually consult.
  if ! command -v gsettings >/dev/null; then
    _WARN "gsettings missing (glib2) — cannot set colour-scheme preference"; return 0
  fi
  run "gsettings set org.gnome.desktop.interface color-scheme prefer-dark"
  (( DRY_RUN )) && return 0

  # Verify through the portal rather than trusting the write: if
  # xdg-desktop-portal-gtk is not installed, gsettings succeeds and browsers
  # still see "no preference" — a silent failure that looks exactly like the
  # bug this module fixes.
  local scheme
  scheme=$(busctl --user call org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.portal.Settings \
    ReadOne ss org.freedesktop.appearance color-scheme 2>/dev/null) || scheme=""
  case "$scheme" in
    *"u 1"*) _OK "portal reports prefer-dark — sites will serve their own dark theme" ;;
    "")      _WARN "portal not answering (install xdg-desktop-portal + xdg-desktop-portal-gtk); browsers may still see light" ;;
    *)       _WARN "portal still reports '$scheme' — restart xdg-desktop-portal or re-login" ;;
  esac
}
step_browser_flags() {
  # Authoritative, not additive: older installs of these dotfiles shipped
  # `--enable-features=WebContentsForceDark` in every *-flags.conf. That flag
  # is now wrong (step_dark_mode replaces it), so strip it on upgrade instead
  # of only appending what is missing — otherwise an existing machine keeps
  # the broken dark rendering forever while a fresh clone comes up correct.
  #
  # Files under ~/.config are stow symlinks into the repo, so edit through
  # them carefully: sed -i on a symlink replaces the link with a regular file
  # and silently detaches the machine from the repo. Resolve first, and skip
  # anything that already points into ~/.dotfiles (the repo copy is correct).
  local f cfg real
  for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
    cfg="$HOME/.config/$f"
    [[ -e "$cfg" ]] || { run "cp $DOTFILES_DIR/.config/$f $cfg"; continue; }
    real="$(readlink -f "$cfg")"
    if [[ "$real" == "$DOTFILES_DIR"/* ]]; then
      _DIM "  $f → repo copy (already correct)"
      continue
    fi
    # Plain file: repair in place.
    #
    # Anchor on a real flag line (`^--`), not a bare substring match: these
    # files now carry comments that *name* WebContentsForceDark to explain why
    # it is gone, and a loose `/WebContentsForceDark/d` would delete the
    # explanation along with the flag.
    if grep -qE '^\s*--[^ ]*WebContentsForceDark' "$real" 2>/dev/null; then
      # Drop the whole line only when force-dark is the sole feature on it.
      # `--enable-features` takes a comma-separated list, so if the user added
      # others alongside it, delete just that one token and keep the rest.
      run "sed -i -E \
        -e 's/,WebContentsForceDark//g' \
        -e 's/WebContentsForceDark,//g' \
        -e '/^\s*--enable-features=\s*\$/d' \
        -e '/^\s*--[^ ]*WebContentsForceDark\s*\$/d' \
        $real"
      _OK "$f: removed WebContentsForceDark (see dark-mode module)"
    fi
    grep -q -- '--load-extension=' "$real" 2>/dev/null \
      || run "echo '--load-extension=$HOME/.config/qtile/browser-theme' >> $real"
    grep -q -- '--process-per-site' "$real" 2>/dev/null \
      || run "echo '--process-per-site' >> $real"
  done
}
step_browser_memory() {
  # Turn on Memory Saver for every Chromium-family browser, by policy.
  #
  # Why policy and not a flag: Memory Saver is a *preference*, so a flag in
  # *-flags.conf cannot set it and a manual toggle in Settings is lost the
  # moment a profile is reset. A managed policy applies on every launch and
  # ships with the dotfiles, which is the point of this repo.
  #
  # What it buys: measured on the 8G laptop, Brave held 2933MB across 13
  # renderer processes to show 6 windows -- most of them idle background tabs
  # sitting on a full heap. Memory Saver discards an inactive tab's renderer
  # outright and reloads it when you click back. This is the same "Make Brave
  # faster" prompt the browser nags about, made declarative.
  #
  # TabDiscardingExceptions matters as much as the saving. A discarded tab
  # stops executing, so anything holding a socket to notify you goes quiet.
  # WhatsApp Web is the reason the exception list exists -- discarding the
  # qtile scratchpad would silently stop message notifications.
  #
  # Policy directories differ per browser and are not guesses:
  #   brave    -> /etc/brave/policies/managed        (strings /opt/brave-bin/brave)
  #   chromium -> /etc/chromium/policies/managed
  #   chrome   -> /etc/opt/chrome/policies/managed
  local src="$DOTFILES_DIR/.config/arch-config/browser-policies/50-memory-saver.json"
  if [[ ! -f "$src" ]]; then
    _WARN "browser policy file missing from repo — skipping"; return 0
  fi
  # Fail loudly on malformed JSON rather than installing a file every browser
  # will silently ignore.
  if (( ! DRY_RUN )) && ! python3 -m json.tool "$src" >/dev/null 2>&1; then
    _ERR "50-memory-saver.json is not valid JSON"; return 1
  fi
  local d
  for d in /etc/brave/policies/managed \
           /etc/chromium/policies/managed \
           /etc/opt/chrome/policies/managed; do
    run "sudo install -Dm644 $src $d/50-memory-saver.json"
  done
  _DIM "  verify at brave://policy — all four entries should read OK"
}
step_chrome_policy() {
  local pem="$HOME/.config/qtile/browser-theme.pem"
  local key="$HOME/.config/qtile/browser-theme.key"
  local crx="$HOME/.config/qtile/browser-theme.crx"
  local upd="$HOME/.config/qtile/browser-theme-updates.xml"
  local ext="$HOME/.config/qtile/browser-theme"
  run "mkdir -p $ext"
  # Sign key (per-machine, gitignored).
  if [[ ! -f "$pem" ]]; then
    run "openssl genrsa -out $pem 2048 2>/dev/null && chmod 600 $pem"
  fi
  run "openssl rsa -in $pem -pubout -outform DER 2>/dev/null | base64 -w0 > $key"
  # Extension id from pubkey.
  local ext_id
  if (( DRY_RUN )); then
    ext_id="<computed_from_pem>"
    _DIM "  [dry] ext_id = sha256(pubkey)[:32] → maps a-p"
  else
    ext_id=$(python3 -c "
import hashlib, base64
k = open('$key').read()
h = hashlib.sha256(base64.b64decode(k)).hexdigest()[:32]
print(''.join(chr(ord('a')+int(c,16)) for c in h))
")
  fi
  # Pack + updates.xml.
  local cbin=""
  for c in /opt/google/chrome/chrome /usr/bin/chromium /opt/brave-bin/brave; do
    [[ -x "$c" ]] && { cbin="$c"; break; }
  done
  [[ -n "$cbin" && -f "$ext/manifest.json" ]] && \
    run "$cbin --pack-extension=$ext --pack-extension-key=$pem --no-message-box >/dev/null 2>&1 || true"
  if [[ -f "$ext/manifest.json" ]]; then
    local ver
    if (( DRY_RUN )); then ver="<from-manifest.json>"
    else ver=$(python3 -c "import json;print(json.load(open('$ext/manifest.json'))['version'])"); fi
    if (( DRY_RUN )); then
      _DIM "  [dry] write $upd (updatecheck version=$ver)"
    else
      cat >"$upd" <<POLICY_EOF
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$ext_id'>
    <updatecheck codebase='file://$crx' version='$ver' />
  </app>
</gupdate>
POLICY_EOF
    fi
  fi
  # Sudo write chrome + chromium policies.
  local policy_json="{
  \"ExtensionSettings\": {
    \"$ext_id\": {
      \"installation_mode\": \"force_installed\",
      \"update_url\": \"file://$upd\",
      \"toolbar_pin\": \"default_unpinned\"
    }
  },
  \"ExtensionInstallSources\": [\"file:///*\"]
}"
  run "sudo mkdir -p /etc/opt/chrome/policies/managed /etc/chromium/policies/managed"
  if (( DRY_RUN )); then
    _DIM "  [dry] sudo tee /etc/opt/chrome/policies/managed/wal-theme.json"
    _DIM "  [dry] sudo tee /etc/chromium/policies/managed/wal-theme.json"
  else
    printf '%s' "$policy_json" | sudo tee /etc/opt/chrome/policies/managed/wal-theme.json >/dev/null
    printf '%s' "$policy_json" | sudo tee /etc/chromium/policies/managed/wal-theme.json >/dev/null
  fi
}

# ─── PREFLIGHT / RESILIENCE ──────────────────────────────────────────
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
  # is whisper models + the fast rebuild + wallpapers + a full dcli sync;
  # `--only=stow,paths` downloads none of that, and demanding 10 GB for it
  # blocked the container smoke test and any config-only re-run on a full
  # disk. Refusing for a reason that does not apply to this run is just a
  # false negative, and false negatives are how safety checks get bypassed.
  local _need_gb=1 _heavy _heavy_sel=0
  for _heavy in dcli-sync dcli-sync-extra whisper whisper-fast piper wallpapers candy-icons speed; do
    if [[ -n "$ONLY_LIST" ]]; then
      _id_in_csv "$ONLY_LIST" "$_heavy" && _heavy_sel=1
    elif [[ -n "$SKIP_LIST" ]]; then
      _id_in_csv "$SKIP_LIST" "$_heavy" || _heavy_sel=1
    else
      _heavy_sel=1
    fi
  done
  (( _heavy_sel )) && _need_gb=10
  _check "disk free > ${_need_gb} GB on \$HOME" "[[ $(df -Pk $HOME | awk 'NR==2{print $4}') -gt $((_need_gb * 1048576)) ]]" "this run needs ~${_need_gb}GB (10GB covers piper 60MB + whisper models+fast-build ~1GB + dcli pkgs + wallpapers; 1GB when none of those are selected)"
  _check "RAM ≥ 2 GB"                  "[[ $(awk '/MemTotal/{print $2}' /proc/meminfo) -gt 2000000 ]]" "wizard pulls 500MB+ concurrently — <2GB risks OOM/freeze"
  _check "pacman db lock clear"        "_pacman_lock_check"                        "another pacman may be running"
  if (( fatal )); then
    echo
    _ERR "Preflight failed. Fix the above and re-run."
    exit 1
  fi
  echo
  _OK "All preflight checks passed."
  sleep 1
}

# ─── UNINSTALL FUNCTIONS ─────────────────────────────────────────────
# Each reverses what its step_* wrote. Package installs, dcli syncs,
# and downloaded models are NEVER touched — those may be shared with
# other user workflows. Only removes files/policies wizard authored.
# Idempotent: safe to run twice.

uninstall_xinit()            { run "rm -f $HOME/.xinitrc"; }
uninstall_xmodmap()          { run "rm -f $HOME/.Xmodmap"; }
# .Xresources is NOT deleted: step_xresources appends a marker-guarded
# block to a file the user may own. Strip only our block.
uninstall_xresources()       { run "sed -i '/^! BEGIN-WIZARD-XCURSOR\$/,/^! END-WIZARD-XCURSOR\$/d' $HOME/.Xresources 2>/dev/null || true"; }
uninstall_image_envs()       { run "sed -i '/VIPS_WARNING/d' $HOME/.profile 2>/dev/null || true"; }
uninstall_touchpad()         { run "sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf"; }
uninstall_pacman_guard()     { run "sudo rm -f /etc/pacman.d/hooks/00-preflight.hook"; }
uninstall_boot_fallback() {
  # Removes the entries and the ~205MB rescue image, and puts the preset
  # back to what linux-lts ships. The linux-lts PACKAGE is left alone --
  # it is declared in base.yaml and other things may want it.
  local esp
  esp="$(sudo bootctl --print-esp-path 2>/dev/null)" || esp=""
  [[ -n "$esp" ]] || esp=/boot
  run "sudo rm -f $esp/loader/entries/arch-lts.conf $esp/loader/entries/arch-lts-fallback.conf"
  run "sudo rm -f $esp/initramfs-linux-lts-fallback.img"
  local preset=/etc/mkinitcpio.d/linux-lts.preset
  sudo test -f "$preset" \
    && run "sudo sed -i \"s/^PRESETS=.*/PRESETS=('default')/\" $preset"
  # loader.conf timeout is left in place: hiding the boot menu again would
  # be a strictly worse system, and it is not exclusively ours.
  return 0
}
uninstall_login_shell()      { run "sudo chsh -s /usr/bin/bash $(id -un)"; }
uninstall_passwordless_sudo(){ run "sudo rm -f /etc/sudoers.d/zz-$(id -un)-nopasswd"; }
uninstall_browser_flags() {
  for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
    run "sed -i '/--load-extension=.*browser-theme/d' $HOME/.config/$f 2>/dev/null || true"
  done
}
uninstall_dark_mode() {
  # Back to "no preference" rather than forcing prefer-light: light would be
  # a different opinion, not a reversal. `gsettings reset` restores whatever
  # the schema default is, which is what the box looked like before us.
  command -v gsettings >/dev/null || return 0
  run "gsettings reset org.gnome.desktop.interface color-scheme"
}
uninstall_browser_memory() {
  # Drop only our own policy file. The managed/ directories are shared with
  # any other policy the user (or another package) installed, so removing
  # the directory itself would take those with it.
  local d
  for d in /etc/brave/policies/managed \
           /etc/chromium/policies/managed \
           /etc/opt/chrome/policies/managed; do
    run "sudo rm -f $d/50-memory-saver.json"
  done
}
uninstall_chrome_policy() {
  # Derive the extension id BEFORE deleting the pem below. The id is
  # sha256(DER pubkey)[:32] mapped a-p, so it is a function of this
  # machine's signing key -- a hardcoded literal would point at some
  # other key's extension and leave the real one installed forever.
  local ext=""
  if [[ -f "$HOME/.config/qtile/browser-theme.pem" ]]; then
    ext=$(openssl rsa -in "$HOME/.config/qtile/browser-theme.pem" -pubout -outform DER 2>/dev/null |
      python3 -c "
import hashlib, sys
h = hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:32]
print(''.join(chr(ord('a') + int(c, 16)) for c in h))
" 2>/dev/null) || true
  fi
  run "sudo rm -f /etc/opt/chrome/policies/managed/wal-theme.json /etc/chromium/policies/managed/wal-theme.json"
  run "rm -f $HOME/.config/qtile/browser-theme.pem $HOME/.config/qtile/browser-theme.key $HOME/.config/qtile/browser-theme.crx $HOME/.config/qtile/browser-theme-updates.xml"
  # Guard: an empty id would expand to the whole Extensions directory.
  if [[ -n "$ext" ]]; then
    for base in "$HOME/.config/google-chrome/Default" "$HOME/.config/chromium/Default"; do
      [[ -d "$base" ]] && run "rm -rf $base/Extensions/$ext"
    done
  fi
}
uninstall_ati_scripts() {
  # Remove every AtiScriptsV1 script from /usr/local/bin.
  local ati="$DOTFILES_DIR/.config/AtiScriptsV1"
  [[ -d "$ati" ]] || return 0
  for f in "$ati"/*; do
    [[ -f "$f" ]] || continue
    local n; n=$(basename "$f")
    [[ "$n" == install.sh ]] && continue
    run "sudo rm -f /usr/local/bin/$n"
  done
}
uninstall_stow() {
  # `stow -D` unlinks the symlinks stow deployed.
  run "cd $DOTFILES_DIR && stow -D -t $HOME . 2>/dev/null || true"
}
uninstall_candy_icons()      { run "sudo rm -rf /usr/share/icons/candy-icons"; }
uninstall_lid() {
  # Restore defaults (Handle*Switch commented out).
  run "sudo sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=suspend/; s/^HandleLidSwitchExternalPower=ignore/#HandleLidSwitchExternalPower=suspend/; s/^HandleLidSwitchDocked=ignore/#HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf"
  run "sudo systemctl restart systemd-logind"
}
uninstall_themes() {
  # Remove generated caches only, keep any user-selected wallpaper.
  run "rm -rf $HOME/.cache/qtile/palettes $HOME/.cache/wal"
  run "rm -f $HOME/.config/eww/colors.scss"
}
# No-op uninstalls (installer step is safe to leave in place, or
# reversing it would harm the user's system).
uninstall_sanity()            { :; }
uninstall_bootstrap()         { :; }  # do NOT pacman -R base-devel
uninstall_yay()               { :; }
uninstall_dcli()              { :; }
uninstall_dcli_sync()         { :; }
uninstall_dcli_sync_extra()   { :; }  # never removes packages, same as dcli_sync
uninstall_boot_splash() {
  # This one MUST really reverse: leaving the plymouth hook in the
  # initramfs after removing the theme boots to a black screen.
  local bs
  bs="$(command -v boot-splash || echo "$DOTFILES_DIR/.config/AtiScriptsV1/boot-splash")"
  [[ -x "$bs" ]] && run "$bs disable" || _WARN "boot-splash not found — cmdline may still say quiet splash"
}
uninstall_paths()             { :; }  # removing them would leave the browser theme and GTK overlay with no config at all
uninstall_ui_scale() {
  run "rm -f $HOME/.cache/qtile/ui_scale $HOME/.cache/qtile/ui_scale.pinned"
  run "sed -i '/^! BEGIN-UI-SCALE\$/,/^! END-UI-SCALE\$/d' $HOME/.Xresources 2>/dev/null || true"
}
uninstall_picom_pin()         { :; }  # removing the compositor mid-session leaves a bare desktop
uninstall_githooks() { run "rm -f $DOTFILES_DIR/.git/hooks/pre-commit"; }
uninstall_gpu() {
  # Removing a GPU driver mid-session is how you end up with no X on next
  # boot, so packages stay. Only the generated picom override is reversed.
  run "rm -f $HOME/.config/picom/gpu.env"
}
uninstall_cargo()             { :; }
uninstall_arch_config()       { :; }
uninstall_flatpak()           { :; }
uninstall_piper()             { :; }  # models may be shared
uninstall_whisper()           { :; }  # models may be shared
uninstall_whisper_fast()      { :; }  # leave the fast binaries in place -- reverting to the ~13x slower pacman ones helps no one
uninstall_mic_gain() {
  run "systemctl --user disable --now fix-mic-gain.service" || true
}
uninstall_wallpapers()        { :; }  # user's picture collection
uninstall_ownership()         { :; }
uninstall_disable_dm()        { :; }
uninstall_speed()             { :; }

# Register uninstaller commands per module id.
declare -A UMOD_CMD
UMOD_CMD[sanity]="uninstall_sanity"
UMOD_CMD[bootstrap]="uninstall_bootstrap"
UMOD_CMD[yay]="uninstall_yay"
UMOD_CMD[dcli]="uninstall_dcli"
UMOD_CMD[stow]="uninstall_stow"
UMOD_CMD[arch-config]="uninstall_arch_config"
UMOD_CMD[dcli-sync]="uninstall_dcli_sync"
UMOD_CMD[cargo]="uninstall_cargo"
UMOD_CMD[ati-scripts]="uninstall_ati_scripts"
UMOD_CMD[pacman-guard]="uninstall_pacman_guard"
UMOD_CMD[boot-fallback]="uninstall_boot_fallback"
UMOD_CMD[login-shell]="uninstall_login_shell"
UMOD_CMD[touchpad]="uninstall_touchpad"
UMOD_CMD[xinit]="uninstall_xinit"
UMOD_CMD[xresources]="uninstall_xresources"
UMOD_CMD[xmodmap]="uninstall_xmodmap"
UMOD_CMD[lid]="uninstall_lid"
UMOD_CMD[image-envs]="uninstall_image_envs"
UMOD_CMD[flatpak]="uninstall_flatpak"
UMOD_CMD[piper]="uninstall_piper"
UMOD_CMD[whisper]="uninstall_whisper"
UMOD_CMD[whisper-fast]="uninstall_whisper_fast"
UMOD_CMD[mic-gain]="uninstall_mic_gain"
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
  ( set +e; "$cmd" >"$logf" 2>"$errf" ) &
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
arm_onboarding() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/atidots"
  if (( UNINSTALL )); then
    rm -f "$state_dir/onboarding.pending"
    return
  fi
  mkdir -p "$state_dir" || return
  rm -f "$state_dir/onboarding.done"
  : >"$state_dir/onboarding.pending"
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
  _INFO "  · Update system:           dcli sync"
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
  page_finale
}

main "$@"
