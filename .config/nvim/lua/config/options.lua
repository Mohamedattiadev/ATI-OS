-- ~/.config/nvim/lua/config/options.lua
--------------------------------------------------------------
-- PICKER
--------------------------------------------------------------
-- Pick ONE picker. Both fzf-lua (LazyVim's auto-selected default) and
-- telescope used to be installed: <leader>ff / <leader>fg went to telescope
-- while every other LazyVim picker key went to fzf-lua. This makes telescope
-- the single picker all of LazyVim's keymaps route to.
--
-- This MUST live in this file: LazyVim loads lazyvim/config/options.lua
-- (which hardcodes vim.g.lazyvim_picker = "auto") immediately before this
-- file, and reads the value afterwards when resolving default extras.
vim.g.lazyvim_picker = "telescope"

--------------------------------------------------------------
-- BASIC OPTIONS
--------------------------------------------------------------
-- Disable netrw completely
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-------------------------------------------------------------

local opt = vim.opt

-- Indentation
opt.expandtab = true
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2

-- UI
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

-- Wrapping
opt.wrap = false

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

-- Scrolling
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.smoothscroll = true

-- Folds
-- LazyVim already sets foldlevel=99 (everything open on file open). Kept
-- explicit here because a stray global foldlevel=0 is what used to make
-- code files open fully collapsed -- see the markdown FileType autocmd in
-- keymaps.lua, which must stay buffer-local (vim.opt_local).
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true

-- Performance
-- NOTE: 'lazyredraw' was removed here on purpose: it suppresses redraws
-- during async work and causes stale/ghost frames with image.nvim's kitty
-- backend. 'ttyfast' was removed too -- it is a no-op on Neovim.
opt.updatetime = 50
opt.timeoutlen = 300

-- Clipboard
opt.clipboard = "unnamedplus"

-- Swap
opt.swapfile = false

-- Conceal
opt.conceallevel = 0
opt.concealcursor = ""

-- Mouse
opt.mouse = "a"

--------------------------------------------------------------
-- DIAGNOSTICS
--------------------------------------------------------------
vim.diagnostic.config({
  float = { border = "rounded" },
})

--------------------------------------------------------------
-- TERMINAL (horizontal split)
--------------------------------------------------------------
local previous_terminal_height = 13

vim.keymap.set("n", "<leader>tt", function()
  vim.cmd("botright split term://" .. vim.o.shell)
  vim.cmd("resize " .. previous_terminal_height)

  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = true, silent = true })
end)

--------------------------------------------------------------
-- SPLITS
--------------------------------------------------------------
vim.keymap.set("n", "<leader><leader>v", "<cmd>vsplit<CR>")
vim.keymap.set("n", "<leader><leader>h", "<cmd>split<CR>")

--------------------------------------------------------------
-- MARKDOWN FIXES
--------------------------------------------------------------
vim.filetype.add({
  extension = {
    md = "markdown",
  },
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.md",
  callback = function()
    if vim.bo.filetype ~= "markdown" then
      vim.bo.filetype = "markdown"
    end
  end,
})

-- NOTE: a monkey patch of vim.treesitter.highlighter.on_line_impl used to
-- live here to swallow "end_col out of range" crashes. It was dead code on
-- Neovim 0.12 (on_line_impl no longer exists, so the guard never fired) and
-- would have hidden genuine errors if the name ever came back. Removed.
