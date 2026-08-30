# install/config/all.sh — config phase: step_*/uninstall_* functions for the
# modules classified into this phase, extracted verbatim from wizard.sh
# (no behavior change) as part of splitting the installer into Omarchy-
# style phase directories. wizard.sh sources this file; module dispatch
# (_reg/_run_module/UMOD_CMD) is unchanged and still lives in wizard.sh /
# install/lib/registry.sh.

step_stow()         { run "$DOTFILES_DIR/installScripts/stow_script.sh"; }

step_arch_config()  { run "$DOTFILES_DIR/installScripts/arch-config.sh"; }

step_paths() {
  # Seed ~/.config/secrets.env from the tracked template.
  #
  # Every rofi script that talks to Gemini sources this file, and until now
  # nothing created it and nothing shipped an example -- the only way to
  # learn that GEMINI_API_KEY exists was to grep the source. A new user got
  # translators with silently empty "synonyms" and "examples" sections and
  # no indication why.
  #
  # Seeded with the key left EMPTY, so behaviour does not change for anyone
  # who has not filled it in; it just becomes discoverable. Mode 600 from
  # the start, because rofi_common.sh warns about anything looser and the
  # first thing written into it will be a credential. Never overwritten:
  # this must not clobber a file that already has keys in it.
  local secrets_tmpl="$HOME/.config/secrets.env.example"
  local secrets_out="$HOME/.config/secrets.env"
  if [[ -f "$secrets_tmpl" && ! -e "$secrets_out" ]]; then
    run "install -m600 $secrets_tmpl $secrets_out"
  fi

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
  # ati-theme-apply's render_dunstrc. That is what keeps a per-machine value
  # from being written back into the repo through the link.
  local src dst
  for src in \
    "$DOTFILES_DIR/.config/brave-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/chrome-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/chromium-flags.conf.tmpl" \
    "$DOTFILES_DIR/.config/gtk-3.0/gtk.css.tmpl" \
    "$DOTFILES_DIR/.config/gtk-4.0/gtk.css.tmpl" \
    "$DOTFILES_DIR/.config/gtk-3.0/bookmarks.tmpl" \
    "$DOTFILES_DIR/.config/tide-island/userconfig.json.tmpl"
  do
    [[ -f "$src" ]] || { _WARN "missing template $src"; continue; }
    dst="$HOME/.config/${src#"$DOTFILES_DIR"/.config/}"
    dst="${dst%.tmpl}"
    run "mkdir -p $(dirname "$dst") && rm -f $dst && sed 's|@HOME@|$HOME|g' $src > $dst"
  done
}


step_ui_scale() {
  # Runs AFTER ati-scripts, which is what puts ati-ui-scale on PATH.
  #
  # Every pixel value in the qtile config was tuned on a 1366x768 14"
  # panel. Without this the bar is a sliver of unreadable text on a 4K
  # laptop -- the one axis these dotfiles cannot keep identical by copying
  # files, because the right answer depends on the glass.
  local bin
  bin="$(command -v ati-ui-scale || echo "$DOTFILES_DIR/.config/AtiScriptsV1/input/ati-ui-scale")"
  [[ -x "$bin" ]] || { _WARN "ati-ui-scale not found — run the ati-scripts module first"; return 0; }
  if [[ -z "${DISPLAY:-}" ]]; then
    # xrandr needs an X server. During a TTY install there is none yet, so
    # defer rather than write a wrong factor: .xinitrc runs it at login.
    _OK "no X session yet — ati-ui-scale will run from .xinitrc on first startx"
    return 0
  fi
  run "$bin"
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
# white on the dark desktop. qt6ct/qt5ct read the palette ati-theme-apply
# generates into ~/.config/qt6ct/colors/current.conf.
export QT_QPA_PLATFORMTHEME=qt6ct
# Cursor size + theme for X apps (Xcursor honors both env vars).
export XCURSOR_SIZE=24
export XCURSOR_THEME=breeze_cursors
# Size the UI to whatever display is actually attached, BEFORE xrdb merges
# .Xresources (ati-ui-scale writes Xft.dpi into it) and before qtile reads
# ~/.cache/qtile/ui_scale. Docking to an external monitor between sessions
# changes the answer, so this runs every login rather than once at install.
command -v ati-ui-scale >/dev/null 2>&1 && ati-ui-scale >/dev/null 2>&1
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
# ati-copyq-rofi needs copyq's background server running to have any
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
!
! This module is OPT-IN and is not part of a default ./install.sh run:
! it is right for one machine and merely surprising on every other.
! Undo with: ./wizard.sh --uninstall --only=xmodmap
clear lock
clear mod1
keycode 66 = Alt_L
add mod1 = Alt_L Alt_R
XMM_EOF
}

