#!/usr/bin/env zsh
# Start the Complete Access Hub under Wine. Refuses to start when the pieces the Hub needs are
# missing, because the Hub itself only shows a generic "iLok not installed" or a dead button.
# Usage: maintain/start-hub.zsh [hub args]   (or: arch-slate-bridge hub)
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

APPDIR="$WINEPREFIX/drive_c/Program Files/Complete Access Hub"
HUBEXE="$APPDIR/Complete Access Hub.exe"
SP="$APPDIR/resources/app/node_modules/@vscode/sudo-prompt/index.js"

step "0. preflight"
[ -f "$HUBEXE" ] || die "Hub not installed: $HUBEXE (run install/20-hub.zsh)"
grep -q 'wine: no UAC' "$SP" 2>/dev/null || die "Hub is unpatched (Install button would do nothing); run maintain/repatch-hub.zsh"
wine sc query PACELicenseDServices 2>/dev/null | grep -q RUNNING || die "PACE service not running; run install/10-prefix-pace.zsh"
if pgrep -f 'Complete Access Hu[b].exe' >/dev/null; then
	log "Hub already running (pid $(pgrep -f 'Complete Access Hu[b].exe' | head -1)); starting another instance focuses it"
fi

step "1. start"
log "hub logs: $WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Complete Access Hub/logs/ (main.log, sudo-service.log)"
log "after installing a plugin: arch-slate-bridge sync, then re-scan in REAPER"
# Electron/Chromium under Wine: software GL is the safe default
run "wine Complete Access Hub.exe" -- wine "$HUBEXE" --disable-gpu "$@"
