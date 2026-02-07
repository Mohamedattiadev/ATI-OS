return {

  "nvim-lualine/lualine.nvim",
  enabled = function()
    return not vim.g.started_by_firenvim
  end,
}
