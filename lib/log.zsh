# Shared logging for every script in this repo. Source it; do not run it.
# Every step is announced, every command is echoed with its exit code, and a failure
# names the step and exit code. Output is also appended to <repo>/cah-wine.log.
REPO_ROOT="${REPO_ROOT:-${0:A:h:h}}"
CAH_LOG="${CAH_LOG:-$REPO_ROOT/cah-wine.log}"
exec > >(tee -a "$CAH_LOG") 2>&1
_ts() { date '+%H:%M:%S'; }
log() { print -r -- "[$(_ts)] $*"; }
step() {
	print -r -- ""
	print -r -- "[$(_ts)] ==== $* ===="
}
die() {
	print -r -- "[$(_ts)] FATAL: $*"
	print -r -- "see $CAH_LOG"
	exit 1
}
# run <description> -- <command...> : echo, execute, report exit code, abort on failure
run() {
	local desc="$1"
	shift
	[ "$1" = "--" ] && shift
	log "-> $desc"
	log "   \$ ${(j: :)${(q)@}}"
	local rc=0
	"$@" || rc=$?
	if [ $rc -ne 0 ]; then die "step '$desc' failed with exit code $rc"; fi
	log "   ok (exit 0)"
}
# try <description> -- <command...> : same, but a failure is only logged
try() {
	local desc="$1"
	shift
	[ "$1" = "--" ] && shift
	log "-> $desc"
	log "   \$ ${(j: :)${(q)@}}"
	local rc=0
	"$@" || rc=$?
	log "   exit $rc"
	return $rc
}
need_tools() { for t in "$@"; do command -v "$t" >/dev/null && log "tool ok: $t ($(command -v $t))" || die "missing tool: $t"; done; }
# Silence Mesa/EGL chatter from wine processes on NVIDIA (harmless, but it drowns real output)
export EGL_LOG_LEVEL=fatal
export WINEDEBUG="${WINEDEBUG:--all}"
log "script: ${0:A}  user: $USER  pwd: $PWD"
log "WINEPREFIX=${WINEPREFIX:-<unset>}  wine=$(command -v wine 2>/dev/null) $(wine --version 2>/dev/null)"
