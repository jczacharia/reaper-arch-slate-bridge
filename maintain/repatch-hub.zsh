#!/usr/bin/env zsh
# Re-apply the Hub patch after the Hub updates itself (an update restores app.asar, which
# undoes the sudo-prompt patch and brings the dead Install button back). Same script as the
# install step; with the Hub already installed it only unpacks and patches.
exec "${0:A:h}/../install/20-hub.zsh" "$@"
