#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

STAGES=(check bootstrap install configure doctor)
DEFAULT_STAGES=(check bootstrap install configure)

usage() {
    cat <<EOF
Usage: $(basename "$0") [--only STAGE[,STAGE...]] [--skip STAGE[,STAGE...]] [--clean-bash] [-h|--help]

Stages:
  check       Pre-flight: Arch Linux, non-root, pacman/git, internet
  bootstrap   Patch /etc/pacman.conf (Color, ILoveCandy, ParallelDownloads,
              VerbosePkgLists, multilib), refresh archlinux-keyring,
              pacman -Syu, install base-devel + git, bootstrap yay
  install     Install every row in packages.csv; run per-row hooks
  configure   Leaf-symlink everything under dotfiles/ into \$HOME, prune
              stale symlinks that resolve into the repo, set zsh as default
  doctor      Read-only drift report: missing packages, dotfiles whose
              link is wrong/missing/shadowed, orphan in-repo links.
              Opt-in: run with --only doctor. Exits non-zero on drift.

Default run: check, bootstrap, install, configure (doctor is opt-in).

  --only        Comma-separated list of stages to run.
  --skip        Comma-separated list of stages to skip (wins over --only).
  --clean-bash  In configure, remove ~/.bashrc, ~/.bash_profile, ~/.bash_logout
                so they don't shadow the zsh init files. Destructive.
  -h, --help    Show this message.

Each run is logged to \$XDG_STATE_HOME/marc-os/install-<timestamp>.log
(defaults to ~/.local/state/marc-os/).
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

tune_pacman_conf() {
    local conf=/etc/pacman.conf
    [[ -f "$conf" ]] || die "$conf not found"

    info "Tuning $conf"

    local opt
    for opt in Color VerbosePkgLists ParallelDownloads; do
        if grep -qE "^${opt}\b" "$conf"; then
            info "  $opt: already enabled"
        elif grep -qE "^#\s*${opt}\b" "$conf"; then
            sudo sed -i -E "s/^#\s*(${opt}\b)/\1/" "$conf"
            info "  Enabled: $opt"
        else
            warn "  $opt: pattern not found, skipping"
        fi
    done

    if grep -qE "^ILoveCandy\b" "$conf"; then
        info "  ILoveCandy: already enabled"
    else
        sudo sed -i -E "/^\[options\]/a ILoveCandy" "$conf"
        info "  Enabled: ILoveCandy"
    fi

    if grep -qE "^\[multilib\]" "$conf"; then
        info "  [multilib]: already enabled"
    elif grep -qE "^#\s*\[multilib\]" "$conf"; then
        sudo sed -i -E "/^#\s*\[multilib\]/,/^$/{s/^#\s*//}" "$conf"
        info "  Enabled: [multilib]"
    else
        warn "  [multilib]: pattern not found, skipping"
    fi
}

refresh_keyring() {
    info "Refreshing archlinux-keyring"
    sudo pacman -S --needed --noconfirm archlinux-keyring
}

stage_bootstrap() {
    tune_pacman_conf
    refresh_keyring

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

# Strip surrounding double quotes from $1 (LARBS-style desc).
unquote() {
    local s="$1"
    s="${s#\"}"
    s="${s%\"}"
    printf '%s' "$s"
}

# Parse "tag,name,desc" with optional "..."-wrapped desc that may contain commas.
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

stop_sudo_keepalive() {
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] || return 0
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    unset SUDO_KEEPALIVE_PID
}

start_sudo_keepalive() {
    sudo -v || die "sudo authentication failed"
    ( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap stop_sudo_keepalive EXIT
}

stage_install() {
    local csv="$REPO_ROOT/packages.csv"
    [[ -f "$csv" ]] || die "packages.csv not found at $csv"

    mapfile -t rows < <(tail -n +2 "$csv" | grep -Ev '^\s*$')
    local total=${#rows[@]}
    (( total > 0 )) || die "no package rows found in $csv"

    info "Installing $total packages from packages.csv"

    start_sudo_keepalive

    local failed=()
    local i=0 row
    for row in "${rows[@]}"; do
        i=$((i + 1))
        parse_row "$row"
        if ! install_row "$PARSED_TAG" "$PARSED_NAME" "$PARSED_DESC" "$i" "$total"; then
            failed+=("$PARSED_NAME")
        fi
    done

    stop_sudo_keepalive

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
    else
        info "Changing default shell to zsh"
        chsh -s "$zsh_path"
        success "Default shell changed to zsh"
    fi

    if (( CLEAN_BASH )); then
        info "Removing legacy bash init files (--clean-bash)"
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
    fi
}

# ---------- stage: doctor ----------

stage_doctor() {
    local csv="$REPO_ROOT/packages.csv"
    [[ -f "$csv" ]] || die "packages.csv not found at $csv"

    info "Checking for drift"

    local -i missing_pkgs=0 wrong_links=0 missing_links=0 shadow=0 orphans=0
    local row key

    while IFS= read -r row; do
        parse_row "$row"
        case "$PARSED_TAG" in
            ""|A)
                if ! pacman -Qq "$PARSED_NAME" &>/dev/null; then
                    warn "missing package: $PARSED_NAME"
                    missing_pkgs+=1
                fi
                ;;
            G)
                key="$(basename "$PARSED_NAME" .git)"
                if [[ ! -d "$HOME/.local/src/$key" ]]; then
                    warn "missing git source: $key ($PARSED_NAME)"
                    missing_pkgs+=1
                fi
                ;;
            *)
                warn "unknown tag '$PARSED_TAG' for $PARSED_NAME"
                ;;
        esac
    done < <(tail -n +2 "$csv" | grep -Ev '^\s*$')

    local src_root="$REPO_ROOT/dotfiles"
    if [[ -d "$src_root" ]]; then
        local file rel dest target
        while IFS= read -r -d '' file; do
            rel="${file#"$src_root"/}"
            dest="$HOME/$rel"
            if [[ -L "$dest" ]]; then
                target="$(readlink -f -- "$dest" 2>/dev/null || true)"
                if [[ "$target" != "$file" ]]; then
                    warn "wrong link target: $dest -> ${target:-<broken>} (expected $file)"
                    wrong_links+=1
                fi
            elif [[ -e "$dest" ]]; then
                warn "real file shadows link: $dest"
                shadow+=1
            else
                warn "missing link: $dest"
                missing_links+=1
            fi
        done < <(find "$src_root" -type f -print0)

        # Orphan in-repo links: symlinks anywhere in tracked subtrees (and at
        # $HOME depth 1) whose target resolves into the repo but is gone.
        local link
        local -a search_roots=("$HOME")
        local -a depth_args=(-maxdepth 1)
        local entry name
        for entry in "$src_root"/* "$src_root"/.*; do
            name="$(basename "$entry")"
            [[ "$name" == "." || "$name" == ".." ]] && continue
            [[ -d "$entry" ]] || continue
            [[ -d "$HOME/$name" ]] && search_roots+=("$HOME/$name")
        done

        local idx root
        for idx in "${!search_roots[@]}"; do
            root="${search_roots[$idx]}"
            local -a find_args=("$root")
            if (( idx == 0 )); then
                find_args+=("${depth_args[@]}")
            fi
            find_args+=(-type l -print0)
            while IFS= read -r -d '' link; do
                target="$(readlink -f -- "$link" 2>/dev/null || true)"
                if [[ -n "$target" && "$target" == "$REPO_ROOT"* && ! -e "$target" ]]; then
                    warn "orphan link: $link -> $target"
                    orphans+=1
                fi
            done < <(find "${find_args[@]}" 2>/dev/null)
        done
    else
        warn "dotfiles/ not found at $src_root"
    fi

    local total=$((missing_pkgs + wrong_links + missing_links + shadow + orphans))
    if (( total == 0 )); then
        success "No drift detected"
        return 0
    fi

    error "Drift detected ($total finding(s)):"
    (( missing_pkgs   > 0 )) && printf "  missing packages / sources: %d\n" "$missing_pkgs"   >&2
    (( wrong_links    > 0 )) && printf "  wrong link targets:         %d\n" "$wrong_links"    >&2
    (( missing_links  > 0 )) && printf "  missing links:              %d\n" "$missing_links"  >&2
    (( shadow         > 0 )) && printf "  real files shadowing links: %d\n" "$shadow"         >&2
    (( orphans        > 0 )) && printf "  orphan in-repo links:       %d\n" "$orphans"        >&2
    return 1
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
    CLEAN_BASH=0
    while (( $# > 0 )); do
        case "$1" in
            --only)
                [[ $# -ge 2 ]] || die "--only requires an argument"
                only="$2"; shift 2 ;;
            --skip)
                [[ $# -ge 2 ]] || die "--skip requires an argument"
                skip="$2"; shift 2 ;;
            --clean-bash) CLEAN_BASH=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) error "unknown option: $1"; usage >&2; exit 2 ;;
        esac
    done
    export CLEAN_BASH

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

    local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/marc-os"
    mkdir -p "$log_dir"
    local log_file
    log_file="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$log_file") 2> >(tee -a "$log_file" >&2)

    info "Starting marc-os setup"
    info "Logging to $log_file"

    local -a planned=()
    local s
    if [[ -n "$only" ]]; then
        for s in "${STAGES[@]}"; do
            [[ -n "${only_set[$s]:-}" ]] && planned+=("$s")
        done
    else
        planned=("${DEFAULT_STAGES[@]}")
    fi

    local ran=0
    for s in "${planned[@]}"; do
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
