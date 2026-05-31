# marc-os

Personal Arch Linux setup. Installs a minimal i3wm environment.

## What it does

- Updates the system and bootstraps `yay` AUR helper
- Installs every package listed in `packages.csv` (Xorg, audio, fonts, zsh,
  neovim, i3 stack, apps, browsers, NetworkManager, bluez, …) and runs the
  per-row hooks (e.g. enabling `NetworkManager.service` and `bluetooth.service`)
- Links dotfiles into `$HOME`
- Sets zsh as the default shell

## Requirements

- Arch Linux
- Internet connection
- Run as a regular user (not root)

## Usage

    ./install.sh

After installation, restart your shell or run `exec zsh -l`. Log in on a
TTY and run `startx` to launch i3.

## Adding a package

Edit `packages.csv`. Five columns, comma-separated, no header:

    tag,name,description,pre-install-script,post-install-script

| Tag | Source | `name` |
|-----|--------|--------|
| (blank) | pacman | package name |
| `A` | AUR (yay) | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

Hook columns hold paths to scripts under `hooks/` (relative to repo root),
or are empty. Fields must not contain commas. Lines starting with `#` are
comments.

## Structure

- `install.sh` — entry point
- `scripts/` — numbered setup steps run in order
- `lib/common.sh` — shared helpers
- `packages.csv` — package manifest
- `hooks/` — per-package install hooks referenced from `packages.csv`
- `config/` — dotfiles
- `vm-*.sh` — helper scripts for QEMU VM workflows

## License

MIT
