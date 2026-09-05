-- Run from the config root: nvim --headless -u NONE -l tests/terminal_panel.lua
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.g.mapleader = ' '
vim.o.columns, vim.o.lines = 160, 52
local api = vim.api
local panel = require 'terminal_panel'
panel.setup { auto_open = false, tab_title = false }
local assertions = 0
local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end
local function settle()
  vim.wait(60, function()
    return false
  end, 5)
end
local function snapshot()
  return panel.snapshot()
end
local function view()
  return snapshot().views[api.nvim_get_current_tabpage()]
end
local function status(id)
  return snapshot().sessions[id].status
end
local function hook(s, event, extra)
  panel.event(vim.tbl_extend('force', { id = s.token, source = s.kind, hook_event_name = event }, extra or {}))
  settle()
end
local function key(lhs)
  local callback = vim.fn.maparg(lhs, 'n', false, true).callback
  assert(type(callback) == 'function', 'Missing key: ' .. lhs)
  callback()
end

-- Real split layout and unsaved buffers survive opening/switching terminals.
local first = api.nvim_get_current_win()
local first_buf = api.nvim_get_current_buf()
api.nvim_buf_set_lines(first_buf, 0, -1, false, { 'unsaved work', 'keep my cursor' })
api.nvim_win_set_cursor(first, { 2, 3 })
vim.cmd 'vsplit'
local second = api.nvim_get_current_win()
vim.cmd 'enew'
local second_buf = api.nvim_get_current_buf()
vim.cmd 'split'
local third = api.nvim_get_current_win()
vim.cmd 'enew'
local tree_buf = api.nvim_create_buf(false, true)
vim.bo[tree_buf].filetype = 'neo-tree'
vim.cmd 'topleft 25vsplit'
local tree = api.nvim_get_current_win()
api.nvim_win_set_buf(tree, tree_buf)
api.nvim_set_current_win(second)
local original_layout = vim.fn.winlayout()
local a = panel.create { kind = 'claude', name = 'Login fix', cmd = { 'cat' } }
local b = panel.create { kind = 'codex', name = 'Keyboard navigation', cmd = { 'cat' }, focus = false }
local c = panel.create { name = 'Dev server', cmd = { 'cat' }, focus = false }
settle()
check(a and b and c, 'PTY jobs start')
check(api.nvim_win_get_buf(tree) == tree_buf, 'Neo-tree stays in place')
local config = api.nvim_win_get_config(view().terminal)
check(config.col >= api.nvim_win_get_width(tree), 'Terminal excludes the file tree')
local right = api.nvim_win_get_position(view().panel)[2]
check(config.col + config.width <= right, 'Terminal excludes session panel')
check(api.nvim_win_get_buf(second) == second_buf, 'Editor buffers remain underneath')

-- The hidden terminal still runs and receives output.
vim.fn.chansend(c.job, 'background output\n')
check(
  vim.wait(1500, function()
    return table.concat(api.nvim_buf_get_lines(c.buf, 0, -1, false), '\n'):find('background output', 1, true) ~= nil
  end),
  'Hidden PTY output is retained'
)

-- Lifecycle events, attention sorting, frozen selection, and acknowledgement.
hook(a, 'UserPromptSubmit')
check(status(a.id) == 'working', 'Claude working hook')
panel.event { id = b.token, source = 'codex', type = 'agent-turn-complete' }
settle()
check(view().order[1] == b.id, 'Finished unseen turn sorts above work')
hook(a, 'PermissionRequest')
check(view().order[1] == a.id, 'Approval sorts first')
panel.panel(true)
local frozen = vim.deepcopy(view().order)
local selected = view().rows[api.nvim_win_get_cursor(view().panel)[1]]
hook(a, 'PostToolUse')
check(vim.deep_equal(view().order, frozen), 'Order frozen while navigating')
check(vim.deep_equal(view().rows[api.nvim_win_get_cursor(view().panel)[1]], selected), 'Selection stays on same item')
key '<Down>'
local row = api.nvim_win_get_cursor(view().panel)[1]
check(view().rows[row].id == b.id, 'Down skips status lines')
key '<CR>'
settle()
check(view().active == b.id and api.nvim_get_current_buf() == b.buf, 'Enter opens selected PTY')
check(not snapshot().sessions[b.id].unread, 'Reading a completed turn clears unread')
check(view().order[1] == a.id, 'List resorts after leaving')
hook(a, 'PermissionRequest')
panel.open(a.id)
check(status(a.id) == 'approval', 'Viewing does not resolve an approval')
hook(a, 'PostToolUse')
check(status(a.id) == 'working', 'Tool completion resolves approval')
panel.event { id = 'stale-token', source = 'claude', hook_event_name = 'PermissionRequest' }
check(status(a.id) == 'working', 'Stale event cannot target a different PTY')
panel.event { id = a.token, source = 'codex', type = 'agent-turn-complete' }
check(status(a.id) == 'working', 'Agent source must match')

