# marc-os

Personal Arch Linux setup. Installs a minimal i3wm environment.

## What it does

- Updates the system and installs base xorg packages
- Bootstraps `yay` AUR helper
- Installs core CLI/audio/font packages (zsh, neovim, pipewire, etc.)
- Installs the i3 window manager stack (i3, i3status, i3lock, xss-lock,
  dunst, picom, rofi, polkit-gnome, autorandr, arandr)
- Installs apps (alacritty, qutebrowser/firefox/chromium/google-chrome,
  yazi/lf/ranger, maim+slop+xclip+xdotool, clipmenu, playerctl, xdg utils)
- Installs and enables NetworkManager and bluez
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

## Structure

- `install.sh` — entry point
- `scripts/` — numbered setup steps run in order
- `lib/common.sh` — shared helpers
- `config/` — dotfiles
- `vm-*.sh` — helper scripts for QEMU VM workflows

## License

MIT
