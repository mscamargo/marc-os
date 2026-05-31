#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Installing window manager stack"

pacman_install \
    i3-wm \
    i3status \
    i3lock \
    xss-lock \
    dunst \
    picom \
    rofi \
    polkit-gnome \
    autorandr \
    arandr

success "Window manager stack installed"
