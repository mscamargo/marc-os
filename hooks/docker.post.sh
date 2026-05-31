#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/packages.sh
source "$__HOOK_DIR/../lib/packages.sh"

pkg::enable_service docker.service

if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    log::info "$USER is already in the docker group"
else
    log::info "Adding $USER to the docker group"
    sudo usermod -aG docker "$USER"
    log::warn "Log out and back in for the docker group to take effect"
fi
