# Found but not fixed

Everything a five-way audit of this repo turned up and deliberately left
alone, with the reason. Written 2026-08-03, immediately after the stability
pass (commits `53e200f`..`b25dd65`, merged as `50e04ce`).

Nothing here is a regression from that pass. Each item was seen, judged, and
skipped for a stated reason — usually because the fix was wider than a bug
fix, or because it needs a decision only the owner can make. The point of
writing them down is that "we looked at it and chose not to" is only useful
if it survives longer than the session that decided it.

**Read the reason before acting.** Several of these are *correct as written*
and are recorded so nobody "fixes" them again.

---

## Priority 1 — will bite a real user

### 1.1 `gtkmm` is an AUR build that nothing needs

`modules/system-tools.yaml:23`. It resolves to **gtkmm2** (1:2.24.5), which
was dropped from the official repos, so every fresh install now spends an
AUR compile on it. On this machine `pacman -Qi gtkmm` reports
`Required By: None` and `Optional For: None`.

It was left in because removing a package on a hunch risks breaking
something invisible. The check that settles it: remove it from the yaml,
run a full `container-test.sh`, and confirm nothing pulls it back in as a
dependency. If clean, delete the line — it is pure install-time cost.

Same class, lower stakes: `neofetch` (`system-packages-ati.yaml:78`) also
left the repos. That file is inert (§3.1), so it costs nothing today.

### 1.2 ~30 fixed `/tmp` paths collide between user accounts

`rofi-kill`, `rofi_pass`, `rofi_shared`, `copyq_rofi`, `rofi_translator`,
`dm-weather`, `dm-satty`, `gg_scroll`, `wal-audit`, `ui-scale`,
`theme-apply`, and `dm-recordV2`'s `/tmp/recordingpid`.

The first account to run one creates the file mode 644; every other
account's write then fails with `EACCES`. The audit fixed only
`rofi_common.sh`, because that one had a property the others don't — a
failed redirect there meant the rofi command never ran, so **every
confirmation dialog silently answered "cancel"**. The rest degrade more
visibly.

This only bites on a machine with two accounts, which is why it wasn't
urgent. The fix is mechanical and should be done in one sweep rather than
piecemeal: route all of them through `${XDG_RUNTIME_DIR:-/tmp/rofi-$(id -u)}`,
the pattern `rofi_common.sh` now uses.

### 1.3 Popup geometry is fixed pixels, not `_s()`-scaled

`QtileCheatsheet` 880×580, `_cheatsheet_grid`'s 1366×768 reference panel,
`PINENTRY_W/H`, `FILE_CHOOSER_*_MIN`.

Everything else in the qtile config multiplies through `UI_SCALE`, so on a
4K panel the bar, fonts and margins scale and these popups don't — they
render correctly but small. Threading `UI_SCALE` through three cheatsheets'
layout arithmetic is a redesign, not a surgical fix, and it needs someone
to look at the result on a HiDPI screen. **Nobody has tested this repo on a
HiDPI panel.**

### 1.4 `kitty.conf` has a dead option and a shared socket

`kitty.conf:81` sets `enable_graphics yes`, which is not a kitty option —
kitty logs "Ignoring unknown config key" on every single start. Either the
intended option has a different name or the line is vestigial; it was left
alone rather than guessing at intent.

`kitty.conf:80` `listen_on unix:/tmp/kitty` is the same multi-user
collision as §1.2. `unix:/tmp/kitty-{kitty_pid}` or an `$XDG_RUNTIME_DIR`
path fixes it.

---

## Priority 2 — worth doing, no user impact today

### 2.1 `system-packages-ati.yaml` is a loaded gun

It declares `nvidia`, `plasma-meta`, `plasma-workspace`, `pulseaudio`,
`pulseaudio-alsa`, `grub`, `lightdm` and `xf86-video-{intel,amdgpu,ati,nouveau}`,
plus 68 packages duplicated from other modules. `pulseaudio*` directly
contradicts `media.yaml`'s `conflicts:` list — enabling this file would try
to install PulseAudio onto a PipeWire system, and Plasma and NVIDIA onto an
Intel qtile box.

It is genuinely inert: not in `enabled_modules`, and `dcli status` confirms
233 declared packages = the 10 enabled modules + `base.yaml` only.
`README.md` documents it as "not enabled — a captured snapshot".

Left alone because it is `dcli merge`'s output file and rewriting it isn't a
surgical fix. But it is one uncommented line away from doing real damage.
Deleting it deliberately is the right call; do it as its own commit.

### 2.2 `dunstrc`'s `[logall]` rule forks a 0-byte script per notification

`.config/dunst/scripts/log-all.sh` is executable and empty (0 bytes),
and the rule matches every notification. It's a fork-and-exec for nothing on
every notification you receive. Not a missing-file bug like the `[copy]`
rule that was fixed — this file exists — and it may be a deliberate
placeholder, so it needs a "did you mean to finish this?" from the owner.

