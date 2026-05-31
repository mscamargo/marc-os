#!/usr/bin/env bash
# lib/sudo.sh — long-running sudo keepalive. Depends on log.
[[ -n ${__LIB_SUDO_SOURCED:-} ]] && return 0
__LIB_SUDO_SOURCED=1

__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/log.sh
source "$__LIB_DIR/log.sh"
unset __LIB_DIR

readonly SUDO_KEEPALIVE_INTERVAL=60

# sudo::keepalive_start — refresh sudo, spawn a background refresher, install
# an EXIT trap to stop it. Sets SUDO_KEEPALIVE_PID.
sudo::keepalive_start() {
    sudo -v || log::die "sudo authentication failed"
    (while true; do
        sudo -n true 2> /dev/null || exit
        sleep "$SUDO_KEEPALIVE_INTERVAL"
    done) &
    SUDO_KEEPALIVE_PID=$!
    trap sudo::keepalive_stop EXIT
}

# sudo::keepalive_stop — kill the background refresher if running. Idempotent.
sudo::keepalive_stop() {
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] || return 0
    kill "$SUDO_KEEPALIVE_PID" 2> /dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2> /dev/null || true
    unset SUDO_KEEPALIVE_PID
}
