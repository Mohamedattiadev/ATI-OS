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
# 2. BASE PACKAGES
# =====================================================
info "Installing base packages"

sudo pacman -Syu --needed --noconfirm \
  base-devel git stow \
  xorg-server xorg-xinit \
  libinput imagemagick \
  unzip wget curl

ok "Base packages installed"

# =====================================================
# 3. INSTALL yay (pacman → fallback)
# =====================================================
if ! command -v yay >/dev/null; then
  warn "yay not found, attempting install"

  if sudo pacman -S --noconfirm yay; then
    ok "yay installed via pacman"
  else
    warn "pacman failed, building yay-bin manually"
    TMP="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$TMP/yay-bin"
    (cd "$TMP/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$TMP"
    ok "yay built manually"
  fi
else
  ok "yay already installed"
fi

# =====================================================
# 4. INSTALL dcli
# =====================================================
if ! command -v dcli >/dev/null; then
  info "Installing dcli"
  yay -S --noconfirm dcli-arch-git
else
  ok "dcli already installed"
fi

# =====================================================
# 5. DEPLOY DOTFILES (STOW)
# =====================================================
info "Deploying dotfiles"
"$STOW_SCRIPT"
ok "Dotfiles deployed"

# =====================================================
# 6. ARCH-CONFIG HOST SYNC
# =====================================================
info "Syncing arch-config"
"$ARCH_CONFIG_SCRIPT"
ok "arch-config synced"

# =====================================================
# 7. INSTALL PACKAGES VIA dcli (CORRECT PLACE)
# =====================================================
info "Installing packages via dcli"
cd "$DOTFILES_DIR"
dcli sync
ok "dcli sync completed"

# =====================================================
# 8. TOUCHPAD CONFIG
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
# 9. XINIT + QTILE
# =====================================================
info "Creating ~/.xinitrc"

cat >"$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
setxkbmap -layout us -option
xmodmap ~/.Xmodmap

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
# 10. XMODMAP
# =====================================================
info "Creating ~/.Xmodmap"

cat >"$HOME_DIR/.Xmodmap" <<EOF
clear mod1
add mod1 = Alt_L Alt_R
EOF

ok ".Xmodmap created"

# =====================================================
# 11. LID CLOSE = DO NOTHING
# =====================================================
info "Configuring lid close behavior"

sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

ok "Lid behavior configured"

# =====================================================
# 12. KITTY + NVIM IMAGE SUPPORT
# =====================================================
info "Installing image support"

yay -S --noconfirm openslide
sudo pacman -S --needed --noconfirm ueberzugpp
echo 'set -x VIPS_WARNING 0' >>"$HOME_DIR/.profile"

ok "Image support installed"

# =====================================================
# 13. COLLECTOR APP
# =====================================================
info "Installing Collector dependencies"

yay -S --noconfirm discover || true

flatpak override --user \
  --filesystem=home \
  it.mijorus.collector || true

ok "Collector configured"

# =====================================================
# 14. PIPER VOICES
# =====================================================
info "Installing Piper voices"

VOICE_DIR="$HOME_DIR/.config/piper-voices"
mkdir -p "$VOICE_DIR"
cd "$VOICE_DIR"

curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx.json
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx
curl -LO https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json

ok "Piper voices installed"

# =====================================================
# 15. PASSWORDLESS SUDO
# =====================================================
info "Configuring passwordless sudo"

echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER_NAME >/dev/null
sudo chmod 440 /etc/sudoers.d/$USER_NAME

ok "Passwordless sudo enabled"

# =====================================================
# 16. OWN DOTFILES
# =====================================================
info "Fixing dotfiles ownership"
sudo chown -R "$USER_NAME:$USER_NAME" "$DOTFILES_DIR"
ok "Ownership fixed"

# =====================================================
# 17. ATI SCRIPTS
# =====================================================
info "Installing AtiScripts"
"$HOME_DIR/.config/AtiScriptsV1/install.sh" || true
ok "AtiScripts installed"

# =====================================================
# 18. DISABLE ALL DISPLAY MANAGERS
# =====================================================
info "Disabling all display managers (TTY only)"

sudo systemctl disable lightdm.service 2>/dev/null || true
sudo systemctl disable gdm.service 2>/dev/null || true
sudo systemctl disable sddm.service 2>/dev/null || true
sudo systemctl disable lxdm.service 2>/dev/null || true

ok "No display manager enabled"

# =====================================================
# 19. THEMES & ICONS
# =====================================================
info "Installing themes and icons"

yay -S --noconfirm sweet-gtk-theme-dark

TMP_ICON="$(mktemp -d)"
cd "$TMP_ICON"
wget https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip
unzip master.zip
sudo mv candy-icons-master /usr/share/icons/candy-icons
rm -rf "$TMP_ICON"

ok "Themes installed"

# =====================================================
# 20. WALLPAPERS
# =====================================================
info "Installing wallpapers"

mkdir -p "$HOME_DIR/Pictures"
git clone https://github.com/w3dg/wallpapers.git "$HOME_DIR/Pictures/Wallpapers" || true

ok "Wallpapers installed"

# =====================================================
# DONE
# =====================================================
echo
ok "INSTALLATION COMPLETE"
echo -e "${GREEN}→ Start X11 with:${RESET} exec dbus-run-session startx"
echo -e "${GREEN}→ Restart Qtile:${RESET} fc-cache -fv && qtile cmd-obj -o cmd -f restart"
