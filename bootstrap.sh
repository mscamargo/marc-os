#!/usr/bin/env bash
# bootstrap.sh — bare-metal Arch installer, replaces archinstall.
# Runs as root on the Arch ISO. Wipes the target disk and produces a
# bootable system with a marc-os clone in ~$USERNAME/Work/marc-os.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/util.sh
source "$SCRIPT_DIR/lib/util.sh"

# ---------- constants ----------

readonly USERNAME="mscamargo"
readonly USER_SHELL="/bin/bash"
readonly LOCALE="en_US.UTF-8"
readonly EXTRA_LOCALES=("pt_BR.UTF-8")
readonly TIMEZONE="America/Sao_Paulo"
readonly KEYMAP="us"
readonly REPO_URL="https://github.com/mscamargo/marc-os.git"
readonly REPO_DEST_REL="Work/marc-os"
readonly ESP_SIZE="1G"
readonly SWAP_SIZE="8G"
readonly PACSTRAP_PKGS=(
    base linux linux-firmware sudo networkmanager git neovim openssh
)

# ---------- usage ----------

usage() {
    cat << EOF
Usage: $(basename "$0") [-h|--help]

Bare-metal Arch installer (replaces archinstall). Run as root on the Arch ISO.

Flow:
  1. Prompt for hostname, target disk, CPU microcode (with detected defaults).
  2. Confirm by retyping the full disk path — then wipe and partition.
  3. Format ESP as FAT32 and root as ext4, mount under /mnt, create 8G swapfile.
  4. Refresh mirrors (reflector, Brazil+US, https, latest 20 by rate) and enable
     ParallelDownloads in /etc/pacman.conf so pacstrap runs in parallel.
  5. pacstrap base + kernel + ucode + sudo + networkmanager + git + neovim + openssh.
     Re-enable ParallelDownloads in /mnt/etc/pacman.conf for the installed system.
  6. arch-chroot: timezone, locale (en_US + pt_BR), keymap, hostname, initramfs,
     systemd-boot, NetworkManager enabled, user (password-prompted wheel sudo,
     root locked), marc-os cloned to ~$USERNAME/$REPO_DEST_REL.
  7. Print handoff. Reboot, log in, then run ./install.sh by hand.

Re-runs wipe from scratch. The EXIT trap unmounts /mnt on any exit.
EOF
}

# ---------- preflight ----------

preflight() {
    log::info "Running pre-flight checks"

    [[ $EUID -eq 0 ]] || log::die "bootstrap.sh must run as root on the Arch ISO."
    [[ -f /etc/arch-release ]] || log::die "Not the Arch ISO (no /etc/arch-release)."
    [[ -d /sys/firmware/efi ]] || log::die "UEFI boot required; legacy BIOS unsupported."

    local cmd
    for cmd in pacstrap arch-chroot sgdisk wipefs genfstab blkid \
        mkfs.ext4 mkfs.fat mkswap partprobe udevadm lsblk reflector; do
        util::has_command "$cmd" || log::die "$cmd not found on the live ISO."
    done

    ping -c 1 -W 2 archlinux.org &> /dev/null || log::die "No internet connection."

    log::success "Pre-flight checks passed"
}

# ---------- helpers ----------

_prompt() {
    local question="$1" default="${2:-}" answer
    if [[ -n $default ]]; then
        read -r -p "$question [$default]: " answer
        printf '%s\n' "${answer:-$default}"
    else
        read -r -p "$question: " answer
        printf '%s\n' "$answer"
    fi
}

_detect_disk() {
    lsblk -ndb -o NAME,SIZE,TYPE,TRAN 2> /dev/null \
        | awk '$3 == "disk" && $4 != "usb" { print $2, "/dev/"$1 }' \
        | sort -rn \
        | head -1 \
        | awk '{ print $2 }'
}

_detect_ucode() {
    local vendor
    vendor="$(awk -F: '/^vendor_id/ { gsub(/ /, "", $2); print $2; exit }' /proc/cpuinfo)"
    case "$vendor" in
        GenuineIntel) printf 'intel-ucode\n' ;;
        AuthenticAMD) printf 'amd-ucode\n' ;;
        *) printf '\n' ;;
    esac
}

