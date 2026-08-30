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
| `ati-logout` | rofi theming, and the confirm step |
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

## Omarchy — MIT

<https://github.com/basecamp/omarchy>, by David Heinemeier Hansson (DHH)
and contributors.

**Vendored under `.config/quickshell/ati-menu/`**: `Commons/` and `Ui/`
(Omarchy's shared Quickshell QML component/design-token libraries, copied
verbatim), `plugins/menu/{Menu.qml,MenuModel.js}` — the tree-walking
command-menu UI itself, ported here to run against ATI-OS's own
`.config/AtiScriptsV1/lib/ati-menu.json`/`ati-menu-extensions.json` data files
and dispatch commands instead of Omarchy's — and
`services/{AppLibrary.qml,AppSearch.js}`, the desktop-application list the
menu's Apps section merges in via `DesktopEntries.applications` (a
Quickshell built-in, not Omarchy's). `Menu.qml`, `Commons/Color.qml`, and
`AppLibrary.qml` are modified:
- `Menu.qml` — `defaultMenuPath`/`userMenuPath` properties; a
  `shell.qml`-side `dmenu(payloadPath)` IPC entry point wiring the
  already-vendored `openDmenu()` up to callers for the first time;
  `dmenuRowListHeight()` changed from content-hugging to a fixed height
  (its own `dmenuFixedRowsHeight`/`dmenuFixedVisibleRows: 6` — deliberately
  smaller than the main menu's own `fixedVisibleRows: 10`, so a dmenu
  prompt reads as the small fixed box it is rather than main-menu-sized).
- `Commons/Color.qml` — `colorsFile`/`shellFile` switched from
  `watchChanges: false` to `true` (plus explicit `onFileChanged: reload()`).
  Upstream's own comment there said runtime theme switches "push the
  payload explicitly through shell IPC" — that IPC lives in Omarchy's own
  top-level `omarchy-shell.qml`, never vendored here, so this menu had no
  path to it at all; file-watching is the mechanism this repo already
  trusts for live reload elsewhere (`userShellFile` right below it,
  `ati-menu.json`'s own `defaultMenuFile`/`userMenuFile`). `ati-theme-apply`
  now writes `~/.local/state/omarchy/current/theme/colors.toml` itself (see
  its own comment there) — the path `Color.qml` already expected but
  nothing on this machine had ever written to — so a `style.theme` pick now
  reaches the menu's own colors live, no restart.
- `AppLibrary.qml` — `launch()`, which dropped a `uwsm-app --` prefix
  (Universal Wayland Session Manager, confirmed via `command -v` to not be
  installed or used in this session).

`MenuModel.js`, `AppSearch.js`, and everything else under `Commons/`/`Ui/`
are unmodified. `AppLibrary.qml`'s hidden-entry
management (`omarchy-remove-launcher-entry`, `hidden-entries.sh`) and
launch-feedback OSD (`omarchy-shell osd`) call Omarchy-specific scripts
that don't exist here and were left as-is rather than reimplemented —
they fail silently (no crash) rather than working, a known, minor gap
against the real thing. MIT's terms are compatible with GPL-3.0 in that
direction, same as the Hintium entry below.

**Vendored under `.config/quickshell/ati-menu/plugins/clipboard/`**:
`Clipboard.qml` and `ClipboardHistory.js` are Omarchy's own
`shell/plugins/clipboard/{Clipboard.qml,ClipboardHistory.js}`, including
its real data layer this time — an earlier pass here read ATI-OS's
`copyq` clipboard manager instead of capturing independently, which meant
a data-integrity bug in copyq's own text/image mime handling (confirmed
live: some entries carried raw PNG bytes under `text/plain`, copyq's own
`str()` conversion having already replaced the invalid leading byte with
U+FFFD by the time anything downstream could check for it) showed up as
garbage rows with no way to fix it from this side. Capturing directly the
way this file's own `wl-paste --watch` mechanism does, that bug class
cannot happen here at all.

