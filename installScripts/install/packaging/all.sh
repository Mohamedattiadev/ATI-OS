# install/packaging/all.sh — packaging phase: step_*/uninstall_* functions for the
# modules classified into this phase, extracted verbatim from wizard.sh
# (no behavior change) as part of splitting the installer into Omarchy-
# style phase directories. wizard.sh sources this file; module dispatch
# (_reg/_run_module/UMOD_CMD) is unchanged and still lives in wizard.sh /
# install/lib/registry.sh.

step_bootstrap() {
  if (( DRY_RUN )); then _DIM "  [dry] sudo pacman -Syu … (retry x3)"; return; fi
  retry_net 3 5 sudo pacman -Syu --needed --noconfirm base-devel git stow xorg-server xorg-xinit curl wget unzip
}

step_yay()          { command -v yay >/dev/null && { _OK "yay present"; return; }
                      run "rm -rf /tmp/yay-bin && cd /tmp && git clone https://aur.archlinux.org/yay-bin.git yay-bin && cd yay-bin && makepkg -si --noconfirm"; }

step_dcli()         { command -v dcli >/dev/null && { _OK "dcli present"; return; }
                      run "yay -S --needed --noconfirm dcli-arch-git"; }

# informant hooks pacman and REFUSES every transaction until the Arch news
# is marked read. That is the whole point of it on a running machine --
# those are the posts that say "manual intervention required" -- but it is
# installed BY this sync, and a fresh machine always has unread news. So
# from the moment it lands, every later pacman call in the install dies:
#
#   :: informant: Run `informant read` before re-running your pacman command
#   error: failed to commit transaction (failed to run transaction hooks)
#
# In a clean VM that took out boot-splash (plymouth never installed) and
# anything else that needed a package later in the run -- reported, of
# course, as unrelated broken modules.
#
# Marking them read here is honest rather than a bypass: the installer has
# just fetched a current package set, so the news items are about upgrades
# it did not perform. It also leaves informant fully armed for the next
# real -Syu, which is when its warning actually matters.
_clear_informant_news() {
  (( DRY_RUN )) && return 0
  command -v informant >/dev/null 2>&1 || return 0
  if ! informant check >/dev/null 2>&1; then
    _DIM "  marking Arch news read so informant stops blocking pacman"
    # --all where supported; the bare form otherwise. timeout because an
    # older informant pages interactively and there is no tty here.
    # sudo, and that is the whole point: informant's pacman hook runs as
    # ROOT and checks root's read-state. Marking the news read as your own
    # user updates a cache the hook never looks at, so pacman stays
    # blocked -- which is exactly what happened, twice, and took out
    # boot-splash (no plymouth) and the desktop check (no Xvfb).
    sudo timeout 60 informant read --all >/dev/null 2>&1 \
      || yes | sudo timeout 60 informant read >/dev/null 2>&1 \
      || sudo timeout 60 informant read >/dev/null 2>&1 \
      || _WARN "could not clear the informant news queue — later pacman calls may fail"
    # Prove it worked rather than assuming: `informant check` is what the
    # hook itself runs, so if this still fails, so will the next pacman.
    if sudo informant check >/dev/null 2>&1; then
      _DIM "  informant is satisfied — pacman is unblocked"
    else
      _WARN "informant STILL reports unread news; later package installs will fail"
    fi
  fi
  return 0
}


# Reclaim the AUR build trees once the packages are installed.
#
# yay keeps every package's full build directory under ~/.cache/yay, source
# tree included, and never prunes them. For a set this size that is not a
# rounding error: espanso alone is a Rust project whose target/ runs to
# several GB, and the sum of them exhausted a 40G disk mid-install -- the
# packages went on fine, then `wallpapers`, `whisper` and `themes` all died
# on "No space left on device", and the wizard aborted at 40 ok / 6 failed.
#
# Measured, not guessed: a clean VM install needed more than 40G of
# transient space to produce a system that occupies a fraction of it.
# Anyone installing this on a modest partition would hit the same wall,
# with the failure landing on an unrelated module several steps later.
#
# Best-effort by design. Nothing here is load-bearing -- if the cleanup
# fails the install is still complete, just fatter -- so it never returns
# non-zero into the module's exit status.
# Packages whose build tree a LATER module still needs. Deleting these is
# not a cleanup, it is a broken install:
#
#   whisper.cpp-git -- step_whisper_fast (module 33) rebuilds whisper-cli
#     and whisper-stream from this exact source tree, because the AUR
#     PKGBUILD ships an unoptimised binary (~13x slower, measured) and
#     never builds whisper-stream at all. It checks for the directory and
#     hard-fails when it is missing.
#
# The first version of this cleanup did not have that list and removed the
# tree at module 8, so whisper-fast failed 25 modules later with an empty
# error log -- because it fails via _ERR and `return 1`, which never
# reaches the module's stderr. Exactly the sort of action-at-a-distance
# this whole cleanup was written to stop causing.
RECLAIM_KEEP=(whisper.cpp-git)

