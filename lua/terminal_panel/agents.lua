local M = {}

-- Session-local configuration: never edit an agent's global settings.
function M.command(kind, root)
  local python = vim.fn.exepath 'python3'
  local helper = root .. '/tools/terminal-panel-event.py'
  if kind == 'claude' then
    local command = vim.fn.shellescape(python) .. ' ' .. vim.fn.shellescape(helper) .. ' claude'
    local hooks = {}
    for _, event in ipairs { 'UserPromptSubmit', 'PermissionRequest', 'PreToolUse', 'PostToolUse', 'Notification', 'Stop' } do
      hooks[event] = { { hooks = { { type = 'command', command = command, timeout = 2 } } } }
    end
    return { 'claude', '--settings', vim.json.encode { hooks = hooks } }
  elseif kind == 'codex' then
    return {
      'codex',
      '-c',
      'notify=' .. vim.json.encode { python, helper, 'codex' },
      '-c',
      'tui.notifications=true',
      '-c',
      'tui.notification_method="osc9"',
      '-c',
      'tui.notification_condition="always"',
    }
  end
  return { vim.o.shell }
end

function M.shell_env(root)
  if vim.fn.fnamemodify(vim.o.shell, ':t') ~= 'zsh' then
    return {}
  end
  local claude, codex = M.command('claude', root), M.command('codex', root)
  claude[1], codex[1] = vim.fn.exepath 'claude', vim.fn.exepath 'codex'
  return {
    ZDOTDIR = root .. '/tools/terminal-panel-zsh',
    TERMINAL_PANEL_ZDOTDIR = root .. '/tools/terminal-panel-zsh',
    TERMINAL_PANEL_ORIGINAL_ZDOTDIR = vim.env.ZDOTDIR or vim.env.HOME,
    TERMINAL_PANEL_ZDOTDIR_WAS_SET = vim.env.ZDOTDIR and '1' or '0',
    TERMINAL_PANEL_LAUNCHER = root .. '/tools/terminal-panel-launch.py',
    TERMINAL_PANEL_PYTHON = vim.fn.exepath 'python3',
    TERMINAL_PANEL_CLAUDE_ARGV = vim.json.encode(claude),
    TERMINAL_PANEL_CODEX_ARGV = vim.json.encode(codex),
  }
end

-- Do not infer readiness from a pause in terminal output.
function M.status(event)
  if event.source == 'codex' then
    if event.type == 'agent-turn-complete' then
      return 'finished'
    end
    return nil
  end
  local hook = event.hook_event_name
  if hook == 'PermissionRequest' then
    return 'approval'
  end
  if hook == 'Notification' then
    if event.notification_type == 'permission_prompt' then
      return 'approval'
    end
    -- Claude sends idle_prompt after a completed response, not while a tool
    -- question is blocked. Treat it like Stop (and Codex's turn-complete).
    if event.notification_type == 'idle_prompt' then
      return 'finished'
    end
    if event.notification_type == 'elicitation_dialog' or event.notification_type == 'elicitation_url_dialog' then
      return 'waiting'
    end
  elseif hook == 'PreToolUse' then
    return event.tool_name == 'AskUserQuestion' and 'waiting' or 'working'
  elseif hook == 'UserPromptSubmit' or hook == 'PostToolUse' then
    return 'working'
  elseif hook == 'Stop' then
    return 'finished'
  end
end

return M
