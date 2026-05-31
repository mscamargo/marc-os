#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CSV="$REPO_ROOT/packages.csv"
[[ -f "$CSV" ]] || die "packages.csv not found at $CSV"

mapfile -t ROWS < <(grep -Ev '^\s*(#|$)' "$CSV")
TOTAL=${#ROWS[@]}
(( TOTAL > 0 )) || die "no package rows found in $CSV"

FAILED=()

run_hook() {
    local hook="$1"
    local path="$REPO_ROOT/$hook"
    [[ -f "$path" ]] || { error "hook missing: $hook"; return 1; }
    bash "$path"
}

install_row() {
    local tag="$1" name="$2" desc="$3" pre="$4" post="$5" i="$6" total="$7"

    unset SRC_DIR
    export PKG_NAME="$name" PKG_TAG="$tag" PKG_DESC="$desc"

    case "$tag" in
        ""|A)
            if pacman -Qq "$name" &>/dev/null; then
                info "[$i/$total] $name: already installed, skipping"
                return 0
            fi
            ;;
        G)
            local repo_name
            repo_name="$(basename "$name" .git)"
            export SRC_DIR="$HOME/.local/src/$repo_name"
            if [[ -d "$SRC_DIR" ]]; then
                info "[$i/$total] $name: already cloned at $SRC_DIR, skipping"
                return 0
            fi
            ;;
        *)
            error "[$i/$total] unknown tag '$tag' for $name"
            return 1
            ;;
    esac

    info "[$i/$total] Installing $name: $desc"

    if [[ -n "$pre" ]]; then
        run_hook "$pre" || { error "pre-hook failed for $name"; return 1; }
    fi

    case "$tag" in
        "")  sudo pacman -S --needed --noconfirm "$name" || return 1 ;;
        A)   yay -S --needed --noconfirm "$name" || return 1 ;;
        G)
            mkdir -p "$(dirname "$SRC_DIR")"
            git clone --depth 1 "$name" "$SRC_DIR" || return 1
            ;;
    esac

    if [[ -n "$post" ]]; then
        run_hook "$post" || { error "post-hook failed for $name"; return 1; }
    fi
}

info "Installing $TOTAL packages from packages.csv"

i=0
for row in "${ROWS[@]}"; do
    i=$((i + 1))
    IFS=',' read -r tag name desc pre post <<< "$row"
    if ! install_row "$tag" "$name" "$desc" "$pre" "$post" "$i" "$TOTAL"; then
        FAILED+=("$name")
    fi
done

if (( ${#FAILED[@]} > 0 )); then
    error "Failed rows (${#FAILED[@]}/${TOTAL}):"
    for f in "${FAILED[@]}"; do
        printf "  - %s\n" "$f" >&2
    done
    exit 1
fi

success "All $TOTAL packages installed"
