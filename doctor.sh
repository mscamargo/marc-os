#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"
# shellcheck source=lib/dotfiles.sh
source "$SCRIPT_DIR/lib/dotfiles.sh"

log::assert_non_root

readonly REPO_ROOT="$SCRIPT_DIR"
csv="$REPO_ROOT/packages.csv"
[[ -f "$csv" ]] || log::die "packages.csv not found at $csv"

log::info "Checking for drift"

declare -i missing_pkgs=0 wrong_links=0 missing_links=0 shadow=0 orphans=0

while IFS= read -r row; do
    IFS=',' read -r tag name _ <<< "$row"
    case "$tag" in
        "" | A)
            if ! pkg::is_installed_pacman "$name"; then
                log::warn "missing package: $name"
                missing_pkgs+=1
            fi
            ;;
        G)
            key="$(basename "$name" .git)"
            if ! pkg::is_installed_git_src "$key"; then
                log::warn "missing git source: $key ($name)"
                missing_pkgs+=1
            fi
            ;;
        *)
            log::warn "unknown tag '$tag' for $name"
            ;;
    esac
done < <(tail -n +2 "$csv" | grep -Ev '^\s*(#|$)')

src_root="$REPO_ROOT/dotfiles"
if [[ -d "$src_root" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$src_root"/}"
        dest="$HOME/$rel"
        if [[ -L "$dest" ]]; then
            target="$(dot::readlink_target "$dest")"
            if [[ "$target" != "$file" ]]; then
                log::warn "wrong link target: $dest -> ${target:-<broken>} (expected $file)"
                wrong_links+=1
            fi
        elif [[ -e "$dest" ]]; then
            log::warn "real file shadows link: $dest"
            shadow+=1
        else
            log::warn "missing link: $dest"
            missing_links+=1
        fi
    done < <(find "$src_root" -type f -print0)

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
        if ((idx == 0)); then
            find_args+=("${depth_args[@]}")
        fi
        find_args+=(-type l -print0)
        while IFS= read -r -d '' link; do
            target="$(dot::readlink_target "$link")"
            if [[ -n "$target" && "$target" == "$REPO_ROOT"* && ! -e "$target" ]]; then
                log::warn "orphan link: $link -> $target"
                orphans+=1
            fi
        done < <(find "${find_args[@]}" 2> /dev/null)
    done
else
    log::warn "dotfiles/ not found at $src_root"
fi

total=$((missing_pkgs + wrong_links + missing_links + shadow + orphans))
if ((total == 0)); then
    log::success "No drift detected"
    exit 0
fi

log::error "Drift detected ($total finding(s)):"
((missing_pkgs > 0))  && printf "  missing packages / sources: %d\n" "$missing_pkgs"  >&2
((wrong_links > 0))   && printf "  wrong link targets:         %d\n" "$wrong_links"   >&2
((missing_links > 0)) && printf "  missing links:              %d\n" "$missing_links" >&2
((shadow > 0))        && printf "  real files shadowing links: %d\n" "$shadow"        >&2
((orphans > 0))       && printf "  orphan in-repo links:       %d\n" "$orphans"       >&2
exit 1
