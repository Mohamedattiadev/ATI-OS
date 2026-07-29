-- Read the foreground (or background) of an existing highlight group as
-- "#rrggbb", following links, and fall back when the active colorscheme
-- does not define it.
local function hl_color(name, attr, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl and hl[attr] then
    return string.format("#%06x", hl[attr])
  end
  return fallback
end

-- Heading/bullet colors, derived from whatever colorscheme is loaded.
--
-- These used to be literal doom-one hex values. Two problems with that:
-- this setup swaps between ~20 colorschemes via theme-apply, so markdown
-- kept rendering in doom-one purple/blue no matter the active theme; and,
-- worse, `:colorscheme` clears all user highlight groups, so defining
-- them once at plugin-setup time meant they were destroyed by the first
-- theme change -- verified: RenderMarkdownH1Bg reverted to its default
-- `link = "DiffText"`, i.e. headings lost their styling entirely until
-- the next nvim restart.
--
-- Fixed by sourcing each color from a standard syntax group (which every
-- colorscheme defines) and reapplying on every ColorScheme event. The
-- fallbacks are the previous hardcoded values, so a theme that is missing
-- a group renders exactly as it did before.
-- Groups to source heading/bullet hues from, most visually distinct first.
-- Deliberately weighted towards Diagnostic* over the classic syntax groups:
-- many themes link Function/Constant/String to a single color (dracula maps
-- all three to #f1fa8c), which would render H2, H3 and H5 as identical bars.
local COLOR_SOURCES = {
  "Statement",
  "DiagnosticInfo",
  "DiagnosticWarn",
  "Special",
  "DiagnosticError",
  "Type",
  "Identifier",
  "PreProc",
  "Constant",
  "Function",
  "String",
}

-- The previous hardcoded doom-one palette, still used to top up whenever a
-- colorscheme does not offer enough distinct hues.
local COLOR_FALLBACKS = {
  "#bd9cf9",
  "#51afef",
  "#ffb86c",
  "#c678dd",
  "#98be65",
  "#BF616A",
  "#D08770",
}

-- Collect `n` mutually distinct colors: theme-derived where possible, then
-- padded from the fallback palette. Duplicates are skipped rather than
-- accepted, so nesting levels never render in the same color as each other.
local function distinct_colors(n)
  local out, seen = {}, {}
  local function add(color)
    if #out >= n or color == nil then
      return
    end
    local key = color:lower()
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = color
    end
  end
  for _, group in ipairs(COLOR_SOURCES) do
    add(hl_color(group, "fg", nil))
  end
  for _, color in ipairs(COLOR_FALLBACKS) do
    add(color)
  end
  return out
end

local function apply_highlights()
  -- Dark text on a colored heading bar: use the theme's own background.
  local base_bg = hl_color("Normal", "bg", "#282c34")
  local heads = distinct_colors(7)

  for i = 1, 5 do
    vim.api.nvim_set_hl(0, "RenderMarkdownH" .. i .. "Bg", { bg = heads[i], fg = base_bg })
  end
  -- H6 stays inverted -- a subtle code-block-colored bar rather than a
  -- sixth loud stripe, matching the original design.
  vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", {
    bg = hl_color("CursorLine", "bg", "#1e222a"),
    fg = heads[2],
  })

  -- The plain RenderMarkdownH<n> groups are what heading.foregrounds
  -- points at, and despite the name they do NOT color the heading text --
  -- render/markdown/heading.lua uses them only for the sign-column icon
  -- (the bar and its text both come from the *Bg groups above). They were
  -- left undefined, so the sign icons rendered uncolored; tint each with
  -- its own heading hue.
  for i = 1, 6 do
    vim.api.nvim_set_hl(0, "RenderMarkdownH" .. i, { fg = heads[i] })
  end

  -- Checkbox states map onto diagnostic colors so they read as
  -- pending/done/info in every theme.
  vim.api.nvim_set_hl(0, "RenderMarkdownUnchecked", {
    fg = hl_color("DiagnosticWarn", "fg", "#EBCB8B"),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "RenderMarkdownChecked", {
    fg = hl_color("DiagnosticOk", "fg", "#A3BE8C"),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "RenderMarkdownTodo", {
    fg = hl_color("DiagnosticInfo", "fg", "#88C0D0"),
    bold = true,
  })
  vim.api.nvim_set_hl(0, "RenderMarkdownMath", {
    fg = hl_color("Type", "fg", "#B48EAD"),
    italic = true,
  })

  -- Rotating bullet colors, reusing the same distinct set (rotated by one
  -- so a level-1 bullet does not match the H1 bar it usually sits under).
  for i = 1, 7 do
    local color = heads[(i % 7) + 1]
    vim.api.nvim_set_hl(0, "RenderMarkdownBullet" .. i, { fg = color })
  end

  vim.api.nvim_set_hl(0, "RenderMarkdownDash", {
    fg = hl_color("Comment", "fg", "#4a6582"),
    bold = true,
  })
end

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    -- Icons come from nvim-web-devicons, not mini.nvim. render-markdown
    -- accepts either (lib/icons.lua tries mini.icons, then falls back to
    -- nvim-web-devicons), and devicons is already installed -- whereas
    -- depending on the mini.nvim monorepo dragged in duplicate copies of
    -- mini.files/ai/pairs/surround that shadowed the standalone plugins
    -- and silently discarded their config. See plugins/mini.lua.
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = function(_, opts)
      -- Markdown variants that share the markdown treesitter grammar, so
      -- headings/bullets render in them too. Previously this was pinned to
      -- { "markdown" } alone, which is why .rmd (filetype "rmd") and .qmd
      -- (filetype "quarto") opened completely unrendered.
      opts.file_types = opts.file_types or { "markdown", "rmd", "quarto" }

      -- Colors are theme-derived and must be re-established after every
      -- colorscheme swap, since :colorscheme wipes user highlight groups.
      apply_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("RenderMarkdownColors", { clear = true }),
        callback = apply_highlights,
      })

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
        -- Setext headings are the "underline" form: a paragraph followed
        -- immediately by a line of --- (H2) or === (H1). That is valid
        -- CommonMark, so a `---` written directly under a few lines of
        -- notes silently swallows them into one big heading bar instead
        -- of drawing a separator.
        --
        -- Off, because in these notes `---` is always meant as a divider.
        -- Only # headings are rendered as headings now.
        --
        -- Note this changes rendering, not parsing: the file is still a
        -- setext heading to any other markdown tool (GitHub included). To
        -- make `---` a real horizontal rule, leave a blank line above it
        -- -- then it parses as a thematic break and gets the full-width
        -- dash from opts.dash below.
        setext = false,
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
          -- Guard the tonumber: this runs inside the render path, so a
          -- marker that does not parse as a number (anything other than
          -- the expected "12." / "12)") made `index > 1` compare nil with
          -- a number and threw, which takes down rendering for the whole
          -- buffer rather than just that one list item.
          local index = tonumber(value:sub(1, #value - 1)) or ctx.index
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
