# Packages — how this machine decides what is installed

## In one paragraph

Every package on this machine is written down in a file here. Nothing is
installed by hand. When you run `dcli sync`, it reads these files and makes
the system match them — installing whatever is listed and missing.

**Why bother?** Because the alternative is what most people have: a machine
that works, and no way to rebuild it. Install something at 2am, forget, and
six months later a fresh install is missing it with nothing to say what.
Here, if a package is not written down, it is not part of the system — and
`wizard.sh --audit` tells you the moment those two things disagree.

## The files, in the order they matter

| File | What it does |
| ---- | ------------ |
| `hosts/<you>.yaml` | **Start here.** Lists which module files are switched on for this machine. |
| `modules/*.yaml` | The actual package lists, grouped by purpose — `apps`, `dev`, `fonts`, `wm`, and so on. |
| `config.yaml` | One line: which host file above is the active one. |
| `audit-ignore.yaml` | Packages that are installed on purpose but deliberately never declared, each with the reason. |

Three module files are **not** listed in `enabled_modules`, and that is
intentional — `dcli sync` must never install them:

- `optional.yaml` — docker, JDK, qemu, printing. Nothing the desktop needs.
  Installed only by `./wizard.sh --yes --only=dcli-sync-extra`.
- `graphics-intel.yaml` / `-amd.yaml` / `-nvidia.yaml` — one of these is
  correct per machine. The wizard's `gpu` module reads the real PCI ids and
  installs the matching one.
- `splash.yaml` — plymouth, for the opt-in boot splash.

## Common things you might want to do

```bash
# Add a package permanently: put it in the right modules/*.yaml, then
dcli sync

# See what is installed but not written down (and vice versa)
./installScripts/wizard.sh --audit

# Preview a sync without changing anything
dcli sync --dry-run
```

If the audit reports a package as drift, you have two honest options: add
it to a module file, or add it to `audit-ignore.yaml` **with a reason**.
Silencing it without one is how the problem comes back.

## Layout

```
arch-config/
├── config.yaml              # one line that matters: which host is active
├── hosts/ati.yaml           # enabled_modules, host packages, update hooks
├── modules/*.yaml           # the actual package lists, grouped by purpose
├── scripts/                 # dcli update hooks (pre/post)
├── pacman-hooks/            # tool-independent PreTransaction guard
├── browser-policies/        # Chromium-family managed policy JSON
├── boot/                    # reference snapshots of boot entries (not deployed)
└── state/                   # dcli's own bookkeeping
```

## Host selection

`config.yaml` and `hosts/<user>.yaml` both carry a `host:` field and they
must agree. Rather than hand-editing them after a clone,
`installScripts/arch-config.sh` (wizard module `arch-config`) renames the
single host file to the current `$(id -un)` and rewrites both fields. It
refuses to guess if it finds zero or more than one host file, and backs
up anything it touches into `.backup-<timestamp>/` first.

## Modules

`hosts/ati.yaml` lists which modules are live under `enabled_modules`.
Files in `modules/` that are *not* listed there are inert:

| Module | Contents |
| ------ | -------- |
| `base.yaml` | always-on core: `base`, `base-devel`, dcli, timeshift, pacman-contrib |
| `apps.yaml` | daily applications |
| `wm.yaml` | qtile, qtile-extras, picom fork, qt5ct/qt6ct, tray applets |
| `dev.yaml` | editors, git, fish, toolchains |
| `media.yaml` | pipewire stack, mpv, easyeffects |
| `fonts.yaml` | Nerd Fonts, Amiri, Cairo, emoji, and every family a tracked config names by hand |
| `graphics.yaml` | vendor-neutral mesa/vulkan base |
| `network.yaml` | networking daemons and tools |
| `xorg.yaml` | X server and input/display utilities |
| `system-tools.yaml` | CLI utilities |
| `python-lib.yaml` | Python packages qtile's config and scripts import |
| `declared-packages.yaml` | *not enabled* — scratch list written by `dcli install`/`dcli search` |
| `graphics-intel.yaml`, `graphics-amd.yaml`, `graphics-nvidia.yaml` | *not enabled* — the wizard's `gpu` module picks one at install time from the PCI vendor id |
| `optional.yaml` | *not enabled* — docker/jdk/qemu/printing, installed only by `wizard.sh --only=dcli-sync-extra` |
| `splash.yaml` | *not enabled* — plymouth, installed only by the wizard's `boot-splash` module (a package that is inert until something hooks it into the initramfs) |
| `example.yaml` | template for a new module |

