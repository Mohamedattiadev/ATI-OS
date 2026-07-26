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

# ─── LOG SINK ────────────────────────────────────────────────────────
WIZ_LOGDIR="${XDG_STATE_HOME:-$HOME/.local/state}/wizard"
mkdir -p "$WIZ_LOGDIR"
WIZ_RUNLOG="$WIZ_LOGDIR/run-$(date +%Y%m%d-%H%M%S).log"

# ─── CONFIG ──────────────────────────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
ONLY_LIST=""
SKIP_LIST=""
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y)     ASSUME_YES=1 ;;
    --only=*)     ONLY_LIST="${arg#*=}" ;;
    --skip=*)     SKIP_LIST="${arg#*=}" ;;
    --uninstall)  UNINSTALL=1 ;;
    --help|-h)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      cat <<'HELP'

Filters (combine with --yes for scripted runs):
  --only=id1,id2       Run only these module ids (comma-sep)
  --skip=id1,id2       Skip these module ids (comma-sep)

Module ids: sanity bootstrap yay dcli stow arch-config dcli-sync
cargo ati-scripts touchpad xinit xmodmap lid image-envs flatpak
piper whisper passwordless-sudo ownership disable-dm candy-icons
wallpapers speed themes browser-flags chrome-policy

Example (safe non-network test — skip heavy downloads):
  ./wizard.sh --yes --skip=dcli-sync,whisper,piper,wallpapers,flatpak

Uninstall (reverse config files + sudoers + policies wizard wrote —
NEVER touches pacman packages, dcli syncs, or downloaded models):
  ./wizard.sh --uninstall            # interactive confirm
  ./wizard.sh --uninstall --dry-run  # preview reversals
  ./wizard.sh --uninstall --yes      # unattended
HELP
      exit 0 ;;
  esac
done

_id_in_csv() { [[ ",$1," == *",$2,"* ]]; }

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
  clear
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
    eval "$@"
  fi
}

# ─── MODULE DEFINITIONS ──────────────────────────────────────────────
# Each module: id | group | title | 1-line desc | shell to execute
# Group is only used for the picker header — keep display order stable.
declare -A MOD_TITLE MOD_DESC MOD_GROUP MOD_CMD
MOD_ORDER=(
  sanity bootstrap yay dcli stow arch-config dcli-sync cargo ati-scripts
  touchpad xinit xresources xmodmap lid image-envs flatpak piper whisper
  passwordless-sudo ownership disable-dm candy-icons wallpapers speed
  themes browser-flags chrome-policy
)

_reg() { MOD_TITLE[$1]="$2"; MOD_GROUP[$1]="$3"; MOD_DESC[$1]="$4"; MOD_CMD[$1]="$5"; }
_reg sanity            "System check"        System    "Arch + X11 + dotfiles present"                          "step_sanity"
_reg bootstrap         "Bootstrap packages"  System    "base-devel · git · stow · xorg-server · curl"           "step_bootstrap"
_reg yay               "AUR helper (yay)"    System    "Build yay-bin from AUR if missing"                      "step_yay"
_reg dcli              "dcli"                System    "Declarative package sync tool"                          "step_dcli"
_reg stow              "Deploy dotfiles"     Dotfiles  "Symlink .config · .local · etc via GNU stow"            "step_stow"
_reg arch-config       "Host arch-config"    Dotfiles  "Point arch-config at this host"                         "step_arch_config"
_reg dcli-sync         "dcli sync (all pkgs)" System   "Install every declared pkg + flatpak (slow)"            "step_dcli_sync"
_reg cargo             "Cargo tools"         System    "pomodoro-tui"                                           "step_cargo"
_reg ati-scripts       "AtiScriptsV1"        Dotfiles  "Install rofi-kill · theme-apply · etc to /usr/local/bin" "step_ati_scripts"
_reg touchpad          "Touchpad tap"        System    "Enable tap-to-click"                                    "step_touchpad"
_reg xinit             ".xinitrc"            Dotfiles  "Auto-start qtile + xcape + picom + cursor size"         "step_xinit"
_reg xresources        ".Xresources"         Dotfiles  "Xcursor size 24 + Breeze theme (load via xrdb)"         "step_xresources"
_reg xmodmap           ".Xmodmap"            Dotfiles  "Caps hold = Alt (xcape restores tap-Caps)"              "step_xmodmap"
_reg lid               "Lid = ignore"        System    "Never sleep on lid close"                               "step_lid"
_reg image-envs        "Image env"           Dotfiles  "Suppress VIPS warnings for kitty+nvim images"           "step_image_envs"
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
step_bootstrap() {
  if (( DRY_RUN )); then _DIM "  [dry] sudo pacman -Syu … (retry x3)"; return; fi
  retry_net 3 5 sudo pacman -Syu --needed --noconfirm base-devel git stow xorg-server xorg-xinit curl wget unzip
}
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
if command -v xcape >/dev/null 2>&1; then
  pkill -x xcape 2>/dev/null
  xcape -e 'Alt_L=Caps_Lock' &
