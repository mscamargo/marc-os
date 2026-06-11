#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/log.sh
source "$__HOOK_DIR/../lib/log.sh"
# shellcheck source=SCRIPTDIR/../lib/util.sh
source "$__HOOK_DIR/../lib/util.sh"

if ! util::has_command mise; then
    log::error "mise not on PATH; cannot materialize tools"
    exit 1
fi

cfg="$HOME/.config/mise/config.toml"
if [[ ! -f "$cfg" ]]; then
    log::warn "mise config.toml not found at $cfg; skipping mise install"
    log::warn "Re-run after your dotfiles provide $cfg"
    exit 0
fi

log::info "Installing mise-managed runtimes from $cfg"
mise install

log::info "Enabling corepack via mise-managed node"
mise exec node -- corepack enable || log::warn "corepack enable failed (non-fatal)"
