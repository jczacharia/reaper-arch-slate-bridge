#!/usr/bin/env zsh
# While REAPER is frozen on a plugin: dump every thread's stack of each yabridge-host process
# (the Wine side) and of REAPER itself, with symbols for the Linux libraries. This is the only
# way to see which library the Wine side is stuck or crashed in; the yabridge trace stops at the
# last call. Needs sudo because Arch sets kernel.yama.ptrace_scope=1 (no attaching otherwise).
# Writes backtrace-<time>.log next to this repo's cah-wine.log. Does not kill anything.
# Usage: sudo maintain/backtrace-sudo.zsh   (or: sudo arch-slate-bridge backtrace)
set -uo pipefail
[ "$EUID" -ne 0 ] && { echo "run with sudo (ptrace_scope=$(cat /proc/sys/kernel/yama/ptrace_scope))"; exit 1; }
REPO_ROOT="${0:A:h:h}"
OUT="$REPO_ROOT/backtrace-$(date +%H%M%S).log"
command -v gdb >/dev/null || { echo "missing tool: gdb (pacman -S gdb)"; exit 1; }

pids=("${(@f)$(pgrep -f 'yabridge-hos[t]')}")
reaper="$(pgrep -x reaper | head -1)"
[ -n "${pids[1]:-}" ] || { echo "no yabridge-host process; reproduce the hang first and leave REAPER frozen"; exit 1; }

{
  for p in "${pids[@]}"; do
    echo "==== yabridge-host pid $p: $(tr '\0' ' ' </proc/$p/cmdline | cut -c1-200)"
    echo "---- threads"; ls /proc/$p/task | wc -l
    gdb -p "$p" -batch -ex 'set pagination off' -ex 'thread apply all bt' 2>&1 | grep -vE '^\[New LWP|^\[Thread debugging|^Using host|warning: .*debuginfod'
    echo "---- maps (to resolve addresses from the yabridge trace)"
    grep -E '\.so|\.exe' /proc/$p/maps | awk '{print $1, $6}' | sort -u -k2 | head -80
  done
  if [ -n "$reaper" ]; then
    echo "==== reaper pid $reaper (main thread only)"
    gdb -p "$reaper" -batch -ex 'set pagination off' -ex 'bt' 2>&1 | grep -vE '^\[New LWP|^\[Thread debugging|^Using host|warning: .*debuginfod'
  fi
} >| "$OUT" 2>&1
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT"
echo "wrote $OUT ($(wc -l <"$OUT") lines); processes were resumed untouched"