fi
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=qtile
export XDG_SESSION_DESKTOP=qtile
systemctl --user import-environment DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP 2>/dev/null
fi
# Cursor size + theme for X apps (Xcursor honors both env vars).
export XCURSOR_SIZE=24
export XCURSOR_THEME=breeze_cursors
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name left_ptr
xset s off -dpms
if [ -f "$HOME/.cache/wall" ] && command -v xwallpaper >/dev/null 2>&1; then
  wall_path="$(readlink -f "$HOME/.cache/wall")"
  [ -f "$wall_path" ] && xwallpaper --stretch "$wall_path" &
fi
if command -v picom >/dev/null 2>&1; then
  pkill -x picom 2>/dev/null
  picom &
fi
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
! Caps physical key acts as Alt_L; xcape restores tap-Caps behavior
clear lock
clear mod1
keycode 66 = Alt_L
add mod1 = Alt_L Alt_R
XMM_EOF
}
step_lid()          { run "sudo sed -i 's/^#\\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf && sudo systemctl restart systemd-logind"; }
step_image_envs()   { run "grep -qx 'set -x VIPS_WARNING 0' $HOME/.profile 2>/dev/null || echo 'set -x VIPS_WARNING 0' >> $HOME/.profile"; }
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
  local out="$dir/ggml-small.en.bin"
  run "mkdir -p $dir"
  if (( DRY_RUN )); then _DIM "  [dry] curl whisper small.en (~500MB, retry x3)"; return; fi
  [[ -f "$out" ]] && return
  retry_net 3 10 curl -fL --retry 3 --continue-at - -o "$out" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin" || \
    { _ERR "whisper model download failed after 3 retries"; return 1; }
}
step_nopasswd()     { run "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" | sudo tee /etc/sudoers.d/zz-$(id -un)-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-$(id -un)-nopasswd"; }
step_ownership()    { run "sudo chown -R $(id -un):$(id -un) $DOTFILES_DIR"; }
step_disable_dm()   { for dm in lightdm gdm sddm lxdm; do run "sudo systemctl disable $dm.service 2>/dev/null || true"; done; }
step_candy()        { [[ -d /usr/share/icons/candy-icons ]] && { _OK "candy-icons present"; return; }
                      run "cd /tmp && wget -q https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip && unzip -q master.zip && sudo mv candy-icons-master /usr/share/icons/candy-icons"; }
step_wallpapers()   { [[ -d $HOME/Pictures/Wallpapers ]] && { _OK "wallpapers present"; return; }
                      run "mkdir -p $HOME/Pictures && git clone https://github.com/w3dg/wallpapers.git $HOME/Pictures/Wallpapers"; }
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
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -1)
    [[ -n "$first" ]] && run "mkdir -p $HOME/.cache && ln -sfn $first $HOME/.cache/wall"
  fi
  run "wal-precompile"
  run "theme-apply doomone"
}
step_browser_flags() {
  run "for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
    cfg=$HOME/.config/\$f
    grep -q -- '--load-extension=' \$cfg 2>/dev/null || echo '--load-extension=$HOME/.config/qtile/browser-theme' >> \$cfg
  done"
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
  _check "disk free > 10 GB on \$HOME" "[[ $(df -Pk $HOME | awk 'NR==2{print $4}') -gt 10485760 ]]" "wizard needs ~10GB (piper 60MB + whisper 500MB + dcli pkgs + wallpapers)"
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
uninstall_image_envs()       { run "sed -i '/VIPS_WARNING/d' $HOME/.profile 2>/dev/null || true"; }
uninstall_touchpad()         { run "sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf"; }
uninstall_passwordless_sudo(){ run "sudo rm -f /etc/sudoers.d/zz-$(id -un)-nopasswd"; }
uninstall_browser_flags() {
  for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
    run "sed -i '/--load-extension=.*browser-theme/d' $HOME/.config/$f 2>/dev/null || true"
  done
}
uninstall_chrome_policy() {
  run "sudo rm -f /etc/opt/chrome/policies/managed/wal-theme.json /etc/chromium/policies/managed/wal-theme.json"
  run "rm -f $HOME/.config/qtile/browser-theme.pem $HOME/.config/qtile/browser-theme.key $HOME/.config/qtile/browser-theme.crx $HOME/.config/qtile/browser-theme-updates.xml"
  # Remove installed extension traces per browser profile.
  local ext=fommfacojlllmdogognehdgombidbpjg
  for base in "$HOME/.config/google-chrome/Default" "$HOME/.config/chromium/Default"; do
    [[ -d "$base" ]] && run "rm -rf $base/Extensions/$ext"
  done
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
uninstall_cargo()             { :; }
uninstall_arch_config()       { :; }
uninstall_flatpak()           { :; }
uninstall_piper()             { :; }  # models may be shared
uninstall_whisper()           { :; }
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
UMOD_CMD[touchpad]="uninstall_touchpad"
UMOD_CMD[xinit]="uninstall_xinit"
UMOD_CMD[xmodmap]="uninstall_xmodmap"
UMOD_CMD[lid]="uninstall_lid"
UMOD_CMD[image-envs]="uninstall_image_envs"
UMOD_CMD[flatpak]="uninstall_flatpak"
UMOD_CMD[piper]="uninstall_piper"
UMOD_CMD[whisper]="uninstall_whisper"
UMOD_CMD[passwordless-sudo]="uninstall_passwordless_sudo"
UMOD_CMD[ownership]="uninstall_ownership"
UMOD_CMD[disable-dm]="uninstall_disable_dm"
UMOD_CMD[candy-icons]="uninstall_candy_icons"
UMOD_CMD[wallpapers]="uninstall_wallpapers"
UMOD_CMD[speed]="uninstall_speed"
UMOD_CMD[themes]="uninstall_themes"
UMOD_CMD[browser-flags]="uninstall_browser_flags"
UMOD_CMD[chrome-policy]="uninstall_chrome_policy"

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
  local options=() csv
  for id in "${MOD_ORDER[@]}"; do
    options+=("$(printf '%-22s [%-8s] %s' "$id" "${MOD_GROUP[$id]}" "${MOD_DESC[$id]}")")
  done
  csv="$(printf '%s\n' "${options[@]}" | paste -sd, -)"
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
  local id="$1" logf="/tmp/wizard-$id.log" errf="/tmp/wizard-$id.err"
  : >"$logf"; : >"$errf"
  local cmd
  if (( UNINSTALL )); then cmd="${UMOD_CMD[$id]}"; else cmd="${MOD_CMD[$id]}"; fi
  ( set +e; "$cmd" ) >"$logf" 2>"$errf"
}

_show_error_tail() {
  local id="$1" errf="/tmp/wizard-$id.err" logf="/tmp/wizard-$id.log"
  local tail_content
  tail_content=$(tail -5 "$errf" 2>/dev/null | grep -v '^\s*$' | head -5)
  [[ -z "$tail_content" ]] && tail_content=$(tail -5 "$logf" 2>/dev/null | grep -v '^\s*$' | head -5)
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
  local ok=0 fail=0 total=${#PICKED_IDS[@]} idx=0
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
      "$cmd" 2>&1 | sed 's/^/    /'
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
  local border_color="$ACCENT" title="Installation Complete"
  if [[ "$status" == "aborted" ]]; then
    border_color="$URGENT"
    title="Installation Aborted"
  elif (( fail )); then
    border_color="$WARN_C"
    title="Installation Finished (with failures)"
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
  if (( ! DRY_RUN )); then
    preflight
  fi
  if (( ASSUME_YES )); then
    PICKED_IDS=("${MOD_ORDER[@]}")
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
