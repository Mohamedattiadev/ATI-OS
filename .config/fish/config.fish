#  ____ _____
# |  _ \_   _|  Derek Taylor (DistroTube)
# | | | || |    http://www.youtube.com/c/DistroTube
# | |_| || |    http://www.gitlab.com/dwt1/
# |____/ |_|
#
#
# to make the tty colored
set -gx TCT_NO_RC_WARN 1
if test "$TERM" = linux; and not set -q TTY_COLORS_APPLIED
    set -gx TTY_COLORS_APPLIED 1
    ~/.config/tty-colors/tty-color-tool set-soft ~/.config/tty-colors/doom-one.colors
end

function fish_exit --on-event fish_exit
    # Only meaningful for a shell attached to a real terminal; running it in
    # `fish -c` / scripts just prints "reset: terminal attributes".
    if status is-interactive; and test -t 1
        reset
    end
end
#
#
# My fish config. Not much to see here; just some pretty standard stuff.

### ADDING TO THE PATH
# First line removes the path; second line sets it.  Without the first line,
# your path gets massive and fish becomes very slow.
#
# -g, not -U. Universal variables live in ~/.config/fish/fish_variables, and
# assigning one re-serializes that whole file to disk -- so setting it here,
# in a file that runs on every single shell launch, meant every new terminal
# did a pointless write (confirmed: fish_variables' mtime changed on each
# launch). It is also a race: two shells starting at once both rewrite the
# same file. A global is rebuilt from this line on every start anyway, which
# is exactly the intent, and it does not touch the disk.
set -e fish_user_paths
set -g fish_user_paths $HOME/.bin $HOME/.local/bin $HOME/.config/emacs/bin $HOME/Applications /var/lib/flatpak/exports/bin/ $HOME/Desktop $fish_user_paths

### EXPORT ###

set fish_greeting # Supresses fish's intro message
# Only fall back to xterm-256color when the terminal did not tell us what it
# is (or told us something we have no terminfo entry for). Overriding this
# unconditionally threw away kitty's xterm-kitty capabilities.
if not set -q TERM; or not infocmp "$TERM" >/dev/null 2>&1
    set -gx TERM xterm-256color
end
set -gx VISUAL nvim # $VISUAL use nvim in GUI mode
set -gx EDITOR nvim # $EDITOR use nvim in terminal
# -gx, not -Ux -- see the fish_user_paths note above for why universals are
# the wrong scope for anything assigned from config.fish. The -eU clears a
# stale universal left by the previous version; it is a silent no-op (status
# 4) once gone, so it costs nothing on later launches.
set -eU SUDO_EDITOR
set -gx SUDO_EDITOR nvim

# ---------------------------------------------------------------------
# Migrated out of fish_variables (2026-07-30)
# ---------------------------------------------------------------------
# These were universal variables, which live in .config/fish/fish_variables
# -- a file fish REWRITES at runtime. Committing it meant shipping this
# machine's state to every other machine: the tracked copy carried a PATH
# with ~/.cargo/bin three times over and dead /run/user/1000/fnm_multishells
# session paths that only ever existed on this laptop. Setting them here
# instead makes them versioned, reviewable, and identical everywhere, and
# lets fish_variables go back to being untracked runtime state.
#
# Each is guarded on the thing it points at, because the packages that
# provide them are opt-in (modules/optional.yaml): exporting JAVA_HOME to a
# path with no JDK behind it is worse than not exporting it.

# ~/tmp, not /tmp: /tmp is a tmpfs sized from RAM, and image/video work
# through it filled it on this machine. The wizard's image-envs module
# creates the directory.
set -gx TMPDIR $HOME/tmp
test -d $TMPDIR; or mkdir -p $TMPDIR

if test -d /usr/lib/jvm/default
    set -gx JAVA_HOME /usr/lib/jvm/default
end

if test -d $HOME/Android/Sdk
    set -gx ANDROID_HOME $HOME/Android/Sdk
    set -gx ANDROID_SDK_ROOT $HOME/Android/Sdk
    set -gx ADB_LIBUSB 0
