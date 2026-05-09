# marc-os

Personal Arch Linux setup. Installs a minimal environment with suckless tools.

## What it does

- Updates the system and installs base packages
- Bootstraps `yay` AUR helper
- Installs main packages (zsh, neovim, fonts, audio, etc.)
- Clones and builds [dwm](https://dwm.suckless.org), [dmenu](https://tools.suckless.org/dmenu/), and [st](https://st.suckless.org/) from source
- Links dotfiles for zsh, nvim, and X11
- Sets zsh as the default shell

## Requirements

- Arch Linux
- Internet connection
- Run as a regular user (not root)

## Usage

    ./install.sh

After installation, restart your shell or run `exec zsh -l`.

## Structure

- `install.sh` — entry point
- `scripts/` — setup steps run in order
- `lib/common.sh` — shared helpers
- `config/` — dotfiles
- `vm-*.sh` — helper scripts for QEMU VM workflows

## License

MIT
