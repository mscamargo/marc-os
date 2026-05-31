#!/usr/bin/env bash
# Shared helpers for install.sh, configure.sh, doctor.sh, and per-package
# hooks. Sourced; does not set -e itself (callers do).
#
# Transitional shim: the canonical implementations now live in lib/*.sh.
# This file keeps the old un-namespaced names alive while callers migrate.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=lib/util.sh
source "$REPO_ROOT/lib/util.sh"
# shellcheck source=lib/sudo.sh
source "$REPO_ROOT/lib/sudo.sh"
# shellcheck source=lib/packages.sh
source "$REPO_ROOT/lib/packages.sh"
# shellcheck source=lib/dotfiles.sh
source "$REPO_ROOT/lib/dotfiles.sh"

info()                      { log::info "$1"; }
warn()                      { log::warn "$1"; }
error()                     { log::error "$1"; }
success()                   { log::success "$1"; }
die()                       { log::die "$1"; }
assert_non_root()           { log::assert_non_root; }
check_command()             { util::has_command "$1"; }
pacman_install()            { pkg::install_pacman "$@"; }
enable_service()            { pkg::enable_service "$1"; }
migrate_ancestor_symlinks() { dot::migrate_ancestors "$1" "$REPO_ROOT"; }
link_dotfile()              { dot::link "$1" "$2" "$REPO_ROOT"; }
prune_stale_links_in()      { dot::prune_stale_in "$1" "$REPO_ROOT" "${2:-}"; }
configure_dotfiles()        { dot::configure "$REPO_ROOT/dotfiles" "$HOME"; }

# Strip surrounding double quotes from $1 (LARBS-style desc).
unquote() {
    local s="$1"
    s="${s#\"}"
    s="${s%\"}"
    printf '%s' "$s"
}

# Parse "tag,name,desc" with optional "..."-wrapped desc that may contain commas.
# Sets PARSED_TAG, PARSED_NAME, PARSED_DESC for the caller.
# shellcheck disable=SC2034  # PARSED_* are read by install.sh / doctor.sh
parse_row() {
    local row="$1"
    PARSED_TAG=""; PARSED_NAME=""; PARSED_DESC=""
    IFS=',' read -r PARSED_TAG PARSED_NAME PARSED_DESC <<< "$row"
    if [[ "$PARSED_DESC" == \"* && "$PARSED_DESC" != *\" ]]; then
        # Quoted desc with embedded commas: re-extract tail from second comma.
        PARSED_DESC="${row#*,*,}"
    fi
    PARSED_DESC="$(unquote "$PARSED_DESC")"
}
