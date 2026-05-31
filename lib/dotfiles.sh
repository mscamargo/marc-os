#!/usr/bin/env bash
# lib/dotfiles.sh — leaf-symlink dotfiles repo into $HOME, prune stale links.
[[ -n ${__LIB_DOTFILES_SOURCED:-} ]] && return 0
__LIB_DOTFILES_SOURCED=1

__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/log.sh
source "$__LIB_DIR/log.sh"
unset __LIB_DIR

# dot::readlink_target <path> — print canonical target of a symlink, or empty
# string on failure. Never errors.
dot::readlink_target() {
    readlink -f -- "$1" 2> /dev/null || true
}

# dot::migrate_ancestors <dest> <repo_root> — replace any ancestor of <dest>
# that is a symlink into <repo_root> with a real directory. Stops at $HOME.
dot::migrate_ancestors() {
    local dest="$1" repo_root="$2"
    local dir target
    dir="$(dirname "$dest")"
    while [[ "$dir" == "$HOME"/* ]]; do
        if [[ -L "$dir" ]]; then
            target="$(dot::readlink_target "$dir")"
            if [[ -n "$target" && "$target" == "$repo_root"* ]]; then
                log::info "Replacing dir-symlink with real dir: $dir"
                rm -- "$dir"
            fi
        fi
        dir="$(dirname "$dir")"
    done
}

# dot::link <src> <dest> <repo_root> — symlink <src> at <dest>. Auto-migrates
# dir-symlink ancestors that point into <repo_root>. Backs up real files in
# the way as <dest>.backup.<ts>.
dot::link() {
    local src="$1" dest="$2" repo_root="$3"

    dot::migrate_ancestors "$dest" "$repo_root"

    if [[ -L "$dest" && "$(dot::readlink_target "$dest")" == "$src" ]]; then
        return 0
    fi

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        log::warn "Backing up existing file: $dest"
        mv -- "$dest" "$dest.backup.$(date +%s)"
    fi

    mkdir -p -- "$(dirname "$dest")"
    ln -sfn -- "$src" "$dest"
    log::info "Linked: $dest -> $src"
}

# dot::prune_stale_in <dir> <repo_root> [maxdepth] — remove broken symlinks
# within <dir> whose canonical target lives inside <repo_root>. Optional
# <maxdepth> caps the find walk (used for the $HOME pass).
dot::prune_stale_in() {
    local dir="$1" repo_root="$2"
    local -a find_args=("$dir")
    if [[ -n "${3:-}" ]]; then
        find_args+=(-maxdepth "$3")
    fi
    find_args+=(-type l -print0)

    local link target
    while IFS= read -r -d '' link; do
        target="$(dot::readlink_target "$link")"
        if [[ -n "$target" && "$target" == "$repo_root"* && ! -e "$target" ]]; then
            log::info "Pruning stale link: $link"
            rm -- "$link"
        fi
    done < <(find "${find_args[@]}" 2> /dev/null)
}

# dot::configure <src_root> <home> — mirror every file under <src_root> into
# <home> via leaf symlinks, prune stale in-repo links, and remove legacy bash
# init files. Idempotent. <src_root> must live one level under the repo root.
dot::configure() {
    local src_root="$1" home="$2"
    [[ -d "$src_root" ]] || log::die "dotfiles/ not found at $src_root"

    local repo_root
    repo_root="$(dirname "$src_root")"

    log::info "Linking dotfiles from $src_root into $home"

    local file rel dest
    while IFS= read -r -d '' file; do
        rel="${file#"$src_root"/}"
        dest="$home/$rel"
        dot::link "$file" "$dest" "$repo_root"
    done < <(find "$src_root" -type f -print0)

    log::info "Pruning stale symlinks"
    dot::prune_stale_in "$home" "$repo_root" 1
    local entry name target
    for entry in "$src_root"/* "$src_root"/.*; do
        name="$(basename "$entry")"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        [[ -d "$entry" ]] || continue
        target="$home/$name"
        [[ -d "$target" ]] || continue
        dot::prune_stale_in "$target" "$repo_root"
    done

    log::success "Dotfiles configured"

    log::info "Removing legacy bash init files"
    local f
    for f in "$home/.bashrc" "$home/.bash_profile" "$home/.bash_logout"; do
        if [[ -L "$f" ]]; then
            log::info "  Skipping symlink: $f"
            continue
        fi
        [[ -e "$f" ]] || continue
        log::info "  Removing: $f"
        rm -f -- "$f"
    done
}
