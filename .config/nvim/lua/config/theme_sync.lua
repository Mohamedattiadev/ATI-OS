-- Single source of truth for "what does the desktop theme mean in nvim".
--
-- `theme-apply` writes the active mode to ~/.cache/qtile/theme_mode and the
-- 9-slot palette it just painted the bar, GTK, btop, qt and glow with to
-- ~/.cache/qtile/current_palette.json. Everything here reads those two files
-- so nvim lands on the same colours as the rest of the desktop.
--
-- This module used to be two maps in themes.lua that disagreed with each
-- other -- LazyVim's `opts.colorscheme` said tokyonight meant "nord" while
-- the doom-one config said it meant "tokyonight". Both are built from
-- `scheme_of` now, so they cannot drift apart again.

local M = {}

M.mode_file = vim.fn.expand("~/.cache/qtile/theme_mode")
M.wal_cache = vim.fn.expand("~/.cache/wal/colors-wal.vim")
M.wal_json = vim.fn.expand("~/.cache/wal/colors.json")
M.palette_json = vim.fn.expand("~/.cache/qtile/current_palette.json")

M.fallback = "doom-one"

-- Desktop mode -> installed nvim colorscheme. `theme-apply` knows 22 modes;
-- only the ones listed here ship a plugin. Everything else (matrix,
-- synthwave, mono-*, github-dark, nightowl, ...) is rendered directly from
-- current_palette.json by apply_palette() below, which is why those modes
-- still each look different instead of collapsing onto one fallback.
--
-- catppuccin is deliberately absent: lua/plugins/disabled.lua turns the
-- plugin off, so the mode takes the palette path.
M.scheme_of = {
  wal = "wal",
  doomone = "doom-one",
  dracula = "dracula",
  gruvbox = "gruvbox",
  nord = "nord",
  tokyonight = "tokyonight",
  monokai = "monokai-pro",
  everforest = "everforest",
  ["rose-pine"] = "rose-pine",
  kanagawa = "kanagawa",
  oxocarbon = "oxocarbon",
}

-- colorscheme name -> lazy.nvim plugin dir, for on-demand loading.
M.plugin_of = {
  ["doom-one"] = "doom-one.nvim",
  dracula = "dracula.nvim",
  gruvbox = "gruvbox.nvim",
  nord = "nord.nvim",
  tokyonight = "tokyonight.nvim",
  ["monokai-pro"] = "monokai-pro.nvim",
  everforest = "everforest-nvim",
  ["rose-pine"] = "rose-pine",
  kanagawa = "kanagawa.nvim",
  oxocarbon = "oxocarbon.nvim",
  wal = "wal.vim",
}

function M.read_mode()
  local ok, f = pcall(io.open, M.mode_file, "r")
  if not (ok and f) then
    return nil
  end
  local m = (f:read("*l") or ""):gsub("%s+", "")
  f:close()
  return m ~= "" and m or nil
end

function M.scheme_for(mode)
  return mode and M.scheme_of[mode] or nil
end

local function read_json(path)
  local ok, f = pcall(io.open, path, "r")
  if not (ok and f) then
    return nil
  end
  local raw = f:read("*a")
  f:close()
  local ok2, d = pcall(vim.json.decode, raw)
  return ok2 and d or nil
end

-- The 9 semantic slots, from whichever source describes the current mode.
function M.read_palette()
  local d = read_json(M.palette_json)
  if d and d.bg and d.fg and d.red then
    return d
  end
  return nil
end

function M.read_wal_palette()
  local d = read_json(M.wal_json)
  if not (d and d.colors and d.special) then
    return nil
  end
  local c = d.colors
  return {
    mode = "wal",
    bg = d.special.background,
    -- wal emits color0 == background, so bg_alt would collapse into bg;
    -- color8 is the nearest thing to a raised surface it gives us.
    bg_alt = c.color0,
    fg = d.special.foreground,
    grey = c.color8,
    red = c.color1,
    -- color2 is wal-precompile's dominant wallpaper hue -- the same slot
    -- the qtile bar and the brave accent use, so branding matches.
    green = c.color2,
    yellow = c.color3,
    blue = c.color4,
    purple = c.color5,
    cyan = c.color6,
    -- Same slot theme-apply hands GTK in wal mode: the bright variant of
    -- the wallpaper's dominant hue.
    accent = c.color12 or c.color2,
  }
end

