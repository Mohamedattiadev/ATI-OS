# install/lib/registry.sh — the module manifest: what wizard.sh can install,
# in what order, and which ids default off. Extracted verbatim from
# wizard.sh's "MODULE DEFINITIONS" section (no behavior change) as the
# second step of splitting the installer into phase directories.
#
# Sourced early, before the --audit/--help top-level branches in wizard.sh:
# _reg() calls only populate associative arrays (no output, no side
# effects), so running them earlier than before is safe — --help still
# exits before wizard.sh's _validate_ids calls run (those stay in
# wizard.sh, at their original position, so `--help --only=badid` keeps
# printing help and exiting 0 rather than newly erroring on the bad id).

# Each module: id | group | title | 1-line desc | shell to execute
# Group is only used for the picker header — keep display order stable.
declare -A MOD_TITLE MOD_DESC MOD_GROUP MOD_CMD
MOD_ORDER=(
  sanity bootstrap yay dcli stow arch-config paths dcli-sync radios gpu picom-pin cargo ati-scripts hintium simplenote ui-scale githooks
  pacman-guard boot-fallback boot-splash login-shell
  touchpad xinit xresources xmodmap system-files keyd lid image-envs flatpak piper ankiconnect vaultwarden vaultwarden-phone tmux-tpm voxtype
  mic-gain scrcpy
  passwordless-sudo ownership disable-dm candy-icons wallpapers speed
  themes dark-mode browser-flags browser-memory chrome-policy
  dcli-sync-extra grub-boost ydotool
)

