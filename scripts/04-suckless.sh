#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_DIR="$REPO_ROOT/packages"

readonly SUCKLESS_TOOLS=(dwm dmenu st surf)

info "Setting up suckless tools"

for tool in "${SUCKLESS_TOOLS[@]}"; do
    TOOL_DIR="$PACKAGES_DIR/$tool"

    if [[ ! -d "$TOOL_DIR" ]]; then
        warn "$tool not found at $TOOL_DIR, skipping"
        continue
    fi

    info "Building and installing $tool..."
    cd "$TOOL_DIR"
    make clean
    make
    sudo make install
    success "$tool installed"
done
