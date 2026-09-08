#!/bin/bash
# 1. Clear out old instances
# NOTE: 'pkill -9 -x kitty' used to be here, which killed EVERY kitty window --
# including the one running this script, so the script died before launching
# anything. Only close the four dashboard windows, by their titles, and never
# this script's own terminal.
for t in terminal-1 terminal-2 terminal-3 terminal-4; do
  pkill -f -- "--title $t" 2>/dev/null
done
sleep 0.3

# 2. Launch the 4-window grid with auto-commands
# Terminal 1: System Monitoring
nohup kitty --title "terminal-1" -e btop >/dev/null 2>&1 &

# Terminal 2: Kaia Core (CD, Activate, Run, and Keep Shell Open)
nohup kitty --title "terminal-2" -e bash -c "cd ~/github/Kaiacord/ && source venv/bin/activate && python Kaiacord.py; exec bash" >/dev/null 2>&1 &

# Terminal 3: Metropolis
nohup kitty --title "terminal-3" -e bash -c "metropolis; exec bash" >/dev/null 2>&1 &

# Terminal 4: Standard Interactive Shell
nohup kitty --title "terminal-4" -e bash -c "exec bash" >/dev/null 2>&1 &

# 3. Finalize
disown -a
exit
