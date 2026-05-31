#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Updating system"
sudo pacman -Syu --noconfirm

info "Installing AUR helper prerequisites"
pacman_install base-devel git

success "Base prerequisites installed"
