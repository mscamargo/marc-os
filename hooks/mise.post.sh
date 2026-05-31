#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=SCRIPTDIR/../functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../functions.sh"

if ! check_command mise; then
    error "mise not on PATH; cannot materialize tools"
    exit 1
fi

cfg="$HOME/.config/mise/config.toml"
if [[ ! -f "$cfg" ]]; then
    warn "mise config.toml not found at $cfg; skipping mise install"
    warn "Re-run after dotfiles are linked (configure.sh)"
    exit 0
fi

info "Installing mise-managed runtimes from $cfg"
mise install

info "Enabling corepack via mise-managed node"
mise exec node -- corepack enable || warn "corepack enable failed (non-fatal)"
