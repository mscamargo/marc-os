# AGENTS.md — marc-os

Personal Arch Linux setup. Shell scripts that install the i3wm stack and
symlink dotfiles. No package manager, no tests, no CI.

## Repository structure

| Path | Purpose |
|------|---------|
| `install.sh` | Entry point. Sources `lib/common.sh`, runs `scripts/*.sh` in glob order. |
| `scripts/NN-*.sh` | Numbered setup steps. Must be `chmod +x` or `install.sh` skips them. |
| `lib/common.sh` | Shared helpers: `info`, `warn`, `die`, `pacman_install`, `link_dotfile`. |
| `config/` | Dotfiles. Linked into `$HOME` and `$HOME/.config/` by `scripts/07-dotfiles.sh`. |
| `config/bin/` | Custom executable scripts. Linked into `$HOME/.local/bin/`. |
| `vm-*.sh` | QEMU/quickemu helpers for testing in a VM. |

## Script order

| # | Script | Purpose |
|---|--------|---------|
| 00 | `00-check.sh`     | Pre-flight: Arch, non-root, pacman, git, internet. |
| 01 | `01-base.sh`      | `pacman -Syu` and base xorg packages. |
| 02 | `02-aur-helper.sh`| Bootstrap `yay`. |
| 03 | `03-packages.sh`  | Core CLI/audio/fonts: zsh + plugins, neovim, pipewire, brightnessctl, fonts. |
| 04 | `04-wm.sh`        | i3 stack: i3-wm, i3status, i3lock, xss-lock, dunst, picom, rofi, polkit-gnome, autorandr, arandr. |
| 05 | `05-apps.sh`      | Apps: alacritty, browsers (qutebrowser/firefox/chromium + google-chrome via yay), yazi/lf/ranger, maim/slop/xclip/xdotool, clipmenu, playerctl, xdg utils. |
| 06 | `06-system.sh`    | NetworkManager + bluez, enabled via `systemctl`. |
| 07 | `07-dotfiles.sh`  | Symlink `config/` into `$HOME` and `$HOME/.config/`. |
| 08 | `08-shell.sh`     | `chsh -s zsh`. |

## Critical workflow details

### Install script behavior
- Runs only on Arch Linux, as a regular user (not root). Uses `sudo` internally.
- Scripts run in glob order (`00-check.sh` → `01-base.sh` …). Numbering matters.
- Any non-executable `.sh` in `scripts/` is skipped with a warning.
- `install.sh` sets `set -euo pipefail`; individual scripts do too.

### Dotfile linking
- `link_dotfile` in `lib/common.sh` symlinks with `ln -sfn`.
- If a real file (not symlink) already exists at the destination, it is backed up to `$dest.backup.<timestamp>`.

### i3 launch flow
- TTY login → `startx` → `~/.xinitrc` (`exec i3`).
- i3 spawns daemons (`picom`, `dunst`, `clipmenud`, `polkit-gnome` agent, `xss-lock -- i3lock`) via `exec`, and re-applies `xsetroot` and `xset s 300` via `exec_always`.

## VM testing

`vm-start.sh`, `vm-shutdown.sh`, `vm-restore.sh` use `quickemu` with a hard-coded VM path (`~/vms/archlinux/archlinux-latest.conf`).

`vm-sync.sh` copies the repo into the VM via `scp -P 22220`.

## Commit style

Plain imperative, e.g. `Add screenshot wrappers`, `Restructure scripts for i3 stack`.

## What this repo does NOT have

- No test suite, linter, or typechecker.
- No CI/CD.
- No dependency lockfile (relies on Arch repos and AUR).
