#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

readonly SUCKLESS_TOOLS=(dwm dmenu st)

info "Setting up suckless tools"

mkdir -p "$SRC_DIR"

for tool in "${SUCKLESS_TOOLS[@]}"; do
    TOOL_DIR="$SRC_DIR/$tool"

    if [[ ! -d "$TOOL_DIR" ]]; then
        info "Cloning $tool source..."
        git clone "https://git.suckless.org/$tool" "$TOOL_DIR"
    else
        info "$tool source already exists at $TOOL_DIR (manual updates only)"
    fi

    info "Building and installing $tool..."
    cd "$TOOL_DIR"
    make clean
    make
    sudo make install
    success "$tool installed"
done