# _partition_path <disk> <num> — append partition number with the right separator.
# /dev/nvme0n1 → /dev/nvme0n1p1, /dev/sda → /dev/sda1.
_partition_path() {
    local disk="$1" num="$2"
    if [[ $disk =~ [0-9]$ ]]; then
        printf '%sp%s\n' "$disk" "$num"
    else
        printf '%s%s\n' "$disk" "$num"
    fi
}

_disk_info_line() {
    local disk="$1" model size serial
    model="$(lsblk -dn -o MODEL "$disk" 2> /dev/null | sed 's/^ *//;s/ *$//')"
    size="$(lsblk -dn -o SIZE "$disk" 2> /dev/null)"
    serial="$(lsblk -dn -o SERIAL "$disk" 2> /dev/null | sed 's/^ *//;s/ *$//')"
    printf '%s (%s, %s, serial %s)' \
        "$disk" "${model:-unknown}" "${size:-?}" "${serial:-?}"
}

_confirm_wipe() {
    local disk="$1" typed
    cat << EOF

About to WIPE this disk — ALL DATA WILL BE LOST:

  $(_disk_info_line "$disk")

Type the full device path ($disk) to confirm:
EOF
    read -r typed
    [[ $typed == "$disk" ]] || log::die "Confirmation mismatch. Aborting."
}

# ---------- stages ----------

refresh_mirrors() {
    log::info "Refreshing mirrors via reflector (Brazil, United States)"
    reflector \
        --country Brazil,'United States' \
        --age 12 \
        --protocol https \
        --latest 20 \
        --sort rate \
        --save /etc/pacman.d/mirrorlist
}

enable_parallel_downloads() {
    local conf="$1"
    log::info "Enabling ParallelDownloads in $conf"
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' "$conf"
}

partition() {
    local disk="$1"
    log::info "Wiping $disk"
    sgdisk --zap-all "$disk" > /dev/null
    wipefs -af "$disk" > /dev/null

    log::info "Creating GPT partitions (1: $ESP_SIZE ESP, 2: rest root)"
    sgdisk \
        -n "1:0:+$ESP_SIZE" -t 1:ef00 -c 1:ESP \
        -n "2:0:0" -t 2:8300 -c 2:root \
        "$disk" > /dev/null

    partprobe "$disk"
    udevadm settle
}

format_and_mount() {
    local disk="$1" esp root
    esp="$(_partition_path "$disk" 1)"
    root="$(_partition_path "$disk" 2)"

    log::info "Formatting $esp as FAT32"
    mkfs.fat -F32 -n ESP "$esp" > /dev/null

    log::info "Formatting $root as ext4"
    mkfs.ext4 -F -L root "$root" > /dev/null

    log::info "Mounting $root at /mnt"
    mount "$root" /mnt
    mkdir -p /mnt/boot
    mount "$esp" /mnt/boot
}

pacstrap_base() {
    local ucode="$1"
    log::info "Running pacstrap (this takes a few minutes)"
    pacstrap -K /mnt "${PACSTRAP_PKGS[@]}" "$ucode"
}

write_fstab_and_swap() {
    log::info "Generating /etc/fstab"
    genfstab -U /mnt >> /mnt/etc/fstab

    log::info "Creating $SWAP_SIZE swapfile at /mnt/swapfile"
    mkswap -U clear --size "$SWAP_SIZE" --file /mnt/swapfile > /dev/null
    printf '/swapfile none swap defaults 0 0\n' >> /mnt/etc/fstab
}

