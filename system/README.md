# `system/` — the files this desktop owns outside `$HOME`

ARCHITECTURE.md §2.3 names the gap this closes:

> `/etc/keyd/default.conf` was, until recently, the **only** record of the
> Caps-as-Alt mapping the whole desktop assumes. It was found by accident.

Everything under `.config/` is a stow symlink: the repo *is* the live file,
so it cannot drift. Nothing outside `$HOME` can work that way — `/etc` is
root-owned, and the programs that read it (keyd, pacman, systemd) will not
follow a symlink into a user's home for a file they treat as privileged.
So those files are **copied**, and a copy is a thing that can drift.

This directory is the answer to "drift from what?".

## The rule

**A file this repo authors outside `$HOME` lives here, at its real path
with `system/` on the front, and nowhere else.**

    system/etc/keyd/default.conf   →   /etc/keyd/default.conf

Not "here as well as in an installer heredoc". That was the actual state
before this directory existed, and the two disagreed: `step_keyd` wrote a
four-line `/etc/keyd/default.conf` containing only `capslock = leftalt`,
while `.config/keyd/default.conf` held the same remap *plus* the AltGr
repeat key. Running the installer would have silently deleted a working
feature. One file, one place, and the installer reads it.

## Installing them

    ./installScripts/wizard.sh --only=system-files

It is **opt-in**, and that is a statement about today's contents rather
than about the mechanism: the only file here belongs to `keyd`, which is
itself opt-in, so running the walker by default would put a keyd config on
machines that deliberately skipped keyd. The `keyd` module installs that
one file itself, through the same helper on the same source, so nothing is
missed. The day this directory holds a file every machine needs, the walker
moves to the default run — and `validate.sh` will require the step count
and the step table in `docs/install-git.html` to move with it.

The module walks this tree and `install -Dm644`s every file to its
mirrored absolute path. It is idempotent and it is the whole
mechanism — there is no manifest to keep in step, because the directory
layout *is* the manifest. Adding a new file means adding the file.

A step that needs more than a copy still owns that part: `system-files`
installs `/etc/keyd/default.conf`, and the `keyd` module separately loads
`uinput`, enables the service and reloads it. Copying a config is generic;
knowing that keyd needs `/dev/uinput` is not.

## What does NOT belong here

* **Files this repo only edits.** `/etc/default/grub`, `/etc/environment`,
  `/etc/pacman.conf` — the installer changes lines in files another package
  owns. A whole-file copy would clobber whatever else is in them.
* **Generated files.** `/etc/opt/chrome/policies/managed/wal-theme.json` is
  rewritten by `theme-apply` on every palette change. Its template is
  versioned; the output is not.
* **Anything with a secret in it.** Same rule as everywhere else in this
  repo.

Mode is `0644` for everything here so far. A file needing anything else —
an executable hook, a `0600` credential — needs a real decision about
whether it belongs in a git repo at all, and the module should grow an
explicit case rather than a mode being guessed from the source file's bits.