end

if type -q google-chrome-stable
    set -gx CHROME_EXECUTABLE (command -v google-chrome-stable)
end

# Shared preview command for fzf and television. bat/eza/file is a
# deliberate fallback chain -- the first one present wins.
set -gx FZF_PREVIEW_OPTS "bat --style=numbers,changes --color=always --line-range=:100 {} || eza -T --icons {} || file {}"
set -gx TV_DEFAULT_OPTS "--height=60% --layout=reverse --multi --info=inline --tiebreak=begin,length --ansi --border=rounded --preview-window=right:55%:wrap --preview='bat --style=numbers,changes --color=always --paging=never {} || eza -T --icons {} || file {}'"

### SET MANPAGER
### Uncomment only one of these!

### "nvim" as manpager
set -x MANPAGER "nvim +Man!"

### "less" as manpager
# set -x MANPAGER "less"

### SET EITHER DEFAULT EMACS MODE OR VI MODE ###
function fish_user_key_bindings
    # fish_default_key_bindings
    fish_vi_key_bindings
end
### END OF VI MODE ###

### AUTOCOMPLETE AND HIGHLIGHT COLORS ###
set fish_color_normal brcyan
set fish_color_autosuggestion '#7d7d7d'
set fish_color_command brcyan
set fish_color_error '#ff6c6b'
set fish_color_param brcyan

### FUNCTIONS ###

# Functions needed for !! and !$
function __history_previous_command
    switch (commandline -t)
        case "!"
            commandline -t $history[1]
            commandline -f repaint
        case "*"
            commandline -i !
    end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

# The bindings for !! and !$
if [ "$fish_key_bindings" = fish_vi_key_bindings ]
    bind -Minsert ! __history_previous_command
    bind -Minsert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

# Function for creating a backup file
# ex: backup file.txt
# result: copies file as file.txt.bak
function backup --argument filename
    cp $filename $filename.bak
end

# Function for copying files and directories, even recursively.
# ex: copy DIRNAME LOCATIONS
# result: copies the directory and all of its contents.
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | trim-right /)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

# Function for printing a column (splits input on whitespace)
# ex: echo 1 2 3 | coln 3
# output: 3
function coln
    while read -l input
        echo $input | awk '{print $'$argv[1]'}'
    end
end

# Function for printing a row
# ex: seq 3 | rown 3
# output: 3
function rown --argument index
    sed -n "$index p"
end

# Function for ignoring the first 'n' lines
# ex: seq 10 | skip 5
# results: prints everything but the first 5 lines
function skip --argument n
    tail +(math 1 + $n)
end

# Function for taking the first 'n' lines
# ex: seq 10 | take 5
# results: prints only the first 5 lines
function take --argument number
    head -$number
end

#NOTE: used the rust tool pomodoro-tui
function pomo
    if test (count $argv) -eq 2
        pomodoro-tui -w $argv[1] -b $argv[2]
    else
        echo "Usage: pomo <work_minutes> <break_minutes>"
    end
end

# # Function for org-agenda
# function org-search -d "send a search string to org-mode"
#     set -l output (/usr/bin/emacsclient -a "" -e "(message \"%s\" (mapconcat #'substring-no-properties \
#         (mapcar #'org-link-display-format \
#         (org-ql-query \
#         :select #'org-get-heading \
#         :from  (org-agenda-files) \
#         :where (org-ql--query-string-to-sexp \"$argv\"))) \
#         \"
#     \"))")
#     printf $output
# end

