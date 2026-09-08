#!/bin/bash

# --- Kaia's Comprehensive System Cleanup Script ---
# This script performs system-wide cleanup (Pacman cache, orphans, journal logs)
# and user-specific cleanup (old logs, backups, temporary database files in home).

show_welcome_message() {
  clear
  if command -v lolcat &>/dev/null; then
    cat << "EOF" | lolcat
▓█████  ██ ▄█▀ ▄████▄   ▒█████
▓█  ▀  ██▄█▒ ▒██▀ ▀█  ▒██▒  ██▒
▒███   ▓███▄░ ▒▓█    ▄ ▒██░  ██▒
▒▓█  ▄ ▓██ █▄ ▒▓▓▄ ▄██▒▒██   ██░
░▒████▒▒██▒ █▄▒ ▓███▀ ░░ ████▓▒░
░░ ▒░ ░▒ ▒▒ ▓▒░ ░▒ ▒   ░░ ▒░▒░▒░
  ░ ░  ░ ░▒ ▒░  ░  ▒     ░ ▒ ▒░
    ░  ░ ░░ ░ ░       ░ ░ ░ ▒
    ░  ░  ░   ░ ░         ░ ░
            ░
EOF
  else
    echo -e "\033[1;36mComprehensive System Cleanup\033[0m"
    echo -e "\n\033[1;34mThis script performs system-wide and user-specific file cleanup.\033[0m\n"
  fi
  sleep 1
}

# Ensure the script is run as root, as many cleanup tasks require sudo
if [ "$EUID" -ne 0 ]; then
  show_welcome_message # Show welcome even if not root, then advise
  echo "Error: This script must be run with sudo."
  echo "Usage: sudo ./clean_system.sh"
  exit 1
fi

show_welcome_message

echo "--- Starting System-Wide Cleanup ---"
echo ""

# --- 1. Install pacman-contrib if paccache is not found ---
echo "Checking for 'paccache'..."
if ! command -v paccache &> /dev/null; then
    echo "Error: paccache not found. Install it with:"
    echo "    sudo pacman -S pacman-contrib"
    exit 1
else
    echo "'paccache' is already installed."
fi
echo ""

# --- 2. Clean Pacman cache ---
echo "--- Cleaning Pacman Package Cache (/var/cache/pacman/pkg/) ---"
echo "Removing all cached versions of uninstalled packages..."
# 'paccache -r' alone keeps 3 versions of EVERYTHING, which is not what the
# line above claims. -ruk0 is the one that drops packages no longer installed.
paccache -ruk0

echo "Keeping only the latest two versions of installed packages for safety..."
paccache -rk2
echo ""

# --- 3. Remove Orphan Packages ---
echo "--- Checking for and Removing Orphan Packages ---"
# Orphan packages are dependencies that are no longer needed by any installed software.
ORPHANS=$(pacman -Qqtd)
if [ -n "$ORPHANS" ]; then
    echo "The following orphan packages have been identified and will be removed:"
    echo "---------------------------------------------------"
    echo "$ORPHANS"
    echo "---------------------------------------------------"
    read -rp "Do you want to proceed with removing these orphan packages? (y/N) " confirm_orphans
    if [[ "$confirm_orphans" =~ ^[Yy]$ ]]; then
        # Read into an array rather than relying on unquoted word splitting.
        mapfile -t orphan_list <<< "$ORPHANS"
        pacman -Rns "${orphan_list[@]}"
    else
        echo "Skipping removal of orphan packages."
    fi
else
    echo "No orphan packages found. Your system is lean!"
fi
echo ""

# --- 4. Clean up Journal Logs ---
echo "--- Cleaning Systemd Journal Logs ---"
echo "Keeping only the last 100MB of journal logs to free up space..."
journalctl --vacuum-size=100M
echo ""

# --- 5. Clean up Yay/AUR Cache (if yay is installed) ---
# This checked for 'yay', which is not installed -- paru is the AUR helper here,
# so the branch never ran and ~/.cache/paru was never cleaned.
if command -v paru &> /dev/null; then
    echo "--- Cleaning Paru/AUR Cache ---"
    echo "Running 'paru -Sc' to clean the AUR build cache..."
    sudo -u "${SUDO_USER:-ekco}" paru -Sc --noconfirm
    echo ""
else
    echo "Paru (AUR helper) not found. Skipping AUR cache cleanup."
fi

echo "--- Starting User-Specific File Cleanup in /home/ekco ---"
echo ""

