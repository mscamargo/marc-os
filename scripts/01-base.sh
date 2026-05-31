#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Updating system and installing base packages"

sudo pacman -Syu --noconfirm

pacman_install \
    base-devel \
    git \
    xorg-server \
    xorg-xinit \
    xorg-xrandr \
    xorg-xsetroot

success "Base packages installed"
