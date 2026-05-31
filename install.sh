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
# shellcheck source=lib/dotfiles.sh
source "$SCRIPT_DIR/lib/dotfiles.sh"

usage() {
    cat << EOF
Usage: $(basename "$0") [-h|--help]

End-to-end new-machine setup, run in order:
  check       Pre-flight: Arch Linux, non-root, pacman/git, internet
  bootstrap   Patch /etc/pacman.conf (Color, ILoveCandy, ParallelDownloads,
              VerbosePkgLists, multilib), refresh archlinux-keyring,
              pacman -Syu, install base-devel + git, bootstrap yay
  install     Install every row in packages.csv; run per-row hooks
  shell       chsh -s zsh
  configure   Leaf-symlink dotfiles/ into \$HOME, prune stale links,
              remove legacy ~/.bash{rc,_profile,_logout}

For re-linking dotfiles only, use ./configure.sh.
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
    util::has_command git || log::die "git is required but not installed. Install it first: sudo pacman -S git"
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

install_row() {
    local tag="$1" name="$2" desc="$3" i="$4" total="$5"

    unset SRC_DIR
    export PKG_NAME="$name" PKG_TAG="$tag" PKG_DESC="$desc"

    local key already=0
    case "$tag" in
        "" | A)
            key="$name"
            pkg::is_installed_pacman "$name" && already=1
            ;;
        G)
            key="$(basename "$name" .git)"
            export SRC_DIR="$PKG_SRC_ROOT/$key"
            pkg::is_installed_git_src "$key" && already=1
            ;;
        *)
            log::error "[$i/$total] unknown tag '$tag' for $name"
            return 1
            ;;
    esac

    if ((already)); then
        log::info "[$i/$total] $name: already installed"
    else
        log::info "[$i/$total] Installing $name: $desc"
    fi

    local hooks_dir="$SCRIPT_DIR/hooks"
    pkg::run_pre_hook "$key" "$hooks_dir" || return 1

    if ((!already)); then
        case "$tag" in
            "") pkg::install_pacman "$name" || return 1 ;;
            A) pkg::install_aur "$name" || return 1 ;;
            G) pkg::install_git_src "$name" "$PKG_SRC_ROOT" || return 1 ;;
        esac
    fi

    pkg::run_post_hook "$key" "$hooks_dir" || return 1
}

install_packages() {
    local csv="$SCRIPT_DIR/packages.csv"
    [[ -f "$csv" ]] || log::die "packages.csv not found at $csv"

    mapfile -t rows < <(tail -n +2 "$csv" | grep -Ev '^\s*(#|$)')
    local total=${#rows[@]}
    ((total > 0)) || log::die "no package rows found in $csv"

    log::info "Installing $total packages from packages.csv"

    sudo::keepalive_start

    local failed=() i=0 row tag name desc
    for row in "${rows[@]}"; do
        i=$((i + 1))
        IFS=',' read -r tag name desc <<< "$row"
        if ! install_row "$tag" "$name" "$desc" "$i" "$total"; then
            failed+=("$name")
        fi
    done

    sudo::keepalive_stop

    if ((${#failed[@]} > 0)); then
        log::error "Failed rows (${#failed[@]}/${total}):"
        local f
        for f in "${failed[@]}"; do
            printf "  - %s\n" "$f" >&2
        done
        return 1
    fi

    log::success "All $total packages installed"
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
    dot::configure "$SCRIPT_DIR/dotfiles" "$HOME"

    log::success "Setup complete. Restart your shell or run: exec zsh -l"
}

main "$@"
