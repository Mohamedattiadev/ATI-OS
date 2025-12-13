return {
  "folke/noice.nvim",
  event = "VeryLazy",
  opts = {
    lsp = {
      progress = { enabled = false },
      signature = { enabled = false },
      hover = { enabled = false },
      message = { enabled = false },
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = false,
        ["vim.lsp.util.stylize_markdown"] = false,
        ["cmp.entry.get_documentation"] = false,
      },
    },
    views = {
      -- cmdline_popup = { border = { style = "none" } },
      -- popupmenu = { border = { style = "none" } },
      mini = { win_options = { winblend = 0 } },
    },
    presets = {
      bottom_search = false,
      command_palette = false,
      long_message_to_split = false,
      inc_rename = false,
      lsp_doc_border = false,
    },
    routes = {}, -- no filters / delays
    throttle = 0, -- disable any throttling/delays
    notify = {
      enabled = false,
    },
  },
  dependencies = {
    "MunifTanjim/nui.nvim",
    -- Only needed if you explicitly want notify, otherwise disable it:
    -- "rcarriga/nvim-notify",
  },
  keys = {
    { "<esc><esc>", "<cmd>NoiceDismiss<cr>" },
  },
}
