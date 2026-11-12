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
check "mfc42 (32-bit mfc42.dll; ISSkin installers like sonible smart:limit fail with 'Cannot Import dll: isskin.dll' without it)" "run install/10-prefix-pace.zsh" -- test -f "$WINEPREFIX/drive_c/windows/syswow64/mfc42.dll"
check "GLX backend (UseEGL=N; OpenGL editors like Inf Horizon get no pixel format on EGL)" "run install/17-opengl-glx.zsh" -- \
  sh -c "wine reg query 'HKCU\\Software\\Wine\\X11 Driver' /v UseEGL 2>/dev/null | grep -qE 'UseEGL\s+REG_SZ\s+N'"
check "DXVK (d3d11=native; D3D-rendered editors like SSL hang on close without it)" "run install/15-dxvk.zsh" -- \
  sh -c "wine reg query 'HKCU\\Software\\Wine\\DllOverrides' /v '*d3d11' 2>/dev/null | grep -q native"

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

step "5. yabridge trace (arch-slate-bridge debug on|off)"
if systemctl --user show-environment 2>/dev/null | grep -q '^YABRIDGE_DEBUG_FILE='; then
  log "  info  trace ON -> $(systemctl --user show-environment | sed -n 's/^YABRIDGE_DEBUG_FILE=//p') (arch-slate-bridge logs)"
else
  log "  info  trace off; plugin/Wine output is not kept. For hangs or crashes: arch-slate-bridge debug on"
fi

step "6. plugins: Windows side vs bridged vs REAPER cache"
# JUCE 8 Direct2D plugins verified to render anyway: their editor attaches an OpenGL context (trace shows wglCreateContext)
GL_PAINTED=("SSL X-DynEQ.vst3" smartcomp3.vst3 pufferfish.vst3 learncomp.vst3 learnlimit.vst3)
typeset -a win bridged
# Windows VST3 is a single file or a bundle dir; prune so bundle internals are not listed
win=("${(@f)$(find "$C/Common Files/VST3" -name '*.vst3' -prune -print 2>/dev/null | sort)}")
bridged=("${(@f)$(find "$HOME/.vst3/yabridge" -type d -name '*.vst3' 2>/dev/null | sort)}")
log "  installed in prefix: ${#win}   bridged in ~/.vst3/yabridge: ${#bridged}"
for p in "${win[@]}"; do
	[ -n "$p" ] || continue
	rel="${p#$C/Common Files/VST3/}"
	if [ -e "$HOME/.vst3/yabridge/$rel" ]; then
		# JUCE < 8.0.13 defaults to its Direct2D renderer, which needs DirectComposition; Wine has none, so the editor stays blank
		bin="$p"; [ -d "$p" ] && bin="$(find "$p/Contents/x86_64-win" -name '*.vst3' -type f 2>/dev/null | head -1)"
		js="$([ -f "$bin" ] && strings "$bin" | grep -E 'JUCE D2D swap chain thread|^juce_version_')" # no grep -q: pipefail + SIGPIPE
		note="" blank=0
		if [[ "$js" == *"JUCE D2D swap chain thread"* && ! "$js" =~ 'juce_version_(8_0_1[3-9]|8_0_[2-9][0-9]|8_[1-9]|9)' ]]; then
			jv="${${js##*juce_version_}%%$'\n'*}"
			if (( ${GL_PAINTED[(Ie)${rel:t}]} )); then
				note="; JUCE ${jv//_/.} Direct2D, but paints through its own OpenGL context so the editor works"
			else
				blank=1 note="; JUCE ${jv//_/.} Direct2D -> blank editor on Wine unless it attaches an OpenGL context (seh trace shows wglCreateContext); only a vendor build on JUCE >= 8.0.13 fixes it"
			fi
		fi
		name="${rel:t}"
		name="${name//[^A-Za-z0-9.]/_}" # REAPER keys the cache by file name, non-alphanumerics as _
		if [ -f "$REAPER_CACHE" ] && ! grep -q "^$name=" "$REAPER_CACHE"; then
			warn "$rel bridged, not in REAPER's plugin cache -> re-scan in REAPER$note"
		elif [ $blank -eq 1 ]; then
			warn "$rel$note"
		else
			ok "$rel$note"
		fi
	else
		fail "$rel not bridged -> arch-slate-bridge sync"
	fi
done
[ ${#win} -eq 0 ] && warn "no VST3 plugins in the prefix yet; install one in the Hub"
# bridges left behind after an uninstall: yabridgectl symlinks the Windows module into the bridge, so an
# orphan is a dangling link (works for bridges from other prefixes too); REAPER shows "does not contain a Windows VST3 module"
for b in "${(@f)$(find "$HOME/.vst3/yabridge" -xtype l 2>/dev/null)}"; do
	[ -n "$b" ] || continue
	fail "${${b#$HOME/.vst3/yabridge/}%%/*} bridged but its Windows module is gone -> arch-slate-bridge sync"
done

step "result"
if [ $fails -eq 0 ]; then log "all checks passed"; else die "$fails check(s) failed; fixes are listed above"; fi
