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
than about the mechanism: every file here belongs to software that is
itself opt-in -- `keyd`, and the container daemons from
`arch-config/modules/optional.yaml` -- so running the walker by default
would put a keyd config on machines that deliberately skipped keyd, and a
docker data-root on machines with no docker. The `keyd` module installs
its own file, through the same helper on the same source, so nothing is
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

## `etc/docker/daemon.json` + `etc/containerd/config.toml`

Both exist for one reason: **container storage does not fit on `/`.**

This machine partitions `sda` as 1G `/boot`, 32G `/`, 202G `/home`. Docker
uses the containerd snapshotter (`Storage Driver: overlayfs`,
`driver-type io.containerd.snapshotter.v1`), so image layers live under
containerd's root and **not** under `/var/lib/docker` -- which is why
there are two files here and not one:

    /var/lib/containerd   7.8G   snapshots + content blobs (images)
    /var/lib/docker       4.9G   volumes, containers, buildkit

12.7G, or 42% of everything on a 32G partition. On 2026-08-31 that
partition hit 100% full with 273M left, which stops every pacman
transaction dead (`00-preflight.hook` refuses to unpack with under 3G
free -- correctly). Pruning was not the answer: `docker system df` showed
only 970MB reclaimable, the rest being the live `poultrycareai-dev` stack
and its volumes.

So both roots moved to `/home/.container-storage/{docker,containerd}`,
which took `/` from 100% to 57%.

Notes for whoever touches this next:

* `containerd`'s file is **two keys**, deliberately. containerd fills every
  unset key from its built-in defaults, so a minimal file cannot pin stale
  defaults across upgrades the way a full `containerd config default` dump
  does. `version = 3` is the config schema for containerd 2.x.
* If you ever move this data by hand, `rsync -aHAX` **without `-S`** will
  expand every sparse file. Measured here: a 6.6G store arrived as 9.3G.
  Use `-aHAXS`, and stop both daemons first so the copy is consistent.
* Deleting the old directories is the step that actually frees `/`.
  Renaming or `--keep-old` frees nothing.

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
