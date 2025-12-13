-------------------------------------------------------------------------------
---

                           Folding section

---

---

-- Ensure markdown filetype detection for specific files
vim.api.nvim*create_autocmd({ "BufRead", "BufNewFile", "BufEnter" }, {
pattern = { "*.md", "\_.markdown", "sum.md", "TODO*", "*todo\*" },
callback = function()
if vim.bo.filetype ~= "markdown" then
vim.bo.filetype = "markdown"
vim.schedule(function()
set_markdown_folding()
end)
end
end,
})

-- Fold expression for markdown headers
function \_G.markdown_foldexpr()
local lnum = vim.v.lnum
local line = vim.fn.getline(lnum)

-- Match headers with space after # characters
local heading = line:match("^(#+)%s+")
if heading then
return ">" .. #heading
end

-- If not a header, inherit fold level from previous line
return "="
end

function \_G.markdown_foldtext()
local line = vim.fn.getline(vim.v.foldstart)
local fold_size = (vim.v.foldend - vim.v.foldstart)
return line .. "  " .. fold_size .. " lines"
end

function \_G.set_markdown_folding()
vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.markdown_foldexpr()"
vim.opt_local.foldtext = "v:lua.markdown_foldtext()"
vim.opt_local.foldlevel = 0 -- Start with all folds closed
vim.opt_local.foldnestmax = 6 -- Allow up to H6 nesting
vim.opt_local.fillchars = "fold: "
vim.opt_local.foldminlines = 1
end

-- Apply only to markdown files
vim.api.nvim_create_autocmd("FileType", {
pattern = "markdown",
callback = set_markdown_folding,
})

-- Debug function to check filetype and folding
vim.keymap.set("n", "<leader>df", function()
print("Filetype:", vim.bo.filetype)
print("File name:", vim.fn.expand("%:p"))
print("Fold method:", vim.bo.foldmethod)
print("Fold expr:", vim.bo.foldexpr)
print("Buffer number:", vim.fn.bufnr())
end, { desc = "Debug folding" })

---

## -- Functions for folding

local function get_heading_level(line_content)
if not line_content then
return 0
end
local heading = line_content:match("^(#+)%s+")
return heading and #heading or 0
end

local function find_fold_range(start_line, level)
local total_lines = vim.fn.line("$")
local end_line = total_lines

for line = start_line + 1, total_lines do
local content = vim.fn.getline(line)
local next_level = get_heading_level(content)

    -- If we find a heading of same or higher level, this is the end of the fold
    if next_level > 0 and next_level <= level then
      end_line = line - 1
      break
    end

end

return end_line
end

local function safe_fold_operation(line, operation)
pcall(function()
vim.fn.setpos(".", { 0, line, 1, 0 })
if operation == "close" then
vim.cmd("normal! zc")
elseif operation == "open" then
vim.cmd("normal! zo")
end
end)
end

local function toggle_fold_at_line(line)
pcall(function()
vim.fn.setpos(".", { 0, line, 1, 0 })
if vim.fn.foldclosed(line) == -1 then
vim.cmd("normal! zc")
else
vim.cmd("normal! zo")
end
end)
end

local function toggle_headings_of_level(level)
local total_lines = vim.fn.line("$")
local saved_view = vim.fn.winsaveview()

-- Check current state: if any heading of this level is closed, we should open all
local should_open = false
for line = 1, total_lines do
local content = vim.fn.getline(line)
if get_heading_level(content) == level and vim.fn.foldclosed(line) ~= -1 then
should_open = true
break
end
end

for line = 1, total_lines do
local content = vim.fn.getline(line)
if get_heading_level(content) == level then
if should_open then
safe_fold_operation(line, "open")
else
safe_fold_operation(line, "close")
end
end
end

vim.fn.winrestview(saved_view)
return should_open
end

local function fold_headings_of_level(target_level)
local total_lines = vim.fn.line("$")
local saved_view = vim.fn.winsaveview()

