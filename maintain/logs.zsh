#!/usr/bin/env zsh
# Follow yabridge's trace (needs: arch-slate-bridge debug on). Reproduce the hang in REAPER and
# the last lines name the plugin and the call that never returned. Ctrl-C to stop.
# Usage: maintain/logs.zsh [lines]   (or: arch-slate-bridge logs)
set -uo pipefail
YLOG="${YABRIDGE_LOG:-$HOME/.local/state/yabridge/yabridge.log}"
[ -f "$YLOG" ] || { print -u2 "no $YLOG yet; run 'arch-slate-bridge debug on', restart REAPER, load a plugin"; exit 1; }
exec tail -n "${1:-50}" -F "$YLOG"
