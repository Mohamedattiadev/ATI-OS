function zenmode --description "Toggle every qtile bar on/off"
    # Check if Qtile is running
    if not pgrep -x qtile >/dev/null
        echo "Qtile not running"
        return 1
    end

    set -l screens (qtile cmd-obj -o root -f eval -a "len(self.screens)" 2>/dev/null | string trim -c '"')
    if not string match -qr '^\d+$' -- "$screens"
        echo "Could not talk to qtile"
        return 1
    end

    # Derive the target state from the first bar we can read, so every bar
    # ends up in the same state instead of flip-flopping independently.
    set -l target
    for i in (seq 0 (math $screens - 1))
        for pos in top bottom
            set -l shown (qtile cmd-obj -o screen $i bar $pos -f eval -a "self.is_show()" 2>/dev/null | string trim -c '"')
            if test "$shown" = True
                set target False
                break
            else if test "$shown" = False
                set target True
                break
            end
        end
        if set -q target[1]
            break
        end
    end

    if not set -q target[1]
        echo "No qtile bars found"
        return 1
    end

    for i in (seq 0 (math $screens - 1))
        for pos in top bottom
            qtile cmd-obj -o screen $i bar $pos -f eval -a "self.show($target)" >/dev/null 2>&1
        end
    end

    if test "$target" = False
        echo "Zen mode on (bars hidden)"
    else
        echo "Zen mode off (bars shown)"
    end
end