function letsgo --description 'Start the X session (qtile) from a TTY'
    # No `exec`: it replaced the login shell, so if startx aborted (stale
    # lock, X already active, ...) the error flashed past and you landed
    # back at the login prompt with no shell to read it in -- a failure
    # and a success looked identical. Without exec the message stays on
    # screen, and you return to this shell when X exits.
    if pgrep -x Xorg >/dev/null
        echo "X is already running on :0 — switch to that VT (Ctrl+Alt+F1)."
        return 1
    end
    # Xorg normally removes this on exit; a lock left behind with no
    # server running is stale and blocks startx with "Server is already
    # active for display 0".
    if test -e /tmp/.X0-lock
        echo "Removing stale /tmp/.X0-lock left by an unclean exit."
        rm -f /tmp/.X0-lock
    end
    # Same class of leftover, different file. Every unclean X exit leaves its
    # MIT-MAGIC-COOKIE in ~/.Xauthority and startx adds a fresh one on top, so
    # entries for this display accumulate. startx then does:
    #
    #     authcookie=$(xauth list "$displayname" | sed ...)
    #     xauth -q -f "$xserverauthfile" << EOF
    #     add :$dummy . $authcookie
    #     EOF
    #
    # With more than one entry, $authcookie is multi-line and the extra
    # cookies land on their own lines inside the here-doc, where xauth reads
    # them as commands:
    #
    #     xauth: (stdin):2: unknown command "cd6ac1acd7289e776cc7554a586a1a71"
    #
    # Harmless to the session, but it is the first thing on screen at every
    # single login. We already know Xorg is not running (checked above), so
    # nothing needs these cookies -- drop them and let startx write exactly
    # one. `uname -n`, not `hostname`: hostname ships in inetutils and is not
    # installed here.
    if command -q xauth
        set -l host (uname -n)
        for d in :0 $host:0 $host/unix:0
            xauth remove $d 2>/dev/null
        end
    end
    dbus-run-session startx
end

function letshypr --description 'Start the Wayland session (Hyprland) from a TTY'
    # The Hyprland counterpart to `letsgo`. Deliberately a SEPARATE
    # function rather than a flag on that one: the two sessions have
    # different failure modes and different leftovers, and the whole
    # point of running both in parallel is that neither can break the
    # other by accident.
    #
    # No `exec`, for the same reason letsgo avoids it -- a failed launch
    # must leave its message on screen instead of dropping you back at
    # the login prompt with nothing to read.
    if pgrep -x Xorg >/dev/null
        echo "X is already running — quit qtile first, or switch to that VT."
        return 1
    end
    if pgrep -x Hyprland >/dev/null
        echo "Hyprland is already running — switch to that VT."
        return 1
    end
    # Hyprland requires a seat, and a TTY login has one only if logind
    # is tracking this session. Without it the compositor fails on DRM
    # master with a message that reads like a GPU fault rather than a
    # permissions problem, so check it here where it can be explained.
    if not test -n "$XDG_SESSION_ID"
        echo "No logind session — Hyprland needs a seat. Log in on a TTY, not via su."
        return 1
    end
    # keyd remaps Caps to Alt below the display server. If it is not up,
    # ~40 Hyprland bindings are silently dead, and the usual cause is a
    # kernel upgrade since the last reboot (uinput's module is gone from
    # /lib/modules until you boot the new kernel). Worth one line now
    # rather than ten minutes of wondering why Alt does nothing.
    if not systemctl is-active --quiet keyd
        echo "WARNING: keyd is not running — Caps will not act as Alt, and ~40 bindings need it."
        echo "         sudo systemctl status keyd   (after a kernel upgrade: reboot first)"
    end
    set -x XDG_SESSION_TYPE wayland
    set -x XDG_CURRENT_DESKTOP Hyprland
    set -x XDG_SESSION_DESKTOP Hyprland
    # Qt apps default to XWayland and then ignore fractional scaling;
    # qt5-wayland/qt6-wayland are installed precisely so this works.
    set -x QT_QPA_PLATFORM "wayland;xcb"
    set -x MOZ_ENABLE_WAYLAND 1
    # Electron apps (Telegram, Obsidian) need to be told, and silently
    # fall back to blurry XWayland rendering if they are not.
    set -x ELECTRON_OZONE_PLATFORM_HINT auto
    Hyprland
end