-- Claude sends a delayed idle notification after Stop. It describes the same
-- finished turn, not a new request, and must not reset acknowledgement or age.
hook(a, 'Stop')
check(status(a.id) == status(b.id), 'Claude and Codex use the same completed-turn status')
panel.open(a.id)
local completed_at = snapshot().sessions[a.id].changed
hook(a, 'Notification', { notification_type = 'idle_prompt' })
check(status(a.id) == 'finished', 'Delayed Claude idle remains Finished turn')
check(not snapshot().sessions[a.id].unread, 'Delayed idle does not re-alert an acknowledged completion')
check(snapshot().sessions[a.id].changed == completed_at, 'Delayed idle preserves completion ordering')
local function generic_alert()
  api.nvim_exec_autocmds('TermRequest', { buffer = a.buf, data = { sequence = '\027]9;Notification\027\\' } })
end
-- Deliberately older than the old two-second guard, without a wall-clock wait.
panel.detach().sessions[a.id].changed = os.time() - 120
generic_alert()
check(status(a.id) == 'finished', 'Late generic alert cannot overwrite completion')
hook(a, 'PreToolUse', { tool_name = 'AskUserQuestion' })
check(status(a.id) == 'waiting', 'An actual question still waits for the user')
generic_alert()
check(status(a.id) == 'waiting', 'Generic alert preserves the question status')
hook(a, 'PostToolUse', { tool_name = 'AskUserQuestion' })
check(status(a.id) == 'working', 'Answering a question resumes work')
hook(a, 'Stop')
check(status(a.id) == 'finished', 'Answered question followed by Stop finishes the turn')
hook(a, 'Notification', { notification_type = 'elicitation_url_dialog' })
check(status(a.id) == 'waiting', 'Browser input requests wait for the user')
hook(a, 'PermissionRequest')
generic_alert()
check(status(a.id) == 'approval', 'Generic alert preserves the approval status')
hook(a, 'UserPromptSubmit')
generic_alert()
check(status(a.id) == 'attention', 'A new turn can still raise generic attention')
hook(a, 'PostToolUse')

-- Actual OSC notifications emitted by a hidden PTY, not a mocked autocmd.
local osc = panel.create {
  kind = 'codex',
  name = 'OSC test',
  focus = false,
  cmd = { 'python3', '-u', '-c', 'import sys,time; time.sleep(.15); sys.stdout.write("\\x1b]9;Agent needs input\\x1b\\\\"); sys.stdout.flush(); time.sleep(5)' },
}
check(
  vim.wait(2000, function()
    return status(osc.id) == 'attention'
  end, 10),
  'Hidden OSC 9 captured by Neovim'
)

-- Exercise the real dependency-free helper and Neovim socket end to end.
local helper_done
vim.system({ 'python3', 'tools/terminal-panel-event.py', 'claude' }, {
  env = { TERMINAL_PANEL_SERVER = vim.v.servername, TERMINAL_PANEL_ID = a.token, TERMINAL_PANEL_NVIM = vim.v.progpath },
  stdin = vim.json.encode { hook_event_name = 'PermissionRequest', tool_name = 'Bash', tool_input = { command = 'private content' } },
}, function(result)
  helper_done = result
end)
check(
  vim.wait(2500, function()
    return helper_done ~= nil
  end, 10),
  'Event bridge finishes'
)
check(helper_done.code == 0 and status(a.id) == 'approval', 'Hook reaches the correct terminal through RPC')
check(helper_done.stdout == '' and helper_done.stderr == '', 'Hooks produce no agent-visible output')

local child_done
vim.system({ 'python3', 'tools/terminal-panel-event.py', 'claude' }, {
  env = { TERMINAL_PANEL_SERVER = vim.v.servername, TERMINAL_PANEL_ID = a.token, TERMINAL_PANEL_NVIM = vim.v.progpath },
  stdin = vim.json.encode { hook_event_name = 'Stop', agent_id = 'child-agent' },
}, function(result)
  child_done = result
end)
check(
  vim.wait(2000, function()
    return child_done ~= nil
  end, 10),
  'Subagent hook finishes'
)
check(status(a.id) == 'approval', 'A subagent completion cannot clear parent approval')

local codex_done
vim.system({ 'python3', 'tools/terminal-panel-event.py', 'codex', vim.json.encode { type = 'agent-turn-complete' } }, {
  env = { TERMINAL_PANEL_SERVER = vim.v.servername, TERMINAL_PANEL_ID = b.token, TERMINAL_PANEL_NVIM = vim.v.progpath },
}, function(result)
  codex_done = result
end)
check(vim.wait(2000, function()
  return codex_done ~= nil
end, 10) and status(b.id) == 'finished', 'Codex completion callback reaches its terminal')

panel.open(osc.id)
check(status(osc.id) == 'attention', 'Viewing a generic alert does not resolve it')

