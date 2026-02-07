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
  "neovim/nvim-lspconfig",
  dependencies = {
    "j-hui/fidget.nvim",
    "stevearc/conform.nvim",

    -- Mason is handled elsewhere, but required as dependency
    "mason-org/mason.nvim",
    "mason-org/mason-lspconfig.nvim",
  },

  config = function()
    local lspconfig = require("lspconfig")

    --------------------------------------------------------------------
    -- CAPABILITIES (Blink-compatible)
    --------------------------------------------------------------------
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local ok, blink = pcall(require, "blink.cmp")
    if ok then
      capabilities = blink.get_lsp_capabilities(capabilities)
    end

    --------------------------------------------------------------------
    -- UI + FORMAT
    --------------------------------------------------------------------
    require("fidget").setup({})
    require("conform").setup({ formatters_by_ft = {} })

    --------------------------------------------------------------------
    -- LSP SERVERS YOU ACTUALLY WANT
    -- (Mason handles installation; we only configure them)
    --------------------------------------------------------------------
    local servers = {
      "lua_ls",
      "pyright",
      "ts_ls",
      "html",
      "cssls",
      "bashls",
    }

    --------------------------------------------------------------------
    -- GENERIC CONFIG FOR ALL SERVERS
    --------------------------------------------------------------------
    for _, server in ipairs(servers) do
      lspconfig[server].setup({
        capabilities = capabilities,
      })
    end

    --------------------------------------------------------------------
    -- SPECIAL CASE: LUA (Prime-style)
    --------------------------------------------------------------------
    lspconfig.lua_ls.setup({
      capabilities = capabilities,
      root_dir = lspconfig.util.root_pattern(unpack(root_files)),
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
    })

    --------------------------------------------------------------------
    -- SPECIAL CASE: Tailwind
    --------------------------------------------------------------------
    if lspconfig.tailwindcss then
      lspconfig.tailwindcss.setup({
        capabilities = capabilities,
        filetypes = {
          "html",
          "css",
          "scss",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "vue",
        },
      })
    end

    --------------------------------------------------------------------
    -- PRIMEAGEN DIAGNOSTIC STYLE
    --------------------------------------------------------------------
    vim.diagnostic.config({
      float = {
        focusable = false,
        style = "minimal",
        border = "rounded",
        source = "always",
        header = "",
        prefix = "",
      },
    })

    --------------------------------------------------------------------
    -- LSP KEYMAPS (buffer-local, safe)
    --------------------------------------------------------------------
    ---

    local hover_state = {
      win = nil,
      buf = nil,
    }

    local function hover_in_split()
      local params = vim.lsp.util.make_position_params()

      vim.lsp.buf_request(0, "textDocument/hover", params, function(_, result)
        if not result or not result.contents then
          return
        end

        local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
        lines = vim.lsp.util.trim_empty_lines(lines)
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

        -- 🔥 THIS IS THE FIX
        vim.bo[hover_state.buf].modifiable = true
        vim.api.nvim_buf_set_lines(hover_state.buf, 0, -1, false, lines)
        vim.bo[hover_state.buf].modifiable = false

        -- window options
        vim.wo[hover_state.win].wrap = true
        vim.wo[hover_state.win].linebreak = true
      end)
    end

    ---
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(ev)
        -- Go to definition
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
}