-- Last resort when the palette file is stale or missing: read the colours
-- back out of whatever colorscheme is currently loaded. Always available,
-- always consistent with what is on screen, just not necessarily identical
-- to the bar.
function M.palette_from_hl()
  local function fg(group, fallback)
    local h = vim.api.nvim_get_hl(0, { name = group, link = false })
    return h and h.fg and string.format("#%06x", h.fg) or fallback
  end
  local function bg(group, fallback)
    local h = vim.api.nvim_get_hl(0, { name = group, link = false })
    return h and h.bg and string.format("#%06x", h.bg) or fallback
  end
  local normal_fg = fg("Normal", "#dcdfe4")
  return {
    mode = vim.g.colors_name or "unknown",
    bg = bg("Normal", "#282c34"),
    bg_alt = bg("CursorLine", bg("Normal", "#1e222a")),
    fg = normal_fg,
    grey = fg("Comment", "#5b6268"),
    red = fg("Statement", "#ff6c6b"),
    green = fg("String", "#98be65"),
    yellow = fg("Constant", "#ecbe7b"),
    blue = fg("Function", "#51afef"),
    purple = fg("Type", "#c678dd"),
    cyan = fg("Special", "#46d9ff"),
    -- No published accent to read here, so use the scheme's function
    -- colour: the closest thing a colorscheme has to a signature hue.
    accent = fg("Function", "#51afef"),
  }
end

