return {

  "stevearc/conform.nvim",
  dependencies = { "mason.nvim" },
  lazy = true,
  event = "VeryLazy",
  cmd = "ConformInfo",

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
