# install/login/all.sh — login phase: step_*/uninstall_* functions for the
# modules classified into this phase, extracted verbatim from wizard.sh
# (no behavior change) as part of splitting the installer into Omarchy-
# style phase directories. wizard.sh sources this file; module dispatch
# (_reg/_run_module/UMOD_CMD) is unchanged and still lives in wizard.sh /
# install/lib/registry.sh.

step_boot_splash() {
  # Part of the default run, but the riskiest thing in it: this edits
  # /etc/mkinitcpio.conf and the kernel cmdline and rebuilds the initramfs.
  # What makes that acceptable is the module ORDER -- boot-fallback runs
  # immediately before this and leaves behind LTS entries that carry
  # neither quiet nor splash, so the worst case is one menu pick away from
  # a fully verbose boot. Do not move this above boot-fallback.
  #
  # `boot-splash enable` refuses rather than half-applies (do_check ||
  # die), so a machine it cannot handle -- no /etc/kernel/cmdline, no
  # plymouth, an unsupported bootloader -- ends with the module marked
  # failed and the boot path untouched, not with a system that comes up
  # black.
  local mod="$DOTFILES_DIR/.config/arch-config/modules/splash.yaml"
  local bs="$DOTFILES_DIR/.config/AtiScriptsV1/system/boot-splash"
  [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
  [[ -x "$bs" ]] || { _ERR "missing $bs"; return 1; }

  local pkgs; pkgs="$(_pkgs_from_module "$mod" | tr '\n' ' ')"
  run "sudo pacman -S --needed --noconfirm $pkgs"

  # The LTS rescue entries are rewritten WITHOUT quiet/splash (see the
  # token filter in step_boot_fallback), so a splashed boot that hangs can
  # always be diagnosed from the fallback entry.
  run "$bs enable"
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
  esp="$(sudo_probe bootctl --print-esp-path 2>/dev/null)" || esp=""
  [[ -n "$esp" ]] || esp=/boot
  if ! sudo_probe test -d "$esp/loader/entries"; then
    _WARN "$esp/loader/entries missing — systemd-boot not installed here, skipping"; return 0
  fi
  if ! sudo_probe test -e "$esp/vmlinuz-linux-lts"; then
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
  #
  # initrd= and BOOT_IMAGE= go too, and that one is not cosmetic. This
  # machine boots a UKI, whose cmdline carries neither -- but a plain
  # systemd-boot or GRUB install puts `initrd=\initramfs-linux.img` (the
  # STOCK kernel's image) right there in /proc/cmdline. Copying it into an
  # LTS entry hands the LTS kernel the stock kernel's modules alongside the
  # `initrd` line below, and the rescue entry you finally reach for panics
  # on a module version mismatch. BOOT_IMAGE= is the same shape of stale
  # self-reference, pointing at whichever kernel booted this time.
  opts="$(tr ' ' '\n' <<<"$opts" \
    | grep -vxE 'quiet|splash' \
    | grep -vE '^(initrd|BOOT_IMAGE)=' \
    | paste -sd' ' -)"

  # /proc/cmdline is authoritative for root= on every normal install, but it
  # is not guaranteed to CONTAIN one. A system booting under the discoverable
  # partitions spec (systemd-gpt-auto-generator) finds its root from the GPT
  # type GUID and carries no root= at all -- and the generator lives in the
  # initramfs, so an LTS rescue image built without it gets a kernel with no
  # idea where root is. That is an emergency shell on the one entry that
  # exists for emergencies. Derive it from the running root instead.
  local real_root_uuid=""
  if ! grep -qE '(^|[[:space:]])root=' <<<"$opts"; then
    local root_src; root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    [[ -n "$root_src" ]] && real_root_uuid="$(lsblk -no PARTUUID "$root_src" 2>/dev/null | head -1 | tr -d '[:space:]' || true)"
    if [[ -n "$real_root_uuid" ]]; then
      opts="root=PARTUUID=$real_root_uuid $opts"
      _DIM "  no root= in /proc/cmdline (gpt-auto?) — derived root=PARTUUID=$real_root_uuid"
    else
      _WARN "no root= in /proc/cmdline and could not derive one — the LTS entries may not boot"
    fi
  fi
  # Microcode is vendor-specific and optional; only reference what exists.
  # Match it to the CPU, not to whatever image happens to be on the ESP: a
  # machine that once ran the other vendor's ucode package (or installed
  # both) left amd-ucode.img sitting there, and the unconditional loop below
  # took the last hit -- so an Intel box got an AMD microcode image and no
  # errata fixes at all on the entry it boots when things are already wrong.
  local ucode_line="" ucode_img=""
  case "$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)" in
    GenuineIntel) ucode_img=intel-ucode.img ;;
    AuthenticAMD) ucode_img=amd-ucode.img   ;;
  esac
  [[ -n "$ucode_img" ]] && sudo_probe test -e "$esp/$ucode_img" \
    && ucode_line="initrd  /$ucode_img"

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
  if sudo_probe test -f "$preset"; then
    if sudo_probe grep -q "^PRESETS=.*fallback" "$preset"; then
      _DIM "  fallback preset already enabled"
    else
      run "sudo sed -i \"s/^PRESETS=.*/PRESETS=('default' 'fallback')/\" $preset"
    fi
    # -S autodetect drops the autodetect hook: every module ships, not just
    # the ones probed on this machine. ~205MB, and worth it.
    sudo_probe grep -q "^fallback_options" "$preset" \
      || run "echo \"fallback_options=\\\"-S autodetect\\\"\" | sudo tee -a $preset >/dev/null"
    run "sudo mkinitcpio -p linux-lts"
  else
    _WARN "$preset missing — skipping rescue initramfs"
  fi

  if (( DRY_RUN )) || sudo_probe test -e "$esp/initramfs-linux-lts-fallback.img"; then
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
  if sudo_probe test -f "$lc" && ! sudo_probe grep -qE '^timeout[[:space:]]+[0-9]+' "$lc"; then
    run "echo 'timeout 5' | sudo tee -a $lc >/dev/null"
  fi
  # Verify what actually landed on disk, rather than trusting that the
  # here-doc above said what we meant. An entry whose root= names a device
  # that does not exist looks completely fine in the boot menu and drops to
  # an emergency shell only when you finally need it -- the failure mode
  # this module exists to prevent. boot-splash owns the comparison; it is
  # read-only, and it checks every entry on the ESP, not just ours.
  if (( ! DRY_RUN )); then
    local bs="$DOTFILES_DIR/.config/AtiScriptsV1/system/boot-splash"
    if [[ -x "$bs" ]]; then
      local vout vrc=0
      vout="$("$bs" verify-root 2>&1)" || vrc=$?
      case "$vrc" in
        0) _DIM "  every boot entry's root= matches $(findmnt -no SOURCE / 2>/dev/null)" ;;
        2) _DIM "  boot entries not verified (ESP unreadable)" ;;
        *) _WARN "a boot entry names the wrong root device:"; printf '%s\n' "$vout" ;;
      esac
    fi
    _DIM "  verify with: bootctl list"
  fi
}

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

