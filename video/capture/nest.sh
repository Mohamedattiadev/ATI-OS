#!/usr/bin/env bash
# nest.sh — bring up a throwaway desktop on a nested X server, so clips can
# be recorded without anything ever appearing on the owner's real screen.
#
#   ./nest.sh up      start Xephyr :9 + private bus + picom + a second qtile
#   ./nest.sh down    kill everything this started, and nothing else
#   ./nest.sh status  what is running
#   ./nest.sh exec …  run a command inside the nest
#
# THE RULE THIS SCRIPT EXISTS TO ENFORCE
#
# Nothing may ever reach the owner's display, bus, or files. Every rule below
# was learned by breaking it — see "Containment, learned the hard way" in
# notes/gif_list.md. In short:
#
#   * D-Bus. dbus-run-session's address is NOT on its own process; reading
#     /proc/<pid>/environ gives you the PARENT's bus, which is the owner's,
#     and a notification then pops on their real screen. We start our own
#     daemon and read the address it prints.
#   * Killing. Never `pkill -f <name>` -- it matches the owner's daemons.
#     Everything started here carries ATIOS_NEST=1 in its environment and
#     teardown matches on THAT, read out of /proc/<pid>/environ.
#   * Theming. Never run theme-apply against the nest. It writes through
#     paths that are symlinks to the owner's real config and would retint and
#     restart their live session. The three files that matter are written
#     directly, below.
#   * pipewire cannot be contained at all -- it lives in the shared
#     XDG_RUNTIME_DIR. Any clip that changes volume or mutes hits the real
#     sink. That is a per-clip problem; this script cannot solve it.
set -Eeuo pipefail

NEST_DISPLAY="${NEST_DISPLAY:-:9}"
NEST_SIZE="${NEST_SIZE:-1366x768}"
ROOT="${NEST_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/atios-nest}"
HOME_DIR="$ROOT/home"
RUN_DIR="$ROOT/run"
REAL_CONFIG="$HOME/.config"

r=$'\033[31m'; g=$'\033[32m'; y=$'\033[33m'; d=$'\033[90m'; o=$'\033[0m'
say()  { printf '%s::%s %s\n' "$d" "$o" "$*"; }
ok()   { printf '  %s✓%s %s\n' "$g" "$o" "$*"; }
warn() { printf '  %s!%s %s\n' "$y" "$o" "$*"; }
die()  { printf '%s✗%s %s\n' "$r" "$o" "$*" >&2; exit 1; }

# ── finding what we started ──────────────────────────────────────────
# The ONLY safe way to identify our processes. A name match would catch the
# owner's qtile, picom and dunst; an environment match cannot.
nest_pids() {
  local p
  for p in /proc/[0-9]*; do
    # The redirect itself fails on other users' processes, and that error
    # comes from the shell rather than from tr -- so the whole compound is
    # silenced, not just the command. [[ -r ]] is not enough: access(2) says
    # yes for root-owned entries that then refuse the open.
    if { tr '\0' '\n' <"$p/environ"; } 2>/dev/null | grep -qx 'ATIOS_NEST=1'; then
      printf '%s\n' "${p#/proc/}"
    fi
  done
}

is_up() { [[ -e "/tmp/.X11-unix/X${NEST_DISPLAY#:}" ]]; }

