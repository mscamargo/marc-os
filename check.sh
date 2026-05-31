#!/usr/bin/env bash
# Run shellcheck across every .sh file in the repo.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

check_command() { command -v "$1" &>/dev/null; }
check_command shellcheck || {
    echo "shellcheck not found. Install: sudo pacman -S shellcheck" >&2
    exit 1
}

mapfile -t files < <(find . -type f -name '*.sh' -not -path './.git/*')
(( ${#files[@]} > 0 )) || { echo "no .sh files found"; exit 0; }

shellcheck --shell=bash --external-sources "${files[@]}"
