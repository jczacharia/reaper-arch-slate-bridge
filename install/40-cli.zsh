#!/usr/bin/env zsh
# Step 4: put the `arch-slate-bridge` command on PATH (symlink to cli/arch-slate-bridge, so the
# repo stays the single source; git pull updates the command). Replaces the per-script launchers.
# Usage: install/40-cli.zsh
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
source "${0:A:h}/../lib/log.zsh"

CLI="${0:A:h}/../cli/arch-slate-bridge"
BIN="$HOME/.local/bin"
LINK="$BIN/arch-slate-bridge"

step "1. symlink"
[ -x "$CLI" ] || die "missing or not executable: $CLI"
mkdir -p "$BIN"
run "link $LINK -> $CLI" -- ln -sfn "$CLI" "$LINK"
# the launcher older versions of install/20-hub.zsh wrote; `arch-slate-bridge hub` replaces it
[ -e "$BIN/complete-access-hub" ] && run "remove old launcher $BIN/complete-access-hub" -- trash-put -f -- "$BIN/complete-access-hub"

step "2. verify"
run "arch-slate-bridge help (via symlink)" -- "$LINK" help
case ":$PATH:" in
*":$BIN:"*) log "$BIN is on PATH" ;;
*) log "WARN: $BIN is not on PATH; add it to your shell rc or call $LINK directly" ;;
esac
log "step 4 done"
