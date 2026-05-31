#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=SCRIPTDIR/../functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../functions.sh"

key="$HOME/.ssh/id_ed25519"

if [[ ! -f "$key" ]]; then
    info "Generating ed25519 SSH key at $key"
    [[ -d "$HOME/.ssh" ]] || mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$USER@$(hostname)" -f "$key" -N ""
else
    info "SSH key already present at $key"
fi

if systemctl --user is-enabled --quiet ssh-agent.service 2>/dev/null \
   && systemctl --user is-active --quiet ssh-agent.service 2>/dev/null; then
    info "ssh-agent.service (user) already enabled and active"
else
    info "Enabling and starting ssh-agent.service (user)"
    systemctl --user enable --now ssh-agent.service
fi

info "Public key:"
cat -- "$key.pub"
