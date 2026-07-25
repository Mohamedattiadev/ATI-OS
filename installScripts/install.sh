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
# ===============================
# XINITRC – QTILE (STABLE BUILD)
# ===============================

# ---- Sanity cleanup (CRITICAL)
unset SESSION_MANAGER
# unset DBUS_SESSION_BUS_ADDRESS

# ---- Keyboard / input (EARLY)
setxkbmap -layout us -option
[ -f "$HOME/.Xmodmap" ] && xmodmap "$HOME/.Xmodmap"
# xcape: tap Caps -> Caps_Lock (hold = Alt via xmodmap remap above)
if command -v xcape >/dev/null 2>&1; then
  pkill -x xcape 2>/dev/null
  xcape -e 'Alt_L=Caps_Lock' &
fi

# ---- XDG session identity
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=qtile
export XDG_SESSION_DESKTOP=qtile

# ---- Make systemd --user aware of X
systemctl --user import-environment \
  DISPLAY \
  XAUTHORITY \
  XDG_SESSION_TYPE \
  XDG_CURRENT_DESKTOP \
  XDG_SESSION_DESKTOP

# ---- DBus activation env (dunst / portals need this)
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd \
    DISPLAY XAUTHORITY \
    XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP 2>/dev/null
fi

# ---- Root cursor (avoid X-shaped default)
command -v xsetroot >/dev/null 2>&1 && xsetroot -cursor_name left_ptr

# ---- Disable screensaver + DPMS (no blank/monitor sleep)
xset s off -dpms

# ---- Wallpaper (FAST, NON-BLOCKING)
if [ -f "$HOME/.cache/wall" ] && command -v xwallpaper >/dev/null 2>&1; then
  wall_path="$(cat "$HOME/.cache/wall")"
  [ -f "$wall_path" ] && xwallpaper --stretch "$wall_path" &
fi

# ---- Compositor (start before WM, no dupes)
if command -v picom >/dev/null 2>&1; then
  pkill -x picom 2>/dev/null
  picom &
fi

# ---- Start Qtile (NO dbus-run-session)
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
# zz- prefix so this file sorts LAST in /etc/sudoers.d — the last
# matching rule wins in sudo, so this overrides any earlier
# "(ALL) ALL" (password-required) rule that some sudoers configs ship.
info "Configuring passwordless sudo"
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/zz-$USER_NAME-nopasswd" >/dev/null
sudo chmod 440 "/etc/sudoers.d/zz-$USER_NAME-nopasswd"
# Drop old un-prefixed file if it exists — it sorts earlier so its
# effect is stomped by any later /etc/sudoers.d rule.
[[ -f "/etc/sudoers.d/$USER_NAME" ]] && sudo rm "/etc/sudoers.d/$USER_NAME"
ok "Passwordless sudo enabled (zz-$USER_NAME-nopasswd)"

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
# 23. THEME SYSTEM (pywal + palette precompile + initial apply)
# =====================================================
info "Setting up theme system"

# Deps: pywal engine, colorz backend (multi-hue k-means), Pillow (used
# by wal-precompile), papirus icons + folders (accent-aware folders),
# jq (theme-apply uses it to read wal cache).
sudo pacman -S --needed --noconfirm \
  python-pywal python-pillow \
  papirus-icon-theme jq >/dev/null || warn "some theme deps failed"
yay -S --needed --noconfirm papirus-folders-catppuccin-git 2>/dev/null \
  || yay -S --needed --noconfirm papirus-folders 2>/dev/null \
  || warn "papirus-folders install failed"
python3 -m pip install --user --break-system-packages colorz 2>/dev/null \
  || warn "colorz backend install failed (falls back to wal default)"

# Seed a wallpaper so ~/.cache/wall exists for theme-apply.
if [[ ! -f "$HOME_DIR/.cache/wall" ]]; then
  first_wall="$(find "$HOME_DIR/Pictures/Wallpapers" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    | sort | head -1 || true)"
  if [[ -n "${first_wall:-}" ]]; then
    mkdir -p "$HOME_DIR/.cache"
    echo "$first_wall" >"$HOME_DIR/.cache/wall"
    ok "Seeded ~/.cache/wall -> $(basename "$first_wall")"
  fi
fi

# Precompile every wallpaper into deterministic doomone-quality palettes
# (~50s for 400 wallpapers). Populates ~/.cache/qtile/palettes/*.json;
# theme-apply wal reads this cache first.
if command -v wal-precompile >/dev/null; then
  wal-precompile 2>&1 | tail -3 || warn "wal-precompile failed"
  ok "Palettes precompiled"
else
  warn "wal-precompile not on PATH — AtiScriptsV1 install missed it?"
fi

# Seed eww colors.scss from template so eww.scss @import resolves
# before the first theme-apply runs. theme-apply overwrites this on
# every switch; the .tmpl is versioned as the doom-one fallback.
if [[ -f "$HOME_DIR/.config/eww/colors.scss.tmpl" && ! -f "$HOME_DIR/.config/eww/colors.scss" ]]; then
  cp "$HOME_DIR/.config/eww/colors.scss.tmpl" "$HOME_DIR/.config/eww/colors.scss"
  ok "Seeded eww colors.scss from tmpl"
fi

# Apply initial theme so kitty/rofi/dunst/qtile/gtk/eww all get seeded.
if command -v theme-apply >/dev/null; then
  theme-apply doomone >/dev/null 2>&1 || warn "initial theme-apply failed"
  ok "Initial theme: doomone"
