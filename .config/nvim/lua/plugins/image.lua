-- Extensions image.nvim can actually decode (see its utils/dimensions.lua
-- handlers + hijack_file_patterns). Anything outside this list must fall
-- through to mini.files' normal text preview, not be blanked and left empty.
local IMAGE_EXT = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  avif = true,
}

local function is_image_path(path)
  local ext = path and path:match("%.([%a%d]+)$")
  return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

-- The single image currently drawn into the mini.files preview pane, if
-- any, plus enough of what it was drawn from to tell a redundant refresh
-- from a real one. mini.files only ever shows one preview at a time, and
-- a stale handle here is what leaves a ghost image painted over the next
-- directory listing.
local shown = { image = nil, path = nil, win = nil, width = nil, height = nil, row = nil, col = nil }

-- Every image this integration has ever drawn into a preview pane.
--
-- Tracking only the current one is not enough: mini.files reshuffles its
-- columns whenever you go in or out of a directory, replacing the preview
-- window rather than moving it. The handle for the old window then never
-- gets cleared, and because terminal graphics are painted independently of
-- neovim's drawing, the picture stays on screen at its old position --
-- covering the file listing that has since slid underneath it.
--
-- Keeping every handle means a reconcile can take down all of them, no
-- matter which window each was tied to.
local created = {}

local function clear_preview_image()
  for _, img in ipairs(created) do
    pcall(function()
      img:clear()
    end)
  end
  created = {}
  shown = { image = nil, path = nil, win = nil, width = nil, height = nil, row = nil, col = nil }
end

