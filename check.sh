#!/usr/bin/env bash
# Lint and format-check every .sh file in the repo.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

readonly SHFMT_FLAGS=(-i 4 -ci -sr -bn)

has_command() { command -v "$1" &> /dev/null; }

has_command shellcheck || {
    echo "shellcheck not found. Install: sudo pacman -S shellcheck" >&2
    exit 1
}
has_command shfmt || {
    echo "shfmt not found. Install: sudo pacman -S shfmt" >&2
    exit 1
}

mapfile -t files < <(find . -type f -name '*.sh' -not -path './.git/*')
((${#files[@]} > 0)) || {
    echo "no .sh files found"
    exit 0
}

shellcheck --shell=bash --external-sources "${files[@]}"
shfmt -d "${SHFMT_FLAGS[@]}" "${files[@]}"
