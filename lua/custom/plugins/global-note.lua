return {
  {
    'backdround/global-note.nvim',
    lazy = true,
    keys = '<leader>n',
    config = function()
      local global_note = require('global-note')
      global_note.setup({
        filename = "global.md",
        additional_presets = {
          ref = {
            filename = "ref.md",
            title = "Reference",
            command_name = "RefNote"
          },
          apis = {
            filename = "apis.md",
            title = "Api docs",
            command_name ="ApieNote"
          }
        },
      })
      vim.keymap.set('n', '<leader>nr', function() global_note.toggle_note("ref") end, { desc = 'Toggle reference notes' })
      vim.keymap.set('n', '<leader>np', function() global_note.toggle_note("apis") end, { desc = 'Toggle api notes' })
      vim.keymap.set('n', '<leader>nn', global_note.toggle_note, { desc = 'Toggle global notes' })
    end
  }
}
