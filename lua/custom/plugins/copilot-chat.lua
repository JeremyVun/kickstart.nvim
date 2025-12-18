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
      tools = {
        "copilot",
        "filesystem",
        "neovim",
        "time"
      },
      prompts = {
        research = {
          prompt = "Follow the instructions in research_codebase.md to create a document summarising your research findings. Use the filesystem tools to explore the project as needed",
          system_prompt = function()
            local file_path = vim.fn.getcwd() .. '/.prompts/research_codebase.md'
            if vim.fn.filereadable(file_path) == 0 then
              return "You are an AI programming assistant."
            end
            local file_content = vim.fn.readfile(file_path)
            return table.concat(file_content, '\n')
          end
        }
      }
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}
