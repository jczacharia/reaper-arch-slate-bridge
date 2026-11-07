#!/usr/bin/env zsh
# Bridge every Windows plugin installed in the Slate prefix into ~/.vst3 / ~/.vst / ~/.clap.
# Run after installing anything in the Complete Access Hub, then re-scan in REAPER.
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

YCTL="$HOME/.local/bin/yabridgectl"
C="$WINEPREFIX/drive_c/Program Files"
# every directory the Hub's installers write to (from the Hub's own scanner table)
DIRS=(
	"$C/Common Files/VST3"
	"$C/Common Files/CLAP"
	"$C/Steinberg/Vstplugins"
	"$C/VSTPlugIns"
)

step "0. tools"
[ -x "$YCTL" ] || die "$YCTL missing; run install/30-yabridge.zsh"

step "1. register plugin directories"
for d in "${DIRS[@]}"; do
	if [ -d "$d" ]; then
		try "add $d (ok if already added)" -- "$YCTL" add "$d"
	else
		log "skip (not present yet): $d"
	fi
done

step "2. sync"
run "yabridgectl sync --prune (also removes bridges for plugins uninstalled in the Hub)" -- "$YCTL" sync --prune
run "yabridgectl status" -- "$YCTL" status

step "3. result"
log "VST3 bridged: $(find ~/.vst3/yabridge -type d -name '*.vst3' 2>/dev/null | sed "s|$HOME/.vst3/yabridge/||" | sort | tr '\n' ' ')"
log "Now in REAPER: Preferences > Plug-ins > VST > Re-scan (or Clear cache/re-scan if a plugin is missing)."
