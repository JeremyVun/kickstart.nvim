-- Keep one module table across live reloads: PTY callbacks can outlive the code.
local M = type(package.loaded.terminal_panel) == 'table' and package.loaded.terminal_panel or {}
local api, fn = vim.api, vim.fn
local agents = require 'terminal_panel.agents'
local root = fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
local ns = api.nvim_create_namespace 'terminal_panel'
local sessions, views = {}, {}
local next_id, pending, configured = 0, false, false
local last_title, title_busy
local preview_pending = false
local styled = {}
local opts = { width = 38, auto_open = true, tab_title = true }
local states = {
  approval = { label = 'Needs approval', rank = 1, hl = 'DiagnosticWarn', mark = '!' },
  waiting = { label = 'Waiting for you', rank = 1, hl = 'DiagnosticWarn', mark = '?' },
  attention = { label = 'Needs attention', rank = 1, hl = 'DiagnosticWarn', mark = '!' },
  finished = { label = 'Finished turn', rank = 2, hl = 'DiagnosticOk', mark = '+' },
  working = { label = 'Working', rank = 3, hl = 'DiagnosticInfo', mark = '~' },
  active = { label = 'Active', rank = 3, hl = 'DiagnosticInfo', mark = '~' },
  ready = { label = 'Ready', rank = 4, hl = 'Comment', mark = '-' },
  shell = { label = 'Shell', rank = 4, hl = 'Comment', mark = '-' },
  unknown = { label = 'Status unavailable', rank = 4, hl = 'Comment', mark = '-' },
  exited = { label = 'Exited', rank = 5, hl = 'Comment', mark = 'x' },
}
local function valid(win)
  return win and api.nvim_win_is_valid(win)
end
local function validbuf(buf)
  return buf and api.nvim_buf_is_valid(buf)
end
local function view()
  local tab = api.nvim_get_current_tabpage()
  views[tab] = views[tab] or { tab = tab, order = {}, rows = {} }
  return views[tab]
end
local function clean(value)
  return fn.strcharpart(tostring(value or ''):gsub('[%c]', ' '), 0, 200)
end
local function clip(value, width)
  value = clean(value)
  if fn.strdisplaywidth(value) <= width then
    return value
  end
  while #value > 0 and fn.strdisplaywidth(value) > width - 1 do
    value = fn.strcharpart(value, 0, fn.strchars(value) - 1)
  end
  return value .. '…'
end
local function attention_count()
  local count = 0
  for _, s in pairs(sessions) do
    if states[s.status].rank == 1 or (s.status == 'finished' and s.unread) then
      count = count + 1
    end
  end
  return count
end

function M.update_title()
  if not opts.tab_title or not vim.env.WEZTERM_PANE or fn.executable 'wezterm' == 0 then
    return
  end
  local count = attention_count()
  local title = fn.fnamemodify(fn.getcwd(), ':t') .. (count > 0 and (' [' .. count .. '!]') or '')
  if title == last_title or title_busy then
    return
  end
  last_title, title_busy = title, true
  vim.system({ 'wezterm', 'cli', 'set-tab-title', '--pane-id', vim.env.WEZTERM_PANE, title }, { timeout = 1000 }, function()
    vim.schedule(function()
      title_busy = false
      -- Serialize writes so a delayed old count cannot overwrite a newer one.
      -- A failed CLI call is retried only after the desired title changes.
      M.update_title()
    end)
  end)
end

