local root_files = {
  ".luarc.json",
  ".luarc.jsonc",
  ".luacheckrc",
  ".stylua.toml",
  "stylua.toml",
  "selene.toml",
  "selene.yml",
  ".git",
}

return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "j-hui/fidget.nvim",
    "stevearc/conform.nvim",

    -- Mason is handled elsewhere, but required as dependency
    "mason-org/mason.nvim",
    "mason-org/mason-lspconfig.nvim",
  },

  config = function()
    local lspconfig = require("lspconfig")

    --------------------------------------------------------------------
    -- CAPABILITIES (Blink-compatible)
    --------------------------------------------------------------------
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local ok, blink = pcall(require, "blink.cmp")
    if ok then
      capabilities = blink.get_lsp_capabilities(capabilities)
    end

    --------------------------------------------------------------------
    -- UI + FORMAT
    --------------------------------------------------------------------
    require("fidget").setup({})
    require("conform").setup({ formatters_by_ft = {} })

    --------------------------------------------------------------------
    -- LSP SERVERS YOU ACTUALLY WANT
    -- (Mason handles installation; we only configure them)
    --------------------------------------------------------------------
    local servers = {
      "lua_ls",
      "pyright",
      "ts_ls",
      "html",
      "cssls",
      "bashls",
    }

    --------------------------------------------------------------------
    -- GENERIC CONFIG FOR ALL SERVERS
    --------------------------------------------------------------------
    for _, server in ipairs(servers) do
      lspconfig[server].setup({
        capabilities = capabilities,
      })
    end

    --------------------------------------------------------------------
    -- SPECIAL CASE: LUA (Prime-style)
    --------------------------------------------------------------------
    lspconfig.lua_ls.setup({
      capabilities = capabilities,
      root_dir = lspconfig.util.root_pattern(unpack(root_files)),
      settings = {
        Lua = {
          diagnostics = { globals = { "vim" } },
          format = {
            enable = true,
            defaultConfig = {
              indent_style = "space",
              indent_size = "2",
            },
          },
        },
      },
    })

    --------------------------------------------------------------------
    -- SPECIAL CASE: Tailwind
    --------------------------------------------------------------------
    if lspconfig.tailwindcss then
      lspconfig.tailwindcss.setup({
        capabilities = capabilities,
        filetypes = {
          "html",
          "css",
          "scss",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "vue",
        },
      })
    end

    --------------------------------------------------------------------
    -- PRIMEAGEN DIAGNOSTIC STYLE
    --------------------------------------------------------------------
    vim.diagnostic.config({
      float = {
        focusable = false,
        style = "minimal",
        border = "rounded",
        source = "always",
        header = "",
        prefix = "",
      },
    })
  end,
}
