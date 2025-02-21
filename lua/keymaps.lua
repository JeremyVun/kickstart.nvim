local function map(modes, key, action, desc)
  vim.keymap.set(modes, key, action, desc)
end

-- [[ LSP Keymaps ]]
map('n','l', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic' })
map('n','k', vim.diagnostic.goto_prev, { desc = 'Go to prev diagnostic' })
map('n','<leader>t', vim.diagnostic.open_float, { desc = 'Show diagnostics' })

-- [[ Buffer keymaps ]]
map('n','<leader>`', '<cmd>e #<cr>', { desc = 'switch to last buffer' })
map('n','<leader>bd', function()
  local bd = require('mini.bufremove').delete
  if vim.bo.modified then
    local choice = vim.fn.confirm(('Save changes to %q?'):format(vim.fn.bufname()), '&Yes\n&No\n&Cancel')
    if choice == 1 then
      vim.cmd.write()
      bd(0)
    elseif choice == 2 then
      bd(0, true)
    end
  else
    bd(0)
  end
end, { desc = 'Close buffer' })

map('n', '<leader>wd', ':q<CR>', { desc = 'Close window' })

-- [[ Terminal keymaps ]]
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- [[ Nav keymaps ]]
map('n','<PageUp>', '<PageUp>zz')
map('n','<PageDown>', '<PageDown>zz')
map('n','n', 'nzzzV')
map('n','N', 'NzzzV')

map('n','<leader><Left>', '<C-w><C-h>', { desc = 'Move focus left'})
map('n','<leader><Right>', '<C-w><C-l>', { desc = 'Move focus right'})
map('n','<leader><Up>', '<C-w><C-k>', { desc = 'Move focus up'})
map('n','<leader><Down>', '<C-w><C-j>', { desc = 'Move focus down'})

-- Global marks
map('n','ma', 'mA', { desc = 'set Mark A' })
map('n','`a', '`A', { desc = 'goto Mark A' })
map('n','mb', 'mB', { desc = 'set Mark B' })
map('n','`b', '`B', { desc = 'goto Mark B' })
map('n','mc', 'mC', { desc = 'set Mark C' })
map('n','`c', '`C', { desc = 'goto Mark C' })
map('n','md', 'mD', { desc = 'set Mark D' })
map('n','`d', '`D', { desc = 'goto Mark D' })

-- [[ Text manipulation keymaps ]]
map('n','<leader>sr', ':%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>', { desc = 'Search and replace word under cursor in current buffer' })
map('n','<leader>sw', '/<C-r><C-w><CR>', { desc = 'search word under cursor in current buffer'})

map('x', 'p', '"_dP"', { desc = 'delete to blackhole register' })
map('n', 'd', '"_d', { desc = 'delete to blackhole register' })
map('v', 'd', '"_d', { desc = 'delete to blackhole register' })
map('n', 'D', '"_D', { desc = 'delete to blackhole register' })
map('v', 'D', '"_D', { desc = 'delete to blackhole register' })
map('n', '<c-a>', 'ggVG', { desc = 'select all' })

map('v', '<leader>=', vim.lsp.buf.format, { desc = 'auto format buffer' })
map('n', '<esc>', ':nohl<cr>', { desc = 'clear search highlights' })

-- [[ Plugin keymaps ]]

-- Markdown Preview
map('n','<leader>md', ':<c-u>MarkdownPreview<cr>', { desc = 'open md file in browser' })

-- neotree
map('n', '<leader>e', function()
  require("neo-tree.command").execute({ toggle = true })
end, { desc = 'Toggle neotree' })

-- kulala
map('n', '<leader>rr', ":Rest run<cr>", { desc = 'Run http request' })
map('n', '<leader>re', ":Rest env select", { desc = 'Select rest nvim env' })
