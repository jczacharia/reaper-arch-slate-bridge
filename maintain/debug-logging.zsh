#!/usr/bin/env zsh
# Turn yabridge's trace on or off for REAPER. Without it, plugin and Wine output goes to
# REAPER's stderr, which is lost when REAPER is started from the desktop (systemd user unit).
# "on" writes ~/.config/environment.d/60-yabridge.conf (every future login) and sets the same
# variables in the running systemd user manager, so the next REAPER start picks them up.
# Usage: maintain/debug-logging.zsh on|off   (or: arch-slate-bridge debug on|off)
set -uo pipefail
[ "$EUID" -eq 0 ] && { echo "run as user, not sudo"; exit 1; }
source "${0:A:h}/../lib/log.zsh"

CONF="$HOME/.config/environment.d/60-yabridge.conf"
YLOG="${YABRIDGE_LOG:-$HOME/.local/state/yabridge/yabridge.log}"
# level 1 logs every host<->plugin call (enough to see which call never returns); +editor adds
# window attach/remove detail, which is where REAPER hung (IPlugView::removed). 2 is too noisy.
LEVEL="1+editor"
# "on seh" also makes Wine log every exception (code, address, backtrace) in the plugin process;
# that is what identifies a crash that only shows up as "stack overflow" in the trace.
WINE_CH="${2:-}"; [ -z "$WINE_CH" ] || [ "$WINE_CH" = seh ] || die "usage: $0 on [seh] | off"

case "${1:-}" in
  on)
    step "1. enable"
    mkdir -p "${CONF:h}" "${YLOG:h}"
    printf 'YABRIDGE_DEBUG_FILE=%s\nYABRIDGE_DEBUG_LEVEL=%s\n' "$YLOG" "$LEVEL" >| "$CONF"
    [ "$WINE_CH" = seh ] && printf 'WINEDEBUG=+seh,+wgl,+opengl\n' >> "$CONF"
    log "wrote $CONF"
    run "apply to the systemd user manager (new REAPER starts see it)" -- \
      systemctl --user set-environment "YABRIDGE_DEBUG_FILE=$YLOG" "YABRIDGE_DEBUG_LEVEL=$LEVEL"
    if [ "$WINE_CH" = seh ]; then
      run "wine exception + OpenGL/WGL call logging on" -- systemctl --user set-environment WINEDEBUG=+seh,+wgl,+opengl
    else
      try "wine exception logging off" -- systemctl --user unset-environment WINEDEBUG
    fi
    log "restart REAPER, reproduce, then: arch-slate-bridge logs"
    ;;
  off)
    step "1. disable"
    [ -e "$CONF" ] && run "remove $CONF" -- trash-put -f -- "$CONF"
    run "unset in the systemd user manager" -- systemctl --user unset-environment YABRIDGE_DEBUG_FILE YABRIDGE_DEBUG_LEVEL WINEDEBUG
    log "restart REAPER for it to take effect; $YLOG is kept"
    ;;
  *) die "usage: $0 on [seh] | off" ;;
esac
step "2. state"
log "environment.d: $(cat "$CONF" 2>/dev/null | tr '\n' ' ' || echo none)"
log "systemd user env: $(systemctl --user show-environment | grep -E 'YABRIDGE|WINEDEBUG' | tr '\n' ' ')"
pgrep -x reaper >/dev/null && log "REAPER is running with the OLD environment; restart it"
