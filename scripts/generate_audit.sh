#!/bin/bash
# ============================================================
# KAIA SYSTEM AUDIT - generates ~/system_audit.md
# ============================================================
OUT="/home/ekco/system_audit.md"
DATE=$(date '+%B %d, %Y %H:%M')
HOST=$(hostname 2>/dev/null || echo "kaia")

sudo -v || exit 1
echo "Analyzing system health and generating audit... this may take a minute."

# --- 1. Gather status info for Quick Health Summary ---
# CPU Temp
cpu_temp=$(sensors 2>/dev/null | grep -E 'Tctl|Tdie|Package id|Core 0|temp1' | grep -oE '[+-][0-9]+' | head -n 1 | tr -d '+-')
if [ -n "$cpu_temp" ] && [ "$cpu_temp" -gt 80 ]; then
  cpu_status="🟡 WARN (${cpu_temp}°C)"
elif [ -n "$cpu_temp" ]; then
  cpu_status="🟢 PASS (${cpu_temp}°C)"
else
  cpu_status="🟢 PASS (Sensors OK)"
fi

# Load Average
cores=$(nproc)
load1=$(awk '{print $1}' /proc/loadavg)
if awk -v sysload="$load1" -v cores="$cores" 'BEGIN { if (sysload > cores) exit 1; exit 0 }'; then
  load_status="🟢 PASS (Load: $load1 / Cores: $cores)"
else
  load_status="🟡 WARN (Load: $load1 / Cores: $cores)"
fi

# Disk Usage
high_disk=$(df -h 2>/dev/null | grep -vE '^tmpfs|^devtmpfs' | awk 'NR>1 {print $5}' | tr -d '%' | sort -nr | head -n 1)
if [ -n "$high_disk" ] && [ "$high_disk" -gt 90 ]; then
  storage_status="🟡 WARN (Max disk usage: ${high_disk}%)"
else
  storage_status="🟢 PASS (Max disk usage: ${high_disk}%)"
fi

# SMART Health
smart_ok=true; smart_msg=""
for dev in nvme0n1 sda sdb; do
  if [ -b "/dev/$dev" ]; then
    h=$(sudo smartctl -H "/dev/$dev" 2>/dev/null | grep -iE "health|self-test" | grep -iE "ok|passed")
    [ -z "$h" ] && smart_ok=false && smart_msg="${smart_msg} /dev/$dev FAILED"
  fi
done
$smart_ok && smart_status="🟢 PASS (SMART Health OK)" || smart_status="🔴 CRITICAL ($smart_msg)"

# GPU & VRAM
if command -v nvidia-smi &>/dev/null; then
  vram_info=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
  if [ -n "$vram_info" ]; then
    used_vram=$(echo "$vram_info" | cut -d, -f1 | tr -d ' ')
    total_vram=$(echo "$vram_info" | cut -d, -f2 | tr -d ' ')
    vram_pct=$(( used_vram * 100 / total_vram ))
    [ "$vram_pct" -gt 95 ] && gpu_status="🟡 WARN (VRAM: $vram_pct% - ${used_vram}/${total_vram} MiB)" || gpu_status="🟢 PASS (VRAM: $vram_pct% - ${used_vram}/${total_vram} MiB)"
  else
    gpu_status="🟡 WARN (NVIDIA present, telemetry failed)"
  fi
else
  gpu_status="⚪ N/A (No NVIDIA GPU)"
fi

# Ollama
ollama_active=$(systemctl is-active ollama.service 2>/dev/null)
ollama_port=$(ss -tlnp 2>/dev/null | grep -E ':11434 ')
if [ "$ollama_active" = "active" ] && [ -n "$ollama_port" ]; then
  ollama_status="🟢 PASS (Running on port 11434)"
elif [ "$ollama_active" = "active" ]; then
  ollama_status="🟡 WARN (Active, port 11434 not listening)"
else
  ollama_status="🔴 CRITICAL (ollama.service is $ollama_active)"
fi