### 2.3 Dead rofi themes and eww styles name fonts that don't resolve

`rofi/themes/dtos-dmenu.rasi` and `PowerMenu.rasi` name `FiraCode Nerd`,
`FiraCode Nerd Bold` and `Material Design Icons Desktop`; none resolves.
`eww/fonts.scss:16` (`$display-font: fira-code`) and `cheatsheet.scss:126`
(`BebasNeue`) likewise.

All are unreferenced — grep finds nothing loading either rofi theme, and
`cheatsheet.yuck` is commented out of `eww.yuck:3`. "Fixing"
`Material Design Icons Desktop 36` means picking a replacement glyph face
for a file nobody loads. **Delete the dead files instead**; that's the
honest fix and it removes the trap.

### 2.4 `dm-weather` / `dm-setbg` source a helper by relative path

`source ./_dm-helper.sh` depends on the current working directory and on the
upstream `dmscripts` package's layout. If both source attempts fail, `set -e`
kills the script with no message at all.

Fixing it properly means deciding where `_dm-helper.sh` should live — an
installer question, not a script question.

### 2.5 `hosts/ati.yaml:20` references a module that doesn't exist

`# - sys`, commented out. Both the wizard audit (`[[ -f ]] || continue`) and
dcli tolerate it. Cosmetic; delete the line.

### 2.6 `rofi_docs`' system panels are silently Arch-only

`pacman -Qi`, `pacman -Qtdq`, `/var/cache/pacman/pkg`. Every call already has
`2>/dev/null` and an empty-result path, so off Arch the panels render *empty*
rather than erroring — which reads as "no data" instead of "wrong distro".
Saying so explicitly means restructuring ~15 panels.

Same shape, already correct: `boot-splash`'s `pacman -Qq plymouth` checks
degrade properly (`check` prints ✗, `status` says "not installed", `enable`
refuses) — the message just doesn't name the distro as the reason.

---

## Priority 3 — decisions, not bugs

### 3.1 `step_xmodmap` repurposes Caps Lock as Alt for everyone

The comment is honest about why: Alt is dead in hardware on the author's
laptop. That is not detectable at runtime, so it cannot be conditionalised.

On a normal machine it is harmless — `clear mod1` is immediately followed by
`add mod1 = Alt_L Alt_R`, so the real Alt keys keep working and Caps simply
becomes a third Alt. But a stranger installing this loses Caps Lock with no
warning and no tap-to-Caps fallback.

This is a preference decision. Options: leave it, gate it behind a prompt,
or make it opt-in like `dcli-sync-extra`.

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

### 3.4 `grub_boost.sh` now refuses rather than guessing

It aborts on a trailing-comment or unquoted `GRUB_CMDLINE_LINUX_DEFAULT`
instead of corrupting it. Strictly safer than the old behaviour, but it does
mean a small number of hand-edited grub files need a manual edit first. The
script says so and prints the offending line. Recorded so the refusal isn't
mistaken for a bug.

### 3.5 `wizard.sh` hard-fails on non-Arch in `preflight`

Deliberate — see the "Arch specifically · Linux generally" section of
`README.md`. Loosening the gate would let pacman-only steps run on a distro
that cannot satisfy them. Recorded so nobody "fixes" it.

---

## Verified correct — do not change

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
| `validate.sh` | green |
| `wizard.sh --audit` | clean, no drift |
| `container-test.sh` | full install twice on a clean Arch container, no diff between runs, no `/home/ati` in anything deployed |

What that container **cannot** cover, by its own admission: no X server, so
nothing about qtile, picom, animations or themes; no systemd, so no
services; no PCI bus, so `step_gpu` correctly detects nothing.

Outstanding:

1. **Reboot.** The only real test of `boot-splash` now being a default module
   and of the `boot-fallback` rescue-entry fix. Note that an existing machine
   already has the *old, bad* LTS entries on disk — re-run
   `./wizard.sh --yes --only=boot-fallback` to regenerate them.
2. **`./vm-test.sh`** — ~40 min, needs qemu via
   `./wizard.sh --yes --only=dcli-sync-extra`. Covers X11, systemd and boot.
3. **A real second machine, ideally AMD.** The dead-package fix in
   `graphics-amd.yaml` is reasoned from `pacman -Si`, not observed on AMD
   hardware. Same for the `BAT1`/`ADP1` battery fix — reasoned from `/sys`
   semantics, never seen on a laptop that names them that way.
4. **A HiDPI panel** — see §1.3.

### `validate.sh`'s font list is hand-maintained

It is now exhaustive (8 families) and the regenerating query is recorded next
to the list, but it does not derive itself. Any config that starts naming a
new family will pass validation while rendering in a substituted face. That
is the exact failure this repo has now hit twice.
