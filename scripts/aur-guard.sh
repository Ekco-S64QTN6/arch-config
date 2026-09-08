#!/bin/bash
# ============================================================
# AUR SUPPLY-CHAIN GUARD
# Audits every installed AUR/foreign package against the
# community IOC feed (lenucksi/aur-malware-check) plus the
# AUR RPC, and scans local PKGBUILDs for known payloads.
#
# Adapted from the aur-precheck.sh approach in Linux_Hacks,
# which checks ONE package at install time. This checks
# EVERYTHING already installed, which is the gap that leaves.
#
# Exit: 0 clean/advisory-only, 2 findings, 1 usage/dependency error
# ============================================================
set -uo pipefail

# ============================================================
# CONFIG
# ============================================================
IOC_BASE="${AUR_IOC_RAW_BASE:-https://raw.githubusercontent.com/lenucksi/aur-malware-check/HEAD/data}"
CAMPAIGNS=(aur-infected chaos-rat russian-spam)
CACHE_DIR="${AUR_GUARD_CACHE:-$HOME/.cache/aur-guard}"
CACHE_TTL="${AUR_GUARD_TTL:-21600}"                       # 6 hours
ALLOWLIST="${AUR_GUARD_ALLOWLIST:-$HOME/.config/aur-guard/allowlist.txt}"
STALE_DAYS="${AUR_GUARD_STALE_DAYS:-365}"                 # PKGBUILD age warning
PKGBUILD_DIRS=("$HOME/.cache/paru/clone" "$HOME/.cache/yay")

# ============================================================
# COLORS
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

QUIET=0
REPORT=""
REFRESH=0
NOTIFY=0

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
    echo -e "${CYAN}AUR Supply-Chain Guard${NC}"
  fi
  echo -e "\n${CYAN}Auditing installed AUR packages against known-compromise data.${NC}\n"
  sleep 1
}

usage() {
  cat <<'USAGE'
Usage: aur-guard.sh [options]

  -q, --quiet      No banner, findings only (for timers/cron)
  -n, --notify     Send a desktop notification if anything is found
  -r, --refresh    Force a fresh IOC download, ignoring the cache
  -o, --report F   Also write the findings to file F
  -h, --help       This message

Exit codes: 0 = nothing to act on, 2 = findings, 1 = error

Allowlist (one name or glob per line, '#' comments):
  ~/.config/aur-guard/allowlist.txt
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet)   QUIET=1 ;;
    -n|--notify)  NOTIFY=1 ;;
    -r|--refresh) REFRESH=1 ;;
    -o|--report)  shift; REPORT="${1:-}"; [ -z "$REPORT" ] && { echo "--report needs a path"; exit 1; } ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# ============================================================
# DEPENDENCIES
# ============================================================
for dep in curl jq pacman; do
  command -v "$dep" &>/dev/null || { echo -e "${RED}Error: '$dep' is required.${NC}" >&2; exit 1; }
done