# PostgreSQL
pg_active=$(systemctl is-active postgresql.service 2>/dev/null)
pg_port=$(ss -tlnp 2>/dev/null | grep -E ':5432 ')
if [ "$pg_active" = "active" ] && [ -n "$pg_port" ]; then
  pg_status="🟢 PASS (Running on port 5432)"
elif [ "$pg_active" = "active" ]; then
  pg_status="🟡 WARN (Active, port 5432 not listening)"
else
  pg_status="🔴 CRITICAL (postgresql.service is $pg_active)"
fi

# Firewall: judge the kernel ruleset, not a manager's opinion of itself.
# `ufw status` said "active" for weeks while enforcing nothing: nftables.service
# loads /etc/nftables.conf, which begins with `flush ruleset`, 2s after ufw.
if sudo nft list ruleset 2>/dev/null | grep -qE 'hook input .*policy drop'; then
  ufw_status="🟢 PASS (nftables input policy drop)"
else
  ufw_status="🔴 CRITICAL (no input chain with policy drop)"
fi

# Failed Services
failed_units=$(systemctl --failed --legend=no | grep -c "\.service")
[ "$failed_units" -gt 0 ] && services_status="🔴 CRITICAL ($failed_units failed services)" || services_status="🟢 PASS (0 failed services)"

# User Limits
nofile_limit=$(ulimit -n)
[ "$nofile_limit" -ge 524288 ] && limits_status="🟢 PASS (ulimit -n: $nofile_limit)" || limits_status="🟡 WARN (ulimit -n: $nofile_limit < 524288)"

# Package Database Lock
[ -f /var/lib/pacman/db.lck ] && pkg_status="🟡 WARN (Pacman lock db.lck exists)" || pkg_status="🟢 PASS (No db.lck)"

# --- 2. Gather specifications & format as markdown ---
display_type=$(loginctl show-session "${XDG_SESSION_ID:-1}" -p Type 2>/dev/null | cut -d= -f2)
kwin_info=$(qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null | grep -iE "geometry|refresh|active" || echo "KWin support info unavailable")
cpu_model=$(lscpu | grep -i "Model name:" | cut -d: -f2- | sed 's/^[ \t]*//')
cpu_threads=$(lscpu | grep -i "CPU(s):" | head -n 1 | awk '{print $2}')
gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || echo "AMD iGPU / Intel Integrated")
ram_total=$(free -h | awk '/^Mem:/ {print $2}')


storage_table=$(df -h 2>/dev/null | grep -vE '^tmpfs|^devtmpfs' | awk 'NR>1 {printf "| `%s` | %s | %s | %s | %s | `%s` |\n", $1, $2, $3, $4, $5, $6}')
lsblk_table=$(lsblk -o NAME,FSTYPE,SIZE,USED,AVAIL,USE%,MOUNTPOINTS,MODEL 2>/dev/null)
fdisk_table=$(sudo fdisk -l 2>/dev/null | grep -iE "^/dev/")

smart_nvme=$(sudo smartctl -H /dev/nvme0n1 2>/dev/null | grep -iE "test|status|result" || echo "smartctl unsupported")
smart_sda=$(sudo smartctl -H /dev/sda 2>/dev/null | grep -iE "test|status|result" || echo "smartctl unsupported")
smart_sdb=$(sudo smartctl -H /dev/sdb 2>/dev/null | grep -iE "test|status|result" || echo "smartctl unsupported")
trim_timer_status=$(systemctl status fstrim.timer --no-pager 2>/dev/null)

gpu_apps=""
while read -r line; do
  [ -z "$line" ] && continue
  g_pid=$(echo "$line" | cut -d, -f1 | tr -d ' ')
  g_proc=$(echo "$line" | cut -d, -f2 | sed 's/^[ \t]*//')
  g_vram=$(echo "$line" | cut -d, -f3 | sed 's/^[ \t]*//')
  gpu_apps="${gpu_apps}| \`$g_pid\` | $g_proc | $g_vram |
"
done < <(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null)
[ -z "$gpu_apps" ] && gpu_apps="| - | No active GPU processes | - |
"