### END OF FUNCTIONS ###

### ALIASES ###
#ati alias
alias ati='cd $HOME/Attia-Pro/'
#clear
alias cl='clear'
#exit
alias e='exit'
alias ex='exit'
alias exi='exit'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

#tmux
alias tmuxdev='tmux new-session -A -s dev'
alias tmuxmedo='tmux new-session -A -s medo'

# Smart tmux wrapper
function tmux
    set -l cmds attach-session detach kill-server kill-session kill-pane kill-window \
        list-sessions ls new-session rename-session display-message show-messages \
        switch-client source-file run-shell save-buffer list-keys select-pane \
        split-window resize-pane move-window clock-mode send-keys capture-pane

    switch (count $argv)
        case 0
            command tmux
        case 1
            if contains $argv[1] $cmds
                command tmux $argv[1]
            else
                set -l session $argv[1]
                tmux has-session -t $session 2>/dev/null
                and command tmux attach-session -t $session
                or command tmux new-session -s $session
            end
        case '*'
            command tmux $argv
    end
end

# Kill all sessions except 'dev' and 'medo'
function tmuxDel
    for session in (tmux list-sessions -F '#S' 2>/dev/null)
        if not contains $session dev medo
            echo "Killing tmux session: $session"
            tmux kill-session -t $session
        end
    end
end

#img func
function img
    if not type -q imv
        echo "imv not found. Installing..."
        yay -S --noconfirm imv
    end

    imv \
        $argv
end

# Shared helpers for the pwd/which/path clipboard trio below: collapse $HOME
# to ~ (so copied paths read like they would in a prompt) and escape spaces
# (so the copied text pastes straight into a shell command without quoting).
function __fish_display_path
    set -l p (string replace --regex "^$HOME" "~" -- $argv[1])
    string replace -a " " "\ " -- $p
end

function __fish_clip_copy
    if not type -q xclip
        echo "xclip not found. Installing with yay..."
        yay -S --noconfirm xclip
    end
    printf '%s' "$argv[1]" | xclip -selection clipboard
end

# pwd: print the cwd (optionally with a path appended) and copy it to the
# clipboard, ~-collapsed and space-escaped. Absorbs the old "ppwd" variant --
# one command, always copies, no need to remember which name did what.
function pwd
    set -l full_path (builtin pwd)

    if test (count $argv) -ge 1
        set full_path "$full_path/$argv[1]"
    end

    set -l display_path (__fish_display_path $full_path)
    echo $display_path
    __fish_clip_copy $display_path
end

# which: resolve like the real `which`, but also copy the resolved path(s)
# to the clipboard using the same ~-collapse/escape convention as pwd/path.
function which
    set -l resolved (command which $argv 2>/dev/null)

    if test -z "$resolved"
        command which $argv
        return 1
    end

    set -l display_paths
    for p in $resolved
        set -a display_paths (__fish_display_path $p)
    end

    set -l joined (string join \n $display_paths)
    echo $joined
    __fish_clip_copy $joined
end

# path: fish ships a builtin `path` with its own subcommands (path
# extension/resolve/basename/...) -- scripts in this repo rely on those, so
# pass those straight through unshadowed. With no recognised subcommand,
# treat the args as files: resolve to an absolute path (like realpath),
# print ~-collapsed when under $HOME, and copy the result to the clipboard.
function path
    set -l builtin_subcommands basename dirname extension filter is mtime normalize resolve sort change-extension
    if test (count $argv) -ge 1; and contains -- $argv[1] $builtin_subcommands
        builtin path $argv
        return $status
    end

    if test (count $argv) -lt 1
        echo "Usage: path <file_or_dir> ..." >&2
        return 1
    end

    set -l display_paths
    for arg in $argv
        set -l resolved (realpath -- $arg 2>/dev/null)
        if test -z "$resolved"
            echo "path: no such file or directory: $arg" >&2
            continue
        end
        set -a display_paths (__fish_display_path $resolved)
    end

    if test (count $display_paths) -eq 0
        return 1
    end

    set -l joined (string join \n $display_paths)
    echo $joined
    __fish_clip_copy $joined
