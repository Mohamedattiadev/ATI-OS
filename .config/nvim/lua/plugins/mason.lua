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
