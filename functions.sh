#!/usr/bin/env bash
# Shared helpers for install.sh and per-package hooks.
# Sourced; does not set -e itself (callers do).

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    printf "${C_BLUE}==>${C_RESET} %s\n" "$1"
}

warn() {
    printf "${C_YELLOW}WARN:${C_RESET} %s\n" "$1"
}

error() {
    printf "${C_RED}ERROR:${C_RESET} %s\n" "$1" >&2
}

success() {
    printf "${C_GREEN}==>${C_RESET} %s\n" "$1"
}

die() {
    error "$1"
    exit 1
}

check_command() {
    command -v "$1" &>/dev/null
}

pacman_install() {
    info "Installing: $*"
    sudo pacman -S --needed --noconfirm "$@"
}

link_dotfile() {
    local src="$1"
    local dest="$2"

    if [[ -L "$dest" && "$(readlink -f "$dest")" == "$src" ]]; then
        info "Link already correct: $dest"
        return 0
    fi

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        warn "Backing up existing file: $dest"
        mv "$dest" "$dest.backup.$(date +%s)"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest"
    success "Linked: $dest -> $src"
}

run_hook() {
    local hook="$1"
    local path="$REPO_ROOT/$hook"
    [[ -f "$path" ]] || { error "hook missing: $hook"; return 1; }
    bash "$path"
}
