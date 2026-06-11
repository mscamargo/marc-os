#!/usr/bin/env bash
set -euo pipefail
__HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/../lib/packages.sh
source "$__HOOK_DIR/../lib/packages.sh"

# NVIDIA PRIME render offload on a hybrid (Optimus) laptop, using the
# open kernel modules (nvidia-open; Turing+). Intel Iris Xe stays the
# primary/display GPU; the NVIDIA dGPU powers up on demand. Run GPU-heavy
# apps with `prime-run <command>`.
# Refs: Arch wiki "NVIDIA Optimus" and "PRIME".

# 1. Blacklist nouveau and enable the NVIDIA DRM kernel mode setting that
#    render offload requires.
modprobe_conf=/etc/modprobe.d/marc-os-nvidia.conf
read -r -d '' desired_modprobe << 'EOF' || true
# marc-os: NVIDIA PRIME render offload — Intel primary, NVIDIA on demand
blacklist nouveau
options nvidia_drm modeset=1 fbdev=1
EOF

if [[ "$(cat "$modprobe_conf" 2> /dev/null || true)" == "$desired_modprobe" ]]; then
    log::info "$modprobe_conf already up to date"
else
    log::info "Writing $modprobe_conf (blacklist nouveau, enable NVIDIA DRM KMS)"
    printf '%s\n' "$desired_modprobe" | sudo tee "$modprobe_conf" > /dev/null
fi

# 2. Load the NVIDIA modules from the initramfs so KMS is active early.
mkinitcpio_conf=/etc/mkinitcpio.conf
nvidia_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
if grep -qE '^MODULES=\(.*\bnvidia\b' "$mkinitcpio_conf"; then
    log::info "mkinitcpio MODULES already include nvidia"
else
    log::info "Adding NVIDIA modules to mkinitcpio MODULES and regenerating initramfs"
    sudo sed -i -E "s/^MODULES=\((.*)\)/MODULES=(\1 $nvidia_modules)/" "$mkinitcpio_conf"
    # Drop a leading space left behind when the array started empty.
    sudo sed -i -E 's/^MODULES=\( +/MODULES=(/' "$mkinitcpio_conf"
    sudo mkinitcpio -P
fi

# 3. Preserve VRAM across suspend/hibernate (recommended for laptops).
#    These are triggered by the sleep targets; only enable, never start.
for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
    if systemctl is-enabled --quiet "$svc" 2> /dev/null; then
        log::info "$svc already enabled"
    else
        log::info "Enabling $svc"
        sudo systemctl enable "$svc"
    fi
done

log::warn "NVIDIA driver switch takes effect after a reboot. Use 'prime-run <app>' to run on the dGPU."
