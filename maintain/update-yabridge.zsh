#!/usr/bin/env zsh
# Rebuild yabridge + yabridgectl from current master and re-sync. Run after a Wine upgrade
# breaks plugin editors, or when yabridge master has a fix you need. Same script as the install
# step; it is idempotent and only rebuilds when HEAD changed.
exec "${0:A:h}/../install/30-yabridge.zsh" "$@"