nvidia_status=$(nvidia-smi 2>/dev/null || echo "NVIDIA driver not responding")

services_table=""
# coolercontrold was in this list but is not installed, so it rendered as a
# permanent red "Inactive" row. Only report on units that actually exist.
for s in ollama postgresql NetworkManager wpa_supplicant bluetooth sddm systemd-timesyncd ufw; do
  systemctl list-unit-files "$s.service" &>/dev/null || continue
  active=$(systemctl is-active "$s" 2>/dev/null)
  desc=$(systemctl show -p Description "$s" 2>/dev/null | cut -d= -f2)
  status="🔴 Inactive"; [ "$active" = "active" ] && status="🟢 Active"
  services_table="${services_table}| \`$s\` | $desc | $status |
"
done
failed_services=$(systemctl --failed --no-pager 2>/dev/null)

ports_table=""
while read -r line; do
  [ -z "$line" ] && continue
  local_addr=$(echo "$line" | awk '{print $4}')
  port=${local_addr##*:}
  [[ "$local_addr" =~ \[.*\]:([0-9]+) ]] && port="${BASH_REMATCH[1]}"
  proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+(?=",pid=\d+)')
  pid=$(echo "$line" | grep -oP 'pid=\K\d+')
  [ -z "$proc" ] && proc="Unknown"
  [ -z "$pid" ] && pid="-"
  ports_table="${ports_table}| \`$port\` | $proc | $pid | \`$local_addr\` |
"
done < <(sudo ss -tlnp 2>/dev/null | grep LISTEN)

sshfs_mounts=$(mount | grep sshfs || echo "No active sshfs mounts")
systemd_mounts=$(systemctl list-units --type=mount --all --no-pager 2>/dev/null | grep -iE "satellite|wintermute" || echo "No matching mounts")

total_pkg=$(pacman -Q | wc -l); flatpak_count=$(flatpak list --app | wc -l 2>/dev/null || echo 0)
aur_count=$(pacman -Qm | wc -l); orphan_count=$(pacman -Qdt | wc -l)

flatpak_table=""
while IFS=$'\t' read -r name appid version; do
  [ -n "$name" ] && flatpak_table="${flatpak_table}| $name | \`$appid\` | $version |
"
done < <(flatpak list --app --columns=name,application,version 2>/dev/null)
[ -z "$flatpak_table" ] && flatpak_table="| None | | |
"

python_version=$(~/venv/bin/python --version 2>/dev/null || echo "No venv python")
pip_list=$(~/venv/bin/pip list 2>/dev/null || echo "venv unavailable")

home_large_table=$(du -sh "$HOME"/* 2>/dev/null | sort -hr | head -n 15 | awk '{print "| "$2" | "$1" |"}')
startup_apps=$(ls -la "$HOME/.config/autostart/" 2>/dev/null || echo "None")
shell_traces=$(cat "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null | grep -iE "ulimit|kaia|path|db_")

scripts_table=""
for f in "$HOME"/*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  firstline=$(grep -v -E "^#|^$|show_welcome_message" "$f" | head -n 1 | head -c 120 | sed 's/|/\\|/g' | tr -d '`')
  desc=$(grep -m1 "^#.*desc\|^# .*-\|^# [A-Z]" "$f" 2>/dev/null | sed 's/^# *//' | head -c 200 | sed 's/|/\\|/g' | tr -d '`')
  scripts_table="${scripts_table}| \`$name\` | \`$firstline\` | $desc |
"
done

# --- 3. Gather verbose diagnostic logs for collapsible sections ---
log_journal=$(journalctl -b -p 3 -n 50 --no-pager 2>/dev/null)
log_dmesg=$(dmesg 2>/dev/null | grep -iE "fail|error|warn|segfault|timeout|denied|reject" | tail -30)
log_nvidia=$(journalctl -b --no-pager 2>/dev/null | grep -i nvidia | grep -iE "fail|error|warn" | tail -30 || echo "No NVIDIA failures/warnings logged.")
log_ollama_status=$(systemctl status ollama --no-pager -l 2>/dev/null); log_ollama_journal=$(journalctl -u ollama -b --no-pager 2>/dev/null | grep -iE "error|fail|warn" | tail -30)
log_pg_status=$(systemctl status postgresql --no-pager -l 2>/dev/null); log_pg_journal=$(journalctl -u postgresql -b --no-pager 2>/dev/null | grep -iE "error|fail|fatal|panic" | tail -30)
log_cc_status=$(systemctl status coolercontrold --no-pager -l 2>/dev/null); log_cc_journal=$(journalctl -u coolercontrold -b --no-pager 2>/dev/null | grep -iE "error|fail|warn" | tail -30)
log_nm_status=$(systemctl status NetworkManager wpa_supplicant --no-pager -l 2>/dev/null); log_nm_journal=$(journalctl -u NetworkManager -b --no-pager 2>/dev/null | grep -iE "error|fail|denied" | tail -30)
log_audio=$(journalctl -b --no-pager 2>/dev/null | grep -iE "pipewire|wireplumber" | grep -iE "error|fail|warn" | tail -30)
log_sshfs=$(journalctl -b --no-pager 2>/dev/null | grep -i sshfs | grep -iE "error|fail|timeout" | tail -30)
log_oom=$(journalctl -k -b --no-pager 2>/dev/null | grep -iE "oom|out of memory|killed process" || echo "No OOM events logged since boot.")
log_zram=$(zramctl 2>/dev/null || echo "zramctl not available"); log_swap=$(swapon --show 2>/dev/null || echo "swapon not available")
log_top_mem=$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -15)
log_ufw_status=$(sudo ufw status verbose 2>/dev/null); log_ufw_journal=$(journalctl -b --no-pager 2>/dev/null | grep -i ufw | grep -iE "block|deny|limit" | tail -30 || echo "No UFW blocks logged.")
log_pkg_integrity=$(pacman -Qk 2>/dev/null | grep -v " 0 missing files" || echo "All packages verified intact.")
log_timers=$(systemctl list-timers --all --no-pager 2>/dev/null)
log_mirrors=$(cat /etc/pacman.d/mirrorlist 2>/dev/null | grep -v '^#' | head -n 10)
log_paccache=$(paccache -dk 3 2>/dev/null || echo "paccache not available")
log_sensors=$(sensors 2>/dev/null || echo "sensors command not available")
log_iotop=$(sudo iotop -boP -n 5 2>/dev/null || echo "iotop not available or failed")
mapfile -t _foreign < <(pacman -Qmq 2>/dev/null)
log_aur_desc=$( [ ${#_foreign[@]} -gt 0 ] && pacman -Qqi "${_foreign[@]}" 2>/dev/null | grep -iE "^Name|^Description" || echo "No explicit AUR packages found")
log_modules=$(lsmod | sort 2>/dev/null)
log_recent_pkg=$(awk -v d="$(date -d '30 days ago' +%Y-%m-%d)" '$1 >= d && $3 == "installed"' /var/log/pacman.log 2>/dev/null | tail -50 || echo "Log unavailable")
log_pacman_locks=$(ls -l /var/lib/pacman/db.lck 2>/dev/null || echo "No stale transaction locks found.")

# scan logs for known warnings/errors
declare -A explanations
explanations["couldn't find an input interrupt endpoint"]="USB HID device endpoint mismatch. Safe to ignore. | **None**"
explanations["split lock detection"]="Atomic CPU lock instruction. Performance advisory only. | **Cosmetic**"
explanations["module verification failed"]="NVIDIA driver verification warning. Expected on Arch. | **None**"
explanations["failed to register LPS0 sleep handler"]="Desktop motherboard sleep mapping fallback. | **None**"
explanations["Failed to set default system config for hci0"]="Bluetooth daemon configuration override bypass. | **None**"
explanations["Failed to get percentage from UPower"]="Battery check failed (upower daemon missing). | **Cosmetic**"
explanations["link failed"]="Audio source socket closed before PipeWire graph linked. | **Harmless**"
explanations["error setting IPv4 forwarding"]="NetworkManager sysctl forwarding setup race. | **Non-breaking**"

warnings_table=""
for key in "${!explanations[@]}"; do
  if echo "$log_dmesg $log_journal" | grep -Fq "$key"; then
    warnings_table="${warnings_table}| \`$key\` | ${explanations[$key]} |
"
  fi
done
[ -z "$warnings_table" ] && warnings_table="| *None of the known warnings found in recent logs.* | | |
"

# Write out report
cat > "$OUT" << EOF
# 🛡️ Kaia System Security & Diagnostics Audit

**Generated on:** $DATE | **Host:** \`$HOST\` | **Status:** Completed

---

## 📊 Quick Health Summary
| Subsystem | Status | Details / Issues |
| :--- | :---: | :--- |
| **System Load & Kernel** | $load_status | Load average vs. CPU cores |
| **Hardware Thermals** | $cpu_status | Temperature threshold monitoring |
| **Storage & FTL Integrity** | $storage_status | Free space partition check |
| **Drive SMART Health** | $smart_status | Structural health check of sda/sdb/nvme0n1 |
| **GPU & VRAM Compute** | $gpu_status | NVIDIA hardware & VRAM load state |
| **Local AI (Ollama)** | $ollama_status | Ollama system service & socket validation |
| **Database (PostgreSQL)** | $pg_status | Datastore accessibility check |
| **Network & Firewall** | $ufw_status | Kernel nftables ruleset (input hook) |
| **Systemd Services** | $services_status | Failed service sweep |
| **User Space Limits** | $limits_status | Dynamic file handle ceilings |
| **Package Database** | $pkg_status | DB transaction locks status |

---

## 💻 Hardware & Host Specifications
| Component | Details |
| :--- | :--- |
| **CPU** | $cpu_model ($cpu_threads threads) |
| **GPU** | $gpu_model |
| **Memory (RAM)** | $ram_total |
| **Display Server / Session** | Wayland ($display_type session) |

### Active Compositor Topology
\`\`\`
$kwin_info
\`\`\`

---

## 🗄️ Storage & Partition Layout
### Storage Space Utilization (df -h)
| Filesystem | Size | Used | Avail | Use% | Mounted on |
| :--- | :--- | :--- | :--- | :--- | :--- |
$storage_table

### SMART Telemetry Summary
- **nvme0n1 (OS):** \`$smart_nvme\`
- **sda (Steam):** \`$smart_sda\`
- **sdb (Backup):** \`$smart_sdb\`

---

## 🧠 GPU & AI Inference Stack
- **Primary GPU:** $gpu_model
- **Active VRAM Compute Processes:**
  | PID | Process Name | VRAM Used |
  | :--- | :--- | :--- |
  $gpu_apps

---

## ⚙️ Service & Network Topology
### Core Services
| Service | Purpose | Status |
| :--- | :--- | :--- |
$services_table
### Open Listening Ports
| Port | Process | PID | Bind Address |
| :--- | :--- | :--- | :--- |
$ports_table
### SSHFS Network Storage Mounts
- **Active Mounts (mount | grep sshfs):**
\`\`\`
$sshfs_mounts
\`\`\`
- **Systemd Automount Status:**
\`\`\`
$systemd_mounts
\`\`\`

---

## 📦 Package Management & Virtual Envs
- **System Package Counts:**
  - \`pacman\` native packages: **$total_pkg**
  - \`AUR\` (foreign) packages: **$aur_count**
  - \`Flatpak\` application profiles: **$flatpak_count**
  - \`Orphans\` detected: **$orphan_count**

### Flatpak Applications
| Application | Application ID | Version |
| :--- | :--- | :--- |
$flatpak_table
### Python virtualenv (~/venv)
- **Python Version:** \`$python_version\`
- **Packages:**
\`\`\`
$pip_list
\`\`\`

---

## 🐚 Scripts & Home Directories
### Large Home Folders
| Target Directory | Size |
| :--- | :--- |
$home_large_table

### Scripts in Home Directory
| Script | First execution line | Description hint |
| :--- | :--- | :--- |
$scripts_table
### Startup Applications (KDE Autostart)
\`\`\`
$startup_apps
\`\`\`

### Shell Configuration Traces (~/.bashrc / ~/.zshrc)
\`\`\`
$shell_traces
\`\`\`

---

## 🪵 Log & Diagnostics Interpretation Table
| Log Warning / Message | Mechanical Explanation | Impact |
| :--- | :--- | :--- |
$warnings_table

---

## 📝 Verbose Diagnostics & Logs

### 🔍 System Journal Errors & Warnings (Priority 0-3)
\`\`\`
$log_journal
\`\`\`

### 🐧 Kernel Warning Messages (dmesg)
\`\`\`
$log_dmesg
\`\`\`

### 💚 NVIDIA Kernel Logs
\`\`\`
$log_nvidia
\`\`\`

### 🪵 Ollama Logs (Errors & Warnings)
\`\`\`
$log_ollama_status

$log_ollama_journal
\`\`\`

### 🐘 PostgreSQL Logs
\`\`\`
$log_pg_status

$log_pg_journal
\`\`\`

### 💨 CoolerControl Daemon Logs
\`\`\`
$log_cc_status

$log_cc_journal
\`\`\`

### 📶 NetworkManager & WiFi Logs
\`\`\`
$log_nm_status

$log_nm_journal
\`\`\`

### 🔊 PipeWire / WirePlumber Audio Logs
\`\`\`
$log_audio
\`\`\`

### 🔗 SSHFS Storage Logs
\`\`\`
$log_sshfs
\`\`\`

### 🧱 Out-Of-Memory (OOM) Kernel Traces
\`\`\`
$log_oom
\`\`\`

### 💾 ZRAM / Swap Block Compression Telemetry
\`\`\`
$log_zram

$log_swap
\`\`\`

### 📊 Top Memory Consuming Processes
\`\`\`
$log_top_mem
\`\`\`

### 🔥 UFW Firewall Block Logs
\`\`\`
$log_ufw_status

$log_ufw_journal
\`\`\`

### 🚨 Package File Integrity Verification
\`\`\`
$log_pkg_integrity
\`\`\`

### ⏱️ Systemd Timer Execution Schedules
\`\`\`
$log_timers
\`\`\`

### ⚙️ Pacman Mirrorlist & Cache Pruning Dry-Run
**Active Pacman Mirrors (Top 10):**
\`\`\`
$log_mirrors
\`\`\`

**Reclaimable Cache Space (paccache -dk 3):**
\`\`\`
$log_paccache
\`\`\`

### 🎛️ Hardware Thermal Sensor Baseline (lm_sensors)
\`\`\`
$log_sensors
\`\`\`

### 💽 High-Resolution I/O Saturation (5-second snapshot)
\`\`\`
$log_iotop
\`\`\`

### 📦 Explicit AUR Package Footprints
\`\`\`
$log_aur_desc
\`\`\`

### 🐧 Loaded Kernel Modules (lsmod)
\`\`\`
$log_modules
\`\`\`

### 🕒 Recently Installed Packages (last 30 days)
\`\`\`
$log_recent_pkg
\`\`\`

### 🗝️ Pacman Keyring & Database Transaction Locks
\`\`\`
$log_pacman_locks
\`\`\`

### 📼 Full Hardware Block Layout (lsblk)
\`\`\`
$lsblk_table
\`\`\`

### 📂 Full Disk Partition Table (fdisk)
\`\`\`
$fdisk_table
\`\`\`

### 📟 Full NVIDIA System Status (nvidia-smi)
\`\`\`
$nvidia_status
\`\`\`

### ⏱️ SSD TRIM Timer Detail
\`\`\`
$trim_timer_status
\`\`\`

### 💀 Failed Systemd Units Detail
\`\`\`
$failed_services
\`\`\`

---
*Report generated automatically by \`generate_audit.sh\` on $DATE.*
EOF

echo ""
echo "✓ Audit complete! Saved to: $OUT"
echo "  Size: $(du -sh "$OUT" | cut -f1)"
