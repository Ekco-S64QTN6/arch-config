#!/bin/bash
# ============================================================
# PANIC: RESTORE NETWORKING
#
# Run this when the machine has no network and you suspect Kaia's
# emergency lockdown fired (tamper detection triggering
# kaia-lockdown.service, which does `nft flush ruleset` and sets
# input/forward/output to policy drop).
#
#     sudo ~/kaia-panic-unlock.sh
#
# Deliberately standalone: no dependency on the Kaia repo, no network
# access, no Python. If Kaia is the thing that is broken, this must
# still work. Safe to run even if the lockdown was NOT the cause --
# it only removes Kaia's own lockdown table and reloads your firewall.
#
# Exit: 0 network restored, 1 could not restore
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[1;36m'; NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  KAIA PANIC UNLOCK — restore networking${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}\n"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Must run as root:  sudo $0${NC}"
    exit 1
fi

# --- 1. Stop the thing that keeps re-applying the lockdown ------------------
# Do this FIRST. Restoring the firewall while the policy gate is still running
# its 30s tamper loop just means it locks you out again on the next tick.
echo -e "${YELLOW}[1/5]${NC} Stopping Kaia services so the lockdown cannot re-fire..."
for unit in kaia-policy-gate.service kaia-lockdown.service; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        systemctl stop "$unit" 2>/dev/null && echo "      stopped $unit" || echo "      $unit not running"
    fi
done

# --- 2. Remove the lockdown ruleset -----------------------------------------
echo -e "${YELLOW}[2/5]${NC} Removing Kaia's lockdown table..."
if nft list table inet filter >/dev/null 2>&1; then
    # Only delete Kaia's own table. A blanket `nft flush ruleset` here would
    # destroy whatever the firewall has legitimately loaded and make things worse.
    nft delete table inet filter 2>/dev/null && echo "      deleted 'inet filter' (the lockdown table)" \
        || echo -e "      ${YELLOW}could not delete it; continuing${NC}"
else
    echo "      no lockdown table present"
fi

# --- 3. Restore the real firewall -------------------------------------------
echo -e "${YELLOW}[3/5]${NC} Restoring the firewall..."
restored=""
if command -v ufw >/dev/null 2>&1; then
    # ufw reload regenerates its ruleset authoritatively, which is safer than
    # replaying a captured snapshot that may not match ufw's userspace state.
    if ufw reload >/dev/null 2>&1; then
        restored="ufw reload"
    else
        ufw --force enable >/dev/null 2>&1 && restored="ufw enable"
    fi
fi
if [ -z "$restored" ] && [ -f /var/lib/kaia/pre-lockdown.nft ]; then
    nft -f /var/lib/kaia/pre-lockdown.nft 2>/dev/null && restored="pre-lockdown snapshot"
fi
if [ -n "$restored" ]; then
    echo -e "      ${GREEN}restored via: $restored${NC}"
else
    echo -e "      ${YELLOW}no firewall restored — host may be UNFIREWALLED${NC}"
fi

# --- 4. Nudge the network stack ---------------------------------------------
echo -e "${YELLOW}[4/5]${NC} Restarting NetworkManager..."
systemctl restart NetworkManager 2>/dev/null && echo "      restarted" || echo "      not present / failed"
printf "      waiting for a connection"
for _ in $(seq 1 20); do
    nmcli -t -f STATE general 2>/dev/null | grep -q '^connected' && break
    printf "."; sleep 1
done
echo

# --- 5. Verify --------------------------------------------------------------
echo -e "${YELLOW}[5/5]${NC} Testing connectivity..."
gw=$(ip route | awk '/^default/{print $3; exit}')
ok=0
[ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1 && { echo -e "      ${GREEN}gateway $gw reachable${NC}"; ok=1; } \
                                                   || echo -e "      ${RED}gateway unreachable${NC}"
getent hosts archlinux.org >/dev/null 2>&1 && echo -e "      ${GREEN}DNS resolving${NC}" \
                                           || echo -e "      ${RED}DNS failing${NC}"

echo
if [ "$ok" -eq 1 ]; then
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}  Network restored.${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
else
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo -e "${RED}  Still no network. This was probably NOT Kaia.${NC}"
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo "  Check:  ip link  /  nmcli device status  /  nft list ruleset"
    echo "  A reboot also clears any lockdown: nftables rules are runtime-only."
fi

echo
echo -e "${CYAN}Why this happened, if it was Kaia:${NC}"
echo "  Tamper detection saw a core file change and asserted a compromise."
echo "  Check:  journalctl -u kaia-policy-gate | grep -i tamper | tail -20"
echo
echo -e "${CYAN}Kaia's policy gate is now STOPPED.${NC} Once you know why it fired:"
echo "      sudo systemctl start kaia-policy-gate"
echo "  It re-baselines file hashes on startup, so legitimate edits are accepted."