`Clipboard.qml` is modified only in the property names for its script
paths (`captureScript`/`pasteTextScript`/`pasteFileScript`/`openScript`
point at this repo's own scripts below instead of building paths from an
`OMARCHY_PATH` env var that doesn't exist here) and the preview pane,
which now shows every entry's capture timestamp — upstream only ever
showed one for images (`imagePreviewText`), since only its own
`capture.sh` ever wrote one onto an image entry; `ati-clip-capture` (below)
writes one onto text entries too, and `ClipboardHistory.js` is modified in
exactly the two places (`normalizeEntry`, `displayRows`) needed to carry
that value through. Nothing else in either file changed — same layout,
same dedup/file-URI-detection logic, same full keyboard contract
(Up/Down/PageUp/PageDown/Home/End, Enter to paste, Shift+Enter to copy
only, Alt+Enter to open, Delete to remove one entry, Shift+Delete to
clear all with a confirm step, type-anywhere-to-filter), and the same
reuse of `ConfirmDialog`/`PointerMoveGate` from the vendored `Ui/`.

**Also vendored under `.config/AtiScriptsV1/`**: `ati-clip-capture`
(Omarchy's `shell/plugins/clipboard/capture.sh`, paths retargeted to this
repo's state directory, plus one addition — a timestamp on text entries,
see above — the sensitive-clipboard skip, content-addressed image
dedup, and UTF-16 text-encoding detection are all unmodified);
`ati-clip-paste-text` (Omarchy's `bin/omarchy-clipboard-paste-text`,
unmodified) and `ati-clip-paste-file` (`bin/omarchy-clipboard-paste-file`,
unmodified). `ati-clip-view-entry` is adapted rather than vendored
verbatim: same URL-sniff-else-editor logic for text entries as
`bin/omarchy-clipboard-open`, but `tensaku-edit` (an Omarchy-specific
image editor, not installed here) is swapped for `imv`, and
`omarchy-launch-browser`/`omarchy-launch-editor` are swapped for
`xdg-open` and this repo's own `alacritty -e nvim` editor idiom.

**Also vendored, near-verbatim**: `.config/AtiScriptsV1/system/ati-network-speedtest-probe`
(Omarchy's `bin/omarchy-network-speedtest`, one line changed —
`omarchy-cmd-present` isn't installed here, swapped for a plain
`command -v` check) and `ati-disk-speedtest` (Omarchy's
`bin/omarchy-disk-speedtest`, only the usage string/temp-file prefix and
default target directory renamed). `ati-network-speedtest` (no `-probe`
suffix) is original — a thin wrapper running the probe script for
download then upload in sequence, since Omarchy's own two-direction UI is
a dedicated QML panel (`omarchy-shell shell summon omarchy.speedtest`)
that wasn't ported.

**Also vendored, verbatim, unmodified**: `.config/AtiScriptsV1/lib/ati-emoji-data.json`
is Omarchy's own `shell/plugins/emojis/emojis.json` (1870 entries of
`{"e": emoji, "k": "keyword..."}`), copied as-is and read by
`ati-emoji-insert`; this is data, not code, and nothing in it was changed.

**Adapted, not vendored** — rewritten in bash against ATI-OS's own scripts
rather than copied: `.config/AtiScriptsV1/apps/ati-launch-webapp`,
`ati-webapp-install`, and `ati-webapp-remove` reimplement the *behaviour* of
Omarchy's `bin/omarchy-launch-webapp`, `bin/omarchy-webapp-install`, and
`bin/omarchy-webapp-remove` (favicon-fetch chain, `.desktop`-launcher
write-up, app-mode browser launch) — no Omarchy source text was copied, but
the design (icon-fetch fallback order, `.desktop` field layout, argument
shape) is theirs, ported to call `dcli`/`xdg-settings`/this repo's own
`ati-menu-select` instead of Omarchy's own tooling. `ati-install-gaming-steam`,
`ati-install-gaming-geforce-now`, `ati-install-gaming-xbox-controllers`, and
`ati-install-gaming-battlenet` are the same kind of behavioural port of
`bin/omarchy-install-gaming-*`, adapted where ATI-OS's base install differs
from Omarchy's (`[multilib]` is off by default here and must be enabled
first; Battle.net's install is pointed at Lutris's own installer rather than
reimplementing Omarchy's standalone umu-launcher/GE-Proton prefix).
`ati-keybindings` is a reduced-scope port of `bin/omarchy-menu-keybindings`
(search Hyprland's live `hyprctl binds` and dispatch the selection
immediately) — Omarchy's XKB keycode resolution and Lua-bind-config
awareness aren't ported, since `hyprctl binds -j` already reports plain key
symbols here.

**Not vendored, despite matching names**: `omarchy-font-current`,
`omarchy-font-list`, and `omarchy-font-set` in `.config/AtiScriptsV1/` are
new ATI-OS scripts, written from scratch — they are named exactly that
because the vendored `Menu.qml`'s `"fonts"` provider (`providers.fonts.script`,
unmodified) shells out to those literal command names, not because any
Omarchy source was copied into them. Unlike Omarchy's own font-set (which
rewrites the shared system fontconfig alias), ATI-OS's version scopes the
change to the menu's own `OMARCHY_MENU_FONT` override only, deliberately
leaving `.config/fontconfig/fonts.conf`'s own curated `monospace` alias
untouched.

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
