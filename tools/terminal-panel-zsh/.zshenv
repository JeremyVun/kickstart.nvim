# Forward normal startup; use the panel's .zshrc for this shell only.
ZDOTDIR="$TERMINAL_PANEL_ORIGINAL_ZDOTDIR"
if [[ -r "$ZDOTDIR/.zshenv" ]]; then source "$ZDOTDIR/.zshenv"; fi
ZDOTDIR="$TERMINAL_PANEL_ZDOTDIR"
