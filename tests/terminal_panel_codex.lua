-- Run: nvim --headless -u NONE -l tests/terminal_panel_codex.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
local panel = require 'terminal_panel'
panel.setup { auto_open = false, tab_title = false }
-- A real PTY redraws the footer without user key mappings or lifecycle starts.
local s = panel.create {
  kind = 'codex',
  focus = false,
  cmd = {
    'python3',
    '-u',
    '-c',
    [[
import sys, tty
tty.setraw(sys.stdin.fileno())
while True:
    key = sys.stdin.read(1)
    text = '• Working (1m 43s • esc to interrupt)' if key == 'w' else '• Done'
    sys.stdout.write('\x1b[2J\x1b[H' + text)
    sys.stdout.flush()
]],
  },
}
local function status()
  return panel.snapshot().sessions[s.id].status
end
local function draw(key, text)
  vim.fn.chansend(s.job, key)
  assert(
    vim.wait(2000, function()
      return table.concat(vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)):find(text, 1, true)
    end),
    'PTY redraw arrives'
  )
  vim.wait(150, function()
    return false
  end)
end
vim.wait(150, function()
  return false
end)
panel.event { id = s.token, source = 'codex', type = 'agent-turn-complete' }
assert(status() == 'finished')
draw('w', 'esc to interrupt')
assert(status() == 'working', 'Background work clears stale completion without Enter')
assert(not panel.snapshot().sessions[s.id].unread, 'Working clears completion attention')
draw('d', 'Done')
assert(status() == 'working', 'Ordinary output does not imply completion')
panel.event { id = s.token, source = 'codex', type = 'agent-turn-complete' }
assert(status() == 'finished', 'Actual completion still works')
draw('d', 'Done')
assert(status() == 'finished', 'Idle redraw does not clear completion')
-- Shell-launched Codex uses the same detection.
local record = panel.detach().sessions[s.id]
record.kind, record.agent = 'shell', 'codex'
draw('w', 'esc to interrupt')
assert(status() == 'working', 'Shell-launched Codex activity is detected')
record.status = 'finished'
dofile 'tools/reload-terminal-panel.lua'
assert(status() == 'working', 'Reload repairs an already stale status')
draw('d', 'Done')
record.status = 'finished'
draw('w', 'esc to interrupt')
assert(status() == 'working', 'Output watcher survives reload')
panel.remove(s.id, true)
print 'PASS: Codex resume, hidden output, completion, shell launch, and reload'
vim.cmd 'qa!'