-- Bring the rendered image in line with whatever mini.files is currently
-- previewing. Written as a full reconcile rather than a render-on-event
-- because MiniFilesWindowUpdate fires once per open column, so a naive
-- "is this event's path an image?" handler would render on the preview
-- column and then immediately clear again on the parent directory's.
local function reconcile()
  local ok_mf, mf = pcall(require, "mini.files")
  if not ok_mf then
    return clear_preview_image()
  end

  local state = mf.get_explorer_state()
  if state == nil then
    return clear_preview_image()
  end

  -- The preview always sits one column right of the focused one; every
  -- column at or left of depth_focus is a real directory listing.
  local entry = state.windows[state.depth_focus + 1]
  local path = entry and entry.path
  local win = entry and entry.win_id

  if not is_image_path(path) or win == nil or not vim.api.nvim_win_is_valid(win) then
    return clear_preview_image()
  end

  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  -- Screen position matters as much as size. Navigating in or out shifts
  -- every column sideways, and comparing only win/width/height treated
  -- that as "nothing changed" -- so the image was left drawn at the old
  -- column's coordinates.
  local ok_pos, pos = pcall(vim.api.nvim_win_get_position, win)
  local row, col = nil, nil
  if ok_pos then
    row, col = pos[1], pos[2]
  end

  -- Bail out when nothing that affects the drawing has changed. This is
  -- what keeps the image from flickering: MiniFilesWindowUpdate is
  -- documented as triggering "VERY frequently", and re-rendering on each
  -- one tears the picture down and back up several times per keystroke.
  if
    shown.image ~= nil
    and shown.path == path
    and shown.win == win
    and shown.width == width
    and shown.height == height
    and shown.row == row
    and shown.col == col
  then
    return
  end

  clear_preview_image()

  local ok, image_api = pcall(require, "image")
  if not ok then
    return
  end

  local img = image_api.from_file(path, {
    window = win,
    buffer = vim.api.nvim_win_get_buf(win),
    x = 0,
    y = 0,
    width = width,
    height = height,
  })
  if img == nil then
    return
  end
  pcall(function()
    img:render()
  end)
  created[#created + 1] = img
  shown = {
    image = img,
    path = path,
    win = win,
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

-- image.nvim registers a WinNew/BufWinEnter/TabEnter autocmd for
-- hijack_file_patterns ("*.png", "*.gif", ...) so that opening an image
-- file shows the picture instead of binary junk. Those patterns match on
-- the *buffer name*, and mini.files names its buffers
-- "minifiles://<id>/<path>" -- which ends in ".gif" and therefore matches.
--
-- The handler then feeds that whole buffer name to from_file() as if it
-- were a filesystem path. It isn't, so from_file throws "file not found",
-- and because the hijack runs from a BufWinEnter fired inside mini.files'
-- own nvim_open_win() call, the error unwinds through explorer_refresh and
-- takes the entire explorer down -- not just the preview.
--
-- (It is wrong twice over: it also resolves the target window with
-- nvim_get_current_win(), which during mini.files' window_open is not the
-- window being created.)
--
-- image.nvim exposes no ignore-list, so intercept at the public API it
-- dispatches through. The autocmd looks `hijack_buffer` up on the module
-- table at call time, so replacing the field is enough. Previews are drawn
-- by reconcile() below instead, which knows the real path.
local function block_hijack_for_minifiles(image_api)
  if image_api.__minifiles_hijack_guard then
    return
  end
  local original = image_api.hijack_buffer
  image_api.hijack_buffer = function(path, win, buf, options)
    if type(path) == "string" and path:match("^minifiles://") then
      return
    end
    return original(path, win, buf, options)
  end
  image_api.__minifiles_hijack_guard = true
end

-- Images rendered elsewhere in the editor that we took down for the
-- duration of the explorer, so they can be put back on close.
local suppressed = {}

-- Hide every image that is not the explorer's own preview.
--
-- image.nvim's window_overlap_clear_enabled already tries to do this, but
-- it is driven from a decoration-provider redraw callback and reconciles
-- masks asynchronously through its render scheduler -- so an image that
-- was rendered before the explorer opened can survive the transition and
-- stay painted over the file listing. Terminal graphics sit above
-- everything neovim draws, so the result is a picture floating on top of
-- the tree.
--
-- Doing it explicitly on the open/close events makes it deterministic:
-- the explorer is modal, so nothing behind it should be showing anyway.
-- Shallow clear (clear(true)) keeps image.nvim's state for the image, so
-- restoring is a plain re-render rather than a reload from disk.
local function suppress_other_images()
  suppressed = {}
  local ok, image_api = pcall(require, "image")
  if not ok then
    return
  end
  for _, img in ipairs(image_api.get_images()) do
    local is_ours = false
    for _, mine in ipairs(created) do
      if mine == img then
        is_ours = true
        break
      end
    end
    if img.is_rendered and not is_ours then
      table.insert(suppressed, { image = img, window = img.window, buffer = img.buffer })
      pcall(function()
        img:clear(true)
      end)
    end
  end
end

local function restore_other_images()
  local entries = suppressed
  suppressed = {}
  for _, entry in ipairs(entries) do
    -- Only put an image back if its window still shows the same buffer.
    -- Opening a file from the explorer replaces that buffer, and the new
    -- one draws itself -- re-rendering the old image over it would leave
    -- exactly the ghost this is meant to prevent.
    local win_ok = entry.window ~= nil and vim.api.nvim_win_is_valid(entry.window)
    if win_ok and vim.api.nvim_win_get_buf(entry.window) == entry.buffer then
      pcall(function()
        entry.image:render()
      end)
    end
  end
end

local function setup_minifiles_integration()
  local group = vim.api.nvim_create_augroup("ImageMiniFiles", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesExplorerOpen",
    callback = suppress_other_images,
  })

  local ok, image_api = pcall(require, "image")
  if ok then
    block_hijack_for_minifiles(image_api)
  end

  -- Content pass. mini.files' buffer_update_file() sniffs the first 1024
  -- bytes for a NUL and, finding one, fills the preview with the literal
  -- placeholder "-Non-text-file--------". That text sits underneath a
  -- kitty-protocol image and shows through, so blank it here.
  --
  -- This has to happen on BufferUpdate specifically, not in reconcile():
  -- the event is triggered synchronously from inside buffer_update(),
  -- immediately BEFORE it resets opened_buffers[buf].n_modified = -1, so
  -- our write is absorbed by that reset and mini.files never sees the
  -- preview as user-modified. Blanking later would leave a buffer it
  -- believes the user edited, and offer to write it back on synchronize.
  --
  -- Note this event's win_id is always nil (files.lua nils it on refresh
  -- and only assigns it once the window is opened, which happens after
  -- the buffer is filled) -- hence the separate geometry pass below.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesBufferUpdate",
    callback = function(args)
      local buf = args.data and args.data.buf_id
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      -- mini.files names every buffer it owns "minifiles://<buf_id>/<path>".
      local path = vim.api.nvim_buf_get_name(buf):match("^minifiles://%d+/(.*)$")
      if not is_image_path(path) then
        return
      end
      -- Blank *lines*, not an empty buffer. mini.files sizes the preview
      -- window with `min(buf_line_count, max_height)` (files.lua
      -- window_update), so clearing to zero lines collapses the window to
      -- a single row and the image gets one row to draw in. Padding past
      -- the screen height makes that min() pick mini.files' own maximum,
      -- giving the picture the full pane.
      local filler = {}
      for i = 1, vim.o.lines do
        filler[i] = ""
      end
      local was_modifiable = vim.bo[buf].modifiable
      vim.bo[buf].modifiable = true
      pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, filler)
      vim.bo[buf].modifiable = was_modifiable
    end,
  })

  -- Geometry/render pass. By the time this fires every window for the
  -- refresh exists and has its final size.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesWindowUpdate",
    callback = function()
      pcall(reconcile)
    end,
  })

  -- Closing the explorer tears down its floats, but image.nvim draws
  -- straight to the terminal and has no idea the window went away --
  -- without this the picture stays burned over the editor.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesExplorerClose",
    callback = function()
      clear_preview_image()
      restore_other_images()
    end,
  })
