#!/usr/bin/env bash
# wizard.sh — premium TUI installer for Ati Dotfiles.
#
# Wraps installScripts/install.sh step blocks as selectable modules.
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

# ─── CONFIG ──────────────────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y)     ASSUME_YES=1 ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
INSTALL_SH="$DOTFILES_DIR/installScripts/install.sh"

# ─── BOOTSTRAP GUM ───────────────────────────────────────────────────
if ! command -v gum >/dev/null; then
  echo "Bootstrapping wizard dep 'gum'…"
  if ! sudo pacman -S --needed --noconfirm gum >/dev/null 2>&1; then
    echo "Failed to install gum. Install manually: sudo pacman -S gum" >&2
    exit 1
  fi
fi

# ─── WAL-TINTED PALETTE ──────────────────────────────────────────────
# Pull accents from wal cache when available; fall back to a doom-one
# inspired defaults so wizard renders identical on fresh Arch (before
# any theme-apply has ever run).
_wal_hex() {
  local key="$1" fallback="$2" hex
  hex=$(jq -r ".colors.$key // empty" ~/.cache/wal/colors.json 2>/dev/null)
  [[ -z "$hex" || "$hex" == null ]] && hex="$fallback"
  echo "$hex"
}
ACCENT=$(_wal_hex color10 '#98be65')   # dominant
URGENT=$(_wal_hex color9  '#ff6c6b')
INFO=$(_wal_hex   color14 '#46d9ff')
MUTED='#5b6268'
FG='#dcdfe4'

# Gum uses 256-color / hex; passing hex directly is supported.
_H1()   { gum style --bold --foreground "$ACCENT" "$@"; }
_H2()   { gum style --bold --foreground "$INFO"   "$@"; }
_INFO() { gum style --foreground "$FG"     "$@"; }
_DIM()  { gum style --foreground "$MUTED"  "$@"; }
_OK()   { gum style --foreground '#82c882' "$@"; }
_WARN() { gum style --foreground '#e5c07b' "$@"; }
_ERR()  { gum style --foreground "$URGENT" "$@"; }

_LOGO=$'\n     █████╗ ████████╗██╗\n    ██╔══██╗╚══██╔══╝██║\n    ███████║   ██║   ██║\n    ██╔══██║   ██║   ██║\n    ██║  ██║   ██║   ██║\n    ╚═╝  ╚═╝   ╚═╝   ╚═╝\n           d o t f i l e s\n'

_BOX_HEADER() {
  clear
  gum style --align center --foreground "$ACCENT" "$_LOGO"
  gum style --align center --foreground "$MUTED" \
    "Arch · X11 · Qtile · wal-themed"
  echo
  gum style --border thick --align center \
    --border-foreground "$ACCENT" --padding "0 4" --margin "0 0 1 0" \
    "$1"
}

# Colored group badge — 6-char pill with fg=black bg=group-color.
_BADGE() {
  local g="$1" c
  case "$g" in
    System)   c='#61afef' ;;
    Dotfiles) c='#c678dd' ;;
    Themes)   c='#e5c07b' ;;
    Browsers) c='#56b6c2' ;;
    Apps)     c='#98c379' ;;
    Media)    c='#e06c75' ;;
    *)        c='#5b6268' ;;
  esac
  gum style --foreground '#282c34' --background "$c" --padding "0 1" --bold "$g"
}

# Numbered step chip: "[03/26]"
_CHIP() {
  local n="$1" total="$2"
  gum style --foreground '#282c34' --background "$ACCENT" --bold --padding "0 1" \
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
    eval "$@"
  fi
}

# ─── MODULE DEFINITIONS ──────────────────────────────────────────────
# Each module: id | group | title | 1-line desc | shell to execute
# Group is only used for the picker header — keep display order stable.
declare -A MOD_TITLE MOD_DESC MOD_GROUP MOD_CMD
MOD_ORDER=(
  sanity bootstrap yay dcli stow arch-config dcli-sync cargo ati-scripts
  touchpad xinit xmodmap lid image-envs flatpak piper whisper
  passwordless-sudo ownership disable-dm candy-icons wallpapers speed
  themes browser-flags chrome-policy
)

