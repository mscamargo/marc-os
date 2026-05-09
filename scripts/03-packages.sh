#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Installing main packages"

pacman_install \
    zsh \
    neovim \
    brightnessctl \
    acpi \
    alsa-utils \
    pipewire \
    pipewire-pulse \
    wireplumber \
    noto-fonts \
    noto-fonts-emoji \
    ttf-hack \
    ttf-jetbrains-mono \
    picom \
    feh \
    zsh-completions \
    zsh-syntax-highlighting \
    zsh-autosuggestions

success "Main packages installed"
