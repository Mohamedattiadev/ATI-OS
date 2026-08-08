return {
  -- The mini.nvim *monorepo* ships every mini module at lua/mini/<mod>.lua,
  -- which is the exact same require path the standalone plugins use. With
  -- both installed there are two copies of mini.files, mini.ai, mini.pairs
  -- and mini.surround on the runtimepath, and `require("mini.files")`
  -- resolves to whichever one lands there first.
  --
  -- mini.nvim always won that race: it has no lazy trigger (and was pulled
  -- in eagerly as a render-markdown dependency), while the standalone
  -- plugins load on demand. The result was that this config's own
  -- miniFiles.lua opts were silently discarded -- verified by inspecting
  -- the live config: mini.files reported preview=false / width_preview=25
  -- (upstream defaults) instead of the configured preview=true /
  -- width_preview=80, so the explorer had no preview column at all.
  --
  -- Nothing here uses a module that exists only in the monorepo, so it is
  -- disabled rather than deleted: kept as an explicit marker, and it stays
  -- off even if a future plugin re-declares it as a dependency.
  { "nvim-mini/mini.nvim", enabled = false },

  -- Quote / backtick autopairing that can tell an opener from a closer.
  --
  -- LazyVim already passes `skip_unbalanced = true`, but its implementation
  -- guards on `c ~= o`, so it only ever applies to () [] {} -- never to " ' `,
  -- whose opening and closing characters are the same. Those are precisely
  -- the ones that misbehave when writing prose:
  --
  --   type  "  before a word  ->  no pair (skip_next sees the letter),
  --                               leaving  say "Hello
  --   type  "  at end of line ->  pairs again  ->  say "Hello""
  --
  -- The rule below: if the line already holds an odd number of that
  -- character, the one being typed is closing it, so emit a single character
  -- instead of a pair. An even count means a fresh pair, and pairs normally.
  {
    "nvim-mini/mini.pairs",
    config = function(_, opts)
      -- LazyVim's wrapper first (skip_next / skip_ts / skip_unbalanced, and
      -- the ``` fence expansion), then ours layered outside it.
      LazyVim.mini.pairs(opts)

      local pairs_mod = require("mini.pairs")
      local open = pairs_mod.open
      -- Quotes are mapped to the "closeopen" action, not "open" -- but
      -- MiniPairs.closeopen() falls through to MiniPairs.open() whenever it
      -- is not simply moving over an adjacent closing character, so patching
      -- open() is enough to cover them.
      pairs_mod.open = function(pair, neigh_pattern)
        local o, c = pair:sub(1, 1), pair:sub(2, 2)
        -- Same-character pairs only, and never while typing a : command.
        if o == c and vim.fn.getcmdline() == "" then
          local _, count = vim.api.nvim_get_current_line():gsub(vim.pesc(o), "")
          if count % 2 == 1 then
            return o
          end
        end
        return open(pair, neigh_pattern)
      end
    end,
  },
  -- event = "InsertEnter",
  -- {
  --   "nvim-mini/mini.ai",
  --   event = "InsertEnter",
  --   version = false,
  --   config = function()
  --     require("mini.ai").setup()
  --   end,
  -- },
}
