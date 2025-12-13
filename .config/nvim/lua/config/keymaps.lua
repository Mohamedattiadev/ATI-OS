-- Keymaps are automatically loaded on the VeryLazy event
-- Add any additional keymaps here

-------------------------------------------------------------------------------
-- UTIL: Safe delete for LazyVim default mappings
-------------------------------------------------------------------------------
local function safe_del(modes, key)
  if type(modes) == "table" then
    for _, mode in ipairs(modes) do
      if vim.fn.maparg(key, mode) ~= "" then
        vim.keymap.del(mode, key)
      end
    end
  else
    if vim.fn.maparg(key, modes) ~= "" then
      vim.keymap.del(modes, key)
    end
  end
end

-------------------------------------------------------------------------------
-- DELETE UNUSED DEFAULT KEYMAPS
-------------------------------------------------------------------------------
safe_del("n", "gx")
safe_del("n", "<leader>w")
safe_del("n", "<leader>-")
safe_del("n", "<leader>|")
safe_del("n", "<leader>wd")
safe_del("n", "<leader>wm")
safe_del("n", "<leader>bb")
safe_del("n", "<S-h>")
safe_del("n", "<S-l>")
safe_del("n", "<leader>/")
safe_del("v", "t")
safe_del("n", "t")
safe_del({ "i", "x", "n", "s" }, "<C-s>")

-------------------------------------------------------------------------------
-- FOLD HIGHLIGHT COLORS
-------------------------------------------------------------------------------
vim.api.nvim_set_hl(0, "FoldLine", { fg = "#c8caca", bg = "#1e222a" })
vim.api.nvim_set_hl(0, "FoldInfo", { fg = "#c678dd", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH1", { fg = "#bd9cf9", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH2", { fg = "#51afef", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH3", { fg = "#ffb86c", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH4", { fg = "#c678dd", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH5", { fg = "#98be65", bold = true })
vim.api.nvim_set_hl(0, "FoldHeaderH6", { fg = "#51afef", bold = true })

-------------------------------------------------------------------------------
-- SAVE / QUIT
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>w", "<cmd>w<CR>")
vim.keymap.set("n", "<leader>q", "<cmd>q<CR>")
vim.keymap.set("n", "<leader><leader>q", "<cmd>wqa<CR>")
vim.keymap.set("n", "<leader>`", "<cmd>e #<CR>") -- switch to last buffer

-------------------------------------------------------------------------------
-- PASTE BEHAVIOR
-------------------------------------------------------------------------------
vim.keymap.set("n", "p", '"+p')
vim.keymap.set("v", "p", '"_dP')
vim.keymap.set("n", "P", "p")
vim.keymap.set("v", "P", "p")

vim.keymap.set("n", "<C-v>", '"+P')
vim.keymap.set("n", "<C-S-v>", '"+p')
vim.keymap.set("i", "<C-v>", "<C-R>+")
vim.keymap.set("v", "<C-v>", '"+P')

-------------------------------------------------------------------------------
-- SCROLLING
-------------------------------------------------------------------------------
vim.keymap.set("n", "<C-e>", "10<C-e>")
vim.keymap.set("n", "<C-y>", "10<C-y>")

-------------------------------------------------------------------------------
-- MOVEMENT BOOST (5 steps per tap)
-------------------------------------------------------------------------------
vim.keymap.set("n", "<tab>h", "5h")
vim.keymap.set("n", "<tab>j", "5j")
vim.keymap.set("n", "<tab>k", "5k")
vim.keymap.set("n", "<tab>l", "5l")
vim.keymap.set("v", "<tab>h", "5h")
vim.keymap.set("v", "<tab>j", "5j")
vim.keymap.set("v", "<tab>k", "5k")
vim.keymap.set("v", "<tab>l", "5l")

-------------------------------------------------------------------------------
-- TAB NAVIGATION
-------------------------------------------------------------------------------
vim.keymap.set("n", "L", "gt", { desc = "Next tab" })
vim.keymap.set("n", "H", "gT", { desc = "Prev tab" })

-------------------------------------------------------------------------------
-- BUFFER
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>bd", ":bd<CR>")

-------------------------------------------------------------------------------
-- RUN CODE
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>r", ":RunCode<CR>")

-------------------------------------------------------------------------------
-- OPEN MARKDOWN LINKS
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>of", function()
  local line = vim.api.nvim_get_current_line()
  local link = line:match("%((.-)%)")
  if link then
    local current_dir = vim.fn.expand("%:p:h")
    local full_path = vim.fn.resolve(current_dir .. "/" .. link)
    vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
    vim.cmd("edit " .. full_path)
  else
    print("No Markdown link on this line")
  end
end)

-------------------------------------------------------------------------------
-- MARKDOWN FOLDING SYSTEM (your advanced folding preserved cleanly)
-------------------------------------------------------------------------------
function _G.markdown_foldexpr()
  local line = vim.fn.getline(vim.v.lnum)
  local heading = line:match("^(#+)%s+")
  return heading and (">" .. #heading) or "="
end

function _G.markdown_foldtext()
  local line = vim.fn.getline(vim.v.foldstart)
  local size = vim.v.foldend - vim.v.foldstart
  local hashes = line:match("^(#+)")
  local level = hashes and #hashes or 0
  local padding = string.rep(" ", level + 2)
  local header_hl = "FoldHeaderH" .. (level ~= 0 and level or 1)
  return {
    { padding .. hashes, header_hl },
    { " " .. line:gsub("^#+%s*", ""), "FoldLine" },
    { "  " .. size .. " lines", "FoldInfo" },
  }
end

function _G.set_markdown_folding()
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldexpr = "v:lua.markdown_foldexpr()"
  vim.opt_local.foldtext = "v:lua.markdown_foldtext()"
  vim.opt_local.foldlevel = 0
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    _G.set_markdown_folding()
  end,
})

-------------------------------------------------------------------------------
-- FOLD CONTROL KEYMAPS
-------------------------------------------------------------------------------
local fold_states = { false, false, false, false, false, false }

local function get_heading_level(line)
  local h = line:match("^(#+)%s+")
  return h and #h or 0
end

local function safe_fold(line, action)
  pcall(function()
    vim.fn.setpos(".", { 0, line, 1, 0 })
    vim.cmd(action == "open" and "normal! zo" or "normal! zc")
  end)
end

local function toggle_level(level)
  local lines = vim.fn.line("$")
  local open_any = false

  for i = 1, lines do
    if get_heading_level(vim.fn.getline(i)) == level and vim.fn.foldclosed(i) ~= -1 then
      open_any = true
      break
    end
  end

  for i = 1, lines do
    if get_heading_level(vim.fn.getline(i)) == level then
      safe_fold(i, open_any and "open" or "close")
    end
  end

  fold_states[level] = open_any
end

for i = 1, 6 do
  vim.keymap.set("n", "<leader>" .. i, function()
    if vim.bo.filetype == "markdown" then
      toggle_level(i)
    end
  end, { desc = "Toggle H" .. i })
end

vim.keymap.set("n", "<leader>0", function()
  if vim.bo.filetype ~= "markdown" then
    return
  end
  local close_all = false
  for _, v in ipairs(fold_states) do
    if not v then
      close_all = true
      break
    end
  end
  for i = 1, 6 do
    toggle_level(i)
  end
end)

vim.keymap.set("n", "zu", function()
  vim.cmd("normal! zR")
end)

vim.keymap.set("n", "<CR>", function()
  local l = vim.fn.line(".")
  if vim.fn.foldclosed(l) == -1 then
    vim.cmd("normal! zc")
  else
    vim.cmd("normal! zo")
  end
end)
