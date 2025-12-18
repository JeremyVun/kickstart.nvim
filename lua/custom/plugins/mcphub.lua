return {
  {
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    build = "npm install -g mcp-hub@latest",  -- Installs `mcp-hub` node binary globally
    config = function()
      require("mcphub").setup({
        global_env = function(context)
          return {
            GITHUB_READ_ONLY = "1",
            GITHUB_PERSONAL_ACCESS_TOKEN = os.getenv("GH_TOKEN"),
            GITHUB_TOOLSETS = "context,get_file_contents,get_commit,search_code,search_repositories,list_pull_requests,pull_request_read,search_pull_requests,users,git",
            ALLOWED_DIRECTORY = "Users/jeremy.vun/projects"
          }
        end,
        extensions = {
          copilotchat = {
              enabled = true,
              convert_tools_to_functions = true,     -- Convert MCP tools to CopilotChat functions
              convert_resources_to_functions = true, -- Convert MCP resources to CopilotChat functions  
              add_mcp_prefix = false,                -- Add "mcp_" prefix to function names
          }
        }
      })
    end
  }
}
