return {

  "stevearc/conform.nvim",
  dependencies = { "mason.nvim" },
  lazy = true,
  event = "VeryLazy",
  cmd = "ConformInfo",

  opts = {
    -- IMPORTANT: always try LSP if no formatter
    format_on_save = false,

    formatters_by_ft = {
      python = { "ruff_format", "black" }, -- try ruff first, then black
      lua = { "stylua" },
      sh = { "shfmt" },
      json = { "prettier" },
      yaml = { "prettier" },
      html = { "prettier" },
      css = { "prettier" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      markdown = { "prettier" },
      toml = { "taplo" },
    },
  },

  keys = {

    --   those two  are the defual
    { "<leader>cf", enabled = false },
    -- wanna disable them
    { "<leader>cF", enabled = false },
    --   those two  are the defual

    {

      "<leader>gF",

      function()
        require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
      end,

      mode = { "n", "v" },
    },

    {

      "<leader>gf",

      function()
        require("conform").format()
      end,
      mode = { "n", "v" },
    },
  },
}
