#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

ZSH_PATH="$(command -v zsh)"

if [[ "$SHELL" == "$ZSH_PATH" ]]; then
    info "zsh is already the default shell"
    exit 0
fi

info "Changing default shell to zsh"
chsh -s "$ZSH_PATH"

success "Default shell changed to zsh"
