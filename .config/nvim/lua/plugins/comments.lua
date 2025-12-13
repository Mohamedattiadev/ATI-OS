return {
  "numToStr/Comment.nvim",
  event = "InsertEnter",
  opts = {
    -- add any options here
  },
  config = function()
    local Comment = require("Comment")

    Comment.setup()
  end,
}
