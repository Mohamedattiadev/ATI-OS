function fzfsmartopen
    set selected (fd . ~/.config ~/Projects ~/Documents --hidden --follow --exclude .git \
        | sed "s|^$HOME|~|" \
        | fzf --reverse \
            --preview 'bat --style=numbers --color=always --line-range=:100 {} 2>/dev/null || exa -T {} 2>/dev/null' \
            --bind "change:top" \
            --tiebreak=begin,length \
            --info=inline \
            --ansi)

    if test -z "$selected"
        return
    end

    set realpath (string replace '~' $HOME $selected)

    copyq copy -- "$realpath"

    set editable_regex '\.(txt|md|sh|bash|zsh|fish|conf|ini|toml|yaml|yml|json|py|js|ts|cpp|c|h|java|go|rs|lua|php|rb|html|css|scss|svelte|vue|vim|vimrc|nvim|service)$'

    if test -d "$realpath"
        xdg-open "$realpath" >/dev/null 2>&1 &
    else if string match -r $editable_regex $realpath
        nvim "$realpath"
    else
        xdg-open "$realpath" >/dev/null 2>&1 &
    end
end
