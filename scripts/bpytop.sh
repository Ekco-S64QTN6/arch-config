#!/bin/bash

show_welcome_message() {
  clear
  if command -v lolcat &>/dev/null; then
    cat << "EOF" | lolcat
▓█████  ██ ▄█▀ ▄████▄   ▒█████
▓█   ▀  ██▄█▒ ▒██▀ ▀█  ▒██▒  ██▒
▒███   ▓███▄░ ▒▓█    ▄ ▒██░  ██▒
▒▓█  ▄ ▓██ █▄ ▒▓▓▄ ▄██▒▒██   ██░
░▒████▒▒██▒ █▄▒ ▓███▀ ░░ ████▓▒░
░░ ▒░ ░▒ ▒▒ ▓▒░ ░▒ ▒  ░░ ▒░▒░▒░ 
 ░ ░  ░░ ░▒ ▒░  ░  ▒     ░ ▒ ▒░ 
   ░   ░ ░░ ░ ░        ░ ░ ░ ▒  
   ░  ░░  ░   ░ ░          ░ ░  
              ░
EOF
  else
    echo -e "\033[1;36mbpytop Launcher\033[0m"
    echo -e "\n\033[1;34mThis script starts the bpytop system monitor.\033[0m\n"
  fi
  sleep 1
}

show_welcome_message

# Check if bpytop is installed, and install it if it's not
if ! command -v bpytop &>/dev/null; then
    # Previously this ran 'sudo pacman -S bpytop --noconfirm' on its own, which
    # escalated privilege and installed a package just because a binary was
    # missing. Tell the user instead and let them decide.
    echo "bpytop not found. Install it with:"
    echo "    sudo pacman -S bpytop"
    exit 1
fi

# This script launches bpytop because i can't remember "bpytop" on my own.

bpytop