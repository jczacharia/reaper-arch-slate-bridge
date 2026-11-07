#!/usr/bin/env zsh
# Step 1b: DXVK in the prefix. Plugins whose editors render with Direct3D (SSL Native: GateVerb,
# X-Orcism) hang REAPER on closing the editor under Wine's built-in D3D (wined3d); the yabridge
# trace ends at IPlugView::removed() with no reply. yabridge's README names DXVK as the fix for
# D3D-rendered editors. Needs a working Vulkan driver (vulkaninfo must list your GPU).
# Usage: install/15-dxvk.zsh
set -uo pipefail
[ "$EUID" -eq 0 ] && { echo "run as user, not sudo"; exit 1; }
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-slate}"
source "${0:A:h}/../lib/log.zsh"

step "0. tools"
need_tools wine winetricks vulkaninfo
[ -f "$WINEPREFIX/system.reg" ] || die "no prefix at $WINEPREFIX; run install/10-prefix-pace.zsh first"
vulkaninfo --summary 2>/dev/null | grep -E '^\s*deviceName' | while read -r l; do log "vulkan: $l"; done
vulkaninfo --summary 2>/dev/null | grep -q deviceName || die "no Vulkan device; DXVK cannot work without one (install your GPU's vulkan driver)"

step "1. dxvk"
if wine reg query 'HKCU\Software\Wine\DllOverrides' /v '*d3d11' 2>/dev/null | grep -q native; then
  log "already installed: d3d11 override '*d3d11' is 'native' (winetricks writes the keys with a leading *) in $WINEPREFIX"
else
  run "winetricks -q dxvk (downloads the latest DXVK release from GitHub)" -- winetricks -q dxvk
fi

step "2. verify"
for d in d3d11 dxgi d3d9; do
  wine reg query 'HKCU\Software\Wine\DllOverrides' /v "*$d" 2>/dev/null | grep -q native && log "override ok: $d=native" || die "override missing for $d; winetricks dxvk did not complete"
done
log "restart REAPER; the D3D plugin editors now render through Vulkan. Roll back: WINEPREFIX=$WINEPREFIX winetricks -q dxvk=none"  # not tested
log "step 1b done"