# ── copying config without a path back to the owner's files ──────────
#
# ~/.config/* is stow-symlinked into ~/.dotfiles. A plain `cp -r` of a
# symlinked directory copies THE SYMLINK, and every write into the "copy"
# then lands on the owner's real, git-tracked config.
#
# This was not hypothetical: the first run of this script tried to stub
# autostart.sh and the write went at `../.dotfiles/.config/qtile`. It failed
# only because stow's link is RELATIVE and did not resolve from the nest. An
# absolute link would have silently overwritten the owner's real
# autostart.sh.
#
# So: --copy-links, which turns every symlink into the file it points at and
# breaks the path back to ~/.dotfiles, followed by assert_contained to prove
# it worked. Exclusions are not housekeeping:
#
#   brave-profiles  256 MB of the owner's real browser profile, sitting
#                   inside ~/.config/qtile. Cookies, history, logins. It
#                   must not be in a directory we are about to record.
#   __pycache__     stale .pyc compiled against the real paths.
#
# rsync exits 23/24 when a dangling symlink cannot be followed (the Brave
# profiles are full of SingletonLock links to dead sockets). Those are
# skipped, correctly, so those two codes are not failures here.
copy_config() {
  local src="$1" dst="$2" rc=0
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  rsync -a --copy-links --quiet \
        --exclude 'brave-profiles/' --exclude '__pycache__/' \
        --exclude '*.pyc' --exclude '.git/' \
        "$src/" "$dst/" || rc=$?
  (( rc == 0 || rc == 23 || rc == 24 )) || die "rsync failed ($rc) copying $src"
  assert_contained "$dst"
}

