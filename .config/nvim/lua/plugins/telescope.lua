return {
  "nvim-telescope/telescope.nvim",
  branch = "master",
  event = "VeryLazy",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    "nvim-tree/nvim-web-devicons",
    "folke/todo-comments.nvim",
  },

  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")
    local transform_mod = require("telescope.actions.mt").transform_mod

    local trouble = require("trouble")
    local trouble_telescope = require("trouble.sources.telescope")

    local custom_actions = transform_mod({
      open_trouble_qflist = function()
        trouble.toggle("quickfix")
      end,
    })

    telescope.setup({
      defaults = {
        ------------------------------------------------------------
        -- SHAPE / LAYOUT  (matches your screenshot)
        ------------------------------------------------------------
        layout_strategy = "horizontal",
        layout_config = {
          width = 0.80,
          height = 0.80,
          preview_width = 0.58,
          prompt_position = "top",
        },

        sorting_strategy = "ascending",
        path_display = { "smart" },

        ------------------------------------------------------------
        -- VISUAL CHROME
        ------------------------------------------------------------
        border = true,
        winblend = 0,

        prompt_prefix = "    ",
        selection_caret = "▌ ",
        entry_prefix = "  ",

        borderchars = {
          "─",
          "│",
          "─",
          "│",
          "╭",
          "╮",
          "╯",
          "╰",
        },

        ------------------------------------------------------------
        -- PREVIEW
        ------------------------------------------------------------
        preview = {
          treesitter = true,
        },

        ------------------------------------------------------------
        -- KEYMAPS
        ------------------------------------------------------------
        mappings = {
          i = {
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-q>"] = actions.send_selected_to_qflist + custom_actions.open_trouble_qflist,
            ["<C-t>"] = trouble_telescope.open,
          },
        },
      },

      --------------------------------------------------------------
      -- FZF NATIVE
      --------------------------------------------------------------
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = "smart_case",
        },
      },
    })

    telescope.load_extension("fzf")

    --------------------------------------------------------------
    -- KEYMAPS
    --------------------------------------------------------------
    local builtin = require("telescope.builtin")
    local keymap = vim.keymap

    keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
    keymap.set("n", "<leader>oo", builtin.oldfiles, { desc = "Old files" })
    keymap.set("n", "<leader>fw", builtin.grep_string, { desc = "Grep word" })
  end,
}
