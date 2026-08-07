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
-- gx is NOT deleted: it opens the URL under the cursor via vim.ui.open, which
-- is the one thing <leader>of cannot do (that handles []() links, not bare
-- URLs). Deleting it left no way to open a plain https://... from these notes.
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
-- Moved here from lua/plugins/arabic.lua, which returned
-- `{ vim.keymap.set(...) }` -- vim.keymap.set returns nil, so that "plugin
-- spec" was an empty table and the mapping was only a side effect of lazy
-- parsing the spec file. This is a keymap, so it belongs in keymaps.lua.
vim.keymap.set("n", "<leader>ar", function()
  vim.opt_local.rightleft = not vim.opt_local.rightleft:get()
  vim.opt_local.arabic = not vim.opt_local.arabic:get()
end, { desc = "Toggle Arabic Mode" })

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
-- NOTE: `p` is deliberately NOT remapped to '"+p'. clipboard=unnamedplus
-- (options.lua) already makes plain `p` paste the system clipboard, and the
-- remap silently discarded explicit registers -- `"ap` pasted the clipboard
-- instead of register a.
vim.keymap.set("v", "p", '"_dP')
-- Restored by request: P pastes BELOW, same as p. Note this means there is no
-- normal-mode key left for paste-above -- use `]p` / `[p` (indent-aware paste
-- after/before) if you ever need to paste on the line above.
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
-- Kept by request. Known trade-off: in a terminal <Tab> and <C-i> are the same
-- byte, so using <Tab> as a mapping prefix means <C-i> (jump forward) waits out
-- 'timeoutlen' -- 300ms -- before firing, while <C-o> stays instant.
vim.keymap.set("n", "<tab>h", "5h")
vim.keymap.set("n", "<tab>j", "5j")
vim.keymap.set("n", "<tab>k", "5k")
vim.keymap.set("n", "<tab>l", "5l")
vim.keymap.set("v", "<tab>h", "5h")
vim.keymap.set("v", "<tab>j", "5j")
vim.keymap.set("v", "<tab>k", "5k")
vim.keymap.set("v", "<tab>l", "5l")

-------------------------------------------------------------------------------
-- TAB / BUFFER NAVIGATION
-------------------------------------------------------------------------------
-- H and L move between the things you have open. Which command that means
-- depends on the session, and hardwiring one of them is why these used to
-- look broken:
--
-- `gt`/`gT` only cycle tab *pages*. <leader>bn makes real tab pages, but a
-- file opened from Telescope, mini.files or `:e` becomes a *buffer* inside
-- the current tab page. In the normal single-tab-page session there was
-- therefore nothing for gt to cycle to, and H/L did nothing at all -- while
-- still shadowing built-in H/L (top/bottom of screen).
--
-- bufferline is disabled (plugins/disabled.lua), so neither buffers nor tabs
-- have a visible bar; the rule is just "cycle tab pages if there are several,
-- otherwise cycle buffers". pcall because :bnext raises E85 when no listed
-- buffer exists (an empty session, or only a terminal open).
local function cycle_open(tab_cmd, buf_cmd)
  return function()
    local cmd = #vim.api.nvim_list_tabpages() > 1 and tab_cmd or buf_cmd
    pcall(vim.cmd, cmd)
  end
end

vim.keymap.set("n", "L", cycle_open("tabnext", "bnext"), { desc = "Next tab / buffer" })
vim.keymap.set("n", "H", cycle_open("tabprevious", "bprevious"), { desc = "Prev tab / buffer" })

-------------------------------------------------------------------------------
-- BUFFER
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>bd", ":bd<CR>")

-------------------------------------------------------------------------------
-- RUN CODE
-------------------------------------------------------------------------------
-- Removed: <leader>r was mapped to :RunCode, but code_runner.nvim lives in
-- lua/notUsed/ and is never loaded, so the command does not exist. Restore
-- the plugin spec first if you want this key back.

