return {
  -- disable trouble
  { "akinsho/bufferline.nvim", enabled = false },
  { "mfussenegger/nvim-dap", enabled = false },
  { "leoluz/nvim-dap-go", enabled = false },
  { "mfussenegger/nvim-dap-python", enabled = false },
  { "David-Kunz/gen.nvim", enabled = false },

  -- ✅ disable animations/popups/UI overhead
  { "nvim-mini/mini.animate", enabled = false },

  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

  { "Exafunction/codeium.nvim", enabled = false },
  { "lazyvim.plugins.extras.ai.codeium", enabled = false },

  { "smear-cursor.nvim", enabled = false },

  { "dressing.nvim", enabled = false }, -- noice replaces this
  { "catppuccin", enabled = false }, -- you already use other themes

  -- rarely used
  { "crates.nvim", enabled = false }, -- rust only
  { "hererocks", enabled = false }, -- Lua dev

  -- too niche & heavy
  { "startuptime.vim", enabled = false },
  -- { "nvim-silicon", enabled = false },      -- code screenshots, not dev tool
  { "open-browser.vim", enabled = false }, -- rare usage

  -- formatting fluff
  { "tailwindcss-colorizer-cmp.nvim", enabled = false },

  -- tools you probably don’t use daily
  { "renamer.nvim", enabled = false },
  -- { "harpoon", enabled = false },
  { "venv-selector.nvim", enabled = false },

  -- fancy navigation
  { "grug-far.nvim", enabled = false },

  -- markdown extras (since you already render)
  { "markdown-preview.nvim", enabled = false },

  { "rcarriga/nvim-notify", enabled = false },

  { "folke/which-key.nvim", enabled = false },
  { "mrcjkb/rustaceanvim", enabled = false },
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

  { "lewis6991/gitsigns.nvim", enabled = false },

  -- NEW DISABLED PLUGINS (your request)
  { "mini.icons", enabled = false },
  { "antosha417/nvim-lsp-file-operations", enabled = false },
  { "folke/persistence.nvim", enabled = false },
  { "b0o/SchemaStore.nvim", enabled = false },
  { "nvimtools/none-ls.nvim", enabled = false },
  -- { "MeanderingProgrammer/render-markdown.nvim", enabled = false },

  -- UI frameworks (Primeagen does NOT use)
  { "folke/noice.nvim", enabled = false },
  { " MunifTanjim/nui.nvim", enabled = false },

  -- Visual addons Prime does not use
  -- { "folke/flash.nvim", enabled = false },
  { "michaelb/sniprun", enabled = false },

  -- Optional extras (your choice)
  -- In lua/plugins/ui.lua (or wherever indent-blankline is)
  { "lukas-reineke/indent-blankline.nvim", enabled = false },

  --

  --
}
