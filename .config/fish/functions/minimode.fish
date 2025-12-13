function minimode
    echo "🟡 Entering Minimode (pausing heavy processes)..."

    # apps to manage
    set apps nvim google-chrome firefox zen-browser brave alacritty pcmanfm org.gnome.nautilus ticktick qutebrowser obsidian
    set current_ws (xdotool get_desktop)

    # collect all PIDs of windows in the current workspace
    set skip_pids ()
    for wid in (wmctrl -lp | awk '{print $1}')
        set ws (xprop -id $wid _NET_WM_DESKTOP 2>/dev/null | awk '{print $3}')
        if test "$ws" = "$current_ws"
            set pid (xprop -id $wid _NET_WM_PID 2>/dev/null | awk '{print $3}')
            if test -n "$pid"
                set skip_pids $skip_pids $pid
            end
        end
    end

    # pause all apps not in skip_pids
    for wid in (wmctrl -lp | awk '{print $1}')
        set wmclass (xprop -id $wid WM_CLASS 2>/dev/null | awk -F '"' '{print tolower($2)}')
        set pid (xprop -id $wid _NET_WM_PID 2>/dev/null | awk '{print $3}')

        if test -z "$wmclass" -o -z "$pid"
            continue
        end

        if contains $wmclass $apps
            if not contains $pid $skip_pids
                echo "Pausing $wmclass (PID $pid)"
                fish -c "pstree -p $pid | grep -o '([0-9]\+)' | tr -d '()' | xargs -I {} kill -STOP {}"
            end
        end
    end

    # pause running Docker containers
    if type -q docker
        set containers (docker ps -q --filter "status=running")
        if test (count $containers) -gt 0
            echo "Pausing Docker containers..."
            docker pause $containers
        end
    end

    # suspend tmux sessions
    if type -q tmux
        set sessions (tmux list-sessions -F '#S' 2>/dev/null)
        for s in $sessions
            set server_pid (pgrep -f "tmux: server" | head -n 1)
            if test -n "$server_pid"
                echo "Suspending tmux session $s (PID $server_pid)"
                fish -c "pstree -p $server_pid | grep -o '([0-9]\+)' | tr -d '()' | xargs -I {} kill -STOP {}"
            end
        end
    end

    echo "✅ Minimode applied. Use 'resumemode' to restore everything."
end
