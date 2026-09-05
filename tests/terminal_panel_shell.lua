-- Run: nvim --headless -u NONE -l tests/terminal_panel_shell.lua
-- Fake CLIs and shell startup files: no model requests or global config edits.
vim.opt.runtimepath:append(vim.fn.getcwd())
local api = vim.api
local panel = require 'terminal_panel'
panel.setup { auto_open = false, tab_title = false }
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. '/bin', 'p')
vim.fn.writefile({ 'export PANEL_FIXTURE=normal-startup-preserved', "PS1='fixture> '" }, dir .. '/.zshrc')
local fake = [[#!/usr/bin/env python3
import json, os, shlex, subprocess, sys, time
args = sys.argv[1:]
time.sleep(.15)
if os.path.basename(sys.argv[0]) == 'codex':
    callback = json.loads(next(arg[7:] for arg in args if arg.startswith('notify=')))
    subprocess.run(callback + [json.dumps({'type': 'agent-turn-complete'})])
else:
    config = json.loads(args[args.index('--settings') + 1])
    command = config['hooks']['PermissionRequest'][0]['hooks'][0]['command']
    subprocess.run(shlex.split(command), input=json.dumps({'hook_event_name': 'PermissionRequest'}), text=True)
print('fixture agent args preserved: ' + args[-1], flush=True)
time.sleep(.3)
]]
for _, name in ipairs { 'codex', 'claude' } do
  vim.fn.writefile(vim.split(fake, '\n'), dir .. '/bin/' .. name)
  vim.fn.setfperm(dir .. '/bin/' .. name, 'rwx------')
end
local original_path, original_zdotdir = vim.env.PATH, vim.env.ZDOTDIR
vim.env.PATH, vim.env.ZDOTDIR = dir .. '/bin:' .. vim.env.PATH, dir
vim.o.shell = '/bin/zsh'
local s = panel.new 'shell'
vim.env.PATH, vim.env.ZDOTDIR = original_path, original_zdotdir
local function state()
  return panel.snapshot().sessions[s.id]
end
local function output()
  return table.concat(api.nvim_buf_get_lines(s.buf, 0, -1, false), '\n')
end
assert(
  vim.wait(2500, function()
    return output():find('fixture>', 1, true)
  end),
  'Normal shell startup loads'
)
vim.fn.chansend(s.job, 'printf "%s\\n" "$PANEL_FIXTURE"\n')
assert(
  vim.wait(1500, function()
    return output():find('normal-startup-preserved', 1, true)
  end),
  'Existing shell initialization preserved'
)
for _, source in ipairs { 'codex', 'claude' } do
  vim.fn.chansend(s.job, source .. ' --version\n')
  assert(
    vim.wait(1500, function()
      return state().agent == source
    end),
    'Typed agent attaches to shell row: ' .. source
  )
  local expected = source == 'codex' and 'finished' or 'approval'
  assert(
    vim.wait(2000, function()
      return state().status == expected
    end),
    'Actual hook bridge routes shell agent: ' .. source
  )
  assert(
    vim.wait(2000, function()
      return state().agent == nil and state().status == 'shell'
    end),
    'Agent exit restores shell: ' .. source
  )
end
assert(output():find('fixture agent args preserved: --version', 1, true), 'Agent command arguments preserved')
panel.remove(s.id, true)
vim.fn.delete(dir, 'rf')
print 'PASS: shell startup, typed agent wrappers, lifecycle bridge, CLI arguments, return to shell'
vim.cmd 'qa!'
