# Handoff — paste this into a new session

## Where things stand

`~/.dotfiles` — Arch + X11 + qtile. Branches: work on `test`, merge to `main`, push both.
Current: `main` @ `fe2423a`, `test` @ `f588645`, clean, nothing unpushed.

A long session on 2026-08-03 did three things:

1. Worked the `plan_found-but-not-fixed.md` backlog — 13 of 14 items fixed,
   2 investigated and deliberately left alone.
2. Built `installScripts/vm-test.sh --unattended`, which did not exist before:
   it scripts a minimal Arch base system (pacstrap + bootctl, no archinstall),
   boots it under UEFI from its own ESP, runs `./install.sh`, and asserts the
   result. ~2 hours a run, most of it compiling `pacman-static` and espanso.
3. Used it to find **ten real bugs**, every one invisible on this machine
   because this machine was the single configuration where the code happened
   to work.

## Verified

| | |
|---|---|
| Clean-machine install | 46/46 modules, twice |
| `validate.sh` in the guest | passes (qtile config loads, fonts resolve) |
| Boot entries | all `root=` match the real root device |
| Boot + plymouth splash | confirmed by the owner watching a real reboot |
| qtile under X | starts, loads THIS config (not the fallback), renders |
| picom glx + animations | glx working on Mesa Intel HD 520; 30fps x11grab shows spring overshoot (~230ms) |
| All 9 popups (HiDPI) | byte-identical at scale 1.0, proportional at 2.0 |

## NOT verified — needs hardware nobody here has

- AMD and NVIDIA graphics (`graphics-amd.yaml` is reasoned from `pacman -Si`, never observed)
- A real HiDPI/4K panel (scaling is proven proportional mathematically, never looked at)
- `BAT1`/`ADP1` battery naming (reasoned from `/sys` semantics)

**The VM cannot cover the GPU path at all** — Xvfb has no graphics hardware, so
phase D passing must NOT be read as covering compositing or animations.

## The two lessons that matter most

**1. On a clean install, the module that reports the failure is almost never
the module at fault.** One full disk presented as five broken modules. One
blocked pacman presented as two. Always read the per-module `.err` logs that
`vm-test.sh` copies back to `~/vm-dotfiles-test/module-errors/` — not just the
wizard's summary card.

**2. Verify a check against a known-good case before trusting it.** Five times
in that session the *check* was wrong, not the code: a picom assertion that
reads "not found" even on a working display; "dead" README links that are
actually HTML anchors inside `<details>`; a "broken heading" that is a comment
in a code fence; desktop probes that reported a working stack as broken because
the daemons were already running; and picom filed as "untestable" when the
hardware was right there. Every one would have been a regression.

## Gotchas specific to this repo

- `vm-test.sh --unattended` clones from **GitHub**, so it tests what was last
  PUSHED, never the working tree. It refuses to start if the branch is ahead of
  its remote — do not bypass that guard without meaning to.
- Editing `vm-test.sh` while a run is in progress can corrupt it (bash reads
  scripts lazily by byte offset). Wait for the run to finish.
- A full run needs ~5 GB free RAM and 60 GB disk; the preflight refuses below
  that by design and names the number that failed.
- `host:` in `arch-config` means USERNAME, not hostname. It cannot be renamed —
  the string is baked into the external `dcli-arch-git` binary.
- `pacman-static` is roughly an hour of any fresh install on its own.
- Never add the Claude co-author trailer to commits.

## What a new user actually gets

A working, themed qtile desktop that boots — which was NOT true before this
session (a `jack2`/`pipewire-jack` provider conflict aborted the entire pacman
transaction, so a fresh install produced stock qtile with none of this config).

They still supply their own: `GEMINI_API_KEY` in `~/.config/secrets.env` (the
install seeds the file from a template with the key empty), Vaultwarden /
Simplenote / scrcpy accounts, and their own wallpapers if they do not want the
author's repo. Caps-Lock-as-Alt is opt-in and NOT part of a default install.

## Test layers, cheapest first

```
./installScripts/validate.sh              seconds  syntax + config load + fonts
./installScripts/wizard.sh --audit        seconds  declared vs installed packages
./installScripts/container-test.sh        ~3 min   real install as a different user
./installScripts/vm-test.sh --unattended  ~2 hours X11, systemd, boot, the desktop
```

Read `plan_found-but-not-fixed.md` first. It records what was fixed, what was
deliberately left alone and why, and what is still open — including items that
are *correct as written* and must not be "fixed".
