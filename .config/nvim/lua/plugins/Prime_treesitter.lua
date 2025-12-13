return {
  -- 1. Main Treesitter Config
  {
    "nvim-treesitter/nvim-treesitter",
    -- We use 'opts' to configure it. LazyVim calls setup() automatically using these options.
    opts = {
      -- Your Language List
      ensure_installed = {
        "lua",
        "python",
        "javascript",
        "typescript",
        "bash",
        "c",
        "json",
        "yaml",
        "markdown",
        "vim",
        "vimdoc",
        "html",
        "css",
        "toml",
        "query",
      },

      ignore_install = { "markdown_inline" },

      -- Highlighting Settings (Primeagen Style)
      highlight = {
        enable = true,
        -- Use standard Vim regex for Markdown (fixes bugs)
        additional_vim_regex_highlighting = { "markdown" },

        -- Custom Disable Logic
        disable = function(lang, buf)
          -- 1. Disable HTML (Your preference)
          if lang == "html" then
            return true
          end

          -- 2. Disable for Large Files (>100KB)
          local max_filesize = 100 * 1024 -- 100 KB
          local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
          if ok and stats and stats.size > max_filesize then
            -- Optional: Silent return to avoid spamming notifications
            return true
          end
        end,
      },

      -- Indentation
      indent = { enable = true },
    },
  },

  -- 2. Treesitter Context (Configured correctly for LazyVim)
  {
    "nvim-treesitter/nvim-treesitter-context",
    opts = {
      enable = true,
      multiwindow = false,
      max_lines = 0,
      min_window_height = 0,
      line_numbers = true,
      multiline_threshold = 20,
      trim_scope = "outer",
      mode = "cursor",
      separator = nil,
      zindex = 20,
    },
  },
}
