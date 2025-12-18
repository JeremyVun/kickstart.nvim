return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    build = "make tiktoken", -- Only on MacOS or Linux
    opts = {
      -- model = "claude-sonnet-4.5",
      -- model = "gpt-4.1",
      model = "gpt-4o",
      -- model = "raptor-mini",
      chat_autocomplete = false,
      mappings = {
        close = {
          normal = 'q',
          insert = '',
        }
      },
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}
