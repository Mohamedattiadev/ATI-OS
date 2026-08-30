# ati-os — how it is put together, and how it should be extended

Written to answer one question, asked twice:

> why my dotfiles not so cool like omarchy and why omarchy has plugin things
> which any person can write and be added like smooth, and its whole system
> looks well organized can we make our like that?

This is the architecture document that comes *before* the reorganisation.
It is deliberately opinionated: it says what is already right and must not
be touched, what the three real gaps are, and what a plugin is allowed to
be. Nothing here is a rewrite.

---

## 1. The finding: this repo is not disorganised

That has to be said first, because the obvious reading of the question is
"tear it down and lay it out like Omarchy", and that would destroy working
infrastructure to fix a problem it does not have.

Measured against the tree as it stands:

| | state |
|---|---|
| `installScripts/install/` | already split `preflight / packaging / config / login / post-install / lib` — **Omarchy's own installer shape**, already adopted |
| `.config/AtiScriptsV1/` | 99 executables, and every one is named `ati-*`. The naming convention is already total |
| Omarchy references | 201 across the tree, each citing the upstream file it ports. This is a *tracked* upstream, not a vague inspiration |
| `quickshell/ati-menu/plugins/` | `menu`, `clipboard`, `translate` — a working plugin directory with a real pattern |
| `ati-menu-extensions.json` | an extension point that already exists, merged by **both** `ati-menu` (bash) and `Menu.qml` |

So the gap is not organisation. Omarchy does not feel organised because of
where its files sit; it feels organised because **a stranger can add
something without reading the codebase**. That is a contract problem.

---

## 2. The three real gaps

### 2.1 No extension contract

`ati-menu-extensions.json` is the only defined way in, it is one JSON blob,
and it is empty. Everything else — a new keybind, a new bar chip, a new
theme, a new tool — requires editing a file that already exists, by hand, in
a place you must already know about. There is no answer to "I wrote a thing,
where do I put it".

### 2.2 99 executables in one flat directory

The naming is consistent; the *grouping* is absent. `ati-adhkar`,
`ati-capture-qr`, `ati-install-gaming-steam` and `ati-wal-precompile` are
peers in the same directory and belong to four unrelated concerns. Nothing
is broken by this — `install.sh` symlinks the lot to `/usr/local/bin` and
they all work — but it is unreadable from outside, and it is the single
biggest reason the tree *looks* less organised than Omarchy's `bin/`.

### 2.3 Things that live outside the repo, silently

`/etc/keyd/default.conf` was, until recently, the **only** record of the
Caps-as-Alt mapping the whole desktop assumes. It was found by accident. A
system this integrated needs a stated rule for the files it owns outside
`$HOME`, and a way to install them.

---

## 3. What a plugin IS here

A plugin is **one directory** with a **manifest** and any subset of five
well-known subdirectories. Nothing else. It is installed by being present.

```
~/.config/ati-plugins/<name>/
    plugin.toml         # required — the manifest
    bin/                # executables, symlinked onto PATH
    binds.conf          # Hyprland binds, sourced after the base config
    menu.json           # entries merged into the ati-menu tree
    theme/              # palette + wallpaper, offered to the theme picker
    qml/                # a bar chip or a popup, loaded by the shell
```

`plugin.toml`:

```toml
name        = "pomodoro"
description = "A work timer that mutes notifications while running"
version     = "1.0.0"
# Refuse to load against an incompatible host rather than half-working.
requires    = { atios = ">=1.0", hyprland = ">=0.50" }
# Checked before anything is installed; a missing one is reported, not
# guessed at.
depends     = ["libnotify", "jq"]
# Optional lifecycle hooks. Each is run once, with the plugin dir as cwd.
[hooks]
install   = "hooks/install.sh"
uninstall = "hooks/uninstall.sh"
```

### The rules that make this work

1. **Everything is optional except the manifest.** A plugin that is only a
   theme has a `theme/` and nothing else. A plugin that is only a script has
   a `bin/`. This is what makes the barrier low enough that people actually
   write one.
2. **A plugin never edits a file it does not own.** No appending to
   `binds.conf`, no patching `ati-menu.json`. The host *reads* the plugin's
   own files. This is the whole difference between an extension mechanism
   and a pile of install scripts, and it is what makes uninstall a `rm -rf`.
3. **Namespacing is enforced, not requested.** A plugin's binds are loaded
   into a check that refuses a key already bound by the base config, and
   reports the collision by name. Two plugins fighting over `$mod K` in
   silence is how a plugin system stops being trusted.