Declare a package where it belongs by purpose, not where it happens to
be convenient. Anything a config file calls **unguarded** must be
declared; a guarded optional fallback (`command -v x && x`) need not be.

Two failure modes these files have actually produced, both silent:

- **A package that no longer exists takes the whole transaction with it.**
  `graphics-amd.yaml` carried `libva-mesa-driver` and `mesa-vdpau` long
  after both were dropped from the repos. dcli installs a module's packages
  in one `pacman -S`, so a single "target not found" meant an AMD machine
  got no `vulkan-radeon` either and ran the desktop on llvmpipe — with
  nothing in any log naming a package. Before adding or keeping a name here,
  `pacman -Si <pkg>` it.
- **A font that is merely installed is not declared.** fontconfig never
  errors on a missing family; it substitutes one. `adwaita-fonts` and
  `noto-fonts` were named by tracked configs, present on the author's
  machine, and in no module at all — so a fresh install rendered the qtile
  systray and every GTK app in a different face than intended and said
  nothing. `validate.sh` now `fc-match`es every family the UI names.

## Update safety

`hosts/ati.yaml` wires two hooks with `behavior: always`, so they cannot
be skipped by accident — a safety check you can click past is not a
safety check.

- **`scripts/pre-update.sh`** runs *before* `dcli update`. It refuses
  (non-zero exit aborts the transaction before anything is downloaded)
  on: too little free space on `/`, timeshift snapshots living on the
  root filesystem, unread Arch news, an inconsistent package database,
  or unmerged `.pacnew` files. It also warns about high-impact packages
  (kernel, glibc, gcc-libs) in the pending batch. It reports; it does
  not repair.
- **`scripts/post-update.sh`** runs *after*, and checks whether a
  library soname bump actually broke anything — typically AUR packages,
  which no maintainer rebuilt for you. It catches this while you are
  still at the keyboard, rather than a week later when an app fails to
  launch and the cause is no longer obvious.

## The pacman hook

`pacman-hooks/00-preflight.hook` is installed to
`/etc/pacman.d/hooks/` by the wizard module `pacman-guard`. It duplicates
the free-space part of the pre-update check on purpose:

A dcli `update_hook` only protects `dcli update`. The pacman hook runs
for `dcli`, `yay`, `paru` and bare `pacman` alike, and it cannot stop
working silently if dcli changes its config format.

It is `AbortOnFail`, and its `Exec=` points at
`/usr/local/bin/pacman-preflight` — a symlink created by the *separate*
`ati-scripts` module. **If that target is missing, every pacman
transaction fails, including the one that would fix it.** The wizard
therefore refuses to install this hook until the script is in place; see
TROUBLESHOOTING.md if you have already managed it.

## Browser policies

`browser-policies/50-memory-saver.json` is installed by the
`browser-memory` module into `/etc/brave/policies/managed/`,
`/etc/chromium/policies/managed/` and
`/etc/opt/chrome/policies/managed/`. Memory Saver is a *preference*, not
a flag, so a `*-flags.conf` line cannot set it and a manual toggle is
lost whenever a profile resets. A managed policy applies on every
launch. Verify at `brave://policy`.

`TabDiscardingExceptions` matters as much as the saving: a discarded tab
stops executing, so anything holding a socket to notify you goes quiet.
That is why WhatsApp Web and friends are excluded.

## Boot entries

See `boot/README.md`. Those files are reference snapshots of what this
machine has — nothing stows or installs them, because a boot entry is
machine-specific. The wizard module `boot-fallback` derives the
equivalents from the running system instead.
