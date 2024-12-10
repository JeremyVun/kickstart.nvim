return {
  {
    "f-person/git-blame.nvim",
    event = "VeryLazy",
    config = function()
      require('gitblame').setup {
        schedule_event = "CursorHold",
        clear_event = "CursorHoldI"
      }
    end
  }
}
