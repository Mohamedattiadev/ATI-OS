-- ~/.config/nvim/lua/config/options.lua
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

-- Performance
opt.lazyredraw = true
opt.ttyfast = true
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

-- HACK: Monkey patch the internal Treesitter highlighter to catch the crash
-- Place this at the VERY TOP of your init.lua or config/options.lua

local ok, TSHighlighter = pcall(require, "vim.treesitter.highlighter")
if ok and TSHighlighter.on_line_impl then
  local original_on_line_impl = TSHighlighter.on_line_impl

  TSHighlighter.on_line_impl = function(self, ...)
    -- Try to run the original function
    local status, err = pcall(original_on_line_impl, self, ...)

    -- If it crashes...
    if not status then
      -- Check if it's the specific "end_col" or "out of range" error
      if err and (err:match("end_col") or err:match("out of range")) then
        -- SILENCE: Do nothing. Pretend it worked.
        return
      end
      -- If it's a different error, let it crash so you know.
      error(err)
    end
  end
end
