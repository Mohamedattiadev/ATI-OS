function screenshot_todos_today
    set todo_file "$HOME/.config/rofi/Todo_files/todos.md"
    set today (date +%Y-%m-%d)
    set date_str (date +%d-%m-%Y)
    set outfile "$HOME/Pictures/todos-today-$date_str.png"

    # Grab today's todos
    set todays_todos (grep "@$today" "$todo_file")

    if test -z "$todays_todos"
        notify-send "No todos for today 🎉"
        return
    end

    # Build the content and pipe to silicon
    begin
        echo "## Todos for $date_str"
        echo
        for line in $todays_todos
            echo $line
        end
    end | silicon \
        --language markdown \
        --theme Dracula \
        --output "$outfile"

    # Copy to clipboard (X11 or Wayland)
    if type -q xclip
        xclip -selection clipboard -t image/png -i "$outfile"
    else if type -q wl-copy
        wl-copy <"$outfile"
    end

    notify-send "Today's todos saved → $outfile (copied ✅)"
end
