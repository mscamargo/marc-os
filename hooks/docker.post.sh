#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=SCRIPTDIR/../functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../functions.sh"

enable_service docker.service

if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    info "$USER is already in the docker group"
else
    info "Adding $USER to the docker group"
    sudo usermod -aG docker "$USER"
    warn "Log out and back in for the docker group to take effect"
fi
