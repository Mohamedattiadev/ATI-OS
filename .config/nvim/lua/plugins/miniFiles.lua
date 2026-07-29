--------------------------------------------------------------------------
-- Unsaved-buffer markers in the file explorer.
--
-- Marks any file with unwritten changes so you can spot it after navigating
-- away, and marks the directories leading to it so you can find it without
-- opening every folder.
--
--   somefile.lua    ● unsaved      <- file has unsaved changes
--   src/            ●              <- something unsaved lives in here
--
-- Drawn as extmarks rather than via `content.prefix`, because prefix returns
-- a single highlight group for the whole prefix -- putting the marker there
-- would force the file icon to take the marker's colour too.
--------------------------------------------------------------------------
local ns = vim.api.nvim_create_namespace("MiniFilesUnsaved")

-- Set of absolute paths of real, listed buffers with unwritten changes.
local function unsaved_paths()
  local set = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].modified
      and vim.bo[buf].buftype == ""
    then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        set[vim.fs.normalize(name)] = true
      end
    end
  end
  return set
end

local function annotate(buf)
  if type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local unsaved = unsaved_paths()
  if vim.tbl_isempty(unsaved) then
    return
  end

  for lnum = 1, vim.api.nvim_buf_line_count(buf) do
    -- get_fs_entry errors on buffers that are not directory buffers (e.g.
    -- the file preview pane), hence the pcall.
    local ok, entry = pcall(MiniFiles.get_fs_entry, buf, lnum)
    if ok and entry then
      local path = vim.fs.normalize(entry.path)
      local text, hl

      if entry.fs_type == "directory" then
        local dir = path:gsub("/+$", "") .. "/"
        for p in pairs(unsaved) do
          if p:sub(1, #dir) == dir then
            text, hl = "●", "MiniFilesUnsavedDir"
            break
          end
        end
      elseif unsaved[path] then
        text, hl = "● unsaved", "MiniFilesUnsaved"
      end

      if text then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
          virt_text = { { "  " .. text, hl } },
          virt_text_pos = "eol",
          hl_mode = "combine",
        })
      end
    end
  end
end

-- Re-declared on every colorscheme change: themes.lua runs `hi clear` when
-- it switches theme, which would otherwise wipe these.
local function set_highlights()
  vim.api.nvim_set_hl(0, "MiniFilesUnsaved", { fg = "#ffb86c", bold = true, default = true })
  vim.api.nvim_set_hl(0, "MiniFilesUnsavedDir", { fg = "#c678dd", default = true })
end

return {
  "nvim-mini/mini.files",

  init = function()
    local group = vim.api.nvim_create_augroup("MiniFilesUnsavedMarks", { clear = true })

    set_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })

    -- Fires once per directory buffer render -- exactly when the listing
    -- needs its markers (re)drawn.
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "MiniFilesBufferUpdate",
      callback = function(args)
        local buf = args.data and args.data.buf_id
        if buf then
          annotate(buf)
        end
      end,
    })
  end,

  opts = function(_, opts)
    -- Your custom mappings (These are fine)
    opts.mappings = vim.tbl_deep_extend("force", opts.mappings or {}, {
      close = "q",
      go_in = "l",
      go_in_plus = "<CR>",
      go_out = "H",
      go_out_plus = "h",
      reset = "<BS>",
      reveal_cwd = ".",
      show_help = "g?",
      synchronize = "s",
      trim_left = "<",
      trim_right = ">",
    })

    -- Your window options (These are fine)
    opts.windows = vim.tbl_deep_extend("force", opts.windows or {}, {
      preview = true,
      width_focus = 30,
      width_preview = 80,
    })

    -- Your general options (These are fine)
    opts.options = vim.tbl_deep_extend("force", opts.options or {}, {
      use_as_default_explorer = true,
      permanent_delete = false,
    })

    -- NOTE: the old commented-out `content.prefix` attempt at an unsaved
    -- marker was removed -- it is implemented at the top of this file as
    -- extmarks instead. That version also had a latent bug worth
    -- remembering: `vim.fn.bufnr(path)` does *pattern* matching, so a path
    -- like `init.lua` could match an unrelated buffer whose name merely
    -- contains it. The implementation above compares normalized full paths.

    return opts
  end,

  keys = {
    {
      "<leader>e",
      function()
        local buf_name = vim.api.nvim_buf_get_name(0)
        local dir_name = vim.fn.fnamemodify(buf_name, ":p:h")
        if vim.fn.filereadable(buf_name) == 1 then
          require("mini.files").open(buf_name, true)
        elseif vim.fn.isdirectory(dir_name) == 1 then
          require("mini.files").open(dir_name, true)
        else
          require("mini.files").open(vim.uv.cwd(), true)
        end
      end,
      desc = "Open mini.files (Directory of Current File or CWD if not exists)",
    },
    -- {
    --   "<leader>E",
    --   function()
    --     require("mini.files").open(vim.uv.cwd(), true)
    --   end,
    --   desc = "Open mini.files (cwd)",
    -- },
  },

  -- config = function(_, opts)
  --
  --   require("mini.files").setup(opts)
  --   vim.api.nvim_set_hl(0, "MiniFilesModified", { fg = "#98be65", bold = true })
  --   vim.api.nvim_create_autocmd("FileType", {
  --     pattern = "minifiles",
  --     callback = function(args)
  --       local map = function(lhs, rhs, desc)
  --         vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
  --       end
  --       map("<M-c>", function()
  --         local fs = require("mini.files")
  --         local target = fs.get_fs_entry()
  --         if target then
  --           vim.fn.setreg("+", target.path)
  --           print("Copied path: " .. target.path)
  --         end
  --       end, "Copy path")
  --     end,
  --   })
  -- end,
}
