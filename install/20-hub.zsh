#!/usr/bin/env zsh
# Step 2: install Complete Access Hub into the prefix and patch its elevation path.
# Usage: install/20-hub.zsh ["/path/to/Complete Access Hub Setup X.Y.Z.exe"]
#   Default: the newest "Complete Access Hub Setup*.exe" in ~/Downloads.
# What the shipped app does (static analysis of Hub 2.27.0):
#  - Setup is a stock NSIS stub from electron-builder (requireAdministrator, per-machine). Its
#    "is the app already running?" probe trusts Wine's powershell.exe stub, which exits 0, so the
#    silent install aborts with exit code 2. Disabling the stub makes it fall back to tasklist.
#  - The Install button uses @vscode/sudo-prompt:
#      powershell.exe Start-Process -FilePath 'execute.bat' -WindowStyle hidden -Verb runAs
#    Wine's PowerShell is a stub, so every elevated action fails. Wine already runs as admin,
#    so we replace that one line with cmd.exe "start /b".
#  - Electron fuses EnableEmbeddedAsarIntegrityValidation and OnlyLoadAppFromAsar are both off,
#    so the app can run unpacked from resources/app with app.asar renamed.
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

SETUP="${1:-$(command ls -t "$HOME"/Downloads/Complete\ Access\ Hub\ Setup*.exe 2>/dev/null | head -1)}"
APPDIR="$WINEPREFIX/drive_c/Program Files/Complete Access Hub"
RES="$APPDIR/resources"
HUBEXE="$APPDIR/Complete Access Hub.exe"

step "0. tools and prefix"
need_tools wine wineserver python3 sed grep
[ -f "$WINEPREFIX/system.reg" ] || die "prefix $WINEPREFIX missing; run install/10-prefix-pace.zsh first"

step "1. NSIS silent install"
if [ -f "$HUBEXE" ]; then
	log "already installed: $HUBEXE"
else
	[ -n "$SETUP" ] && [ -f "$SETUP" ] || die "setup exe not found (pass its path as \$1): '$SETUP'"
	log "setup: $SETUP ($(stat -c %s "$SETUP") bytes, sha256 $(sha256sum "$SETUP" | cut -c1-16)...)"
	run "wine setup /S (NSIS silent, per-machine; powershell stub disabled)" -- env WINEDLLOVERRIDES="powershell.exe=d" wine "$SETUP" /S
	run "wait for wineserver" -- wineserver -w
	[ -f "$HUBEXE" ] || die "setup returned but $HUBEXE is missing; run the setup without /S to see its dialog"
	log "installed: $(du -sh "$APPDIR" | cut -f1) in $APPDIR"
fi
log "resources dir: $(command ls -1 "$RES" | tr '\n' ' ')"

step "2. unpack app.asar -> resources/app"
if [ -f "$RES/app.asar" ]; then
	[ -d "$RES/app.asar.unpacked" ] || die "$RES/app.asar.unpacked missing; cannot restore native modules"
	log "app.asar: $(stat -c %s "$RES/app.asar") bytes"
	run "python unpack" -- python3 -I - "$RES" <<'EOF'
import json, struct, sys, os, shutil
res = sys.argv[1]
asar = os.path.join(res, "app.asar"); unpacked = asar + ".unpacked"; out = os.path.join(res, "app")
f = open(asar, "rb")
f.seek(4); hsz = struct.unpack("<I", f.read(4))[0]  # asar: [u32 4][u32 header pickle size][u32 str pickle][u32 json len][json...]
f.seek(12); hlen = struct.unpack("<I", f.read(4))[0]
hdr = json.loads(f.read(hlen).decode()); base = 8 + hsz
n = {"files": 0, "unpacked": 0}
def walk(node, rel):
    for name, v in node.get("files", {}).items():
        p = os.path.join(rel, name)
        if "files" in v:
            os.makedirs(os.path.join(out, p), exist_ok=True); walk(v, p); continue
        dst = os.path.join(out, p); os.makedirs(os.path.dirname(dst), exist_ok=True)
        if v.get("unpacked"):
            shutil.copy2(os.path.join(unpacked, p), dst); n["unpacked"] += 1
        elif "link" in v:
            pass  # symlinks are not used in this bundle
        else:
            f.seek(base + int(v["offset"])); open(dst, "wb").write(f.read(int(v["size"]))); n["files"] += 1
walk(hdr, "")
print(f"unpacked {n['files']} files + {n['unpacked']} native/unpacked files -> {out}")
print("package.json main:", json.load(open(os.path.join(out, "package.json")))["main"])  # sanity: offsets right
EOF
	for f in out/main/index.js node_modules/@vscode/sudo-prompt/index.js node_modules/pace-js/build/Release/pace-js.node; do
		[ -f "$RES/app/$f" ] && log "present: app/$f" || die "missing after unpack: app/$f"
	done
	run "disable app.asar (rename)" -- mv -- "$RES/app.asar" "$RES/app.asar.disabled"
	run "disable app.asar.unpacked (rename)" -- mv -- "$RES/app.asar.unpacked" "$RES/app.asar.unpacked.disabled"
else
	[ -d "$RES/app" ] && log "already unpacked (app.asar absent, resources/app present)" || die "neither app.asar nor resources/app in $RES"
fi

step "3. patch sudo-prompt elevation"
SP="$RES/app/node_modules/@vscode/sudo-prompt/index.js"
[ -f "$SP" ] || die "sudo-prompt not found at $SP"
if grep -q 'wine: no UAC' "$SP"; then
	log "already patched"
else
	grep -q -- "-Verb runAs" "$SP" || die "expected '-Verb runAs' in $SP (different sudo-prompt version?)"
	# only the WindowsElevate copy (the one right after '-Verb runAs'); the macOS/Linux ones keep the same text
	run "sed patch" -- sed -i "/-Verb runAs/,/command = command.join(' ');/ s|command = command.join(' ');|command = 'cmd.exe /c start \"\" /b \"' + instance.pathExecute + '\"'; // wine: no UAC, run execute.bat directly|" "$SP"
	grep -q 'wine: no UAC' "$SP" || die "patch did not apply in $SP"
fi
log "patched line: $(grep -n 'wine: no UAC' "$SP")"

step "4. done"
log "start it with: arch-slate-bridge hub (install/40-cli.zsh) or maintain/start-hub.zsh"
log "hub logs:  $WINEPREFIX/drive_c/users/$USER/AppData/Roaming/Complete Access Hub/logs/ (main.log, sudo-service.log)"
log "step 2 done"
