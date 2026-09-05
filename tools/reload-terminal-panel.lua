-- :luafile ~/.config/nvim/tools/reload-terminal-panel.lua
-- Replace plugin code without restarting terminals or losing editor state.
local old = package.loaded.terminal_panel
local state
if old then
  if old.detach then
    state = old.detach()
  else
    -- One-time compatibility with the first prototype, which had no detach API.
    local function upvalue(func, name)
      for i = 1, 60 do
        local key, value = debug.getupvalue(func, i)
        if not key then
          break
        end
        if key == name then
          return value
        end
      end
    end
    local timer = upvalue(old.setup, 'timer')
    if timer then
      timer:stop()
      timer:close()
    end
    state = { sessions = assert(upvalue(old.create, 'sessions')), views = old.snapshot().views, next_id = assert(upvalue(old.create, 'next_id')) }
  end
end
package.loaded['terminal_panel.agents'] = nil
local panel = assert(loadfile(vim.fn.stdpath 'config' .. '/lua/terminal_panel/init.lua'))()
package.loaded.terminal_panel = panel
panel.setup { restore = state, auto_open = false }
panel.panel(false)
vim.notify 'Terminal panel updated. Your terminals are still running.'
