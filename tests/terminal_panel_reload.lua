-- Run: nvim --headless -u NONE -l tests/terminal_panel_reload.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
local panel = require 'terminal_panel'
panel.setup { auto_open = false, tab_title = false }
local s = panel.create { name = 'Keep this process', cmd = { 'cat' } }
local job, buf = s.job, s.buf
for _ = 1, 2 do
  dofile 'tools/reload-terminal-panel.lua'
  assert(require 'terminal_panel' == panel, 'Module identity must survive reload')
  local restored = panel.snapshot().sessions[s.id]
  assert(restored.job == job and restored.buf == buf, 'Reuse exact process and buffer')
  vim.fn.chansend(job, 'survived reload\n')
  assert(
    vim.wait(1500, function()
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find('survived reload', 1, true)
    end),
    'Original process still responds'
  )
end
vim.fn.jobstop(job)
assert(
  vim.wait(1500, function()
    return panel.snapshot().sessions[s.id].status == 'exited'
  end),
  'Old job callbacks reach new module'
)
panel.remove(s.id)
print 'PASS: repeated live reload preserves module, job, buffer, output and exit events'
vim.cmd 'qa!'
