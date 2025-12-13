#FIXME: under maintenance
function restoremode
    set -g MINIMODE_LOG ~/.cache/minimode.log
    set with_nvim 0

    if test (count $argv) -gt 0
        if test $argv[1] = --with-nvim
            set with_nvim 1
        end
    end

    echo "🔵 Restoring apps from log..."

    if not test -f $MINIMODE_LOG
        echo "No log found."
        return
    end

    for entry in (cat $MINIMODE_LOG)
        set wmclass (echo $entry | awk '{print $1}')
        set ws (echo $entry | awk '{print $2}')
        set title (echo $entry | cut -d " " -f3-) # everything after workspace

        # skip restoring alacritty itself
        if test $wmclass = alacritty
            echo "⏭️  Skipping alacritty..."
            continue
        end

        # skip restoring nvim unless explicitly requested
        if test $wmclass = nvim -a $with_nvim -eq 0
            echo "⏭️  Skipping nvim (use --with-nvim to restore)..."
            continue
        end

        echo "Restarting $wmclass in workspace $ws"

        switch $wmclass
            case google-chrome
                google-chrome & disown
            case firefox
                firefox & disown
            case obsidian
                obsidian & disown
            case nvim
                if test -n "$title"
                    alacritty -e nvim "$title" & disown
                else
                    alacritty -e nvim & disown
                end
            case org.gnome.nautilus
                nautilus & disown
            case pcmanfm
                pcmanfm & disown
            case ticktick
                ticktick & disown
            case qutebrowser
                if test -n "$title"
                    qutebrowser "$title" & disown
                else
                    qutebrowser & disown
                end
            case zen-browser
                zen-browser & disown
            case brave
                brave & disown
            case '*'
                echo "⚠️  No mapping for $wmclass, trying to launch directly..."
                $wmclass & disown
        end

        sleep 1

        # move window to its original workspace
        set new_wid (wmctrl -lp | while read -l line
            set wid (echo $line | awk '{print $1}')
            set cls (xprop -id $wid WM_CLASS 2>/dev/null | awk -F '"' '{print tolower($2)}')
            if test "$cls" = "$wmclass"
                echo $wid
                break
            end
        end)

        if test -n "$new_wid"
            wmctrl -i -r $new_wid -t $ws
        else
            echo "⚠️  Could not find new window for $wmclass"
        end
    end

    # clear the log after restore
    echo -n "" >$MINIMODE_LOG

    echo "✅ Restore attempt complete."
end
