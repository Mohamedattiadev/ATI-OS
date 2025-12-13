function fe
    set -l raw_paths (history | string match -ra '([~/]|\.\.?/)[^[:space:]:"\'\`]*')

    set -l existing_paths

    for item in $raw_paths
        set -l real_item (string replace '~' $HOME $item)
        if test -e "$real_item"
            set existing_paths $existing_paths $item
        end
    end

    if test (count $existing_paths) -eq 0
        echo "No valid file paths found in history."
        return 1
    end

    set -l selected (printf "%s\n" $existing_paths | sort -u | fzf_launcher)

    if test -n "$selected"
        set -l real_path (string replace '~' $HOME "$selected")
        nvim "$real_path"
    end

    commandline -f repaint
end
