#!/usr/bin/env python3
"""Forward a Claude hook or Codex notify event to its owning Neovim. No dependencies.

Launched by terminal_panel.agents, with routing variables inherited from its PTY.
Keep agent callbacks silent and fail open if the editor has gone away.
"""
import json
import os
import subprocess
import sys


def main():
    server = os.environ.get("TERMINAL_PANEL_SERVER")
    session = os.environ.get("TERMINAL_PANEL_ID")
    nvim = os.environ.get("TERMINAL_PANEL_NVIM")
    if not all((server, session, nvim)):
        return
    source = sys.argv[1]
    raw = json.loads(sys.argv[2]) if source == "codex" else json.load(sys.stdin)
    if raw.get("agent_id"):
        # A child finishing or running a tool must not change the parent row.
        return
    # Only send lifecycle metadata, never prompts, tool input, or transcripts.
    event = {key: raw[key] for key in (
        "type", "hook_event_name", "notification_type", "tool_name"
    ) if key in raw}
    event.update(id=session, source=source)
    encoded = json.dumps(event, ensure_ascii=True).replace("'", "''")
    expression = "luaeval(\"require('terminal_panel').event(_A)\", json_decode('%s'))" % encoded
    subprocess.run(
        [nvim, "--server", server, "--remote-expr", expression],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        timeout=1, check=False,
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        pass