# --- Scoped deletion helper -------------------------------------------------
# These sweeps used to run `find /home/ekco -name "*.log" -delete` across the
# WHOLE home directory. That is not safe here: Steam, Wine/Proton prefixes,
# Flatpak app data, git checkouts, venvs and model caches all keep .log/.old/
# .bak files they actively need -- Wine's *.old registry backups are literally
# how a broken prefix gets repaired. So: prune those trees, only touch files
# older than 30 days, and always show the list and ask before deleting.

PRUNE_DIRS=(
  "/home/ekco/.local/share/Steam"
  "/home/ekco/.local/lib"
  "/home/ekco/.steam"
  "/home/ekco/.var"
  "/home/ekco/.wine"
  "/home/ekco/.cache"
  "/home/ekco/.cargo"
  "/home/ekco/.rustup"
  "/home/ekco/.ollama"
  "/home/ekco/github"
  "/home/ekco/Games"
  "/home/ekco/venv"
)

# Build the -path A -o -path B ... expression find needs for pruning.
build_prune_expr() {
  prune_expr=()
  local first=1
  for d in "${PRUNE_DIRS[@]}"; do
    [ $first -eq 1 ] || prune_expr+=( -o )
    prune_expr+=( -path "$d" )
    first=0
  done
  for pat in "*/node_modules" "*/.git" "*/site-packages" "*/.venv"; do
    prune_expr+=( -o -path "$pat" )
  done
}
build_prune_expr

AGE_DAYS=30

# confirm_and_delete "<description>" <extra find predicates...>
confirm_and_delete() {
  local desc="$1"; shift
  local victims=()
  mapfile -t victims < <(
    find /home/ekco \( "${prune_expr[@]}" \) -prune -o \
         -type f -mtime "+${AGE_DAYS}" "$@" -print 2>/dev/null
  )

  if [ ${#victims[@]} -eq 0 ]; then
    echo "No $desc older than ${AGE_DAYS} days found."
    return 0
  fi

  echo "Found ${#victims[@]} $desc older than ${AGE_DAYS} days:"
  printf '  %s\n' "${victims[@]}" | head -n 20
  if [ ${#victims[@]} -gt 20 ]; then
    echo "  ... and $(( ${#victims[@]} - 20 )) more"
  fi

  read -rp "Delete these ${#victims[@]} files? (y/N) " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    printf '%s\0' "${victims[@]}" | xargs -0 -r rm -f --
    echo "Deleted ${#victims[@]} files."
  else
    echo "Skipping deletion of $desc."
  fi
}

# --- 6. Delete old log files (excluding my_combined_recent_logs.log) ---
echo "--- Old Log Files ---"
confirm_and_delete "log files" \
  -name "*.log" ! -name "my_combined_recent_logs.log"
echo ""

# --- 7. Delete old backup files ---
echo "--- Old Backup Files (*.old, *.bak, *~) ---"
# Wine/Proton registry backups (system.reg.old etc.) are how a broken prefix
# gets repaired, and prefixes turn up outside the pruned dirs too (e.g. under
# Documents). Never sweep those, wherever they live.
confirm_and_delete "backup files" \
  \( -name "*.old" -o -name "*.bak" -o -name "*~" \) \
  ! -name "system.reg.old" ! -name "user.reg.old" ! -name "userdef.reg.old"
echo ""

# --- 8. Delete temporary database log files (common in browser/snap caches) ---
# These are LevelDB journal files. They regenerate, but only sweep them when the
# owning application is closed -- deleting a live LevelDB's LOG is asking for
# trouble. Path-restricted, so pruning is not applied here.
echo "--- LevelDB / shared_proto_db Journal Files ---"
echo "(close browsers and Electron apps before answering yes)"
victims=()
mapfile -t victims < <(
  find /home/ekco -type f -mtime "+${AGE_DAYS}" \
    \( \( -name "*.log" -a \( -path "*/leveldb/*" -o -path "*/shared_proto_db/*" \) \) \
       -o -name "LOG.old" \) -print 2>/dev/null
)
if [ ${#victims[@]} -eq 0 ]; then
  echo "No stale LevelDB journal files found."
else
  echo "Found ${#victims[@]} LevelDB journal files older than ${AGE_DAYS} days."
  read -rp "Delete these ${#victims[@]} files? (y/N) " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    printf '%s\0' "${victims[@]}" | xargs -0 -r rm -f --
    echo "Deleted ${#victims[@]} files."
  else
    echo "Skipping deletion of LevelDB journal files."
  fi
fi
echo ""

echo "--- Comprehensive System Cleanup Complete! ---"
echo "Your system should now be much cleaner."
