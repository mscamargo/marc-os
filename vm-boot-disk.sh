#!/usr/bin/env bash
# vm-boot-disk.sh — detach the ISO and restart. Boots from the installed disk.
set -euo pipefail

readonly CONF="$HOME/vms/archlinux/archlinux-latest.conf"

quickemu --vm "$CONF" --monitor-cmd system_powerdown 2> /dev/null || true
sleep 2

sed -i 's|^iso=|# iso=|' "$CONF"

exec quickemu --vm "$CONF"