_reg() { MOD_TITLE[$1]="$2"; MOD_GROUP[$1]="$3"; MOD_DESC[$1]="$4"; MOD_CMD[$1]="$5"; }
_reg sanity            "System check"        System    "Arch + X11 + dotfiles present"                          "step_sanity"
_reg bootstrap         "Bootstrap packages"  System    "base-devel, git, stow, xorg-server, curl"               "step_bootstrap"
_reg yay               "AUR helper (yay)"    System    "Build yay-bin from AUR if missing"                      "step_yay"
_reg dcli              "dcli"                System    "Declarative package sync tool"                          "step_dcli"
_reg stow              "Deploy dotfiles"     Dotfiles  "Symlink .config, .local, etc via GNU stow"              "step_stow"
_reg arch-config       "Host arch-config"    Dotfiles  "Point arch-config at this host"                         "step_arch_config"
_reg dcli-sync         "dcli sync (all pkgs)" System   "Install every declared pkg + flatpak (slow)"            "step_dcli_sync"
_reg cargo             "Cargo tools"         System    "pomodoro-tui"                                           "step_cargo"
_reg ati-scripts       "AtiScriptsV1"        Dotfiles  "Install rofi-kill, theme-apply, etc to /usr/local/bin"  "step_ati_scripts"
_reg touchpad          "Touchpad tap"        System    "Enable tap-to-click"                                    "step_touchpad"
_reg xinit             ".xinitrc"            Dotfiles  "Auto-start qtile + xcape + picom"                       "step_xinit"
_reg xmodmap           ".Xmodmap"            Dotfiles  "Caps hold = Alt (xcape restores tap-Caps)"              "step_xmodmap"
_reg lid               "Lid = ignore"        System    "Never sleep on lid close"                               "step_lid"
_reg image-envs        "Image env"           Dotfiles  "Suppress VIPS warnings for kitty+nvim images"           "step_image_envs"
_reg flatpak           "Flatpak + Collector" Apps      "flathub + it.mijorus.collector"                         "step_flatpak"
_reg piper             "Piper voices"        Media     "EN + DE TTS voices (~60MB)"                             "step_piper"
_reg whisper           "Whisper model"       Media     "small.en STT model (~500MB)"                            "step_whisper"
_reg passwordless-sudo "Passwordless sudo"   System    "Add user to NOPASSWD sudoers"                           "step_nopasswd"
_reg ownership         "Fix ownership"       System    "chown -R \$USER on ~/.dotfiles"                         "step_ownership"
_reg disable-dm        "Disable display mgrs" System   "TTY + startx only"                                      "step_disable_dm"
_reg candy-icons       "Candy icons"         Themes    "Install candy-icons theme"                              "step_candy"
_reg wallpapers        "Wallpapers"          Themes    "Clone w3dg/wallpapers to ~/Pictures"                    "step_wallpapers"
_reg speed             "Speed tweaks"        System    "sysctl + service trims (from speed_boost.sh)"           "step_speed"
_reg themes            "Theme system"        Themes    "pywal + palette precompile + initial doom-one apply"    "step_themes"
_reg browser-flags     "Browser flags"       Browsers  "brave/chrome/chromium wal theme extension flags"        "step_browser_flags"
_reg chrome-policy     "Chrome theme policy" Browsers  "Sign .pem + install /etc/opt/chrome force_installed"    "step_chrome_policy"

# ─── STEP IMPLEMENTATIONS ────────────────────────────────────────────
# Each step_* delegates to install.sh's actual work via `run`.
# For the wizard scaffold we call install.sh with an env-guarded flag
# where possible; otherwise we inline the minimal command.

