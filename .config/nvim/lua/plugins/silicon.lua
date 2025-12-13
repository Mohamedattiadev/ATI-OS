return {
  {
    "michaelrommel/nvim-silicon",
    cmd = "Silicon",
    keys = {
      -- Copy to clipboard
      {
        "<leader>sc",
        function()
          require("nvim-silicon").clip({ theme = "Dracula" })
        end,
        mode = "v",
        desc = "Copy code screenshot to clipboard",
      },
      -- Save screenshot to ~/Screenshots with timestamp
      {
        "<leader>sf",
        function()
          require("nvim-silicon").file({ theme = "Dracula" })
        end,
        mode = "v",
        desc = "Save code screenshot as file",
      },
      -- Shoot screenshot to ~/Screenshots with timestamp
      {
        "<leader>ss",
        function()
          require("nvim-silicon").shoot({ theme = "Dracula" })
        end,
        mode = "v",
        desc = "Create code screenshot",
      },
    },
    opts = {
      theme = "Dracula",
      output = function()
        local dir = os.getenv("HOME") .. "/Screenshots"
        os.execute("mkdir -p " .. dir) -- ensure folder exists
        return dir .. "/" .. os.date("!%Y-%m-%dT%H-%M-%SZ") .. "_code.png"
      end,
      -- optional: font, line_offset, padding, etc.
      -- font = "FiraCode Nerd Font",
      -- line_offset = function(args) return args.line1 end,
    },
  },
}
