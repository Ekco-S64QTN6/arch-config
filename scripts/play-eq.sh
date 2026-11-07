#!/usr/bin/env bash
# One-click P99: EverQuest (Lutris) + Ekco Parse overlay.
# Window placement/borders/always-on-top come from KWin rules (~/.config/kwinrulesrc):
#   EverQuest  -> 0,0 1920x1080 on the left monitor, borderless (forced)
#   Ekco HUD   -> 1365,0, click-through (clicks reach the game), always on top,
#                 auto-hides when EverQuest is not running
# Either half is skipped if it is already running.
pgrep -f "ekco_parse.main --hud" >/dev/null || setsid -f "$HOME/github/EkcoParse/run.sh" --hud >/dev/null 2>&1
pgrep -f 'eqgame.exe'      >/dev/null || exec flatpak run net.lutris.Lutris lutris:rungameid/1
