#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

assert_non_root

csv="$REPO_ROOT/packages.csv"
[[ -f "$csv" ]] || die "packages.csv not found at $csv"

info "Checking for drift"

declare -i missing_pkgs=0 wrong_links=0 missing_links=0 shadow=0 orphans=0

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
done < <(tail -n +2 "$csv" | grep -Ev '^\s*(#|$)')

src_root="$REPO_ROOT/dotfiles"
if [[ -d "$src_root" ]]; then
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
    declare -a search_roots=("$HOME")
    declare -a depth_args=(-maxdepth 1)
    for entry in "$src_root"/* "$src_root"/.*; do
        name="$(basename "$entry")"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        [[ -d "$entry" ]] || continue
        [[ -d "$HOME/$name" ]] && search_roots+=("$HOME/$name")
    done

    for idx in "${!search_roots[@]}"; do
        root="${search_roots[$idx]}"
        declare -a find_args=("$root")
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

total=$((missing_pkgs + wrong_links + missing_links + shadow + orphans))
if (( total == 0 )); then
    success "No drift detected"
    exit 0
fi

error "Drift detected ($total finding(s)):"
(( missing_pkgs   > 0 )) && printf "  missing packages / sources: %d\n" "$missing_pkgs"   >&2
(( wrong_links    > 0 )) && printf "  wrong link targets:         %d\n" "$wrong_links"    >&2
(( missing_links  > 0 )) && printf "  missing links:              %d\n" "$missing_links"  >&2
(( shadow         > 0 )) && printf "  real files shadowing links: %d\n" "$shadow"         >&2
(( orphans        > 0 )) && printf "  orphan in-repo links:       %d\n" "$orphans"        >&2
exit 1
