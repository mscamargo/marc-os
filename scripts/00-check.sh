#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

info "Running pre-flight checks"

if [[ ! -f /etc/arch-release ]]; then
    die "This script is intended for Arch Linux only."
fi

if [[ "$EUID" -eq 0 ]]; then
    die "Do not run this script as root. It will use sudo when needed."
fi

if ! check_command pacman; then
    die "pacman not found. Is this Arch Linux?"
fi

if ! check_command git; then
    die "git is required but not installed. Install it first: sudo pacman -S git"
fi

# Check internet connectivity
if ! ping -c 1 -W 2 archlinux.org &>/dev/null; then
    die "No internet connection detected."
fi

success "Pre-flight checks passed"
