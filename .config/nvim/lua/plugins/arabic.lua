return {
  -- Toggle keybinding: <leader>ar
  vim.keymap.set("n", "<leader>ar", function()
    vim.opt.rightleft = not vim.opt.rightleft:get()
    vim.opt.arabic = not vim.opt.arabic:get()
  end, { desc = "Toggle Arabic Mode" }),
  -- end,
  -- },
}