configure_chroot() {
    local hostname="$1" ucode="$2" root_partuuid="$3"

    log::info "Configuring timezone ($TIMEZONE)"
    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    log::info "Configuring locale ($LOCALE + ${EXTRA_LOCALES[*]})"
    local loc
    sed -i "s/^#\\($LOCALE\\)/\\1/" /mnt/etc/locale.gen
    for loc in "${EXTRA_LOCALES[@]}"; do
        sed -i "s/^#\\($loc\\)/\\1/" /mnt/etc/locale.gen
    done
    arch-chroot /mnt locale-gen
    printf 'LANG=%s\n' "$LOCALE" > /mnt/etc/locale.conf
    printf 'KEYMAP=%s\n' "$KEYMAP" > /mnt/etc/vconsole.conf

    log::info "Setting hostname to $hostname"
    printf '%s\n' "$hostname" > /mnt/etc/hostname
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain $hostname
EOF

    log::info "Regenerating initramfs"
    arch-chroot /mnt mkinitcpio -P

    log::info "Installing systemd-boot to /boot"
    arch-chroot /mnt bootctl --esp-path=/boot install
    cat > /mnt/boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 3
console-mode max
editor no
EOF
    cat > /mnt/boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /$ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=$root_partuuid rw
EOF

    log::info "Enabling NetworkManager"
    arch-chroot /mnt systemctl enable NetworkManager > /dev/null
}

create_user() {
    log::info "Creating user $USERNAME (wheel, $USER_SHELL)"
    arch-chroot /mnt useradd -m -G wheel -s "$USER_SHELL" "$USERNAME"

    log::info "Set the password for $USERNAME"
    arch-chroot /mnt passwd "$USERNAME"

    log::info "Locking root account"
    arch-chroot /mnt passwd -l root > /dev/null

    log::info "Granting wheel password-prompted sudo"
    printf '%%wheel ALL=(ALL:ALL) ALL\n' > /mnt/etc/sudoers.d/10-wheel
    chmod 0440 /mnt/etc/sudoers.d/10-wheel
}

clone_repo() {
    local home="/home/$USERNAME"
    local dest="$home/$REPO_DEST_REL"
    local parent
    parent="$(dirname "$dest")"

    log::info "Cloning marc-os to $dest"
    arch-chroot /mnt sudo -u "$USERNAME" mkdir -p "$parent"
    arch-chroot /mnt sudo -u "$USERNAME" git clone --depth 1 "$REPO_URL" "$dest"
}

handoff() {
    log::success "Bootstrap complete."
    cat << EOF

Next steps:

    1. reboot
    2. log in on TTY as $USERNAME
    3. cd ~/$REPO_DEST_REL && ./install.sh

EOF
}

# ---------- main ----------

main() {
    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            *)
                log::error "unknown option: $1"
                usage >&2
                exit 2
                ;;
        esac
    done

    trap 'umount -R /mnt 2>/dev/null || true' EXIT

    # Re-attach stdin to the controlling tty so `read` works when bootstrap.sh
    # is reached via `curl … | bash` (the pipe leaves stdin at EOF).
    exec < /dev/tty

    preflight

    local hostname disk ucode disk_default ucode_default

    hostname="$(_prompt "Hostname" "arch")"
    [[ -n $hostname ]] || log::die "Hostname cannot be empty."

    disk_default="$(_detect_disk)"
    disk="$(_prompt "Target disk" "$disk_default")"
    [[ -b $disk ]] || log::die "$disk is not a block device."

    ucode_default="$(_detect_ucode)"
    ucode="$(_prompt "CPU microcode (intel-ucode or amd-ucode)" "$ucode_default")"
    [[ $ucode == "intel-ucode" || $ucode == "amd-ucode" ]] \
        || log::die "Microcode must be intel-ucode or amd-ucode."

    cat << EOF

Configuration:
  Hostname  : $hostname
  Disk      : $(_disk_info_line "$disk")
  Microcode : $ucode
  User      : $USERNAME
  Locale    : $LOCALE (+${EXTRA_LOCALES[*]})
  Timezone  : $TIMEZONE
  Keymap    : $KEYMAP
EOF

    _confirm_wipe "$disk"

    refresh_mirrors
    enable_parallel_downloads /etc/pacman.conf

    partition "$disk"
    format_and_mount "$disk"
    pacstrap_base "$ucode"
    write_fstab_and_swap

    enable_parallel_downloads /mnt/etc/pacman.conf

    local root_partuuid
    root_partuuid="$(blkid -s PARTUUID -o value "$(_partition_path "$disk" 2)")"

    configure_chroot "$hostname" "$ucode" "$root_partuuid"
    create_user
    clone_repo
    handoff
}

main "$@"
