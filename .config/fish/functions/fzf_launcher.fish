function fzf_launcher
    # Check if the $TMUX variable is set (which means we are in tmux)
    if test -n "$TMUX"
        # Use the classic fzf-tmux script with the -p flag.
        # This creates a centered popup pane with a given height percentage.
        # It is the most compatible way to create a popup in tmux.
        fzf-tmux -p 90% $argv
    else
        # If not in tmux, just use the regular fzf command.
        # It will use the --height from FZF_DEFAULT_OPTS to create the popup.
        fzf $argv
    end
end
