#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

STAGES=(check bootstrap install configure)

usage() {
    cat <<EOF
Usage: $(basename "$0") [--only STAGE[,STAGE...]] [--skip STAGE[,STAGE...]] [--dry-run] [-h|--help]

Stages (run in order):
  check       Pre-flight: Arch Linux, non-root, pacman/git, internet
  bootstrap   pacman -Syu, install base-devel + git, bootstrap yay
  install     Install every row in packages.csv; run per-row hooks
  configure   Leaf-symlink everything under dotfiles/ into \$HOME, prune
              stale symlinks that resolve into the repo, set zsh as default

By default all stages run, in order.

  --only      Comma-separated list of stages to run (others skipped).
  --skip      Comma-separated list of stages to skip.
              --skip wins on conflicts with --only.
  --dry-run   Print link / prune / migrate / chsh ops instead of executing.
  -h, --help  Show this message.
EOF
}

# ---------- stage: check ----------

stage_check() {
    info "Running pre-flight checks"

    [[ -f /etc/arch-release ]] || die "This script is intended for Arch Linux only."
    [[ "$EUID" -ne 0 ]] || die "Do not run this script as root. It will use sudo when needed."
    check_command pacman || die "pacman not found. Is this Arch Linux?"
    check_command git || die "git is required but not installed. Install it first: sudo pacman -S git"
    ping -c 1 -W 2 archlinux.org &>/dev/null || die "No internet connection detected."

    success "Pre-flight checks passed"
}

# ---------- stage: bootstrap ----------

stage_bootstrap() {
    info "Updating system"
    sudo pacman -Syu --noconfirm

    info "Installing AUR helper prerequisites"
    pacman_install base-devel git

    if check_command yay; then
        info "yay is already installed"
        return 0
    fi

    info "Bootstrapping yay AUR helper"
    (
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
    )
    success "yay installed"
}

# ---------- stage: install ----------

install_row() {
    local tag="$1" name="$2" desc="$3" i="$4" total="$5"

    unset SRC_DIR
    export PKG_NAME="$name" PKG_TAG="$tag" PKG_DESC="$desc"

    local key already=0
    case "$tag" in
        ""|A)
            key="$name"
            pacman -Qq "$name" &>/dev/null && already=1
            ;;
        G)
            key="$(basename "$name" .git)"
            export SRC_DIR="$HOME/.local/src/$key"
            [[ -d "$SRC_DIR" ]] && already=1
            ;;
        *)
            error "[$i/$total] unknown tag '$tag' for $name"
            return 1
            ;;
    esac

    local pre="$REPO_ROOT/hooks/$key.pre.sh"
    local post="$REPO_ROOT/hooks/$key.post.sh"

    if (( already )); then
        info "[$i/$total] $name: already installed"
    else
        info "[$i/$total] Installing $name: $desc"
    fi

    if [[ -f "$pre" ]]; then
        bash "$pre" || { error "pre-hook failed for $name"; return 1; }
    fi

    if (( ! already )); then
        case "$tag" in
            "")  sudo pacman -S --needed --noconfirm "$name" || return 1 ;;
            A)   yay -S --needed --noconfirm "$name" || return 1 ;;
            G)
                mkdir -p "$(dirname "$SRC_DIR")"
                git clone --depth 1 "$name" "$SRC_DIR" || return 1
                ;;
        esac
    fi

    if [[ -f "$post" ]]; then
        bash "$post" || { error "post-hook failed for $name"; return 1; }
    fi
}

stage_install() {
    local csv="$REPO_ROOT/packages.csv"
    [[ -f "$csv" ]] || die "packages.csv not found at $csv"

    mapfile -t rows < <(tail -n +2 "$csv" | grep -Ev '^\s*$')
    local total=${#rows[@]}
    (( total > 0 )) || die "no package rows found in $csv"

    info "Installing $total packages from packages.csv"

    local failed=()
    local i=0 row tag name desc
    for row in "${rows[@]}"; do
        i=$((i + 1))
        IFS=',' read -r tag name desc <<< "$row"
        if ! install_row "$tag" "$name" "$desc" "$i" "$total"; then
            failed+=("$name")
        fi
    done

    if (( ${#failed[@]} > 0 )); then
        error "Failed rows (${#failed[@]}/${total}):"
        local f
        for f in "${failed[@]}"; do
            printf "  - %s\n" "$f" >&2
        done
        return 1
    fi

    success "All $total packages installed"
}

# ---------- stage: configure ----------

stage_configure() {
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
    # Top-level dotfiles in $HOME (depth 1) — catches stale ~/.zshrc-style links.
    prune_stale_links_in "$HOME" 1
    # Each top-level entry in dotfiles/ that's a directory maps to a target
    # tree we own; walk it recursively for stale leaves.
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

    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "$SHELL" == "$zsh_path" ]]; then
        info "zsh is already the default shell"
    elif (( DRY_RUN )); then
        info "[dry-run] would change default shell to zsh ($zsh_path)"
    else
        info "Changing default shell to zsh"
        chsh -s "$zsh_path"
        success "Default shell changed to zsh"
    fi
}

# ---------- runner ----------

validate_stages() {
    local label="$1" list="$2"
    [[ -z "$list" ]] && return 0
    local parts part s found
    IFS=',' read -ra parts <<< "$list"
    for part in "${parts[@]}"; do
        found=0
        for s in "${STAGES[@]}"; do
            [[ "$part" == "$s" ]] && { found=1; break; }
        done
        (( found )) || die "$label: unknown stage '$part' (known: ${STAGES[*]})"
    done
}

main() {
    local only="" skip=""
    DRY_RUN=0
    while (( $# > 0 )); do
        case "$1" in
            --only)
                [[ $# -ge 2 ]] || die "--only requires an argument"
                only="$2"; shift 2 ;;
            --skip)
                [[ $# -ge 2 ]] || die "--skip requires an argument"
                skip="$2"; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) error "unknown option: $1"; usage >&2; exit 2 ;;
        esac
    done
    export DRY_RUN

    validate_stages "--only" "$only"
    validate_stages "--skip" "$skip"

    local -A only_set=() skip_set=()
    local parts part
    if [[ -n "$only" ]]; then
        IFS=',' read -ra parts <<< "$only"
        for part in "${parts[@]}"; do only_set[$part]=1; done
    fi
    if [[ -n "$skip" ]]; then
        IFS=',' read -ra parts <<< "$skip"
        for part in "${parts[@]}"; do skip_set[$part]=1; done
    fi

    info "Starting marc-os setup"

    local ran=0 s
    for s in "${STAGES[@]}"; do
        [[ -n "$only" && -z "${only_set[$s]:-}" ]] && continue
        [[ -n "${skip_set[$s]:-}" ]] && continue
        "stage_$s"
        ran=$((ran + 1))
    done

    if (( ran == 0 )); then
        warn "No stages ran. Check your --only/--skip filters."
    else
        success "Setup complete. Restart your shell or run: exec zsh -l"
    fi
}

main "$@"
