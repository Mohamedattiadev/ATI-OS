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

    -- 🔹 Overlap handling (YOU DON’T WANT OVERLAP CLEARING)
    -- window_overlap_clear_enabled = false, -- ❌ disable clearing on overlap
    -- window_overlap_clear_ft_ignore = {
    --   "cmp_menu",
    --   "cmp_docs",
    --   "snacks_notif",
    --   "scrollview",
    --   "scrollview_sign",
    -- },

    -- 🔹 Size limits (safe defaults)
    max_width = 100,
    max_height = 30,
    max_width_window_percentage = nil,
    max_height_window_percentage = nil,
  },
}