step_keyd() {
  # The same Caps->Alt remap as step_xmodmap, one layer lower.
  #
  # xmodmap is an X11 client: it talks to the X server, so it does
  # nothing at all under Wayland. keyd sits on evdev, BELOW the display
  # server, so one config serves the qtile/X11 session and the Hyprland
  # session both -- which matters because the alternative is maintaining
  # the remap twice and watching the two drift.
  #
  # Opt-in for exactly the reason .Xmodmap is: this laptop's Alt is dead
  # in hardware and Caps is the only working Alt. On any other machine
  # this silently takes the Caps key away.
  #
  # Undo with: ./wizard.sh --uninstall --only=keyd
  #
  # keyd writes through /dev/uinput, and dies on startup with
  # "open uinput: No such device" if that module is not loaded. The
  # device node can exist while the module does not, so the failure
  # does not look like a missing module -- it looks like broken keyd.
  # Declaring it in modules-load.d is what makes the remap survive a
  # reboot rather than needing a modprobe every time.
  run "echo uinput | sudo tee /etc/modules-load.d/uinput.conf > /dev/null"
  run "sudo modprobe uinput || true"
  run "sudo mkdir -p /etc/keyd"
  run "sudo tee /etc/keyd/default.conf > /dev/null << 'EOF'
[ids]
*

[main]
capslock = leftalt
EOF"
  run "sudo systemctl enable --now keyd"
  # Verify rather than assume: keyd silently does nothing if the service
  # failed to bind the device, and the failure mode is a third of the
  # keyboard going dead at the next login. Immediately after a kernel
  # upgrade this WILL report inactive -- the running kernel's modules are
  # already gone from /lib/modules, so uinput cannot load until a reboot.
  # That case is expected and resolves itself; any other is not.
  run "systemctl is-active --quiet keyd && echo '  keyd active' || echo '  keyd NOT active -- expected if the kernel was just upgraded (reboot); otherwise: sudo journalctl -u keyd -n20'"
}

                    # VIPS_WARNING now ships as a tracked fish conf.d snippet
                    # (.config/fish/conf.d/vips.fish) instead of being appended
                    # to ~/.profile: that line was fish syntax in a POSIX file,
                    # so fish never read it and sh read `set -x` as xtrace.
                    # Strip the old broken line if a previous run added it.
step_image_envs()   { run "sed -i '/VIPS_WARNING/d' $HOME/.profile 2>/dev/null || true"
                      # fish_variables (versioned) pins TMPDIR to ~/tmp for psub/mktemp
                      # (starship init, pyenv init) -- must exist or fish startup breaks.
                      run "mkdir -p $HOME/tmp"; }

# tmux plugin manager + the plugins .tmux.conf declares.
#
# This was the one step the README told you to run by hand. Without it
# vim-tmux-navigator's pane navigation and resurrect/continuum's
# save-on-interval and restore-on-start all silently do nothing -- tmux
# starts fine and simply ignores every `set -g @plugin` line, which is
# the kind of failure nobody notices until they need the feature.
step_tmux_tpm() {
  local tpm="$HOME/.tmux/plugins/tpm"

  (( DRY_RUN )) && { _DIM "  [dry] clone TPM + install_plugins"; return 0; }

  if [[ ! -d "$tpm/.git" ]]; then
    run "mkdir -p $HOME/.tmux/plugins"
    retry_net 3 5 git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm" || {
      _ERR "TPM clone failed after 3 retries"; return 1; }
  fi

  # install_plugins is idempotent: already-cloned plugins are skipped.
  # It does not need a running server, but it does need $HOME set, which
  # is why it runs here rather than from a tmux hook.
  if [[ -x "$tpm/bin/install_plugins" ]]; then
    run "$tpm/bin/install_plugins" || _WARN "TPM install_plugins reported a problem"
  fi
}


