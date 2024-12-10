return {
  {
    'stevearc/aerial.nvim',
    lazy = true,
    keys = {
      { '<leader>a', '<cmd>AerialToggle!<CR>', desc = 'Toggle Aerial' }
    },
    config = function()
      require("aerial").setup({
        on_atach = function(bufnr)
          vim.keymap.set('n', '}', '<cmd>AerialNext<CR>', { buffer = bufnr })
          vim.keymap.set('n', '{', '<cmd>AerialPrev<CR>', { buffer = bufnr })
        end
      })
    end,
    opts = {},
    dependenties = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons"
    },
  }
}
