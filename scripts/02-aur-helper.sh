#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

if check_command yay; then
    info "yay is already installed"
    exit 0
fi

info "Bootstrapping yay AUR helper"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

success "yay installed"
