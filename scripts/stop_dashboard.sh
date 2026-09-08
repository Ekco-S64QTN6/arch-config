#!/bin/bash
# 1. Targets the specific titles we used in the launch script
# -9 forces an immediate close, -f matches the full launch command
# Match on the actual launch flag, not the bare word. 'pkill -f terminal-1'
# matched ANY process whose command line merely contained that string -- an
# editor with the file open, a grep, this script's own shell.
for t in terminal-1 terminal-2 terminal-3 terminal-4; do
  pkill -f -- "--title $t" 2>/dev/null
done

# 2. (A 'pkill -9 -f "nohup kitty"' line used to be here. nohup exec()s and does
#    not stay in the command line, so it never matched anything.)

# 3. Small safety delay
sleep 0.1
