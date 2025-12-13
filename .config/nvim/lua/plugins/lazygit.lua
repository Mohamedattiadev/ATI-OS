return {
  "kdheepak/lazygit.nvim",
  event = "VeryLazy", -- Load it lazily
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = {
    "LazyGit",
    "LazyGitConfig",
    "LazyGitCurrentFile",
    "LazyGitFilter",
    "LazyGitFilterCurrentFile",
  },
  keys = {
    { "<leader>gg", "<cmd>LazyGit<cr>", desc = "Open LazyGit" },
  },
}
