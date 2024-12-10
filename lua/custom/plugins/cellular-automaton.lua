return {
  {
    'Eandrju/cellular-automaton.nvim',
    lazy = true,
    keys = {
      { '<leader>fml', '<cmd>CellularAutomaton make_it_rain<CR>', desc = "make it rain" },
      { '<leader>gol', '<cmd>CellularAutomaton game_of_life<CR>', desc = "game of life" },
    }
  }
}