# Refuse to continue if anything under $1 is a symlink that escapes the nest.
# A single one is a writable path straight into the owner's home.
assert_contained() {
  local dir="$1" link target escapees=0
  while IFS= read -r -d '' link; do
    target="$(readlink -f "$link" 2>/dev/null || true)"
    if [[ -z "$target" || "$target" != "$ROOT"/* ]]; then
      printf '%s✗%s escaping symlink: %s -> %s\n' "$r" "$o" "$link" "${target:-<broken>}" >&2
      escapees=1
    fi
  done < <(find "$dir" -type l -print0 2>/dev/null)
  (( escapees )) && die "refusing to run: the nest home has links into the owner's files"
  return 0
}

# Write a file, but only if the path is a real file inside the nest. The
# last line of defence before anything in build_home touches disk.
safe_write() {
  local path="$1"
  [[ "$(readlink -f "$(dirname "$path")")" == "$ROOT"/* ]] \
    || die "refusing to write outside the nest: $path"
  [[ -L "$path" ]] && die "refusing to write through a symlink: $path"
  cat >"$path"
}

# ── the scrubbed home ────────────────────────────────────────────────
build_home() {
  rm -rf "$HOME_DIR"
  mkdir -p "$HOME_DIR"/{.config,.cache,.local/share,Pictures,Documents,Downloads}

  # qtile: a COPY, never the real directory. The autostart hook is what
  # would otherwise launch a second picom, dunst, copyq, eww and tray applet
  # against the owner's live session, so it is replaced with a stub rather
  # than deleted -- the hook calls it unconditionally and a missing file
  # would just log an error on every start.
  copy_config "$REAL_CONFIG/qtile" "$HOME_DIR/.config/qtile"
  safe_write "$HOME_DIR/.config/qtile/autostart.sh" <<'STUB'
#!/usr/bin/env bash
# Deliberately empty. The real autostart.sh starts session-wide daemons that
# would attach to the owner's session. nest.sh starts what the nest needs.
exit 0
STUB
  chmod +x "$HOME_DIR/.config/qtile/autostart.sh"

  # Read-only config the nest renders with. Copied, not symlinked, so
  # anything that writes cannot reach the owner's files.
  local c
  for c in rofi alacritty kitty gtk-3.0 gtk-4.0 fontconfig fish; do
    copy_config "$REAL_CONFIG/$c" "$HOME_DIR/.config/$c"
  done

  # A scrubbed home has no shell history and no shell rc, and zsh treats
  # that as a brand-new account: every terminal in the nest opened on
  # "This is the Z Shell configuration function for new users,
  # zsh-newuser-install..." and the first layouts take recorded four panes
  # of it. An empty .zshrc is the documented way to tell zsh the account has
  # been set up. Kept even though the nest runs fish, because anything that
  # spawns a login shell can still land in zsh.
  : >"$HOME_DIR/.zshrc"

  # fish is what the desktop actually ships (see the shell docs), so clips
  # show fish. Its greeting is suppressed: a recording should open on a
  # prompt, not on a banner, and rule 7 in notes/gif_list.md says the first
  # frame must already be the subject.
  mkdir -p "$HOME_DIR/.config/fish/conf.d"
  safe_write "$HOME_DIR/.config/fish/conf.d/zz-nest.fish" <<'FISHRC'
# Recording nest only. Not part of the shipped config.
set -g fish_greeting ""
FISHRC

  # Stubs that shadow real commands for recordings only, via a PATH entry
  # ahead of everything else. Overriding here rather than editing the copied
  # config.fish, because these run INLINE partway through it -- there is no
  # "unset" to append afterwards.
  mkdir -p "$HOME_DIR/.local/bin"

  # config.fish runs `colorscript random` on every interactive shell. It is
  # a real part of this desktop, but it paints a different ANSI artwork each
  # time, so no two takes of the same clip match and it fills the pane that
  # the clip is supposed to be showing. Reproducible takes win.
  safe_write "$HOME_DIR/.local/bin/colorscript" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$HOME_DIR/.local/bin/colorscript"

  # Something to look at. Throwaway names only -- these show up on camera.
  mkdir -p "$HOME_DIR"/Projects/{api,web}
  printf '{\n  "name": "demo",\n  "port": 8080\n}\n' >"$HOME_DIR/Projects/config.json"
  printf '# demo\n\nA throwaway project.\n' >"$HOME_DIR/Projects/README.md"
  printf 'alpha\nbeta\ngamma\n' >"$HOME_DIR/Documents/notes.txt"
}

# ── theming the nest, without theme-apply ────────────────────────────
theme_nest() {
  local mode="${NEST_THEME:-doomone}"
  mkdir -p "$HOME_DIR/.cache/qtile"
  printf '%s\n' "$mode" | safe_write "$HOME_DIR/.cache/qtile/theme_mode"

  # qtile popups and the bar read this; so does anything else that asks the
  # desktop what colour it is. Generated by hand because theme-apply is off
  # limits here (it restarts qtile and rewrites global state).
  if [[ -f "$HOME/.cache/qtile/current_palette.json" ]]; then
    cp "$HOME/.cache/qtile/current_palette.json" "$HOME_DIR/.cache/qtile/current_palette.json"
  fi
  # rofi and GTK popups do not follow theme_mode -- they need their own file
  # or they clash with the bar in frame.
  if [[ -f "$REAL_CONFIG/rofi/themes/current-palette.rasi" ]]; then
    mkdir -p "$HOME_DIR/.config/rofi/themes"
    cp "$REAL_CONFIG/rofi/themes/current-palette.rasi" \
       "$HOME_DIR/.config/rofi/themes/current-palette.rasi"
  fi
  if [[ -f "$REAL_CONFIG/alacritty/themes/current.toml" ]]; then
    mkdir -p "$HOME_DIR/.config/alacritty/themes"
    cp "$REAL_CONFIG/alacritty/themes/current.toml" \
       "$HOME_DIR/.config/alacritty/themes/current.toml"
  fi
}

up() {
  is_up && die "$NEST_DISPLAY is already up — ./nest.sh down first"
  command -v Xephyr  >/dev/null || die "Xephyr not installed (xorg-server-xephyr)"
  command -v qtile   >/dev/null || die "qtile not installed"
  command -v xdotool >/dev/null || die "xdotool not installed"

  mkdir -p "$RUN_DIR"
  say "building scrubbed home at $HOME_DIR"
  build_home
  theme_nest
  # Whole-tree re-check after everything is in place, not just per-copy.
  assert_contained "$HOME_DIR"
  ok "home, qtile copy (autostart stubbed), theme files — no links escape the nest"

  # ── Xephyr ──
  say "starting Xephyr on $NEST_DISPLAY at $NEST_SIZE"
  env ATIOS_NEST=1 Xephyr "$NEST_DISPLAY" -screen "$NEST_SIZE" -ac -br -noreset \
      >"$RUN_DIR/xephyr.log" 2>&1 &
  local i
  for i in $(seq 1 60); do is_up && break; sleep 0.25; done
  is_up || die "Xephyr never came up — see $RUN_DIR/xephyr.log"

  # Get its window off the owner's screen. x11grab reads the :9 root
  # framebuffer, which Xephyr maintains whether or not its own window on :0
  # is visible, so unmapping costs nothing and guarantees nothing is seen.
  local wid
  wid="$(xdotool search --class Xephyr 2>/dev/null | tail -1 || true)"
  if [[ -n "$wid" ]]; then
    xdotool windowunmap "$wid" 2>/dev/null && ok "Xephyr window unmapped (nothing on the real screen)" \
      || warn "could not unmap the Xephyr window — it is VISIBLE; do not record"
  else
    warn "could not find the Xephyr window to hide it"
  fi

  # ── private session bus ──
  # Started explicitly rather than via dbus-run-session: that wrapper does
  # not put its address on its own process, so /proc reads give the owner's.
  say "starting a private session bus"
  local bus
  bus="$(env ATIOS_NEST=1 dbus-daemon --session --fork --print-address)"
  [[ -n "$bus" ]] || die "no bus address"
  printf '%s\n' "$bus" >"$RUN_DIR/bus"
  ok "bus $bus"

  # ── compositor ──
  # The top bar is background="#11111b00" -- fully transparent. With no
  # compositor on :9 it does not render as "transparent", it renders as
  # garbage, and every bar clip is worthless. glx does not work under
  # Xephyr; xrender does.
  if command -v picom >/dev/null; then
    env ATIOS_NEST=1 DISPLAY="$NEST_DISPLAY" DBUS_SESSION_BUS_ADDRESS="$bus" \
        picom --backend xrender --config /dev/null \
        >"$RUN_DIR/picom.log" 2>&1 &
    sleep 1
    ok "picom (xrender) — the transparent top bar will composite"
  else
    warn "picom missing — the transparent top bar will NOT render correctly"
  fi

  # ── the second qtile ──
  say "starting qtile from the copy"
  env ATIOS_NEST=1 \
      DISPLAY="$NEST_DISPLAY" \
      HOME="$HOME_DIR" \
      XDG_CONFIG_HOME="$HOME_DIR/.config" \
      XDG_CACHE_HOME="$HOME_DIR/.cache" \
      XDG_DATA_HOME="$HOME_DIR/.local/share" \
      DBUS_SESSION_BUS_ADDRESS="$bus" \
      qtile start -c "$HOME_DIR/.config/qtile/config.py" \
      >"$RUN_DIR/qtile.log" 2>&1 &

  for i in $(seq 1 80); do
    DISPLAY="$NEST_DISPLAY" xdotool search --class qtile >/dev/null 2>&1 && break
    sleep 0.25
  done
  sleep 2
  if grep -qiE '^(Traceback|.*Error)' "$RUN_DIR/qtile.log" 2>/dev/null; then
    warn "qtile logged errors — check $RUN_DIR/qtile.log"
  fi
  ok "qtile up on $NEST_DISPLAY"

  printf '\n%sready.%s  seed windows:  ./nest.sh exec alacritty &\n' "$g" "$o"
  printf '        record:        ./shoot.sh <clip>\n'
  printf '        tear down:     ./nest.sh down\n'
}

nest_env() {
  local bus=""
  [[ -f "$RUN_DIR/bus" ]] && bus="$(cat "$RUN_DIR/bus")"
  # SHELL is set explicitly: terminals inherit the login shell from the
  # passwd entry otherwise, which is how the nest ended up recording zsh's
  # new-user wizard instead of the shell this desktop ships.
  printf 'ATIOS_NEST=1\nDISPLAY=%s\nHOME=%s\nSHELL=%s\nPATH=%s\nXDG_CONFIG_HOME=%s/.config\nXDG_CACHE_HOME=%s/.cache\nXDG_DATA_HOME=%s/.local/share\nDBUS_SESSION_BUS_ADDRESS=%s\n' \
    "$NEST_DISPLAY" "$HOME_DIR" "${NEST_SHELL:-$(command -v fish || command -v bash)}" \
    "$HOME_DIR/.local/bin:$PATH" \
    "$HOME_DIR" "$HOME_DIR" "$HOME_DIR" "$bus"
}

do_exec() {
  is_up || die "nest is not up"
  cd "$HOME_DIR" || die "no nest home"
  # shellcheck disable=SC2046
  exec env $(nest_env | tr '\n' ' ') "$@"
}

down() {
  local pids
  mapfile -t pids < <(nest_pids)
  if (( ${#pids[@]} == 0 )); then
    say "nothing tagged ATIOS_NEST=1 is running"
  else
    say "stopping ${#pids[@]} nest processes (matched on ATIOS_NEST=1, never by name)"
    kill "${pids[@]}" 2>/dev/null || true
    sleep 2
    mapfile -t pids < <(nest_pids)
    (( ${#pids[@]} )) && { kill -9 "${pids[@]}" 2>/dev/null || true; sleep 1; }
  fi
  rm -f "/tmp/.X11-unix/X${NEST_DISPLAY#:}" 2>/dev/null || true
  ok "down"
}

# ── seeding ──────────────────────────────────────────────────────────
# The GroupBox uses hide_unused=True, so a group with no windows is not
# drawn at all -- on an empty nest the widget is invisible and groups.gif
# records nothing. Layout clips need at least two windows per group too, or
# monadtall/max/treetab all look identical.
#
# kitty is the configured terminal (myTerm) but it talks to a session-wide
# instance over a socket; alacritty (my2ndTerm) is the safe one to spawn
# repeatedly in a nest.
seed() {
  is_up || die "nest is not up"
  local term="${NEST_TERM:-alacritty}"
  command -v "$term" >/dev/null || die "$term not installed"
  local SEED_CMD="${NEST_SEED_CMD:-ls -1 Projects; and cat Projects/config.json}"
  local grp n
  for grp in 1 2 4; do
    DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "super+$grp"
    sleep 0.5
    for n in 1 2; do
      # `cd` first, and it matters. A terminal inherits the working
      # directory of whatever spawned it, so running this from the repo
      # gave every pane a fish prompt reading
      # ".dotfiles/video/capture on ⎇ test [!?]" -- the owner's real path,
      # branch and dirty state, on camera, in a clip meant to show layouts.
      # setsid + all three fds closed. Without it the spawned terminal holds
      # the write end of whatever pipe seed's own stdout is attached to, so
      # `./nest.sh seed | tail` never returns even though the seeding
      # finished seconds earlier.
      # Each pane gets a little throwaway content. Bare prompts make every
      # tiling layout look like empty rectangles, and a viewer cannot tell a
      # pane from the wallpaper. The commands only ever touch the nest's own
      # fake Projects/ tree.
      # shellcheck disable=SC2046
      ( cd "$HOME_DIR" && setsid env $(nest_env | tr '\n' ' ') "$term" \
          -e fish -C "$SEED_CMD" </dev/null >/dev/null 2>&1 & )
      sleep 1.2
    done
  done
  DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "super+1"
  sleep 1
  ok "seeded groups 1, 2 and 4 with two $term windows each (8 stays empty)"
}

status() {
  is_up && ok "$NEST_DISPLAY is up" || warn "$NEST_DISPLAY is down"
  local pids; mapfile -t pids < <(nest_pids)
  printf '  %s nest-tagged processes\n' "${#pids[@]}"
  local p
  for p in "${pids[@]}"; do
    printf '    %-7s %s\n' "$p" "$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | cut -c1-70)"
  done
}

case "${1:-}" in
  up)     up ;;
  seed)   seed ;;
  down)   down ;;
  status) status ;;
  env)    nest_env ;;
  exec)   shift; do_exec "$@" ;;
  *) printf 'usage: %s {up|seed|down|status|env|exec <cmd…>}\n' "${0##*/}" >&2; exit 2 ;;
esac
