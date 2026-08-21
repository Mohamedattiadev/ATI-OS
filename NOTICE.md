# Third-party code in this repository

ATI-OS as a whole is licensed under the **GNU General Public License v3.0** —
see [`LICENSE`](LICENSE).

That choice is not arbitrary. This repository contains code derived from
GPL-3.0 projects, and the GPL does not permit relicensing a derivative work
under weaker terms. The list below records what came from where, which is
what the licence actually asks of anyone redistributing it.

## dmscripts — GPL-3.0

<https://gitlab.com/dwt1/dmscripts>, by Derek Taylor (DistroTube) and
contributors.

**25 files** vendored under `.config/dmscripts/scripts/` — `dm-note`,
`dm-kill`, `dm-wiki`, `dm-dictionary`, `dm-ip` and the rest, largely as
upstream ships them.

**2 files modified and kept alongside original work** in
`.config/AtiScriptsV1/`:

| file | what changed |
|---|---|
| `dm-logout` | rofi theming, and the confirm step |
| `ati-dm-setbg` | wallpaper path and picker integration |

These two are the reason the whole repository is GPL-3.0 rather than MIT.
They are derivative works of GPL-3.0 code sitting in the same directory as,
and calling into, the original scripts here.

`.config/dmscripts/scripts/dm-auto` additionally credits
<https://gitlab.com/dwt1/fzscripts>.

## archiso — GPL-3.0-or-later

<https://gitlab.archlinux.org/archlinux/archiso>, by the Arch Linux
developers. Three files under
`installScripts/iso/profile/airootfs/usr/local/bin/`, carrying their own
`SPDX-License-Identifier` headers:

- `choose-mirror`
- `livecd-sound`
- `Installation_guide`

## Anki

Not vendored, and no longer in this repository.

A launcher bundle for Anki 25.07.5 used to live at
`.config/anki-launcher-25.07.5-linux/` — 82 MB of tracked files, 78 MB of
which were `uv` binaries for amd64 and arm64. It was removed because it was
redundant three times over: `anki` is already declared in
[`apps.yaml`](.config/arch-config/modules/apps.yaml) and installed by the
installer, nothing in the repository referenced the bundled path, and the
bundled version was already behind the packaged one.

Anki itself is AGPL-3.0 — <https://github.com/ankitects/anki> — and is
installed from the Arch repositories like any other package.

## Hintium — MIT

<https://github.com/Mohamedattiadev/Hintium>, by the same author as this
repository. **Not vendored** — the installer clones it to
`~/.local/share/hintium` at install time, so it is a dependency rather than
part of this work. Its MIT terms are compatible with GPL-3.0 in that
direction.

## Everything else

Original work: the qtile configuration and its popups, `AtiScriptsV1`
(except the two files named above), the installer and its module
definitions, `boot-splash`, the ISO build scripts, the manual under `docs/`,
and the documentation.

Wallpapers are not in this repository. They are cloned at install time from
<https://github.com/Mohamedattiadev/wallpapers> and carry whatever terms
that repository states.
