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

    ./install.sh                       # everything, in order
    ./install.sh --only configure      # only re-link dotfiles + set shell
    ./install.sh --skip check          # skip the pre-flight check
    ./install.sh -h                    # usage

Stages (run in this order): `check`, `bootstrap`, `install`, `configure`.
`--only` and `--skip` take a comma-separated list of stage names. They can be
combined; `--skip` wins on conflicts. No dependency validation — if you
`--only configure` on a bare system, you'll see the underlying errors.

After installation, restart your shell or run `exec zsh -l`. Log in on a
TTY and run `startx` to launch i3.

## Adding a package

Edit `packages.csv`. Five columns, comma-separated, with a header row:

    tag,name,description,pre-install-script,post-install-script

| Tag | Source | `name` |
|-----|--------|--------|
| (blank) | pacman | package name |
| `A` | AUR (yay) | package name |
| `G` | `git clone` to `~/.local/src/<repo>` | clone URL |

Hook columns hold paths to scripts under `hooks/` (relative to repo root),
or are empty. Fields must not contain commas. The runner skips the header
row and blank lines.

## Structure

- `install.sh` — entry point. All stage logic lives here as functions.
- `functions.sh` — shared helpers (`info`, `die`, `pacman_install`,
  `link_dotfile`, `run_hook`, …) sourced by `install.sh` and each hook.
- `packages.csv` — package manifest.
- `hooks/` — per-package install hooks referenced from `packages.csv`.
- `config/` — dotfiles.
- `vm-*.sh` — helper scripts for QEMU VM workflows.

## License

MIT
