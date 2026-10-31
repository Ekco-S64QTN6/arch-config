#!/bin/bash

# Check if lolcat is installed, and install it if it's not
if ! command -v lolcat &>/dev/null; then
  # Was 'sudo pacman -S lolcat --noconfirm'. The banner already falls back to
  # plain colours when lolcat is missing, so this only needs to be a hint.
  echo "lolcat not found (banner will render without it). Install with:"
  echo "    sudo pacman -S lolcat"
fi

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
 ░ ░  ░▒ ░▒ ▒░  ░  ▒     ░ ▒ ▒░ 
   ░   ░ ░░ ░ ░        ░ ░ ░ ▒  
   ░  ░░  ░   ░ ░          ░ ░  
              ░
EOF
  else
    echo -e "\033[1;36mSystem Update & Cleanup\033[0m"
    echo -e "\n\033[1;34mThis script updates packages and cleans up the system.\033[0m\n"
  fi
  sleep 1
}

show_welcome_message

# Record what is installed BEFORE touching anything, so a bad upgrade can be
# rolled back to exact versions. Pairs with the paccache -rk2 below, which is
# what keeps those versions available in the cache to roll back TO.
# The script is update-snapshot.sh in arch-config and xupdate-snapshot.sh in
# $HOME. Hardcoding one name silently skipped every snapshot from Oct 8 to 28.
snap=""
for s in "$HOME/update-snapshot.sh" "$HOME/xupdate-snapshot.sh"; do
  [ -x "$s" ] && { snap="$s"; break; }
done
if [ -n "$snap" ]; then
  "$snap" >/dev/null 2>&1 && \
    echo -e "\033[0;32mPre-update snapshot recorded.\033[0m" || \
    echo -e "\033[1;33mCould not record a pre-update snapshot (continuing).\033[0m"
else
  echo -e "\033[1;33mupdate-snapshot.sh not found -- no rollback record for this upgrade.\033[0m"
fi

# Update and upgrade packages (Arch based)
# NOTE: no --noconfirm. Arch's prompts are where you find out about package
# replacements, provider choices and conflicts -- answering them blind is how
# installs break.
sudo pacman -Syu

# Clean up old packages (Arch based)
# NOTE: paccache -rk2, NOT `pacman -Scc`. -Scc wipes the entire cache including
# the versions you currently have installed, which destroys your ability to
# downgrade right after an upgrade -- exactly when you'd need it. -rk2 keeps the
# current version plus one previous version of every package.
sudo paccache -rk2