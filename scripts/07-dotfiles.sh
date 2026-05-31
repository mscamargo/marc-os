#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/config"

info "Linking dotfiles"

# X11
link_dotfile "$CONFIG_DIR/x11/.xinitrc" "$HOME/.xinitrc"

# Zsh
link_dotfile "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
link_dotfile "$CONFIG_DIR/zsh/.zprofile" "$HOME/.zprofile"

# Neovim
link_dotfile "$CONFIG_DIR/nvim" "$HOME/.config/nvim"

# Custom scripts
mkdir -p "$HOME/.local/bin"
if [[ -d "$CONFIG_DIR/bin" ]]; then
    for script in "$CONFIG_DIR/bin"/*; do
        if [[ -f "$script" ]]; then
            link_dotfile "$script" "$HOME/.local/bin/$(basename "$script")"
        fi
    done
fi

success "Dotfiles linked"
