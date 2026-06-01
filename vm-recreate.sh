#!/usr/bin/env bash
# vm-recreate.sh — wipe the VM disk and attach the ISO. For testing bootstrap.sh.
set -euo pipefail

readonly CONF="$HOME/vms/archlinux/archlinux-latest.conf"
readonly DISK="$HOME/vms/archlinux/archlinux-latest/disk.qcow2"

quickemu --vm "$CONF" --monitor-cmd system_powerdown 2> /dev/null || true
sleep 2

rm -f -- "$DISK"
sed -i 's|^# *iso=|iso=|' "$CONF"

exec quickemu --vm "$CONF"
