return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    build = "make tiktoken",
    opts = {
      model = "claude-3.7-sonnet-thought",
      -- model = "claude-3.7-sonnet",
      -- model = "gemini-2.0-flash-001",
      agent = 'copilot',
      chat_autocomplete = false,
      mappings = {
        close = {
          normal = 'q',
          insert = '',
        }
      }
    },
  },
}
