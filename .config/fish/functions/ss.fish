function ss
    if test (count $argv) -eq 0
        echo "Usage: ss tag1 tag2 ..."
        return 1
    end

    set -l todo_file "$HOME/.config/rofi/Todo_files/todos.md"
    set -l date_str (date +%d-%m-%Y)
    set -l base "$HOME/Pictures/todos-$(string join _ $argv)-$date_str"
    set -l outfile "$base.png"

    # Auto-increment filename if exists
    set -l i 1
    while test -e "$outfile"
        set outfile "$base-$i.png"
        set i (math $i + 1)
    end

    # Build grep pattern for tags
    set -l patterns
    for tag in $argv
        set -l clean_tag (string trim -c '#' $tag)
        set patterns $patterns "@Tag\($clean_tag\)"
    end
    set -l pattern_str (string join "|" $patterns)

    # Search for matching todos
    set -l todos (grep -iE "$pattern_str" $todo_file 2>/dev/null)

    if test -z "$todos"
        notify-send "No todos found for tags: $argv 🎉"
        return
    end

    # Generate the image silently
    begin
        echo "## Todos with tags: $argv"
        echo
        for line in $todos
            echo $line
        end
    end | silicon \
        --language markdown \
        --theme Dracula \
        --output "$outfile" >/dev/null 2>&1

    if not test -e "$outfile"
        notify-send "Error: Failed to create image!"
        return 1
    end

    # Open in satty (suppressing all warnings)
    if type -q satty
        satty --filename "$outfile" 2>/dev/null &
        notify-send "Todos with tags $argv opened in satty"
    else
        notify-send "Image created → $outfile (satty not installed)"
    end
end
