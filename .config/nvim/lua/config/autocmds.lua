-- autocmds are automatically loaded on the verylazy event
-- default autocmds that are always set: https://github.com/lazyvim/lazyvim/blob/main/lua/lazyvim/config/autocmds.lua
-- add any additional autocmds here
--

-- Push TODOS.md to Simplenote on every write, so the Mod+Shift+S note is on the
-- phone. BufWritePost fires once per buffer actually written, so :w, :wa, :wq,
-- :wqa and :x are all covered by the one autocmd.
--
-- pattern="*" plus an explicit realpath comparison, rather than the obvious
-- pattern="/home/ati/ATITODOS/TODOS.md": autocmd patterns match the buffer name
-- as typed, so opening the file by a relative path or through a symlink misses.
-- Resolving both sides catches every spelling of the same file.
local sn_target = vim.uv.fs_realpath(
  vim.fn.expand("~/" .. (vim.env.USER or ""):upper() .. "TODOS/TODOS.md")
)
if sn_target then
  -- Shared matcher. Two things it must get right:
  --   * read the name off the buffer, not ev.match -- FocusGained sets match to
  --     the window id, not a path, so matching on it silently never fires.
  --   * bail on a plain string compare before calling fs_realpath, which is a
  --     syscall: CursorHold fires constantly, in every buffer, forever.
  local function is_sn_buf(ev)
    local name = vim.api.nvim_buf_get_name(ev.buf or 0)
    if name == "" or not name:match("TODOS%.md$") then
      return false
    end
    return vim.uv.fs_realpath(name) == sn_target
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*",
    callback = function(ev)
      if not is_sn_buf(ev) then
        return
      end
      -- detached vim.system(), never :! -- this talks to the network, and a
      -- stalled request must not freeze the editor mid-save.
      local push_script = vim.fn.expand("~/.config/AtiScriptsV1/notes/ati-simplenote-push")
      -- executable() guard: a rename/removal of the script must not turn a
      -- routine :w into an ENOENT error every time this autocmd fires.
      if vim.fn.executable(push_script) == 1 then
        vim.system({ push_script }, { detach = true })
      end
    end,
    desc = "Mirror TODOS.md into Simplenote",
  })

  -- The other direction. qtile fires `ati-simplenote-push --pull` when the
  -- Mod+Shift+S window opens, but it cannot block the WM waiting for the
  -- network -- so the pull often lands a second or two AFTER nvim has already
  -- read the file. Without this the phone's edits sit on disk, invisible, until
  -- the next time the buffer is loaded from scratch.
  --
  -- 'autoread' only re-reads when something asks it to; :checktime is that ask.
  -- It is a no-op when the file is unchanged, and when the buffer has unsaved
  -- edits nvim prompts instead of clobbering them.
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
    pattern = "*",
    callback = function(ev)
      if not is_sn_buf(ev) then
        return
      end
      vim.opt_local.autoread = true
      -- pcall: :checktime throws while a prompt or command-line window is open,
      -- and CursorHold can fire in exactly those moments.
      pcall(vim.cmd, "checktime")
    end,
    desc = "Pick up Simplenote pulls into an open TODOS.md",
  })
end
