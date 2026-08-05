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
| `dm-setbg` | wallpaper path and picker integration |

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

## Anki — AGPL-3.0

<https://github.com/ankitects/anki>. A launcher bundle is vendored at
`.config/anki-launcher-25.07.5-linux/`. It is a redistributed upstream
application, not a modification: its own licence and terms apply, and
nothing in this repository claims otherwise.

> **Note for maintenance, not licensing:** this directory is ~79 MB and
> contributes materially to the size of a clone. It is a packaged
> application rather than configuration, and would be better installed from
> the AUR (`anki-bin`) than tracked here.

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
