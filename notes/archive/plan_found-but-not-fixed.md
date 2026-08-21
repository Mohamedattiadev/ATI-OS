# Found but not fixed

Everything a five-way audit of this repo turned up and deliberately left
alone, with the reason. Written 2026-08-03, immediately after the stability
pass (commits `53e200f`..`b25dd65`, merged as `50e04ce`).

**Revised 2026-08-03, later the same day.** Most of the backlog below has
since been fixed — see "Fixed since" at the top. What remains is genuinely
blocked on hardware nobody has, or is correct as written and recorded so
nobody "fixes" it again.

Nothing here is a regression. Each item was seen, judged, and either fixed
or skipped for a stated reason. The point of writing them down is that "we
looked at it and chose not to" is only useful if it survives longer than
the session that decided it.

**Read the reason before acting.** Several of these are *correct as written*.

---

## Fixed since this file was written

| was | fix | commit |
|---|---|---|
| §1.1 `gtkmm` was an AUR build nothing needed | undeclared; verified by a full `container-test.sh` that it never returns as a dependency. Still installed on this host, so it is in `audit-ignore.yaml` with the `pacman -Rns` command — uninstalling from a working machine is the owner's call | `94e87a0` |
| §1.2 ~30 fixed `/tmp` paths collided between accounts | all routed through `${XDG_RUNTIME_DIR:-/tmp/rofi-$(id -u)}` in one sweep | `ad57393` |
| §1.4 `kitty.conf` dead option + shared socket | `enable_graphics`/`enable_images` deleted (neither has ever been a kitty option, confirmed against 0.48.1); socket moved to `$XDG_RUNTIME_DIR` | `ad57393` |
| §2.1 `system-packages-ati.yaml` was a loaded gun | deleted outright | `5f94a23` |
| §2.2 `dunstrc`'s `[logall]` forked a 0-byte script per notification | rule and script deleted | `5f94a23` |
| §2.3 dead rofi themes / eww styles naming unresolvable fonts | rofi themes deleted; eww font names pointed at `FiraCode Nerd Font` | `5f94a23` |
| §2.4 `dm-*` sourced a helper by relative path and died silently | three-way lookup ending at `/usr/bin/_dm-helper.sh`, with a real error message | `68af5d8` |
| §2.5 `hosts/ati.yaml` referenced a module that doesn't exist | deleted | `94e87a0` |
| §3.1 `step_xmodmap` repurposed Caps Lock for everyone | moved to `OPTIN_MODS`; a default install now leaves Caps alone | `5f94a23` |
| §1.3 popups were fixed pixels, not `UI_SCALE`-scaled | all NINE popups scale now — the plan listed three cheatsheets, pinentry and the file chooser; an audit found the same bug in Audio, Bluetooth, Display, Wallpaper, Wifi and WifiQR. Verified byte-identical at 1.0 and proportional at 2.0 | `b6ab126`, `e438d4f` |
| §2.6 `rofi_docs`' Maintenance was silently Arch-only | refuses off Arch and names the distro. One guard at section entry covered 15 of the 20 pacman calls, so it did not need the panel-by-panel restructure the plan assumed | `b6ab126` |
| boot entries were never checked against the real root device | `boot-splash verify-root`, wired into `boot-splash check`, `validate.sh` and `boot-fallback` | `ed49d58` |

The §1.4 socket move turned out to matter more than the collision the audit
recorded. kitty appends `-<pid>`, so the *name* never collided — but the
socket sat in world-traversable `/tmp` as `srwxr-xr-x` with
`allow_remote_control yes`, which let any other local account drive the
terminal. `$XDG_RUNTIME_DIR` is mode 700.

---

## Still open

### 3.3 `speed_boost.sh`'s zram ceiling was chosen against one machine

`zram-size = min(ram, 8192)`. Worth being precise about what is and is not
machine-specific here: that is zram-generator's own expression and it
already scales with RAM — only the 8 GB *ceiling* is a fixed number, and it
only applies on machines larger than the one it was written on, where an
8 GB zram is a defensible cap anyway. `swappiness=180` and
`page-cluster=0` are the standard pairing for compressed swap.

