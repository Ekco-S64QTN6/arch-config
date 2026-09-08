#!/bin/bash
# ============================================================
# BACKUP STATUS
# How stale is the sdb2 backup? backup_home.sh is run by hand,
# so without this there is no signal at all.
#
# Reads a LOCAL stamp written by backup_home.sh Part B. The
# backup drive is udisks-mounted on demand, so a stamp living
# only on that drive would be unreadable most of the time.
#
# Exit: 0 fresh, 2 stale, 3 never run / no backup
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[1;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

STATE="$HOME/.local/state/backup-home/last-run-partB"
# Discover the backup drive by filesystem LABEL rather than hardcoding a UUID.
# A UUID pins this to one physical disk -- when that disk is replaced the script
# silently reports "not present" forever. Re-label the new drive "Backup Linux"
# and this keeps working.
BACKUP_LABEL="${BACKUP_LABEL:-Backup Linux}"
MOUNT="/run/media/$USER/$BACKUP_LABEL"
WARN_DAYS="${BACKUP_WARN_DAYS:-14}"
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    -h|--help)  echo "Usage: backup-status.sh [-q]   (warn after \$BACKUP_WARN_DAYS, default 14)"; exit 0 ;;
    *)          echo "Unknown option: $1"; exit 1 ;;
  esac; shift
done

show_welcome_message() {
  [ "$QUIET" -eq 1 ] && return 0
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
    echo -e "${CYAN}Backup Status${NC}"
  fi
  echo
}

show_welcome_message
say() { [ "$QUIET" -eq 1 ] || echo -e "$@"; }

say "${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  sdb2 OS backup (backup_home.sh Part B)${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"

rc=0
if [ ! -f "$STATE" ]; then
  echo -e "  ${RED}${BOLD}No successful backup on record.${NC}"
  echo -e "  ${RED}Either backup_home.sh has never completed Part B since this${NC}"
  echo -e "  ${RED}tracking was added, or every run has failed.${NC}"
  rc=3
else
  last=$(cat "$STATE" 2>/dev/null || echo 0)
  now=$(date +%s)
  age_d=$(( (now - last) / 86400 ))
  age_h=$(( (now - last) / 3600 ))
  when=$(date -d "@$last" '+%Y-%m-%d %H:%M')
  if [ "$age_d" -ge "$WARN_DAYS" ]; then
    echo -e "  ${YELLOW}${BOLD}[STALE]${NC} last successful backup: ${BOLD}$when${NC} (${age_d}d ago)"
    echo -e "  ${YELLOW}Threshold is ${WARN_DAYS}d. Run: ~/backup_home.sh${NC}"
    rc=2
  else
    if [ "$age_d" -ge 1 ]; then
      say "  ${GREEN}[OK]${NC} last successful backup: ${BOLD}$when${NC} (${age_d}d ago)"
    else
      say "  ${GREEN}[OK]${NC} last successful backup: ${BOLD}$when${NC} (${age_h}h ago)"
    fi
  fi
fi

# --- Is the drive even present / healthy enough to back up to? --------------
say ""
if [ -e "/dev/disk/by-label/${BACKUP_LABEL// /\\x20}" ]; then
  dev=$(readlink -f "/dev/disk/by-label/${BACKUP_LABEL// /\\x20}")
  say "  backup drive present: $dev"
  if findmnt -no TARGET "$MOUNT" >/dev/null 2>&1; then
    used=$(df -h "$MOUNT" 2>/dev/null | tail -1 | awk '{print $3" of "$2" ("$5")"}')
    say "  mounted at $MOUNT — $used"
    newest=$(find "$MOUNT/home/ekco" -maxdepth 2 -type f -printf '%T@ %TY-%Tm-%Td\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
    [ -n "${newest:-}" ] && say "  newest file in the backup's home: $newest"
  else
    say "  not mounted (udisks mounts on demand). To inspect it:"
    say "      udisksctl mount -b $dev"
  fi
else
  echo -e "  ${RED}${BOLD}[CRITICAL]${NC} no drive labelled '$BACKUP_LABEL' is attached."
  echo -e "  ${RED}There is currently no backup target attached to this machine.${NC}"
  rc=3
fi

# --- Standing caveats -------------------------------------------------------
say ""
say "${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  Caveats${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"
say "  ${YELLOW}Part A is DISABLED${NC} — its target was the failing Steam drive."
say "  Documents/Music/Pictures/Videos are still covered by Part B's full-system"
say "  sync, which only excludes .cache, Games, github, venv and the pacman cache."
say ""
say "  ${YELLOW}sdb2 is the ONLY backup target in this machine${NC}, it is the same"
say "  model and vintage as the drive that is failing, and it reported 2 pending"
say "  sectors on 2026-09-08. Run ~/drive-health.sh to re-check."

exit $rc
