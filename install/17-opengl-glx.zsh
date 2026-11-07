#!/usr/bin/env zsh
# Step 1c: make Wine use its GLX OpenGL backend instead of the EGL one (Wine 11 default).
# Why: OpenGL plugins (Inf Horizon, learneq, pufferfish: JUCE/GLEW editors) ask
# wglChoosePixelFormatARB for a window format with 8 alpha bits. Wine's EGL backend offers alpha
# only on offscreen formats on NVIDIA + Xwayland, so the call returns 0 formats, the plugin
# creates no context, dereferences its null GL table, and the host process dies in Wine's
# unwinder (REAPER then waits forever). The GLX backend reports the same formats Windows does.
# UseEGL is the documented switch (Wine 11.0 release notes). Verified with tools/wgl-probe.c.
# Usage: install/17-opengl-glx.zsh
set -uo pipefail
[ "$EUID" -eq 0 ] && { echo "run as user, not sudo"; exit 1; }
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"
KEY='HKCU\Software\Wine\X11 Driver'
PROBE_SRC="${0:A:h}/../tools/wgl-probe.c"

step "0. tools"
need_tools wine winegcc
[ -f "$WINEPREFIX/system.reg" ] || die "no prefix at $WINEPREFIX; run install/10-prefix-pace.zsh first"
[ -f "$PROBE_SRC" ] || die "missing $PROBE_SRC"

step "1. UseEGL=N"
if wine reg query "$KEY" /v UseEGL 2>/dev/null | grep -qE '^\s*UseEGL\s+REG_SZ\s+N'; then
  log "already set: UseEGL=N"
else
  run "set $KEY\\UseEGL = N" -- wine reg add "$KEY" /v UseEGL /t REG_SZ /d N /f
fi

step "2. verify with the probe (the exact pixel-format request Inf Horizon makes)"
tmp="$(mktemp -d)"
run "winegcc tools/wgl-probe.c" -- winegcc -o "$tmp/probe" "$PROBE_SRC" -lopengl32 -lgdi32 -luser32
out="$(timeout 60 wine "$tmp/probe.exe" 2>/dev/null | grep formats=)"
trash-put -f -- "$tmp"
log "probe: ${out:-no output}"
[[ "$out" == *"formats=0"* || -z "$out" ]] && die "GLX backend still offers no window format with alpha; the plugin will crash. Check 'wine reg query' output above and that the display is NVIDIA (glxinfo -B)"
log "restart REAPER; OpenGL plugin editors now get a pixel format. Revert: wine reg delete '$KEY' /v UseEGL /f"
log "step 1c done"
