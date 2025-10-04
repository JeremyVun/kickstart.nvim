return {
  {
    "jim-fx/sudoku.nvim",
    cmd = "Sudoku",
    event = "VeryLazy",
    config = function()
      require("sudoku").setup({
      })
    end
  }
}
