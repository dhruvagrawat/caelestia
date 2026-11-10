# Personal fish config (fork only).
# Loaded at the end of config.fish via ~/.config/caelestia/user-config.fish (symlink to this file).

function shenv; set -gx $argv; end
test -f ~/.env && source ~/.env

# Remove upstream abbrs that clash with my aliases (abbrs win over aliases otherwise)
for a in gc ga gs ll
    abbr -q $a && abbr -e $a
end

#####################################
##==> Aliases
#####################################
alias cty='tty-clock -S -c -C 6 -t -n -D'
alias fucking='sudo'
alias n='nvim'
alias t='tmux'
alias ta='tmux attach'
alias tl='tmux ls'
alias cd..='cd ..'
alias ga='git add .'
alias gcm='git commit -m '
alias yeet='git push -u origin main'
alias gs='git status'
alias ll='ls -Alh'
alias ls='lsd --group-dirs first'
alias cat='bat'
alias gc='g++ -o o'
alias py='python3'
alias up='sudo pacman -Syu'
alias upy='yay -Syu'
alias clean='yay -Yc'
alias meow='showcat_random'

# Brightness on second monitor (ddcutil display 1): b0, b1, b10 ... b100
for v in 0 1 10 20 30 40 50 60 70 80 90 100
    alias b$v="ddcutil -d 1 setvcp 10 $v"
end

#####################################
##==> Functions
#####################################
function wget
    command wget --hsts-file="$XDG_DATA_HOME/wget-hsts" $argv
end

function nvidia-settings
    mkdir -p $XDG_CONFIG_HOME/nvidia/
    command nvidia-settings --config="$XDG_CONFIG_HOME/nvidia/settings" $argv
end

# Show a random cat image from ~/.local/share/cats (kitty only)
function showcat_random --argument-names size
    set -q size[1]; or set size 100x40
    set cats ~/.local/share/cats/cat_*.jpg
    if test (count $cats) -gt 0; and type -q kitty
        kitty +kitten icat --align center --place $size@0x0 $cats[(random 1 (count $cats))]
    end
end

# Greeting: padding + random cat
function fish_greeting
    for i in (seq 1 6); echo; end
    showcat_random 50x15
end

#####################################
##==> Dev tools
#####################################
command -v pyenv &> /dev/null && pyenv init - | source
