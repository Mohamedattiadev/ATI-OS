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
            tokyonight = "nord",
            catppuccin = "dracula",
            monokai = "monokai-pro",
            everforest = "everforest",
            ["rose-pine"] = "rose-pine",
            kanagawa = "kanagawa",
            oxocarbon = "oxocarbon",
            -- New themes fall back to closest installed nvim scheme.
            ["cyberpunk-neon"] = "dracula",
            synthwave = "dracula",
            matrix = "gruvbox",
            ["mono-dark"] = "doom-one",
            ["mono-light"] = "doom-one",
            nightowl = "nord",
            onedark = "doom-one",
            palenight = "nord",
            ["github-dark"] = "nord",
            ["ayu-mirage"] = "kanagawa",
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
  { "loctvl842/monokai-pro.nvim", lazy = true },
  { "neanias/everforest-nvim", lazy = true },
  { "rose-pine/neovim", name = "rose-pine", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },
  { "nyoom-engineering/oxocarbon.nvim", lazy = true },

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
      -- Sync nvim colorscheme with ~/.cache/qtile/theme_mode. Reapply on
      -- any of: fs_event (theme-apply rewrote the file), FocusGained
      -- (user tabbed back to terminal), :Theme user command.
      local mode_file = vim.fn.expand("~/.cache/qtile/theme_mode")
      local wal_cache = vim.fn.expand("~/.cache/wal/colors-wal.vim")
      local wal_json  = vim.fn.expand("~/.cache/wal/colors.json")

      -- dylanaraps/wal.vim only sets cterm* — invisible under
      -- termguicolors. Read colors.json and set gui* highlights so bg
      -- and syntax actually track the wallpaper. Overrides the common
      -- LazyVim dashboard/UI groups so those tint too.
      local function apply_wal_from_json()
        local ok, f = pcall(io.open, wal_json, "r")
        if not (ok and f) then return false end
        local raw = f:read("*a"); f:close()
        local ok2, d = pcall(vim.json.decode, raw)
        if not ok2 then return false end
        local c = d.colors; local bg = d.special.background; local fg = d.special.foreground
        vim.cmd("hi clear")
        if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
        vim.o.background = "dark"
        vim.g.colors_name = "wal"
        local set = function(g, o) vim.api.nvim_set_hl(0, g, o) end
        set("Normal",       { fg = fg,       bg = bg })
        set("NormalFloat",  { fg = fg,       bg = c.color0 })
        set("NormalNC",     { fg = fg,       bg = bg })
        set("SignColumn",   { fg = fg,       bg = bg })
        set("EndOfBuffer",  { fg = bg,       bg = bg })
        set("LineNr",       { fg = c.color8, bg = bg })
        set("CursorLineNr", { fg = c.color3, bg = bg, bold = true })
        set("CursorLine",   { bg = c.color0 })
        set("Visual",       { bg = c.color8 })
        set("Comment",      { fg = c.color8, italic = true })
        set("Constant",     { fg = c.color3 })
        set("String",       { fg = c.color2 })
        set("Statement",    { fg = c.color1 })
        set("Keyword",      { fg = c.color1 })
        set("Function",     { fg = c.color4 })
        set("Type",         { fg = c.color5 })
        set("Special",      { fg = c.color6 })
        set("PreProc",      { fg = c.color3 })
        set("Identifier",   { fg = c.color1 })
        set("StatusLine",   { fg = fg,       bg = c.color0 })
        set("StatusLineNC", { fg = c.color8, bg = c.color0 })
        set("TabLine",      { fg = c.color8, bg = c.color0 })
        set("TabLineSel",   { fg = bg,       bg = c.color4, bold = true })
        set("TabLineFill",  { bg = c.color0 })
        set("WinSeparator", { fg = c.color8, bg = bg })
        set("Pmenu",        { fg = fg,       bg = c.color0 })
        set("PmenuSel",     { fg = bg,       bg = c.color4, bold = true })
        set("PmenuThumb",   { bg = c.color4 })
        set("Search",       { fg = bg,       bg = c.color3 })
        set("IncSearch",    { fg = bg,       bg = c.color6 })
        set("MatchParen",   { fg = c.color6, bold = true })
        set("DiagnosticError", { fg = c.color1 })
        set("DiagnosticWarn",  { fg = c.color3 })
        set("DiagnosticInfo",  { fg = c.color4 })
        set("DiagnosticHint",  { fg = c.color6 })
        set("Error",        { fg = c.color1, bold = true })
        set("WarningMsg",   { fg = c.color3 })
        -- LazyVim / Snacks dashboard. Header uses c.color2 (precompile
        -- dominant slot = main wallpaper hue) so it matches qtile bar +
        -- brave accent. Icons use dominant too for consistent branding.
        set("DashboardHeader",       { fg = c.color2, bold = true })
        set("DashboardIcon",         { fg = c.color2 })
        set("DashboardDesc",         { fg = fg })
        set("DashboardKey",          { fg = c.color1 })
        set("DashboardFooter",       { fg = c.color8, italic = true })
        set("DashboardProjectTitle", { fg = c.color2, bold = true })
        set("SnacksDashboardHeader", { fg = c.color2, bold = true })
        set("SnacksDashboardIcon",   { fg = c.color2 })
        set("SnacksDashboardDesc",   { fg = fg })
        set("SnacksDashboardKey",    { fg = c.color1 })
        set("SnacksDashboardFooter", { fg = c.color8, italic = true })
        set("SnacksDashboardTitle",  { fg = c.color2, bold = true })
        set("SnacksDashboardFile",   { fg = fg })
        set("SnacksDashboardDir",    { fg = c.color8 })
        set("SnacksDashboardSpecial",{ fg = c.color2 })
        -- Alpha / Startify fallbacks
        set("AlphaHeader",    { fg = c.color2, bold = true })
        set("AlphaButtons",   { fg = fg })
        set("AlphaShortcut",  { fg = c.color1 })
        set("StartifyHeader", { fg = c.color2, bold = true })
        -- Sidebar / picker tint
        set("NeoTreeNormal",   { fg = fg, bg = bg })
        set("TelescopeNormal", { fg = fg, bg = bg })
        set("TelescopeBorder", { fg = c.color2, bg = bg })
        set("TelescopeSelection", { fg = fg, bg = c.color0, bold = true })
        set("WhichKeyGroup",   { fg = c.color2 })
        set("WhichKeyDesc",    { fg = fg })
        set("WhichKey",        { fg = c.color1 })
        set("BufferLineFill",  { bg = c.color0 })
        -- git signs
        set("DiffAdd",     { fg = c.color2 })
        set("DiffChange",  { fg = c.color3 })
        set("DiffDelete",  { fg = c.color1 })
        set("GitSignsAdd",    { fg = c.color2 })
        set("GitSignsChange", { fg = c.color3 })
        set("GitSignsDelete", { fg = c.color1 })
        return true
      end
      local map = {
        wal = "wal",
        doomone = "doom-one",
        dracula = "dracula",
        gruvbox = "gruvbox",
        nord = "nord",
        tokyonight = "tokyonight",
        catppuccin = "catppuccin",
        monokai = "monokai-pro",
        everforest = "everforest",
        ["rose-pine"] = "rose-pine",
        kanagawa = "kanagawa",
        oxocarbon = "oxocarbon",
        ["cyberpunk-neon"] = "dracula",
        synthwave = "dracula",
        matrix = "gruvbox",
        ["mono-dark"] = "doom-one",
        ["mono-light"] = "doom-one",
        nightowl = "nord",
        onedark = "doom-one",
        palenight = "nord",
        ["github-dark"] = "nord",
        ["ayu-mirage"] = "kanagawa",
      }
      local last_mode = nil
      local last_wal_mtime = 0
      local function read_mode()
        local ok, f = pcall(io.open, mode_file, "r")
        if not (ok and f) then return nil end
        local m = (f:read("*l") or ""):gsub("%s+", "")
        f:close()
        return m
      end
      local function wal_mtime()
        local st = vim.uv.fs_stat(wal_cache)
        return st and st.mtime.sec or 0
      end
      -- scheme name -> lazy.nvim plugin dir name (for on-demand load).
      local plugin_for = {
        ["doom-one"] = "doom-one.nvim",
        dracula = "dracula.nvim",
        gruvbox = "gruvbox.nvim",
        nord = "nord.nvim",
        tokyonight = "tokyonight.nvim",
        catppuccin = "catppuccin",
        ["monokai-pro"] = "monokai-pro.nvim",
        everforest = "everforest-nvim",
        ["rose-pine"] = "rose-pine",
        kanagawa = "kanagawa.nvim",
        oxocarbon = "oxocarbon.nvim",
        wal = "wal.vim",
      }

      local function try_load_plugin(scheme)
        local plug = plugin_for[scheme]
        if not plug then return end
        local ok, lazy = pcall(require, "lazy")
        if ok then pcall(lazy.load, { plugins = { plug } }) end
      end

      local function set_scheme(scheme)
        try_load_plugin(scheme)
        local ok = pcall(vim.cmd, "colorscheme " .. scheme)
        if ok then return true end
        -- Retry after next tick so lazy load can finish plugin setup.
        vim.defer_fn(function()
          try_load_plugin(scheme)
          if not pcall(vim.cmd, "colorscheme " .. scheme) then
            try_load_plugin("doom-one")
            pcall(vim.cmd, "colorscheme doom-one")
          end
        end, 30)
        return false
      end

      local function apply(force)
        local m = read_mode()
        if not m then return end
        local mt = wal_mtime()
        -- wal mode: reapply when colors-wal.vim mtime changed (wallpaper switch).
        -- Preset modes: reapply only when mode name changed.
        local changed = force or (m ~= last_mode) or (m == "wal" and mt ~= last_wal_mtime)
        if not changed then return end
        last_mode = m
        last_wal_mtime = mt
        if m == "wal" then
          -- Native json reader — sets gui* highlights (wal.vim only
          -- sets cterm*, invisible under termguicolors).
          if not apply_wal_from_json() then
            set_scheme("doom-one")
          end
        else
          set_scheme(map[m] or "doom-one")
        end
      end
      apply(true)

      local function arm_fs(path, cb)
        local w = vim.uv.new_fs_event()
        if not w then return nil end
        local function start()
          w:start(path, {}, vim.schedule_wrap(function()
            cb()
            vim.defer_fn(function() pcall(w.stop, w); start() end, 50)
          end))
        end
        start()
        return w
      end
      -- watch theme_mode (preset switches) + colors-wal.vim (wallpaper switches).
      arm_fs(mode_file, function() apply(false) end)
      arm_fs(wal_cache, function() apply(false) end)

      vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
        callback = function() apply(false) end,
      })
      vim.api.nvim_create_user_command("Theme", function() apply(true) end,
        { desc = "Reapply colorscheme from ~/.cache/qtile/theme_mode" })
    end,
  },
}