4. **The host degrades, the plugin does not break the desktop.** A plugin
   with a bad manifest is skipped with a notification. A plugin whose QML
   fails to load is skipped — it must not take the bar down. This is
   non-negotiable: the bar is the desktop.

---

## 4. Where the code for this goes

One new script, `ati-plugin`, and one new loader hook per surface:

| surface | how the plugin reaches it |
|---|---|
| PATH | `ati-plugin sync` symlinks `*/bin/*` alongside the `AtiScriptsV1` symlinks |
| keybinds | `hypr/binds.conf` ends with `source = ~/.config/ati-plugins/*/binds.conf` — Hyprland already supports glob sourcing |
| menu | the merge that `ati-menu-extensions.json` already gets, widened to `*/menu.json` |
| themes | `ati-theme-*` gains `*/theme/` as a second search path |
| bar / popups | a `Loader` per `*/qml/`, wrapped so a failure is contained |

`ati-plugin` subcommands: `list`, `install <path|url>`, `remove <name>`,
`sync`, `doctor`. `doctor` is the one that matters — it reports collisions,
missing dependencies and failed loads in one place.

---

## 5. The reorganisation, in the order it is safe to do it

Each phase leaves a working desktop. None of them is a rewrite.

**Phase 1 — group the scripts, keep every path working.**
`AtiScriptsV1/` gains subdirectories by concern (`capture/`, `theme/`,
`system/`, `media/`, `islam/`, `install/`, `dev/`). `install.sh` already
walks the directory; it learns to recurse. **Every script keeps its name**,
so every keybind, menu entry and cross-reference in 17k lines of scripts
keeps working. This is a pure `git mv` plus one loop change, and it closes
gap 2.2 on its own.

**Phase 2 — write down what is owned outside `$HOME`. ✅ DONE.**
A `system/` directory in the repo mirroring the real paths
(`system/etc/keyd/default.conf`), and an installer module that copies them
with `install -m`. Closes 2.3. Small, and it stops the next silent
dependency.

Built as described, and it found the failure 2.3 predicts already in
progress: `step_keyd` wrote `/etc/keyd/default.conf` from an inline heredoc
carrying only `capslock = leftalt`, while `.config/keyd/default.conf` in
the same repo carried that **plus** the AltGr repeat key. Two records of
one file, disagreeing, with the installer's copy the one that would win — a
`--only=keyd` would have silently deleted a working feature. The heredoc is
gone; both `step_keyd` and the new `step_system_files` now install the one
file in `system/`, through one helper (`install_system_file`, in
`install/lib/common.sh`).

The directory layout is the manifest: `system/<path>` installs to `/<path>`,
so shipping the second file is adding the second file. See
`system/README.md` for what belongs there — and, more usefully, for the
three categories that do not (files this repo only *edits*, generated
files, anything holding a secret).

**Phase 3 — the plugin loader, read-only first.**
Implement `ati-plugin list|sync|doctor` and the five load points. Ship it
with **zero** plugins. Nothing changes for the user; the mechanism gets to
be proven while the blast radius is nil.

**Phase 4 — move one existing feature out into a plugin.**
`ati-adhkar` is the right candidate: self-contained, optional, has its own
timer and notification, and nobody else's code depends on it. If it cannot
be expressed as a plugin, the contract in §3 is wrong and this is where that
is discovered — before anything else is migrated.

**Phase 5 — a second theme as a plugin,** proving the `theme/` path against
the existing picker.

---

## 6. What NOT to do

- **Do not restructure `.config/` to look like Omarchy's repo.** Those paths
  are stow symlink targets and XDG locations; they are dictated by the
  programs that read them, not chosen.
- **Do not rewrite the installer.** It is already the shape being asked for.
- **Do not rename any script.** The names are the API — they are in
  keybinds, menus, comments, and muscle memory.
- **Do not let a plugin run arbitrary code at load.** Hooks run at *install*
  time, once, visibly. A plugin that executes on every login is a plugin
  that can make the desktop unbootable.
- **Do not build a registry, a marketplace, or an updater** until there is
  more than one plugin that is not written by this repo's author. Omarchy's
  own extension story is a directory and a convention.

---

## 7. The measure of success

Not "the tree looks tidier". This:

> A stranger writes a `plugin.toml`, drops a directory into
> `~/.config/ati-plugins/`, runs `ati-plugin sync`, and their thing works —
> without having read a single file in this repository.

Until that sentence is true, the reorganisation has not achieved what it was
asked to achieve.
