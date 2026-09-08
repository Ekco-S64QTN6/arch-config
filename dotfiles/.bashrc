#!/usr/bin/env bash

# --- GLOBAL EXPORTS (Safe for all apps/scripts) ---
# Arch's system-wide file is /etc/bash.bashrc, not /etc/bashrc (that name is
# Fedora/RHEL). The old test never matched, so this never sourced anything.
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# Enable bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# History Settings
export HISTFILESIZE=10000
export HISTSIZE=10000
export HISTTIMEFORMAT="%F %T"
export HISTCONTROL=erasedups:ignoredups:ignorespace

# XDG Folders
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# Editor & Tooling
export EDITOR=nano
export VISUAL=nano

# Path & Libraries
# Prepend only if not already present. .bashrc gets sourced more than once
# (login shell -> .bash_profile -> .bashrc, then again by nested shells), and the
# old unconditional prepends grew PATH to 19 entries with /opt/cuda/bin,
# ~/.local/bin and the flatpak exports each appearing three times.
# Removes any existing occurrence first, then prepends. That way precedence
# stays exactly as written below (CUDA ahead of /usr/bin, as it was before)
# even when the system profile has already put an entry further down the list.
_path_prepend() {
    local d="$1" p=":${PATH}:"
    p="${p//:$d:/:}"
    p="${p#:}"; p="${p%:}"
    PATH="$d${p:+:$p}"
}
_path_prepend "$HOME/.local/share/flatpak/exports/bin"
_path_prepend "/var/lib/flatpak/exports/bin"
_path_prepend "$HOME/.cargo/bin"
_path_prepend "$HOME/.local/bin"
_path_prepend "/opt/cuda/bin"
export PATH
# NOTE: the :+ guard matters. A bare "$LD_LIBRARY_PATH" when the variable is
# unset leaves a trailing colon, and an empty element in the library search
# path means "the current directory" -- so any dir you cd into could hijack
# shared libraries for every binary you launch.
export LD_LIBRARY_PATH="/opt/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Project Specifics
# Credentials live in ~/.config/kaia/env (mode 0600), not here -- .bashrc is
# world-readable and mirrored to a public repo. Sourced only if present, so a
# fresh checkout of the dotfiles repo still works without it.
[ -r "$HOME/.config/kaia/env" ] && . "$HOME/.config/kaia/env"

# --- INTERACTIVE ONLY (Terminal usage, Kitty, etc.) ---
if [[ $- == *i* ]]; then
    # Fix the "White Flash" Visual Bell
    bind 'set bell-style none'

    # Bash behavior
    shopt -s checkwinsize
    shopt -s histappend
    PROMPT_COMMAND='history -a'

    # Keybinds
    # (a second 'bind "set bell-style visible"' used to live here and silently
    #  undid the bell-style none set above, which is what ~/.inputrc asks for)
    bind '"\C-f":"zi\n"'
    stty -ixon

    # Completion behavior
    bind "set completion-ignore-case on" 2>/dev/null
    bind "set show-all-if-ambiguous On" 2>/dev/null

    # Heavy Visual Tools (Loads only for YOU, not for background apps)
    fastfetch
    eval "$(starship init bash)"
    eval "$(zoxide init bash)"

    # Core Aliases
    alias lnp="~/github/dwarffortress/startlnp.sh"
    alias ls='ls --color=auto'
    alias ll='ls -la'
    alias la='ls -A'
    alias grep='grep --color=auto'
    alias cp='cp -i'
    alias mv='mv -i'
    alias rm='rm -i'
    alias ..='cd ..'
    alias catplease="curl -sL cataas.com/cat | kitty +kitten icat --align left"

    # Arch Linux Aliases
    alias update='sudo pacman -Syu'
    alias install='sudo pacman -S'
    alias remove='sudo pacman -Rns'
    alias search='pacman -Ss'
    alias cleanup='sudo pacman -Rns $(pacman -Qtdq)'
    alias yayf="paru -Slq | fzf --multi --preview 'paru -Sii {1}' --preview-window=down:75% | xargs -ro paru -S"

    # Git Aliases
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph --decorate'

    # Kitty Tools
    alias kssh="kitty +kitten ssh"

    # Functions
    extract() {
        for archive in "$@"; do
            if [ -f "$archive" ]; then
                case "$archive" in
                    *.tar.bz2|*.tbz2) tar xvjf "$archive" ;;
                    *.tar.gz|*.tgz)   tar xvzf "$archive" ;;
                    *.tar.xz)         tar xvJf "$archive" ;;
                    *.tar.zst)        tar --zstd -xvf "$archive" ;;
                    *.tar)            tar xvf "$archive" ;;
                    *.gz)             gunzip -k "$archive" ;;
                    *.bz2)            bunzip2 -k "$archive" ;;
                    *.zip)            unzip "$archive" ;;
                    *.rar)            unrar x "$archive" ;;
                    *.7z)             7z x "$archive" ;;
                    *)         echo "don't know how to extract '$archive'..." ;;
                esac
            else
                echo "'$archive' is not a valid file!"
            fi
        done
    }

    mkcd() { mkdir -p "$1" && cd "$1"; }

    cd() {
        if [ -n "$1" ]; then
            builtin cd "$@" && ls
        else
            builtin cd ~ && ls
        fi
    }

    # (An 'exec startx on tty1' block used to live here. SDDM is the display
    #  manager on this machine and ~/.xinitrc does not exist, so if it had ever
    #  fired it would have dropped you into a bare X session or just failed.)
fi



