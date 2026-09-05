-- Run: nvim --headless -u NONE -l tests/terminal_panel_adopt.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/toggleterm.nvim')
vim.g.mapleader = ' '
require('toggleterm').setup { direction = 'float', open_mapping = '<C-`>', auto_scroll = false }
local terminal = require('toggleterm.terminal').Terminal:new { cmd = 'cat', display_name = 'Existing agent' }
terminal:open()
local job, buf = terminal.job_id, terminal.bufnr
local panel = require 'terminal_panel'
panel.setup { auto_open = false, tab_title = false }
local sessions = panel.snapshot().sessions
assert(#sessions == 1 and sessions[1].buf == buf and sessions[1].job == job, 'Adopt exact buffer and process')
assert(sessions[1].name == 'Existing agent', 'Keep terminal name')
assert(sessions[1].status == 'unknown', 'Do not invent agent state')
panel.open(1)
assert(vim.api.nvim_get_current_buf() == buf, 'Display adopted terminal')
vim.fn.chansend(job, 'still running\n')
assert(
  vim.wait(1500, function()
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find('still running', 1, true) ~= nil
  end),
  'Original process still receives input'
)
assert(panel.adopt() == 0, 'Adoption is idempotent')
vim.fn.jobstop(job)
assert(
  vim.wait(1500, function()
    return panel.snapshot().sessions[1].status == 'exited'
  end),
  'Adopted exit tracked'
)
assert(vim.api.nvim_buf_is_valid(buf), 'Exited adopted buffer retained')
panel.remove(1)
print 'PASS: adopted ToggleTerm job, name, input/output, exit, retained buffer, idempotence'
vim.cmd 'qa!'