Left alone deliberately. Changing swap policy on a hunch, against values
that are already RAM-adaptive and already justified at length in the
comments, would be worse than the complaint.

---

## Verified correct — do not change

- **`arch-config.sh` keys the host identity off the username, not the
  hostname**, despite the yaml field being called `host:`. It reads like a
  bug and cannot be renamed: `host:` is *dcli's* config schema, not this
  repo's — the string is baked into the `dcli-arch-git` binary, so renaming
  it would stop dcli finding its configuration. The behaviour is also the
  one wanted: these are per-USER package sets and dotfile profiles, and two
  accounts on one machine legitimately want different ones. Documented in
  place at `arch-config.sh` so the next reader does not "fix" it.
- **`grub_boost.sh` refuses rather than guessing.** It aborts on a
  trailing-comment or unquoted `GRUB_CMDLINE_LINUX_DEFAULT` instead of
  corrupting it. Strictly safer than the old behaviour, but it does mean a
  small number of hand-edited grub files need a manual edit first. The
  script says so and prints the offending line. Recorded so the refusal
  isn't mistaken for a bug.
- **`wizard.sh` hard-fails on non-Arch in `preflight`.** Deliberate — see
  the "Arch specifically · Linux generally" section of `README.md`.
  Loosening the gate would let pacman-only steps run on a distro that
  cannot satisfy them.
- **`boot/*.conf` hardcode `PARTUUID=021e8f52-…` and `intel-ucode.img`.**
  Reference copies that are never installed (`boot/README.md:39-54`); the
  wizard generates live entries from `/proc/cmdline`,
  `bootctl --print-esp-path` and whichever microcode file exists.
- **`config.py`'s `font="Ubuntu Bold"`** despite `fc-match "Ubuntu Bold"`
  answering Noto Sans CJK. libqtile builds via
  `FontDescription.from_string(f"{font} {size}px")` and pango parses that to
  family `Ubuntu` + weight 700. The `set_family()` path that *would* break it
  is only reachable from the `set_font` command, which this config never calls.
- **`container-test.sh`'s idempotency diff warns but never fails** —
  regenerated files legitimately differ between runs.
- **`ati-copyq-rofi`'s one remaining `/tmp` path** is a `mktemp`, which is
  unique and mode 600. Correct as written; not part of the §1.2 sweep.
- **shellcheck**: SC2209 at `ati-ui-scale:55-56` (`MODE=set` — `set` as a string
  value, false positive), SC2016 at `container-test.sh:100` (single-quoted
  in-container script, intentional), SC2015 at `scripts/pre-update.sh:70,142`
  (`A && B || C` where B is an always-succeeding `printf`).
- **`stow_script.sh` timestamp collision** if run twice inside one second —
  harmless (`mkdir -p`, and the second run backs nothing up).
- **`--audit`'s `graphics-*.yaml` glob** would pass a literal unmatched
  pattern to awk if those files were ever deleted. Audit-only, read-only, and
  the files are tracked.

---

## Not a code finding — verification debt

The stability pass was a *review*, not a proof. What is actually verified:

| | |
|---|---|
| `validate.sh` | green, now including the boot-entry root check |
| `wizard.sh --audit` | clean, no drift |
| `container-test.sh` | full install twice on a clean Arch container, no diff between runs, no `/home/ati` in anything deployed. Re-run after the `gtkmm` removal |
| reboot | **done.** The splash, the UKI frame and the corrected boot entries all came up clean on the first reboot after the stability pass |

What the container **cannot** cover, by its own admission: no X server, so
nothing about qtile, picom, animations or themes; no systemd, so no
services; no PCI bus, so `step_gpu` correctly detects nothing.

### The VM layer has now run, and it found five real bugs

`./vm-test.sh --unattended` exists as of 2026-08-03: it scripts a minimal
base system directly (pacstrap and bootctl, no archinstall — inside the VM
there is one disk, so the "might pick the wrong one" objection does not
apply), boots the installed system under UEFI from its own ESP, runs
`./install.sh`, and asserts the wizard's summary. Roughly two hours a run,
most of it compiling espanso.

