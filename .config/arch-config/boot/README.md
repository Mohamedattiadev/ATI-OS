# Boot entries — the spare key for your own machine

## What this is, in plain terms

Arch is a rolling release: you upgrade whenever you like, and one of those
upgrades will eventually ship a kernel that does not boot on your hardware.
It is rare. It is also unrecoverable if the only kernel you have is the
broken one — you get a black screen, and fixing it requires a working
Linux, which is exactly what you just lost.

So this machine installs **two** kernels:

- **`linux`** — the normal one. This is what boots every day.
- **`linux-lts`** — long-term support. Older, changes slowly, and therefore
  almost never broken by the same upgrade that broke the normal one.

When the normal kernel fails, you pick the LTS entry at the boot menu and
land in a working system where you can actually repair things. That is the
whole idea: a spare key, kept in the door.

## Why a second kernel is not enough on its own

Installing `linux-lts` gives you the kernel file and **nothing else**. It
adds no boot menu entry, so nothing at the boot screen offers it to you.
You would reboot into a broken system and discover the rescue kernel you
carefully installed was never reachable.

The wizard's `boot-fallback` module writes the two entries that make it
selectable:

| Entry in the boot menu | What it is | Size |
| ---------------------- | ---------- | ---- |
| **Arch Linux (LTS fallback)** | LTS kernel, normal startup image. Try this first. | ~18 MB |
| **Arch Linux (LTS rescue - all modules)** | LTS kernel with *every* driver included, not only the ones this machine happened to need when the image was built. Slower to start. Use it when the first entry still cannot find your disk or keyboard. | ~205 MB |

It also sets `timeout 5`, because systemd-boot hides the menu by default —
and a rescue entry you cannot select is not a rescue entry.

## Why the files in this folder are not used

**Nothing here is installed.** These are copies of what this laptop
currently has, kept so you can diff against them and see what changed.

A boot entry is machine-specific in three ways at once:

- `root=` names *this* disk's partition (a PARTUUID)
- `intel-ucode.img` is *this* CPU's vendor
- `/boot` is *this* machine's EFI partition mount point

Copy these onto another machine verbatim and you get an entry that looks
perfectly correct in `bootctl list` and drops to an emergency shell the one
time you need it. So the wizard **generates** them instead, reading all
three from the running system: `/proc/cmdline`, `bootctl --print-esp-path`,
and whichever microcode file actually exists.

## One deliberate difference: these entries are never "quiet"

If you enable the boot splash (`boot-splash enable`), the main entry gets
`quiet splash` and shows your name over a progress bar instead of kernel
text.

These rescue entries are explicitly **stripped** of those options. A rescue
entry that inherited the splash would show a logo while hiding the kernel
messages that say what broke — indistinguishable from the failed boot you
are trying to escape.

## Files

| File | Live location | Notes |
| ---- | ------------- | ----- |
| `arch-lts.conf` | `/boot/loader/entries/` | LTS fallback, trimmed startup image |
| `arch-lts-fallback.conf` | `/boot/loader/entries/` | LTS rescue, all drivers included |
| `linux-lts.preset` | `/etc/mkinitcpio.d/` | pacman owns this — the module edits it **in place** (adds `fallback` to `PRESETS`) rather than overwriting, or every `linux-lts` upgrade leaves a `.pacnew` |

Keep them updated when the live files change, so a diff still tells you
something.

## Checking it actually works

```bash
bootctl list                                             # both LTS entries should appear
./installScripts/wizard.sh --yes --only=boot-fallback    # rewrite them
```

The honest limit: the only complete test is rebooting and picking the
entry. Do that once, deliberately, while everything is fine — finding out
the spare key does not turn is much better on a Tuesday afternoon than
during a real failure.

See also TROUBLESHOOTING.md, "The two LTS entries, and who writes them".
