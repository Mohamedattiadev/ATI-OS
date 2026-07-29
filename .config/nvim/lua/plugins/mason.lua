-- lua/plugins/mason.lua
return {
  {
    "mason-org/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup({
        ui = {
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      })
    end,
  },

  {
    "mason-org/mason-lspconfig.nvim",
    lazy = false,
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "pyright",
          "ts_ls",
          "html",
          "cssls",
          "bashls",
          "clangd",
          "jdtls",
        },
        automatic_installation = false, -- 🚨 IMPORTANT
        -- `automatic_installation` and `automatic_enable` are DIFFERENT
        -- options. automatic_enable defaults to true in mason-lspconfig v2
        -- and calls vim.lsp.enable() on every installed package -- that
        -- started a SECOND client for servers LazyVim already configures,
        -- and even enabled `stylua` (a formatter) as a language server.
        -- LazyVim starts the servers itself, so keep this off.
        automatic_enable = false,
      })
    end,
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = {
          "stylua",
          "prettier",
          "black",
          "isort",
          "shfmt",
        },
        auto_update = false,
      })
    end,
  },
}
