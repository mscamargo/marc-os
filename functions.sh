#!/usr/bin/env bash
# Shared helpers for install.sh and per-package hooks.
# Sourced; does not set -e itself (callers do).

readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    printf "${C_BLUE}==>${C_RESET} %s\n" "$1"
}

warn() {
    printf "${C_YELLOW}WARN:${C_RESET} %s\n" "$1"
}

error() {
    printf "${C_RED}ERROR:${C_RESET} %s\n" "$1" >&2
}

success() {
    printf "${C_GREEN}==>${C_RESET} %s\n" "$1"
}

die() {
    error "$1"
    exit 1
}

check_command() {
    command -v "$1" &>/dev/null
}

pacman_install() {
    info "Installing: $*"
    sudo pacman -S --needed --noconfirm "$@"
}

: "${DRY_RUN:=0}"

# Returns 0 if any ancestor of $dest (up to $HOME) is a symlink resolving
# into $REPO_ROOT, else 1. Used to short-circuit dry-run reporting.
has_ancestor_symlink_into_repo() {
    local dest="$1" dir target
    dir="$(dirname "$dest")"
    while [[ "$dir" == "$HOME"/* ]]; do
        if [[ -L "$dir" ]]; then
            target="$(readlink -f -- "$dir" 2>/dev/null || true)"
            [[ -n "$target" && "$target" == "$REPO_ROOT"* ]] && return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Replace any ancestor of $dest that is a symlink pointing into $REPO_ROOT
# with a real directory. Stops at $HOME. Handles the legacy state where a
# whole config dir (e.g. ~/.config/nvim) is a symlink into the repo.
migrate_ancestor_symlinks() {
    local dest="$1" dir target
    dir="$(dirname "$dest")"
    while [[ "$dir" == "$HOME"/* ]]; do
        if [[ -L "$dir" ]]; then
            target="$(readlink -f -- "$dir" 2>/dev/null || true)"
            if [[ -n "$target" && "$target" == "$REPO_ROOT"* ]]; then
                if (( DRY_RUN )); then
                    info "[dry-run] would replace dir-symlink with real dir: $dir"
                else
                    info "Replacing dir-symlink with real dir: $dir"
                    rm -- "$dir"
                fi
            fi
        fi
        dir="$(dirname "$dir")"
    done
}

# Symlink a single leaf file from the repo into the target tree.
# Auto-migrates any dir-symlink ancestor that points into the repo.
# Real files in the way are moved aside to <dest>.backup.<ts>.
link_dotfile() {
    local src="$1"
    local dest="$2"

    # Dry-run accuracy: if a parent dir-symlink would be removed in a real
    # run, the dest's existence checks would all be false afterwards. Skip
    # the misleading "would back up" branch in that case.
    if (( DRY_RUN )) && has_ancestor_symlink_into_repo "$dest"; then
        migrate_ancestor_symlinks "$dest"
        info "[dry-run] would link: $dest -> $src"
        return 0
    fi

    migrate_ancestor_symlinks "$dest"

    if [[ -L "$dest" && "$(readlink -f -- "$dest")" == "$src" ]]; then
        return 0
    fi

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        if (( DRY_RUN )); then
            warn "[dry-run] would back up existing file: $dest -> $dest.backup.<ts>"
        else
            warn "Backing up existing file: $dest"
            mv -- "$dest" "$dest.backup.$(date +%s)"
        fi
    fi

    if (( DRY_RUN )); then
        info "[dry-run] would link: $dest -> $src"
        return 0
    fi

    mkdir -p -- "$(dirname "$dest")"
    ln -sfn -- "$src" "$dest"
    info "Linked: $dest -> $src"
}

# Remove broken symlinks within $dir whose canonical target lives inside
# $REPO_ROOT. Optional second arg caps find depth (used for $HOME scan).
prune_stale_links_in() {
    local dir="$1"
    local -a find_args=("$dir")
    if [[ -n "${2:-}" ]]; then
        find_args+=(-maxdepth "$2")
    fi
    find_args+=(-type l -print0)

    local link target
    while IFS= read -r -d '' link; do
        target="$(readlink -f -- "$link" 2>/dev/null || true)"
        if [[ -n "$target" && "$target" == "$REPO_ROOT"* && ! -e "$target" ]]; then
            if (( DRY_RUN )); then
                info "[dry-run] would prune stale link: $link"
            else
                info "Pruning stale link: $link"
                rm -- "$link"
            fi
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
}