for line = 1, total_lines do
local content = vim.fn.getline(line)
if get_heading_level(content) == target_level then
safe_fold_operation(line, "close")
end
end

vim.fn.winrestview(saved_view)
end

local function fold_markdown_headings(levels)
-- First unfold everything to start fresh
vim.cmd("normal! zR")

-- Give time for folds to initialize
vim.defer_fn(function()
-- Fold levels from highest to lowest (H6 → H1)
for i = #levels, 1, -1 do
local level = levels[i]
fold_headings_of_level(level)
end
vim.cmd("normal! zz")
end, 50)
end

-- Track fold states
local fold_states = {}
for i = 1, 6 do
fold_states[i] = false
end

---

## -- Keymaps (Robust version)

-- Fold all headings level 1 or above (individual H1 sections)
vim.keymap.set("n", "zj", function()
if vim.bo.filetype == "markdown" then
pcall(function()
fold_markdown_headings({ 1, 2, 3, 4, 5, 6 })
end)
end
end, { desc = "Fold all headings level 1 or above" })

-- Fold all headings level 2 or above
vim.keymap.set("n", "zk", function()
if vim.bo.filetype == "markdown" then
pcall(function()
fold_markdown_headings({ 2, 3, 4, 5, 6 })
end)
end
end, { desc = "Fold all headings level 2 or above" })

-- Fold all headings level 3 or above
vim.keymap.set("n", "zl", function()
if vim.bo.filetype == "markdown" then
pcall(function()
fold_markdown_headings({ 3, 4, 5, 6 })
end)
end
end, { desc = "Fold all headings level 3 or above" })

-- Fold all headings level 4 or above
vim.keymap.set("n", "z;", function()
if vim.bo.filetype == "markdown" then
pcall(function()
fold_markdown_headings({ 4, 5, 6 })
end)
end
end, { desc = "Fold all headings level 4 or above" })

-- Toggle specific heading levels with leader + number
for i = 1, 6 do
vim.keymap.set("n", "<leader>" .. i, function()
if vim.bo.filetype == "markdown" then
pcall(function()
local should_open = toggle_headings_of_level(i)
fold_states[i] = should_open
end)
end
end, { desc = "Toggle H" .. i .. " headings" })
end

-- Toggle all headers
vim.keymap.set("n", "<leader>0", function()
if vim.bo.filetype ~= "markdown" then
return
end

pcall(function()
-- Check if all are closed (if any is open, we should close all)
local should_close = false
for i = 1, 6 do
if not fold_states[i] then
should_close = true
break
end
end

    if should_close then
      -- Close all levels
      for i = 1, 6 do
        toggle_headings_of_level(i)
        fold_states[i] = true
      end
    else
      -- Open all levels
      vim.cmd("normal! zR")
      for i = 1, 6 do
        fold_states[i] = false
      end
    end

end)
end, { desc = "Toggle all headers" })

-- Toggle fold under cursor
vim.keymap.set("n", "<CR>", function()
pcall(function()
local line = vim.fn.line(".")
toggle_fold_at_line(line)
end)
end, { desc = "Toggle fold" })

-- Unfold all headings
vim.keymap.set("n", "zu", function()
pcall(function()
vim.cmd("normal! zR")
for i = 1, 6 do
fold_states[i] = false
end
end)
end, { desc = "Unfold all headings" })

-- Fold current heading
vim.keymap.set("n", "zi", function()
pcall(function()
local line = vim.fn.line(".")
local content = vim.fn.getline(line)

    if content and content:match("^#+%s+") then
      toggle_fold_at_line(line)
    else
      -- Find nearest heading above
      for l = line, 1, -1 do
        local above_content = vim.fn.getline(l)
        if above_content and above_content:match("^#+%s+") then
          toggle_fold_at_line(l)
          break
        end
      end
    end

end)
end, { desc = "Fold/unfold current heading" })

---

## -- End Folding section