-------------------------------------------------------------------------------
--  clear messages
-------------------------------------------------------------------------------
vim.keymap.set("n", "<Esc>", function()
  vim.cmd("nohlsearch")
  vim.cmd("echo ''")
end, { desc = "Clear highlights and messages" })

-------------------------------------------------------------------------------
-- MARKDOWN FILETYPES
-------------------------------------------------------------------------------
-- Kept in sync with render-markdown's file_types (plugins/render_markdown.lua).
-- rmd and quarto share the markdown treesitter grammar. The folding autocmd
-- below used to fire on "markdown" alone, so .rmd/.qmd files rendered their
-- headings but had no fold structure at all, and the <leader>1..6 keys were
-- dead in them.
local MARKDOWN_FILETYPES = { "markdown", "rmd", "quarto" }

local function is_markdown()
  return vim.tbl_contains(MARKDOWN_FILETYPES, vim.bo.filetype)
end

-------------------------------------------------------------------------------
-- OPEN MARKDOWN LINKS
-------------------------------------------------------------------------------
-- Returns the destination of the []() link under the cursor, else the first
-- one on the line. The old version used `line:match("%((.-)%)")`, which takes
-- the first parenthesised text anywhere on the line -- so on a line like
-- "grep (case insensitive) notes" it happily treated "case insensitive" as a
-- link target.
local function markdown_link_at(line, col)
  local first, init = nil, 1
  while true do
    local s, e, dest = line:find("%[[^%]]*%]%(([^)]+)%)", init)
    if not s then
      return first
    end
    first = first or dest
    if col >= s and col <= e then
      return dest
    end
    init = e + 1
  end
end

-- <leader>gx: open the URL the cursor is sitting anywhere inside.
--
-- Built-in gx works off <cfile>, which stops at punctuation and mis-handles a
-- URL wrapped in markdown parens. This scans the line for whole URLs and picks
-- the one whose span contains the cursor, so any letter of it works -- and
-- falls back to the first URL on the line when the cursor is elsewhere.
local function url_at(line, col)
  local first, init = nil, 1
  while true do
    -- Stop at whitespace and at the delimiters that wrap links in markdown,
    -- so `[x](https://a.b)` and `<https://a.b>` yield a clean URL.
    local s, e, url = line:find("(%a[%w+.-]*://[^%s%)%]>\"'`]+)", init)
    if not s then
      return first
    end
    first = first or url
    if col >= s and col <= e then
      return url
    end
    init = e + 1
  end
end

vim.keymap.set("n", "<leader>gx", function()
  local url = url_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2] + 1)
  if not url then
    vim.notify("No URL on this line", vim.log.levels.WARN)
    return
  end
  vim.ui.open(url)
end, { desc = "Open URL under cursor" })

