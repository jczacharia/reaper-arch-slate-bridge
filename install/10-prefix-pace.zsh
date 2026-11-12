#!/usr/bin/env zsh
# Step 1: dedicated Wine prefix + PACE License Support (iLok) under Wine 11.
# Usage: install/10-prefix-pace.zsh /path/to/LicenseSupport.exe
#   LicenseSupport.exe is the Windows "License Support Installer" from https://www.ilok.com/#!license-manager
# Why: the Hub's pace-js native module talks to LDSvc.exe over a named pipe, and the Hub decides
#      iLok is installed by finding an Uninstall registry key whose DisplayName contains
#      "PACE License Support" with version >= 5.6.0. Without it the Hub downloads its own
#      ilm-win installer, which fails on Wine.
# The stock PACE installer fails on Wine 11 (OS-version launch condition + a WiX service-recovery
# action Wine lacks); sirsipe's scripts patch the MSI. See TECHNICAL.md in that repo.
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
export WINEARCH=win64
source "${0:A:h}/../lib/log.zsh"

PACE_REPO="$(ghq root)/github.com/sirsipe/ilok-pace-license-support-wine11-scripts"
LS_EXE="${1:-}"

step "0. tools"
need_tools wine wineboot wineserver winetricks msiinfo msibuild 7z git ghq unzip bash

step "1. wine prefix $WINEPREFIX"
if [ -f "$WINEPREFIX/system.reg" ]; then
	log "prefix exists (system.reg present), skipping wineboot"
else
	run "create 64-bit prefix" -- wineboot -u
	run "wait for wineserver" -- wineserver -w
	[ -f "$WINEPREFIX/system.reg" ] || die "wineboot finished but $WINEPREFIX/system.reg is missing"
fi
run "winetricks: windows version -> win10" -- winetricks -q win10
run "winetricks: vcrun2022 (needed by PACE) + corefonts" -- winetricks -q vcrun2022 corefonts
# Inno Setup installers skinned with ISSkin (sonible smart:limit, smart:EQ 4, smart:deess, prime:vocal) die with
# "Cannot Import dll: isskin.dll" (error 126): the 32-bit isskin.dll imports MFC42.DLL, which Wine does not ship
run "winetricks: mfc42 (ISSkin-based installers)" -- winetricks -q mfc42
log "winetricks verbs recorded in prefix: $(tr '\n' ' ' <"$WINEPREFIX/winetricks.log" 2>/dev/null)"
[ -f "$WINEPREFIX/drive_c/windows/system32/vcruntime140.dll" ] && log "vcruntime140.dll present" || die "vcrun2022 did not land in system32"
[ -f "$WINEPREFIX/drive_c/windows/syswow64/mfc42.dll" ] && log "mfc42.dll present (32-bit)" || die "mfc42 did not land in syswow64"

step "2. PACE License Support"
if try "is PACELicenseDServices already running" -- sh -c 'wine sc query PACELicenseDServices 2>/dev/null | grep -q RUNNING'; then
	log "PACE service already running, skipping install"
else
	[ -n "$LS_EXE" ] || die "pass the path to LicenseSupport.exe as \$1 (download from https://www.ilok.com/#!license-manager)"
	[ -f "$LS_EXE" ] || die "LicenseSupport.exe not found at: $LS_EXE"
	log "installer: $LS_EXE ($(stat -c %s "$LS_EXE") bytes, sha256 $(sha256sum "$LS_EXE" | cut -c1-16)...)"
	run "fetch sirsipe wine11 scripts (shallow) into $(ghq root)" -- ghq get -u --shallow github.com/sirsipe/ilok-pace-license-support-wine11-scripts
	[ -f "$PACE_REPO/install.sh" ] || die "expected $PACE_REPO/install.sh after ghq get"
	log "repo HEAD: $(git -C "$PACE_REPO" log -1 --format='%h %cs %s')"
	log "running sirsipe install.sh (msiexec logs land next to LicenseSupport.exe on failure)"
	run "sirsipe install.sh" -- env TMPDIR=/dev/shm bash "$PACE_REPO/install.sh" "$LS_EXE"
fi

step "3. verify PACE in prefix"
try "service state" -- wine sc query PACELicenseDServices
try "LDSvc.exe process" -- sh -c 'wine tasklist 2>/dev/null | grep -i LDSvc'
if try "Uninstall entry 'PACE License Support' (what the Hub looks for)" -- sh -c "wine reg query 'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall' /s 2>/dev/null | grep -i 'PACE License Support'"; then
	log "PACE OK: the Hub will treat iLok as installed"
else
	die "no Uninstall entry named 'PACE License Support'; the Hub would try to install ilm-win itself, which fails on Wine"
fi
log "step 1 done"
