function colorscript_fit --description 'Run a random color-script (stock + custom) that fits the terminal width'
    set -l stock_dir /opt/shell-color-scripts/colorscripts
    set -l custom_dir $__fish_config_dir/colorscripts
    set -l cache_file $HOME/.cache/colorscript-fit-widths.tsv

    set -l scripts
    for d in $stock_dir $custom_dir
        test -d $d; or continue
        for f in $d/*
            test -f $f; and test -x $f; and set -a scripts $f
        end
    end
    if test (count $scripts) -eq 0
        return
    end

    # Each script's widest visible column (ANSI stripped) is cached so a
    # normal shell startup doesn't have to execute every script just to
    # measure it. Wide ones (e.g. stock "rupees" at 167 cols) wrap and glitch
    # in anything narrower than a maximized terminal, so only scripts that
    # actually fit $COLUMNS are eligible.
    set -l rebuild 0
    if not test -f $cache_file
        set rebuild 1
    else if test (count (cat $cache_file)) -ne (count $scripts)
        # a script was added or removed since the cache was built
        set rebuild 1
    else
        set -l cache_mtime (stat -c %Y $cache_file)
        for s in $scripts
            if test (stat -c %Y $s) -gt $cache_mtime
                set rebuild 1
                break
            end
        end
    end

    if test $rebuild -eq 1
        mkdir -p (dirname $cache_file)
        set -l tmp $cache_file.tmp.$fish_pid
        for s in $scripts
            set -l w ($s 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' | awk '{ if (length($0)>m) m=length($0) } END { print m+0 }')
            printf '%s\t%s\n' $s $w >> $tmp
        end
        mv $tmp $cache_file
    end

    set -l cols $COLUMNS
    if test -z "$cols"
        set cols (tput cols 2>/dev/null; or echo 80)
    end

    set -l candidates
    while read -l line
        set -l parts (string split \t -- $line)
        if test (count $parts) -eq 2; and test $parts[2] -le $cols
            set -a candidates $parts[1]
        end
    end < $cache_file

    if test (count $candidates) -eq 0
        # Terminal too narrow for even the smallest art; skip rather than glitch.
        return
    end

    set -l pick $candidates[(random 1 (count $candidates))]
    $pick
end
