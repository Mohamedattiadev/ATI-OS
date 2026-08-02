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
| boot entries were never checked against the real root device | `boot-splash verify-root`, wired into `boot-splash check`, `validate.sh` and `boot-fallback` | `ed49d58` |

The §1.4 socket move turned out to matter more than the collision the audit
recorded. kitty appends `-<pid>`, so the *name* never collided — but the
socket sat in world-traversable `/tmp` as `srwxr-xr-x` with
`allow_remote_control yes`, which let any other local account drive the
terminal. `$XDG_RUNTIME_DIR` is mode 700.

---

## Still open

### 1.3 Popup geometry is fixed pixels, not `_s()`-scaled — *blocked on hardware*

`QtileCheatsheet` 880×580, `_cheatsheet_grid`'s 1366×768 reference panel,
`PINENTRY_W/H`, `FILE_CHOOSER_*_MIN`.

Everything else in the qtile config multiplies through `UI_SCALE`, so on a
4K panel the bar, fonts and margins scale and these popups don't — they
render correctly but small. Threading `UI_SCALE` through three cheatsheets'
layout arithmetic is a redesign, not a surgical fix, and it needs someone
to look at the result on a HiDPI screen. **Nobody has tested this repo on a
HiDPI panel**, so the change could not be verified even if it were written.

### 2.6 `rofi_docs`' system panels are silently Arch-only

`pacman -Qi`, `pacman -Qtdq`, `/var/cache/pacman/pkg`. Every call already has
`2>/dev/null` and an empty-result path, so off Arch the panels render *empty*
rather than erroring — which reads as "no data" instead of "wrong distro".
Saying so explicitly means restructuring ~15 panels.

Same shape, already correct: `boot-splash`'s `pacman -Qq plymouth` checks
degrade properly (`check` prints ✗, `status` says "not installed", `enable`
refuses) — the message just doesn't name the distro as the reason.

### 3.2 `arch-config.sh` keys the host identity off the username

It uses `id -un`, not the hostname, despite the field being called `host`.
It looks wrong every time someone reads it. It is a deliberate repo-wide
convention that `wizard.sh` and the yaml both depend on — changing it is a
cross-file semantic change, not a bug fix. Either change it everywhere at
once or rename the field to say what it means.

### 3.3 `speed_boost.sh`'s zram and sysctl values are tuned for 8 GB

`min(ram, 8192)` and `swappiness=180`. Sane Fedora-default policy at any RAM
size and the comments justify them at length, but they were chosen against
one machine.

---

## Verified correct — do not change

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
- **`copyq_rofi`'s one remaining `/tmp` path** is a `mktemp`, which is
  unique and mode 600. Correct as written; not part of the §1.2 sweep.
- **shellcheck**: SC2209 at `ui-scale:55-56` (`MODE=set` — `set` as a string
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

Outstanding:

1. **`./vm-test.sh`** — ~40 min, and the one layer that covers X11, systemd
   and boot. qemu and edk2-ovmf are installed and `--smoke` has passed
   before. Two things gate a full run: it needs ~5 GB of free RAM
   (`--check` refuses below that, by design), and it is **deliberately not
   unattended** — `archinstall` is interactive, so a human drives that one
   step. See the note below.
2. **A real second machine, ideally AMD.** The dead-package fix in
   `graphics-amd.yaml` is reasoned from `pacman -Si`, not observed on AMD
   hardware. Same for the `BAT1`/`ADP1` battery fix — reasoned from `/sys`
   semantics, never seen on a laptop that names them that way.
3. **A HiDPI panel** — see §1.3.

### `validate.sh`'s font list is hand-maintained

It is now exhaustive (8 families) and the regenerating query is recorded next
to the list, but it does not derive itself. Any config that starts naming a
new family will pass validation while rendering in a substituted face. That
is the exact failure this repo has now hit three times — most recently in
`eww/fonts.scss`, where `fira-code` had never been a family fontconfig knew.
