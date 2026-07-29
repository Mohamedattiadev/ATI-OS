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