panel.open(c.id)
panel.navigate 'l'
check(api.nvim_get_current_win() == view().panel, 'Right enters sessions panel')
panel.navigate 'h'
check(api.nvim_get_current_buf() == c.buf, 'Left returns to active terminal')
panel.navigate 'h'
check(api.nvim_get_current_win() == tree, 'Left enters Neo-tree')
panel.navigate 'l'
check(api.nvim_get_current_buf() == c.buf, 'Right returns from Neo-tree')
panel.hide()
check(api.nvim_win_get_buf(first) == first_buf and api.nvim_win_get_buf(second) == second_buf, 'Editor buffers restored')
check(vim.bo[first_buf].modified, 'Unsaved edits remain modified')
check(vim.deep_equal(api.nvim_win_get_cursor(first), { 2, 3 }), 'Editor cursor restored')
check(api.nvim_win_is_valid(third), 'Editor split survives')
check(vim.fn.winlayout()[1] == original_layout[1], 'Original split orientation survives')

-- Eight terminals and repeated switches exercise the hot path.
for i = 5, 8 do
  panel.create { name = 'Terminal ' .. i, cmd = { 'cat' }, focus = false }
end
local started = vim.uv.hrtime()
for i = 1, 100 do
  panel.open(i % 2 == 0 and a.id or b.id)
end
local elapsed = (vim.uv.hrtime() - started) / 1e6
check(#snapshot().sessions == 8, 'Eight PTYs coexist')
check(api.nvim_get_current_buf() == a.buf, 'Repeated switching ends in correct PTY')

-- A short window must still expose eight sessions and all launch actions.
vim.o.lines = 32
vim.o.cmdheight = 1
-- Headless 'lines' does not reflow windows as an attached UI resize does.
api.nvim_win_set_height(view().panel, 29)
settle()
panel.render(view())
local compact = view()
check(
  api.nvim_buf_line_count(compact.buf) <= api.nvim_win_get_height(compact.panel),
  string.format(
    'Eight compact rows and launch controls fit at 32 lines (%d rows, %d height)',
    api.nvim_buf_line_count(compact.buf),
    api.nvim_win_get_height(compact.panel)
  )
)
check(#compact.stops == 9, 'All eight terminals and the single New action remain selectable')
local footer = api.nvim_eval_statusline(vim.wo[compact.panel].statusline, { winid = compact.panel })
check(footer.str:find('Enter Open', 1, true), 'Persistent panel footer evaluates')
vim.o.lines = 52
settle()

-- Previews follow actual output without switching or resizing the source PTY.
vim.fn.chansend(c.job, 'live preview changed\n')
check(
  vim.wait(2000, function()
    return table.concat(api.nvim_buf_get_lines(view().buf, 0, -1, false)):find('live preview changed', 1, true) ~= nil
  end, 10),
  'Hidden terminal preview updates live'
)
local original_window = view().terminal
panel.toggle_panel()
check(not (view().panel and api.nvim_win_is_valid(view().panel)), 'Panel toggle collapses sidebar')
check(api.nvim_win_is_valid(original_window), 'Collapsing sidebar preserves terminal viewport')
panel.toggle_panel()
check(api.nvim_win_is_valid(view().panel) and api.nvim_win_is_valid(original_window), 'Reopening sidebar preserves terminal viewport')
local before_input = vim.ui.input
vim.ui.input = function()
  error 'New terminal must not prompt for a name'
end
local immediate = panel.new 'shell'
vim.ui.input = before_input
check(immediate and immediate.job > 0, 'New terminal starts immediately')
panel.remove(immediate.id, true)
panel.toggle(2)
check(view().active == 2, 'Count selects stable terminal number')
panel.toggle(15)
check(view().active == 15 and snapshot().sessions[15], 'Count creates a missing numbered terminal')
panel.remove(15, true)

-- Exited terminals retain their output and ignore late events.
local ended = panel.create { name = 'Exit status', cmd = { 'sh', '-c', 'printf "kept output"; exit 7' }, focus = false }
check(
  vim.wait(2000, function()
    return status(ended.id) == 'exited'
  end, 10),
  'PTY exit tracked'
)
check(snapshot().sessions[ended.id].exit_code == 7, 'Exit code retained')
check(table.concat(api.nvim_buf_get_lines(ended.buf, 0, -1, false)):find('kept output', 1, true), 'Exit output retained')
panel.open(ended.id)
panel.remove(ended.id)
check(not snapshot().sessions[ended.id], 'Exited terminal closes without confirmation')

for id in pairs(snapshot().sessions) do
  panel.remove(id, true)
end
settle()
check(vim.tbl_count(snapshot().sessions) == 0, 'Cleanup removes all terminal records')
print(string.format('PASS: %d assertions; 100 terminal switches %.1f ms (%.2f ms/switch, headless)', assertions, elapsed, elapsed / 100))
vim.cmd 'qa!'