end

#NOTE:  used to source all the config files (fish, bash, zsh, etc)
function src
    echo "🔄 Reloading config files..."

    # Fish shell
    if test -f ~/.config/fish/config.fish
        source ~/.config/fish/config.fish
        echo "✅ Reloaded: config.fish"
    end

    # Bash
    if test -f ~/.bashrc
        bash -c "source ~/.bashrc"
        echo "✅ Reloaded: .bashrc"
    end

    # Zsh
    if test -f ~/.zshrc
        zsh -c "source ~/.zshrc"
        echo "✅ Reloaded: .zshrc"
    end

    # Profile (used by both Bash and others)
    if test -f ~/.profile
        bash -c "source ~/.profile"
        echo "✅ Reloaded: .profile"
    end

    echo "🚀 All configs sourced (in subshells where needed)"
end

#yay fzf
function yay
    if test (count $argv) -eq 0
        set selected (
            command yay -Sl | fzf --multi \
                --with-nth=2 \
                --preview 'clear ; yay -Si (echo {} | awk "{print \$2}")' \
                --preview-window=right:70%:wrap \
            | awk '{print $2}'
        )

        if test -n "$selected"
            command yay -S $selected
        end
    else
        command yay $argv
    end
end

# Remove packages with fzf
function yayd
    if test (count $argv) -eq 0
        set selected (
            pacman -Qq | fzf --multi \
                --preview 'clear; yay -Qi {}' \
                --preview-window=right:70%:wrap
        )

        if test -n "$selected"
            command yay -Rns $selected
        end
    else
        command yay -Rns $argv
    end
end

# nivm with fake daemon(nvim+tmux+nvr)
# NOTE: used the nvr (nvim remote) to have the tmux+nvr ,yay -S neovim-remote

# -------------------------------
# NEOVIM DAEMON (tmux + nvr)
# -------------------------------

set -g NVIM_DAEMON_SOCKET /tmp/nvimsocket
set -g NVIM_DAEMON_SESSION nvd

function __nvd_ensure
    # If socket exists, daemon is alive
    if test -S $NVIM_DAEMON_SOCKET
        return
    end

    # Kill broken session
    tmux kill-session -t $NVIM_DAEMON_SESSION 2>/dev/null

    # IMPORTANT: bypass fish functions here
    tmux new-session -d -s $NVIM_DAEMON_SESSION \
        "command nvim --listen $NVIM_DAEMON_SOCKET"

    # Wait for socket (no race)
    while not test -S $NVIM_DAEMON_SOCKET
        sleep 0.05
    end
end

function __nvd_open
    __nvd_ensure

    if test (count $argv) -gt 0
        nvr --servername $NVIM_DAEMON_SOCKET --remote-tab $argv
    end

    # Attach only if not already in tmux
    if not set -q TMUX
        tmux attach -t $NVIM_DAEMON_SESSION
    end
end

# ONE behavior for EVERYTHING
# function nvim
#     __nvd_open $argv
# end

function vim
    __nvd_open $argv
end

alias vi='vim'
alias v='vim'
alias n='nvim'
alias nv='nvim'
alias nvi='nvim'
#showkeys
alias showkeys="screenkey"

# vim and emacs
# alias vim='nvim'
# alias vi='nvim'
# alias v='vim'
# alias n='nvim'
# alias nv='nvim'
# alias nvi='nvim'
# alias nvim='nvim'

# alias em='/usr/bin/emacs -nw'
# alias emacs="emacsclient -c -a 'emacs'"
# alias rem="killall emacs || echo 'Emacs server not running'; /usr/bin/emacs --daemon"

#pgadmin4
# for the pgadmin4 database manager
alias pgadmin4="/usr/pgadmin4/bin/pgadmin4"

# ls | grep
alias lsg='ls | grep'

