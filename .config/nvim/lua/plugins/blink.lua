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
      preset = "default",
    },

    -- don't touch completion.accept at all to avoid "Unexpected field" errors
  },
}
