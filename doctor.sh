#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=lib/lists.sh
source "$SCRIPT_DIR/lib/lists.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"

log::assert_non_root

readonly REPO_ROOT="$SCRIPT_DIR"
readonly DATA_DIR="$REPO_ROOT/data"

log::info "Checking for drift"

declare -i missing_pkgs=0

# shellcheck disable=SC2329  # invoked indirectly by lists::for_each_row
_check_pacman() {
    local name="$1"
    if ! pkg::is_installed_pacman "$name"; then
        log::warn "missing package: $name"
        ((missing_pkgs += 1))
    fi
}

# shellcheck disable=SC2329  # invoked indirectly by lists::for_each_row
_check_aur() {
    local name="$1"
    if ! pkg::is_installed_pacman "$name"; then
        log::warn "missing AUR package: $name"
        ((missing_pkgs += 1))
    fi
}

# shellcheck disable=SC2329  # invoked indirectly by lists::for_each_row
_check_git_src() {
    local url="$1"
    local key
    key="$(basename "$url" .git)"
    if ! pkg::is_installed_git_src "$key"; then
        log::warn "missing git source: $key ($url)"
        ((missing_pkgs += 1))
    fi
}

lists::for_each_row "$DATA_DIR/pacman.list" _check_pacman
lists::for_each_row "$DATA_DIR/aur.list" _check_aur
lists::for_each_row "$DATA_DIR/git_src.list" _check_git_src

total=$((missing_pkgs))
if ((total == 0)); then
    log::success "No drift detected"
    exit 0
fi

log::error "Drift detected ($total finding(s)):"
((missing_pkgs > 0)) && printf "  missing packages / sources: %d\n" "$missing_pkgs" >&2
exit 1
