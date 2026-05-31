#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/log.sh
source "$__HOOK_DIR/../lib/log.sh"

key="$HOME/.ssh/id_ed25519"

if [[ ! -f "$key" ]]; then
    log::info "Generating ed25519 SSH key at $key"
    [[ -d "$HOME/.ssh" ]] || mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$USER@$(hostname)" -f "$key" -N ""
else
    log::info "SSH key already present at $key"
fi

if systemctl --user is-enabled --quiet ssh-agent.service 2> /dev/null \
    && systemctl --user is-active --quiet ssh-agent.service 2> /dev/null; then
    log::info "ssh-agent.service (user) already enabled and active"
else
    log::info "Enabling and starting ssh-agent.service (user)"
    systemctl --user enable --now ssh-agent.service
fi

log::info "Public key:"
cat -- "$key.pub"
