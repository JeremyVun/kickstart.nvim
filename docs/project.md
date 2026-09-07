# Neovim configuration

Personal Neovim config using Lazy, Neo-tree, Telescope and a local terminal panel.
Each WezTerm tab owns one project's Neovim and terminal jobs. Alt + number stays
with WezTerm; Space is the Neovim leader.

## Terminal panel

Neo-tree stays left. The right panel uses two lines per terminal: a stable number,
name and status, followed by a live preview of its latest nonempty output line.
Requests for attention sort first (oldest first), then unread completed turns,
active work, and other terminals. The order freezes while navigating the list.
Numbers never change when rows move.

The centre displays one terminal. A borderless viewport covers the editor area,
keeping editor splits, unsaved buffers and cursors intact underneath. Ctrl +
backtick returns to the editor. Opening a file from Neo-tree or Telescope also
exposes the editor. The sidebar can stay collapsed while switching terminals.

### Controls

| Control | Action |
| --- | --- |
| Enter on **+ New terminal** | Start a shell immediately, with an automatic name |
| Space + arrows (normal mode) | Move between Neo-tree, terminal and session panel |
| Up / Down in session panel | Select a terminal or New |
| Enter / Right in session panel | Open selection and focus it |
| Left / Escape in session panel | Return to the centre |
| Ctrl + backtick | Show/hide the terminal workspace; create a shell if none exist |
| Number, then Ctrl + backtick (normal mode) | Open/create that numbered terminal; toggle it if already selected |
| Space + backslash (normal mode) | Collapse/show the right panel |
| q in session panel | Collapse the panel |
| F2 in session panel | Rename terminal |
| Delete in session panel | Close terminal; confirm before stopping a live process |
| `:TermPanel` | Open/focus the panel |
| `:TermPanelToggle` / `:TermPanelHide` | Toggle/hide the panel |
| `:TermNew [name]` | Start a shell immediately, optionally with a name |

Plain terminal arrows, digits and spaces belong to the shell or agent; no
leader maps exist in terminal input mode, so a space is sent immediately. Leave
terminal input with Ctrl + backslash then Ctrl + n, or Ctrl + backtick, and the
Space maps apply. Count prefixes work in Neovim normal mode, as with ToggleTerm.
The footer indicates when more content is above or below the viewport.

### Apply an update without restarting agents

New Neovim instances load the panel automatically. In an existing instance:

```vim
:luafile ~/.config/nvim/tools/reload-terminal-panel.lua
```

The reload helper preserves buffers, processes, names and editor state. It also
supports the first prototype. Non-hidden ToggleTerm buffers are adopted if the
plugin hasn't been loaded yet. Existing processes cannot retroactively gain new
launch settings; their output previews work, but detailed status may be unavailable.

### Agent status from ordinary shells

In a **new panel shell**, type `claude` or `codex` normally. For zsh, a session-local
startup shim loads the user's normal shell setup and adds launch functions. These
functions add notification settings only to that agent invocation and preserve
command arguments. Global shell/agent configuration files are not rewritten.
When the agent exits, the same shell remains usable. Each agent launch receives
its own event id, preventing late hooks from an earlier launch changing the row.

- Claude hooks report working, approvals, questions, idle prompts and completed
  turns. Subagent events do not overwrite the parent terminal's status.
- **Finished turn** means the same thing for both agents. Claude's delayed
  `idle_prompt` is another completion signal, not an unanswered question. It
  preserves acknowledgement and completion time. **Waiting for you** is reserved
  for actual questions or input forms; **Needs approval** is a permission request.
  Generic terminal alerts never overwrite these more precise statuses.
- Codex reports completion through its callback and attention through OSC 9.
  Generic alerts say **Needs attention** because their precise reason is unknown.
- **Active** means input was submitted, not verified tool execution. Viewing a
  completed turn clears unread status; viewing an input request does not resolve it.
- Exited terminals retain output. **Finished turn** does not mean the task succeeded.

Automatic shell integration currently supports zsh. Existing shells, nested shells,
absolute-path agent invocations and `command codex`/`command claude` bypass those
functions. Their output previews still work. Codex's `notify` is overridden only
for an integrated invocation, so any existing external notify callback won't run
there. Models, sandbox and approval policies are unchanged. Attention counts are
also written asynchronously to the owning WezTerm tab title when available.

### Performance and scope

Switching reuses buffers and one viewport. Preview redraws are event-driven and
capped at ten per second across the whole panel; each reads at most 120 trailing
lines per terminal. No background screenshot capture, transcript scanning or idle
state inference. Previewing a terminal never resizes its PTY. Each terminal has
10,000 scrollback lines. The previews are text excerpts, not scaled full-screen
terminal thumbnails.

`lua/terminal_panel/init.lua` owns jobs, views and rendering. `agents.lua` supplies
session-local launch settings. `tools/terminal-panel-event.py` forwards lifecycle
metadata (never prompt/transcript contents) to Neovim; `terminal-panel-launch.py`
wraps agents typed in new zsh terminals. No additional Neovim plugin dependencies.

```sh
nvim --headless -u NONE -l tests/terminal_panel.lua
nvim --headless -u NONE -l tests/terminal_panel_adopt.lua
nvim --headless -u NONE -l tests/terminal_panel_reload.lua
nvim --headless -u NONE -l tests/terminal_panel_shell.lua
```

Tests use real PTYs, hidden output/OSC, live previews, event routing, count switching,
layout preservation, adoption, reload and isolated fake agent CLIs. Terminal jobs
still depend on their Neovim process; names are not persisted after quitting. One
project per Neovim instance is assumed; internal Neovim tabs share the terminal list.

To revert for future instances, remove `terminal_panel.setup()` from `init.lua`
and remove `enabled = false` from the ToggleTerm spec. Already adopted buffers stay
under the panel until that Neovim instance exits.

Sources checked 2026-09-05:
[Claude hooks](https://code.claude.com/docs/en/hooks),
[Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications),
[Neovim terminals](https://neovim.io/doc/user/terminal/).
