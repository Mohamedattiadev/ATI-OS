#!/bin/bash
# Arch Linux Bootstrap Script — Dev Environment Setup
# Author: MohamedattiaDev
# GitHub: github.com/MohamedattiaDev

set -euo pipefail

trap 'echo "❌ Script aborted unexpectedly."; exit 1;' ERR

# -------------------- CONFIG --------------------
GIT_NAME="MohamedattiaDev"
GIT_EMAIL="mohamedattia.dev@gmail.com"
DOTFILES_DIR="$HOME/.dotfiles"
# ------------------------------------------------

log() { echo -e "✅ \033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "⚠️ \033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "❌ \033[1;31m[ERROR]\033[0m $1"; }

# --- Setup: Refresh Keyring & Optimize Mirrors ---
refresh_system() {
	log "Refreshing keyring and optimizing mirrors..."
	sudo pacman-key --refresh-keys
	sudo pacman -Syu --noconfirm
	sudo pacman -S --needed --noconfirm reflector
	sudo reflector --verbose --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
	log "Mirrorlist updated."
}

# --- Cleanup Conflicts ---
clean_system() {
	log "Removing known conflicting packages..."
	yay -Rdd --noconfirm libpamac-full pamac-all copyq || true
	sudo pacman -Sc --noconfirm
	yay -Scc --noconfirm || true
}

# --- Install Core & Dev Tools ---

install_packages() {
	log "Installing all core packages and languages..."

	yay -S --needed --noconfirm tmux stow df btop htop missioncenter inotify-tools zoxide arandr \
		dunst rofi rofi-pass copyq warpd xdotool feh nitrogen \
		blueman pavucontrol syncthing pcmanfm vlc obsidian sushi nautilus \
		ticktick kedconnect docker docker-compose silicon \
		screenkey imagemagick tesseract tesseract-data-eng \
		tesseract-data-ara gromit-mpx gimp \
		neovim emacs code zed-editor-bin alacritty kitty lazygit \
		zathura zathura-pdf-poppler okular \
		brave-browser google-chrome chromium zen-browser whatsdesk \
		postman-bin yt-dlp \
		gcc g++ clang cmake make vala pkgconf cairo gobject-introspection gtk4 libwnck3 \
		python python-pip python-rich python-pipx \
		rust go lua ruby perl php composer dotnet-sdk mono r \
		jdk-openjdk java-runtime-common \
		nodejs npm pnpm \
		dart flutter swift-bin \
		kotlin kotlinc \
		ghc stack haskell \
		fish fnm \
		godot love fasm vlang-bin zig \
		lua-language-server pyright rust-analyzer bash-language-server typescript-language-server \
		vscode-langservers-extracted \
		rstudio-desktop-bin

	log "Installing Wayland/X11-specific dependencies for 'hints'..."
	if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
		yay -S --needed --noconfirm gtk-layer-shell grim
	else
		yay -S --needed --noconfirm libwnck3
	fi

	log "Ensuring pipx is set up..."
	pipx ensurepath
	export PATH="$PATH:$HOME/.local/bin"

	log "Installing 'hints' via pipx..."
	pipx install git+https://github.com/AlfredoSequeida/hints.git

	# ── Node.js global packages ──────────────────────────
	log "Installing global Node.js developer tools..."
	npm install -g \
		live-server \
		nodemon \
		typescript \
		ts-node \
		yarn \
		pm2 \
		prettier \
		eslint \
		http-server

	log "Configuring accessibility environment variables in /etc/environment..."
	sudo tee -a /etc/environment >/dev/null <<EOF

# Required for 'hints'
ACCESSIBILITY_ENABLED=1
GTK_MODULES=gail:atk-bridge
OOO_FORCE_DESKTOP=gnome
GNOME_ACCESSIBILITY=1
QT_ACCESSIBILITY=1
QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
EOF

	log "Enabling and starting hintsd and accessibility DBus service..."
	systemctl --user enable --now hintsd.service
	systemctl --user restart at-spi-dbus-bus.service
	# WARN: important to work:
	#   systemctl --user enable --now hintsd.service
	#   systemctl --user restart at-spi-dbus-bus.service

	log "NOTE: To customize hints configuration, edit:"
	# NOTE: copy the hintsConfig to this:
	echo "    ~/.local/share/pipx/venvs/hints/lib/python*/site-packages/hints/constants.py"
}

