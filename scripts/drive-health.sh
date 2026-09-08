#!/bin/bash
# ============================================================
# DRIVE HEALTH CHECK
# Reads the SMART ATTRIBUTES that actually predict failure, not
# just the pass/fail summary.
#
# WHY THIS EXISTS: `smartctl -H` only reports whether a drive has
# crossed the vendor's own failure threshold. On 2026-09-07 sdb
# reported "PASSED" while carrying 2 Current_Pending_Sector and
# 2 Reallocated_Sector_Ct. Those climb for months before -H trips.
# A drive reads PASSED right up until it doesn't.
#
# Handles both ATA/SATA and NVMe via smartctl's JSON output.
# Needs root (SMART reads require it).
#
# Exit: 0 all healthy, 2 warnings, 3 critical, 1 error
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[1;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

QUIET=0; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet)  QUIET=1 ;;
    -o|--report) shift; REPORT="${1:-}"; [ -z "$REPORT" ] && { echo "--report needs a path"; exit 1; } ;;
    -h|--help)   echo "Usage: drive-health.sh [-q] [-o report.txt]"; exit 0 ;;
    *)           echo "Unknown option: $1"; exit 1 ;;
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
    echo -e "${CYAN}Drive Health Check${NC}"
  fi
  echo -e "\n${CYAN}Reading the SMART attributes that predict failure.${NC}\n"
  sleep 1
}

command -v smartctl &>/dev/null || { echo -e "${RED}smartctl not found: sudo pacman -S smartmontools${NC}"; exit 1; }
command -v jq       &>/dev/null || { echo -e "${RED}jq not found: sudo pacman -S jq${NC}"; exit 1; }
[ "$EUID" -eq 0 ] || { echo -e "${RED}SMART data requires root. Run: sudo $0${NC}"; exit 1; }

show_welcome_message
[ -n "$REPORT" ] && : > "$REPORT"

