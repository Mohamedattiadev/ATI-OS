return {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {},
  -- stylua: ignore
  keys = {
    { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
    -- Give S back to Neovim (S = change the whole line).
    --
    -- Commenting the S entry out below did NOT disable it: lazy.nvim MERGES
    -- the `keys` of every spec for a plugin, and LazyVim's own flash spec
    -- (lazyvim/plugins/editor.lua) declares S itself. So S stayed bound to
    -- Flash Treesitter, just sourced from LazyVim rather than from this file.
    -- `false` as the second element is how lazy.nvim drops an inherited key.
    { "S", false },
    -- { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
  },
}
