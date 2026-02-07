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
-- safe_del("n", "<leader>bb")
safe_del("n", "<S-h>")
safe_del("n", "<S-l>")
safe_del("n", "<leader>/")
safe_del("v", "t")
safe_del("n", "t")
safe_del("n", "<leader>ft")
safe_del("n", "<leader>fT")
safe_del({ "i", "x", "n", "s" }, "<C-s>")
safe_del("n", "<leader>fg")

----------
---after delete
----------

-- Project-wide TODOs
vim.keymap.set("n", "<leader>fT", "<cmd>TodoTelescope<cr>", { desc = "TODOs in project" })
-- Current file TODOs
vim.keymap.set("n", "<leader>ft", "<cmd>TodoTelescope cwd=false<cr>", { desc = "TODOs in current file" })
-- Fuzzy find recent buffers
vim.keymap.set(
  "n",
  "<leader>bb",
  ":Telescope buffers<cr>",
  { noremap = true, silent = true, desc = "Fuzzy find recent buffers" }
)
--  live grep
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
-------------------------------------------------------------------------------
-- SAVE / QUIT
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>w", "<cmd>w<CR>")
vim.keymap.set("n", "<leader>q", "<cmd>q<CR>")
vim.keymap.set("n", "<leader><leader>q", "<cmd>wqa<CR>")
vim.keymap.set("n", "<leader>`", "<cmd>e #<CR>") -- switch to last buffer

-- clear search
vim.keymap.set("n", "<leader><leader>n", "<cmd>:nohlsearch <CR>")

------------------------------------
--- for arabic layout
------------------------------------
-- vim.keymap.set("n", "ه", "i", { noremap = true, silent = true })
-- vim.keymap.set("n", "ه", "i", { noremap = true, silent = true })
-- vim.keymap.set("n", "يي", "dd", { noremap = true, silent = true })
-- vim.keymap.set("n", "ؤهص", "ciw", { noremap = true, silent = true })
-- vim.keymap.set("n", "ؤهلا", "cib", { noremap = true, silent = true })
-- vim.keymap.set("n", "غغ", "yy", { noremap = true, silent = true })
-- vim.keymap.set("n", "ح", "p", { noremap = true, silent = true })
-- vim.keymap.set("n", "ء", "x", { noremap = true, silent = true })
-- vim.keymap.set("n", "ا", "h", { noremap = true, silent = true })
-- vim.keymap.set("n", "ت", "j", { noremap = true, silent = true })
-- vim.keymap.set("n", "ن", "k", { noremap = true, silent = true })
-- vim.keymap.set("n", "م", "l", { noremap = true, silent = true })
-- vim.keymap.set("n", "ع", "u", { noremap = true, silent = true })
-- vim.keymap.set("n", "ق", "r", { noremap = true, silent = true })
-- vim.keymap.set("n", "ص", "w", { noremap = true, silent = true })
-- -- vim.keymap.set("n" "لا", "b", { noremap = true, silent = true })
--
-- vim.keymap.set("v", "ا", "h", { noremap = true, silent = true })
-- vim.keymap.set("v", "ت", "j", { noremap = true, silent = true })
-- vim.keymap.set("v", "ن", "k", { noremap = true, silent = true })
-- vim.keymap.set("v", "م", "l", { noremap = true, silent = true })
--
-- vim.keymap.set("n", "<C-ق>", "<C-r>", { noremap = true, silent = true })
-- vim.keymap.set("n", "ر", "v", { noremap = true, silent = true })
-- vim.keymap.set("n", "غ", "y", { noremap = true, silent = true })
-- vim.keymap.set("n", "ش", "a", { noremap = true, silent = true })
--

-- vim.keymap.set("n", "<leader>ص", "<cmd>w<CR>")
-- vim.keymap.set("n", "<leader>ض", "<cmd>q<CR>")
--
-- vim.keymap.set("n", "<tab>ا", "5h")
-- vim.keymap.set("n", "<tab>ت", "5j")
-- vim.keymap.set("n", "<tab>ن", "5k")
-- vim.keymap.set("n", "<tab>م", "5l")
-- vim.keymap.set("v", "<tab>ا", "5h")
-- vim.keymap.set("v", "<tab>ت", "5j")
-- vim.keymap.set("v", "<tab>ن", "5k")
-- vim.keymap.set("v", "<tab>م", "5l")
--

-- c+o  , c+i,gcc,gg,G ...

-- vim.keymap.set("v", "<S-ت>", ":m '>+1<CR>gv=gv", { noremap = true, silent = true })
-- vim.keymap.set("v", "<S-ن>", ":m '<-2<CR>gv=gv", { noremap = true, silent = true })

-- vim.keymap.set("n", "<S-م>", "gt", { desc = "Next tab" })
-- vim.keymap.set("n", "<S-ا>", "gT", { desc = "Prev tab" })

------------------------------------
---  create new buffer
-----------------------------------
vim.keymap.set("n", "<leader>bn", function()
  vim.cmd("tabnew")

  local buf = vim.api.nvim_buf_get_name(0)
  if vim.fn.filereadable(buf) == 1 then
    require("mini.files").open(buf, true)
  else
    require("mini.files").open(vim.uv.cwd(), true)
  end
end, { desc = "New tab + mini.files (smart)" })
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
-- vim.keymap.set("n", "<C-e>", "10<C-e>")
-- vim.keymap.set("n", "<C-y>", "10<C-y>")

--------------------------------------------------------------------------------
--- move selected text/block of in visual mode
--------------------------------------------------------------------------------

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { noremap = true, silent = true })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { noremap = true, silent = true })

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
--  clear messages
-------------------------------------------------------------------------------
vim.keymap.set("n", "<Esc>", function()
  vim.cmd("nohlsearch")
  vim.cmd("echo ''")
end, { desc = "Clear highlights and messages" })

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
  local heading = line:match("^%s*(#+)%s+")
  return heading and (">" .. #heading) or "="
end

-- function _G.markdown_foldtext()
--   local line = vim.fn.getline(vim.v.foldstart)
--   local size = vim.v.foldend - vim.v.foldstart
--   local hashes = line:match("^(#+)")
--   local level = hashes and #hashes or 0
--   local padding = string.rep(" ", level + 2)
--   local header_hl = "FoldHeaderH" .. (level ~= 0 and level or 1)
--   return {
--     { padding .. hashes, header_hl },
--     { " " .. line:gsub("^#+%s*", ""), "FoldLine" },
--     { "  " .. size .. " lines", "FoldInfo" },
--   }
-- end

-------------------------------------------------------------------------------
-- MARKDOWN FOLDING (SIMPLE & RELIABLE)
-------------------------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt.foldmethod = "expr"
    vim.opt.foldexpr = "v:lua.markdown_foldexpr()"
    -- vim.opt.foldtext = "v:lua.markdown_foldtext()"
    vim.opt.foldlevel = 0
    vim.opt.foldenable = true
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

  -- Not inside any fold at all
  if vim.fn.foldlevel(l) == 0 then
    return
  end

  -- If on a closed fold start → open it
  if vim.fn.foldclosed(l) ~= -1 then
    vim.cmd("normal! zo")
    return
  end

  -- Otherwise close the nearest parent fold
  vim.cmd("normal! zc")
end, { desc = "Toggle nearest fold" })

-- require("config.image_toggle")
