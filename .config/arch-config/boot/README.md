# arch-config/boot — reference snapshots, NOT deployed

These files are copies of what this machine currently has. Nothing stows
or installs them. The wizard module `boot-fallback` **generates** the
equivalents at install time.

That distinction matters: a boot entry is machine-specific. `root=` here
is this laptop's PARTUUID, `intel-ucode.img` is this laptop's CPU vendor,
and `/boot` is this laptop's ESP mount point. Copied verbatim onto
another machine you get an entry that looks perfectly fine in
`bootctl list` and drops to an emergency shell the one time you need it.
So the module derives all three from the running system — `/proc/cmdline`
(authoritative; the primary entry is a UKI, so `arch.conf`'s `options`
line is ignored and has carried a stale PARTUUID for months),
`bootctl --print-esp-path`, and whichever ucode image actually exists.

| File | Live location | Notes |
| ---- | ------------- | ----- |
| `arch-lts.conf` | `/boot/loader/entries/` | LTS fallback, trimmed initramfs (~18MB) |
| `arch-lts-fallback.conf` | `/boot/loader/entries/` | LTS rescue, full-module initramfs (~205MB) |
| `linux-lts.preset` | `/etc/mkinitcpio.d/` | pacman owns this — the module edits it **in place** (adds `fallback` to `PRESETS`) rather than overwriting, or every `linux-lts` upgrade leaves a `.pacnew` |

Keep them updated when the live files change, so a diff still tells you
something. See TROUBLESHOOTING.md, "The two LTS entries, and who writes
them".
