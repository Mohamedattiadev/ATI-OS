#FIXME: under maintenance
set -g MINIMODE_LOG ~/.cache/minimode.log

function agrsmode
    echo "🔴 Aggressive mode: killing selected apps..."

    # apps we allow to be killed + restored later
    set apps google-chrome firefox obsidian nvim alacritty \
        org.gnome.nautilus pcmanfm ticktick qutebrowser \
        zen-browser

    # clear old log
    echo -n "" >$MINIMODE_LOG

    for wid in (wmctrl -lp | awk '{print $1}')
        set ws (xprop -id $wid _NET_WM_DESKTOP 2>/dev/null | awk '{print $3}')
        set wmclass (xprop -id $wid WM_CLASS 2>/dev/null | awk -F '"' '{print tolower($2)}')

        if test -z "$wmclass"
            continue
        end

        # only act if wmclass is in our apps list
        if contains $wmclass $apps
            echo "Killing $wmclass (window $wid) from workspace $ws"
            echo "$wmclass $ws" >>$MINIMODE_LOG
            xdotool windowkill $wid
        end
    end

    echo "✅ Aggressive mode complete. Log saved to $MINIMODE_LOG"
end
