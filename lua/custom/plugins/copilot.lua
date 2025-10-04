return {
  -- {
  --   "github/copilot.vim",
  --   -- lazy = true
  -- }

  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function ()
      require("copilot").setup({
        suggestion = {
          auto_trigger = true,
          keymap = {
            accept = "<M-\\>"
          },
        }
      })
    end
  }
}
