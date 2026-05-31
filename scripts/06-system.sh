#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Installing system services (network, bluetooth)"

pacman_install \
    networkmanager \
    bluez \
    bluez-utils

info "Enabling NetworkManager and bluetooth"
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service

success "System services installed and enabled"
