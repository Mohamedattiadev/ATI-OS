return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" },
    opts = function(_, opts)
      -- Force Markdown file types for universal functionality
      opts.file_types = opts.file_types or { "markdown" }

      -- Using your CSS color palette for bg and fg in headers

      vim.api.nvim_set_hl(0, "RenderMarkdownH1Bg", { bg = "#bd9cf9", fg = "#282c34" }) -- Bright purple bg + dark bg fg (#md-default-bg-color)
      vim.api.nvim_set_hl(0, "RenderMarkdownH2Bg", { bg = "#51afef", fg = "#282c34" }) -- Primary blue bg + default fg
      vim.api.nvim_set_hl(0, "RenderMarkdownH3Bg", { bg = "#ffb86c", fg = "#282c34" }) -- Default dark bg + primary blue fg
      vim.api.nvim_set_hl(0, "RenderMarkdownH4Bg", { bg = "#c678dd", fg = "#282c34" }) -- Accent purple bg + dark bg fg
      vim.api.nvim_set_hl(0, "RenderMarkdownH5Bg", { bg = "#98be65", fg = "#282c34" }) -- Greenish code fg as bg + dark fg
      vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", { bg = "#1e222a", fg = "#51afef" }) -- Code bg + default fg
      -- Checkbox highlight groups
      vim.api.nvim_set_hl(0, "RenderMarkdownUnchecked", { fg = "#EBCB8B", bold = true }) -- Yellow
      vim.api.nvim_set_hl(0, "RenderMarkdownChecked", { fg = "#A3BE8C", bold = true }) -- Green
      vim.api.nvim_set_hl(0, "RenderMarkdownTodo", { fg = "#88C0D0", bold = true }) -- Cyan
      vim.api.nvim_set_hl(0, "RenderMarkdownMath", { fg = "#B48EAD", italic = true }) -- Purple

      -- Bullet highlight groups with a clean, rotating color scheme
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet1", { fg = "#51afef" }) -- Soft Blue (lighter than #5E81AC)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet2", { fg = "#bd9cf9" }) -- Green (keep as is, good contrast)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet3", { fg = "#ffb86c" }) -- Warm Yellow (same, nice brightness)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet4", { fg = "#c678dd" }) -- Muted Purple (same, calm)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet5", { fg = "#98be65" }) -- Teal (a bit lighter than #8FBCBB)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet6", { fg = "#BF616A" }) -- Warm Red (good as is)
      vim.api.nvim_set_hl(0, "RenderMarkdownBullet7", { fg = "#D08770" }) -- Soft Orange (keep as is)

      -- Dash line highlight
      vim.api.nvim_set_hl(0, "RenderMarkdownDash", { fg = "#4a6582", bold = true })

      -- Checkbox icons and settings
      opts.checkbox = vim.tbl_deep_extend("force", opts.checkbox or {}, {
        enabled = true,
        render_modes = false,
        bullet = false,
        right_pad = 1,
        unchecked = {
          icon = "󰄱 ",
          highlight = "RenderMarkdownUnchecked",
        },
        checked = {
          icon = "󰱒 ",
          highlight = "RenderMarkdownChecked",
        },
        custom = {
          todo = {
            raw = "[-]",
            rendered = "󰦪 ", -- A more distinct "TODO" icon
            highlight = "RenderMarkdownTodo",
          },
        },
      })

      -- Heading icons and settings
      opts.heading = vim.tbl_deep_extend("force", opts.heading or {}, {
        enabled = true,
        render_modes = false,
        atx = true,
        setext = true,
        sign = true,
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " }, -- Reusing these clear icons
        position = "overlay",
        signs = { "󰫎 " },
        width = "full",
        left_margin = 0,
        left_pad = 3,
        right_pad = 3,
        min_width = 0,
        border = false,
        border_virtual = false,
        border_prefix = false,
        above = "▄",
        below = "▀",
        backgrounds = {
          "RenderMarkdownH1Bg",
          "RenderMarkdownH2Bg",
          "RenderMarkdownH3Bg",
          "RenderMarkdownH4Bg",
          "RenderMarkdownH5Bg",
          "RenderMarkdownH6Bg",
        },
        foregrounds = {
          "RenderMarkdownH1",
          "RenderMarkdownH2",
          "RenderMarkdownH3",
          "RenderMarkdownH4",
          "RenderMarkdownH5",
          "RenderMarkdownH6",
        },
        custom = {},
      })

      -- Bullet config with requested icons and dynamic highlights
      opts.bullet = {
        enabled = true,
        render_modes = false,
        -- icons = { "❀", "✿", "✾", "❁", "✦", "✧", "❉" },

        icons = { "❀", "✿", "◍", "◉", "✦", "●" },
        highlight = function(ctx)
          local hl_groups = {
            [1] = "RenderMarkdownBullet1",
            [2] = "RenderMarkdownBullet2",
            [3] = "RenderMarkdownBullet3",
            [4] = "RenderMarkdownBullet4",
            [5] = "RenderMarkdownBullet5",
            [6] = "RenderMarkdownBullet6",
            [7] = "RenderMarkdownBullet7",
          }
          return hl_groups[ctx.level] or "RenderMarkdownBullet1"
        end,
        scope_highlight = {},
        left_pad = 0,
        right_pad = 1,
        ordered_icons = function(ctx)
          local value = vim.trim(ctx.value)
          local index = tonumber(value:sub(1, #value - 1))
          return ("%d."):format(index > 1 and index or ctx.index)
        end,
      }

      -- LaTeX rendering
      opts.latex = vim.tbl_deep_extend("force", opts.latex or {}, {
        enabled = true,
        render_modes = false,
        converter = nil,
        highlight = "RenderMarkdownMath",
        position = "above",
        top_pad = 0,
        bottom_pad = 0,
      })

      -- Code block settings
      opts.code = vim.tbl_deep_extend("force", opts.code or {}, {
        sign = true,
      })

      -- Dash line config
      opts.dash = {
        enabled = true,
        render_modes = false,
        icon = "─",
        width = "full",
        left_margin = 0,
        highlight = "RenderMarkdownDash",
      }

      -- Pipe table settings
      opts.pipe_table = {
        preset = "round",
      }
    end,
  },
}