#Syncthing solve confliction with of todos
alias slc=" $HOME/.config/qtile/scripts/sync_todo_conflict_resolver.sh"

# df -disk usage
# NOTE: used python-rich to have the table format
alias df="python3 $HOME/.config/fish/scripts/df.py"
alias dfh="python3 $HOME/.config/fish/scripts/dfh"

# Changing "ls" to "eza"
# NOTE: used python-rich to have the table format (lst)
alias lst="python3 $HOME/.config/fish/scripts/lst.py"
alias ls='eza -al --color=always --group-directories-first' # my preferred listing
alias la='eza -a --color=always --group-directories-first' # all files and dirs
alias ll='eza -l --color=always --group-directories-first' # long format
alias lt='eza -aT --color=always --group-directories-first' # tree listing
alias l.='eza -a | egrep "^\."'

# pacman and yay
alias pacsyu='sudo pacman -Syu' # update only standard pkgs
alias pacsyyu='sudo pacman -Syyu' # Refresh pkglist & update standard pkgs
alias parsua='paru -Sua --noconfirm' # update only AUR pkgs (paru)
alias parsyu='paru -Syu --noconfirm' # update standard pkgs and AUR pkgs (paru)
alias unlock='sudo rm /var/lib/pacman/db.lck' # remove pacman lock
alias cleanup='sudo pacman -Rns (pacman -Qtdq)' # remove orphaned packages (DANGEROUS!)

# get fastest mirrors
alias mirror="sudo reflector -f 30 -l 30 --number 10 --verbose --save /etc/pacman.d/mirrorlist"
alias mirrord="sudo reflector --latest 50 --number 20 --sort delay --save /etc/pacman.d/mirrorlist"
alias mirrors="sudo reflector --latest 50 --number 20 --sort score --save /etc/pacman.d/mirrorlist"
alias mirrora="sudo reflector --latest 50 --number 20 --sort age --save /etc/pacman.d/mirrorlist"

# Colorize grep output (good for log files)
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# adding flags
# alias df='df -h' # human-readable sizes
alias free="python3 $HOME/.config/fish/scripts/free.py"

# ps
alias psa="ps auxf"
alias psgrep="ps aux | grep -v grep | grep -i -e VSZ -e"
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

# Merge Xresources
alias merge='xrdb -merge ~/.Xresources'

# git
alias addup='git add -u'
alias addall='git add .'
alias branch='git branch'
alias checkout='git checkout'
alias clone='git clone'
alias commit='git commit -m'
alias fetch='git fetch'
alias pull='git pull origin'
alias push='git push origin'
alias tag='git tag'
alias newtag='git tag -a'

# get error messages from journalctl
alias jctl="journalctl -p 3 -xb"

# gpg encryption
# verify signature for isos
alias gpg-check="gpg2 --keyserver-options auto-key-retrieve --verify"
# receive the key of a developer
alias gpg-retrieve="gpg2 --keyserver-options auto-key-retrieve --receive-keys"

# Play audio files in current dir by type
alias playwav='vlc *.wav'
alias playogg='vlc *.ogg'
alias playmp3='vlc *.mp3'

# Play video files in current dir by type
alias playavi='vlc *.avi'
alias playmov='vlc *.mov'
alias playmp4='vlc *.mp4'

# switch between shells
alias tobash="sudo chsh $USER -s /bin/bash && echo 'Now log out.'"
alias tozsh="sudo chsh $USER -s /bin/zsh && echo 'Now log out.'"
alias tofish="sudo chsh $USER -s /bin/fish && echo 'Now log out.'"

# bare git repo alias for dotfiles
# alias config="/usr/bin/git --git-dir=$HOME/dotfiles --work-tree=$HOME"
alias cf="nvim $HOME/.config"

# termbin
alias tb="nc termbin.com 9999"

# the terminal rickroll
alias rr='curl -s -L https://raw.githubusercontent.com/keroserene/rickrollrc/master/roll.sh | bash'

