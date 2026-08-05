# ATI-OS ISO — build plan

A bootable USB that installs this repo's desktop on a blank machine, with the
expensive compiles already done.

Written 2026-08-03. Nothing here is built yet.

---

## What "100% identical" can and cannot mean

The honest scope, decided up front so nobody is surprised at first boot.

**Identical — the ISO reproduces these exactly:**

- All 267 declared packages across the 18 module yamls, same versions as the
  build day (they come from the ISO's own frozen local repo).
- Every dotfile, stowed the same way by `stow_script.sh`.
- qtile config, picom, rofi themes, eww, kitty, dunst, fonts — byte-identical,
  because they are files in the repo, not generated.
- The wizard's 47 modules run in the same order, from the same code.

**Cannot be identical — machine-specific by nature:**

| thing | why | what the ISO does instead |
|---|---|---|
| boot entries (`PARTUUID`, microcode) | different disk, different CPU | generated at install from `/proc/cmdline` + `bootctl --print-esp-path`, exactly as the wizard already does |
| `GEMINI_API_KEY` and `~/.config/secrets.env` | it is your secret | seeded empty from the template; installer says so |
| Vaultwarden / Simplenote / scrcpy accounts | per-person | left unconfigured |
| GPU stack | AMD/NVIDIA/Intel differ | `step_gpu` detects at install, same as now |
| `host: ati` in `arch-config` | that field is a USERNAME (see `notes/archive/plan_found-but-not-fixed.md`) | installer asks for a username and writes a matching host yaml |
| Caps-Lock-as-Alt (`xmodmap`) | correct for exactly one laptop | stays opt-in, per the existing `OPTIN_MODS` decision |
| wallpapers (~500 MB clone) | author's personal repo | offered, not baked |

**And: it is a snapshot.** The ISO freezes packages at build day. It stays
installable for roughly 1–2 years, then the archlinux-keyring in it ages out
and signature checks start failing. This is Arch, not a defect in the build.
The mitigation is that `build-iso.sh` is unattended, so rebuilding is a
scheduled job, not a project.

---

## The boundary: compile vs. download

The rule is **bake what is slow to BUILD, not slow to DOWNLOAD**.

Downloading 267 repo packages is minutes. Compiling is hours. Measured costs
from this repo's own notes:

- `pacman-static` — ~1 hour on its own, single-threaded autotools
- `espanso-x11`, `paru`, `didyoumean`, `yt-x-git` — Rust
- `whisper.cpp-git` — C++, and `step_whisper_fast` rebuilds it Release

So: **the 30 AUR packages get prebuilt into a local pacman repo on the ISO.**
Repo packages are NOT baked — the user would re-download them on the first
`pacman -Syu` anyway, and a half-updated system is a partial upgrade, which is
the classic way to break Arch.

### The 30 AUR packages baked in

```
ani-cli            dmscripts-git   informant        python-simplenote   ttf-amiri
auto-cpufreq       downgrade       light            qtile-extras        ttf-cairo
betterlockscreen   espanso-x11     neovim-remote    rofi-pass           whisper.cpp-git
brave-bin          eww             pacman-static    shell-color-scripts-git  yay-bin
dcli-arch-git      google-chrome   papirus-folders  sweet-gtk-theme-dark     yt-x-git
didyoumean         gromit-mpx      paru             timeshift-autosnap
                                   python-pulsectl
```

They ship as real `.pkg.tar.zst` in an `[ati-local]` repo, **not** as
pre-extracted files. pacman still owns them, so upgrades stay clean and
`pacman -Qo` still answers.

The repo is **not signed**, and that is a decision rather than a shortcut.
The packages, the database and the pacman reading them all arrive on the same
read-only medium, so a signature would be verifying the medium against itself
— the same trust model archiso already uses for its own airootfs. What makes
it safe is that the repo is *temporary*: `ati-os-install` copies it into the
target to install from, then deletes both the packages and the `pacman.conf`
section before the first boot. The installed system tracks the normal Arch
mirrors and is never left with a permanent unsigned source.

The packages also are **not installed into the live environment** — they are
carried on it as files under `/usr/share/ati-os/repo`. The live session never
needs brave or eww; only the installer does, and it installs them into the
target.

### Three stages

| stage | what | cost to the user |
|---|---|---|
| baked in the ISO | base system, kernel, the 30 AUR packages, the dotfiles repo itself | 0 — already on the USB |
| during install | partition, pacstrap, `wizard.sh` runs its 47 modules | ~15–25 min instead of ~2 hours |
| after first boot, opt-in | whisper models (~630 MB), piper voices (~60 MB), wallpapers (~500 MB) | user's choice, on their bandwidth |

---

## Layout

```
installScripts/iso/
├── PLAN.md                  this file
├── build-iso.sh             driver — one command, unattended
├── aur-repo.sh              builds the 30 AUR pkgs in a clean chroot → [ati-local]
├── test-iso.sh              QEMU: boot the ISO, install unattended, assert
└── profile/                 archiso profile, forked from /usr/share/archiso/configs/releng
    ├── profiledef.sh        iso_name=ati-os, iso_label=ATI_OS_<date>, publisher
    ├── packages.x86_64      live-env packages + the baked set
    ├── pacman.conf          adds [ati-local] with SigLevel Required
    ├── airootfs/
    │   ├── etc/os-release           NAME="ATI-OS"
    │   ├── etc/issue, etc/motd      branded login banner
    │   ├── root/.zlogin             auto-launches the installer
    │   └── usr/local/bin/ati-os-install    the installer itself
    ├── efiboot/loader/entries/      "ATI-OS — Install"
    ├── syslinux/                    same, BIOS side
    └── grub/                        same, UEFI grub side
```

Nothing in `installScripts/` changes. The ISO is additive.

---

## The installer (`ati-os-install`)

**It does not reinvent the install.** `vm-test.sh` already contains a
partition + pacstrap + bootctl sequence that has been verified end-to-end
(`vm-test.sh:740-780`). That logic gets lifted into `ati-os-install`, so the
ISO installs by the same code path the VM harness has already proven.

Flow:

1. **Preflight** — UEFI, RAM, disk present, network reachable. Refuse with
   the specific number that failed, in the style of `vm-test.sh`'s preflight.

**The installer is UEFI-only, and refuses on BIOS.** The installed system
boots with systemd-boot, and every boot module in this repo — `boot-fallback`,
`boot-splash`, and `boot-splash verify-root` — is written against that layout.
A GRUB/BIOS path would be a second way to boot that nothing here tests, and an
untested boot path is the worst kind to ship. The ISO still *offers* a BIOS
boot entry: booting the live environment on an old machine to look around or
rescue something is useful even when installing there is not.
2. **Ask** — target disk (list, with sizes, confirm by typing the name),
   username, password, timezone, hostname. Nothing else.
3. **Partition** — `sgdisk` ESP + root, `mkfs.fat -F32` + `mkfs.ext4`.
   Unlike the VM, a real machine may have several disks, so this step is
   **always confirmed by a human**, never silently picked.
4. **pacstrap** — base + linux + firmware, then the declared package set,
   with `[ati-local]` mounted from the ISO so the AUR packages install as
   binaries instead of building.
5. **Clone + wizard** — clone the dotfiles repo (or copy the baked-in one when
   offline), then `./install.sh` for the 47 modules.
6. **Assert** — run `validate.sh` in the chroot before declaring success, and
   print the same summary card the wizard prints.

The known clean-install traps stay fixed, because they live in `wizard.sh` and
the ISO calls it unchanged: the `jack2` provider pre-seed, `rustup default
stable`, marking Arch news read as **root** for `informant`, and the
whisper.cpp build-tree fallback.

---

## Branding

Cosmetic, deliberately shallow — no forked packages, nothing that makes this
harder to rebuild.

| where | what you see |
|---|---|
| boot menu (UEFI + BIOS) | `ATI-OS — Install` / `ATI-OS — Safe graphics` |
| `/etc/os-release` | `NAME="ATI-OS"`, `ID=ati-os`, `ID_LIKE=arch` |
| login banner / motd | ATI-OS ASCII header |
| installer TUI | same box-drawing + colour palette as `wizard.sh` already uses |
| ISO volume label | `ATI_OS_202608` (shows as the USB's name) |
| boot splash | the existing plymouth `dotfiles.plymouth` theme, unchanged |

`ID_LIKE=arch` matters: it keeps every script and package that sniffs the
distro working. The wizard's own `preflight` hard-fails on non-Arch — this is
what keeps it passing.

---

## Testing on this machine

`test-iso.sh` runs four phases. It deliberately does **not** use ssh — adding
`sshd` to the product to make it testable would mean testing something other
than what ships.

| phase | what it boots | what it proves |
|---|---|---|
| **A0** | the ISO, through its own bootloader | the medium boots. Evidence is a framebuffer screenshot with more than 2 distinct colours |
| **A** | the ISO's kernel directly (`-kernel`) | the install runs unattended and the wizard's modules complete |
| **B** | the installed disk, medium detached | the boot entry actually works — reaches a login prompt |
| **C** | nothing; mounts the qcow2 via `qemu-nbd` | the installed filesystem is correct |

**A0 and A are split because qemu forces it.** Driving an unattended install
needs a kernel command line (archiso's `script=` hook), and qemu's `-append`
only applies to a kernel it loads itself with `-kernel`; booting from an
emulated CD offers no way to set the cmdline. So A bypasses the bootloader —
which means A alone would pass on an ISO whose bootloader was completely
broken. A0 is what closes that hole.

Phase C asserts: `/etc/os-release` says ATI-OS and keeps `ID_LIKE=arch`; the
dotfiles and qtile config landed; `[ati-local]` and its package cache were
removed; the boot entry's `root=PARTUUID` matches the real partition; the
kernel and initramfs are on the ESP; and the prebuilt AUR packages are
genuinely *installed* rather than merely carried — if pacman had ignored
`[ati-local]` and yay compiled them instead, the install still succeeds, it
just takes two hours, and nothing else would notice.

### What this test CANNOT cover

Unchanged from what the repo already documents, and it must not be
overclaimed:

- **No GPU.** Xvfb has no graphics hardware, so picom, glx and the animations
  are not covered. Phase D passing is not evidence about compositing.
- **AMD / NVIDIA** — no such hardware here.
- **HiDPI** — no 4K panel here.
- **Real USB boot** — QEMU boots the ISO file; writing it to a stick and
  booting real firmware is a separate, manual check.

### Host constraints (checked, real numbers)

| | this machine | needed |
|---|---|---|
| RAM | 7 GB total, ~5 GB free | 4 GB for QEMU — fits, but nothing else heavy at the same time |
| `/` free | **6.5 GB** | too small — all work dirs MUST go on `/home` |
| `/home` free | 102 GB | ~40 GB for build + test |
| `archiso` | **not installed** | `pacman -S archiso arch-install-scripts` |

Wall-clock estimate, this laptop:

| step | time |
|---|---|
| prebuild 30 AUR packages (pacman-static ~1 h, Rust builds) | 2–3 h |
| `mkarchiso` | 20–40 min |
| QEMU install + assert | 30–60 min |
| **total** | **~4–5 h**, mostly unattended |

Build and test cannot run at once — 7 GB of RAM will not hold both.

---

## Bugs found while building this

Recorded for the same reason `notes/archive/plan_found-but-not-fixed.md` exists: "we hit
this and fixed it" is only useful if it survives the session that found it.
Every one of these was invisible until something actually ran.

| bug | how it presented | fix |
|---|---|---|
| `aur-repo.sh` piped through `tee`, so the pipeline reported **tee's** exit status | a run that died on a sudo prompt with nothing built was reported as **exit 0, success** | the script writes its own log via process substitution; no caller can mask its status |
| preflight probed sudo with `sudo -n true`, the keepalive used `sudo -v` | preflight printed "ok sudo available", then the run stopped dead at a password prompt. `-v` validates credentials *in general*, so a command-scoped NOPASSWD rule satisfies one and not the other | both use `sudo -n true`; the keepalive is skipped entirely when sudo is passwordless |
| `mkarchroot` resolves its working dir with `readlink -f`, which returns **empty** when the path's *parent* does not exist | `ERROR: Please specify a working directory` — which reads as a missing argument, not a missing parent | create `$CHROOT` first; `$CHROOT/root` must still not exist |
| the chroot config was copied from the **host's** `/etc/pacman.conf` | this repo's own `00-preflight.hook` fired inside a fresh root and tried to exec `/usr/local/bin/pacman-preflight`. pacman said `call to execv failed (No such file or directory)` and named neither the hook nor the file | base on devtools' stock `extra.conf` instead |
| stock `extra.conf` has no `HookDir`, so it fell back to the compiled-in default — the host's hook directory again | **identical** error message, second run wasted | set `HookDir` explicitly to an empty directory. It *replaces* the default rather than adding to it (verified with `pacman-conf --config`), and must be inserted into `[options]` — appended it lands in `[extra]` and is silently ignored. `build-iso.sh` needs the same fix, because `mkarchiso` pacstraps the airootfs the same way |
| the BIOS speech menu label was rewritten by a substring match | the plain BIOS label is a prefix of the speech one, so one replacement hit both and produced a label with **two** syslinux accelerators (`^I` and `^s`) | replace the longer label first; assert one `^` per label |
| the password was interpolated into a single-quoted string inside an unquoted chroot heredoc | a password containing `'`, `$` or a backtick would break out and either fail the install or set a *different* password than the one typed | set passwords outside the heredoc, piping into `chpasswd` stdin, where no character is special |
| `test-iso.sh` wrote an autotest script and served it, but never passed `script=` to the guest | shellcheck flagged `HOST_FROM_GUEST` as unused — which was the only visible symptom of a phase that would have asserted nothing | phase A boots via `-kernel` with an explicit cmdline; phase A0 added to still cover the bootloader |

### Found by actually running it

| bug | how it presented | fix |
|---|---|---|
| **`[ati-local]` was added to `pacman.conf` but never `pacman -Sy`'d** | `Failed to install gum`, and nothing else installed. A repo with no synced database makes **every** pacman transaction fail — `error: failed to prepare transaction (could not find database)` — so the first package attempted takes the blame. Cost two full test runs and one wrong diagnosis (the chroot) | sync after wiring, then **verify**: the `.db` must exist and `pacman -Sl` must list packages |
| the wizard ran under `arch-chroot` | no systemd, no reliable environment. Not the cause of the gum failure, but not a path anything had ever proven either | moved to a first-boot systemd unit, where `vm-test.sh` proves the wizard works |
| the installer treated a wizard failure as a **warning** and still reported success | a machine with no desktop at all printed `INSTALL-OK` | the first-boot marker records the wizard's **exit status**, so "ran" and "succeeded" are different answers |
| `unwire_local_repo` deleted the packages **before** the wizard needed them | would have silently sent every AUR package back to compiling on the user's machine — undoing the ISO's entire purpose | cleanup moved into the first-boot script, after the wizard consumes the repo |
| phase A0 fired `screendump` at t=0 | qemu's monitor has **no `sleep` command**, so it captured qemu's own "Guest has not initialized the display" placeholder — whose ~6 colours passed a `colours > 2` assertion. **Phase A0 passed on a guest that never booted** | drive the monitor over a unix socket, wait on the host, and assert on two measured numbers (placeholder 6 colours/2.0% lit; real console 12/4.1%) |
| phase B grepped the serial log for a login prompt | the installed system's cmdline has no `console=ttyS0`, so getty output goes to VGA and could never appear there — a permanent **false negative** | assert what serial can actually prove: systemd-boot rendering the `ATI-OS` entry |
| `unsquashfs -e` takes a file *listing* targets, not a path | nothing was extracted, and `grep X file \|\| echo ok` printed **"ok"** because grep on a missing file returns non-zero — a verification step that examined nothing | check the file exists before asserting on its contents |
| the motd's ANSI codes had no `ESC` bytes | `[38;2;23;147;209m` printed as literal garbage on the first screen a user ever sees. The escape sequences were copied from a rendering where `ESC` is invisible | write real `\033` bytes, and verify at the byte level |

The pattern is the repo's own second lesson, over and over: **eleven of these
sixteen were the check being wrong rather than the code.** A preflight that
says "ok", a build that exits 0, a menu label that looks fine, a screenshot
nobody looked at, a grep against a file that was never extracted — every one
a false pass.

The two that actually mattered were both found the same way: by **reproducing
the failure standalone** instead of reasoning about it. `pacman-conf --config`
settled the HookDir question in seconds; a throwaway `pacman.conf` with an
unsynced repo settled the gum question after two hours of test runs had not.

## Result — 2026-08-03

`ati-os-2026.08.03-x86_64.iso`, 2.6 GB, volume label `ATI_OS_202608`.
**16 of 16 assertions pass across all four phases**, on the fifth build.

| verified | how |
|---|---|
| the medium boots through its own bootloader | phase A0 screenshot, **looked at**: `ATI-OS Live 7.1.5-arch1-2 (tty1)`, banner, root prompt. 16 colours / 3.46% lit, reproduced identically across two runs |
| the base system installs unattended | phase A |
| `[ati-local]` resolves | 32 prebuilt packages visible to pacman, asserted at install time |
| **every wizard module passes** | `46 ok · 0 not run · 0 failed`, parsed from the summary card — not inferred from an exit code, which returns 0 even when modules fail |
| the desktop installs in **~22 minutes** | measured, first boot start to marker write. The prebuilt repo's entire justification, against ~2 h without it |
| the installed system boots | systemd-boot renders the `ATI-OS` entry; 1219 packages, qtile/picom/rofi/dunst/kitty/eww all present |
| the boot entry is correct | `root=PARTUUID` compared against the real partition |
| the install-time repo is gone | both the `pacman.conf` section and the package cache |

### Still NOT verified — unchanged, and not laundered by a green run

- **the GPU path** — qemu has no graphics hardware. picom, glx and the
  window animations are untouched by all four phases.
- **AMD and NVIDIA** — no such hardware here.
- **HiDPI** — no 4K panel here.
- **a real USB stick on real firmware** — qemu boots the ISO *file*.

An ISO makes the install far easier to run, which means these paths now
reach strangers' machines. That is an argument for testing them, not for
reading 16/16 as though it had.

## Order of work

1. Install `archiso` + `arch-install-scripts`; fork the `releng` profile.
2. `aur-repo.sh` — clean-chroot build of the 30 packages, sign, `repo-add`.
   Cache the result; it is the expensive half and should not be rebuilt to
   change a menu label.
3. `profile/` — branding, `pacman.conf`, `packages.x86_64`.
4. `ati-os-install` — lifted from `vm-test.sh:740-780`, plus the prompts.
5. `build-iso.sh` — glue, with a preflight in the house style.
6. `test-iso.sh` — QEMU run, fix whatever it finds, re-run until clean.
7. Document: `README.md` section, and update `notes/archive/HANDOFF.md`'s verified table
   with what the ISO run actually proved — and what it did not.