_reclaim_build_cache() {
  (( DRY_RUN )) && { _DIM "  [dry] clean AUR build caches"; return 0; }
  local before after d keep
  before=$(du -sm "$HOME/.cache/yay" 2>/dev/null | cut -f1 || echo 0)
  [[ "${before:-0}" -gt 0 ]] || return 0

  # Not `yay -Sc`: that prunes by its own rules and would take the kept
  # trees with it. Walk the directories so the keep-list is honoured.
  for d in "$HOME"/.cache/yay/*/; do
    [[ -d "$d" ]] || continue
    keep=0
    for k in "${RECLAIM_KEEP[@]}"; do
      [[ "$(basename "$d")" == "$k" ]] && keep=1 && break
    done
    (( keep )) && continue
    rm -rf "${d}src" "${d}pkg" 2>/dev/null || true
  done

  after=$(du -sm "$HOME/.cache/yay" 2>/dev/null | cut -f1 || echo 0)
  # Report either way. Logging ONLY on a reduction made this function
  # silent on every run, and that silence is why the disk exhaustion was
  # credited to this cleanup rather than to the disk being too small --
  # yay prunes its own build trees on a fresh machine, so there was
  # nothing here to reclaim and no output to say so. A cleanup that
  # cannot be observed cannot be reasoned about.
  if (( before > after )); then
    _DIM "  reclaimed $(( before - after ))MB of AUR build cache (kept: ${RECLAIM_KEEP[*]})"
  else
    _DIM "  AUR build cache already minimal (${after}MB) — nothing to reclaim"
  fi
  return 0
}


step_dcli_sync() {
  # Settle the `jack` provider BEFORE anything else resolves it.
  #
  # ffmpeg, mpv and timidity++ all depend on the virtual package `jack`,
  # and two packages provide it: jack2 and pipewire-jack. media.yaml
  # declares pipewire-jack, but on a CLEAN machine the resolver meets the
  # `jack` dependency first, picks jack2, and then dies:
  #
  #   :: pipewire-jack-1:1.6.8-1 and jack2-1.9.22-2 are in conflict
  #   error: unresolvable package conflicts detected
  #
  # That aborts the whole transaction, so NO packages install -- and every
  # module after this one fails for want of them. A VM install came out as
  # 41 ok / 5 failed with a desktop that fell back to stock qtile, all from
  # this one line. It is invisible on a machine that already has
  # pipewire-jack, which is why it survived this long.
  #
  # Naming pipewire-jack explicitly removes the choice: pacman prefers an
  # already-installed provider, so `jack` is satisfied before the ambiguous
  # dependency is ever reached. --needed makes it a no-op on a machine that
  # already has it.
  if (( ! DRY_RUN )) && command -v pacman >/dev/null; then
    if ! pacman -Qq pipewire-jack >/dev/null 2>&1; then
      _DIM "  pre-seeding the jack provider (pipewire-jack) so dcli sync cannot pick jack2"
      sudo pacman -S --needed --noconfirm pipewire-jack >/dev/null 2>&1 \
        || _WARN "could not pre-install pipewire-jack — dcli sync may hit the jack2 conflict"
    fi

    # rustup, and a DEFAULT TOOLCHAIN, before anything tries to build with
    # cargo.
    #
    # step_cargo already runs `rustup default stable`, and its comment
    # already names paru and didyoumean as the packages that fail without
    # it. The problem is purely ordering: cargo is module 12 and this is
    # module 8, so dcli sync reaches those AUR builds four modules before
    # the toolchain is selected, and both die with
    #
    #   error: rustup could not choose a version of cargo to run, because
    #   one wasn't specified explicitly, and no default is configured
    #
    # rustup itself only arrives WITH this sync (dev.yaml), so the fix
    # cannot be "move the cargo module earlier" -- it has to be seeded
    # here, the same way the jack provider is.
    if ! command -v rustup >/dev/null 2>&1; then
      _DIM "  pre-seeding rustup so cargo-built AUR packages can compile"
      sudo pacman -S --needed --noconfirm rustup >/dev/null 2>&1 || true
    fi
    if command -v rustup >/dev/null 2>&1 && ! rustup default >/dev/null 2>&1; then
      _DIM "  selecting the stable rust toolchain (paru/didyoumean need it)"
      rustup default stable >/dev/null 2>&1 \
        || _WARN "rustup default stable failed — cargo-built AUR packages may not build"
    fi
  fi
  run "cd $DOTFILES_DIR && dcli sync --force && { command -v mandb >/dev/null && sudo mandb || true; } && fc-cache -fv"
  (( DRY_RUN )) && return
  # dcli can report the sync step as done even when an individual AUR
  # package's post-build install silently failed (e.g. a sudo hiccup
  # mid-build, long before the sudo-keepalive fix existed). Verify
  # with a dry-run and self-heal with bounded retries before moving on
  # — cheap insurance, and turns a silent gap into either a real fix
  # or a visible failure instead of a false "✔ ok".
  local pending attempt=0
  while (( attempt < 2 )); do
    pending=$(cd "$DOTFILES_DIR" && dcli sync --dry-run 2>/dev/null | grep -oP 'Packages to install: \K[0-9]+' | head -1)
    if [[ -z "$pending" || "$pending" == "0" ]]; then
      _clear_informant_news
      _reclaim_build_cache
      return 0
    fi
    attempt=$((attempt+1))
    echo "dcli sync left $pending package(s) uninstalled — retry $attempt/2"
    ( cd "$DOTFILES_DIR" && dcli sync --force )
  done
  pending=$(cd "$DOTFILES_DIR" && dcli sync --dry-run 2>/dev/null | grep -oP 'Packages to install: \K[0-9]+' | head -1)
  if [[ -n "$pending" && "$pending" != "0" ]]; then
    echo "dcli sync still has $pending package(s) uninstalled after retries — run 'dcli sync --force' manually later"
    return 1
  fi
  _clear_informant_news
  _reclaim_build_cache
}

step_picom_pin() {
  # Build the animation-capable picom fork from a PINNED commit.
  #
  # The AUR package (picom-ftlabs-git) sources `#branch=next`, so it builds
  # whatever the tip is on the day you install. picom is what renders the
  # animations, rounded corners, shadows and blur this desktop is built
  # around, so letting it float means two machines from the same repo can
  # look and move differently with nothing in the config to explain it.
  local dir="$DOTFILES_DIR/.config/arch-config/pkgbuilds/picom-ftlabs-pinned"
  [[ -d "$dir" ]] || { _ERR "missing $dir"; return 1; }

  if pacman -Qq picom-ftlabs-pinned >/dev/null 2>&1; then
    _OK "picom-ftlabs-pinned present"
    return 0
  fi

  # The floating AUR build conflicts (same provides). Remove it first, or
  # makepkg fails at the install step after a full compile -- a slow way to
  # discover a problem visible up front.
  if pacman -Qq picom-ftlabs-git >/dev/null 2>&1; then
    _WARN "removing floating picom-ftlabs-git in favour of the pinned build"
    run "sudo pacman -Rdd --noconfirm picom-ftlabs-git"
  fi

  # -s installs build deps, -i installs the result, -r cleans them up.
  # Built in a temp copy: makepkg writes src/ and pkg/ next to the PKGBUILD,
  # and that directory is inside the git repo.
  local tmp
  if (( DRY_RUN )); then
    # mktemp -d creates a real directory, which a preview has no business
    # doing. Name one instead so the printed command still reads correctly.
    _DIM "  [dry] cp -r $dir/. <tmpdir>/ && cd <tmpdir> && makepkg -si --noconfirm --needed --clean"
    return 0
  fi
  tmp="$(mktemp -d)"
  run "cp -r $dir/. $tmp/ && cd $tmp && makepkg -si --noconfirm --needed --clean"
  rm -rf "$tmp"
}


step_gpu() {
  # The single most portability-critical module in the wizard.
  #
  # graphics.yaml used to hardcode the Intel driver set. Installing that on
  # an AMD or NVIDIA machine leaves the real GPU with no driver, GLX falls
  # back to llvmpipe, and picom -- which this repo configures with
  # `backend = "glx"` and `vsync = true` -- either crawls or refuses to
  # start. Either way the animations, rounded corners and shadows that the
  # desktop is built around are gone, with nothing in the logs that points
  # at a package list. So: detect, then install what this machine needs.
  local mod_dir="$DOTFILES_DIR/.config/arch-config/modules"
  local arch vendors="" ids
  arch="$(uname -m)"

  if [[ "$arch" != x86_64 ]]; then
    # ARM boards have no PCI GPU to probe and no ucode package; mesa's
    # KMS drivers in graphics.yaml are the whole story there.
    _WARN "arch is $arch, not x86_64 -- skipping PCI GPU + microcode detection"
    _WARN "graphics.yaml (vendor-neutral mesa) is installed; verify GL with vainfo"
    return 0
  fi

  command -v lspci >/dev/null || run "sudo pacman -S --needed --noconfirm pciutils"

  # Class 03xx is Display controller: VGA (0300), XGA, 3D (0302). A laptop
  # with switchable graphics reports two, and genuinely needs both sets.
  ids="$(lspci -mn 2>/dev/null | awk -F'"' '$2 ~ /^03/ {print tolower($4)}')"
  [[ -n "$ids" ]] || { _ERR "no display controller found via lspci"; return 1; }

  local id
  for id in $ids; do
    case "$id" in
      8086) vendors+=" intel"  ;;   # Intel Corporation
      1002|1022) vendors+=" amd" ;; # ATI/AMD, and AMD's own vendor id
      10de) vendors+=" nvidia" ;;   # NVIDIA
      1af4|15ad|1234|80ee)
        # virtio-gpu / VMware SVGA / QEMU stdvga / VirtualBox. mesa's
        # generic KMS driver covers these; there is no vendor package, and
        # installing one would be wrong. vm-test.sh lands here.
        _OK "virtual GPU ($id) -- vendor-neutral mesa is correct, nothing to add"
        ;;
      *) _WARN "unrecognised display controller vendor id: $id" ;;
    esac
  done

  # Deduplicate: a dual-GPU laptop lists Intel twice on some firmware.
  vendors="$(printf '%s\n' $vendors | sort -u | tr '\n' ' ')"
  [[ -n "${vendors// /}" ]] || { _OK "no vendor driver set needed"; return 0; }
  _OK "GPU vendor(s) detected:${vendors% }"

  local v mod pkgs
  for v in $vendors; do
    mod="$mod_dir/graphics-$v.yaml"
    [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
    pkgs="$(_pkgs_from_module "$mod" | tr '\n' ' ')"
    [[ -n "${pkgs// /}" ]] || { _ERR "no packages parsed from $mod"; return 1; }
    run "yay -S --needed --noconfirm $pkgs"
  done

  # NVIDIA: nvidia-open-dkms only supports Turing (2018) and newer. On an
  # older card it builds and installs happily, then fails to bind at boot
  # -- you get a black screen or a fallback to modesetting with no
  # acceleration, which reads as "the dotfiles broke my machine".
  if [[ " $vendors " == *" nvidia "* ]]; then
    if ! lspci -d 10de: -k 2>/dev/null | grep -qiE 'TU[0-9]|GA[0-9]|AD[0-9]|GB[0-9]'; then
      _WARN "NVIDIA card may predate Turing; nvidia-open-dkms supports Turing+ only"
      _WARN "if X fails to start, swap it: sudo pacman -S nvidia-dkms"
    fi
  fi

  # Per-GPU picom flags. NVIDIA's proprietary GLX is the one stack where
  # picom's use-damage optimisation smears during animations; disabling it
  # costs a little GPU time and makes the motion match Intel and AMD.
  # Written per-machine and gitignored -- never committed.
  local gpu_env="$HOME/.config/picom/gpu.env"
  if [[ " $vendors " == *" nvidia "* ]]; then
    run "mkdir -p $(dirname "$gpu_env") && printf 'PICOM_GPU_FLAGS=\"--no-use-damage\"\\n' > $gpu_env"
  else
    run "mkdir -p $(dirname "$gpu_env") && printf 'PICOM_GPU_FLAGS=\"\"\\n' > $gpu_env"
  fi

  # CPU microcode. Not graphics, but the same "detected once, hardcoded
  # forever" bug: base.yaml has intel-ucode commented out, so a fresh
  # machine of either vendor got no microcode at all. Missing microcode is
  # the cause of hangs and errata that look like random instability.
  local cpu_vendor ucode
  cpu_vendor="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo)"
  case "$cpu_vendor" in
    GenuineIntel) ucode=intel-ucode ;;
    AuthenticAMD) ucode=amd-ucode   ;;
    *) ucode="" ; _WARN "unknown CPU vendor '$cpu_vendor' -- no microcode installed" ;;
  esac
  [[ -n "$ucode" ]] && run "sudo pacman -S --needed --noconfirm $ucode"
}


step_dcli_sync_extra() {
  # modules/optional.yaml is deliberately NOT in hosts/*.yaml's
  # enabled_modules, so `dcli sync` ignores it entirely -- and dcli has no
  # per-module sync flag (see `dcli sync --help`). So read the package
  # list straight out of the yaml and hand it to the AUR helper. Keeping
  # the list in the yaml means it is still declared and reviewable in one
  # place, rather than duplicated into this script.
  local mod="$DOTFILES_DIR/.config/arch-config/modules/optional.yaml"
  [[ -f "$mod" ]] || { _ERR "missing $mod"; return 1; }
  local -a pkgs=()
  mapfile -t pkgs < <(_pkgs_from_module "$mod")
  (( ${#pkgs[@]} )) || { _ERR "no packages parsed from optional.yaml"; return 1; }
  # --needed so a re-run is a no-op instead of a reinstall.
  run "yay -S --needed --noconfirm ${pkgs[*]}"
}

step_cargo() {
  # rustup installs the stable toolchain but doesn't activate it as the
  # default -- every cargo/rustup invocation (this step, and any AUR
  # package built with cargo, e.g. paru/didyoumean) fails with "rustup
  # could not choose a version of cargo to run" until this is set once.
  command -v rustup >/dev/null && run "rustup default stable"
  # if/else, not `a && b || c`: written as a chain, a FAILED build ran the
  # `|| _WARN "cargo missing"` arm -- reporting the one thing that was not
  # true, swallowing the real compiler error, and leaving the module exit
  # status at 0 so the wizard ticked it off as ✔ ok.
  if command -v cargo >/dev/null; then
    run "cargo install pomodoro-tui"
  else
    _WARN "cargo missing, skip"
  fi
}

step_simplenote() {
  # Prepares the Simplenote mirror for the Mod+Shift+S TODOS note: package,
  # credentials file, state dir. The account login itself is NOT asked here --
  # _run_module captures a step's stdout into /tmp/wizard-<id>.log behind a
  # spinner, so a gum prompt in here would render into a file and read as a
  # hang. page_simplenote_creds() asks at the end of the run instead.
  #
  # python-simplenote is also declared in arch-config's python-lib module, so a
  # full `dcli sync` covers it; installed here too because this module is
  # legitimately runnable on its own via --only=simplenote.
  run "yay -S --needed --noconfirm python-simplenote"

  local cred_dir="$HOME/.config/simplenote"
  local cred="$cred_dir/credentials"
  run "mkdir -p $cred_dir '${XDG_STATE_HOME:-$HOME/.local/state}/simplenote-push'"
  # Never clobber a filled-in credentials file on a re-run.
  if (( DRY_RUN )); then
    _DIM "  [dry] write $cred (stub, mode 600) if absent"
  elif [[ ! -f "$cred" ]]; then
    printf '[simplenote]\nemail = \npassword = \n' >"$cred"
  fi
  # Reassert 600 unconditionally: this file holds a plaintext account password
  # (Simplenote's API has no tokens), and a stray umask on a re-run is enough
  # to leave it world-readable.
  run "chmod 600 $cred"

  # The push script rides along with the stowed AtiScriptsV1 tree, so there is
  # nothing to copy -- but say so plainly if stow has not run yet.
  [[ -x "$HOME/.config/AtiScriptsV1/ati-simplenote-push" ]] \
    || _WARN "ati-simplenote-push not on disk yet — run the stow module first"
}

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


# AnkiConnect: the HTTP bridge rofi_anki (Mod+p a) posts cards to.
#
# Without it, rofi_anki reaches a fully built card and then fails on the
# last step, because nothing is listening on :8765 -- and the addon is
# the one piece of that flow that cannot be stowed, since Anki loads
# addons from its own data dir rather than from ~/.config.
#
# 2055492159 is the AnkiWeb id. The v/p query pair is the API version and
# Anki point version the addon manager would normally send; the endpoint
# 400s without them and 404s with "your version of Anki is too old" if p
# is omitted entirely.
step_ankiconnect() {
  local id=2055492159
  local dir="$HOME/.local/share/Anki2/addons21/$id"
  local url="https://ankiweb.net/shared/download/${id}?v=2.1&p=50"

  (( DRY_RUN )) && { _DIM "  [dry] install AnkiConnect -> $dir"; return 0; }
  [[ -f "$dir/__init__.py" ]] && return 0

  command -v unzip >/dev/null 2>&1 || { _ERR "ankiconnect needs unzip"; return 1; }

  local tmp; tmp="$(mktemp -d)" || return 1
  retry_net 3 5 curl -fsSL -o "$tmp/ankiconnect.zip" "$url" || {
    _ERR "AnkiConnect download failed after 3 retries"; rm -rf "$tmp"; return 1; }

  run "mkdir -p $dir"
  unzip -o -q "$tmp/ankiconnect.zip" -d "$dir" || {
    _ERR "AnkiConnect unzip failed"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"

  # Anki only treats a directory as an installed addon when meta.json is
  # present; without it the addon loads but shows as untracked in the UI.
  cat >"$dir/meta.json" <<'EOF'
{
  "name": "AnkiConnect",
  "mod": 0,
  "min_point_version": 0,
  "max_point_version": 0,
  "branch_index": 0,
  "disabled": false
}
EOF
  # Decks and the note type are created by rofi_anki itself on first run,
  # so nothing else is needed here. Anki must be restarted to pick this up.
}


step_whisper() {
  local dir="$HOME/.local/share/whisper"
  run "mkdir -p $dir"
  # base.en: ati-voice-dictate-live (Super+Shift+V) -- fast enough to feel
  # instant on modest hardware, traded for lower accuracy.
  # small.en: ati-voice-dictate (Super+Shift+B) -- much more accurate, not
  # instant. Benchmarked repeatedly on a weak 2-core CPU: small.en runs
  # ~4x slower than real-time even with the fast build below and GPU
  # offload, so it's kept for batch (manual stop) dictation only, not
  # the live mode.
  for model in ggml-base.en.bin ggml-small.en.bin; do
    local out="$dir/$model"
    if (( DRY_RUN )); then _DIM "  [dry] curl whisper $model (retry x3)"; continue; fi
    [[ -f "$out" ]] && continue
    retry_net 3 10 curl -fL --retry 3 --continue-at - -o "$out" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model" || \
      { _ERR "whisper model $model download failed after 3 retries"; return 1; }
  done
}


step_whisper_fast() {
  # whisper.cpp-git's PKGBUILD builds with `-D CMAKE_BUILD_TYPE=None` --
  # no optimization flags at all, no -march=native. Measured on this
  # hardware: encoding 2s of audio took 28s with the pacman-built
  # whisper-cli vs 2.1s with a Release build of the identical source/
  # model -- a ~13x slowdown, present in every binary the package ships.
  # It also doesn't build whisper-stream at all (needs -DWHISPER_SDL2=ON,
  # which the PKGBUILD doesn't pass), and ati-voice-dictate-live needs
  # whisper-stream patched with patches/whisper-stream-poll-ms.patch
  # (adds --poll-ms/--vad-tail-ms, hardcoded upstream with no CLI flag).
  #
  # Builds both from the whisper.cpp-git AUR package's own cached source
  # (already fetched by dcli-sync/yay) and shadows the slow system
  # binaries via /usr/local/bin (already earlier in $PATH than /usr/bin)
  # + /usr/local/lib/whisper-cpp (registered through /etc/ld.so.conf.d,
  # so they keep working even if the yay cache is later cleared). See
  # .config/AtiScriptsV1/patches/README.md for the full writeup.
  local src="$HOME/.cache/yay/whisper.cpp-git/src/whisper.cpp-git"
  local patch="$DOTFILES_DIR/.config/AtiScriptsV1/patches/whisper-stream-poll-ms.patch"
  local build="$src/build-fast"
  local libdir="/usr/local/lib/whisper-cpp"

  if (( DRY_RUN )); then
    _DIM "  [dry] build whisper-cli + whisper-stream (Release, patched) from AUR cache, shadow via /usr/local"
    return
  fi

  # The AUR build tree is NOT guaranteed to still be there. dcli sync's own
  # yay invocation cleans it, so on a clean machine this module found
  # nothing 25 modules after the package was built and hard-failed -- while
  # working forever on a developer box where the tree happened to survive.
  # Depending on another tool's leftovers is the bug; re-fetching is the
  # fix.
  if [[ ! -d "$src" ]]; then
    _DIM "  AUR build tree is gone — re-fetching whisper.cpp-git sources"
    local fetch="$HOME/.cache/whisper-fast-src"
    rm -rf "$fetch"; mkdir -p "$fetch"
    if ( cd "$fetch" && yay -G whisper.cpp-git >/dev/null 2>&1 \
         && cd whisper.cpp-git \
         && makepkg --nobuild --noconfirm --skippgpcheck --nodeps >/dev/null 2>&1 ); then
      src="$fetch/whisper.cpp-git/src/whisper.cpp-git"
      build="$src/build-fast"
    fi
  fi

  # Still nothing: warn and skip rather than fail the install. This module
  # is a SPEEDUP, not a requirement -- the pacman-built whisper-cli works,
  # just ~13x slower -- so a missing source tree is not worth turning a
  # complete install into a failed one.
  if [[ ! -d "$src" ]]; then
    _WARN "whisper.cpp-git source unavailable — keeping the slower packaged whisper-cli"
    _WARN "  rebuild later with: ./wizard.sh --yes --only=whisper-fast"
    return 0
  fi

  # Idempotent: skip the (slow, few-minute) rebuild if already shadowed.
  # Checked via the patched --poll-ms flag rather than ldd against
  # $libdir: RUNPATH prefers whichever path resolves first, and an
  # earlier build's cache dir resolving fine (same file contents either
  # way) doesn't mean it's still pointed at $libdir specifically.
  if /usr/local/bin/whisper-stream --help 2>&1 | grep -q -- "--poll-ms"; then
    _OK "whisper-cli/whisper-stream already built + shadowed via /usr/local"
    return
  fi

  # --poll-ms/--vad-tail-ms not already in stream.cpp -> patch not
  # applied yet on this checkout of the AUR cache.
  if ! grep -q -- "--poll-ms" "$src/examples/stream/stream.cpp" 2>/dev/null; then
    run "cd $src && git apply $patch"
  fi
  run "cmake -S $src -B $build -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release -W no-dev"
  run "cmake --build $build --target whisper-cli whisper-stream -j$(nproc)"
  run "sudo mkdir -p $libdir"
  run "sudo cp $build/bin/lib*.so* $libdir/"
  run "echo $libdir | sudo tee /etc/ld.so.conf.d/whisper-cpp.conf >/dev/null"
  run "sudo ldconfig"
  run "sudo install -Dm755 $build/bin/whisper-cli /usr/local/bin/whisper-cli"
  run "sudo install -Dm755 $build/bin/whisper-stream /usr/local/bin/whisper-stream"
}


step_candy()        { [[ -d /usr/share/icons/candy-icons ]] && { _OK "candy-icons present"; return; }
                      run "cd /tmp && rm -rf master.zip candy-icons-master && wget -q https://github.com/EliverLara/candy-icons/archive/refs/heads/master.zip && unzip -qo master.zip && sudo mv candy-icons-master /usr/share/icons/candy-icons"; }

# Hintium -- the hint/scroll/caret tool config.py calls and nothing used to
# install.
#
# config.py resolves it as `which hintium-hint`, with a fallback to
# ~/Attia-Pro/Projects/Hintium/, a path that exists on exactly one machine in
# the world. Before this module existed, every other install entered the
# Super+Shift+F chord with no binary behind it: the mode chip appeared, the
# hint overlay never did, and nothing said why.
#
# Cloned rather than packaged (it is not in the AUR), into ~/.local/share so
# it is not mistaken for something the user is working on. Entry points are
# SYMLINKED, not copied, so a `git pull` in that directory takes effect
# immediately -- the same reason step_ati_scripts symlinks.
#
# TWO NAMES, ON PURPOSE
#
# The project renamed itself from "homerow" to "hintium", and at the time of
# writing that rename is on a branch and not yet on master: a fresh clone
# still ships homerow-hint / homerow-cli / homerow-daemon, while config.py
# already asks for hintium-hint. Installing only what shipped would leave
# hint mode broken on every new machine until the merge lands; installing
# only the new names would break today. So whichever set the checkout
# provides is linked under BOTH names. When master carries the rename this
# keeps working unchanged, and the homerow-* aliases can be dropped then.
HINTIUM_REPO="${HINTIUM_REPO:-https://github.com/Mohamedattiadev/Hintium}"
HINTIUM_DIR="${HINTIUM_DIR:-$HOME/.local/share/hintium}"
# Kept so an install done before the rename is migrated rather than
# duplicated.
HINTIUM_DIR_OLD="$HOME/.local/share/homerow"
step_hintium() {
  # Migrate a pre-rename clone instead of leaving two copies on disk.
  if [[ -d "$HINTIUM_DIR_OLD/.git" && ! -d "$HINTIUM_DIR/.git" ]]; then
    run "mv $HINTIUM_DIR_OLD $HINTIUM_DIR"
  fi

  if [[ -d "$HINTIUM_DIR/.git" ]]; then
    # `git pull --ff-only || true` on its own is a silent no-op whenever the
    # checkout is on a branch with no upstream -- which happens the moment
    # anyone checks out a feature branch in there to try something. The
    # update then stops happening and nothing says so. Report it instead.
    if (( ! DRY_RUN )) && ! git -C "$HINTIUM_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      _WARN "$HINTIUM_DIR is on '$(git -C "$HINTIUM_DIR" rev-parse --abbrev-ref HEAD)', which tracks nothing — leaving it alone"
    else
      run "cd $HINTIUM_DIR && git pull --ff-only --quiet || true"
    fi
  else
    run "mkdir -p $(dirname "$HINTIUM_DIR") && git clone --depth 1 $HINTIUM_REPO $HINTIUM_DIR"
  fi
  (( DRY_RUN )) && return 0
  [[ -d "$HINTIUM_DIR" ]] || { _WARN "hintium clone missing — skipping the symlinks"; return 0; }

  # role -> the filenames that have carried it, newest naming first.
  local linked=0 role src candidate
  for role in hint cli daemon; do
    src=""
    for candidate in "hintium-$role" "homerow-$role"; do
      [[ -f "$HINTIUM_DIR/$candidate" ]] && { src="$HINTIUM_DIR/$candidate"; break; }
    done
    [[ -n "$src" ]] || continue
    chmod +x "$src" 2>/dev/null || true
    run "sudo ln -sfn $src /usr/local/bin/hintium-$role"
    run "sudo ln -sfn $src /usr/local/bin/homerow-$role"
    linked=$((linked+1))
  done

  # The single front-end command, under bin/.
  for candidate in bin/hintium bin/homerow; do
    if [[ -f "$HINTIUM_DIR/$candidate" ]]; then
      chmod +x "$HINTIUM_DIR/$candidate" 2>/dev/null || true
      run "sudo ln -sfn $HINTIUM_DIR/$candidate /usr/local/bin/hintium"
      run "sudo ln -sfn $HINTIUM_DIR/$candidate /usr/local/bin/homerow"
      break
    fi
  done

  (( linked )) || { _WARN "no hintium entry points found in $HINTIUM_DIR"; return 0; }

  # Its own doctor is the install instructions in executable form, and it
  # knows about at-spi and per-browser flags this wizard does not. Advisory
  # only: a missing browser flag must not fail an install.
  if command -v hintium >/dev/null 2>&1; then
    hintium --doctor >/dev/null 2>&1 \
      && _OK "hintium --doctor passed" \
      || _WARN "hintium installed; run 'hintium --doctor' to see what it still wants"
  fi
}


uninstall_hintium() {
  # The symlinks go; the clone stays. It is a checkout under the user's own
  # ~/.local/share and may carry local commits, so removing it is a data
  # loss this uninstaller has no business deciding on. The path is printed
  # instead. Both naming eras are removed -- see step_hintium for why both
  # get installed.
  local f
  for f in hintium-hint hintium-cli hintium-daemon hintium \
           homerow-hint homerow-cli homerow-daemon homerow; do
    run "sudo rm -f /usr/local/bin/$f"
  done
  [[ -d "$HINTIUM_DIR" ]] && _OK "left the clone at $HINTIUM_DIR — delete it by hand if you want it gone"
  return 0
}

uninstall_simplenote() {
  # Removes the credentials and the pushed-note bookkeeping. The note itself
  # lives in your Simplenote account and is deliberately left alone -- an
  # uninstaller has no business deleting notes off a remote service.
  run "rm -f $HOME/.config/simplenote/credentials"
  run "rmdir --ignore-fail-on-non-empty $HOME/.config/simplenote 2>/dev/null || true"
  run "rm -rf ${XDG_STATE_HOME:-$HOME/.local/state}/simplenote-push"
  _DIM "  The Simplenote note itself was left in your account."
}

uninstall_candy_icons()      { run "sudo rm -rf /usr/share/icons/candy-icons"; }

uninstall_bootstrap()         { :; }  # do NOT pacman -R base-devel

uninstall_yay()               { :; }

uninstall_dcli()              { :; }

uninstall_dcli_sync()         { :; }

uninstall_dcli_sync_extra()   { :; }  # never removes packages, same as dcli_sync

uninstall_picom_pin()         { :; }  # removing the compositor mid-session leaves a bare desktop

uninstall_gpu() {
  # Removing a GPU driver mid-session is how you end up with no X on next
  # boot, so packages stay. Only the generated picom override is reversed.
  run "rm -f $HOME/.config/picom/gpu.env"
}

uninstall_cargo()             { :; }

uninstall_piper()             { :; }  # models may be shared

# Removes only the addon directory. Anki's collection, decks and cards
# live elsewhere and are never touched by this.
uninstall_ankiconnect() {
  run "rm -rf $HOME/.local/share/Anki2/addons21/2055492159"
}

uninstall_whisper()           { :; }  # models may be shared

uninstall_whisper_fast()      { :; }  # leave the fast binaries in place -- reverting to the ~13x slower pacman ones helps no one
