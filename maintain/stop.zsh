#!/usr/bin/env zsh
# Shut the Slate prefix down: Hub, its telemetry sidecar (slate-digital-collector.exe, which
# outlives the Hub), the PACE service and wineserver. Refuses while REAPER has a bridged plugin
# loaded, because those plugins talk to the PACE service in this prefix for their licenses.
# Everything restarts on its own the next time wine touches the prefix; no reboot needed.
# Usage: maintain/stop.zsh   (or: arch-slate-bridge stop)
set -uo pipefail
[ "$EUID" -eq 0 ] && { echo "run as user, not sudo"; exit 1; }
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

step "0. preflight"
if pgrep -f 'yabridge-hos[t]' >/dev/null; then
  pgrep -af 'yabridge-hos[t]' | cut -c1-160 | while read -r l; do log "  $l"; done
  die "REAPER still hosts Windows plugins (above); close them or quit REAPER first"
fi
before="$(pgrep -af 'wineserve[r]|\.ex[e]' | wc -l)"
log "wine processes before: $before"
[ "$before" -eq 0 ] && { log "nothing running"; exit 0; }

step "1. graceful shutdown (WM_ENDSESSION to every window, then end services)"
try "wineboot --shutdown" -- wineboot --shutdown
try "wineserver -k (kill what is left) and wait" -- sh -c 'wineserver -k; wineserver -w'

step "2. verify"
left="$(pgrep -af 'wineserve[r]|\.ex[e]')"
if [ -n "$left" ]; then
  print -r -- "$left" | cut -c1-160 | while read -r l; do log "  still running: $l"; done
  die "wine processes survived; they may belong to another prefix (check WINEPREFIX)"
fi
log "prefix $WINEPREFIX is down; PACE and the Hub start again on next use"