uninstall_login_shell() {
  # Pick a shell that exists on THIS machine rather than assuming Arch's
  # /usr/bin/bash. chsh refuses a path it cannot find, so on a box where
  # bash lives only at /bin/bash the reversal failed and left the account
  # logging into fish -- an uninstall that reports success and undoes
  # nothing is worse than one that never ran.
  local sh fallback=/bin/sh
  for sh in /usr/bin/bash /bin/bash /usr/bin/zsh /bin/sh; do
    [[ -x "$sh" ]] && { fallback="$sh"; break; }
  done
  run "sudo chsh -s $fallback $(id -un)"
}

uninstall_boot_splash() {
  # This one MUST really reverse: leaving the plymouth hook in the
  # initramfs after removing the theme boots to a black screen.
  local bs
  bs="$(command -v boot-splash || echo "$DOTFILES_DIR/.config/AtiScriptsV1/system/boot-splash")"
  # if/else, because `A && B || C` here reported "boot-splash not found"
  # whenever `boot-splash disable` FAILED, and returned 0 while doing it --
  # so the uninstall ticked green on the one module whose whole point is
  # that a half-reversal boots to a black screen.
  if [[ -x "$bs" ]]; then
    run "$bs disable"
  else
    _WARN "boot-splash not found — cmdline may still say quiet splash"
  fi
}

uninstall_disable_dm()        { :; }
