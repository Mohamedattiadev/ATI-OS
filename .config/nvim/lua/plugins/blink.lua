return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
  },
  opts = {
    -- basic sources, no lazydev, no weird providers
    sources = {
      default = { "lsp", "path", "buffer", "snippets" },
    },

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
