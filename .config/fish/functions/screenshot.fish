function screenshot
    if test (count $argv) -lt 1
        echo "Usage: screenshot <file-path> [theme]"
        return 1
    end

    set infile $argv[1]
    set theme (or $argv[2] Dracula)

    if not test -f $infile
        echo "Error: File '$infile' not found."
        return 1
    end

    set date_str (date +%d-%m-%Y_%H-%M-%S)
    set outdir "$HOME/Pictures"
    set outfile "$outdir/screenshot-$date_str.png"
    mkdir -p $outdir

    # Detect language from extension
    set ext (path extension $infile | string trim -c '.')
    set lang_map \
        py:python ipynb:python \
        js:javascript jsx:javascript ts:typescript tsx:typescript \
        sh:shell bash:shell fish:shell zsh:shell \
        md:markdown markdown:markdown rst:markdown \
        html:html htm:html xml:xml \
        css:css scss:css less:css \
        json:json toml:toml ini:toml conf:toml \
        yml:yaml yaml:yaml \
        c:c h:c \
        cpp:cpp cc:cpp cxx:cpp hpp:cpp \
        java:java kt:kotlin \
        go:go rs:rust \
        php:php rb:ruby pl:perl \
        swift:swift dart:dart \
        lua:lua \
        sql:sql \
        tex:latex \
        dockerfile:dockerfile \
        make:makefile Makefile:makefile \
        asm:asm
    set lang ''
    for mapping in $lang_map
        set kv (string split ':' $mapping)
        if test "$ext" = $kv[1]
            set lang $kv[2]
        end
    end

    # Run silicon
    if test -n "$lang"
        silicon "$infile" --language $lang --theme $theme --output "$outfile"
    else
        silicon "$infile" --theme $theme --output "$outfile"
    end

    # Copy to clipboard
    if type -q xclip
        xclip -selection clipboard -t image/png -i "$outfile"
    else if type -q wl-copy
        wl-copy <"$outfile"
    end

    notify-send "Screenshot of '$infile' saved → $outfile (copied ✅)"
end
