# ATIVIM

A [LazyVim](https://lazyvim.github.io) configuration, trimmed for speed and
wired into the desktop's theme system.

## Layout

| Path | What is in it |
|---|---|
| `init.lua` | Entry point; hands off to `lua/config/lazy.lua` |
| `lua/config/` | Options, keymaps, autocmds, lazy bootstrap |
| `lua/config/theme_sync.lua` | The mode→colorscheme map and the highlight painter (see below) |
| `lua/plugins/` | Active plugin specs, one file per concern |
| `lua/plugins/disabled.lua` | LazyVim defaults switched off, each with the reason |
| `lua/notUsed/` | Specs kept for reference. Not on the runtime path |
| `Fixes/` | Notes on problems that took real work to diagnose |

## It follows the desktop theme

`theme-apply <mode>` recolours the whole desktop and writes two files:

- `~/.cache/qtile/theme_mode` — the mode name
- `~/.cache/qtile/current_palette.json` — the nine colour slots it just
  painted everything else with, plus `accent`, the one colour that means
  "this desktop" (the GTK accent, the qtile GroupBox highlight)

`lua/plugins/themes.lua` puts a filesystem watch on both, so **open editors
recolour without restarting**. It also reapplies on `FocusGained`, and
`:Theme` forces it.

Of the 22 modes, eleven have a colorscheme plugin and load it. The other
eleven — `matrix`, `synthwave`, `mono-light`, `github-dark`, … — are drawn
directly from the palette by `theme_sync.apply_palette`, so they still each
look different rather than collapsing onto one fallback.

Either way `theme_sync.apply_accents` runs afterwards, from a `ColorScheme`
autocmd, and paints the dashboard, Telescope and which-key groups from
`accent`. That last step is what makes the ATIVIM banner the same colour as
the bar. Without it the plugin-backed themes left those groups unset and the
start screen came out grey on every one of them.

To add a theme: add the mode to `scheme_of` and the plugin dir to
`plugin_of` in `lua/config/theme_sync.lua`, and add the plugin spec to
`lua/plugins/themes.lua`. Adding it to only one of those is the mistake to
avoid — `scheme_of` is the single source of truth that both the startup
colorscheme and the watcher read.

## Checking a theme change

There is no test runner here. To see what a mode actually resolves to:

```sh
nvim --headless -c 'lua vim.defer_fn(function()
  print(vim.g.colors_name, vim.inspect(vim.api.nvim_get_hl(0, { name = "SnacksDashboardHeader" })))
  vim.cmd("qa!")
end, 2000)'
```

An empty `SnacksDashboardHeader` means the start screen will render grey.