local function set(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

local function rgb(hx)
  hx = tostring(hx):gsub("#", "")
  if #hx ~= 6 then
    return nil
  end
  return tonumber(hx:sub(1, 2), 16), tonumber(hx:sub(3, 4), 16), tonumber(hx:sub(5, 6), 16)
end

-- Relative luminance, WCAG definition.
local function luminance(hx)
  local r, g, b = rgb(hx)
  if not r then
    return nil
  end
  local function lin(c)
    c = c / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if not (la and lb) then
    return 21
  end
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

local function mix(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg_, bb = rgb(b)
  if not (ar and br) then
    return a
  end
  return string.format(
    "#%02x%02x%02x",
    math.floor(ar + (br - ar) * t + 0.5),
    math.floor(ag + (bg_ - ag) * t + 0.5),
    math.floor(ab + (bb - ab) * t + 0.5)
  )
end

-- De-emphasised text -- the dashboard footer, comments, line numbers -- needs
-- a colour dimmer than fg but still READABLE.
--
-- The obvious pick is the palette's own grey slot, and in wal mode that is
-- whatever colour8 the wallpaper happened to produce. On a dark wallpaper
-- that lands at something like #1c1f26 against a #0d1014 background: a
-- contrast ratio near 1.2, i.e. invisible. Blend fg toward bg instead, which
-- sits mid-contrast whichever end of the spectrum the theme is on. Same
-- reasoning as gen_glow_style() in theme-apply.
function M.muted(grey, fg, bg)
  if grey and contrast(grey, bg) >= 2.5 then
    return grey
  end
  return mix(fg, bg, 0.55)
end

-- Dashboard, picker and sidebar groups.
--
-- This is the part that was missing. The wal and palette paths painted these
-- groups, but a plugin colorscheme -- oxocarbon, dracula, kanagawa, ... --
-- never did, and none of those plugins define the Snacks groups themselves.
-- So the ATIVIM banner and the menu rendered in plain `Normal` grey and the
-- dashboard looked identical no matter which theme you picked, which reads
-- exactly like "changing the theme did nothing".
--
-- Applied on top of every scheme, from a ColorScheme autocmd so it survives
-- a later `:colorscheme` too.
function M.apply_accents(p)
  -- No `or p.purple` here, unlike the syntax groups below. The 9-slot
  -- palette has no grey, so falling back to purple made the footer land on
  -- the accent itself for the themes whose accent IS the purple slot
  -- (rose-pine, catppuccin) -- footer and banner came out the same colour.
  -- Dashboard chrome gets a real blend toward the background instead.
  local grey = M.muted(p.grey, p.fg, p.bg)
  -- theme-apply dumps `accent` -- the same colour it hands GTK and the
  -- qtile GroupBox. It is not a fixed slot of the 9 (blue for oxocarbon,
  -- yellow for gruvbox, purple for rose-pine), which is why it is published
  -- rather than guessed. Fall back to green for a palette written by an
  -- older theme-apply that predates the field.
  local accent = p.accent or p.green
  local branding = {
    DashboardHeader = { fg = accent, bold = true },
    DashboardIcon = { fg = accent },
    DashboardDesc = { fg = p.fg },
    DashboardKey = { fg = p.red },
    DashboardFooter = { fg = grey, italic = true },
    DashboardProjectTitle = { fg = accent, bold = true },
    SnacksDashboardHeader = { fg = accent, bold = true },
    SnacksDashboardIcon = { fg = accent },
    SnacksDashboardDesc = { fg = p.fg },
    SnacksDashboardKey = { fg = p.red },
    SnacksDashboardFooter = { fg = grey, italic = true },
    SnacksDashboardTitle = { fg = accent, bold = true },
    SnacksDashboardFile = { fg = p.fg },
    SnacksDashboardDir = { fg = grey },
    SnacksDashboardSpecial = { fg = accent },
    AlphaHeader = { fg = accent, bold = true },
    AlphaButtons = { fg = p.fg },
    AlphaShortcut = { fg = p.red },
    StartifyHeader = { fg = accent, bold = true },
  }
  for g, o in pairs(branding) do
    set(g, o)
  end
end

-- Everything apply_accents does, plus the base editor groups. Used for the
-- modes with no plugin of their own.
function M.apply_palette(p)
  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end
  vim.o.background = (p.mode == "mono-light") and "light" or "dark"
  vim.g.colors_name = "qtile-" .. (p.mode or "preset")

  local grey = M.muted(p.grey or p.purple, p.fg, p.bg)
  local accent = p.accent or p.green
  local base = {
    Normal = { fg = p.fg, bg = p.bg },
    NormalFloat = { fg = p.fg, bg = p.bg_alt },
    NormalNC = { fg = p.fg, bg = p.bg },
    SignColumn = { fg = p.fg, bg = p.bg },
    EndOfBuffer = { fg = p.bg, bg = p.bg },
    LineNr = { fg = grey, bg = p.bg },
    CursorLineNr = { fg = p.yellow, bg = p.bg, bold = true },
    CursorLine = { bg = p.bg_alt },
    Visual = { bg = p.bg_alt },
    Comment = { fg = grey, italic = true },
    Constant = { fg = p.yellow },
    String = { fg = p.green },
    Statement = { fg = p.red },
    Keyword = { fg = p.red },
    Function = { fg = p.blue },
    Type = { fg = p.purple },
    Special = { fg = p.cyan },
    PreProc = { fg = p.yellow },
    Identifier = { fg = p.red },
    StatusLine = { fg = p.fg, bg = p.bg_alt },
    StatusLineNC = { fg = grey, bg = p.bg_alt },
    TabLine = { fg = grey, bg = p.bg_alt },
    TabLineSel = { fg = p.bg, bg = p.blue, bold = true },
    TabLineFill = { bg = p.bg_alt },
    WinSeparator = { fg = grey, bg = p.bg },
    Pmenu = { fg = p.fg, bg = p.bg_alt },
    PmenuSel = { fg = p.bg, bg = p.blue, bold = true },
    PmenuThumb = { bg = p.blue },
    Search = { fg = p.bg, bg = p.yellow },
    IncSearch = { fg = p.bg, bg = p.cyan },
    MatchParen = { fg = p.cyan, bold = true },
    DiagnosticError = { fg = p.red },
    DiagnosticWarn = { fg = p.yellow },
    DiagnosticInfo = { fg = p.blue },
    DiagnosticHint = { fg = p.cyan },
    Error = { fg = p.red, bold = true },
    WarningMsg = { fg = p.yellow },
    NeoTreeNormal = { fg = p.fg, bg = p.bg },
    TelescopeNormal = { fg = p.fg, bg = p.bg },
    TelescopeBorder = { fg = accent, bg = p.bg },
    TelescopeSelection = { fg = p.fg, bg = p.bg_alt, bold = true },
    WhichKeyGroup = { fg = accent },
    WhichKeyDesc = { fg = p.fg },
    WhichKey = { fg = p.red },
    BufferLineFill = { bg = p.bg_alt },
    DiffAdd = { fg = p.green },
    DiffChange = { fg = p.yellow },
    DiffDelete = { fg = p.red },
    GitSignsAdd = { fg = p.green },
    GitSignsChange = { fg = p.yellow },
    GitSignsDelete = { fg = p.red },
  }
  for g, o in pairs(base) do
    set(g, o)
  end
  M.apply_accents(p)
end

return M
