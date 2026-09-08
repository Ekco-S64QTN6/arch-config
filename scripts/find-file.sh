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
 ░ ░  ░░ ░▒ ▒░  ░  ▒     ░ ▒ ▒
   ░   ░ ░░ ░ ░        ░ ░ ░ ▒  
   ░  ░░  ░   ░ ░          ░ ░  
              ░
EOF
  else
    echo -e "\033[1;36mFile Finder\033[0m"
    echo -e "\n\033[1;34mThis script finds files by name, case-insensitively.\033[0m\n"
  fi
  sleep 1
}

show_welcome_message

# Find a file by name (case-insensitive)
read -rp "Enter filename to find: " filename
find . -iname "*$filename*" 2>/dev/null  # 2>/dev/null suppresses error messages if no match is found
