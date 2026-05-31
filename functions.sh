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

info()             { log::info "$1"; }
warn()             { log::warn "$1"; }
error()            { log::error "$1"; }
success()          { log::success "$1"; }
die()              { log::die "$1"; }
assert_non_root()  { log::assert_non_root; }
check_command()    { util::has_command "$1"; }
pacman_install()   { pkg::install_pacman "$@"; }
enable_service()   { pkg::enable_service "$1"; }

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
                info "Replacing dir-symlink with real dir: $dir"
                rm -- "$dir"
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

    migrate_ancestor_symlinks "$dest"

    if [[ -L "$dest" && "$(readlink -f -- "$dest")" == "$src" ]]; then
        return 0
    fi

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        warn "Backing up existing file: $dest"
        mv -- "$dest" "$dest.backup.$(date +%s)"
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
            info "Pruning stale link: $link"
            rm -- "$link"
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
}

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

# Mirror every file under $REPO_ROOT/dotfiles into $HOME via leaf symlinks,
# prune stale in-repo links, and remove legacy bash init files. Idempotent.
configure_dotfiles() {
    local src_root="$REPO_ROOT/dotfiles"
    [[ -d "$src_root" ]] || die "dotfiles/ not found at $src_root"

    info "Linking dotfiles from $src_root into \$HOME"

    local file rel dest
    while IFS= read -r -d '' file; do
        rel="${file#"$src_root"/}"
        dest="$HOME/$rel"
        link_dotfile "$file" "$dest"
    done < <(find "$src_root" -type f -print0)

    info "Pruning stale symlinks"
    prune_stale_links_in "$HOME" 1
    local entry name target
    for entry in "$src_root"/* "$src_root"/.*; do
        name="$(basename "$entry")"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        [[ -d "$entry" ]] || continue
        target="$HOME/$name"
        [[ -d "$target" ]] || continue
        prune_stale_links_in "$target"
    done

    success "Dotfiles configured"

    info "Removing legacy bash init files"
    local f
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_logout"; do
        if [[ -L "$f" ]]; then
            info "  Skipping symlink: $f"
            continue
        fi
        [[ -e "$f" ]] || continue
        info "  Removing: $f"
        rm -f -- "$f"
    done
}