Every one of these was invisible on the author's machine, and every one
presented as several unrelated broken modules *downstream* of its cause:

| bug | how it presented | fix |
|---|---|---|
| `pipewire-jack` vs `jack2` — both provide the virtual `jack`, which ffmpeg/mpv/timidity++ depend on. On a clean machine the resolver picks jack2, which conflicts with the declared pipewire-jack, and **pacman aborts the entire transaction** | 5 failed modules; **nothing installed at all**; the desktop would have come up as stock qtile | pre-seed the provider before `dcli sync` |
| The install needs **>40 GB of transient disk**. yay keeps every AUR build tree — source, and for Rust the whole `target/` — and prunes none of it | 6 failed modules, all `No space left on device`, starting 32 modules after the cause | reclaim the cache after sync |
| `rustup` has no default toolchain when `dcli sync` first builds with cargo. `step_cargo` sets it — at module 12, four modules too late | `paru` and `didyoumean` fail to build | seed `rustup default stable` alongside the jack provider |
| `informant` refuses every pacman transaction until Arch news is read. It installs itself mid-sync, and a fresh machine always has unread news | `boot-splash` (no plymouth) and the desktop check (no Xvfb) — 5 and 20 modules downstream | mark the news read after the sync |
| *(self-inflicted)* the cache reclaim deleted `whisper.cpp-git/src`, which `step_whisper_fast` rebuilds from | failed 25 modules later with an **empty** error log, because it fails via `_ERR`/`return 1` which never reaches stderr | keep-list |

The lesson worth keeping: on a clean install, **the module that reports the
failure is almost never the module at fault**. Reading the per-module
`.err` logs is what distinguished five root causes from twenty-two
symptoms, and capturing them off the guest before it disappears took three
attempts to get right (`scp` spells the port `-P`; `ssh` spells it `-p`).

**Result: 46 of 46 modules pass — a fully clean install — and the desktop
renders.** `validate.sh` passes inside the guest (the qtile config loads,
the fonts resolve), every boot entry's `root=` matches the guest's real
root device, and phase D starts qtile under Xvfb, confirms from the qtile
log that it loaded THIS config rather than silently falling back to the
built-in one, and screenshots a themed bar at 738 distinct colours.

Two more bugs surfaced getting there, after the five above:

| bug | how it presented | fix |
|---|---|---|
| `rustup` has no default toolchain when `dcli sync` first builds with cargo; `step_cargo` sets it at module 12, four modules too late | `paru` and `didyoumean` fail to build | seed it alongside the jack provider |
| `step_whisper_fast` rebuilds from `~/.cache/yay/whisper.cpp-git/src`, which `dcli sync`'s own yay invocation cleans — so it depends on another tool's leftovers surviving 25 modules | hard-failed on a clean machine, worked forever on a developer box | re-fetch through the PKGBUILD; warn and skip rather than fail, since it is a speedup not a requirement |

The `informant` fix also took two attempts: marking the news read as the
invoking user does nothing, because informant's pacman hook runs as ROOT
and checks root's read-state.

**A correction to the table above.** The AUR-cache row overstates its
case. `_reclaim_build_cache` has never reported freeing a single megabyte
in any run, while `step_whisper_fast`'s fallback DID fire with "AUR build
tree is gone" — so in the guest yay prunes those trees itself, and the
reclaim is a no-op there. What actually fixed the disk exhaustion was the
40G → 60G bump, not the cleanup. The 3.7G sitting in `~/.cache/yay` on
this machine is real and worth `yay -Sc`, but that is a long-lived
developer box, not a fresh install, and the two should not be conflated.
The reclaim is harmless and keeps the keep-list honest; it is not
load-bearing and should not be described as the fix.

Outstanding:

