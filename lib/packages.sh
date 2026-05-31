#!/usr/bin/env bash
# lib/packages.sh — pacman/AUR/git-source install + pacman.conf tuning.
[[ -n ${__LIB_PACKAGES_SOURCED:-} ]] && return 0
__LIB_PACKAGES_SOURCED=1

__LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/log.sh
source "$__LIB_DIR/log.sh"
# shellcheck source=SCRIPTDIR/util.sh
source "$__LIB_DIR/util.sh"
unset __LIB_DIR

readonly PKG_SRC_ROOT="$HOME/.local/src"

# pkg::install_pacman <name...> — pacman -S --needed --noconfirm.
pkg::install_pacman() {
    log::info "Installing: $*"
    sudo pacman -S --needed --noconfirm "$@"
}

# pkg::install_aur <name> — yay -S --needed --noconfirm.
pkg::install_aur() {
    yay -S --needed --noconfirm "$1"
}

# pkg::install_git_src <url> [src_root] — shallow-clone <url> into
# <src_root>/<basename-without-.git>. Default src_root=$PKG_SRC_ROOT.
pkg::install_git_src() {
    local url="$1"
    local src_root="${2:-$PKG_SRC_ROOT}"
    local key dest
    key="$(basename "$url" .git)"
    dest="$src_root/$key"
    mkdir -p -- "$(dirname "$dest")"
    git clone --depth 1 "$url" "$dest"
}

# pkg::is_installed_pacman <name> — 0 if pacman tracks <name>, else 1.
pkg::is_installed_pacman() {
    pacman -Qq "$1" &> /dev/null
}

# pkg::is_installed_git_src <key> [src_root] — 0 if <src_root>/<key> exists.
pkg::is_installed_git_src() {
    local key="$1"
    local src_root="${2:-$PKG_SRC_ROOT}"
    [[ -d "$src_root/$key" ]]
}

# pkg::enable_service <unit> — enable+start a systemd unit. Idempotent.
pkg::enable_service() {
    local unit="$1"
    if systemctl is-enabled --quiet "$unit" 2> /dev/null; then
        if systemctl is-active --quiet "$unit" 2> /dev/null; then
            log::info "$unit already enabled and active"
            return 0
        fi
        log::info "Starting: $unit"
        sudo systemctl start "$unit"
        return 0
    fi
    log::info "Enabling and starting: $unit"
    sudo systemctl enable --now "$unit"
}

# pkg::enable_pacman_option <conf> <opt> — flip "#Opt" → "Opt" in <conf>.
# No-op if already enabled. Warn if the pattern is absent.
pkg::enable_pacman_option() {
    local conf="$1" opt="$2"
    if grep -qE "^${opt}\b" "$conf"; then
        log::info "  $opt: already enabled"
    elif grep -qE "^#\s*${opt}\b" "$conf"; then
        sudo sed -i -E "s/^#\s*(${opt}\b)/\1/" "$conf"
        log::info "  Enabled: $opt"
    else
        log::warn "  $opt: pattern not found, skipping"
    fi
}

# pkg::tune_pacman_conf <conf> — enable Color/VerbosePkgLists/ParallelDownloads,
# inject ILoveCandy under [options], and uncomment [multilib] + body.
pkg::tune_pacman_conf() {
    local conf="$1"
    [[ -f "$conf" ]] || log::die "$conf not found"

    log::info "Tuning $conf"

    local opt
    for opt in Color VerbosePkgLists ParallelDownloads; do
        pkg::enable_pacman_option "$conf" "$opt"
    done

    if grep -qE "^ILoveCandy\b" "$conf"; then
        log::info "  ILoveCandy: already enabled"
    else
        sudo sed -i -E "/^\[options\]/a ILoveCandy" "$conf"
        log::info "  Enabled: ILoveCandy"
    fi

    if grep -qE "^\[multilib\]" "$conf"; then
        log::info "  [multilib]: already enabled"
    elif grep -qE "^#\s*\[multilib\]" "$conf"; then
        sudo sed -i -E "/^#\s*\[multilib\]/,/^$/{s/^#\s*//}" "$conf"
        log::info "  Enabled: [multilib]"
    else
        log::warn "  [multilib]: pattern not found, skipping"
    fi
}

# pkg::refresh_keyring — pacman -S --needed --noconfirm archlinux-keyring.
pkg::refresh_keyring() {
    log::info "Refreshing archlinux-keyring"
    sudo pacman -S --needed --noconfirm archlinux-keyring
}

# pkg::run_pre_hook <key> <hooks_dir> — bash-exec <hooks_dir>/<key>.pre.sh in
# a subshell if present. Returns the hook's exit code on failure.
pkg::run_pre_hook() {
    local hook="$2/$1.pre.sh"
    [[ -f "$hook" ]] || return 0
    if ! bash "$hook"; then
        log::error "pre-hook failed for $1"
        return 1
    fi
}

# pkg::run_post_hook <key> <hooks_dir> — bash-exec <hooks_dir>/<key>.post.sh
# in a subshell if present. Returns the hook's exit code on failure.
pkg::run_post_hook() {
    local hook="$2/$1.post.sh"
    [[ -f "$hook" ]] || return 0
    if ! bash "$hook"; then
        log::error "post-hook failed for $1"
        return 1
    fi
}

# pkg::bootstrap_aur_helper — clone + makepkg-install yay. No-op if installed.
pkg::bootstrap_aur_helper() {
    if util::has_command yay; then
        log::info "yay is already installed"
        return 0
    fi
    log::info "Bootstrapping yay AUR helper"
    (
        local tmp
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp" || exit
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit
        makepkg -si --noconfirm
    )
    log::success "yay installed"
}