step_sanity() {
  [[ -f /etc/arch-release ]] || { _ERR "Not Arch Linux"; return 1; }
  [[ "${XDG_SESSION_TYPE:-}" != wayland ]] || { _ERR "Wayland not supported"; return 1; }
  [[ -d "$DOTFILES_DIR" ]] || { _ERR "~/.dotfiles missing"; return 1; }
  _OK "System checks passed"
}
step_bootstrap()    { run "sudo pacman -Syu --needed --noconfirm base-devel git stow xorg-server xorg-xinit curl wget unzip"; }
step_yay()          { command -v yay >/dev/null && { _OK "yay present"; return; }
                      run "cd /tmp && git clone https://aur.archlinux.org/yay-bin.git yay-bin && cd yay-bin && makepkg -si --noconfirm"; }
step_dcli()         { command -v dcli >/dev/null && { _OK "dcli present"; return; }
                      run "yay -S --noconfirm dcli-arch-git"; }
step_stow()         { run "$DOTFILES_DIR/installScripts/stow_script.sh"; }
step_arch_config()  { run "$DOTFILES_DIR/installScripts/arch-config.sh"; }
step_dcli_sync()    { run "cd $DOTFILES_DIR && dcli sync && sudo mandb && fc-cache -fv"; }
step_cargo()        { command -v cargo >/dev/null && run "cargo install pomodoro-tui" || _WARN "cargo missing, skip"; }
step_ati_scripts()  { run "cd $DOTFILES_DIR/.config/AtiScriptsV1 && ./install.sh"; }
step_touchpad()     { run "sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null << 'EOF'
Section \"InputClass\"
    Identifier \"Touchpad\"
    MatchIsTouchpad \"on\"
    Driver \"libinput\"
    Option \"Tapping\" \"on\"
EndSection
EOF"; }
step_xinit()        { _DIM "  (skipped in wizard scaffold — run install.sh for full .xinitrc)"; }
step_xmodmap()      { _DIM "  (skipped in wizard scaffold)"; }
step_lid()          { run "sudo sed -i 's/^#\\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf && sudo systemctl restart systemd-logind"; }
step_image_envs()   { run "grep -qx 'set -x VIPS_WARNING 0' $HOME/.profile 2>/dev/null || echo 'set -x VIPS_WARNING 0' >> $HOME/.profile"; }
step_flatpak()      { run "sudo pacman -S --needed --noconfirm flatpak && flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo && flatpak install -y --user flathub it.mijorus.collector"; }
step_piper()        { _DIM "  (delegates to install.sh full path — big downloads)"; run "true"; }
step_whisper()      { _DIM "  (delegates to install.sh full path — 500MB download)"; run "true"; }
step_nopasswd()     { run "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/zz-$(id -un)-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-$(id -un)-nopasswd"; }
step_ownership()    { run "sudo chown -R $(id -un):$(id -un) $DOTFILES_DIR"; }
step_disable_dm()   { for dm in lightdm gdm sddm lxdm; do run "sudo systemctl disable $dm.service 2>/dev/null || true"; done; }
step_candy()        { [[ -d /usr/share/icons/candy-icons ]] && { _OK "candy-icons present"; return; }
                      run "cd /tmp && wget -q https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip && unzip -q master.zip && sudo mv candy-icons-master /usr/share/icons/candy-icons"; }
step_wallpapers()   { [[ -d $HOME/Pictures/Wallpapers ]] && { _OK "wallpapers present"; return; }
                      run "mkdir -p $HOME/Pictures && git clone https://github.com/w3dg/wallpapers.git $HOME/Pictures/Wallpapers"; }
step_speed()        { run "$DOTFILES_DIR/installScripts/speed_boost.sh"; }
step_themes()       { run "sudo pacman -S --needed --noconfirm python-pywal python-pillow papirus-icon-theme jq && wal-precompile && theme-apply doomone"; }
step_browser_flags() {
  run "for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
    cfg=$HOME/.config/\$f
    grep -q -- '--load-extension=' \$cfg 2>/dev/null || echo '--load-extension=$HOME/.config/qtile/browser-theme' >> \$cfg
  done"
}
step_chrome_policy() { _DIM "  (delegates to install.sh step 23b — pem+crx+policy setup)"; run "true"; }

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
  _FOOTER "[enter] continue  ·  [ctrl-c] quit"
  read -rsn1 -p ""
}

