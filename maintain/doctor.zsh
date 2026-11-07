#!/usr/bin/env zsh
# Check every piece the chain depends on and say which script fixes what is wrong.
# Exit 1 if anything FAILs; WARNs do not change the exit code.
# Usage: maintain/doctor.zsh   (or: arch-slate-bridge doctor)
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

C="$WINEPREFIX/drive_c/Program Files"
APPDIR="$C/Complete Access Hub"
SP="$APPDIR/resources/app/node_modules/@vscode/sudo-prompt/index.js"
YDEST="$HOME/.local/share/yabridge"
YCTL="$HOME/.local/bin/yabridgectl"
REAPER_CACHE="$HOME/.config/REAPER/reaper-vstplugins64.ini"
fails=0
ok() { log "  OK    $*"; }
warn() { log "  WARN  $*"; }
fail() {
	log "  FAIL  $*"
	fails=$((fails + 1))
}
# check <what> <fix hint> -- <command...>
check() {
	local what="$1" fix="$2"
	shift 2
	[ "$1" = "--" ] && shift
	if "$@" >/dev/null 2>&1; then ok "$what"; else fail "$what -> $fix"; fi
}

step "1. wine + prefix"
check "wine on PATH" "install wine" -- command -v wine
check "prefix $WINEPREFIX" "run install/10-prefix-pace.zsh" -- test -f "$WINEPREFIX/system.reg"
check "vcrun2022 (vcruntime140.dll)" "run install/10-prefix-pace.zsh" -- test -f "$WINEPREFIX/drive_c/windows/system32/vcruntime140.dll"

step "2. PACE / iLok (what the Hub checks before it does anything)"
check "service PACELicenseDServices RUNNING" "run install/10-prefix-pace.zsh" -- \
	sh -c 'wine sc query PACELicenseDServices 2>/dev/null | grep -q RUNNING'
check "Uninstall entry 'PACE License Support'" "run install/10-prefix-pace.zsh" -- \
	sh -c "wine reg query 'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall' /s 2>/dev/null | grep -qi 'PACE License Support'"

step "3. Complete Access Hub"
check "Hub installed" "run install/20-hub.zsh" -- test -f "$APPDIR/Complete Access Hub.exe"
check "app.asar unpacked to resources/app" "run maintain/repatch-hub.zsh" -- test -f "$APPDIR/resources/app/package.json"
check "original app.asar disabled (else Electron loads the unpatched bundle)" "run maintain/repatch-hub.zsh" -- \
	sh -c "[ ! -e '$APPDIR/resources/app.asar' ]"
check "sudo-prompt patched (Install button works)" "run maintain/repatch-hub.zsh" -- grep -q 'wine: no UAC' "$SP"
if pgrep -f 'Complete Access Hu[b].exe' >/dev/null; then ok "Hub is running"; else log "  info  Hub not running (arch-slate-bridge hub)"; fi

step "4. yabridge (must be the master build in ~/.local, not the Arch package)"
check "Arch yabridge package absent" "sudo install/00-prereqs-sudo.zsh" -- sh -c '[ ! -e /usr/bin/yabridge-host.exe ] && [ ! -e /usr/lib/libyabridge-vst3.so ]'
check "yabridge-host.exe.so in $YDEST" "run install/30-yabridge.zsh" -- test -f "$YDEST/yabridge-host.exe.so"
check "yabridgectl at $YCTL" "run install/30-yabridge.zsh" -- test -x "$YCTL"
check "yabridgectl resolves host from $YDEST" "run install/30-yabridge.zsh" -- \
	sh -c "'$YCTL' status 2>&1 | grep -q \"yabridge-host.exe: '$YDEST/\""
if pgrep -af 'yabridge-host' | grep -q '/usr/bin/'; then
	fail "a running yabridge-host comes from /usr/bin (mouse input broken) -> sudo install/00-prereqs-sudo.zsh, restart REAPER"
fi

step "5. plugins: Windows side vs bridged vs REAPER cache"
typeset -a win bridged
# Windows VST3 is a single file or a bundle dir; prune so bundle internals are not listed
win=("${(@f)$(find "$C/Common Files/VST3" -name '*.vst3' -prune -print 2>/dev/null | sort)}")
bridged=("${(@f)$(find "$HOME/.vst3/yabridge" -type d -name '*.vst3' 2>/dev/null | sort)}")
log "  installed in prefix: ${#win}   bridged in ~/.vst3/yabridge: ${#bridged}"
for p in "${win[@]}"; do
	[ -n "$p" ] || continue
	rel="${p#$C/Common Files/VST3/}"
	if [ -e "$HOME/.vst3/yabridge/$rel" ]; then
		name="${rel:t}"
		name="${name// /_}" # REAPER keys the cache by file name with spaces as _
		if [ -f "$REAPER_CACHE" ] && ! grep -q "^$name=" "$REAPER_CACHE"; then
			warn "$rel bridged, not in REAPER's plugin cache -> re-scan in REAPER"
		else
			ok "$rel"
		fi
	else
		fail "$rel not bridged -> arch-slate-bridge sync"
	fi
done
[ ${#win} -eq 0 ] && warn "no VST3 plugins in the prefix yet; install one in the Hub"

step "result"
if [ $fails -eq 0 ]; then log "all checks passed"; else die "$fails check(s) failed; fixes are listed above"; fi
