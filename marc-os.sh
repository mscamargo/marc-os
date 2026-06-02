#!/usr/bin/env bash
# marc-os.sh — curl-bash entry point fetched on the Arch ISO.
# Installs git, clones marc-os to /root/marc-os, execs bootstrap.sh.
#
#   curl -L https://mscamargo.github.io/marc-os/marc-os.sh | bash
set -euo pipefail

readonly REPO_URL="https://github.com/mscamargo/marc-os.git"
readonly DEST="/root/marc-os"

[[ $EUID -eq 0 ]] || {
    echo "marc-os.sh: must run as root on the Arch ISO" >&2
    exit 1
}

pacman -Sy --noconfirm --needed git

[[ -d $DEST ]] && rm -rf -- "$DEST"
git clone --depth 1 "$REPO_URL" "$DEST"

exec "$DEST/bootstrap.sh"
