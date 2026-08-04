# ATI-OS installation medium

A bootable USB that installs this repo's desktop on a blank machine, with the
expensive compiles already done.

`PLAN.md` is the design document — read it for *why*. This file is *how*.

## Build it

```sh
./aur-repo.sh      # 2-3 h, cached. 31 AUR packages -> a local pacman repo
./build-iso.sh     # 20-40 min. stages the profile, runs mkarchiso
./test-iso.sh      # 1-2 h. boots it in qemu, installs, asserts
```

Each takes `--check` to run only its preflight and touch nothing. Do that
first; the preflights are the reason a failure costs seconds instead of hours.

`aur-repo.sh` is separate from `build-iso.sh` on purpose: rebuilding 31 AUR
packages to change a boot-menu label would be absurd, so its output is cached
and `build-iso.sh` only checks for it.

Everything is written under `$ATI_ISO_WORK` (default `~/ati-os-build`), never
into the git checkout. On the author's machine `/` has ~6 GB free and `/home`
has ~100 GB, so the default deliberately points at `$HOME`.

## Write it to a stick

```sh
lsblk                      # find the right device FIRST
sudo dd if=~/ati-os-build/out/ati-os-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

`dd` does not ask. Check `lsblk` twice.

## Install from it

Boot the stick, then:

```sh
ati-os-install
```

It asks for the target disk (and makes you type the path twice), a hostname, a
username, a password, a timezone, a keyboard layout, a system language, and
whether to encrypt the disk. Nothing else.

## After the first boot: `letsgo`

There is **no display manager and no autologin**. You log in at a TTY and start
the session yourself:

```sh
letsgo          # or: startx
```

That is a deliberate choice, not something the installer forgot — see
`step_disable_dm` in `wizard.sh`, which turns every display manager off. The
desktop is a `startx` session; nothing launches it behind your back.

**UEFI only.** The installer refuses on BIOS/legacy — see `PLAN.md`. The live
environment still boots either way, so an old machine can be used for rescue.

## What the user still supplies

- `GEMINI_API_KEY` in `~/.config/secrets.env` (seeded empty from a template)
- Vaultwarden / Simplenote / scrcpy accounts
- their own wallpapers, if they do not want the author's

Not installed by default, deliberately:

- Caps-Lock-as-Alt — `./wizard.sh --only=xmodmap`
- docker, JDK, printing, qemu — `./wizard.sh --only=dcli-sync-extra`

## Rebuild it every 6 months

An ISO is a snapshot. The `archlinux-keyring` baked into it ages out in
roughly 1–2 years, after which it cannot install anything, and its kernel
stops recognising new hardware. This is Arch being Arch, not a defect.

`build-iso.sh` is unattended, so the honest version of "always works" is
*cheap to regenerate*, not *never expires*.

## Layout

```
aur-repo.sh    builds the 31 AUR packages in a clean chroot -> [ati-local]
build-iso.sh   stages the profile + repo + dotfiles, runs mkarchiso
test-iso.sh    4-phase qemu test (bootloader, install, boot, filesystem)
profile/       archiso profile, forked from releng
  airootfs/usr/local/bin/ati-os-install    the installer
```

`profile/` is a fork of `/usr/share/archiso/configs/releng` kept deliberately
close to it — every line that differs has to be re-reconciled when archiso
changes, so the diff is branding, the installer, and nothing else.

## What the test does not cover

Unchanged from what `HANDOFF.md` already records, and it must not be
overclaimed just because an ISO now exists:

- **the GPU path** — qemu has no graphics hardware, so picom, glx and the
  window animations are untouched by every phase
- **AMD and NVIDIA** — no such hardware here
- **HiDPI** — no 4K panel here
- **a real USB stick on real firmware** — qemu boots the ISO *file*

An ISO makes the install much easier to run, which means the untested paths
start reaching strangers' machines. That is an argument for fixing them, not
for reading a green test run as though it had.
