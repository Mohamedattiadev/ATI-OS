return {
  "nvim-mini/mini.ai",

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

    -- 🔹 THE FIX IS ONLY INSIDE THIS `prefix` FUNCTION 🔹
    opts.content = vim.tbl_deep_extend("force", opts.content or {}, {
      prefix = function(fs_entry)
        -- Part 1: Get the file/folder icon safely
        local icon_part = "  " -- Default to spaces if nvim-web-devicons is not found
        local success, devicons = pcall(require, "nvim-web-devicons")
        if success then
          local icon, _ = devicons.get_icon(fs_entry.name, vim.fn.fnamemodify(fs_entry.name, ":e"), { default = true })
          icon_part = (icon or " ") .. " "
        end

        -- Part 2: Your original, working logic for the modified indicator
        local modified_indicator = ""
        local bufnr = vim.fn.bufnr(fs_entry.path, false)
        if bufnr ~= -1 and vim.bo[bufnr].modified then
          modified_indicator = "[+] " -- Your indicator
        end

        -- Part 3: Combine them and return the result
        return modified_indicator .. icon_part
      end,
    })

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
    {
      "<leader>E",
      function()
        require("mini.files").open(vim.uv.cwd(), true)
      end,
      desc = "Open mini.files (cwd)",
    },
  },

  -- Your config function is fine as it is. No changes needed here.
  config = function(_, opts)
    require("mini.files").setup(opts)
    vim.api.nvim_set_hl(0, "MiniFilesModified", { fg = "#98be65", bold = true })
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "minifiles",
      callback = function(args)
        local map = function(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
        end
        map("<M-c>", function()
          local fs = require("mini.files")
          local target = fs.get_fs_entry()
          if target then
            vim.fn.setreg("+", target.path)
            print("Copied path: " .. target.path)
          end
        end, "Copy path")
      end,
    })
  end,
}
