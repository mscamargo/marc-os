#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=lib/sudo.sh
source "$SCRIPT_DIR/lib/sudo.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [-h|--help]

End-to-end new-machine setup, run in order:
  check       Pre-flight: Arch Linux, non-root, pacman, internet
  bootstrap   Patch /etc/pacman.conf (Color, ILoveCandy, ParallelDownloads,
              VerbosePkgLists, multilib), refresh archlinux-keyring,
              pacman -Syu, install base-devel + git, bootstrap yay
  install     Install every row in data/{pacman,aur,git_src}.list; run hooks
  shell       chsh -s zsh

For a read-only drift report, use ./doctor.sh.

Each run is logged to \$XDG_STATE_HOME/marc-os/install-<timestamp>.log
(defaults to ~/.local/state/marc-os/).
EOF
}

# ---------- check ----------

check() {
    log::info "Running pre-flight checks"

    [[ -f /etc/arch-release ]] || log::die "This script is intended for Arch Linux only."
    log::assert_non_root
    util::has_command pacman || log::die "pacman not found. Is this Arch Linux?"
    ping -c 1 -W 2 archlinux.org &> /dev/null || log::die "No internet connection detected."

    log::success "Pre-flight checks passed"
}

# ---------- bootstrap ----------

bootstrap() {
    pkg::tune_pacman_conf /etc/pacman.conf
    pkg::refresh_keyring

    log::info "Updating system"
    sudo pacman -Syu --noconfirm

    log::info "Installing AUR helper prerequisites"
    pkg::install_pacman base-devel git

    pkg::bootstrap_aur_helper
}

# ---------- install ----------

install_packages() {
    local hooks_dir="$SCRIPT_DIR/hooks"
    local data="$SCRIPT_DIR/data"

    sudo::keepalive_start

    local rc=0
    pkg::install_list "$data/pacman.list" pacman "$hooks_dir" || rc=1
    pkg::install_list "$data/aur.list" aur "$hooks_dir" || rc=1
    pkg::install_list "$data/git_src.list" git "$hooks_dir" || rc=1

    sudo::keepalive_stop

    return "$rc"
}

# ---------- shell ----------

setup_shell() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "$SHELL" == "$zsh_path" ]]; then
        log::info "zsh is already the default shell"
        return 0
    fi
    log::info "Changing default shell to zsh"
    chsh -s "$zsh_path"
    log::success "Default shell changed to zsh"
}

# ---------- main ----------

main() {
    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            *)
                log::error "unknown option: $1"
                usage >&2
                exit 2
                ;;
        esac
    done

    local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/marc-os"
    mkdir -p "$log_dir"
    local log_file
    log_file="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$log_file") 2> >(tee -a "$log_file" >&2)

    log::info "Starting marc-os setup"
    log::info "Logging to $log_file"

    check
    bootstrap
    install_packages
    setup_shell

    log::success "Setup complete. Restart your shell or run: exec zsh -l"
}

main "$@"
