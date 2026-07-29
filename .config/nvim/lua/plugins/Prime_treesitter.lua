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

      -- Highlighting settings.
      --
      -- nvim-treesitter is on the `main` branch, where LazyVim only honours
      -- `disable` as a LIST of languages (see lazyvim.TSFeat). The previous
      -- `disable = function(lang, buf)` form was silently ignored, so the
      -- HTML rule and the >100KB guard were never actually in effect.
      -- `ignore_install` and `additional_vim_regex_highlighting` are not part
      -- of the main-branch API either, so they were dropped.
      highlight = {
        enable = true,
        disable = { "html" },
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
