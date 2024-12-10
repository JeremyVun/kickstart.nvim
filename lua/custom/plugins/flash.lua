return {
  {
    'folke/flash.nvim',
    lazy = true,
    event = 'VeryLazy',
    config = function()
      vim.api.nvim_set_hl(0, 'FlashLabel', { bg = '#FF10F0', bold = true, fg = '#FFFFFF' })
    end,
    vscode = false,
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {
      { "<leader>fs",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "<leader>fS",     mode = { "n", "o", "x" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
    },
  },
}
