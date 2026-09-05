# Preserve the user's normal interactive setup, then add session-local launchers.
ZDOTDIR="$TERMINAL_PANEL_ORIGINAL_ZDOTDIR"
if [[ "$TERMINAL_PANEL_ZDOTDIR_WAS_SET" == 0 ]]; then unset ZDOTDIR; fi
if [[ -r "$TERMINAL_PANEL_ORIGINAL_ZDOTDIR/.zshrc" ]]; then
  source "$TERMINAL_PANEL_ORIGINAL_ZDOTDIR/.zshrc"
fi
# Quoted names avoid expanding any aliases defined by the user's shell config.
function 'claude' { command "$TERMINAL_PANEL_PYTHON" "$TERMINAL_PANEL_LAUNCHER" claude "$@"; }
function 'codex' { command "$TERMINAL_PANEL_PYTHON" "$TERMINAL_PANEL_LAUNCHER" codex "$@"; }