# Mocp must be launched with bash instead of Fish!
alias mocp="bash -c mocp"

### RANDOM COLOR SCRIPT ###
# Get this script from my GitLab: gitlab.com/dwt1/shell-color-scripts
# Or install it from the Arch User Repository: shell-color-scripts
# colorscript_fit (functions/colorscript_fit.fish) picks only scripts that
# fit $COLUMNS, so wide art (e.g. rupees, 167 cols) doesn't wrap and glitch
# in a non-maximized terminal.
if status is-interactive
    colorscript_fit
end

### SETTING THE STARSHIP PROMPT ###
if status is-interactive
    starship init fish | source
end

### tmuxifier ###
set -gx PATH $HOME/.tmux/plugins/tmuxifier/bin $PATH
#eval (tmuxifier init - fish)

### fcitx for lang ###
set -x GTK_IM_MODULE fcitx
set -x QT_IM_MODULE fcitx
set -x SDL_IM_MODULE fcitx
set -x XMODIFIERS '@im=fcitx'

# pnpm
set -gx PNPM_HOME "$HOME/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

# fnm (nvm alter)
# --use-on-cd auto-switches Node per .nvmrc when you cd into a project
if type -q fnm
    fnm env --use-on-cd --shell fish | source
end

# =============================================================================
# FZF Configuration
# =============================================================================

# Set default fzf options for a large, borderless popup UI

# -gx, not -Ux (see the fish_user_paths note above). This one was the worst
# offender: a ~600-byte string rewritten into fish_variables on every launch.
set -eU FZF_DEFAULT_OPTS
set -gx FZF_DEFAULT_OPTS "\
--height=60% \
--layout=reverse \
--multi \
--info=inline \
--tiebreak=begin,length \
--ansi \
--border=rounded \
--color=fg:#bbc2cf,bg:#282c34,hl:#51afef \
--color=fg+:#eeeeee,bg+:#3e4451,hl+:#51afef \
--color=info:#c678dd,prompt:#98be65,pointer:#ff6c6b \
--color=marker:#da8548,spinner:#61afef,header:#51afef \
--preview-window=right:55%:wrap \
--preview='clear; bat --style=numbers,changes --color=always --paging=never {} || exa -T --icons {} || file {}'"

# --- Keybinding OtPTIONS ---

# Ctrl+T - Find files and directories
set -g fzf_fd_opts --hidden --follow --exclude .git

# Alt+C - Change directory
set -g fzf_alt_c_opts # Options can be added here if needed

# Ctrl+R - Search command history (now copies on Enter)
set -g fzf_history_opts '\
--preview-window=right:55%:wrap \
--preview="echo {} | clear; bat --language=sh --color=always" \
--bind="ctrl-y:execute-silent(echo -n {1..} | command copyq copy --)+abort" \
--bind="enter:accept+execute(echo -n {1..} | command copyq copy --)"'

# --- Custom Keybindings ---

# Bind Ctrl+O to find a file from history and edit it in default and insert modes
bind \co fe
bind -M insert \co fe

# --- ACTIVATE FZF KEYBINDINGS ---
# This enables the default Ctrl+T, Ctrl+R, and Alt+C behaviors.
# It MUST come before any overrides.
fzf --fish | source

# Override the default Ctrl+T behavior to open the selected file(s) in nvim
function fzf-file-widget
    # Use our new launcher instead of calling fzf directly
    set -l selected (fd --type f $fzf_fd_opts | fzf_launcher)
    if test -n "$selected"
        nvim $selected
    end
    commandline -f repaint
end

# =============================================================================
# FZF Configuration END
# =============================================================================

# pyenv
set -gx PYENV_ROOT $HOME/.pyenv
set -gx PATH $PYENV_ROOT/bin $PATH

# Initialize pyenv
status --is-interactive; and source (pyenv init -|psub)

#zoxide
zoxide init fish | source

#Cargo
if test -d $HOME/.cargo/bin
    set -gx PATH $HOME/.cargo/bin $PATH
end
