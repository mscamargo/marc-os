#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

info "Starting marc-os setup"

for script in "$SCRIPT_DIR"/scripts/*.sh; do
    if [[ -x "$script" ]]; then
        info "Running $(basename "$script")"
        "$script"
    else
        warn "Skipping non-executable: $(basename "$script")"
    fi
done

success "Setup complete. Restart your shell or run: exec zsh -l"
