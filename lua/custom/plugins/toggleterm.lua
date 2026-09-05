return {
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    -- Terminal Panel owns the workspace. Keep this spec for an easy rollback.
    enabled = false,
    config = function()
      require('toggleterm').setup {
        auto_scroll = false,
        open_mapping = [[<C-`>]],
        direction = 'float',
        float_opts = {
          border = 'curved',
        },
      }
    end,
  },
}
