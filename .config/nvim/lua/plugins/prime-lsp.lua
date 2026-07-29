--------------------------------------------------------------------------
-- LSP
--------------------------------------------------------------------------
-- This file used to define `config = function() ... end` for
-- nvim-lspconfig, which REPLACES LazyVim's own config rather than extending
-- it. Two consequences, both measured:
--
--   1. LazyVim's `opts.servers` (11 entries contributed by the lang extras
--      in lazyvim.json -- vtsls/ts_ls, basedpyright, ruff, tailwind, json,
--      yaml, java ...) was assembled and then never applied.
--   2. Servers were started twice: once by the deprecated
--      `require("lspconfig")[server].setup()` framework, and once by
--      mason-lspconfig's `automatic_enable`. A single Lua buffer ended up
--      with two lua_ls clients plus a bogus `stylua` "LSP" client.
--
-- Now we only contribute `opts`, so LazyVim's config still runs and the
-- extras do their job. Server installation is handled by mason.lua.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Custom hover: render LSP hover markdown in a reusable bottom split
-- instead of a floating window.
--------------------------------------------------------------------------
local hover_state = {
  win = nil,
  buf = nil,
}

local function hover_in_split()
  -- make_position_params() requires an explicit position encoding on
  -- Neovim 0.11+; calling it bare emits a deprecation warning.
  local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/hover" })
  if #clients == 0 then
    return
  end
  local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding or "utf-16")

  vim.lsp.buf_request(0, "textDocument/hover", params, function(_, result)
    if not result or not result.contents then
      return
    end

    local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)

    -- Inline replacement for the deprecated vim.lsp.util.trim_empty_lines.
    while lines[1] and vim.trim(lines[1]) == "" do
      table.remove(lines, 1)
    end
    while lines[#lines] and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    if vim.tbl_isempty(lines) then
      return
    end

    -- validate window
    if hover_state.win and not vim.api.nvim_win_is_valid(hover_state.win) then
      hover_state.win = nil
    end

    -- validate buffer
    if hover_state.buf and not vim.api.nvim_buf_is_valid(hover_state.buf) then
      hover_state.buf = nil
    end

    -- create split if needed
    if not hover_state.win then
      vim.cmd("belowright split")
      hover_state.win = vim.api.nvim_get_current_win()
    end

    -- create buffer if needed
    if not hover_state.buf then
      hover_state.buf = vim.api.nvim_create_buf(false, true)

      vim.bo[hover_state.buf].filetype = "markdown"
      vim.bo[hover_state.buf].bufhidden = "wipe"
      vim.bo[hover_state.buf].swapfile = false

      -- q to close
      vim.keymap.set("n", "q", function()
        if hover_state.win and vim.api.nvim_win_is_valid(hover_state.win) then
          vim.api.nvim_win_close(hover_state.win, true)
        end
        hover_state.win = nil
        hover_state.buf = nil
      end, { buffer = hover_state.buf, silent = true })
    end

    -- attach buffer
    vim.api.nvim_win_set_buf(hover_state.win, hover_state.buf)

    vim.bo[hover_state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(hover_state.buf, 0, -1, false, lines)
    vim.bo[hover_state.buf].modifiable = false

    -- window options
    vim.wo[hover_state.win].wrap = true
    vim.wo[hover_state.win].linebreak = true
  end)
end

local root_files = {
  ".luarc.json",
  ".luarc.jsonc",
  ".luacheckrc",
  ".stylua.toml",
  "stylua.toml",
  "selene.toml",
  "selene.yml",
  ".git",
}

return {
  {
    "neovim/nvim-lspconfig",

    -- Registered in `init` (a proper lazy.nvim hook) rather than at file
    -- scope, so the autocmd is not a side effect of parsing the spec.
    init = function()
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("ati_lsp_keymaps", { clear = true }),
        callback = function(ev)
          -- Go to definition via telescope
          vim.keymap.set("n", "<leader>gd", function()
            require("telescope.builtin").lsp_definitions({
              jump_type = "never",
            })
          end, { buffer = ev.buf, desc = "Go to definition (Telescope)" })

          -- Hover in bottom split (NO FLOAT)
          vim.keymap.set("n", "K", hover_in_split, { buffer = ev.buf, desc = "Hover (bottom split)" })
        end,
      })
    end,

    opts = {
      diagnostics = {
        float = {
          focusable = false,
          style = "minimal",
          border = "rounded",
          -- `source = "always"` is the old spelling; the current API is a boolean.
          source = true,
          header = "",
          prefix = "",
        },
      },

      -- Only override what LazyVim's extras do not already set. html,
      -- cssls, bashls, pyright/basedpyright, ts_ls/vtsls and tailwindcss all
      -- come from the extras enabled in lazyvim.json.
      servers = {
        lua_ls = {
          root_markers = root_files,
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              format = {
                enable = true,
                defaultConfig = {
                  indent_style = "space",
                  indent_size = "2",
                },
              },
            },
          },
        },
      },
    },
  },

  -- LSP progress UI. Previously set up by hand inside the replaced config
  -- function; it gets a normal spec now.
  { "j-hui/fidget.nvim", event = "LspAttach", opts = {} },
}
