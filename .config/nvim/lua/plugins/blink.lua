return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
  },
  opts = {
    -- NOTE: `sources.default` is intentionally NOT set here.
    -- LazyVim lists it in `opts_extend`, so anything set here is APPENDED to
    -- LazyVim's list rather than replacing it. Since LazyVim already uses
    -- exactly { "lsp", "path", "snippets", "buffer" }, redeclaring it
    -- produced a doubled 8-entry source list (every provider queried twice).
    -- LazyVim also wires the `lazydev` source in for lua buffers on top.

    -- keep default keymaps for now (you can tune later)
    keymap = {
      preset = "enter",
      -- extra navigation (like tmux / vim muscle memory)
      ["<C-j>"] = { "select_next", "fallback" },
      ["<C-k>"] = { "select_prev", "fallback" },
    },

    -- don't touch completion.accept at all to avoid "Unexpected field" errors
  },
}