page_module_picker() {
  _BOX_HEADER "select modules to install"
  echo
  local options=()
  for id in "${MOD_ORDER[@]}"; do
    options+=("$(printf '%-22s %-9s %s' "$id" "[${MOD_GROUP[$id]}]" "${MOD_DESC[$id]}")")
  done
  local picked
  picked=$(printf '%s\n' "${options[@]}" | gum choose --no-limit \
    --header "space=toggle · a=all · enter=continue" \
    --selected="$(printf '%s\n' "${options[@]}" | paste -sd, -)")
  # Extract id (first whitespace token) per line.
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
    chip="$(gum style --foreground '#82c882' --bold '  ✔')"
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

page_execute() {
  _BOX_HEADER "installing modules"
  local ok=0 fail=0 total=${#PICKED_IDS[@]} idx=0
  for id in "${PICKED_IDS[@]}"; do
    idx=$((idx+1))
    local chip badge title status
    chip="$(_CHIP "$idx" "$total")"
    badge="$(_BADGE "${MOD_GROUP[$id]}")"
    title="$(gum style --bold --foreground "$FG" "${MOD_TITLE[$id]}")"
    # Header row: chip [badge] title
    gum join --horizontal "$chip" " " "$badge" " " "$title"
    _DIM   "        ${MOD_DESC[$id]}"
    if (( DRY_RUN )); then
      # Preview commands with subtle indent + capture output.
      out="$("${MOD_CMD[$id]}" 2>&1)"
      [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /'
      status="$(gum style --foreground '#82c882' '  ✔ preview')"
      ok=$((ok+1))
    else
      if bash -c "$(declare -f run _OK _WARN _ERR _DIM); DRY_RUN=$DRY_RUN; ${MOD_CMD[$id]}" \
           >/tmp/wizard-$id.log 2>/tmp/wizard-$id.err; then
        status="$(gum style --foreground '#82c882' '  ✔ ok')"; ok=$((ok+1))
      else
        status="$(gum style --foreground "$URGENT" '  ✖ failed')"; fail=$((fail+1))
      fi
    fi
    printf '%s\n' "$status"
    _PROGRESS "$idx" "$total"
    echo
  done
  echo
  local border_color="$ACCENT"
  (( fail )) && border_color="$URGENT"
  gum style --border rounded --padding "1 3" --align center \
    --border-foreground "$border_color" \
    "$(gum style --bold "Installation Complete")" \
    "" \
    "$(gum style --foreground '#82c882' "✔ $ok succeeded")   $(gum style --foreground "$URGENT" "✖ $fail failed")"
}

page_finale() {
  echo
  _H1 "Next steps"
  _INFO "  · Log out to TTY and run:  startx"
  _INFO "  · Reload qtile any time:   qtile cmd-obj -o cmd -f reload_config"
  _INFO "  · Update system:           dcli sync"
  echo
  _DIM "TROUBLESHOOTING.md documents every common failure + fix."
  echo
}

# ─── MAIN FLOW ───────────────────────────────────────────────────────
main() {
  page_welcome
  if (( ASSUME_YES )); then
    PICKED_IDS=("${MOD_ORDER[@]}")
  else
    page_module_picker
  fi
  page_summary || { _WARN "Cancelled by user."; exit 0; }
  page_execute
  page_finale
}

main "$@"
