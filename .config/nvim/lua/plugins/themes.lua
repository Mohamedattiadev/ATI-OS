return {
  --
  {
    "folke/tokyonight.nvim",
    enabled = false,
    -- lazy = false,
    -- priority = 1000,
    -- opts = {
    --   style = "moon", -- Options: "storm", "moon", "night", "day"
    --   transparent = false,
    --   terminal_colors = true,
    --   styles = {
    --     comments = { italic = true },
    --     keywords = { italic = true },
    --     functions = {},
    --     variables = {},
    --     sidebars = "dark", -- style for sidebars: dark/light/transparent
    --     floats = "dark", -- style for floating windows
    --   },
    --   sidebars = { "qf", "help", "terminal", "packer" },
    --   dim_inactive = true,
    --   lualine_bold = true,
    -- },
    -- config = function(_, opts)
    --   require("tokyonight").setup(opts)
    --   vim.cmd.colorscheme("tokyonight") -- apply it
    -- end,
    -- },
    -- {
    --   "ellisonleao/gruvbox.nvim",
    --   priority = 1000,
    --   config = function()
    --     -- Set Gruvbox as the default color scheme
    --     -- vim.cmd("colorscheme gruvbox")
    --
    --     -- Optional: Set the background (dark or light)
    --     -- vim.o.background = "dark" -- Use "light" if you prefer the light theme
    --   end,
    --   opts = {}, -- Optional: Add any other options for the plugin here if needed
    -- },
    -- {
    --   "olimorris/onedarkpro.nvim",
    --   priority = 1000, -- Ensure it loads first
    -- },

    -- Using Lazy
    -- {
    --   "navarasu/onedark.nvim",
    --   priority = 1000, -- make sure to load this before all the other start plugins
    --   config = function()
    --     require("onedark").setup({
    --       style = "darker",
    --     })
    --     -- Enable theme
    --     require("onedark").load()
    --   end,
    -- },
    -- {
    --   "catppuccin/nvim",
    --   lazy = false,
    --   name = "catppuccin",
    --   priority = 1000,
    --
    --   config = function()
    --     require("catppuccin").setup({
    --       transparent_background = true,
    --     })
    --     vim.cmd.colorscheme("catppuccin-mocha")
    --   end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local mode_file = vim.fn.expand("~/.cache/qtile/theme_mode")
        local ok, f = pcall(io.open, mode_file, "r")
        if ok and f then
          local m = (f:read("*l") or ""):gsub("%s+", "")
          f:close()
          local map = {
            wal = "wal",
            doomone = "doom-one",
            dracula = "dracula",
            gruvbox = "gruvbox",
            nord = "nord",
            tokyonight = "tokyonight",
            catppuccin = "catppuccin",
          }
          return map[m] or "doom-one"
        end
        return "doom-one"
      end,
    },
  },

  { "dylanaraps/wal.vim", lazy = false, priority = 999 },
  { "Mofiqul/dracula.nvim", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "shaunsingh/nord.nvim", lazy = true },
  { "folke/tokyonight.nvim", lazy = true },
  { "catppuccin/nvim", name = "catppuccin", lazy = true },

  {
    "NTBBloodbath/doom-one.nvim",
    lazy = false,
    priority = 1000,

    init = function()
      vim.g.doom_one_cursor_coloring = false
      vim.g.doom_one_terminal_colors = false
      vim.g.doom_one_italic_comments = false
      vim.g.doom_one_enable_treesitter = false
      vim.g.doom_one_diagnostics_text_color = false
      vim.g.doom_one_transparent_background = false
      vim.g.doom_one_pumblend_enable = false
      vim.g.doom_one_plugin_neorg = false
      vim.g.doom_one_plugin_barbar = false
      vim.g.doom_one_plugin_telescope = false
      vim.g.doom_one_plugin_neogit = false
      vim.g.doom_one_plugin_nvim_tree = false
      vim.g.doom_one_plugin_dashboard = false
      vim.g.doom_one_plugin_startify = false
      vim.g.doom_one_plugin_whichkey = false
      vim.g.doom_one_plugin_indent_blankline = false
      vim.g.doom_one_plugin_vim_illuminate = false
      vim.g.doom_one_plugin_lspsaga = false
    end,

    config = function()
      -- Watch ~/.cache/qtile/theme_mode. When theme-apply rewrites it,
      -- re-source pywal colors + reapply matching colorscheme so nvim
      -- palette stays synced with the rest of the desktop.
      local mode_file = vim.fn.expand("~/.cache/qtile/theme_mode")
      local wal_cache = vim.fn.expand("~/.cache/wal/colors-wal.vim")
      local function apply_from_mode()
        local ok, f = pcall(io.open, mode_file, "r")
        if not (ok and f) then return end
        local m = (f:read("*l") or ""):gsub("%s+", "")
        f:close()
        local map = {
          wal = "wal",
          doomone = "doom-one",
          dracula = "dracula",
          gruvbox = "gruvbox",
          nord = "nord",
          tokyonight = "tokyonight",
          catppuccin = "catppuccin",
        }
        local scheme = map[m] or "doom-one"
        if m == "wal" and vim.fn.filereadable(wal_cache) == 1 then
          pcall(vim.cmd, "source " .. wal_cache)
        end
        pcall(vim.cmd, "colorscheme " .. scheme)
      end
      apply_from_mode()
      local w = vim.uv.new_fs_event()
      if w then
        w:start(mode_file, {}, vim.schedule_wrap(function()
          apply_from_mode()
          w:stop(); w:start(mode_file, {}, vim.schedule_wrap(apply_from_mode))
        end))
      end
    end,
  },
}
