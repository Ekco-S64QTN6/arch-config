#!/bin/bash
# ============================================================
# UPDATE SNAPSHOT
# Records exactly which package versions were installed before
# an upgrade, so a bad -Syu can be rolled back precisely.
#
# Pairs with the paccache -rk2 change in update-system.sh: that
# keeps the previous version of every package in the cache, and
# this records WHICH version that was. Neither is much use alone.
#
# Exit: 0 ok, 1 error
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[1;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

SNAPDIR="${UPDATE_SNAPSHOT_DIR:-$HOME/.local/state/update-snapshots}"
KEEP="${UPDATE_SNAPSHOT_KEEP:-10}"
CACHE=/var/cache/pacman/pkg

usage() {
  cat <<'USAGE'
Usage: update-snapshot.sh [command]

  (no args)        Take a snapshot now
  -l, --list       List stored snapshots
  -d, --diff [A B] Compare two snapshots (default: the two most recent)
  -r, --rollback   Show pacman -U commands to undo the most recent change set
  -h, --help       This message

Snapshots live in ~/.local/state/update-snapshots (keeps the last 10).
USAGE
}

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
    echo -e "${CYAN}Update Snapshot${NC}"
  fi
  echo
}

snap_list() { find "$SNAPDIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort; }

take_snapshot() {
  local stamp dir
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="$SNAPDIR/$stamp"
  mkdir -p "$dir" || { echo -e "${RED}cannot create $dir${NC}"; exit 1; }

  pacman -Q            > "$dir/all.txt"       2>/dev/null
  pacman -Qe           > "$dir/explicit.txt"  2>/dev/null
  pacman -Qm           > "$dir/foreign.txt"   2>/dev/null
  uname -r             > "$dir/kernel.txt"    2>/dev/null
  date -Iseconds       > "$dir/taken-at.txt"  2>/dev/null

  echo -e "  ${GREEN}Snapshot ${BOLD}$stamp${NC}"
  echo "    packages: $(wc -l < "$dir/all.txt")  explicit: $(wc -l < "$dir/explicit.txt")  foreign: $(wc -l < "$dir/foreign.txt")"
  echo "    kernel:   $(cat "$dir/kernel.txt")"

  # Prune oldest beyond KEEP.
  local n
  n=$(snap_list | wc -l)
  if [ "$n" -gt "$KEEP" ]; then
    snap_list | head -n $(( n - KEEP )) | while read -r old; do
      rm -rf "${SNAPDIR:?}/$old" && echo "    pruned old snapshot $old"
    done
  fi
}

do_diff() {
  local a="${1:-}" b="${2:-}"
  if [ -z "$a" ] || [ -z "$b" ]; then
    mapfile -t all < <(snap_list)
    [ "${#all[@]}" -lt 2 ] && { echo -e "  ${YELLOW}Need at least 2 snapshots (have ${#all[@]}).${NC}"; exit 1; }
    a="${all[-2]}"; b="${all[-1]}"
  fi
  [ -f "$SNAPDIR/$a/all.txt" ] || { echo -e "${RED}no such snapshot: $a${NC}"; exit 1; }
  [ -f "$SNAPDIR/$b/all.txt" ] || { echo -e "${RED}no such snapshot: $b${NC}"; exit 1; }

  echo -e "  ${CYAN}${BOLD}$a${NC}  ->  ${CYAN}${BOLD}$b${NC}\n"

  join -j1 -o 0,1.2,2.2 \
       <(sort -k1,1 "$SNAPDIR/$a/all.txt") \
       <(sort -k1,1 "$SNAPDIR/$b/all.txt") 2>/dev/null \
    | awk '$2 != $3 {printf "    %-38s %s  ->  %s\n", $1, $2, $3}' > /tmp/.us_changed.$$
  comm -23 <(awk '{print $1}' "$SNAPDIR/$a/all.txt" | sort) \
           <(awk '{print $1}' "$SNAPDIR/$b/all.txt" | sort) > /tmp/.us_removed.$$
  comm -13 <(awk '{print $1}' "$SNAPDIR/$a/all.txt" | sort) \
           <(awk '{print $1}' "$SNAPDIR/$b/all.txt" | sort) > /tmp/.us_added.$$

  echo -e "  ${YELLOW}UPGRADED/DOWNGRADED ($(wc -l < /tmp/.us_changed.$$))${NC}"
  [ -s /tmp/.us_changed.$$ ] && cat /tmp/.us_changed.$$ || echo "    none"
  echo -e "\n  ${GREEN}ADDED ($(wc -l < /tmp/.us_added.$$))${NC}"
  [ -s /tmp/.us_added.$$ ] && sed 's/^/    /' /tmp/.us_added.$$ || echo "    none"
  echo -e "\n  ${RED}REMOVED ($(wc -l < /tmp/.us_removed.$$))${NC}"
  [ -s /tmp/.us_removed.$$ ] && sed 's/^/    /' /tmp/.us_removed.$$ || echo "    none"
  rm -f /tmp/.us_changed.$$ /tmp/.us_removed.$$ /tmp/.us_added.$$
}

do_rollback() {
  mapfile -t all < <(snap_list)
  [ "${#all[@]}" -lt 1 ] && { echo -e "  ${YELLOW}No snapshots stored.${NC}"; exit 1; }
  local prev="${all[-1]}"
  echo -e "  Comparing the CURRENT system against snapshot ${BOLD}$prev${NC}\n"

  local found=0 missing=0 cmd=""
  while read -r name oldver; do
    [ -z "${name:-}" ] && continue
    curver=$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')
    [ -z "${curver:-}" ] && continue
    [ "$curver" = "$oldver" ] && continue
    # Find that exact version in the pacman cache.
    pkgfile=$(find "$CACHE" -maxdepth 1 -name "${name}-${oldver}-*.pkg.tar.zst" 2>/dev/null | head -1)
    if [ -n "$pkgfile" ]; then
      echo -e "    ${GREEN}have${NC}   $name  $curver -> $oldver"
      cmd="$cmd $pkgfile"; found=$((found+1))
    else
      echo -e "    ${RED}MISSING${NC} $name  $curver -> $oldver  (not in $CACHE)"
      missing=$((missing+1))
    fi
  done < <(awk '{print $1, $2}' "$SNAPDIR/$prev/all.txt")

  echo
  if [ "$found" -eq 0 ]; then
    echo -e "  ${GREEN}Nothing differs from that snapshot — nothing to roll back.${NC}"
  else
    echo -e "  ${BOLD}$found package(s) can be rolled back, $missing missing from cache.${NC}\n"
    echo -e "  ${YELLOW}Review this before running it:${NC}\n"
    echo "    sudo pacman -U$cmd"
    echo
    echo -e "  ${YELLOW}Downgrading can break dependencies. Roll back the smallest set${NC}"
    echo -e "  ${YELLOW}that fixes your problem, not everything at once.${NC}"
  fi
}

case "${1:-}" in
  -l|--list)
    show_welcome_message
    echo -e "  ${CYAN}Stored snapshots in $SNAPDIR${NC}\n"
    if [ -z "$(snap_list)" ]; then echo "    none yet"; else
      snap_list | while read -r sd; do
        printf "    %-20s %5s pkgs  kernel %s\n" "$sd" \
          "$(wc -l < "$SNAPDIR/$sd/all.txt" 2>/dev/null)" "$(cat "$SNAPDIR/$sd/kernel.txt" 2>/dev/null)"
      done
    fi ;;
  -d|--diff)     show_welcome_message; do_diff "${2:-}" "${3:-}" ;;
  -r|--rollback) show_welcome_message; do_rollback ;;
  -h|--help)     usage ;;
  "")            show_welcome_message; take_snapshot ;;
  *)             echo "Unknown option: $1"; usage; exit 1 ;;
esac
