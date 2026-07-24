#!/usr/bin/env bash
set -Eeuo pipefail

# =====================================================
# COLORS
# =====================================================
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"

info() { echo -e "${BLUE}==>${RESET} $*"; }
ok() { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
die() {
  echo -e "${RED}✖${RESET} $*"
  exit 1
}

# =====================================================
# GLOBALS
# =====================================================
USER_NAME="$(id -un)"
HOME_DIR="$HOME"
DOTFILES_DIR="$HOME/.dotfiles"
INSTALL_SCRIPTS="$DOTFILES_DIR/installScripts"

STOW_SCRIPT="$INSTALL_SCRIPTS/stow_script.sh"
ARCH_CONFIG_SCRIPT="$INSTALL_SCRIPTS/arch-config.sh"

ATI_SCRIPTS_DIR="$DOTFILES_DIR/.config/AtiScriptsV1"
ATI_INSTALL_SCRIPT="$ATI_SCRIPTS_DIR/install.sh"

# =====================================================
# 1. ASSUMPTIONS
# =====================================================
info "Checking system assumptions"

[[ -f /etc/arch-release ]] || die "Not Arch Linux"
[[ "${XDG_SESSION_TYPE:-}" != "wayland" ]] || die "Wayland not supported"
[[ -d "$DOTFILES_DIR" ]] || die "~/.dotfiles not found"
[[ -x "$STOW_SCRIPT" ]] || die "Missing stow_script.sh"
[[ -x "$ARCH_CONFIG_SCRIPT" ]] || die "Missing arch-config.sh"

ok "System assumptions OK"

# =====================================================
# 2. BOOTSTRAP PACKAGES (minimum to reach `dcli sync`)
# =====================================================
info "Installing bootstrap packages"

sudo pacman -Syu --needed --noconfirm \
  base-devel git stow \
  xorg-server xorg-xinit \
  curl wget unzip

ok "Bootstrap packages installed"

# =====================================================
# 3. INSTALL yay (AUR helper)
# =====================================================
if ! command -v yay >/dev/null; then
  warn "yay not found, building yay-bin from AUR"
  TMP="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay-bin.git "$TMP/yay-bin"
  (cd "$TMP/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$TMP"
  ok "yay built"
else
  ok "yay already installed"
fi

# =====================================================
# 4. INSTALL dcli
# =====================================================
if ! command -v dcli >/dev/null; then
  info "Installing dcli-arch-git"
  yay -S --noconfirm dcli-arch-git
else
  ok "dcli already installed"
fi

# =====================================================
# 5. DEPLOY DOTFILES (STOW)
# =====================================================
info "Deploying dotfiles (stow)"
"$STOW_SCRIPT"
ok "Dotfiles deployed"

# =====================================================
# 6. ARCH-CONFIG HOST SYNC
# =====================================================
info "Syncing arch-config host"
"$ARCH_CONFIG_SCRIPT"
ok "arch-config synced"

# =====================================================
# 7. INSTALL ALL PACKAGES VIA dcli (single source of truth)
# =====================================================
info "Installing all declared packages via dcli sync"
cd "$DOTFILES_DIR"
dcli sync
sudo mandb
fc-cache -fv
ok "dcli sync completed"

# =====================================================
# 8. CARGO TOOLS (out of dcli scope)
# =====================================================
info "Installing cargo tools"

if command -v rustup >/dev/null; then
  rustup default stable >/dev/null 2>&1 || true
fi

if command -v cargo >/dev/null; then
  cargo install pomodoro-tui || warn "pomodoro-tui install failed"
else
  warn "cargo not available; skip pomodoro-tui"
fi

ok "Cargo tools done"

# =====================================================
# 9. INSTALL ATI SCRIPTS (deploys rofi_todo, dm-logout, etc. to /usr/local/bin)
# =====================================================
info "Installing AtiScriptsV1 to /usr/local/bin"

if [[ -d "$ATI_SCRIPTS_DIR" && -x "$ATI_INSTALL_SCRIPT" ]]; then
  (cd "$ATI_SCRIPTS_DIR" && ./install.sh)
  ok "AtiScriptsV1 installed"
else
  warn "AtiScriptsV1 install script not found, skipping"
fi

# =====================================================
# 10. TOUCHPAD CONFIG
# =====================================================
info "Configuring touchpad"

sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf >/dev/null <<EOF
Section "InputClass"
    Identifier "Touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
EndSection
EOF

ok "Touchpad configured"

# =====================================================
# 11. .xinitrc (starts qtile + xcape + picom)
# =====================================================
info "Creating ~/.xinitrc"

cat >"$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
setxkbmap -layout us -option
xmodmap ~/.Xmodmap
pkill -x xcape 2>/dev/null
xcape -e 'Alt_L=Caps_Lock' &

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=qtile
export XDG_SESSION_DESKTOP=qtile

systemctl --user import-environment DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP

picom &
exec qtile start
EOF

chmod +x "$HOME_DIR/.xinitrc"
ok ".xinitrc created"

# =====================================================
# 12. .Xmodmap (Caps hold = Alt_L; xcape maps tap → Caps)
# =====================================================
info "Creating ~/.Xmodmap"

cat >"$HOME_DIR/.Xmodmap" <<EOF
! Caps physical key acts as Alt_L; xcape restores tap-Caps behavior
clear lock
clear mod1
keycode 66 = Alt_L
add mod1 = Alt_L Alt_R
EOF

ok ".Xmodmap created"

# =====================================================
# 13. LID CLOSE = IGNORE
# =====================================================
info "Configuring lid close behavior"

sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

ok "Lid behavior configured"

# =====================================================
# 14. KITTY + NVIM IMAGE SUPPORT (suppress VIPS warnings)
# =====================================================
info "Enabling image support envs"
grep -qx 'set -x VIPS_WARNING 0' "$HOME_DIR/.profile" 2>/dev/null \
  || echo 'set -x VIPS_WARNING 0' >>"$HOME_DIR/.profile"
ok "Image support envs set"

# =====================================================
# 15. FLATPAK + COLLECTOR
# =====================================================
info "Configuring flatpak + collector"

sudo pacman -S --needed --noconfirm flatpak || true
flatpak remote-add --if-not-exists --user flathub \
  https://flathub.org/repo/flathub.flatpakrepo || true
flatpak install -y --user flathub it.mijorus.collector || true
flatpak override --user --filesystem=home it.mijorus.collector || true

ok "Collector configured"

# =====================================================
# 16. PIPER VOICES (English + German)
# =====================================================
info "Installing Piper voices"

VOICE_DIR="$HOME_DIR/.config/piper-voices"
mkdir -p "$VOICE_DIR"
cd "$VOICE_DIR"

for f in \
  en/en_US/ryan/high/en_US-ryan-high.onnx \
  en/en_US/ryan/high/en_US-ryan-high.onnx.json \
  de/de_DE/thorsten/high/de_DE-thorsten-high.onnx \
  de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json; do
  fname="$(basename "$f")"
  [[ -f "$fname" ]] && continue
  curl -LO "https://huggingface.co/rhasspy/piper-voices/resolve/main/$f" || warn "voice fetch failed: $f"
done

ok "Piper voices installed"

# =====================================================
# 16b. WHISPER MODEL (voice_dictate)
# =====================================================
info "Downloading whisper small.en model"

WHISPER_DIR="$HOME_DIR/.local/share/whisper"
mkdir -p "$WHISPER_DIR"
if [[ ! -f "$WHISPER_DIR/ggml-small.en.bin" ]]; then
  curl -L -o "$WHISPER_DIR/ggml-small.en.bin" \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin \
    || warn "whisper model fetch failed"
fi
ok "Whisper model ready"

# =====================================================
# 17. PASSWORDLESS SUDO
# =====================================================
info "Configuring passwordless sudo"
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER_NAME" >/dev/null
sudo chmod 440 "/etc/sudoers.d/$USER_NAME"
ok "Passwordless sudo enabled"

# =====================================================
# 18. FIX DOTFILES OWNERSHIP
# =====================================================
info "Fixing dotfiles ownership"
sudo chown -R "$USER_NAME:$USER_NAME" "$DOTFILES_DIR"
ok "Ownership fixed"

# =====================================================
# 19. DISABLE ALL DISPLAY MANAGERS (TTY + startx only)
# =====================================================
info "Disabling all display managers"
for dm in lightdm gdm sddm lxdm; do
  sudo systemctl disable "$dm.service" 2>/dev/null || true
done
ok "No display manager enabled"

# =====================================================
# 20. THEMES & ICONS (candy-icons — not in AUR)
# =====================================================
info "Installing candy-icons theme"

if [[ ! -d /usr/share/icons/candy-icons ]]; then
  TMP_ICON="$(mktemp -d)"
  cd "$TMP_ICON"
  wget https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip
  unzip master.zip
  sudo mv candy-icons-master /usr/share/icons/candy-icons
  rm -rf "$TMP_ICON"
  ok "candy-icons installed"
else
  ok "candy-icons already installed"
fi

# =====================================================
# 21. WALLPAPERS
# =====================================================
info "Installing wallpapers"

mkdir -p "$HOME_DIR/Pictures"
[[ -d "$HOME_DIR/Pictures/Wallpapers" ]] \
  || git clone https://github.com/w3dg/wallpapers.git "$HOME_DIR/Pictures/Wallpapers" \
  || warn "wallpaper clone failed"
ok "Wallpapers ready"

# =====================================================
# 22. SYSTEM SPEED TWEAKS (delegated to speed_boost.sh)
# =====================================================
info "Applying system speed tweaks (via speed_boost.sh)"
"$INSTALL_SCRIPTS/speed_boost.sh"
ok "Speed tweaks applied"

# =====================================================
# DONE
# =====================================================
echo
ok "INSTALLATION COMPLETE"
echo -e "${GREEN}→ Start X:${RESET} 'startx'  (or alias 'letsgo')"
echo -e "${GREEN}→ Reload qtile:${RESET} 'qtile cmd-obj -o cmd -f reload_config'"
echo -e "${GREEN}→ Update system anytime:${RESET} 'dcli sync' (timeshift snapshot auto)"
