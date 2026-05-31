#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Installing applications"

pacman_install \
    alacritty \
    qutebrowser \
    firefox \
    chromium \
    yazi \
    lf \
    ranger \
    maim \
    slop \
    xclip \
    xdotool \
    clipmenu \
    playerctl \
    xdg-utils \
    xdg-user-dirs

info "Installing AUR applications"
yay -S --needed --noconfirm google-chrome

success "Applications installed"
