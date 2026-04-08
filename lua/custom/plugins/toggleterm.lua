return {
  {
    'akinsho/toggleterm.nvim',
    version = "*",
    config = function()
      require("toggleterm").setup {
        auto_scroll = false,
        open_mapping = [[<C-`>]],
        direction = 'float',
        float_opts = {
          border = 'curved'
        }
      }
    end
  },
}