end

return {
  "3rd/image.nvim",
  build = false, -- do NOT build luarocks (Arch-safe)
  lazy = false, -- MUST load early (before mini.files hooks)
  opts = {
    processor = "magick_cli",
    backend = "kitty",

    -- 🔹 Markdown / text integrations
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = true,
        download_remote_images = true,
        only_render_image_at_cursor_mode = "inline", -- or "inline"
        only_render_image_at_cursor = true,
        floating_windows = true,
      },
    },

    -- 🔹 Overlap handling
    --
    -- This has to be ON. Images are painted by the terminal itself, on a
    -- layer above everything neovim draws, so they do not obey window
    -- stacking: with clearing disabled, an image opened in a normal
    -- window keeps showing straight *through* any float placed over it --
    -- which is why opening an image and then opening the mini.files tree
    -- left the picture bleeding over the file listing.
    --
    -- Enabling it makes image.nvim hide an image while another window
    -- overlaps its region (renderer.lua bails when #window.masks > 0).
    window_overlap_clear_enabled = true,
    -- ...except for these. Transient popups that draw over an image
    -- should not make it disappear and flash back on dismissal. Note
    -- "minifiles" is deliberately NOT in this list: the tree overlapping
    -- an image is exactly the case that must clear.
    window_overlap_clear_ft_ignore = {
      "cmp_menu",
      "cmp_docs",
      "snacks_notif",
      "scrollview",
      "scrollview_sign",
    },

    -- 🔹 Size limits (safe defaults)
    max_width = 100,
    max_height = 30,
    max_width_window_percentage = nil,
    max_height_window_percentage = nil,
  },

  -- Explicit config (instead of letting lazy.nvim call setup from `opts`)
  -- so the mini.files autocmds are registered at exactly the same moment
  -- image.nvim finishes setting up -- registering them earlier would let
  -- a MiniFilesBufferUpdate arrive before `require("image")` is usable.
  config = function(_, opts)
    require("image").setup(opts)
    setup_minifiles_integration()
  end,
}