WARNINGS=0; CRITICALS=0
emit() { echo -e "$@"; [ -n "$REPORT" ] && echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT"; }
crit() { emit "    ${RED}${BOLD}[CRITICAL]${NC} $*"; CRITICALS=$((CRITICALS+1)); }
warn() { emit "    ${YELLOW}[WARN]${NC}     $*"; WARNINGS=$((WARNINGS+1)); }
ok()   { [ "$QUIET" -eq 1 ] || emit "    ${GREEN}[OK]${NC}       $*"; }
info() { [ "$QUIET" -eq 1 ] || emit "    ${CYAN}[info]${NC}     $*"; }

# ATA attribute IDs that actually predict failure, with the threshold at which
# a non-zero raw value stops being noise. 0 means "any non-zero value matters".
#   5   Reallocated_Sector_Ct    sectors already remapped to spares
#   187 Reported_Uncorrect       errors the drive could not fix
#   188 Command_Timeout          controller/cable trouble
#   197 Current_Pending_Sector   failed to read, awaiting reallocation  <-- the loud one
#   198 Offline_Uncorrectable    unreadable and unrecoverable
#   199 UDMA_CRC_Error_Count     cable/connector errors, usually not the disk itself
declare -A CRIT_ATTRS=( [5]="Reallocated sectors" [197]="Pending sectors" [198]="Offline uncorrectable" [187]="Reported uncorrectable" )
declare -A WARN_ATTRS=( [188]="Command timeouts" [199]="UDMA CRC errors (check the SATA cable)" )

check_drive() {
  local dev="$1" json type model serial
  json="$(smartctl --json -x "$dev" 2>/dev/null)"
  [ -z "$json" ] && { warn "$dev: smartctl returned nothing"; return; }

  type=$(jq -r '.device.type // "unknown"' <<<"$json")
  model=$(jq -r '.model_name // "?"'       <<<"$json")
  serial=$(jq -r '.serial_number // "?"'   <<<"$json")

  emit "\n  ${BOLD}$dev${NC}  $model  (serial $serial)"

  # Overall pass/fail -- necessary but NOT sufficient, hence everything below.
  local passed
  passed=$(jq -r '.smart_status.passed // empty' <<<"$json")
  case "$passed" in
    true)  info "smartctl -H says PASSED (threshold not crossed -- see attributes below)" ;;
    false) crit "smartctl -H says FAILING -- replace this drive now" ;;
    *)     warn "no overall health status reported" ;;
  esac

  local hours
  hours=$(jq -r '.power_on_time.hours // empty' <<<"$json")
  [ -n "$hours" ] && info "power-on hours: $hours ($(( hours / 24 )) days, $(( hours / 8760 )) years)"

  if [ "$type" = "nvme" ] || jq -e '.nvme_smart_health_information_log' >/dev/null 2>&1 <<<"$json"; then
    # --- NVMe ---------------------------------------------------------------
    local used spare spare_thr media err crit_warn
    used=$(jq -r      '.nvme_smart_health_information_log.percentage_used // empty'          <<<"$json")
    spare=$(jq -r     '.nvme_smart_health_information_log.available_spare // empty'          <<<"$json")
    spare_thr=$(jq -r '.nvme_smart_health_information_log.available_spare_threshold // empty'<<<"$json")
    media=$(jq -r     '.nvme_smart_health_information_log.media_errors // 0'                 <<<"$json")
    err=$(jq -r       '.nvme_smart_health_information_log.num_err_log_entries // 0'          <<<"$json")
    crit_warn=$(jq -r '.nvme_smart_health_information_log.critical_warning // 0'             <<<"$json")

    # Written as if/elif rather than A && B || C: with the chained form, C also
    # runs whenever B fails, which is not what "else" means.
    if [ -n "$used" ]; then
      if   [ "$used" -ge 90 ]; then crit "endurance used: ${used}% -- at or past end of rated life"
      elif [ "$used" -ge 70 ]; then warn "endurance used: ${used}%"
      else                          ok   "endurance used: ${used}%"
      fi
    fi
    if [ -n "$spare" ] && [ -n "$spare_thr" ]; then
      if [ "$spare" -le "$spare_thr" ]; then
        crit "available spare ${spare}% is at/below threshold ${spare_thr}%"
      else
        ok "available spare: ${spare}% (threshold ${spare_thr}%)"
      fi
    fi
    if [ "$media" -gt 0 ]; then crit "media and data integrity errors: $media"
    else                        ok   "no media/data integrity errors"; fi
    [ "$crit_warn" -gt 0 ] && crit "NVMe critical warning bitfield: $crit_warn"
    [ "$err" -gt 0 ]       && info "error log entries: $err (informational)"
  else
    # --- ATA / SATA ---------------------------------------------------------
    # Severity uses the vendor's own normalised scale, not just "raw > 0".
    #
    # A raw count above zero is not automatically critical on an SSD: these
    # drives retire blocks as ordinary wear, and a handful out of thousands is
    # expected. The normalised value (100 = perfect, counting down to the
    # failure threshold) is how the vendor rates it. Reading only the raw count
    # flagged two healthy-by-spec SSDs as CRITICAL.
    #
    # Pending sectors are treated more harshly than reallocated ones either way:
    # a pending sector is a read that FAILED and has not yet been remapped, so
    # data may already be unreadable. A reallocated sector was successfully
    # moved.
    local found=0 id name raw val thresh
    while IFS=$'\t' read -r id name raw val thresh; do
      [ -z "${id:-}" ] && continue
      found=1
      local label="${CRIT_ATTRS[$id]:-${WARN_ATTRS[$id]:-}}"
      [ -z "$label" ] && continue
      [ "$raw" -gt 0 ] 2>/dev/null || continue

      local margin="n/a"
      if [ "${val:-}" != "null" ] && [ "${thresh:-}" != "null" ] 2>/dev/null; then
        margin="normalised ${val}, fails at ${thresh}"
      fi

      # Below or at the vendor threshold: the drive itself calls this failure.
      if [ "${val:-999}" != "null" ] && [ "${thresh:-0}" != "null" ] \
         && [ "$val" -le "$thresh" ] 2>/dev/null; then
        crit "${label} (attr $id $name): raw ${BOLD}$raw${NC} — AT VENDOR FAILURE THRESHOLD ($margin)"
      elif [ "$id" = "197" ] || [ "$id" = "198" ]; then
        # Unreadable sectors matter regardless of headroom.
        warn "${label} (attr $id $name): raw ${BOLD}$raw${NC} — unreadable sectors present ($margin)"
      elif [ -n "${CRIT_ATTRS[$id]:-}" ]; then
        info "${label} (attr $id $name): raw $raw — within vendor tolerance ($margin)"
      else
        warn "${label} (attr $id $name): raw $raw ($margin)"
      fi
    done < <(jq -r '.ata_smart_attributes.table[]? | [(.id|tostring), .name, (.raw.value|tostring), ((.value // "null")|tostring), ((.thresh // "null")|tostring)] | @tsv' <<<"$json")
    [ "$found" -eq 0 ] && warn "no ATA SMART attribute table returned"

    local total=0 a
    for a in 5 197 198 187; do
      raw=$(jq -r --arg i "$a" '.ata_smart_attributes.table[]? | select(.id == ($i|tonumber)) | .raw.value' <<<"$json")
      [ -n "${raw:-}" ] && total=$((total + raw))
    done
    if [ "$total" -eq 0 ]; then
      ok "no reallocated, pending, uncorrectable or reported-uncorrectable sectors"
    else
      info "combined reallocated+pending+uncorrectable raw count: $total (see severities above)"
    fi

    local selftest
    selftest=$(jq -r '.ata_smart_self_test_log.standard.table[0].status.string // empty' <<<"$json")
    if [ -n "$selftest" ]; then
      info "last self-test: $selftest"
    else
      info "no self-test on record -- consider: smartctl -t long $dev"
    fi
  fi
}

emit "${CYAN}═══════════════════════════════════════${NC}"
emit "${CYAN}  SMART attribute review${NC}"
emit "${CYAN}═══════════════════════════════════════${NC}"

mapfile -t DEVS < <(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE 'zram|loop')
for d in "${DEVS[@]}"; do check_drive "$d"; done

emit "\n${CYAN}═══════════════════════════════════════${NC}"
if [ "$CRITICALS" -gt 0 ]; then
  emit "${RED}${BOLD}  $CRITICALS critical, $WARNINGS warning(s)${NC}"
  emit "${RED}  Back up anything irreplaceable from the affected drive NOW.${NC}"
  emit "${CYAN}═══════════════════════════════════════${NC}\n"; exit 3
elif [ "$WARNINGS" -gt 0 ]; then
  emit "${YELLOW}  $WARNINGS warning(s) -- worth watching${NC}"
  emit "${CYAN}═══════════════════════════════════════${NC}\n"; exit 2
else
  emit "${GREEN}  All ${#DEVS[@]} drives healthy${NC}"
  emit "${CYAN}═══════════════════════════════════════${NC}\n"; exit 0
fi
