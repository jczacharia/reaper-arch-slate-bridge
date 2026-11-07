#!/usr/bin/env zsh
# Step 3: yabridge from master, installed per-user, then bridge the prefix's VST3 dir.
# Why master: the Wine >= 9.22 fix (mouse input in plugin editors) is merged but unreleased;
# the 5.1.1 release does not work with current Wine. yabridgectl is built from the same
# checkout because the 5.1.1 binary panics on 'set --path'.
# Usage: install/30-yabridge.zsh
set -uo pipefail
[ "$EUID" -eq 0 ] && {
	echo "run as user, not sudo"
	exit 1
}
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

SRC="$(ghq root)/github.com/robbert-vdh/yabridge"
DEST="$HOME/.local/share/yabridge"
YCTL="$HOME/.local/bin/yabridgectl"
VST3DIR="$WINEPREFIX/drive_c/Program Files/Common Files/VST3"

step "0. tools"
need_tools git ghq meson ninja winegcc cargo
[ -e /usr/bin/yabridge-host.exe ] && die "Arch's yabridge package is still installed; run install/00-prereqs-sudo.zsh first"

step "1. source"
run "fetch yabridge master (shallow) into $(ghq root)" -- ghq get -u --shallow github.com/robbert-vdh/yabridge
[ -f "$SRC/meson.build" ] || die "expected $SRC/meson.build after ghq get"
head="$(git -C "$SRC" rev-parse --short HEAD)"
log "HEAD: $(git -C "$SRC" log -1 --format='%h %cs %s')"

step "2. build"
if [ -f "$DEST/.built-$head" ]; then
	log "already built @ $head in $DEST"
else
	cd "$SRC" || die "cd $SRC"
	if [ -d build ]; then
		log "reusing existing build dir"
	else
		run "meson setup (cross-wine)" -- meson setup build --buildtype=release --cross-file=cross-wine.conf --unity=on --unity-size=1000
	fi
	run "ninja -C build" -- ninja -C build
	cd - >/dev/null
	mkdir -p "$DEST"
	for f in libyabridge-chainloader-vst2.so libyabridge-chainloader-vst3.so libyabridge-chainloader-clap.so \
		libyabridge-vst2.so libyabridge-vst3.so libyabridge-clap.so yabridge-host.exe yabridge-host.exe.so; do
		[ -f "$SRC/build/$f" ] || die "build produced no $f (check ninja output above)"
		run "install $f" -- cp -f "$SRC/build/$f" "$DEST/"
	done
	touch "$DEST/.built-$head"
	log "built yabridge master @ $head -> $DEST"
fi
if [ -x "$YCTL" ] && [ -f "$DEST/.yabridgectl-$head" ]; then
	log "yabridgectl already built @ $head: $YCTL"
else
	run "cargo build yabridgectl (release)" -- cargo build --release --manifest-path "$SRC/tools/yabridgectl/Cargo.toml"
	mkdir -p "$HOME/.local/bin"
	run "install yabridgectl -> $YCTL" -- cp -f "$SRC/tools/yabridgectl/target/release/yabridgectl" "$YCTL"
	touch "$DEST/.yabridgectl-$head"
fi
log "yabridgectl: $("$YCTL" --version)"

step "3. yabridgectl"
run "point yabridgectl at $DEST" -- "$YCTL" set --path "$DEST"
"$YCTL" status 2>&1 | grep -q "yabridge-host.exe: '$DEST/" || die "yabridgectl status does not resolve yabridge-host.exe from $DEST"
mkdir -p "$VST3DIR"
try "register $VST3DIR (ok if already added)" -- "$YCTL" add "$VST3DIR"
run "yabridgectl sync" -- "$YCTL" sync
run "yabridgectl status" -- "$YCTL" status
log "In REAPER: Preferences > Plug-ins > VST, make sure ~/.vst3 is scanned, then re-scan."
log "step 3 done"