install_cli_tools() {
	log "Installing modern CLI productivity tools..."

	yay -S --noconfirm --needed \
		bat \
		eza \
		fzf \
		ripgrep \
		fd \
		dust

	log "CLI tools installed."
}
# --- Touchpad Configuration ---
setup_touchpad() {
	log "Configuring touchpad for tap-to-click..."

	# Ensure modern libinput driver is installed and conflicting one is removed
	yay -S --needed --noconfirm xf86-input-libinput xorg-xinput
	sudo pacman -R --noconfirm xf86-input-synaptics || true # || true ignores error if not installed

	# Define the config file path
	local config_dir="/etc/X11/xorg.conf.d"
	local config_file="$config_dir/30-touchpad.conf"

	# Create directory if it doesn't exist
	sudo mkdir -p "$config_dir"

	# Create the touchpad configuration file using a "here document"
	log "Creating Xorg touchpad configuration at $config_file"
	sudo tee "$config_file" >/dev/null <<EOF
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    # Enable tap to click
    Option "Tapping" "on"
EndSection
EOF
	log "Touchpad configured successfully."
}
# --- Dotfiles via GNU Stow ---
stow_dotfiles() {
	log "Setting up dotfiles with stow..."
	if [[ ! -d "$DOTFILES_DIR" ]]; then
		warn "Dotfiles directory $DOTFILES_DIR not found. Skipping."
		return
	fi

	if [[ -d "$HOME/.config" ]]; then
		log "Backing up existing ~/.config to ~/dotnone"
		mv -f "$HOME/.config" "$HOME/dotnone"
	fi

	cd "$DOTFILES_DIR"
	stow .tmux config installScript
	cd ~
	log "Dotfiles stowed successfully."
}

# --- Tmux + Git + SSH Config ---
setup_dev_tools() {
	log "Cloning tmux TPM plugin..."
	mkdir -p ~/.config/tmux/.tmux/plugins
	git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/.tmux/plugins/tpm || true

	log "Configuring Git..."
	git config --global user.name "$GIT_NAME"
	git config --global user.email "$GIT_EMAIL"
}

install_gptscript() {
	local GPTSCRIPT_DIR="$HOME/.config/GptScript"

	log "Installing GPTScript clipboard assistant..."

	# Ensure git is installed
	if ! command -v git &>/dev/null; then
		log "Git not found, installing git..."
		sudo pacman -S --needed --noconfirm git
	fi

	# Clone repo if not exists
	if [[ ! -d "$GPTSCRIPT_DIR" ]]; then
		git clone https://github.com/Mohamedattiadev/gptscript.git "$GPTSCRIPT_DIR"
		log "Cloned GPTScript repo to $GPTSCRIPT_DIR."
	else
		log "GPTScript repo already exists at $GPTSCRIPT_DIR. Pulling latest changes..."
		git -C "$GPTSCRIPT_DIR" pull
	fi

	# Install dependencies (python3, xclip, xdotool)
	log "Installing GPTScript dependencies: python3, xclip, xdotool..."
	sudo pacman -S --needed --noconfirm python xclip xdotool

	# Setup python venv and install python dependencies
	cd "$GPTSCRIPT_DIR"
	if [[ ! -d "venv" ]]; then
		python -m venv venv
		log "Created Python virtual environment."
	fi

	# Activate and install python deps
	source venv/bin/activate
	pip install --upgrade pip
	pip install -r requirements.txt
	deactivate

	# Make main script executable
	chmod +x gpt_inline_auto.py

	# Setup user.env from example if missing (no GEMINI_API_KEY here)
	if [[ ! -f "$GPTSCRIPT_DIR/user.env" ]]; then
		cp "$GPTSCRIPT_DIR/user.env.example" "$GPTSCRIPT_DIR/user.env"
		warn "Please edit $GPTSCRIPT_DIR/user.env and add your NAME, STUDENT_ID, EMAIL, etc."
	else
		log "user.env already exists at $GPTSCRIPT_DIR/user.env"
	fi

	# Check /etc/environment for GEMINI_API_KEY, add placeholder if missing
	if ! grep -q '^GEMINI_API_KEY=' /etc/environment 2>/dev/null; then
		warn "GEMINI_API_KEY not found in /etc/environment."
		echo "Adding placeholder GEMINI_API_KEY to /etc/environment..."
		sudo bash -c 'echo "GEMINI_API_KEY=your_gemini_api_here" >> /etc/environment'
		echo "Please edit /etc/environment and replace 'your_gemini_api_here' with your actual API key."
		echo "Then reboot or run: source /etc/environment"
	else
		log "GEMINI_API_KEY found in /etc/environment."
	fi

	log "GPTScript installation complete."

	echo
	echo "To activate the Python environment for GPTScript (fish shell):"
	echo "  source $GPTSCRIPT_DIR/venv/bin/activate.fish"
	echo
	echo "To run GPTScript:"
	echo "  $GPTSCRIPT_DIR/gpt_inline_auto.py"
	echo
	echo "Or bind it in your window manager keybindings."
}

setup_ssh() {
	if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
		warn "SSH key already exists. Skipping."
	else
		log "Generating new SSH key..."
		ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N ""
	fi

	log "Adding key to ssh-agent..."
	eval "$(ssh-agent -s)"
	ssh-add ~/.ssh/id_ed25519

	echo -e "\n🔐 Public SSH Key:\n"
	cat ~/.ssh/id_ed25519.pub
	echo -e "\n➡️  Add this key to GitHub (Settings > SSH and GPG Keys)"
}

#NOTE: NEEDED TO ADD:
## espanso register and start command  -> for the auto replacement words ex: :soy  =>"Eid"

# --- Main Script Execution ---
main() {
	refresh_system
	clean_system
	stow_dotfiles
	install_packages
	install_cli_tools
	setup_touchpad
	setup_dev_tools
	setup_ssh
	install_gptscript
	log "🚀 All done! You may want to reboot or logout now."
}

main
