# install/post-install/all.sh — post-install phase: step_*/uninstall_* functions for the
# modules classified into this phase, extracted verbatim from wizard.sh
# (no behavior change) as part of splitting the installer into Omarchy-
# style phase directories. wizard.sh sources this file; module dispatch
# (_reg/_run_module/UMOD_CMD) is unchanged and still lives in wizard.sh /
# install/lib/registry.sh.

# mkdir first: `tee` cannot create the directory it writes into, and
# /etc/X11/xorg.conf.d is not guaranteed to exist -- it ships with
# xorg-server, so on a machine where X is installed later (or where the
# module runs with --only before bootstrap) tee failed with "No such file
# or directory" and tap-to-click was silently never configured.
step_touchpad()     { run "sudo mkdir -p /etc/X11/xorg.conf.d"
                      run "sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null << 'EOF'
Section \"InputClass\"
    Identifier \"Touchpad\"
    MatchIsTouchpad \"on\"
    Driver \"libinput\"
    Option \"Tapping\" \"on\"
EndSection
EOF"; }

step_lid() {
  # A drop-in, not `sed -i` on /etc/systemd/logind.conf.
  #
  # The sed depended on a commented `#HandleLidSwitch=` line being present
  # to rewrite. That is true of the logind.conf this machine was installed
  # with and false in general -- current systemd ships the file with the
  # defaults documented elsewhere, and a machine whose logind.conf has been
  # tidied or replaced simply had no line to match. sed then exited 0
  # having changed nothing, the module reported ✔ ok, and the laptop still
  # suspended the moment you shut the lid. A drop-in always applies, needs
  # no line to already exist, survives systemd upgrades without a .pacnew,
  # and is reversed by deleting one file.
  if [[ ! -d /etc/systemd ]]; then
    _WARN "no /etc/systemd — not a systemd machine, skipping lid setting"; return 0
  fi
  run "sudo install -d -m 755 /etc/systemd/logind.conf.d"
  run "sudo tee /etc/systemd/logind.conf.d/90-wizard-lid.conf >/dev/null << 'EOF'
# Never sleep on lid close. Written by wizard.sh (lid module).
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF"
  run "sudo systemctl restart systemd-logind"
}

step_flatpak()      { _OK "Nothing to install — flatpak/collector replaced by qdrop"; }

# Vaultwarden: the password server behind Mod+p p (ati-pass -> rbw).
#
# The packages come from arch-config (apps.yaml); this module does the
# part packages cannot: bind the server to loopback, point it at the web
# vault, start it, and aim rbw at it.
#
# Settings live in /etc/vaultwarden.local.env, referenced from a systemd
# drop-in, rather than in /etc/vaultwarden.env. Two separate reasons:
#
#   * That file is 32KB of commented upstream defaults owned by the
#     package, so local edits get clobbered on upgrade or leave a
#     .pacnew to merge by hand.
#   * It must be EnvironmentFile=, not Environment=. systemd applies
#     EnvironmentFile= AFTER Environment=, so the packaged file (which
#     sets WEB_VAULT_ENABLED=false) beats any Environment= line a
#     drop-in adds -- verified the hard way: ROCKET_* took effect
#     because the packaged file does not set them, while the web vault
#     stayed off and served 404 until this was an EnvironmentFile.
#
# Deliberately loopback-only. Reaching this from the phone is a Tailscale
# job (see README) -- never an open port. And the account itself is not
# created here: that needs a master password, which is yours to choose.
step_vaultwarden() {
  if ! command -v vaultwarden >/dev/null 2>&1; then
    _WARN "vaultwarden not installed -- skipping (check arch-config apps.yaml)"
    return 0
  fi

  local dropin=/etc/systemd/system/vaultwarden.service.d/10-local.conf
  local envfile=/etc/vaultwarden.local.env
  (( DRY_RUN )) && { _DIM "  [dry] write $envfile + $dropin, enable vaultwarden.service"; return 0; }

  # TLS is not optional here. The Bitwarden web vault hard-checks the
  # URL prefix in its bundle:
  #   if (!url.startsWith("https://") && !isDev()) throw "Insecure URL"
  # There is no localhost or 127.0.0.1 exception, so over plain http the
  # signup page dies with "Insecure URL not allowed" before you can
  # create the account.
  #
  # mkcert rather than a bare openssl self-signed cert: it installs its
  # local CA into the system trust store AND the browser's NSS store, so
  # Brave shows no warning page and rbw's TLS verification passes. A
  # self-signed cert would need --insecure-style workarounds in both.
  local tlsdir=/var/lib/vaultwarden/tls
  if command -v mkcert >/dev/null 2>&1; then
    if [[ ! -s "$tlsdir/cert.pem" ]]; then
      run "mkcert -install"
      local tmpc; tmpc="$(mktemp -d)"
      ( cd "$tmpc" && mkcert -cert-file vw.crt -key-file vw.key 127.0.0.1 localhost ::1 >/dev/null 2>&1 )
      run "sudo install -d -m 750 -o vaultwarden -g vaultwarden $tlsdir"
      run "sudo install -o vaultwarden -g vaultwarden -m 644 $tmpc/vw.crt $tlsdir/cert.pem"
      run "sudo install -o vaultwarden -g vaultwarden -m 640 $tmpc/vw.key $tlsdir/key.pem"
      rm -rf "$tmpc"
    fi
  else
    _WARN "mkcert missing -- vaultwarden will run on http, and the web vault"
    _WARN "signup page will refuse to load (\"Insecure URL not allowed\")."
  fi

  sudo tee "$envfile" >/dev/null <<'EOF'
# Local Vaultwarden overrides, written by the dotfiles wizard.
ROCKET_ADDRESS=127.0.0.1
ROCKET_PORT=8222
WEB_VAULT_ENABLED=true
WEB_VAULT_FOLDER=/usr/share/webapps/vaultwarden-web
EOF
  if [[ -s "$tlsdir/cert.pem" ]]; then
    printf 'ROCKET_TLS={certs="%s/cert.pem",key="%s/key.pem"}\n' "$tlsdir" "$tlsdir" |
      sudo tee -a "$envfile" >/dev/null
  fi
  run "sudo chmod 640 $envfile"
  run "sudo install -d -m 755 /etc/systemd/system/vaultwarden.service.d"
  sudo tee "$dropin" >/dev/null <<'EOF'
# Local Vaultwarden setup, written by the dotfiles wizard.
# EnvironmentFile, not Environment: see /etc/vaultwarden.local.env.
[Service]
EnvironmentFile=/etc/vaultwarden.local.env
EOF
  run "sudo systemctl daemon-reload"
  run "sudo systemctl enable --now vaultwarden.service"

  # Aim rbw at the local server. Email stays unset: ati-pass asks for it
  # on first run, because it is per-person rather than per-machine.
  if command -v rbw >/dev/null 2>&1; then
    run "rbw config set base_url https://127.0.0.1:8222"
    run "rbw config set pinentry pinentry-gtk"
    run "rbw config set lock_timeout 900"
  fi
}


# Phone access to the local Vaultwarden, over Tailscale.
#
# Everything here is idempotent and safe to re-run: it enables the
# daemon, and once you are logged in it publishes the proxy. It cannot
# log you in -- that needs a browser and your account -- so on a fresh
# machine it prints the URL and stops, and you re-run it (or just run
# ./wizard.sh --yes --only=vaultwarden-phone) afterwards.
#
# `tailscale serve` rather than rebinding vaultwarden to the tailnet IP:
# one process can only bind one address, so rebinding would take
# 127.0.0.1 away and break ati-pass and the browser extension. The
# proxy terminates TLS with the tailnet's own publicly-trusted cert and
# forwards to the local https listener, so both paths keep working and
# nothing is exposed to the LAN.
step_vaultwarden_phone() {
  if ! command -v tailscale >/dev/null 2>&1; then
    _WARN "tailscale not installed -- skipping (check arch-config network.yaml)"
    return 0
  fi

  (( DRY_RUN )) && { _DIM "  [dry] enable tailscaled + tailscale serve -> 127.0.0.1:8222"; return 0; }

  run "sudo systemctl enable --now tailscaled"

  # Logged in? `tailscale status` says "Logged out." and exits non-zero.
  local dnsname=""
  dnsname="$(tailscale status --json 2>/dev/null |
    sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  dnsname="${dnsname%.}"

  if [[ -z "$dnsname" ]]; then
    _WARN "tailscale is not logged in yet. Run:"
    _WARN "    sudo tailscale up"
    _WARN "then re-run:  ./wizard.sh --yes --only=vaultwarden-phone"
    return 0
  fi

  # Publish the proxy. Do NOT pre-flight this with `tailscale cert`:
  # that command refuses to write to /dev/null, so a probe using it
  # reports failure even when certificates work perfectly -- which is
  # exactly what an earlier version of this module did. Run the real
  # thing and read its exit status.
  #
  # It fails while MagicDNS and HTTPS Certificates are off in the admin
  # console ("your Tailscale account does not support getting TLS
  # certs"). Nothing local can enable those, hence the hint.
  if sudo tailscale serve --bg "https+insecure://127.0.0.1:8222" >/dev/null 2>&1; then
    _DIM "  phone URL:  https://${dnsname}"
    _DIM "  set that as Bitwarden's self-hosted server, before logging in."
  else
    _WARN "Could not publish the Vaultwarden proxy for $dnsname."
    _WARN "Enable BOTH at https://login.tailscale.com/admin/dns :"
    _WARN "    MagicDNS   ·   HTTPS Certificates"
    _WARN "then re-run:  ./wizard.sh --yes --only=vaultwarden-phone"
  fi
}


step_radios() {
  # Declaring a package installs a binary, not a running daemon. dcli puts
  # networkmanager and bluez on the disk; nothing until now started either,
  # and archinstall is what enabled them on the machine this repo was
  # written on -- so a fresh install got nm-applet and blueman-applet in
  # the tray with no daemon behind them, and both qtile popups (Mod+P then
  # n / b) failing with "NetworkManager is not running".
  #
  # Two managers on one interface is how you get a link that flaps between
  # them, so archinstall's alternative is stood down first. iwd is NOT
  # touched: no wifi.backend is shipped, which means NetworkManager drives
  # wpa_supplicant -- but if this machine has been pointed at iwd by hand,
  # disabling it would take the wifi with it. Left to the operator.
  local svc
  if systemctl is-enabled systemd-networkd.service &>/dev/null; then
    run "sudo systemctl disable --now systemd-networkd.service"
  fi

  for svc in NetworkManager.service bluetooth.service; do
    if systemctl is-enabled "$svc" &>/dev/null; then
      _OK "$svc already enabled"
    else
      run "sudo systemctl enable --now $svc"
    fi
  done
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


step_ydotool() {
  # ydotool -- xdotool's Wayland-native (uinput) counterpart. Opt-in: it's
  # test/automation tooling (hypr/scripts/test/uinput-click.py's click
  # path), not something the live session should ever be driven through --
  # see no-synthetic-input-in-live-session. optional.yaml declares the
  # package for `wizard.sh --audit`; this just makes `--only=ydotool`
  # self-sufficient without also requiring dcli-sync-extra.
  if (( DRY_RUN )); then _DIM "  [dry] pacman -S --needed ydotool, enable --now ydotool.service"; return; fi
  command -v ydotool >/dev/null 2>&1 || run "sudo pacman -S --needed --noconfirm ydotool"
  run "systemctl --user daemon-reload"
  run "systemctl --user enable --now ydotool.service"
}

uninstall_ydotool() {
  run "systemctl --user disable --now ydotool.service" || true
}

step_scrcpy() {
  # scrcpy mirrors the Android screen over adb. Declaring the package is
  # not enough: android-udev's rules assign the phone's USB node to the
  # `adbusers` group, and an account outside that group gets `adb devices`
  # listing the serial with "no permissions" next to it -- the device is
  # visible, so it reads as a bad cable or a bad phone rather than a
  # missing group. Same shape as radios: the package installs a tool, this
  # makes the tool usable.
  if ! getent group adbusers >/dev/null; then
    # android-udev creates the group in its post_install. If it is absent,
    # the rules are absent too, and adding the user to a group nothing
    # references would be a silent no-op that looks like success.
    _WARN "no adbusers group — install android-udev first (dcli-sync)"
    return 0
  fi

  if id -nG "$(id -un)" | grep -qw adbusers; then
    _OK "already in adbusers"
  else
    run "sudo gpasswd -a $(id -un) adbusers"
    # Group membership is baked into the login session's credentials, so
    # the shell that ran this still has the old set no matter what the
    # group file now says.
    _WARN "log out and back in before adb can see the phone"
  fi

  # ─── mDNS, which is what makes the wireless path automatic ─────────
  # ati-phone-screen (Mod+Shift+A) finds the phone's wireless-debugging
  # host:port from its own mDNS announcement rather than making you copy
  # a fresh random port off the phone every session. Arch's android-tools
  # is built without mDNS, so avahi does that lookup -- and an installed
  # but stopped avahi-daemon looks exactly like "no phone on the network".
  if systemctl is-enabled avahi-daemon.service &>/dev/null; then
    _OK "avahi-daemon already enabled"
  else
    run "sudo systemctl enable --now avahi-daemon.socket avahi-daemon.service"
  fi

  # ufw is enabled by system-tools, and it drops inbound by default. mDNS
  # replies arrive as fresh inbound UDP on 5353 (multicast, not a reply to
  # a tracked flow), so without this the browse simply returns nothing --
  # no error, no log line, just a phone that is never found.
  if command -v ufw >/dev/null && sudo_probe ufw status 2>/dev/null | grep -q '^Status: active'; then
    if sudo_probe ufw status 2>/dev/null | grep -q '5353'; then
      _OK "ufw already allows mDNS"
    else
      run "sudo ufw allow 5353/udp comment 'mDNS - adb wireless discovery'"
    fi
  fi

  # ─── the pieces ati-phone-screen leans on ──────────────────────────────
  # All four are declared in modules dcli-sync already installed, so this
  # is a check rather than an install -- but each one fails in a way that
  # is hard to read from the outside: no qrencode and the pairing dialog
  # has no QR, no rofi and it has no window at all, no xdotool and both
  # the "focus the mirror I already have" shortcut and the rotation
  # watcher quietly do nothing.
  local miss=() bin
  for bin in scrcpy adb avahi-browse qrencode rofi xdotool; do
    command -v "$bin" >/dev/null || miss+=("$bin")
  done
  if (( ${#miss[@]} )); then
    _WARN "missing for ati-phone-screen: ${miss[*]} — run dcli sync"
  else
    _OK "ati-phone-screen has everything it needs"
  fi

  _DIM "  phone: Settings > About > tap Build number 7x > Developer options"
  _DIM "  then turn on Wireless debugging (stays on across reboots)"
  _DIM "  then press Super+Shift+F6 — it pairs itself (QR or 6 digits), once ever"
}


# sudo(8): files in sudoers.d "whose names end in ~ or contain a . character
# are ignored". The filename was built straight from the login name, so an
# account like `john.doe` -- anything LDAP/AD-joined, which is most machines
# that are not this one -- got a drop-in sudo silently never reads. The module
# reported ✔ ok and sudo went on asking for a password with nothing on disk to
# explain why. Same transform on both sides so uninstall still finds the file.
_nopasswd_file()    { printf '/etc/sudoers.d/zz-%s-nopasswd' "$(id -un | tr '.' '_')"; }
step_nopasswd() {
  local f; f="$(_nopasswd_file)"
  run "echo \"$(id -un) ALL=(ALL) NOPASSWD: ALL\" | sudo tee $f >/dev/null && sudo chmod 440 $f"
  # A sudoers file sudo refuses to parse breaks EVERY sudo invocation on the
  # box, including the one that would delete it. Check, and take it back out
  # ourselves while we still can.
  if (( ! DRY_RUN )) && ! sudo visudo -cf "$f" >/dev/null 2>&1; then
    sudo rm -f "$f"
    _ERR "generated sudoers file was rejected by visudo — removed it again"
    return 1
  fi
}

# $(id -gn), not a second $(id -un): a user-private group of the same name is
# an Arch default, not a guarantee. On an account whose primary group is
# `users` (or a domain group), `chown ati:ati` fails outright with "invalid
# group" and the whole ownership fix-up never happens.
step_ownership()    { run "sudo chown -R $(id -un):$(id -gn) $DOTFILES_DIR"; }

step_speed()        { run "$DOTFILES_DIR/installScripts/speed_boost.sh"; }

uninstall_touchpad()         { run "sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf"; }

uninstall_passwordless_sudo(){ run "sudo rm -f $(_nopasswd_file)"; }

uninstall_lid() {
  # Drop the drop-in, AND still undo the old in-place edit: a machine set up
  # by an earlier wizard has `HandleLidSwitch=ignore` written into
  # logind.conf itself, and removing only the new file would leave it
  # ignoring the lid forever with nothing left to point at as the cause.
  run "sudo rm -f /etc/systemd/logind.conf.d/90-wizard-lid.conf"
  run "sudo sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=suspend/; s/^HandleLidSwitchExternalPower=ignore/#HandleLidSwitchExternalPower=suspend/; s/^HandleLidSwitchDocked=ignore/#HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf 2>/dev/null || true"
  run "sudo systemctl restart systemd-logind"
}

# Deliberately a no-op. Disabling NetworkManager to "reverse" an install is
# how you end up on a machine with no way to reach the internet and no GUI
# to fix it; bluetooth follows the same reasoning. Turn either off by hand
# (or with service_trim.sh) if you really do not want it.
uninstall_radios()            { :; }

uninstall_flatpak()           { :; }

# Drops the proxy only. Tailscale itself stays up -- it is a general
# purpose network, not something this module owns.
uninstall_vaultwarden_phone() {
  run "sudo tailscale serve --https=443 off" || true
}

# Stops the server and drops the drop-in. /var/lib/vaultwarden -- the
# actual vault -- is deliberately left alone: deleting someone's
# passwords is not something an uninstaller should do quietly.
uninstall_vaultwarden() {
  run "sudo systemctl disable --now vaultwarden.service" || true
  run "sudo rm -f /etc/systemd/system/vaultwarden.service.d/10-local.conf"
  run "sudo rm -f /etc/vaultwarden.local.env"
  run "sudo rm -rf /var/lib/vaultwarden/tls"
  run "sudo systemctl daemon-reload" || true
  _DIM "  vault data kept at /var/lib/vaultwarden (delete by hand if you mean it)"
}

uninstall_mic_gain() {
  run "systemctl --user disable --now fix-mic-gain.service" || true
}

# Drops the group membership and the mDNS firewall rule. android-udev's
# rules stay (pacman owns those files), and avahi-daemon stays running:
# it is a general network service that cups and chromium also use, not
# something this module owns.
uninstall_scrcpy() {
  if getent group adbusers >/dev/null; then
    run "sudo gpasswd -d $(id -un) adbusers" || true
  fi
  if command -v ufw >/dev/null; then
    run "sudo ufw delete allow 5353/udp" || true
  fi
}

uninstall_ownership()         { :; }

uninstall_speed()             { :; }

# grub_boost.sh (installScripts/) was on disk since before the phase split
# but never registered as a module — no MOD_ORDER entry meant no --only
# target and no picker line, so the only way to run it was `./grub_boost.sh`
# by hand from installScripts/. It is genuinely safe to automate: it backs
# up /etc/default/grub before editing, only adds flags not already present,
# and exits 0 with a clear message on any machine that isn't GRUB (systemd-
# boot, rEFInd, a UKI) rather than failing. Opt-in anyway (see OPTIN_MODS in
# registry.sh) because it edits the kernel cmdline, and that is not a change
# to make without asking even when the script itself is careful.
step_grub_boost() {
  run "$DOTFILES_DIR/installScripts/grub_boost.sh"
}
# Reversal is a real file restore (sudo cp the timestamped .bak grub_boost.sh
# just wrote, then grub-mkconfig), not something safe to automate blindly --
# picking the WRONG backup or running this after grub_boost.sh has been run
# twice would silently restore the wrong cmdline. Point at the fix instead.
uninstall_grub_boost() {
  _WARN "grub_boost.sh edits /etc/default/grub directly — reverse it by hand:"
  _WARN "  sudo cp /etc/default/grub.bak.<TIMESTAMP> /etc/default/grub"
  _WARN "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
  _WARN "  (see the .bak.* files next to /etc/default/grub for the timestamp)"
}

# service_trim.sh (installScripts/) is deliberately NOT a module here: it
# prompts y/n per service in an interactive loop, and _run_module captures
# a step's stdout behind a spinner into /tmp/wizard-<id>.log -- the same
# reason step_simplenote defers its credential prompt to a page_* function
# instead of asking inline (see that module's comment). A per-service
# interactive audit does not have a page_* analog worth building for one
# script; it stays a manual `./service_trim.sh`, same as before this split
# (see the "or with service_trim.sh" mention above, in uninstall_radios's
# comment).
