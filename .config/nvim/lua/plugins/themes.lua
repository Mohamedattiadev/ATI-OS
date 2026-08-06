-- Colorschemes, and the machinery that keeps nvim in step with the desktop.
--
-- `theme-apply <mode>` repaints the qtile bar, GTK, qt, btop, glow and the
-- terminal, then writes the mode name and its palette into ~/.cache/qtile.
-- The doom-one block at the bottom watches those files and switches nvim to
-- match -- live, in already-open instances, no restart.
--
-- All the mode/scheme knowledge lives in lua/config/theme_sync.lua so the
-- LazyVim opt below and the watcher cannot disagree.

local sync = require("config.theme_sync")

return {
  -- Startup colorscheme. Picks the same answer the watcher would, so there
  -- is no flash of the wrong theme before the first apply() runs.
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        return sync.scheme_for(sync.read_mode()) or sync.fallback
      end,
    },
  },

  -- One entry per mode in theme_sync.scheme_of. catppuccin is not here: it
  -- is switched off in lua/plugins/disabled.lua, so the catppuccin mode
  -- renders from current_palette.json instead.
  { "dylanaraps/wal.vim", lazy = false, priority = 999 },
  { "Mofiqul/dracula.nvim", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "shaunsingh/nord.nvim", lazy = true },
  { "folke/tokyonight.nvim", lazy = true },
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
      local last_mode = nil
      local last_wal_mtime = 0

      local function wal_mtime()
        local st = vim.uv.fs_stat(sync.wal_cache)
        return st and st.mtime.sec or 0
      end

      local function try_load_plugin(scheme)
        local plug = sync.plugin_of[scheme]
        if not plug then
          return
        end
        local ok, lazy = pcall(require, "lazy")
        if ok then
          pcall(lazy.load, { plugins = { plug } })
        end
      end

      -- Repaint the dashboard/branding groups over whatever scheme is
      -- loaded. Prefer the palette theme-apply just wrote (so nvim, the bar
      -- and glow all agree); fall back to the scheme's own highlights if
      -- that file is missing or describes a different mode.
      local function overlay_accents()
        local p = sync.read_palette()
        if not (p and p.mode == last_mode) then
          p = sync.palette_from_hl()
        end
        sync.apply_accents(p)
      end

      -- ColorScheme fires for `:colorscheme x` from anywhere -- our own
      -- set_scheme, LazyVim's startup, or the user at the prompt -- so the
      -- accents follow all three. The palette paths do not go through
      -- `:colorscheme` and call apply_accents themselves.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("AtiThemeAccents", { clear = true }),
        callback = function()
          pcall(overlay_accents)
        end,
      })

      local function set_scheme(scheme)
        try_load_plugin(scheme)
        if pcall(vim.cmd, "colorscheme " .. scheme) then
          return true
        end
        -- Retry after next tick so a lazy load can finish plugin setup.
        vim.defer_fn(function()
          try_load_plugin(scheme)
          if not pcall(vim.cmd, "colorscheme " .. scheme) then
            -- Plugin genuinely unavailable. Render from the palette rather
            -- than collapsing to doom-one, which would make several modes
            -- look identical.
            local p = sync.read_palette()
            if p then
              sync.apply_palette(p)
            else
              try_load_plugin(sync.fallback)
              pcall(vim.cmd, "colorscheme " .. sync.fallback)
            end
          end
        end, 30)
        return false
      end

      local function apply(force)
        local m = sync.read_mode()
        if not m then
          return
        end
        local mt = wal_mtime()
        -- wal mode: reapply when colors-wal.vim mtime changes (wallpaper
        -- switch). Preset modes: reapply when the mode name changes.
        local changed = force or (m ~= last_mode) or (m == "wal" and mt ~= last_wal_mtime)
        if not changed then
          return
        end
        last_mode = m
        last_wal_mtime = mt

        if m == "wal" then
          -- dylanaraps/wal.vim only sets cterm* colours, which are invisible
          -- under termguicolors, so drive gui* from colors.json ourselves.
          local p = sync.read_wal_palette()
          if p then
            sync.apply_palette(p)
            return
          end
        end

        local scheme = sync.scheme_for(m)
        if scheme and scheme ~= "wal" then
          set_scheme(scheme)
          return
        end

        local p = sync.read_palette()
        if p then
          sync.apply_palette(p)
        else
          set_scheme(sync.fallback)
        end
      end

      apply(true)

      local function arm_fs(path, cb)
        local w = vim.uv.new_fs_event()
        if not w then
          return nil
        end
        local function start()
          w:start(
            path,
            {},
            vim.schedule_wrap(function()
              cb()
              vim.defer_fn(function()
                pcall(w.stop, w)
                start()
              end, 50)
            end)
          )
        end
        start()
        return w
      end

      -- theme_mode (preset switches) + colors-wal.vim (wallpaper switches)
      -- + current_palette.json (repaint of the mode we are already on).
      arm_fs(sync.mode_file, function()
        apply(false)
      end)
      arm_fs(sync.wal_cache, function()
        apply(false)
      end)
      arm_fs(sync.palette_json, function()
        apply(true)
      end)

      vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
        callback = function()
          apply(false)
        end,
      })
      vim.api.nvim_create_user_command("Theme", function()
        apply(true)
      end, { desc = "Reapply colorscheme from ~/.cache/qtile/theme_mode" })
    end,
  },
}
