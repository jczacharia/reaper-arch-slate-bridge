#!/usr/bin/env zsh
# Step 0 (sudo): system packages.
#  - msitools: patch the PACE License Support MSI (step 1)
#  - meson:    build yabridge from master (step 3)
#  - remove Arch's yabridge/yabridgectl 5.1.1 if present: the chainloader loads libyabridge-*.so
#    from the directory of the first yabridge-host.exe on PATH, so /usr/bin always beat the
#    master build in ~/.local/share/yabridge, and 5.1.1 ignores mouse input on Wine >= 9.22.
# Idempotent: --needed skips installed packages; removal skips absent ones.
set -uo pipefail
[ "$EUID" -ne 0 ] && {
	echo "run with sudo"
	exit 1
}

echo "==== pacman: ensure msitools meson ===="
pacman -S --needed --noconfirm msitools meson || {
	echo "FAILED: pacman -S"
	exit 1
}

for p in yabridge yabridgectl; do
	if pacman -Q "$p" >/dev/null 2>&1; then
		echo "==== pacman -Rns $p (conflicts with the master build) ===="
		pacman -Rns --noconfirm "$p" || {
			echo "FAILED removing $p"
			exit 1
		}
	else
		echo "not installed (good): $p"
	fi
done

echo "==== verify ===="
for t in msiinfo msibuild meson; do command -v "$t" >/dev/null && echo "ok: $t" || {
	echo "MISSING after install: $t"
	exit 1
}; done
for f in /usr/bin/yabridge-host.exe /usr/lib/libyabridge-vst3.so /usr/bin/yabridgectl; do
	[ -e "$f" ] && {
		echo "STILL PRESENT: $f"
		exit 1
	} || echo "gone: $f"
done
echo "done"
