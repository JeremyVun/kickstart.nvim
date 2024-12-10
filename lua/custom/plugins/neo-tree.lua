return {
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    cmd = 'Neotree',
    lazy = false,
    deactivate = function()
      vim.cmd [[Neotree close]]
    end,
    init = function()
      if vim.fn.argc(-1) == 1 then
        local stat = vim.uv.fs_stat(vim.fn.argv(0))
        if stat and stat.type == 'directory' then
          require 'neo-tree'
        end
      end
    end,
    opts = {
      sources = { 'filesystem', 'buffers', 'git_status', 'document_symbols' },
      open_files_do_not_replace_types = { 'terminal', 'Trouble', 'trouble', 'qf', 'Outline' },
      filesystem = {
        bind_to_cwd = false,
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        hijack_netrw_behavior = 'open_default',
      },
      window = {
        mappings = {
          ['<space>'] = 'none',
          ['Y'] = {
            function(state)
              local node = state.tree:get_node()
              local path = node:get_id()
              vim.fn.setreg('+', path, 'c')
            end,
            desc = 'Copy Path to Clipboard',
          },
          ['O'] = {
            function(state)
              require('lazy.util').open(state.tree:get_node().path, { system = true })
            end,
            desc = 'Open with System Application',
          },
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true, -- if nil and file nesting is enabled, will enable expanders
          expander_collapsed = '',
          expander_expanded = '',
          expander_highlight = 'NeoTreeExpander',
        },
      },
    },
    config = function(_, opts)
      local function get_clients(opts)
        local ret = {} ---@type lsp.Client[]
        if vim.lsp.get_clients then
          ret = vim.lsp.get_clients(opts)
        else
          ---@diagnostic disable-next-line: deprecated
          ret = vim.lsp.get_active_clients(opts)
          if opts and opts.method then
            ---@param client lsp.Client
            ret = vim.tbl_filter(function(client)
              return client.supports_method(opts.method, { bufnr = opts.bufnr })
            end, ret)
          end
        end
        return opts and opts.filter and vim.tbl_filter(opts.filter, ret) or ret
      end

      local function on_move(data)
        local clients = get_clients()
        for _, client in ipairs(clients) do
          if client.supports_method 'workspace/willRenameFiles' then
            ---@diagnostic disable-next-line: invisible
            local resp = client.request_sync('workspace/willRenameFiles', {
              files = {
                {
                  oldUri = vim.uri_from_fname(data.source),
                  newUri = vim.uri_from_fname(data.destination),
                },
              },
            }, 1000, 0)
            if resp and resp.result ~= nil then
              vim.lsp.util.apply_workspace_edit(resp.result, client.offset_encoding)
            end
          end
        end
      end

      local events = require 'neo-tree.events'
      -- opts.event_handlers = opts.event_handlers or {}
      -- vim.list_extend(opts.event_handlers, {
      --   { event = events.FILE_MOVED, handler = on_move },
      --   { event = events.FILE_RENAMED, handler = on_move },
      -- })

      require('neo-tree').setup(opts)

      vim.api.nvim_create_autocmd('TermClose', {
        pattern = '*lazygit',
        callback = function()
          if package.loaded['neo-tree.sources.git_status'] then
            require('neo-tree.sources.git_status').refresh()
          end
        end,
      })
    end,
  },
}