fi

# Browser wal integration — flags load the palette extension so
# brave/chromium/chrome frame tracks wal. Do NOT force-dark web
# contents: it breaks canva / figma / any editor that ships its
# own dark theme (colors invert twice, images render wrong).
mkdir -p "$HOME_DIR/.config" "$HOME_DIR/.config/qtile/browser-theme"
BROWSER_EXT="$HOME_DIR/.config/qtile/browser-theme"
for f in brave-flags.conf chromium-flags.conf chrome-flags.conf; do
  cfg="$HOME_DIR/.config/$f"
  if [[ ! -f "$cfg" ]]; then
    cat >"$cfg" <<EOF
--gtk-version=4
--load-extension=$BROWSER_EXT
EOF
  else
    # Strip legacy content-force-dark flags from any existing config.
    sed -i '/--force-dark-mode/d; /WebContentsForceDark/d' "$cfg"
    grep -q -- '--load-extension=' "$cfg" || printf '\n--load-extension=%s\n' "$BROWSER_EXT" >>"$cfg"
  fi
done
ok "browser flags written (brave/chromium/chrome)"

# =====================================================
# 23b. CHROME THEME KEY + POLICY (auto-apply theme on every wallpaper)
# =====================================================
# Chrome (unlike brave) ignores --load-extension for themes since v134.
# Fix: sign the theme extension with a stable .pem, embed its public
# key as `key` field in manifest.json (via wal-precompile), and install
# it via chrome enterprise policy force_installed pointing at a local
# updates.xml. Every theme-apply repacks the .crx + bumps updates.xml
# so chrome re-installs on next launch (theme-apply also wipes stale
# Preferences entries so the update lands immediately).
info "Setting up chrome/chromium theme policy"
BROWSER_PEM="$HOME_DIR/.config/qtile/browser-theme.pem"
BROWSER_KEY="$HOME_DIR/.config/qtile/browser-theme.key"
BROWSER_CRX="$HOME_DIR/.config/qtile/browser-theme.crx"
BROWSER_UPDATES="$HOME_DIR/.config/qtile/browser-theme-updates.xml"

# Generate stable RSA 2048 signing key if missing (per-machine, gitignored).
if [[ ! -f "$BROWSER_PEM" ]]; then
  openssl genrsa -out "$BROWSER_PEM" 2048 2>/dev/null
  chmod 600 "$BROWSER_PEM"
  ok "Generated browser-theme.pem (RSA 2048)"
fi
# Extract base64 public key so wal-precompile can embed it in manifest.
openssl rsa -in "$BROWSER_PEM" -pubout -outform DER 2>/dev/null | base64 -w0 >"$BROWSER_KEY"
# Compute extension id from public key.
EXT_ID=$(python3 - <<PYEOF
import hashlib, base64
k = open("$BROWSER_KEY").read()
h = hashlib.sha256(base64.b64decode(k)).hexdigest()[:32]
print(''.join(chr(ord('a')+int(c,16)) for c in h))
PYEOF
)
ok "Extension id: $EXT_ID"

# Pack initial .crx (silently ok if it fails — theme-apply will retry).
CHROME_BIN=""
for c in /opt/google/chrome/chrome /usr/bin/chromium /opt/brave-bin/brave; do
  [[ -x "$c" ]] && { CHROME_BIN="$c"; break; }
done
if [[ -n "$CHROME_BIN" && -d "$BROWSER_EXT" ]]; then
  "$CHROME_BIN" --pack-extension="$BROWSER_EXT" --pack-extension-key="$BROWSER_PEM" --no-message-box >/dev/null 2>&1 || true
fi
# Initial updates.xml (theme-apply overwrites on each apply).
if [[ -f "$BROWSER_EXT/manifest.json" ]]; then
  VER=$(python3 -c "import json;print(json.load(open('$BROWSER_EXT/manifest.json'))['version'])" 2>/dev/null || echo "1.0.1")
  cat >"$BROWSER_UPDATES" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$EXT_ID'>
    <updatecheck codebase='file://$BROWSER_CRX' version='$VER' />
  </app>
</gupdate>
EOF
fi

# Sudo write policy for chrome + chromium (system-wide).
POLICY_JSON=$(cat <<EOF
{
  "ExtensionSettings": {
    "$EXT_ID": {
      "installation_mode": "force_installed",
      "update_url": "file://$BROWSER_UPDATES",
      "toolbar_pin": "default_unpinned"
    }
  },
  "ExtensionInstallSources": ["file:///*"]
}
EOF
)
sudo mkdir -p /etc/opt/chrome/policies/managed /etc/chromium/policies/managed
echo "$POLICY_JSON" | sudo tee /etc/opt/chrome/policies/managed/wal-theme.json >/dev/null
echo "$POLICY_JSON" | sudo tee /etc/chromium/policies/managed/wal-theme.json >/dev/null
ok "Chrome/chromium theme policy installed"

ok "Theme system ready"

# =====================================================
# DONE
# =====================================================
echo
ok "INSTALLATION COMPLETE"
echo -e "${GREEN}→ Start X:${RESET} 'startx'  (or alias 'letsgo')"
echo -e "${GREEN}→ Reload qtile:${RESET} 'qtile cmd-obj -o cmd -f reload_config'"
echo -e "${GREEN}→ Update system anytime:${RESET} 'dcli sync' (timeshift snapshot auto)"
