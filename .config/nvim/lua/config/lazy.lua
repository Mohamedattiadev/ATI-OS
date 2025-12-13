--------------------------------------------------------------
-- BOOTSTRAP LAZY.NVIM
--------------------------------------------------------------

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Install lazy.nvim if missing
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    repo,
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end

vim.opt.rtp:prepend(lazypath)

--------------------------------------------------------------
-- SETUP LAZY
--------------------------------------------------------------
require("lazy").setup({

  ------------------------------------------------------------
  -- PLUGIN SOURCES
  ------------------------------------------------------------
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" }, -- LazyVim base
    { import = "plugins" }, -- your custom plugins
  },

  ------------------------------------------------------------
  -- DEFAULTS
  ------------------------------------------------------------
  defaults = {
    lazy = false, -- your own plugins load on startup (faster feel)
    version = false, -- always use the latest commit
  },

  ------------------------------------------------------------
  -- INSTALL SETTINGS
  ------------------------------------------------------------
  install = {
    colorscheme = { "doom-one" }, -- your preferred scheme
  },

  ------------------------------------------------------------
  -- OPTIONAL: UPDATE CHECKER
  ------------------------------------------------------------
  checker = {
    enabled = false,
    notify = false,
  },

  ------------------------------------------------------------
  -- PERFORMANCE TWEAKS
  ------------------------------------------------------------
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
        -- You *can* disable matchit/matchparen/netrw if you want:
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
      },
    },
  },
})