local function sorted(v)
  local order, included = {}, {}
  -- Freeze the visual order, not the statuses, while the user navigates.
  if api.nvim_get_current_win() == v.panel then
    for _, id in ipairs(v.order) do
      if sessions[id] then
        order[#order + 1], included[id] = id, true
      end
    end
    for id in pairs(sessions) do
      if not included[id] then
        order[#order + 1] = id
      end
    end
    return order
  end
  for id in pairs(sessions) do
    order[#order + 1] = id
  end
  table.sort(order, function(a, b)
    local sa, sb = sessions[a], sessions[b]
    local ra = sa.status == 'finished' and not sa.unread and 4 or states[sa.status].rank
    local rb = sb.status == 'finished' and not sb.unread and 4 or states[sb.status].rank
    if ra ~= rb then
      return ra < rb
    end
    if ra <= 2 and sa.changed ~= sb.changed then
      return sa.changed < sb.changed
    end
    return a < b
  end)
  return order
end

local function preview(s)
  if not validbuf(s.buf) then
    return ''
  end
  local count = api.nvim_buf_line_count(s.buf)
  local tail = api.nvim_buf_get_lines(s.buf, math.max(0, count - 120), count, false)
  for i = #tail, 1, -1 do
    local line = vim.trim(tail[i])
    if line ~= '' then
      return line
    end
  end
  return 'No output yet'
end

local function watch(s)
  api.nvim_buf_attach(s.buf, false, {
    on_lines = function()
      if preview_pending then
        return
      end
      local visible = false
      for _, v in pairs(views) do
        if valid(v.panel) then
          visible = true
          break
        end
      end
      if not visible then
        return
      end
      preview_pending = true
      vim.defer_fn(function()
        preview_pending = false
        for _, v in pairs(views) do
          M.render(v)
        end
      end, 100)
    end,
  })
end

function M.render(v)
  if not valid(v.panel) or not validbuf(v.buf) then
    return
  end
  local width = api.nvim_win_get_width(v.panel) - 2
  local selected = v.rows[api.nvim_win_get_cursor(v.panel)[1]]
  local lines, spans, rows, stops = {}, {}, {}, {}
  local function add(text, hl, action)
    lines[#lines + 1] = text
    if hl then
      spans[#spans + 1] = { #lines - 1, hl }
    end
    if action then
      rows[#lines], stops[#stops + 1] = action, #lines
    end
  end
  local count = attention_count()
  v.order = sorted(v)
  vim.wo[v.panel].winbar = ' Terminals  ' .. #v.order .. (count > 0 and ('   ' .. count .. ' need you') or '')
  if #v.order == 0 then
    add(' No terminals yet', 'TerminalPanelMuted')
  end
  for _, id in ipairs(v.order) do
    local s, active = sessions[id], v.active == id and valid(v.terminal)
    local st = states[s.status]
    local action = { id = id }
    local default_name = s.name == ('Terminal ' .. id) or s.name == ('Shell ' .. id) or s.name == ('Claude ' .. id) or s.name == ('Codex ' .. id)
    local agent = s.agent or s.kind
    local label = default_name and (agent == 'claude' and 'Claude' or agent == 'codex' and 'Codex' or 'Terminal') or s.name
    local status = st.label
    if s.status == 'shell' or s.status == 'unknown' then
      status = ''
    end
    local prefix = (active and '▸ ' or '  ') .. id .. ' '
    local suffix = status ~= '' and (' ' .. st.mark .. ' ' .. status) or ''
    local title = clip(label, math.max(3, width - fn.strdisplaywidth(prefix .. suffix)))
    local padding = math.max(1, width - fn.strdisplaywidth(prefix .. title .. suffix))
    add(prefix .. title .. string.rep(' ', padding) .. suffix, active and 'TerminalPanelActive' or 'Normal', action)
    if suffix ~= '' then
      spans[#spans + 1] = { #lines - 1, st.hl, #lines[#lines] - #suffix }
    end
    add('  ' .. clip(preview(s), width - 2), 'TerminalPanelMuted')
    rows[#lines] = action
  end
  add ''
  add(' + New terminal', 'Directory', { new = 'shell' })
  v.rows, v.stops = rows, stops
  vim.bo[v.buf].modifiable = true
  api.nvim_buf_set_lines(v.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(v.buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    api.nvim_buf_set_extmark(v.buf, ns, span[1], span[3] or 0, { end_row = span[1] + 1, hl_group = span[2], hl_eol = true, priority = span[3] and 120 or 100 })
  end
  vim.bo[v.buf].modifiable = false
  local target = stops[1] or 1
  for _, row in ipairs(stops) do
    local action = rows[row]
    if selected and vim.deep_equal(action, selected) then
      target = row
      break
    end
  end
  pcall(api.nvim_win_set_cursor, v.panel, { target, 0 })
end

function M.statusline()
  local win = tonumber(vim.g.statusline_winid) or api.nvim_get_current_win()
  if not valid(win) then
    return ''
  end
  local above = fn.line('w0', win) > 1
  local below = fn.line('w$', win) < api.nvim_buf_line_count(api.nvim_win_get_buf(win))
  if above and below then
    return ' ↑↓ More  Enter Open'
  end
  if below then
    return ' ↓ More below  Enter Open'
  end
  if above then
    return ' ↑ More above  Enter Open'
  end
  return ' Enter Open · F2 Rename · q Hide'
end

local function refresh()
  if pending then
    return
  end
  pending = true
  vim.defer_fn(function()
    pending = false
    for _, v in pairs(views) do
      M.render(v)
    end
    M.update_title()
  end, 20)
end

local function change(s, status)
  if s.status == 'exited' then
    return
  end
  if s.status ~= status then
    s.status, s.changed = status, os.time()
    s.unread = states[status].rank <= 2
    refresh()
  end
end

-- Called by the small external event bridge. A per-launch id prevents old hooks
-- and reused terminal numbers from changing a different process's status.
function M.event(event)
  if type(event) ~= 'table' then
    return false
  end
  for _, s in pairs(sessions) do
    if (s.token == event.id or s.agent_token == event.id) and (s.kind == event.source or s.agent == event.source) then
      local status = agents.status(event)
      if status then
        change(s, status)
      end
      return true
    end
  end
  return false
end

local function is_editor(win)
  if not valid(win) or api.nvim_win_get_config(win).relative ~= '' then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == '' and vim.bo[buf].filetype ~= 'neo-tree'
end

local function editor(v)
  if is_editor(v.origin) then
    return v.origin
  end
  for _, win in ipairs(api.nvim_tabpage_list_wins(v.tab)) do
    if is_editor(win) then
      v.origin = win
      return win
    end
  end
  return nil
end

-- A borderless viewport covers only the editor rectangle. The underlying split
-- tree stays intact; hiding it restores every window, cursor and unsaved buffer.
local function geometry(v)
  local top, left, bottom, right
  for _, win in ipairs(api.nvim_tabpage_list_wins(v.tab)) do
    if api.nvim_win_get_config(win).relative == '' and win ~= v.panel then
      local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
      if ft ~= 'neo-tree' and ft ~= 'terminal_panel' then
        local pos = api.nvim_win_get_position(win)
        top, left = math.min(top or pos[1], pos[1]), math.min(left or pos[2], pos[2])
        bottom = math.max(bottom or 0, pos[1] + api.nvim_win_get_height(win))
        right = math.max(right or 0, pos[2] + api.nvim_win_get_width(win))
      end
    end
  end
  if not top then
    return nil
  end
  return {
    relative = 'editor',
    row = top,
    col = left,
    width = math.max(1, right - left),
    height = math.max(1, bottom - top),
    style = 'minimal',
    border = 'none',
    zindex = 40,
  }
end

function M.resize()
  for _, v in pairs(views) do
    if v.tab == api.nvim_get_current_tabpage() and valid(v.terminal) then
      local config = geometry(v)
      if config then
        api.nvim_win_set_config(v.terminal, config)
      end
    end
  end
end

local function move_selection(v, step)
  local row = api.nvim_win_get_cursor(v.panel)[1]
  local index = 1
  for i, stop in ipairs(v.stops) do
    if stop <= row then
      index = i
    end
  end
  index = math.max(1, math.min(#v.stops, index + step))
  api.nvim_win_set_cursor(v.panel, { v.stops[index], 0 })
end

function M.rename()
  local v = view()
  local action = v.rows[api.nvim_win_get_cursor(v.panel)[1]]
  local s = action and sessions[action.id]
  if not s then
    return
  end
  vim.ui.input({ prompt = 'Terminal name: ', default = s.name }, function(name)
    if name and vim.trim(name) ~= '' then
      s.name = clean(vim.trim(name))
      refresh()
    end
  end)
end

function M.remove(id, confirmed)
  local s = sessions[id]
  if not s then
    return
  end
  if s.status ~= 'exited' and not confirmed then
    if fn.confirm('Stop "' .. s.name .. '" and close its terminal?', '&Cancel\n&Stop terminal', 1) ~= 2 then
      return
    end
  end
  for _, v in pairs(views) do
    if v.active == id and valid(v.terminal) then
      api.nvim_win_close(v.terminal, true)
      v.terminal = nil
    end
    if v.active == id then
      v.active = nil
    end
  end
  sessions[id] = nil
  if s.job and s.status ~= 'exited' then
    pcall(fn.jobstop, s.job)
  end
  if validbuf(s.buf) then
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
  refresh()
end

function M.choose()
  local v = view()
  local action = v.rows[api.nvim_win_get_cursor(v.panel)[1]]
  if not action then
    return
  end
  if action.id then
    M.open(action.id)
  elseif action.new then
    M.new(action.new)
  elseif action.editor then
    M.hide()
  end
end

function M.panel(focus)
  local v = view()
  v.panel_hidden = false
  if valid(v.panel) and styled[v.buf] then
    if focus then
      api.nvim_set_current_win(v.panel)
    end
    return v
  end
  local previous = api.nvim_get_current_win()
  if is_editor(previous) then
    v.origin = previous
  end
  if not validbuf(v.buf) then
    v.buf = api.nvim_create_buf(false, true)
    vim.bo[v.buf].filetype = 'terminal_panel'
    vim.bo[v.buf].bufhidden = 'hide'
    vim.bo[v.buf].swapfile = false
    api.nvim_buf_set_name(v.buf, 'Terminal sessions ' .. v.tab)
  end
  if not styled[v.buf] then
    styled[v.buf] = true
    local function map(key, callback)
      vim.keymap.set('n', key, callback, { buffer = v.buf, silent = true, nowait = true })
    end
    map('<Down>', function()
      move_selection(v, 1)
    end)
    map('<Up>', function()
      move_selection(v, -1)
    end)
    map('<Home>', function()
      api.nvim_win_set_cursor(v.panel, { v.stops[1], 0 })
    end)
    map('<End>', function()
      api.nvim_win_set_cursor(v.panel, { v.stops[#v.stops], 0 })
    end)
    map('<CR>', M.choose)
    map('<Right>', M.choose)
    map('<Left>', function()
      M.navigate 'h'
    end)
    map('<2-LeftMouse>', M.choose)
    map('<F2>', M.rename)
    map('r', M.rename)
    map('q', M.toggle_panel)
    map('<Del>', function()
      local action = v.rows[api.nvim_win_get_cursor(v.panel)[1]]
      if action and action.id then
        M.remove(action.id)
      end
    end)
    map('<Esc>', function()
      M.navigate 'h'
    end)
  end
  -- Splitting from a floating terminal is ambiguous; use its saved editor.
  if not valid(v.panel) then
    -- Avoid BufEnter while exposing the editor solely to make this split.
    v.opening_panel = true
    local origin = editor(v)
    if origin then
      api.nvim_set_current_win(origin)
    end
    vim.cmd('botright ' .. math.min(opts.width, math.max(24, math.floor(vim.o.columns * 0.26))) .. 'vsplit')
    v.panel = api.nvim_get_current_win()
    api.nvim_win_set_buf(v.panel, v.buf)
    v.opening_panel = nil
  end
  for key, value in pairs {
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    foldcolumn = '0',
    wrap = false,
    spell = false,
    list = false,
    cursorline = true,
    winfixwidth = true,
    scrolloff = 2,
    sidescrolloff = 0,
    fillchars = 'eob: ',
    winbar = ' Terminals',
    statusline = "%!v:lua.require'terminal_panel'.statusline()",
  } do
    vim.wo[v.panel][key] = value
  end
  vim.wo[v.panel].winhighlight = 'CursorLine:TerminalPanelCursor,WinBar:Directory'
  M.render(v)
  if not focus and valid(previous) then
    api.nvim_set_current_win(previous)
  elseif focus then
    api.nvim_set_current_win(v.panel)
  end
  M.resize()
  return v
end

function M.open(id)
  local s = sessions[id]
  if not s or not validbuf(s.buf) then
    return
  end
  local v = view()
  if not v.panel_hidden then
    v = M.panel(false)
  end
  if is_editor(api.nvim_get_current_win()) then
    v.origin = api.nvim_get_current_win()
  end
  local config = geometry(v)
  if not config then
    return
  end
  if valid(v.terminal) then
    api.nvim_win_set_buf(v.terminal, s.buf)
    api.nvim_set_current_win(v.terminal)
  else
    v.terminal = api.nvim_open_win(s.buf, true, config)
  end
  v.active = id
  vim.wo[v.terminal].winhighlight = 'Normal:Normal'
  if s.status == 'finished' then
    s.unread = false
  end
  -- Looking at an approval/input request does not resolve it. Clear those only
  -- on input or a subsequent lifecycle event, including generic OSC alerts.
  if s.status ~= 'exited' then
    api.nvim_win_set_cursor(v.terminal, { api.nvim_buf_line_count(s.buf), 0 })
    vim.cmd 'startinsert'
  end
  refresh()
end

function M.hide()
  local v = view()
  vim.cmd 'stopinsert'
  if valid(v.terminal) then
    api.nvim_win_close(v.terminal, true)
  end
  v.terminal = nil
  local origin = editor(v)
  if origin then
    api.nvim_set_current_win(origin)
  end
  refresh()
end

function M.toggle(count)
  local v = view()
  if count and count > 0 then
    if not sessions[count] then
      M.create { id = count }
    elseif v.active == count and valid(v.terminal) then
      M.hide()
    else
      M.open(count)
    end
    return
  end
  if valid(v.terminal) then
    M.hide()
  elseif v.active and sessions[v.active] then
    M.open(v.active)
  elseif next(sessions) then
    M.open(sorted(v)[1])
  else
    M.new 'shell'
  end
end

function M.toggle_panel(resume_input)
  local v = view()
  if valid(v.panel) then
    if api.nvim_get_current_win() == v.panel then
      M.navigate 'h'
    end
    api.nvim_win_close(v.panel, true)
    v.panel = nil
    v.panel_hidden = true
    M.resize()
  else
    M.panel(false)
  end
  if resume_input == true and api.nvim_get_current_win() == v.terminal and sessions[v.active] and sessions[v.active].status ~= 'exited' then
    vim.cmd 'startinsert'
  end
end

function M.navigate(direction)
  local v, win = view(), api.nvim_get_current_win()
  vim.cmd 'stopinsert'
  if win == v.terminal then
    if direction == 'l' then
      M.panel(true)
      return
    end
    if direction == 'h' then
      for _, candidate in ipairs(api.nvim_tabpage_list_wins(v.tab)) do
        if vim.bo[api.nvim_win_get_buf(candidate)].filetype == 'neo-tree' then
          api.nvim_set_current_win(candidate)
          return
        end
      end
    end
    M.hide()
    return
  elseif win == v.panel and direction == 'h' then
    if valid(v.terminal) then
      api.nvim_set_current_win(v.terminal)
      if sessions[v.active] and sessions[v.active].status ~= 'exited' then
        vim.cmd 'startinsert'
      end
    else
      local origin = editor(v)
      if origin then
        api.nvim_set_current_win(origin)
      end
    end
    return
  elseif vim.bo.filetype == 'neo-tree' and direction == 'l' and valid(v.terminal) then
    api.nvim_set_current_win(v.terminal)
    vim.cmd 'startinsert'
    return
  end
  vim.cmd('wincmd ' .. direction)
end

local function bind_terminal(s)
  vim.bo[s.buf].filetype = 'terminal_panel_terminal'
  vim.b[s.buf].terminal_panel_id = s.id
  for key, direction in pairs { Left = 'h', Right = 'l', Up = 'k', Down = 'j' } do
    vim.keymap.set(
      't',
      '<leader><' .. key .. '>',
      '<C-\\><C-n><Cmd>lua require("terminal_panel").navigate("' .. direction .. '")<CR>',
      { buffer = s.buf, silent = true, desc = 'Move to panel' }
    )
  end
  vim.keymap.set('t', '<C-`>', '<C-\\><C-n><Cmd>lua require("terminal_panel").toggle()<CR>', { buffer = s.buf, silent = true })
  vim.keymap.set('t', '<leader>\\', '<C-\\><C-n><Cmd>lua require("terminal_panel").toggle_panel(true)<CR>', { buffer = s.buf, silent = true })
  -- Input is activity, not proof of an agent working. Claude hooks replace this
  -- with an authoritative state; Codex stays Active until its next notification.
  vim.keymap.set('t', '<CR>', function()
    vim.schedule(function()
      if sessions[s.id] == s and (s.agent or s.kind == 'claude' or s.kind == 'codex') then
        change(s, 'active')
      end
    end)
    return '<CR>'
  end, { buffer = s.buf, expr = true })
  if not s.watched then
    s.watched = true
    watch(s)
  end
end

-- Loading the prototype into an existing editor should not require stopping
-- its agents. Adopt ToggleTerm's buffers/jobs, without restarting the processes.
function M.adopt()
  local backend = package.loaded['toggleterm.terminal']
  if not backend then
    return 0
  end
  local count = 0
  for _, term in ipairs(backend.get_all()) do
    if validbuf(term.bufnr) and not vim.b[term.bufnr].terminal_panel_id then
      next_id = next_id + 1
      local s = {
        id = next_id,
        kind = 'existing',
        name = clean(term.display_name or ('Terminal ' .. term.id)),
        buf = term.bufnr,
        job = term.job_id,
        cwd = term.dir or fn.getcwd(),
        status = 'unknown',
        changed = os.time(),
        token = tostring(vim.uv.hrtime()) .. '-' .. next_id,
      }
      vim.bo[s.buf].bufhidden = 'hide'
      -- Leave ToggleTerm's other/custom terminals alone. Remove only this
      -- buffer's window-management autocmds and filename-based identification.
      local ok, events = pcall(api.nvim_get_autocmds, { group = 'ToggleTermBuffer', buffer = s.buf })
      if ok then
        for _, event in ipairs(events) do
          api.nvim_del_autocmd(event.id)
        end
      end
      if valid(term.window) then
        term:close()
      end
      term.close_on_exit, term.auto_scroll = false, false
      api.nvim_buf_set_name(s.buf, 'term://terminal-panel/' .. s.id)
      sessions[s.id] = s
      bind_terminal(s)
      count = count + 1
    end
  end
  refresh()
  return count
end

function M.create(spec)
  spec = spec or {}
  local kind = spec.kind or 'shell'
  local command = spec.cmd or agents.command(kind, root)
  if not spec.cmd and fn.executable(command[1]) == 0 then
    vim.notify(command[1] .. ' is not installed or is missing from PATH.', vim.log.levels.ERROR)
    return nil
  end
  local id = spec.id or (next_id + 1)
  if sessions[id] then
    M.open(id)
    return sessions[id]
  end
  next_id = math.max(next_id, id)
  local s = {
    id = id,
    kind = kind,
    name = clean(spec.name or ('Terminal ' .. id)),
    cwd = spec.cwd or fn.getcwd(),
    status = kind == 'shell' and 'shell' or 'ready',
    changed = os.time(),
    unread = false,
    token = tostring(vim.uv.hrtime()) .. '-' .. id,
  }
  s.buf = api.nvim_create_buf(false, true)
  sessions[id] = s
  vim.bo[s.buf].bufhidden = 'hide'
  vim.bo[s.buf].scrollback = 10000
  vim.b[s.buf].terminal_panel_id = id
  local server = vim.v.servername
  if server == '' then
    server = fn.serverstart()
  end
  local success, job = pcall(api.nvim_buf_call, s.buf, function()
    return fn.jobstart(command, {
      term = true,
      cwd = s.cwd,
      env = vim.tbl_extend(
        'force',
        not spec.cmd and kind == 'shell' and agents.shell_env(root) or {},
        { TERMINAL_PANEL_SERVER = server, TERMINAL_PANEL_ID = s.token, TERMINAL_PANEL_NVIM = vim.v.progpath }
      ),
      on_exit = function(_, code)
        vim.schedule(function()
          if sessions[id] ~= s then
            return
          end
          s.status, s.exit_code, s.changed = 'exited', code, os.time()
          refresh()
        end)
      end,
    })
  end)
  if not success or job <= 0 then
    sessions[id] = nil
    api.nvim_buf_delete(s.buf, { force = true })
    vim.notify('Could not start terminal: ' .. tostring(job), vim.log.levels.ERROR)
    return nil
  end
  s.job = job
  bind_terminal(s)
  if spec.focus ~= false then
    M.open(id)
  end
  refresh()
  return s
end

function M.new(kind)
  return M.create { kind = kind or 'shell' }
end

function M.snapshot()
  local result = { sessions = {}, views = views, attention = attention_count() }
  for id, s in pairs(sessions) do
    result.sessions[id] = vim.deepcopy(s)
  end
  return result
end

function M.setup(options)
  if configured then
    return
  end
  configured = true
  if options and options.restore then
    sessions, views, next_id = options.restore.sessions, options.restore.views, options.restore.next_id
    options.restore = nil
  end
  opts = vim.tbl_extend('force', opts, options or {})
  local group = api.nvim_create_augroup('TerminalPanel', { clear = true })
  local function highlights()
    api.nvim_set_hl(0, 'TerminalPanelActive', { link = 'Title', default = true })
    api.nvim_set_hl(0, 'TerminalPanelCursor', { link = 'Visual', default = true })
    local comment = api.nvim_get_hl(0, { name = 'Comment', link = false })
    api.nvim_set_hl(0, 'TerminalPanelMuted', { fg = comment.fg, italic = false })
  end
  highlights()
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
  api.nvim_create_autocmd('TermRequest', {
    group = group,
    callback = function(args)
      local id = vim.b[args.buf].terminal_panel_id
      local s = id and sessions[id]
      if not s then
        return
      end
      local sequence = args.data and args.data.sequence or ''
      local operation, source, launch = sequence:match '^\027%]777;terminal%-panel;(%a+);(%a+);([%w%-]+)'
      if operation and (source == 'claude' or source == 'codex') then
        if operation == 'start' then
          s.agent, s.agent_token = source, s.token .. '-' .. launch
          change(s, 'ready')
        elseif operation == 'stop' and s.agent_token == s.token .. '-' .. launch then
          s.agent, s.agent_token = nil, nil
          change(s, 'shell')
        end
      elseif sequence:match '^\027%]9;' or sequence:match '^\027%]777;notify;' then
        -- Generic alerts carry no lifecycle meaning. Never downgrade a specific
        -- completion, question or approval, even when the alert arrives later.
        -- New input/activity already clears these before another turn can wait.
        if s.status ~= 'finished' and s.status ~= 'waiting' and s.status ~= 'approval' then
          change(s, 'attention')
        end
      elseif s.kind == 'shell' and not s.agent and sequence:match '^\027%]133;C' then
        change(s, 'active')
      elseif s.kind == 'shell' and not s.agent and sequence:match '^\027%]133;[AD]' then
        change(s, 'shell')
      end
    end,
  })
  api.nvim_create_autocmd('TermClose', {
    group = group,
    callback = function(args)
      local id = vim.b[args.buf].terminal_panel_id
      local s = id and sessions[id]
      if s then
        s.status, s.exit_code, s.changed = 'exited', vim.v.event.status, os.time()
        refresh()
      end
    end,
  })
  api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = group,
    callback = function()
      vim.schedule(function()
        M.resize()
        refresh()
      end)
    end,
  })
  api.nvim_create_autocmd('WinLeave', { group = group, callback = refresh })
  api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function()
      local v = view()
      if is_editor(api.nvim_get_current_win()) then
        v.origin = api.nvim_get_current_win()
        -- Opening a file from Neo-tree/Telescope should expose it immediately.
        if valid(v.terminal) and not v.opening_panel then
          api.nvim_win_close(v.terminal, true)
          v.terminal = nil
          refresh()
        end
      end
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      local id = vim.b[args.buf].terminal_panel_id
      if id and sessions[id] then
        sessions[id] = nil
        refresh()
      end
    end,
  })
  api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function()
      refresh()
    end,
  })
  api.nvim_create_autocmd('TabClosed', {
    group = group,
    callback = function()
      for tab in pairs(views) do
        if not api.nvim_tabpage_is_valid(tab) then
          views[tab] = nil
        end
      end
    end,
  })
  vim.keymap.set('n', '<C-`>', function()
    M.toggle(vim.v.count)
  end, { desc = 'Toggle terminal workspace' })
  vim.keymap.set('n', '<leader>\\', M.toggle_panel, { desc = 'Toggle terminal panel' })
  for key, direction in pairs { Left = 'h', Right = 'l', Up = 'k', Down = 'j' } do
    vim.keymap.set('n', '<leader><' .. key .. '>', function()
      M.navigate(direction)
    end, { desc = 'Move focus ' .. key:lower() })
  end
  api.nvim_create_user_command('TermPanel', function()
    M.panel(true)
  end, {})
  api.nvim_create_user_command('TermPanelHide', function()
    if valid(view().panel) then
      M.toggle_panel()
    end
  end, {})
  api.nvim_create_user_command('TermPanelToggle', M.toggle_panel, {})
  api.nvim_create_user_command('TermNew', function(args)
    if args.args ~= '' then
      M.create { name = args.args }
    else
      M.new 'shell'
    end
  end, { nargs = '*', force = true })
  M.adopt()
  for _, s in pairs(sessions) do
    bind_terminal(s)
  end
  local function start()
    if opts.auto_open and #api.nvim_list_uis() > 0 then
      M.panel(false)
    end
    M.update_title()
  end
  if vim.v.vim_did_enter == 1 then
    vim.schedule(start)
  else
    api.nvim_create_autocmd('VimEnter', {
      group = group,
      once = true,
      callback = function()
        vim.schedule(start)
      end,
    })
  end
end

-- Keep original records so callbacks on existing PTYs survive code replacement.
function M.detach()
  return { sessions = sessions, views = views, next_id = next_id }
end

return M
