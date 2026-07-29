# arch-config

Declarative description of this machine's packages and package-time
safety rails, consumed by [dcli](https://gitlab.com/theblackdon/dcli).

`dcli sync` reads the YAML here and makes the installed set match it.
Nothing in this directory is imperative — if a package is not declared
here, it is not part of the system, and the next sync is entitled to say
so.

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
| `fonts.yaml` | Nerd Fonts, Amiri, Cairo, emoji |
| `graphics.yaml` | Intel/mesa/vulkan drivers |
| `network.yaml` | networking daemons and tools |
| `xorg.yaml` | X server and input/display utilities |
| `system-tools.yaml` | CLI utilities |
| `python-lib.yaml` | Python packages qtile's config and scripts import |
| `system-packages-ati.yaml` | *not enabled* — a captured snapshot of manually-installed packages, kept for reference |
| `declared-packages.yaml` | *not enabled* — scratch list written by `dcli install`/`dcli search` |
| `example.yaml` | template for a new module |

Declare a package where it belongs by purpose, not where it happens to
be convenient. Anything a config file calls **unguarded** must be
declared; a guarded optional fallback (`command -v x && x`) need not be.

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
