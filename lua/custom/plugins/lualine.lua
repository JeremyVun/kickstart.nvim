return {
  {
    'nvim-lualine/lualine.nvim',
    lazy = true,
    event = 'VeryLazy',
    dependencies = {
      {
        'linrongbin16/lsp-progress.nvim'
      }
    },
    -- init = function()
    --   vim.g.lualine_laststatus = vim.o.laststatus
    --   if vim.fn.argc(-1) > 0 then
    --     -- set an empty statusline till lualine loads
    --     vim.o.statusline = ' '
    --   else
    --     -- hide the statusline on the starter page
    --     vim.o.laststatus = 0
    --   end
    -- end,
    opts = function()
      return {
        options = {
          theme = 'auto',
          globalstatus = false,
          disabled_filetypes = { statusline = { 'dashboard', 'alpha', 'starter' } },
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'branch' },
          lualine_c = {
            { 'filename', separator = '', padding = { left = 1, right = 1 } },
            { 'filesize' },
            {
              'diagnostics',
              sources = { 'nvim_lsp' },
              symbols = {
                Error = ' ',
                Warn = ' ',
                Hint = ' ',
                Info = ' ',
              },
            },
          },
          lualine_x = {
            {
              function()
                return "  " .. require("dap").status()
              end,
              cond = function()
                return package.loaded["dap"] and require("dap").status() ~= ""
              end,
              color = {},
            },
            {
              require('lazy.status').updates,
              cond = require('lazy.status').has_updates,
              color = { fg = '#ff9e64' },
            },
            {
              function()
                return require('lsp-progress').progress {
                  format = function(client_messages)
                    if #client_messages > 0 then
                      return table.concat(client_messages, ' ')
                    end
                    local clients = vim.lsp.get_clients()
                    if #clients > 0 then
                      local client_names = vim.tbl_map(function(client)
                        return '[' .. client.name .. ']'
                      end, clients)
                      return table.concat(client_names, ' ')
                    end
                  end
                }
              end,
              separator = '',
              padding = { right = 0 },
            },
            { 'filetype', separator = '', padding = { left = 1, right = 0 } },
            { 'encoding' },
          },
          lualine_y = {
            { 'progress', separator = ' ', padding = { left = 1, right = 0 } },
            { 'location', padding = { left = 0, right = 1 } },
          },
          lualine_z = {
            function()
              return ' ' .. os.date '%R'
            end,
          },
        },
        extensions = { 'neo-tree', 'lazy' },
      }
    end,
  },
}
