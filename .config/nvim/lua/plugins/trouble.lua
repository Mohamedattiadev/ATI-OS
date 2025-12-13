return {
  "folke/trouble.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>" },
    { "<leader>cs", "<cmd>Trouble lsp toggle<cr>", },
    { "<leader>cS", enabled = false,},
    { "<leader>xq", "<cmd>Trouble qflist <cr>" },
    { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>"},
  },
}