vim.keymap.set("n", "<leader>of", function()
  local dest = markdown_link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2] + 1)
  if not dest then
    vim.notify("No markdown link on this line", vim.log.levels.WARN)
    return
  end

  -- Drop an optional link title (`[x](path "Title")`) and any #anchor.
  dest = dest:gsub('%s+".*$', ""):gsub("#.*$", "")
  if dest == "" then
    return -- a bare #anchor, nothing to open
  end

  -- URLs go to the browser. Previously they fell through to the file branch,
  -- where mkdir() ran unconditionally -- so pressing this on an http link
  -- created a real directory tree named after the URL next to the current
  -- file. That is why stray "https:" folders appeared.
  if dest:match("^%a[%w+.-]*://") or dest:match("^mailto:") then
    vim.ui.open(dest)
    return
  end

  local path = vim.fn.fnamemodify(vim.fn.expand("%:p:h") .. "/" .. dest, ":p")
  if vim.fn.filereadable(path) == 0 then
    local parent = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
      if vim.fn.confirm("Create directory " .. parent .. "?", "&Yes\n&No", 2) ~= 1 then
        return
      end
      vim.fn.mkdir(parent, "p")
    end
  end
  -- fnameescape, because the unescaped `:edit ` .. path` broke on any link
  -- whose target had a space in it.
  vim.cmd.edit(vim.fn.fnameescape(path))
end, { desc = "Open markdown link under cursor" })

-------------------------------------------------------------------------------
-- MARKDOWN FOLDING SYSTEM (your advanced folding preserved cleanly)
-------------------------------------------------------------------------------
-- Which lines sit inside a fenced code block. A `#` there is whatever the
-- fenced language says it is -- in ```bash it is a comment -- and never a
-- markdown heading.
--
-- The foldexpr used to match `^%s*(#+)%s+` on the raw line with no fence
-- tracking, so a chapter full of `# output :` shell comments folded into
-- dozens of phantom headings, each swallowing the code block around it.
--
-- Cached per buffer on changedtick: foldexpr is called once per line on
-- every recompute, and rescanning the whole buffer each time would be
-- quadratic.
local fence_cache = { buf = -1, tick = -1, map = {} }

local function code_block_lines()
  local buf = vim.api.nvim_get_current_buf()
  local tick = vim.b[buf].changedtick
  if fence_cache.buf == buf and fence_cache.tick == tick then
    return fence_cache.map
  end

  local map, fence = {}, nil
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local marker = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if marker and not fence then
      -- The fence line itself counts as inside, so it is never a heading.
      fence, map[i] = marker:sub(1, 1), true
    elseif marker and marker:sub(1, 1) == fence then
      fence, map[i] = nil, true
    else
      map[i] = fence ~= nil
    end
  end

  fence_cache = { buf = buf, tick = tick, map = map }
  return map
end

-- An ATX heading takes at most 3 leading spaces; 4 or more makes it an
-- indented code block instead.
local function heading_level(line, lnum)
  if code_block_lines()[lnum] then
    return 0
  end
  local indent, hashes = line:match("^(%s*)(#+)%s")
  if not indent or #indent > 3 or #hashes > 6 then
    return 0
  end
  return #hashes
end

-- Body lines (prose, code, blanks) sit one level deeper than the deepest
-- heading Markdown allows, rather than inheriting their heading's level.
--
-- That is what makes an outline view possible. Previously body lines returned
-- "=", so a section's prose had the same fold level as the heading above it,
-- and "show every heading, hide every body" was not expressible as a single
-- 'foldlevel': in a file mixing ### sections with a #### one, the foldlevel
-- that folded the #### bodies already left every ### body on screen.
--
-- With every body at 7 regardless of depth, foldlevel 6 hides all of them and
-- leaves all six heading levels visible. See MARKDOWN_OUTLINE_LEVEL below.
local PROSE_FOLD_LEVEL = 7

function _G.markdown_foldexpr()
  local level = heading_level(vim.fn.getline(vim.v.lnum), vim.v.lnum)
  return level > 0 and (">" .. level) or PROSE_FOLD_LEVEL
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
-- IMPORTANT: vim.opt_local, never vim.opt. Using vim.opt here set the
-- *global* foldexpr/foldlevel, so after opening a single markdown file every
-- code file afterwards opened fully collapsed (global foldlevel became 0)
-- and needed zR by hand.
-- The resting view for a markdown file: every heading on screen, every body
-- folded away. One below PROSE_FOLD_LEVEL, so heading folds (1..6) stay open
-- and only the body folds close.
local MARKDOWN_OUTLINE_LEVEL = PROSE_FOLD_LEVEL - 1

local function apply_markdown_window()
  -- LazyVim's wrap_spell autocmd already turns on 'wrap' and 'linebreak' for
  -- markdown, so long lines break at spaces rather than mid-word. What it
  -- leaves off is 'breakindent', so the continuation of a wrapped bullet or
  -- quote restarted hard against column 0 and stopped looking like part of
  -- its list item. These notes are mostly long "> ..." and "- ..." lines, so
  -- that is most of the file.
  -- LazyVim's wrap_spell autocmd also turns 'spell' on for markdown. Off here:
  -- these notes are mostly shell commands, flags and file names, so nearly
  -- every other word was underlined -- including everything inside ```bash
  -- blocks, which spell checks too. Re-enable per buffer with :setlocal spell.
  vim.opt_local.spell = false

  vim.opt_local.breakindent = true
  -- Indent continuations a further 2 columns and mark them, so a wrapped line
  -- is never mistaken for a new bullet.
  vim.opt_local.breakindentopt = "shift:2"
  vim.opt_local.showbreak = "↳ "

  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldexpr = "v:lua.markdown_foldexpr()"
  -- vim.opt_local.foldtext = "v:lua.markdown_foldtext()"
  -- Opens as an outline. This was 0, which collapsed the whole file into its
  -- H1 line and hid the structure you actually want to see on open.
  vim.opt_local.foldlevel = MARKDOWN_OUTLINE_LEVEL
  vim.opt_local.foldenable = true
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = MARKDOWN_FILETYPES,
  callback = apply_markdown_window,
})

-- This file is loaded on VeryLazy, which fires *after* FileType has already
-- run for the file named on the command line. So `nvim notes.md` left that
-- first buffer on LazyVim's treesitter foldexpr, while every markdown file
-- opened later in the session got the one above -- folding behaved
-- differently depending on how the buffer happened to be opened, and the
-- in-code `#` comments were still folded as headings in that first file.
--
-- foldexpr is window-local, so catch up window by window.
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.tbl_contains(MARKDOWN_FILETYPES, vim.bo[buf].filetype) then
    vim.api.nvim_win_call(win, apply_markdown_window)
  end
end

-------------------------------------------------------------------------------
-- FOLD CONTROL KEYMAPS
-------------------------------------------------------------------------------
-- <leader>N collapses the document to heading depth N: H1..HN stay visible,
-- everything deeper folds away. Pressing the same N again reopens. <leader>0
-- opens everything.
--
-- This replaces a per-line walk that called zo/zc through vim.fn.setpos, and
-- which failed in four separate ways:
--
--   * it left the cursor parked on the last heading it touched, instead of
--     where you were reading;
--   * `foldclosed()` reports the *enclosing* closed fold, so an H3 sitting
--     inside a collapsed H1 section counted as "closed" and flipped the
--     toggle the wrong way;
--   * zc on a fold nested inside a closed parent raises E490, which the
--     surrounding pcall swallowed -- the key silently did nothing;
--   * the open/closed memory was one table shared by every buffer, so
--     toggling in one file desynced the state of every other. <leader>0 read
--     that table into a `close_all` variable it then never used, and just
--     re-toggled all six levels, which is why it behaved at random.
--
-- <leader>N opens the body of every H<N> section, and closes them again on the
-- second press. It is the bulk version of pressing <CR> on each H<N> heading.
--
-- It used to set 'foldlevel' to N-1 instead, i.e. "collapse the document to
-- depth N". That is a different operation, and in these files it looked like
-- a dead key: the buffer already opens as an outline with every body folded,
-- so lowering foldlevel only swallowed the H<N> headings into their own
-- section folds -- and because 'foldtext' is "" those folds still display the
-- heading line. Nothing appeared to happen, and nothing ever expanded.
--
-- Hierarchical collapsing is still available built in: zm / zr step foldlevel
-- down / up, zM / zR go all the way.
local FOLD_ALL_OPEN = 99

local function toggle_depth(depth)
  if not is_markdown() then
    return
  end
  vim.wo.foldenable = true
  -- A body is only reachable while its enclosing heading folds are open. The
  -- outline level opens all six heading levels and leaves bodies folded, so
  -- come back up to it first if the user had collapsed further than that.
  if vim.wo.foldlevel < MARKDOWN_OUTLINE_LEVEL then
    vim.wo.foldlevel = MARKDOWN_OUTLINE_LEVEL
  end

  local last = vim.fn.line("$")

  -- Line of the last body line under the heading at `l`, i.e. everything up to
  -- the next heading of any depth.
  local function body_end(l)
    for i = l + 1, last do
      if heading_level(vim.fn.getline(i), i) > 0 then
        return i - 1
      end
    end
    return last
  end

  -- Which fold each H<depth> heading should toggle.
  --
  -- Usually its own body, the fold starting on the line below it. But a
  -- heading whose next sibling follows immediately -- "# Terminal 101" then
  -- "## Chapter 4", separated only by a blank line -- has no body worth
  -- folding: a 1-line fold can never display closed, since 'foldminlines' is
  -- 1. Those headings toggle their whole SECTION instead, which is the fold
  -- that starts on the heading itself and holds every sub-heading under it.
  -- Without this <leader>1 and <leader>2 were dead keys in every chapter.
  local targets = {}
  for l = 1, last do
    if heading_level(vim.fn.getline(l), l) == depth then
      local b = l + 1
      targets[#targets + 1] = (b <= last and body_end(l) - b + 1 >= 2) and b or l
    end
  end

  if #targets == 0 then
    vim.notify(("No H%d heading in this buffer"):format(depth), vim.log.levels.INFO)
    return
  end

  -- Any one closed means "open them all"; otherwise close them all.
  local any_closed = false
  for _, b in ipairs(targets) do
    if vim.fn.foldclosed(b) ~= -1 then
      any_closed = true
      break
    end
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  for _, b in ipairs(targets) do
    pcall(vim.cmd, b .. (any_closed and "foldopen" or "foldclose"))
  end
  -- Ranged :foldopen/:foldclose park the cursor on the range.
  pcall(vim.api.nvim_win_set_cursor, 0, pos)
end

for i = 1, 6 do
  vim.keymap.set("n", "<leader>" .. i, function()
    toggle_depth(i)
  end, { desc = "Toggle all H" .. i .. " sections" })
end

-- Toggles the two whole-file views: outline (headings only) and fully open.
vim.keymap.set("n", "<leader>0", function()
  if is_markdown() then
    vim.wo.foldenable = true
    vim.wo.foldlevel = (vim.wo.foldlevel == FOLD_ALL_OPEN) and MARKDOWN_OUTLINE_LEVEL or FOLD_ALL_OPEN
  end
end, { desc = "Toggle markdown outline / fully open" })

vim.keymap.set("n", "zu", "zR", { desc = "Open all folds" })

vim.keymap.set("n", "<CR>", function()
  local l = vim.fn.line(".")

  -- On a markdown heading, toggle only THAT heading's own body -- the fold
  -- that starts on the line below it. Plain zc here would close the heading's
  -- whole *section* fold instead, which also swallows every sub-heading under
  -- it, so collapsing "### 1." made "#### NOTES:" vanish too.
  if is_markdown() and heading_level(vim.fn.getline(l), l) > 0 then
    local body = l + 1
    local has_body = body <= vim.fn.line("$")
      and heading_level(vim.fn.getline(body), body) == 0
      and vim.fn.foldlevel(body) > vim.fn.foldlevel(l)
    if has_body then
      local pos = vim.api.nvim_win_get_cursor(0)
      -- A ranged :foldopen/:foldclose leaves the cursor on the range, so put
      -- it back on the heading you pressed <CR> on.
      pcall(vim.cmd, body .. (vim.fn.foldclosed(body) ~= -1 and "foldopen" or "foldclose"))
      pcall(vim.api.nvim_win_set_cursor, 0, pos)
      return
    end
  end

  if vim.fn.foldlevel(l) == 0 then
    -- No fold here, so hand the key back to Neovim. An early return instead
    -- would swallow <CR> in every unfolded buffer -- it would stop moving to
    -- the next line everywhere, not just in markdown.
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
    return
  end

  vim.cmd("normal! " .. (vim.fn.foldclosed(l) ~= -1 and "zo" or "zc"))
end, { desc = "Toggle fold, else <CR>" })

-- require("config.image_toggle")