# Your own fork, not upstream. ati-theme-apply's `wal` mode derives an entire
# palette from the current wallpaper, so the wallpaper set is not
# decoration -- it is an input to how the desktop looks. Pointing at
# someone else's repo means they can add, remove or re-encode an image and
# change your colours; a fork you control cannot move under you.
WALLPAPERS_REPO="${WALLPAPERS_REPO:-https://github.com/Mohamedattiadev/wallpapers}"
step_wallpapers()   { [[ -d $HOME/Pictures/Wallpapers/.git ]] && { _OK "wallpapers present"; return; }
                      run "rm -rf $HOME/Pictures/Wallpapers && mkdir -p $HOME/Pictures && git clone $WALLPAPERS_REPO $HOME/Pictures/Wallpapers"; }

step_themes() {
  run "sudo pacman -S --needed --noconfirm python-pywal python-pillow papirus-icon-theme jq"
  # Seed eww colors.scss from .tmpl so first ati-theme-apply resolves.
  local eww_tmpl="$HOME/.config/eww/colors.scss.tmpl"
  local eww_out="$HOME/.config/eww/colors.scss"
  [[ -f "$eww_tmpl" && ! -f "$eww_out" ]] && run "cp $eww_tmpl $eww_out"
  # Seed qutebrowser homepage.html from .tmpl (gitignored — regenerated
  # per palette by ati-theme-apply, needs a stable skeleton first). The greeting
  # says "Welcome, <you>": the page is served over file://, so JS can't read
  # the login name — the only place it can be filled in is here, at seed time.
  local qb_tmpl="$HOME/.config/qutebrowser/html/homepage.html.tmpl"
  local qb_out="$HOME/.config/qutebrowser/html/homepage.html"
  local qb_user="${USER:-$(id -un)}"
  [[ -f "$qb_tmpl" && ! -f "$qb_out" ]] && \
    run "sed 's/@@USER@@/${qb_user^}/' $qb_tmpl > $qb_out"
  # Seed default wallpaper if none set.
  if [[ ! -f "$HOME/.cache/wall" ]]; then
    local first
    first=$(find "$HOME/Pictures/Wallpapers" -maxdepth 2 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -1) || true
    [[ -n "$first" ]] && run "mkdir -p $HOME/.cache && ln -sfn $first $HOME/.cache/wall"
  fi
  run "ati-wal-precompile"
  run "ati-theme-apply doomone"
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


uninstall_xinit()            { run "rm -f $HOME/.xinitrc"; }

uninstall_xmodmap()          { run "rm -f $HOME/.Xmodmap"; }

uninstall_keyd()             { run "sudo systemctl disable --now keyd"
                               run "sudo rm -f /etc/keyd/default.conf"; }

# .Xresources is NOT deleted: step_xresources appends a marker-guarded
# block to a file the user may own. Strip only our block.
uninstall_xresources()       { run "sed -i '/^! BEGIN-WIZARD-XCURSOR\$/,/^! END-WIZARD-XCURSOR\$/d' $HOME/.Xresources 2>/dev/null || true"; }

uninstall_image_envs()       { run "sed -i '/VIPS_WARNING/d' $HOME/.profile 2>/dev/null || true"; }

uninstall_pacman_guard()     { run "sudo rm -f /etc/pacman.d/hooks/00-preflight.hook"; }

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

uninstall_themes() {
  # Remove generated caches only, keep any user-selected wallpaper.
  run "rm -rf $HOME/.cache/qtile/palettes $HOME/.cache/wal"
  run "rm -f $HOME/.config/eww/colors.scss"
}

uninstall_paths()             { :; }  # removing them would leave the browser theme and GTK overlay with no config at all

uninstall_ui_scale() {
  run "rm -f $HOME/.cache/qtile/ui_scale $HOME/.cache/qtile/ui_scale.pinned"
  run "sed -i '/^! BEGIN-UI-SCALE\$/,/^! END-UI-SCALE\$/d' $HOME/.Xresources 2>/dev/null || true"
}

uninstall_githooks() { run "rm -f $DOTFILES_DIR/.git/hooks/pre-commit"; }

uninstall_arch_config()       { :; }

# Plugins are cheap to refetch, but removing them would break a running
# tmux config for no benefit. Left in place, like the model downloads.
uninstall_tmux_tpm()          { :; }

uninstall_wallpapers()        { :; }  # user's picture collection
