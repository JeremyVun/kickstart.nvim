return {
  {
    'mcchrish/zenbones.nvim',
    dependencies = {
      'rktjmp/lush.nvim'
    },
    config = function()
      vim.g.zenwritten = {
        colorize_diagnostic_underline_text = true,
      }

      local lush = require("lush")
      local base = require("zenwritten")

      local specs = lush.extends({base}).with(function()
        return {
          Statement { fg = '#BB7777' },
          Type { fg = '#64A0C8' },
          Identifier { fg = '#999999' },
          Function { fg = '#C0B078' },
          Title { fg = '#64A0C8' },
        }
      end)

      lush(specs)
    end
  }
}
