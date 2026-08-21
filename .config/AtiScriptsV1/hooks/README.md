# Hooks

Extension points for this repo's own scripts, run via `ati-hook <name>` and
never edited into directly — this directory is the whole plugin mechanism.

## How it works

`ati-hook <name> [args...]` runs, in order:

1. `hooks/<name>` (a single file), if present and executable.
2. Every executable file in `hooks/<name>.d/`, alphabetically, skipping
   anything ending in `.sample`.

Any extra arguments passed to `ati-hook` are forwarded to each script. A
failing hook is logged to stderr and skipped — it never blocks whatever
called `ati-hook`.

Install a plugin without hand-editing this directory:

```sh
ati-hook-install post-update ~/my-check
```

That copies `~/my-check` into `hooks/post-update.d/` with the executable
bit set.

## Points that currently fire

| name              | fires                                             | args     |
|-------------------|----------------------------------------------------|----------|
| `post-update`     | at the end of a successful `ati-update`             | (none)   |
| `post-theme-apply`| at the end of `theme-apply`, after every app retints | `$1` = theme mode name |

This repo is untracked here on purpose — everything under `hooks/` except
this README is a per-machine plugin, not something `install.sh` ships or
`ati-update` manages.