1. **`pacman-static` is an hour of the install, on its own.** It compiles
   pacman and every dependency statically from source, much of it
   single-threaded through autotools. It is a genuine safety net — the day
   it matters is the day nothing else can install anything — but it is the
   single biggest cost in a fresh install and nothing said so until now.
   The trade is documented at the declaration in `system-tools.yaml`;
   moving it to `optional.yaml` is a one-line change if faster installs are
   worth more than the net.
2. **`boot-splash` — FIXED, and confirmed by the clean run.** It demanded a
   `udev` hook in mkinitcpio.conf; Arch's current default ships `systemd`
   instead, so it refused on every freshly installed machine. Diagnosed by
   rebooting the run-8 disk and running `boot-splash check` inside it
   (two minutes, versus another 1.5-hour run) and verified on both hook
   styles — but no full `--unattended` run has happened since the fix.
   The earlier guess in this file that it was UKI-related was **wrong**;
   the UKI check passed all along.
3. **A clean end-to-end run — DONE.** As of the last run, 43 of 46 modules pass.
   The three fixes above were made after it and have not themselves been
   run end to end.
3. **The desktop on real hardware — picom and the animations are VERIFIED
   here; the VM still cannot cover them.** Xvfb has no GPU, so phase D's
   pass must not be read as though it does. On this machine they were
   measured directly: `picom --diagnostics` reports a working glx backend
   on Mesa Intel HD 520, and a 30fps `x11grab` of a window opening shows
   the per-frame delta ramp 12746 → 88499 → **94618** → 85911 → 67121 →
   53853 → 48810 before settling at ~48720, across about seven frames
   (~230 ms). The peak *above* the steady-state value is the tell: that is
   spring overshoot. An instant appear would jump once and stay flat.
   What actually remains is the same stack on OTHER hardware — AMD,
   NVIDIA, HiDPI.
3. **A real second machine, ideally AMD.** The dead-package fix in
   `graphics-amd.yaml` is reasoned from `pacman -Si`, not observed on AMD
   hardware. Same for the `BAT1`/`ADP1` battery fix — reasoned from `/sys`
   semantics, never seen on a laptop that names them that way.
4. **A HiDPI panel** — see §1.3. The scaling is now implemented and
   verified proportional (at 2.0 the sheets measure the same 3.6 / 2.0 /
   1.4 screenfuls as at 1.0, with pango measuring real glyph extents at
   both), but nobody has looked at it on a 4K screen.

### `validate.sh`'s font list is hand-maintained — **FIXED 2026-08-07**

It is now exhaustive (8 families) and the regenerating query is recorded next
to the list, but it does not derive itself. Any config that starts naming a
new family will pass validation while rendering in a substituted face. That
is the exact failure this repo has now hit three times — most recently in
`eww/fonts.scss`, where `fira-code` had never been a family fontconfig knew.

**Fixed.** The families are derived from the configs that name them, so what
is maintained by hand is the list of *sources* — which kinds of file name a
font, and how — and that changes far less often than the fonts do. Six
extractors: qtile `font=` and pango `font_family=` markup, kitty's four
`*_font` keys, alacritty `family =`, rofi `font:`, both GTK
`gtk-font-name`, dunst, and the `<prefer>` blocks in `fonts.conf`. Generic
aliases (`sans`, `monospace`, …) are skipped: requiring them would assert
that fontconfig works, not that a font is installed. CSS and qutebrowser
fallback stacks are still not scanned at all, on purpose — they name fonts
that are *meant* to be absent.

The hand list was already incomplete when this replaced it, which is the
point: `config.py` asks for **`Ubuntu Mono`** in five widgets and the list
only carried `Ubuntu`. Pango parses "Bold" off "Ubuntu Bold" as a weight, but
"Mono" is a different FAMILY. Nothing broke only because
`ttf-ubuntu-font-family` happens to ship both — luck, not coverage. The
derived set is 11 families, and also picks up `Noto Sans Mono CJK KR` and
`Noto Serif CJK KR` from the fontconfig aliases.

Verified by naming a font that does not exist in each of three different
config kinds — qtile, kitty, `fonts.conf` — and confirming each is caught,
named with the file that asked for it, and exits non-zero.
