function dcheck --description 'Preview dcli sync + pacnew files + orphans'
    set_color cyan; echo "==> Checkupdates (pacman)"; set_color normal
    checkupdates 2>/dev/null; or echo "  none"

    set_color cyan; echo "==> AUR updates (yay)"; set_color normal
    yay -Qua 2>/dev/null; or echo "  none"

    set_color cyan; echo "==> .pacnew / .pacsave files"; set_color normal
    set -l pn (find /etc -type f \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null)
    if test -z "$pn"
        echo "  none"
    else
        for f in $pn
            echo "  $f"
        end
    end

    set_color cyan; echo "==> Orphans (pacman -Qdtq)"; set_color normal
    pacman -Qdtq 2>/dev/null; or echo "  none"

    set_color cyan; echo "==> Cache size"; set_color normal
    du -sh /var/cache/pacman/pkg 2>/dev/null

    set_color cyan; echo "==> Last dcli sync (git log arch-config)"; set_color normal
    git -C ~/.dotfiles log -1 --format='%ar  %s' -- .config/arch-config 2>/dev/null

    set_color yellow; echo ""; echo "Run 'dcli sync' to apply, then commit + push"; set_color normal
end
