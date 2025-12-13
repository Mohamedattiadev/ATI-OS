-- return {
--   {
--     "nvim-telescope/telescope.nvim",
--     tag = "0.1.5",
--     -- event = "BufReadPre",
--
--     config = function()
--       local builtin = require("telescope.builtin")
--       -- vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find Files" })
--       -- vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live Grep" })
--       vim.keymap.set("n", "<leader>oo", builtin.oldfiles, { desc = "Old Files" })
--       --
--       -- vim.keymap.set("n", "<leader>bb", builtin.buffers, { desc = "Buffers" })
--     end,
--
--     --disable some
--   },
-- }
return {
  "nvim-telescope/telescope.nvim",
  branch = "0.1.x",
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

    -- or create your custom action
    local custom_actions = transform_mod({
      open_trouble_qflist = function(prompt_bufnr)
        trouble.toggle("quickfix")
      end,
    })

    telescope.setup({
      defaults = {
        path_display = { "smart" },
        mappings = {
          i = {
            ["<C-k>"] = actions.move_selection_previous, -- move to prev result
            ["<C-j>"] = actions.move_selection_next, -- move to next result
            ["<C-q>"] = actions.send_selected_to_qflist + custom_actions.open_trouble_qflist,
            ["<C-t>"] = trouble_telescope.open,
          },
        },
      },
    })

    telescope.load_extension("fzf")

    -- set keymaps
    -- Set keymaps
    local keymap = vim.keymap -- for conciseness

    -- Telescope key mappings
    keymap.set(
      "n",
      "<leader>ff",
      "<cmd>Telescope find_files<cr>",
      { noremap = true, silent = true, desc = "Fuzzy find files in cwd" }
    )
    keymap.set(
      "n",
      "<leader>oo",
      "<cmd>Telescope oldfiles<cr>",
      { noremap = true, silent = true, desc = "Fuzzy find recent files" }
    )
    keymap.set(
      "n",
      "<leader> bb",
      ":Telescope buffers<cr>",
      { noremap = true, silent = true, desc = "Fuzzy find recent buffers" }
    )
    keymap.set(
      "n",
      "<leader>fg",
      "<cmd>Telescope live_grep<cr>",
      { noremap = true, silent = true, desc = "Find string in cwd" }
    )
    keymap.set(
      "n",
      "<leader>fs",
      "<cmd>Telescope grep_string<cr>",
      { noremap = true, silent = true, desc = "Find string under cursor in cwd" }
    )
    keymap.set("n", "<leader>ft", "<cmd>TodoTelescope<cr>", { noremap = true, silent = true, desc = "Find todos" })
  end,
}
