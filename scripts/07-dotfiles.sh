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

# i3 stack
link_dotfile "$CONFIG_DIR/i3"          "$HOME/.config/i3"
link_dotfile "$CONFIG_DIR/i3status"    "$HOME/.config/i3status"
link_dotfile "$CONFIG_DIR/alacritty"   "$HOME/.config/alacritty"
link_dotfile "$CONFIG_DIR/rofi"        "$HOME/.config/rofi"
link_dotfile "$CONFIG_DIR/dunst"       "$HOME/.config/dunst"
link_dotfile "$CONFIG_DIR/picom"       "$HOME/.config/picom"
link_dotfile "$CONFIG_DIR/qutebrowser" "$HOME/.config/qutebrowser"

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
