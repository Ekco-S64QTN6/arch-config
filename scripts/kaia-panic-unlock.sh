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
# without a lockdown ruleset present it leaves the firewall untouched.
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

# --- 2. Is a lockdown actually in place? -----------------------------------
# Kaia's lockdown table is "inet kaia_lockdown". Older Kaia builds called it
# "inet filter" -- the same name as the stock /etc/nftables.conf table, so this
# script used to delete the host's real firewall whenever it was run on a healthy
# machine. A legacy lockdown is recognised by its output chain: policy drop,
# which no ordinary desktop ruleset uses.
echo -e "${YELLOW}[2/5]${NC} Looking for Kaia's lockdown ruleset..."
locked=0
if nft list table inet kaia_lockdown >/dev/null 2>&1; then
    locked=1; echo "      found 'inet kaia_lockdown'"
elif nft list chain inet filter output 2>/dev/null | grep -q 'policy drop'; then
    locked=1; echo "      found a legacy lockdown in 'inet filter' (output policy drop)"
else
    echo "      no lockdown ruleset present -- leaving the firewall alone"
fi

# --- 3. Replace the lockdown with the real firewall -------------------------
echo -e "${YELLOW}[3/5]${NC} Restoring the firewall..."
if [ "$locked" -eq 1 ]; then
    # The lockdown flushed everything before installing itself, so flush it and
    # rebuild: nftables.conf first (it begins with `flush ruleset`, which would
    # wipe ufw's tables), then ufw, then Kaia's snapshot if neither applies.
    nft flush ruleset
    restored=""
    if systemctl is-enabled --quiet nftables.service 2>/dev/null \
       && systemctl restart nftables.service 2>/dev/null; then
        restored="nftables.service"
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active' \
       && ufw reload >/dev/null 2>&1; then
        restored="${restored:+$restored + }ufw reload"
    fi
    if [ -z "$restored" ] && [ -f /var/lib/kaia/pre-lockdown.nft ]; then
        nft -f /var/lib/kaia/pre-lockdown.nft 2>/dev/null && restored="pre-lockdown snapshot"
    fi
    if [ -n "$restored" ]; then
        echo -e "      ${GREEN}restored via: $restored${NC}"
    else
        echo -e "      ${RED}no firewall restored — host is UNFIREWALLED${NC}"
    fi
    # The flush also dropped Kaia's recorded IP blocks.
    systemctl restart kaia-restore-blocks.service 2>/dev/null \
        && echo "      recorded IP blocks re-applied" \
        || echo -e "      ${YELLOW}kaia-restore-blocks did not run (journalctl -u kaia-restore-blocks)${NC}"
else
    echo "      nothing to restore"
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
