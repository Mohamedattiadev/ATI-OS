# `plugins/` — the plugins this repo ships

First-party plugins, scanned by `ati-plugin` alongside the ones a person
installs by hand in `~/.config/ati-plugins/`. Same contract, same five —
now six — surfaces, no privileges the other directory does not have.

## Why they are here and not in `~/.config/ati-plugins/`

Because a plugin that only exists in the user's directory does not survive
a fresh install. `adhkar` moved out of `AtiScriptsV1` in ARCHITECTURE.md
Phase 4, and had it landed only in `~/.config/ati-plugins/adhkar` the
feature would simply have been absent on every new machine — a migration
that deletes a feature is not a migration.

Two scanned roots rather than symlinking these into the user's directory:
a symlink would make `ati-plugin list` present a shipped plugin as though
somebody had installed it, and deleting it would appear to work right up
until the next `sync` put it back.

A plugin in `~/.config/ati-plugins/` with the same name **wins**, so any
of these can be replaced locally without editing the repo.

## Are these really plugins, or a directory pretending?

They are held to the contract exactly. `adhkar` is a `plugin.toml`, a
`bin/`, and a `[service]` declaration; nothing in the base config knows its
name any more. `autostart.conf` says `ati-plugin sync` and nothing about
adhkar — which is the actual test Phase 4 was for. If a first-party plugin
ever needs a hook the contract does not offer, that is a finding about the
contract, and it belongs in ARCHITECTURE.md before it belongs in code.