# Opt-in modules: valid --only= targets, and listed (unchecked) in the
# interactive picker, but never part of a default `./install.sh` run.
#
# install.sh's promise is a working DESKTOP -- qtile, themes, fonts,
# widgets -- not a working workstation. Docker, a JDK, printing and qemu
# are a second pass you run when you actually need them, on your own
# schedule. Keeping them out of round one is what lets the first boot
# stay short and stay predictable.
#
# boot-splash used to be here. It is part of the default run now: the boot
# screen is as much of the look as the bar is, and leaving it out meant a
# machine installed from this repo still booted to a wall of kernel log.
# What made it safe to promote is ORDERING -- it sits immediately after
# boot-fallback in MOD_ORDER, so the verbose LTS entries (written without
# quiet/splash on purpose) always exist before anything touches the
# cmdline of the primary one. A splashed boot that hangs is then one menu
# pick away from a boot that tells you why.
#
# system-files is opt-in for a third reason, and it is a dependency of the
# second one: system/ currently holds exactly one file,
# etc/keyd/default.conf, and keyd is opt-in. A default system-files would
# write a keyd config onto every fresh machine INCLUDING the ones that
# deliberately skipped keyd -- inert, since the service is not enabled
# there, but still this repo putting a file in /etc for a feature the user
# said no to. The keyd module installs that file itself (same helper, same
# source), so nothing is lost by keeping the generic walker off the default
# path.
#
# Revisit this the day system/ holds a file that is NOT tied to an opt-in
# module. At that point the walker has something every machine needs and
# belongs in the default run -- and the docs' step count and the step table
# in docs/install-git.html have to move with it, which validate.sh will
# insist on.
#
# xmodmap is opt-in for a different reason: it is correct for exactly one
# machine. It repurposes Caps Lock as a third Alt because Alt is dead in
# hardware on the author's laptop -- which nothing can detect at runtime,
# so it cannot be conditionalised. On any other machine the remap is not
# wrong so much as unwanted: `clear mod1` is immediately followed by
# `add mod1 = Alt_L Alt_R`, so the real Alt keys keep working and the only
# actual loss is Caps Lock itself, silently and with no tap-to-Caps
# fallback. A stranger installing this repo should get a normal keyboard.
# On the laptop that needs it:  ./wizard.sh --only=xmodmap
# grub-boost is opt-in because it edits the kernel cmdline via
# /etc/default/grub -- the script itself is careful (backs up first, only
# adds missing flags, no-ops cleanly on a non-GRUB machine), but that is
# not a change to make without asking even so.
OPTIN_MODS=(dcli-sync-extra xmodmap system-files keyd grub-boost ydotool)
_is_optin() {
  local id m
  id="$1"
  for m in "${OPTIN_MODS[@]}"; do [[ "$m" == "$id" ]] && return 0; done
  return 1
}

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
_reg radios            "Network + Bluetooth" System    "Enable NetworkManager + bluetooth so the Mod+P popups have a daemon" "step_radios"
_reg gpu               "GPU + microcode"     System    "Detect Intel/AMD/NVIDIA from PCI ids, install matching drivers" "step_gpu"
_reg picom-pin         "picom (pinned)"      System    "Build the animation fork from a fixed commit, not branch HEAD"  "step_picom_pin"
_reg cargo             "Cargo tools"         System    "pomodoro-tui"                                           "step_cargo"
_reg ati-scripts       "AtiScriptsV1"        Dotfiles  "Install ati-kill · theme-apply · etc to /usr/local/bin" "step_ati_scripts"
_reg hintium           "Hintium"             Apps      "Hint, scroll and caret modes driven from the home row"   "step_hintium"
_reg simplenote        "Simplenote push"     Apps      "Mirror the Mod+Shift+S TODOS note to your phone (asks for login at the end)" "step_simplenote"
_reg touchpad          "Touchpad tap"        System    "Enable tap-to-click"                                    "step_touchpad"
_reg pacman-guard      "Pacman safety hook"  System    "PreTransaction gate: refuse upgrades when / is too full"  "step_pacman_guard"
_reg boot-fallback     "LTS boot entries"    System    "systemd-boot entries for linux-lts + a rescue initramfs"  "step_boot_fallback"
_reg login-shell       "Fish login shell"    System    "chsh to fish so the TTY matches kitty (letsgo, aliases)" "step_login_shell"
_reg xinit             ".xinitrc"            Dotfiles  "Auto-start qtile + picom + cursor size"                 "step_xinit"
_reg xresources        ".Xresources"         Dotfiles  "Xcursor size 24 + Breeze theme (load via xrdb)"         "step_xresources"
_reg xmodmap           ".Xmodmap"            Optional  "Caps fully repurposed as Alt · opt-in · one broken-Alt laptop" "step_xmodmap"
_reg system-files      "Files outside \$HOME"  System    "Copy system/ to its real paths · /etc/keyd/default.conf and anything added beside it" "step_system_files"
_reg keyd              "keyd Caps→Alt"       Optional  "The same remap below the display server · works on X11 AND Wayland" "step_keyd"
_reg lid               "Lid = ignore"        System    "Never sleep on lid close"                               "step_lid"
_reg image-envs        "Image env"           Dotfiles  "Suppress VIPS warnings + ensure ~/tmp (fish TMPDIR)"    "step_image_envs"
_reg flatpak           "Flatpak (legacy)"    Apps      "Uninstall-only: qdrop replaced flathub/collector"       "step_flatpak"
_reg piper             "Piper voices"        Media     "EN + DE TTS voices (~60MB)"                             "step_piper"
_reg ankiconnect       "AnkiConnect"         Media     "Anki addon rofi_anki talks to on :8765 (~26KB)"          "step_ankiconnect"
_reg vaultwarden       "Vaultwarden"         Apps      "Local password server on :8222 + rbw for Mod+p p"        "step_vaultwarden"
_reg vaultwarden-phone "Vaultwarden on phone" Apps     "Tailscale proxy so the Bitwarden app can reach it"        "step_vaultwarden_phone"
_reg tmux-tpm          "tmux plugins (TPM)"  Dotfiles  "Clone TPM + install plugins (was a manual README step)"   "step_tmux_tpm"
_reg voxtype           "Voxtype dictation"   Media     "voxtype-bin (AUR) + base.en model (~150MB) + systemd service, Alt+F8" "step_voxtype"
_reg mic-gain          "Mic gain fix"        System    "Reassert mic capture gain WirePlumber resets on login"  "step_mic_gain"
_reg scrcpy            "Android screen"      Apps      "adbusers + avahi + mDNS through ufw, so Super+Shift+F6 finds the phone" "step_scrcpy"
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
# No comma in the desc: page_module_picker hands gum a CSV of preselected
# option LINES, and a comma inside one splits it into two entries that match
# nothing -- silently unchecking whatever followed it.
_reg dcli-sync-extra   "Optional packages"   Optional  "docker · jdk · qemu · printing (opt-in · run later)"    "step_dcli_sync_extra"
_reg grub-boost        "GRUB cmdline flags"  Optional  "opt-in · no-ops on systemd-boot/rEFInd/UKI · backs up first" "step_grub_boost"
_reg ydotool           "ydotool"             Optional  "Wayland input-injection daemon -- test/automation tooling only" "step_ydotool"
_reg boot-splash       "Boot splash"         System    "Your name + progress ring instead of kernel text at boot" "step_boot_splash"