FINDINGS=0
CRIT_COUNT=0
say()  { [ "$QUIET" -eq 1 ] || echo -e "$@"; }
emit() { echo -e "$@"; [ -n "$REPORT" ] && echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT"; }
crit() { emit "  ${RED}${BOLD}[CRITICAL]${NC} $*"; FINDINGS=$((FINDINGS+1)); CRIT_COUNT=$((CRIT_COUNT+1)); }
warn() { emit "  ${YELLOW}[WARN]${NC}     $*"; FINDINGS=$((FINDINGS+1)); }
ok()   { say  "  ${GREEN}[OK]${NC}       $*"; }

# ============================================================
# IOC CACHE
# Serve a fresh cache if we have one; otherwise refetch. On a
# failed refetch fall back to a STALE cache rather than going
# blind -- a stale list is far better than no list.
# ============================================================
cache_get() {
  # NOTE: split deliberately. bash 5.3 creates every name in a `local`
  # declaration as unset BEFORE evaluating the assignments, so
  # `local a="$1" b="$a"` trips `set -u`. The second line needs $name.
  local name="$1" fetch_fn="$2"
  local f="$CACHE_DIR/$name" now age data
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  now=$(date +%s)
  if [ "$REFRESH" -eq 0 ] && [ -f "$f" ]; then
    age=$(( now - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$CACHE_TTL" ]; then cat "$f"; return 0; fi
  fi
  data="$("$fetch_fn")"
  if [ -n "$data" ]; then
    printf '%s\n' "$data" > "$f" 2>/dev/null || true
    printf '%s\n' "$data"
  elif [ -f "$f" ]; then
    STALE_CACHE=1
    cat "$f"
  fi
}

fetch_bad_packages() {
  local c f
  for c in "${CAMPAIGNS[@]}"; do
    for f in packages.txt packages-extra.txt; do
      curl -fsS --max-time 20 "$IOC_BASE/campaigns/$c/$f" 2>/dev/null || true
    done
  done | grep -vE '^[[:space:]]*(#|$)' | sort -u
}

fetch_bad_accounts() {
  local c
  for c in "${CAMPAIGNS[@]}"; do
    curl -fsS --max-time 20 "$IOC_BASE/campaigns/$c/accounts.json" 2>/dev/null \
      | jq -r '.accounts // {} | keys[]' 2>/dev/null || true
  done | sort -u
}

fetch_bad_npm() {
  local c
  for c in "${CAMPAIGNS[@]}"; do
    curl -fsS --max-time 20 "$IOC_BASE/campaigns/$c/npm-packages.txt" 2>/dev/null || true
  done | grep -vE '^[[:space:]]*(#|$)' | sort -u
}

matches_any() {
  local name="$1"; shift
  local pat
  for pat in "$@"; do
    [ -z "$pat" ] && continue
    # Glob match intended here, so the RHS is deliberately unquoted.
    # shellcheck disable=SC2053
    [[ "$name" == $pat ]] && return 0
  done
  return 1
}

# ============================================================
# MAIN
# ============================================================
show_welcome_message
[ -n "$REPORT" ] && : > "$REPORT"

STALE_CACHE=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

allow=()
[ -f "$ALLOWLIST" ] && mapfile -t allow < <(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST")

pacman -Qmq 2>/dev/null | sort > "$TMP/mine"
TOTAL=$(wc -l < "$TMP/mine")

say "${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  Fetching IOC data${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"

cache_get bad-packages fetch_bad_packages > "$TMP/bad-pkg"
cache_get bad-accounts fetch_bad_accounts > "$TMP/bad-acct"
cache_get bad-npm      fetch_bad_npm      > "$TMP/bad-npm"

if [ ! -s "$TMP/bad-pkg" ]; then
  emit "  ${RED}Could not fetch or cache any IOC data. Checks below are incomplete.${NC}"
elif [ "${STALE_CACHE:-0}" -eq 1 ]; then
  emit "  ${YELLOW}Network fetch failed; using a STALE cached IOC list.${NC}"
fi
say "  campaign package names : $(wc -l < "$TMP/bad-pkg")"
say "  malicious accounts     : $(wc -l < "$TMP/bad-acct")"
say "  npm payload names      : $(wc -l < "$TMP/bad-npm")"
say "  your AUR packages      : $TOTAL"
[ ${#allow[@]} -gt 0 ] && say "  allowlisted             : ${#allow[@]}"

# --- 1. Installed package names against the campaign lists ------------------
say "\n${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  1. Package names vs campaign lists${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"
if [ -s "$TMP/bad-pkg" ]; then
  while read -r p; do
    [ -z "$p" ] && continue
    matches_any "$p" "${allow[@]+"${allow[@]}"}" && continue
    if grep -qxF "$p" "$TMP/bad-pkg"; then
      crit "$p was COMPROMISED during a tracked AUR campaign."
      emit "             A match means the package was touched during the incident, not"
      emit "             that it is malicious today. Check when you installed/rebuilt it"
      emit "             against the campaign window, and re-review its PKGBUILD."
    fi
  done < "$TMP/mine"
  [ "$FINDINGS" -eq 0 ] && ok "none of your $TOTAL AUR packages appear on any campaign list"
else
  warn "skipped - no IOC package data available"
fi

# --- 2. AUR RPC metadata ----------------------------------------------------
say "\n${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  2. AUR metadata (maintainer / status)${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"
args=(); while read -r p; do [ -n "$p" ] && args+=(--data-urlencode "arg[]=$p"); done < "$TMP/mine"
if [ ${#args[@]} -gt 0 ] && curl -fsS --max-time 30 "${args[@]}" \
     "https://aur.archlinux.org/rpc/v5/info" 2>/dev/null > "$TMP/rpc.json" \
   && jq -e 'has("results")' >/dev/null 2>&1 < "$TMP/rpc.json"; then

  # Emit explicit placeholders, never empty fields. Tab is IFS *whitespace*, so
  # bash collapses runs of it into one delimiter -- an empty column silently
  # shifts every later field left. ("-" = no maintainer, ood is 0/1.)
  jq -r '.results[]? | [.Name, (.Maintainer // "-"), (if .OutOfDate then "1" else "0" end), (.LastModified // 0)] | @tsv' \
    < "$TMP/rpc.json" > "$TMP/meta"
  now=$(date +%s)
  n_rpc=0
  while IFS=$'\t' read -r name maint ood lastmod; do
    n_rpc=$((n_rpc+1))
    matches_any "$name" "${allow[@]+"${allow[@]}"}" && continue
    if [ "$maint" != "-" ] && [ -s "$TMP/bad-acct" ] && grep -qxF "$maint" "$TMP/bad-acct"; then
      crit "$name is maintained by KNOWN-MALICIOUS account '$maint'"
    fi
    [ "$maint" = "-" ] && warn "$name is ORPHANED in the AUR (no maintainer)"
    [ "$ood" = "1" ]   && warn "$name is flagged OUT-OF-DATE in the AUR"
    age=$(( (now - lastmod) / 86400 ))
    [ "$age" -gt "$STALE_DAYS" ] && warn "$name PKGBUILD untouched for ${age}d (> ${STALE_DAYS}d)"
  done < "$TMP/meta"

  cut -f1 "$TMP/meta" | sort > "$TMP/known"
  while read -r gone; do
    [ -z "$gone" ] && continue
    matches_any "$gone" "${allow[@]+"${allow[@]}"}" && continue
    warn "$gone is installed but NOT in the AUR any more (deleted/renamed?)"
  done < <(comm -23 "$TMP/mine" "$TMP/known")
  ok "queried $n_rpc of $TOTAL packages via the AUR RPC"
else
  warn "AUR RPC unreachable - metadata checks skipped (offline?)"
fi

# --- 3. Local PKGBUILD / node payload scan ----------------------------------
say "\n${CYAN}═══════════════════════════════════════${NC}"
say "${CYAN}  3. Local payload scan${NC}"
say "${CYAN}═══════════════════════════════════════${NC}\n"
if [ -s "$TMP/bad-npm" ]; then
  scanned=0; found=0
  for d in "${PKGBUILD_DIRS[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r pb; do
      scanned=$((scanned+1))
      while read -r n; do
        [ -z "$n" ] && continue
        if grep -qF -- "$n" "$pb" 2>/dev/null; then
          crit "payload '$n' referenced in $pb"
          found=1
        fi
      done < "$TMP/bad-npm"
    done < <(find "$d" -maxdepth 3 \( -name PKGBUILD -o -name '*.install' \) 2>/dev/null)
  done
  [ "$found" -eq 0 ] && ok "scanned $scanned local PKGBUILD/install files, no payload names found"

  nf=0
  while read -r n; do
    [ -z "$n" ] && continue
    while IFS= read -r hit; do
      crit "payload package present on disk: $hit"; nf=1
    done < <(find "$HOME/.npm" "$HOME/.local/lib" "$HOME/.cache" -maxdepth 6 -type d -name "$n" 2>/dev/null)
  done < "$TMP/bad-npm"
  [ "$nf" -eq 0 ] && ok "no payload package directories in ~/.npm, ~/.local/lib or ~/.cache"
else
  warn "skipped - no npm payload data available"
fi

# ============================================================
# SUMMARY
# ============================================================
say "\n${CYAN}═══════════════════════════════════════${NC}"
if [ "$FINDINGS" -eq 0 ]; then
  emit "${GREEN}  CLEAN - $TOTAL AUR packages, nothing to act on${NC}"
  say "${CYAN}═══════════════════════════════════════${NC}\n"
  exit 0
else
  emit "${RED}${BOLD}  $FINDINGS finding(s) - review the output above${NC}"
  say "${CYAN}═══════════════════════════════════════${NC}\n"
  if [ "$NOTIFY" -eq 1 ] && command -v notify-send >/dev/null 2>&1; then
    # Criticals are a "look now" event; warnings are informational.
    if [ "$CRIT_COUNT" -gt 0 ]; then
      notify-send -u critical "AUR Guard: $CRIT_COUNT CRITICAL" \
        "Known-compromised package or maintainer detected. Run ~/aur-guard.sh" 2>/dev/null || true
    else
      notify-send -u normal "AUR Guard: $FINDINGS advisory finding(s)" \
        "Orphaned / out-of-date / stale AUR packages. Run ~/aur-guard.sh" 2>/dev/null || true
    fi
  fi
  exit 2
fi
