#!/bin/bash

# ============================================================
# MOUNT POINTS
# ============================================================
#GAMES="/mnt/games"
SDB2="/mnt/backup_linux"
# ============================================================
# COLORS
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    echo -e "${CYAN}Home Directory Backup Utility${NC}"
  fi
  sleep 1
}

check_mount() {
  local path="$1"
  local name="$2"
  if ! mountpoint -q "$path" 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} $name is not mounted at $path. Skipping."
    return 1
  fi
  return 0
}

show_welcome_message

# ============================================================
# PART A — HOME DIRS → STEAM (sda1)   *** DISABLED ***
# Syncs Documents, Music, Pictures, Videos to Steam drive
# ------------------------------------------------------------
# Disabled 2026-09-07. The target drive is failing (SMART reported <24h of life
# remaining) and is pending physical removal, so this was writing the only second
# copy of ~64 GB of personal data onto a dying disk.
#
# sdb2 (Part B) is currently the only backup target in this machine.
#
# TO RE-ENABLE once a replacement drive is installed:
#   1. Uncomment the STEAM= line in the MOUNT POINTS block at the top
#      and point it at the new drive's mount point.
#   2. Uncomment this whole block.
# ============================================================
echo -e "\n${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}  PART A: SKIPPED (no backup drive)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}\n"
echo -e "${YELLOW}Home dirs are not being backed up. Re-enable Part A after${NC}"
echo -e "${YELLOW}installing a replacement for the failed Steam drive.${NC}\n"

# echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
# echo -e "${CYAN}  PART A: Home → Steam Backup${NC}"
# echo -e "${CYAN}═══════════════════════════════════════${NC}\n"
#
# if check_mount "$STEAM" "Steam drive"; then
#   for DIR in Documents Music Pictures Videos; do
#     echo -e "${YELLOW}Syncing ${DIR}...${NC}"
#     rsync -av --progress --delete-after --ignore-errors \
#       "$HOME/$DIR/" "$STEAM/$DIR/"
#     echo -e "${GREEN}✓ ${DIR} done${NC}\n"
#   done
# else
#   echo -e "${RED}Steam drive not available. Skipping Part A.${NC}"
# fi

# ============================================================
# PART B — OS BACKUP → sdb2 (old Arch fallback drive)
# Full system clone kept in sync with NVMe primary
# ============================================================
echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  PART B: NVMe OS → sdb2 Fallback Sync${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}\n"

if check_mount "$SDB2" "sdb2 fallback drive"; then
  # Logical dump of kaiadb first. rsync of /var/lib/postgres while the server
  # is running copies data files mid-write -- that copy may not start. A
  # pg_dump is transactionally consistent; it lands in ~ so the sync carries it.
  # Restore: createdb -U postgres kaiadb && pg_restore -U postgres -d kaiadb <file>
  DUMP_DIR="$HOME/.local/state/backup-home"
  mkdir -p "$DUMP_DIR"
  if pg_dump -U postgres -Fc kaiadb -f "$DUMP_DIR/kaiadb.dump.tmp" &&
     pg_dumpall -U postgres --globals-only -f "$DUMP_DIR/pg-globals.sql"; then
    mv "$DUMP_DIR/kaiadb.dump.tmp" "$DUMP_DIR/kaiadb.dump"
    chmod 600 "$DUMP_DIR/kaiadb.dump" "$DUMP_DIR/pg-globals.sql"
    echo -e "${GREEN}✓ kaiadb dumped${NC}"
  else
    rm -f "$DUMP_DIR/kaiadb.dump.tmp"
    echo -e "${RED}✗ pg_dump failed — kaiadb only covered by the raw (unsafe) file copy${NC}"
  fi

  echo -e "${YELLOW}Syncing OS to sdb2 fallback...${NC}"
  # ~/github used to be excluded wholesale ("it's on GitHub"), but gitignored
  # data -- GNN assets, Kaia storage/, Kaiacord knowledge_base, Kaiagotchi
  # pcaps, ~3.5G -- plus non-git folders and uncommitted work exist nowhere
  # else. Exclude only what rebuilds from source. Patterns are anchored under
  # ~/github: a bare 'venv/' would also drop /usr/lib/python3.*/venv.
  # Dungeon Hack+ builds are ~26M each and regenerate with dhplus.py; keep only
  # each build's saves and the files that say how to rebuild it identically.
  DH="$HOME/github/Dungeon Hack+/build"
  sudo rsync -aAXHv --progress --delete-after \
    --include="$DH/*/" \
    --include="$DH/*/savegame/***" \
    --include="$DH/*/MIX.TXT" \
    --include="$DH/*/MASHUP_BUILD.json" \
    --exclude="$DH/*/*" \
    --exclude=/dev \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/tmp \
    --exclude=/run \
    --exclude=/mnt \
    --exclude=/lost+found \
    --exclude=/var/cache/pacman/pkg \
    --exclude="$HOME/.cache" \
    --exclude="$HOME/Games" \
    --exclude="$HOME/venv" \
    --exclude="$HOME/github/**/venv/" \
    --exclude="$HOME/github/**/.venv/" \
    --exclude="$HOME/github/**/node_modules/" \
    --exclude="$HOME/github/**/__pycache__/" \
    --exclude="$HOME/github/Kaiacord/finetune/llama.cpp/" \
    --exclude="$HOME/github/GNN/trailer/build/" \
    / "$SDB2/"
  rsync_rc=$?

  if [ "$rsync_rc" -eq 0 ] || [ "$rsync_rc" -eq 24 ]; then
    # 24 = "some source files vanished during transfer", normal on a live system.
    echo -e "${GREEN}✓ OS backup to sdb2 done${NC}\n"
    # Record the run LOCALLY, not on the backup drive. The drive is udisks-mounted
    # on demand, so a stamp written only over there is unreadable whenever it is
    # unmounted -- which is most of the time. backup-status.sh reads this.
    mkdir -p "$HOME/.local/state/backup-home"
    date +%s > "$HOME/.local/state/backup-home/last-run-partB"
  else
    echo -e "${RED}✗ rsync exited $rsync_rc — backup INCOMPLETE, not recording a success${NC}\n"
  fi
else
  echo -e "${RED}sdb2 not available. Skipping Part B.${NC}"
fi

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  All backups complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}\n"
