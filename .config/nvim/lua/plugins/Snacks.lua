return {
  "folke/snacks.nvim",
  opts = {

    -- ❌ remove all animation / motion effects
    animate = { enabled = false },
    scroll = { enabled = false },
    dim = { enabled = false },

    -- -- ❌ disable animated ui / popups
    -- notifier = { enabled = false },
    -- input    = { enabled = false },
    -- win      = { enabled = false },

    -- ❌ disable visual movement effects
    indent = { enabled = false },

    -- `enabled = false` only stops snacks installing the option itself;
    -- LazyVim points 'statuscolumn' at LazyVim.statuscolumn(), which calls
    -- snacks.statuscolumn.get() regardless. So this block IS live -- it is
    -- what draws the fold arrow.
    --
    -- folds.open defaults to false, so only CLOSED folds got an arrow. In an
    -- outline that reads as a bug: one heading showed the arrow while the
    -- heading right below it showed nothing, purely because its own body was
    -- already expanded. Drawing both states keeps the column consistent.
    statuscolumn = {
      enabled = false,
      folds = { open = true },
    },

    dashboard = {

      width = 82,

      preset = {
        header = [[
 ▄▄▄     ▓█▓▓█████ ██▓ ██▒   █▓ ██▓ ███▄ ▄███▓
▒████▄   ▓  ██▒  ▒▓██▒ ██░   █▒ ██▒ ██▒▀█▀ ██▒
▒██  ▀█▄   ▓██░ ▒░ ██▒ ▓██  █▒░ ██▒ ██    ▓██░
░██▄▄▄▄██  ▓██▓ ░ ░██░  ▒██ █░░ ██░▒██    ▒██ 
 ▓█   ▓██▒ ▒██▒ ░ ░██░   ▒▀█░  ░██░▒██▒   ░██▒
 ▒▒   ▓▒█░ ▒ ░░   ░▓     ░ ▐░  ░▓  ░ ▒░   ░  ░
 ░▒   ▒▒ ░   ░     ▒ ░   ░ ░░   ▒ ░░  ░      ░
  ░   ▒    ░       ▒ ░     ░░   ▒ ░░      ░   
      ░  ░         ░        ░   ░         ░   
                           ░                  

          A T I V I M — opus motus mentis
        ]],

        keys = {

          -------------------------------------------------------------------
          -- FIND FILE: LOCAL PROJECT
          -------------------------------------------------------------------
          {
            icon = " ",
            key = "f",
            desc = "Find File",
            action = function()
              require("snacks.dashboard").pick("files", {
                cwd = vim.fn.getcwd(), -- PROJECT
              })
            end,
          },

          -------------------------------------------------------------------
          -- FIND FILE: GLOBAL (HOME DIR)
          -------------------------------------------------------------------
          {
            icon = "+",
            key = "F",
            desc = "Find File (global)",
            action = function()
              require("snacks.dashboard").pick("files", {
                cwd = vim.fn.expand("~"), -- GLOBAL
              })
            end,
          },

          -------------------------------------------------------------------
          -- SEARCH TEXT: LOCAL PROJECT
          -------------------------------------------------------------------
          {
            icon = "󰈬 ",
            key = "g",
            desc = "Search Text",
            action = function()
              require("snacks.dashboard").pick("live_grep", {
                cwd = vim.fn.getcwd(), -- PROJECT
              })
            end,
          },

          -------------------------------------------------------------------
          -- SEARCH TEXT: GLOBAL
          -------------------------------------------------------------------
          {
            icon = "󰈬+",
            key = "G",
            desc = "Search Text (global)",
            action = function()
              require("snacks.dashboard").pick("live_grep", {
                cwd = vim.fn.expand("~"), -- GLOBAL
              })
            end,
          },

          -------------------------------------------------------------------
          -- RECENT FILES
          -------------------------------------------------------------------
          {
            icon = " ",
            key = "r",
            desc = "Recent",
            action = function()
              require("snacks.dashboard").pick("oldfiles")
            end,
          },

          -------------------------------------------------------------------
          -- CONFIG FILES
          -------------------------------------------------------------------
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = function()
              require("snacks.dashboard").pick("files", {
                cwd = vim.fn.stdpath("config"),
              })
            end,
          },

          -------------------------------------------------------------------
          -- LAZY
          -------------------------------------------------------------------
          { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },

          -------------------------------------------------------------------
          -- QUIT
          -------------------------------------------------------------------
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },

      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 2 },
        { section = "startup" },
      },
    },
  },
}
